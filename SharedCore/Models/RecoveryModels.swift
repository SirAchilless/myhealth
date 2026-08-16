import Foundation

/// myhealth Recovery Score categories (see docs/ALGORITHMS.md).
enum RecoveryCategory: String, CaseIterable {
    case veryLow = "Very Low"
    case low = "Low"
    case moderate = "Moderate"
    case good = "Good"
    case excellent = "Excellent"

    init(score: Int) {
        switch score {
        case ..<ScoringConstants.Recovery.veryLowUpperBound:
            self = .veryLow
        case ..<ScoringConstants.Recovery.lowUpperBound:
            self = .low
        case ..<ScoringConstants.Recovery.moderateUpperBound:
            self = .moderate
        case ..<ScoringConstants.Recovery.goodUpperBound:
            self = .good
        default:
            self = .excellent
        }
    }
}

/// Confidence attached to every generated score. "Insufficient Data" means no
/// score is produced at all.
enum ConfidenceLevel: String, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case insufficientData = "Insufficient Data"
}

/// The inputs a recovery factor was computed from.
enum RecoveryFactorMetric: String, CaseIterable, Identifiable {
    case heartRateVariability = "HRV"
    case restingHeartRate = "Resting HR"
    case sleepDuration = "Sleep Duration"
    case sleepTiming = "Sleep Timing"
    case trainingLoad = "Recent Load"

    var id: String { rawValue }

    var displayName: String { rawValue }
}

/// One weighted contribution to the recovery score.
struct RecoveryFactor: Identifiable, Equatable {
    var id: String { metric.rawValue }

    let metric: RecoveryFactorMetric

    /// −1.0 (strongly hurts recovery) … 1.0 (strongly helps).
    let contribution: Double

    /// Plain-language, baseline-relative explanation. Never a medical claim.
    let detail: String

    var isPositive: Bool { contribution > ScoringConstants.Recovery.notableContribution }
    var isNegative: Bool { contribution < -ScoringConstants.Recovery.notableContribution }
}

/// A metric the recovery engine wanted but could not read.
enum MissingHealthMetric: String, CaseIterable, Identifiable {
    case heartRateVariability = "HRV"
    case restingHeartRate = "Resting HR"
    case sleep = "Sleep"
    case workouts = "Workouts"
    case activity = "Activity"

    var id: String { rawValue }

    var displayName: String { rawValue }
}

/// The full output of `RecoveryEngine` — always explainable.
struct RecoveryResult: Equatable {
    let score: Int
    let category: RecoveryCategory
    let confidence: ConfidenceLevel
    let positiveFactors: [RecoveryFactor]
    let negativeFactors: [RecoveryFactor]
    let missingData: [MissingHealthMetric]
    let explanation: String
    let date: Date

    static func insufficientData(missing: [MissingHealthMetric], date: Date) -> RecoveryResult {
        RecoveryResult(
            score: 0,
            category: .veryLow,
            confidence: .insufficientData,
            positiveFactors: [],
            negativeFactors: [],
            missingData: missing,
            explanation: "Not enough data yet. Keep wearing your Apple Watch and allow Health access to build your baseline.",
            date: date
        )
    }

    var hasScore: Bool { confidence != .insufficientData }
}
