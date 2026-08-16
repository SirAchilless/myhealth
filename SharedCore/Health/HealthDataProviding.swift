import Foundation

/// Authorization state as myhealth can observe it. HealthKit does not expose
/// read authorization per type; "granted" here means the user completed the
/// prompt (queries decide what is actually available — see docs/HEALTH_DATA.md).
enum HealthAuthorizationStatus: Equatable {
    case healthKitUnavailable
    case notDetermined
    case denied
    case granted
}

/// A workout as read from a health source, before load points are attached.
struct RawWorkout: Equatable, Codable {
    let kind: WorkoutKind
    let start: Date
    let end: Date
    let averageHeartRate: Double?
    let activeCalories: Double?
    let distanceKilometers: Double?
    /// True when myhealth itself recorded the workout.
    let recordedByMyHealth: Bool
}

/// Abstraction over health data sources. `HealthKitManager` is the production
/// implementation; `MockHealthDataProvider` backs development scenarios and
/// tests. View models and engines never touch HealthKit directly.
protocol HealthDataProviding: AnyObject {
    func requestAuthorization() async throws -> Bool
    func authorizationStatus() -> HealthAuthorizationStatus

    // Heart
    func heartRateSamples(from: Date, to: Date) async throws -> [HeartRateSample]
    func restingHeartRateSamples(days: Int) async throws -> [HeartRateSample]
    func hrvSamples(days: Int) async throws -> [HRVSample]

    // Sleep
    func sleepSamples(nights: Int) async throws -> [SleepSample]

    // Activity
    func stepCount(on day: Date) async throws -> Int
    func activeEnergyKilocalories(on day: Date) async throws -> Double

    // Fitness
    func latestVO2Max() async throws -> Double?
    func latestWalkingHeartRateAverage() async throws -> Double?
    func dateOfBirth() -> Date?

    // Workouts
    func workouts(days: Int) async throws -> [RawWorkout]

    // Change observation (best-effort while the app is running)
    func startObserving(changeHandler: @escaping @Sendable () -> Void)
}
