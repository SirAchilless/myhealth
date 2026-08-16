import Foundation
import Combine
import HealthKit
import WatchKit

/// Runs a live workout with `HKWorkoutSession` + `HKLiveWorkoutBuilder`,
/// publishes live metrics, and saves the workout to HealthKit on completion.
///
/// All HealthKit delegate callbacks arrive on background queues; they hop to
/// the main actor before touching published state.
@MainActor
final class WorkoutSessionController: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case running
        case paused
        case ended
        case failed(String)
    }

    let kind: WorkoutKind

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var currentHeartRate: Int?
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var distanceKilometers: Double = 0
    @Published private(set) var averageHeartRate: Int?
    /// Populated after a successful save; drives the summary screen.
    @Published private(set) var completedSummary: WorkoutSummary?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var ticker: Timer?
    private let hapticsEnabled: () -> Bool
    private let maxHeartRate: () -> Double
    private let restingHeartRate: () -> Double?
    private let onSave: (WorkoutSummary) -> Void

    private static let bpmUnit = HKUnit.count().unitDivided(by: .minuteUnit())
    private static let kilocalorieUnit = HKUnit.kilocalorie()
    private static let kilometerUnit = HKUnit.meterUnit(with: .kilo)

    init(
        kind: WorkoutKind,
        hapticsEnabled: @escaping () -> Bool,
        maxHeartRate: @escaping () -> Double,
        restingHeartRate: @escaping () -> Double?,
        onSave: @escaping (WorkoutSummary) -> Void
    ) {
        self.kind = kind
        self.hapticsEnabled = hapticsEnabled
        self.maxHeartRate = maxHeartRate
        self.restingHeartRate = restingHeartRate
        self.onSave = onSave
        super.init()
    }

    // MARK: Control

    func start() {
        guard phase == .idle else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType(for: kind)
        configuration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.workoutBuilder
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            builder.metadata = [HealthKitManager.MetadataKeys.recordedByMyHealth: true]
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            builder.beginCollection(at: Date()) { [weak self] success, error in
                guard success else {
                    Task { @MainActor in
                        self?.phase = .failed(error?.localizedDescription ?? "Could not start workout.")
                    }
                    return
                }
                Task { @MainActor in
                    self?.session?.activate()
                }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func pause() {
        guard phase == .running else { return }
        session?.pause()
    }

    func resume() {
        guard phase == .paused else { return }
        session?.resume()
    }

    /// Ends the session; the summary appears after `finishWorkout` completes.
    func end() {
        guard phase == .running || phase == .paused else { return }
        session?.end()
    }

    // MARK: State machine

    private func handleStateChange(
        to toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        switch toState {
        case .running:
            if fromState == .notStarted {
                phase = .running
                Haptics.start(enabled: hapticsEnabled())
                startTicker()
            } else {
                phase = .running
                Haptics.click(enabled: hapticsEnabled())
            }
        case .paused:
            phase = .paused
            Haptics.click(enabled: hapticsEnabled())
        case .ended:
            phase = .ended
            stopTicker()
            Haptics.stop(enabled: hapticsEnabled())
            finishAndSave(endDate: date)
        default:
            break
        }
    }

    private func finishAndSave(endDate: Date) {
        guard let builder else {
            phase = .failed("Workout builder unavailable.")
            return
        }
        builder.endCollection(at: endDate) { [weak self] success, _ in
            guard let self else { return }
            guard success else {
                Task { @MainActor in self.phase = .failed("Could not finish workout.") }
                return
            }
            builder.finishWorkout { [weak self] workout, _ in
                guard let self else { return }
                Task { @MainActor in self.buildSummary(from: builder, workout: workout, end: endDate) }
            }
        }
    }

    private func buildSummary(from builder: HKLiveWorkoutBuilder, workout: HKWorkout?, end: Date) {
        var averageHR: Double?
        var calories: Double?
        var distance: Double?

        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let statistics = builder.statistics(for: hrType) {
            if let average = statistics.averageQuantity() {
                averageHR = average.doubleValue(for: Self.bpmUnit)
            }
        }
        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let statistics = builder.statistics(for: energyType),
           let sum = statistics.sumQuantity() {
            calories = sum.doubleValue(for: Self.kilocalorieUnit)
        }
        let distanceType = HKQuantityType.quantityType(
            forIdentifier: kind == .cycling ? .distanceCycling : .distanceWalkingRunning
        )
        if let distanceType,
           let statistics = builder.statistics(for: distanceType),
           let sum = statistics.sumQuantity() {
            distance = sum.doubleValue(for: Self.kilometerUnit)
        }

        let summary = LoadEngine.workoutSummary(
            kind: kind,
            start: builder.startDate ?? Date().addingTimeInterval(-elapsedSeconds),
            end: end,
            averageHeartRate: averageHR,
            activeCalories: calories,
            distanceKilometers: distance,
            restingHeartRate: restingHeartRate(),
            maxHeartRate: maxHeartRate(),
            recordedByMyHealth: true,
            id: workout?.uuid ?? UUID()
        )
        averageHeartRate = averageHR.map { Int($0.rounded()) }
        activeCalories = calories ?? activeCalories
        distanceKilometers = distance ?? distanceKilometers
        completedSummary = summary
        onSave(summary)
    }

    // MARK: Live metrics

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateLiveMetrics()
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func updateLiveMetrics() {
        guard let builder else { return }
        elapsedSeconds = builder.elapsedTime

        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let statistics = builder.statistics(for: hrType),
           let latest = statistics.mostRecentQuantity() {
            currentHeartRate = Int(latest.doubleValue(for: Self.bpmUnit).rounded())
        }
        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let statistics = builder.statistics(for: energyType),
           let sum = statistics.sumQuantity() {
            activeCalories = sum.doubleValue(for: Self.kilocalorieUnit)
        }
        let distanceType = HKQuantityType.quantityType(
            forIdentifier: kind == .cycling ? .distanceCycling : .distanceWalkingRunning
        )
        if let distanceType,
           let statistics = builder.statistics(for: distanceType),
           let sum = statistics.sumQuantity() {
            distanceKilometers = sum.doubleValue(for: Self.kilometerUnit)
        }
    }

    /// 1–5 heart-rate zone for the current HR (reserve-based).
    var currentZone: Int? {
        guard let hr = currentHeartRate else { return nil }
        let max = maxHeartRate()
        let resting = restingHeartRate() ?? 60
        guard max > resting else { return nil }
        let reserve = min(max((Double(hr) - resting) / (max - resting), 0), 1)
        return min(max(Int(reserve * 5) + 1, 1), 5)
    }

    // MARK: Mapping

    private static func activityType(for kind: WorkoutKind) -> HKWorkoutActivityType {
        switch kind {
        case .running: return .running
        case .walking: return .walking
        case .cycling: return .cycling
        case .strengthTraining: return .traditionalStrengthTraining
        case .other: return .other
        }
    }
}

// MARK: - HealthKit delegates (background queue → main actor hops)

extension WorkoutSessionController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            self.handleStateChange(to: toState, from: fromState, date: date)
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.phase = .failed(error.localizedDescription)
        }
    }
}

extension WorkoutSessionController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Events (laps etc.) are not used in v1.
    }

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            self.updateLiveMetrics()
        }
    }
}
