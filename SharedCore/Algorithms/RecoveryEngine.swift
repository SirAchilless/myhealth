import Foundation

/// Everything `RecoveryEngine` needs. Each input is optional; missing inputs
/// are reported, never guessed.
struct RecoveryInput {
    var date: Date = Date()

    // Heart-rate variability (SDNN, ms)
    var latestHRV: HRVSample?
    var hrvBaseline: MetricBaseline?

    // Resting heart rate (bpm)
    var latestRestingHeartRate: Double?
    var restingHeartRateBaseline: MetricBaseline?

    // Last night's sleep
    var lastNightAsleepMinutes: Double?
    var personalSleepNeedMinutes: Double?

    /// How far last night's sleep midpoint deviated from the user's personal
    /// schedule baseline, in minutes (0 when on schedule).
    var sleepTimingDeviationMinutes: Double?

    // Training load context
    var acuteToChronicRatio: Double?
}

/// Computes the **myhealth Recovery Score** (0–100): a transparent, weighted
/// blend of baseline-relative signals. Full specification: docs/ALGORITHMS.md.
///
/// Design rules:
/// - Every factor is expressed relative to the user's *own* rolling baseline.
/// - Missing factors are excluded and their weight is redistributed.
/// - Below `minimumAvailableWeight` no score is produced at all.
enum RecoveryEngine {
    static func compute(_ input: RecoveryInput) -> RecoveryResult {
        var factors: [RecoveryFactor] = []
        var missing: [MissingHealthMetric] = []

        // MARK: HRV

        if let hrv = input.latestHRV, let baseline = input.hrvBaseline, baseline.isSufficient {
            let z = baseline.robustZScore(hrv.milliseconds) ?? 0
            let contribution = clamp(z / ScoringConstants.Recovery.zClamp)
            factors.append(RecoveryFactor(
                metric: .heartRateVariability,
                contribution: contribution,
                detail: hrvDetail(sample: hrv, baseline: baseline)
            ))
        } else {
            // Either no sample yet, or the baseline is still building.
            missing.append(.heartRateVariability)
        }

        // MARK: Resting heart rate

        if let rhr = input.latestRestingHeartRate,
           let baseline = input.restingHeartRateBaseline, baseline.isSufficient {
            // Higher-than-baseline resting HR hurts recovery → negate z.
            let z = baseline.robustZScore(rhr) ?? 0
            let contribution = clamp(-z / ScoringConstants.Recovery.zClamp)
            let delta = rhr - baseline.median
            let detail = String(
                format: "Resting HR %d bpm, %d bpm %@ your recent baseline.",
                Int(rhr.rounded()), Int(abs(delta).rounded()),
                delta > 0.5 ? "above" : delta < -0.5 ? "below" : "at"
            )
            factors.append(RecoveryFactor(metric: .restingHeartRate, contribution: contribution, detail: detail))
        } else {
            missing.append(.restingHeartRate)
        }

        // MARK: Sleep duration vs personal need

        if let asleep = input.lastNightAsleepMinutes, asleep > 0,
           let need = input.personalSleepNeedMinutes, need > 0 {
            let fulfillment = asleep / need
            let contribution = clamp((fulfillment - 1) / ScoringConstants.Recovery.sleepFulfillmentScale)
            let detail = String(
                format: "Slept %@ vs your %@ target.",
                Formatting.hoursMinutes(fromMinutes: asleep),
                Formatting.hoursMinutes(fromMinutes: need)
            )
            factors.append(RecoveryFactor(metric: .sleepDuration, contribution: contribution, detail: detail))
        } else {
            missing.append(.sleep)
        }

        // MARK: Sleep timing consistency

        if let deviation = input.sleepTimingDeviationMinutes {
            let scaled = clamp(deviation / ScoringConstants.Recovery.sleepTimingScaleMinutes, lower: 0)
            let detail = String(
                format: "Sleep schedule %@ your usual timing.",
                deviation <= 20 ? "matched" : deviation <= 60 ? "drifted from" : "was far from"
            )
            factors.append(RecoveryFactor(metric: .sleepTiming, contribution: -scaled, detail: detail))
        }

        // MARK: Recent load (ACWR)

        if let ratio = input.acuteToChronicRatio {
            let contribution: Double
            if ratio > ScoringConstants.Recovery.loadPenaltyRatio {
                contribution = -clamp((ratio - ScoringConstants.Recovery.loadPenaltyRatio) / 0.7, lower: 0)
            } else if ratio < ScoringConstants.Recovery.loadBonusRatio {
                contribution = ScoringConstants.Recovery.loadBonusCap
                    * clamp((ScoringConstants.Recovery.loadBonusRatio - ratio) / ScoringConstants.Recovery.loadBonusRatio, lower: 0)
            } else {
                contribution = 0
            }
            let detail = String(format: "Training load ratio %.2f, past week vs past month.", ratio)
            factors.append(RecoveryFactor(metric: .trainingLoad, contribution: contribution, detail: detail))
        } else {
            missing.append(.workouts)
        }

        // MARK: Combine

        let weights: [RecoveryFactorMetric: Double] = [
            .heartRateVariability: ScoringConstants.Recovery.weightHeartRateVariability,
            .restingHeartRate: ScoringConstants.Recovery.weightRestingHeartRate,
            .sleepDuration: ScoringConstants.Recovery.weightSleepDuration,
            .sleepTiming: ScoringConstants.Recovery.weightSleepTiming,
            .trainingLoad: ScoringConstants.Recovery.weightRecentLoad,
        ]

        let availableWeight = factors.reduce(0.0) { $0 + (weights[$1.metric] ?? 0) }
        let totalWeight = weights.values.reduce(0, +)

        guard availableWeight / totalWeight >= ScoringConstants.Recovery.minimumAvailableWeight else {
            return .insufficientData(missing: missing, date: input.date)
        }

        let weighted = factors.reduce(0.0) { $0 + (weights[$1.metric] ?? 0) * $1.contribution }
        let score = Int((ScoringConstants.Recovery.midpoint + 50 * weighted / availableWeight).rounded())
        let clampedScore = min(max(score, 0), 100)
        let category = RecoveryCategory(score: clampedScore)
        let confidence = confidenceLevel(for: input, factors: factors)

        let positives = factors.filter(\.isPositive).sorted { $0.contribution > $1.contribution }
        let negatives = factors.filter(\.isNegative).sorted { $0.contribution < $1.contribution }

        return RecoveryResult(
            score: clampedScore,
            category: category,
            confidence: confidence,
            positiveFactors: positives,
            negativeFactors: negatives,
            missingData: missing,
            explanation: explanation(category: category, positives: positives, negatives: negatives),
            date: input.date
        )
    }

    // MARK: - Helpers

    private static func hrvDetail(sample: HRVSample, baseline: MetricBaseline) -> String {
        if let percent = baseline.percentDifference(sample.milliseconds) {
            let percentText = String(format: "%.0f", abs(percent * 100))
            let direction = percent > 0.005 ? "above" : percent < -0.005 ? "below" : "at"
            return String(
                format: "HRV %.0f ms, %@%% %@ your recent baseline.",
                sample.milliseconds, percentText, direction
            )
        }
        return String(format: "HRV %.0f ms.", sample.milliseconds)
    }

    private static func confidenceLevel(for input: RecoveryInput, factors: [RecoveryFactor]) -> ConfidenceLevel {
        let present: Set<RecoveryFactorMetric> = Set(factors.map(\.metric))
        let corePresent = [
            present.contains(.heartRateVariability),
            present.contains(.restingHeartRate),
            present.contains(.sleepDuration),
        ].filter { $0 }.count

        let baselineCounts = [
            input.hrvBaseline?.sampleCount ?? 0,
            input.restingHeartRateBaseline?.sampleCount ?? 0,
        ]
        let strongBaselines = baselineCounts.filter { $0 >= ScoringConstants.Baseline.preferredSamples }.count

        switch corePresent {
        case 3: return strongBaselines >= 1 ? .high : .medium
        case 2: return .medium
        case 1: return .low
        default: return .insufficientData
        }
    }

    private static func explanation(
        category: RecoveryCategory,
        positives: [RecoveryFactor],
        negatives: [RecoveryFactor]
    ) -> String {
        var parts: [String] = []
        if let top = positives.first { parts.append(shortPhrase(top)) }
        if let top = negatives.first { parts.append(shortPhrase(top)) }
        let drivers = parts.isEmpty ? "signals are close to your baseline" : parts.joined(separator: "; ")
        return "Recovery is \(category.rawValue). \(drivers.capitalized)."
    }

    private static func shortPhrase(_ factor: RecoveryFactor) -> String {
        switch factor.metric {
        case .heartRateVariability: return factor.isPositive ? "HRV above baseline" : "HRV below baseline"
        case .restingHeartRate: return factor.isPositive ? "resting HR is low" : "resting HR is elevated"
        case .sleepDuration: return factor.isPositive ? "sleep covered your need" : "sleep was short"
        case .sleepTiming: return factor.isPositive ? "sleep was on schedule" : "sleep timing was off"
        case .trainingLoad: return factor.isPositive ? "recent load is light" : "recent load is high"
        }
    }

    private static func clamp(_ value: Double, lower: Double = -1, upper: Double = 1) -> Double {
        min(max(value, lower), upper)
    }
}
