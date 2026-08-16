import Foundation

/// Structured context the deterministic coach reasons over. All fields are
/// optional — the coach explains gaps instead of inventing answers.
struct CoachContext {
    let recovery: RecoveryResult?
    let sleep: SleepAnalysisResult?
    let load: LoadResult?
    let stress: StressResult?
    let energy: EnergyResult?
    let recentWorkouts: [WorkoutSummary]
    let date: Date
}

/// The five quick questions supported on watch.
enum CoachQuestion: String, CaseIterable, Identifiable {
    case howAmIDoing = "How am I doing?"
    case shouldITrain = "Should I train?"
    case whyRecoveryLow = "Why is recovery low?"
    case howDidISleep = "How did I sleep?"
    case whatToday = "What should I do today?"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .howAmIDoing: return "heart.text.square"
        case .shouldITrain: return "figure.run"
        case .whyRecoveryLow: return "arrow.down.heart"
        case .howDidISleep: return "bed.double"
        case .whatToday: return "sun.max"
        }
    }
}

enum RecommendationTone {
    case train
    case moderate
    case recover
    case buildData
}

/// One answer produced by `CoachEngine` — always grounded in available data.
struct CoachAnswer: Identifiable, Equatable {
    var id: String { question.rawValue }
    let question: CoachQuestion
    let headline: String
    let body: String
    /// Human-readable list of data that was missing for this answer.
    let dataGaps: [String]
}

/// The daily recommendation shown on the Today screen.
struct CoachRecommendation: Equatable {
    let title: String
    let detail: String
    let tone: RecommendationTone
}
