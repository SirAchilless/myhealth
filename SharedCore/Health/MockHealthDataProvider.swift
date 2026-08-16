import Foundation

#if DEBUG
/// Development-only health data source. Never shipped values: the repository
/// only uses this provider when the DEBUG "mock scenario" developer toggle is
/// explicitly selected in Settings → Developer.
///
/// Data is deterministic (seeded generator) so screens and tests are stable.
enum MockScenario: String, CaseIterable, Identifiable {
    case excellent
    case poorRecovery
    case insufficientData
    case permissionDenied
    case partialData

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .poorRecovery: return "Poor Recovery"
        case .insufficientData: return "Insufficient Data"
        case .permissionDenied: return "Permission Denied"
        case .partialData: return "Partial Data"
        }
    }
}

final class MockHealthDataProvider: HealthDataProviding {
    let scenario: MockScenario
    private let generator: SeededGenerator

    init(scenario: MockScenario, seed: UInt64 = 42) {
        self.scenario = scenario
        self.generator = SeededGenerator(seed: seed)
    }

    // MARK: HealthDataProviding

    func requestAuthorization() async throws -> Bool {
        scenario != .permissionDenied
    }

    func authorizationStatus() -> HealthAuthorizationStatus {
        scenario == .permissionDenied ? .denied : .granted
    }

    func heartRateSamples(from startDate: Date, to endDate: Date) async throws -> [HeartRateSample] {
        try checkDenied()
        guard providesHeartData else { return [] }
        var samples: [HeartRateSample] = []
        var time = startDate
        let resting = restingHeartRateBase
        while time < endDate {
            let hour = Calendar.current.component(.hour, from: time)
            // Higher during the day, lower at night.
            let circadian = hour >= 7 && hour <= 22 ? Double.random(in: 10...35, using: &generator)
                                                    : Double.random(in: -4...6, using: &generator)
            samples.append(HeartRateSample(
                beatsPerMinute: resting + circadian,
                date: time
            ))
            time = time.addingTimeInterval(10 * 60)
        }
        return samples
    }

    func restingHeartRateSamples(days: Int) async throws -> [HeartRateSample] {
        try checkDenied()
        guard providesHeartData else { return [] }
        let count = scenario == .insufficientData ? 2 : days
        return (0..<count).map { day in
            HeartRateSample(
                beatsPerMinute: restingHeartRateBase + Double.random(in: -2...2, using: &generator),
                date: daysAgo(day)
            )
        }
    }

    func hrvSamples(days: Int) async throws -> [HRVSample] {
        try checkDenied()
        guard providesHeartData else { return [] }
        let count = scenario == .insufficientData ? 2 : days
        return (0..<count).map { day in
            HRVSample(
                milliseconds: hrvBase + Double.random(in: -4...4, using: &generator),
                date: daysAgo(day).addingTimeInterval(7 * 3600)
            )
        }
    }

    func sleepSamples(nights: Int) async throws -> [SleepSample] {
        try checkDenied()
        guard providesSleepData else { return [] }
        let count = scenario == .insufficientData ? 1 : nights
        var all: [SleepSample] = []
        for night in 0..<count {
            all.append(contentsOf: mockNight(daysAgo: night + 1))
        }
        return all
    }

    func stepCount(on day: Date) async throws -> Int {
        try checkDenied()
        scenario == .insufficientData ? 1200 : 8200
    }

    func activeEnergyKilocalories(on day: Date) async throws -> Double {
        try checkDenied()
        scenario == .insufficientData ? 180 : 640
    }

    func latestVO2Max() async throws -> Double? {
        try checkDenied()
        providesHeartData ? 42.5 : nil
    }

    func latestWalkingHeartRateAverage() async throws -> Double? {
        try checkDenied()
        providesHeartData ? restingHeartRateBase + 12 : nil
    }

    func dateOfBirth() -> Date? {
        Calendar.current.date(byAdding: .year, value: -34, to: Date())
    }

    func workouts(days: Int) async throws -> [RawWorkout] {
        try checkDenied()
        guard providesWorkoutData else { return [] }
        let count = scenario == .insufficientData ? 0 : min(days, 21)
        var workouts: [RawWorkout] = []
        for offset in stride(from: 1, through: count, by: 2) {
            let start = daysAgo(offset).addingTimeInterval(18 * 3600)
            let hard = scenario == .poorRecovery
            let duration = hard ? 75.0 : 45.0
            workouts.append(RawWorkout(
                kind: .running,
                start: start,
                end: start.addingTimeInterval(duration * 60),
                averageHeartRate: hard ? 152 : 138,
                activeCalories: hard ? 720 : 420,
                distanceKilometers: hard ? 12.5 : 7.2,
                recordedByMyHealth: false
            ))
        }
        return workouts
    }

    func startObserving(changeHandler: @escaping @Sendable () -> Void) {
        // Mock data is static; no observation needed.
    }

    // MARK: - Scenario characteristics

    private var providesHeartData: Bool {
        scenario != .partialData
    }
    /// "Partial Data" keeps sleep and workouts but drops HR (HRV/RHR).
    private var providesSleepData: Bool { true }
    private var providesWorkoutData: Bool {
        true
    }

    private var hrvBase: Double {
        switch scenario {
        case .excellent: return 58
        case .poorRecovery: return 31
        default: return 45
        }
    }

    private var restingHeartRateBase: Double {
        switch scenario {
        case .excellent: return 51
        case .poorRecovery: return 63
        default: return 55
        }
    }

    private func checkDenied() throws {
        if scenario == .permissionDenied {
            throw MyHealthError.healthAuthorizationDenied
        }
    }

    private func daysAgo(_ days: Int) -> Date {
        let day = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -days, to: day) ?? day
    }

    /// Builds a realistic night: in-bed span with core/deep/REM/awake stages.
    private func mockNight(daysAgo: Int) -> [SleepSample] {
        let targetAsleep: Double
        switch scenario {
        case .excellent: targetAsleep = 462 // 7h 42m
        case .poorRecovery: targetAsleep = 330 // 5h 30m
        default: targetAsleep = 430
        }
        let bedtime = daysAgo(daysAgo).addingTimeInterval(23 * 3600 - 30 * 60) // 22:30
        var cursor = bedtime.addingTimeInterval(15 * 60)
        let wake = cursor.addingTimeInterval(targetAsleep * 60)
        var samples: [SleepSample] = [
            SleepSample(stage: .inBed, start: bedtime, end: wake.addingTimeInterval(20 * 60)),
        ]
        var remaining = targetAsleep
        let cycle = [SleepStageKind.core, .deep, .core, .rem, .awake]
        var index = 0
        while remaining > 0 {
            let stage = cycle[index % cycle.count]
            let length = min(stage == .awake ? 12 : 55, remaining)
            samples.append(SleepSample(
                stage: stage,
                start: cursor,
                end: cursor.addingTimeInterval(length * 60)
            ))
            cursor = cursor.addingTimeInterval(length * 60)
            remaining -= length
            index += 1
        }
        return samples
    }
}

/// Tiny deterministic PRNG (linear congruential) so mock data is stable.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
#endif
