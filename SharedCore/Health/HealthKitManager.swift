import Foundation
import HealthKit

/// Production health source backed by HealthKit. All queries are one-shot and
/// wrapped in Swift concurrency; long-running observation uses observer
/// queries that simply notify the repository while the app is running.
/// Battery rule: no polling loops — everything here is event- or demand-driven.
final class HealthKitManager: HealthDataProviding {
    private let store = HKHealthStore()
    private var observersInstalled = false

    private var heartRateType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .heartRate)
    }
    private var restingHeartRateType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .restingHeartRate)
    }
    private var hrvType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
    }
    private var sleepType: HKCategoryType? {
        HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
    }
    private var workoutType: HKObjectType { HKObjectType.workoutType() }

    private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minuteUnit())
    private static let milliseconds = HKUnit.secondUnit(with: .milli)
    private static let kilocalories = HKUnit.kilocalorie()
    private static let kilometers = HKUnit.meterUnit(with: .kilo)

    // MARK: Authorization

    func requestAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw MyHealthError.healthKitUnavailable
        }

        var readTypes = Set<HKObjectType>()
        for identifier: HKQuantityTypeIdentifier in [
            .heartRate, .restingHeartRate, .heartRateVariabilitySDNN,
            .activeEnergyBurned, .stepCount, .vo2Max, .walkingHeartRateAverage,
        ] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                readTypes.insert(type)
            }
        }
        if let sleepType {
            readTypes.insert(sleepType)
        }
        readTypes.insert(workoutType)

        // The only writes are workouts myhealth records itself.
        try await store.requestAuthorization(toShare: [workoutType], read: readTypes)
        return true
    }

    func authorizationStatus() -> HealthAuthorizationStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .healthKitUnavailable }
        // Read permission cannot be queried per type; workouts are our write
        // type, so use its status as the strongest available signal.
        switch store.authorizationStatus(for: workoutType) {
        case .sharingAuthorized: return .granted
        case .sharingDenied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    // MARK: Heart

    func heartRateSamples(from startDate: Date, to endDate: Date) async throws -> [HeartRateSample] {
        guard let type = heartRateType else { return [] }
        let samples = try await sampleQuery(
            type: type,
            predicate: HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: .strictStartDate
            ),
            unit: Self.beatsPerMinute
        )
        return samples.map { HeartRateSample(beatsPerMinute: $0.value, date: $0.date) }
    }

    func restingHeartRateSamples(days: Int) async throws -> [HeartRateSample] {
        guard let type = restingHeartRateType else { return [] }
        let start = daysAgo(days)
        let samples = try await sampleQuery(
            type: type,
            predicate: HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate),
            unit: Self.beatsPerMinute
        )
        return samples.map { HeartRateSample(beatsPerMinute: $0.value, date: $0.date) }
    }

    func hrvSamples(days: Int) async throws -> [HRVSample] {
        guard let type = hrvType else { return [] }
        let start = daysAgo(days)
        let samples = try await sampleQuery(
            type: type,
            predicate: HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate),
            unit: Self.milliseconds
        )
        return samples.map { HRVSample(milliseconds: $0.value, date: $0.date) }
    }

    // MARK: Sleep

    func sleepSamples(nights: Int) async throws -> [SleepSample] {
        guard let type = sleepType else { return [] }
        // Start at noon `nights` days ago so evening samples of the oldest
        // night are included.
        let calendar = Calendar.current
        let todayNoon = calendar.date(
            bySettingHour: 12, minute: 0, second: 0, of: Date()
        ) ?? Date()
        let start = calendar.date(byAdding: .day, value: -nights, to: todayNoon) ?? todayNoon

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: start, end: Date(), options: []),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let samples = (results as? [HKCategorySample]) ?? []
                continuation.resume(returning: samples.compactMap(Self.sleepSample(from:)))
            }
            store.execute(query)
        }
    }

    private static func sleepSample(from sample: HKCategorySample) -> SleepSample? {
        let stage: SleepStageKind
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .inBed: stage = .inBed
        case .awake: stage = .awake
        case .asleepREM: stage = .rem
        case .asleepCore: stage = .core
        case .asleepDeep: stage = .deep
        case .asleep, .asleepUnspecified: stage = .unspecifiedAsleep
        default:
            // .outOfBed and future values are not used in analysis.
            return nil
        }
        return SleepSample(stage: stage, start: sample.startDate, end: sample.endDate)
    }

    // MARK: Activity

    func stepCount(on day: Date) async throws -> Int {
        let quantity = try await cumulativeSum(
            identifier: .stepCount,
            unit: HKUnit.count(),
            on: day
        )
        return Int(quantity.rounded())
    }

    func activeEnergyKilocalories(on day: Date) async throws -> Double {
        try await cumulativeSum(
            identifier: .activeEnergyBurned,
            unit: Self.kilocalories,
            on: day
        )
    }

    // MARK: Fitness

    func latestVO2Max() async throws -> Double? {
        // VO2 max is expressed in ml/kg/min.
        let unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo))
            .unitDivided(by: HKUnit.minuteUnit())
        let samples = try await latestSamples(identifier: .vo2Max, unit: unit, limit: 1)
        return samples.first?.value
    }

    func latestWalkingHeartRateAverage() async throws -> Double? {
        let samples = try await latestSamples(identifier: .walkingHeartRateAverage, unit: Self.beatsPerMinute, limit: 1)
        return samples.first?.value
    }

    func dateOfBirth() -> Date? {
        let components = store.dateOfBirthComponents()
        return components.date
    }

    // MARK: Workouts

    func workouts(days: Int) async throws -> [RawWorkout] {
        let start = daysAgo(days)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { [weak self] _, results, error in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (results as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts.map(self.rawWorkout(from:)))
            }
            store.execute(query)
        }
    }

    private func rawWorkout(from workout: HKWorkout) -> RawWorkout {
        let kind: WorkoutKind
        switch workout.workoutActivityType {
        case .running: kind = .running
        case .walking: kind = .walking
        case .cycling: kind = .cycling
        case .traditionalStrengthTraining, .functionalStrengthTraining: kind = .strengthTraining
        default: kind = .other
        }

        var averageHeartRate: Double?
        if let type = heartRateType,
           let statistics = workout.statistics(for: type),
           let average = statistics.averageQuantity() {
            averageHeartRate = average.doubleValue(for: Self.beatsPerMinute)
        }

        let calories = workout.totalEnergyBurned?
            .doubleValue(for: Self.kilocalories)
        let distance = workout.totalDistance?
            .doubleValue(for: Self.kilometers)

        // Workouts recorded by this app carry the myhealth metadata key.
        let recordedByMyHealth = workout.metadata?[MetadataKeys.recordedByMyHealth] as? Bool ?? false

        return RawWorkout(
            kind: kind,
            start: workout.startDate,
            end: workout.endDate,
            averageHeartRate: averageHeartRate,
            activeCalories: calories,
            distanceKilometers: distance,
            recordedByMyHealth: recordedByMyHealth
        )
    }

    /// Metadata key stamped on workouts myhealth records (public so the
    /// workout controller can set it).
    enum MetadataKeys {
        static let recordedByMyHealth = "com.myhealth.recorded"
    }

    // MARK: Observation

    func startObserving(changeHandler: @escaping @Sendable () -> Void) {
        guard !observersInstalled else { return }
        observersInstalled = true

        // HKWorkoutType is an HKSampleType subclass, so all observed types
        // (sleep, HR, resting HR, HRV, workouts) share one observer shape.
        let observedTypes: [HKSampleType?] = [
            sleepType,
            heartRateType,
            restingHeartRateType,
            hrvType,
            HKObjectType.workoutType() as? HKSampleType,
        ]

        for type in observedTypes.compactMap({ $0 }) {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                completion()
                if error == nil {
                    changeHandler()
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Query helpers

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    private func sampleQuery(
        type: HKQuantityType,
        predicate: NSPredicate,
        unit: HKUnit
    ) async throws -> [(value: Double, date: Date)] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let samples = (results as? [HKQuantitySample]) ?? []
                continuation.resume(
                    returning: samples.map { ($0.quantity.doubleValue(for: unit), $0.endDate) }
                )
            }
            store.execute(query)
        }
    }

    private func latestSamples(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        limit: Int
    ) async throws -> [(value: Double, date: Date)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let samples = (results as? [HKQuantitySample]) ?? []
                continuation.resume(
                    returning: samples.map { ($0.quantity.doubleValue(for: unit), $0.endDate) }
                )
            }
            store.execute(query)
        }
    }

    private func cumulativeSum(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        on day: Date
    ) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? day

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: []),
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let sum = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: sum)
            }
            store.execute(query)
        }
    }
}
