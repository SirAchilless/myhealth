import Foundation

/// Sleep stages as HealthKit reports them (assembled into nights by
/// `SleepNightAssembler`).
enum SleepStageKind: String, CaseIterable, Codable {
    case inBed
    case awake
    case rem
    case core
    case deep
    case unspecifiedAsleep
}

/// A raw sleep-stage interval.
struct SleepSample: Equatable, Codable {
    let stage: SleepStageKind
    let start: Date
    let end: Date

    var minutes: Double { end.timeIntervalSince(start) / 60 }
}

/// Minutes spent in each stage across one night.
struct SleepStageBreakdown: Equatable, Codable {
    var remMinutes: Double = 0
    var coreMinutes: Double = 0
    var deepMinutes: Double = 0
    var awakeMinutes: Double = 0
    var inBedMinutes: Double = 0
    var unspecifiedMinutes: Double = 0

    var asleepMinutes: Double { remMinutes + coreMinutes + deepMinutes + unspecifiedMinutes }

    var totalMinutesInBed: Double { inBedMinutes }
}

/// One assembled sleep night (typically the sleep that *ended* on `date`).
struct SleepNight: Equatable, Codable {
    /// The morning the night ended (used as the day identifier).
    let date: Date
    let bedtime: Date?
    let wakeTime: Date?
    let breakdown: SleepStageBreakdown

    /// Sleep midpoint in minutes after local midnight, when bedtime and wake
    /// are both known. Used for schedule-consistency scoring.
    var midpointMinutesFromMidnight: Double? {
        guard let bedtime, let wakeTime else { return nil }
        let midpoint = bedtime.addingTimeInterval(wakeTime.timeIntervalSince(bedtime) / 2)
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: midpoint)
        return midpoint.timeIntervalSince(midnight) / 60
    }
}

enum SleepRating: String, CaseIterable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"

    init(score: Int) {
        switch score {
        case ..<ScoringConstants.Sleep.poorUpperBound:
            self = .poor
        case ..<ScoringConstants.Sleep.fairUpperBound:
            self = .fair
        case ..<ScoringConstants.Sleep.goodUpperBound:
            self = .good
        default:
            self = .excellent
        }
    }
}

/// One weighted component of the sleep score.
struct SleepScoreComponent: Identifiable, Equatable {
    var id: String { name }
    let name: String
    /// Relative weight in the final score (0–1 before normalization).
    let weight: Double
    /// Achieved fraction of this component (0–1).
    let achieved: Double
    let detail: String
}

/// Full output of `SleepAnalyzer`.
struct SleepAnalysisResult: Equatable {
    let night: SleepNight
    /// `nil` when there is not enough data to score honestly.
    let score: Int?
    let rating: SleepRating?
    let confidence: ConfidenceLevel
    let components: [SleepScoreComponent]
    /// Positive values mean the user slept less than their personal need.
    let deficitMinutes: Int?
    let explanation: String

    var hasScore: Bool { score != nil && confidence != .insufficientData }
}
