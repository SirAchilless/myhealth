import Foundation

/// One day-keyed scalar (e.g. steps for 2026-08-16).
struct DailyScalar: Codable, Equatable {
    let day: String
    let value: Double
}

/// High-level result of an import, shown in the Import screen.
struct ImportSummary: Codable, Equatable {
    var importDate: Date = Date()
    var exportDate: Date?
    var recordCount: Int = 0
    var hrvSampleCount: Int = 0
    var restingHeartRateDayCount: Int = 0
    var sleepIntervalCount: Int = 0
    var sleepNightCount: Int = 0
    var workoutCount: Int = 0
    var dateOfBirthFound: Bool = false
}

/// The bounded set of aggregates extracted from an Apple Health export.
/// Raw samples are NOT retained wholesale — only what the insight engines
/// need (see docs/HEALTH_DATA.md §Import).
///
/// Retention bounds (computed from the export's most recent data):
/// - recent heart rate: last ~36 h of samples (stress windows)
/// - HRV: last 60 days
/// - resting HR: one value per day, last 60 days
/// - sleep intervals: last 21 nights
/// - workouts: last 35 days
/// - steps / active energy: daily sums
struct ParsedHealthExport: Codable, Equatable {
    var version: Int = 1
    var importedAt: Date = Date()
    var exportDate: Date?
    var dateOfBirth: Date?

    var recentHeartRate: [HeartRateSample] = []
    var restingHeartRateByDay: [DailyScalar] = []
    var hrvSamples: [HRVSample] = []
    var sleepSamples: [SleepSample] = []
    var dailySteps: [DailyScalar] = []
    var dailyActiveEnergy: [DailyScalar] = []
    var latestVO2Max: Double?
    var latestWalkingHeartRateAverage: Double?
    var workouts: [RawWorkout] = []

    var summary: ImportSummary = ImportSummary()

    var isUsable: Bool {
        !hrvSamples.isEmpty
            || !restingHeartRateByDay.isEmpty
            || !sleepSamples.isEmpty
            || !workouts.isEmpty
    }
}
