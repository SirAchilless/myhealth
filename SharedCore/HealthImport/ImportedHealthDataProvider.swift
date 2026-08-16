import Foundation

/// Serves health data from an imported Apple Health export through the same
/// `HealthDataProviding` port HealthKit uses — so the entire existing
/// pipeline (repository → engines → views) works unchanged with static data.
final class ImportedHealthDataProvider: HealthDataProviding {
    private let export: ParsedHealthExport?

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init(export: ParsedHealthExport?) {
        self.export = export
    }

    // MARK: Authorization (no HealthKit involved)

    func requestAuthorization() async throws -> Bool { true }

    func authorizationStatus() -> HealthAuthorizationStatus { .granted }

    // MARK: Heart

    func heartRateSamples(from startDate: Date, to endDate: Date) async throws -> [HeartRateSample] {
        guard let export else { return [] }
        return export.recentHeartRate.filter { $0.date >= startDate && $0.date <= endDate }
    }

    func restingHeartRateSamples(days: Int) async throws -> [HeartRateSample] {
        guard let export else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        return export.restingHeartRateByDay
            .suffix(days)
            .compactMap { scalar -> HeartRateSample? in
                guard let date = Self.dayFormatter.date(from: scalar.day), date >= cutoff else {
                    return nil
                }
                return HeartRateSample(beatsPerMinute: scalar.value, date: date)
            }
            .sorted { $0.date < $1.date }
    }

    func hrvSamples(days: Int) async throws -> [HRVSample] {
        guard let export else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        return export.hrvSamples.filter { $0.date >= cutoff }
    }

    // MARK: Sleep

    func sleepSamples(nights: Int) async throws -> [SleepSample] {
        guard let export else { return [] }
        let calendar = Calendar.current
        let todayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        let cutoff = calendar.date(byAdding: .day, value: -nights, to: todayNoon) ?? todayNoon
        return export.sleepSamples.filter { $0.end >= cutoff }
    }

    // MARK: Activity

    func stepCount(on day: Date) async throws -> Int {
        guard let export else { return 0 }
        let key = Day.dayIdentifier(day)
        let scalar = export.dailySteps.first { $0.day == key }
        return Int((scalar?.value ?? 0).rounded())
    }

    func activeEnergyKilocalories(on day: Date) async throws -> Double {
        guard let export else { return 0 }
        let key = Day.dayIdentifier(day)
        return export.dailyActiveEnergy.first { $0.day == key }?.value ?? 0
    }

    // MARK: Fitness

    func latestVO2Max() async throws -> Double? {
        export?.latestVO2Max
    }

    func latestWalkingHeartRateAverage() async throws -> Double? {
        export?.latestWalkingHeartRateAverage
    }

    func dateOfBirth() -> Date? {
        export?.dateOfBirth
    }

    // MARK: Workouts

    func workouts(days: Int) async throws -> [RawWorkout] {
        guard let export else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        return export.workouts.filter { $0.start >= cutoff }
    }

    // MARK: Observation

    func startObserving(changeHandler: @escaping @Sendable () -> Void) {
        // Static data — no observation needed.
    }
}
