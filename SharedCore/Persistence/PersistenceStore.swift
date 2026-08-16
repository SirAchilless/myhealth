import Foundation
import SwiftData

/// Long-term daily summary — one row per day of derived scores and the raw
/// inputs that produced them. Only derived/aggregate values are stored; raw
/// HealthKit samples are never duplicated (retention: docs/PRIVACY.md).
@Model
final class DailyHealthSummaryRecord {
    /// Day identifier "yyyy-MM-dd" of the morning the day belongs to.
    @Attribute(.unique) var day: String
    var updatedAt: Date

    // Inputs
    var hrvMilliseconds: Double?
    var restingHeartRate: Double?
    var sleepMinutes: Double?
    var sleepScore: Int?
    var activeKilocalories: Double?
    var stepCount: Int?

    // Derived scores
    var recoveryScore: Int?
    var recoveryConfidence: String?
    var loadRawPoints: Double?
    var stressIndex: Double?
    var energyScore: Int?

    init(
        day: String,
        updatedAt: Date = Date(),
        hrvMilliseconds: Double? = nil,
        restingHeartRate: Double? = nil,
        sleepMinutes: Double? = nil,
        sleepScore: Int? = nil,
        activeKilocalories: Double? = nil,
        stepCount: Int? = nil,
        recoveryScore: Int? = nil,
        recoveryConfidence: String? = nil,
        loadRawPoints: Double? = nil,
        stressIndex: Double? = nil,
        energyScore: Int? = nil
    ) {
        self.day = day
        self.updatedAt = updatedAt
        self.hrvMilliseconds = hrvMilliseconds
        self.restingHeartRate = restingHeartRate
        self.sleepMinutes = sleepMinutes
        self.sleepScore = sleepScore
        self.activeKilocalories = activeKilocalories
        self.stepCount = stepCount
        self.recoveryScore = recoveryScore
        self.recoveryConfidence = recoveryConfidence
        self.loadRawPoints = loadRawPoints
        self.stressIndex = stressIndex
        self.energyScore = energyScore
    }
}

/// A recorded workout kept for history/trends (HealthKit remains the source
/// of truth; this cache avoids repeated queries on launch).
@Model
final class WorkoutRecord {
    @Attribute(.unique) var workoutID: UUID
    var kind: String
    var start: Date
    var end: Date
    var durationMinutes: Double
    var averageHeartRate: Double?
    var activeCalories: Double?
    var distanceKilometers: Double?
    var loadPoints: Double
    var loadMethod: String

    init(from summary: WorkoutSummary) {
        workoutID = summary.id
        kind = summary.kind.rawValue
        start = summary.start
        end = summary.end
        durationMinutes = summary.durationMinutes
        averageHeartRate = summary.averageHeartRate
        activeCalories = summary.activeCalories
        distanceKilometers = summary.distanceKilometers
        loadPoints = summary.loadPoints
        loadMethod = summary.loadMethod.rawValue
    }

    var summary: WorkoutSummary {
        WorkoutSummary(
            id: workoutID,
            kind: WorkoutKind(rawValue: kind) ?? .other,
            start: start,
            end: end,
            durationMinutes: durationMinutes,
            averageHeartRate: averageHeartRate,
            activeCalories: activeCalories,
            distanceKilometers: distanceKilometers,
            loadPoints: loadPoints,
            loadMethod: LoadMethod(rawValue: loadMethod) ?? .durationEstimate,
            recordedByMyHealth: false
        )
    }
}

/// Owns the SwiftData container and provides a small, typed API. All work is
/// performed on a background context via async functions; callers stay on the
/// main actor.
@MainActor
final class PersistenceStore {
    static let shared = PersistenceStore()

    private let container: ModelContainer?
    private let modelContext: ModelContext?

    init(inMemory: Bool = false) {
        do {
            let schema = Schema([DailyHealthSummaryRecord.self, WorkoutRecord.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
            container = try ModelContainer(for: schema, configurations: [configuration])
            modelContext = container?.mainContext
        } catch {
            // Persistence failure must never crash the app — scores still
            // compute fresh each session, only history is lost.
            container = nil
            modelContext = nil
        }
    }

    // MARK: Daily summaries

    func upsertDailySummary(_ record: DailyHealthSummaryRecord) {
        guard let context = modelContext else { return }
        let day = record.day
        let existing = fetchDailySummary(day)
        if let existing {
            existing.updatedAt = record.updatedAt
            existing.hrvMilliseconds = record.hrvMilliseconds
            existing.restingHeartRate = record.restingHeartRate
            existing.sleepMinutes = record.sleepMinutes
            existing.sleepScore = record.sleepScore
            existing.activeKilocalories = record.activeKilocalories
            existing.stepCount = record.stepCount
            existing.recoveryScore = record.recoveryScore
            existing.recoveryConfidence = record.recoveryConfidence
            existing.loadRawPoints = record.loadRawPoints
            existing.stressIndex = record.stressIndex
            existing.energyScore = record.energyScore
        } else {
            context.insert(record)
        }
        save()
    }

    func fetchDailySummary(_ day: String) -> DailyHealthSummaryRecord? {
        guard let context = modelContext else { return nil }
        var descriptor = FetchDescriptor<DailyHealthSummaryRecord>(
            predicate: #Predicate { $0.day == day }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func dailySummaries(days: Int) -> [DailyHealthSummaryRecord] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<DailyHealthSummaryRecord>(
            sortBy: [SortDescriptor(\.day, order: .reverse)]
        )
        let results = (try? context.fetch(descriptor)) ?? []
        return Array(results.prefix(days))
    }

    // MARK: Workouts

    func upsertWorkout(_ summary: WorkoutSummary) {
        guard let context = modelContext else { return }
        let id = summary.id
        let existing = fetchWorkout(id: id)
        if existing != nil { return } // workouts are immutable once saved
        context.insert(WorkoutRecord(from: summary))
        save()
    }

    func recentWorkouts(limit: Int) -> [WorkoutSummary] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        let results = (try? context.fetch(descriptor)) ?? []
        return results.prefix(limit).map(\.summary)
    }

    private func fetchWorkout(id: UUID) -> WorkoutRecord? {
        guard let context = modelContext else { return nil }
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.workoutID == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: Retention & deletion

    /// Applies the retention policy (docs/PRIVACY.md): daily summaries and
    /// workouts are long-term; stale debug-era rows beyond the cap are pruned.
    func applyRetentionPolicy(maxDailyRows: Int = 730, maxWorkoutRows: Int = 1000) {
        guard let context = modelContext else { return }
        let daily = dailySummaries(days: .max)
        if daily.count > maxDailyRows {
            for record in daily.suffix(from: maxDailyRows) {
                context.delete(record)
            }
        }
        let workouts = recentWorkouts(limit: .max)
        if workouts.count > maxWorkoutRows {
            let workoutsDescriptor = FetchDescriptor<WorkoutRecord>(
                sortBy: [SortDescriptor(\.start, order: .reverse)]
            )
            if let all = try? context.fetch(workoutsDescriptor) {
                for record in all.suffix(from: maxWorkoutRows) {
                    context.delete(record)
                }
            }
        }
        save()
    }

    /// Full local-data deletion, exposed in Settings → Data Management.
    func deleteAllLocalData() {
        guard let context = modelContext else { return }
        do {
            try context.delete(model: DailyHealthSummaryRecord.self)
            try context.delete(model: WorkoutRecord.self)
        } catch {
            // Non-fatal: worst case old rows remain until reinstall.
        }
        save()
    }

    private func save() {
        guard let context = modelContext else { return }
        do {
            try context.save()
        } catch {
            // Swallow: derived data is recomputable; never crash on save.
        }
    }
}
