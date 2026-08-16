import Foundation

/// Computes **myhealth Energy** (0–100): today's capacity estimate blended
/// from recovery, sleep, and load freshness. A wellness estimate — never
/// presented as a physiological measurement.
enum EnergyEngine {
    static func compute(
        recovery: RecoveryResult?,
        sleep: SleepAnalysisResult?,
        load: LoadResult?
    ) -> EnergyResult? {
        var components: [(value: Double, weight: Double)] = []

        if let recovery, recovery.hasScore {
            components.append((Double(recovery.score), ScoringConstants.Energy.weightRecovery))
        }
        if let sleep, sleep.hasScore, let sleepScore = sleep.score {
            components.append((Double(sleepScore), ScoringConstants.Energy.weightSleep))
        }

        // Energy requires at least one of recovery or sleep.
        guard !components.isEmpty else { return nil }

        if let load, let todayLoad = load.todayLoad {
            let freshness = 100 - min(todayLoad * 10, 100)
            components.append((freshness, ScoringConstants.Energy.weightLoadFreshness))
        }

        let weightSum = components.reduce(0) { $0 + $1.weight }
        let weighted = components.reduce(0) { $0 + $1.value * $1.weight }
        let score = Int((weighted / weightSum).rounded())
        let clamped = min(max(score, 0), 100)
        let band = EnergyBand(score: clamped)

        let confidence = combineConfidence(recovery: recovery, sleep: sleep, load: load)

        let explanation: String
        switch band {
        case .low:
            explanation = "Running low today — favor rest, easy movement, and an earlier bedtime."
        case .moderate:
            explanation = "Moderate capacity — a steady day with normal training should feel fine."
        case .good:
            explanation = "Good capacity today — your recovery and sleep are supporting you."
        }

        return EnergyResult(
            score: clamped,
            band: band,
            confidence: confidence,
            explanation: explanation
        )
    }

    private static func combineConfidence(
        recovery: RecoveryResult?,
        sleep: SleepAnalysisResult?,
        load: LoadResult?
    ) -> ConfidenceLevel {
        func rank(_ level: ConfidenceLevel) -> Int {
            switch level {
            case .high: return 3
            case .medium: return 2
            case .low: return 1
            case .insufficientData: return 0
            }
        }

        var ranks: [Int] = []
        if let recovery, recovery.hasScore { ranks.append(rank(recovery.confidence)) }
        if let sleep, sleep.hasScore { ranks.append(rank(sleep.confidence)) }
        guard !ranks.isEmpty else { return .insufficientData }

        // The weakest available input dominates — energy can't outrank its
        // shakiest component.
        let weakest = ranks.min() ?? 0
        switch weakest {
        case 3: return .high
        case 2: return .medium
        case 1: return .low
        default: return .insufficientData
        }
    }
}
