import Foundation

/// Wellness-oriented stress estimate categories. This is an app-generated
/// wellness signal — never a diagnosis of any kind.
enum StressCategory: String, CaseIterable {
    case low = "Low"
    case moderate = "Moderate"
    case elevated = "Elevated"

    init(index: Double) {
        switch index {
        case ..<ScoringConstants.Stress.moderateLowerBound:
            self = .low
        case ..<ScoringConstants.Stress.elevatedLowerBound:
            self = .moderate
        default:
            self = .elevated
        }
    }
}

/// One analysis window (default 10 minutes) used by `StressEngine`.
struct StressWindow: Identifiable, Equatable {
    var id: Date { start }
    let start: Date
    let minutes: Double
    let averageHeartRate: Double
    /// 0–100 stress index for this window.
    let index: Double
}

/// Full output of `StressEngine`.
struct StressResult: Equatable {
    let category: StressCategory
    /// 0–100 wellness index backing the category.
    let index: Double
    let confidence: ConfidenceLevel
    let explanation: String
    let assessedAt: Date
}

enum EnergyBand: String, CaseIterable {
    case low = "Low"
    case moderate = "Moderate"
    case good = "Good"

    init(score: Int) {
        switch score {
        case ..<ScoringConstants.Energy.lowUpperBound:
            self = .low
        case ..<ScoringConstants.Energy.moderateUpperBound:
            self = .moderate
        default:
            self = .good
        }
    }
}

/// Full output of `EnergyEngine` — a wellness estimate, not a measurement.
struct EnergyResult: Equatable {
    let score: Int
    let band: EnergyBand
    let confidence: ConfidenceLevel
    let explanation: String

    /// Capacity phrase shown under the number, e.g. "Good capacity today."
    var capacityPhrase: String {
        switch band {
        case .low: return "Take it easy today."
        case .moderate: return "Moderate capacity today."
        case .good: return "Good capacity today."
        }
    }
}
