import Foundation

/// Workout categories myhealth records and understands.
enum WorkoutKind: String, CaseIterable, Identifiable, Codable {
    case running
    case walking
    case cycling
    case strengthTraining
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .strengthTraining: return "Strength"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "figure.outdoor.cycle"
        case .strengthTraining: return "figure.strengthtraining.functional"
        case .other: return "figure.mind.and.body"
        }
    }
}

/// How the load points for a workout were derived — TRIMP is preferred;
/// fallbacks are labeled estimates and lower the result's confidence.
enum LoadMethod: String, Codable {
    case trimp
    case energyEstimate
    case durationEstimate
}

/// Domain representation of one workout (from HealthKit or an in-app session).
struct WorkoutSummary: Identifiable, Equatable {
    let id: UUID
    let kind: WorkoutKind
    let start: Date
    let end: Date
    let durationMinutes: Double
    let averageHeartRate: Double?
    let activeCalories: Double?
    let distanceKilometers: Double?
    /// Estimated single-session load points (see docs/ALGORITHMS.md §Load).
    let loadPoints: Double
    let loadMethod: LoadMethod
    /// Whether myhealth itself recorded this workout.
    let recordedByMyHealth: Bool
}

/// Rolling load status derived from the acute:chronic workload ratio.
enum TrainingLoadBand: String, CaseIterable {
    case recovering = "Recovering"
    case productive = "Productive"
    case high = "High"
    case buildingHistory = "Building History"

    init(acuteToChronicRatio: Double?) {
        guard let ratio = acuteToChronicRatio else {
            self = .buildingHistory
            return
        }
        switch ratio {
        case ..<ScoringConstants.Load.recoveringUpperRatio:
            self = .recovering
        case ...ScoringConstants.Load.productiveUpperRatio:
            self = .productive
        default:
            self = .high
        }
    }
}

/// Full output of `LoadEngine`.
struct LoadResult: Equatable {
    /// Display load for today on the 0–10 myhealth Load scale.
    let todayLoad: Double?
    /// Raw summed load points today (TRIMP or labeled estimates).
    let todayRawPoints: Double
    /// Summed load points over the trailing 7 days.
    let weekRawPoints: Double
    /// Acute (7-day mean) to chronic (28-day mean) workload ratio.
    let acuteToChronicRatio: Double?
    let band: TrainingLoadBand
    let confidence: ConfidenceLevel
    let explanation: String
}
