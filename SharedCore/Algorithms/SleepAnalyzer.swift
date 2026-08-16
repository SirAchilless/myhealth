import Foundation

/// Computes the **myhealth Sleep Score** (0–100) for one night from four
/// transparent components: need fulfillment, efficiency, schedule
/// consistency, and disturbances. Full specification: docs/ALGORITHMS.md.
enum SleepAnalyzer {
    /// - Parameters:
    ///   - night: the assembled sleep night to score.
    ///   - personalNeedMinutes: personal nightly need (from settings or the
    ///     14-night baseline); falls back to the default.
    ///   - timingBaselineMinutes: personal sleep-midpoint baseline (minutes
    ///     from midnight). `nil` disables the consistency component.
    static func analyze(
        night: SleepNight,
        personalNeedMinutes: Double?,
        timingBaselineMinutes: Double?
    ) -> SleepAnalysisResult {
        let breakdown = night.breakdown
        let asleep = breakdown.asleepMinutes
        let need = (personalNeedMinutes ?? ScoringConstants.Sleep.defaultNeedMinutes)
            .clamped(to: 240...720)

        // Not enough recorded sleep to score honestly.
        guard asleep >= ScoringConstants.Sleep.minimumScoreableAsleepMinutes else {
            return SleepAnalysisResult(
                night: night,
                score: nil,
                rating: nil,
                confidence: .insufficientData,
                components: [],
                deficitMinutes: nil,
                explanation: "Not enough sleep data recorded for last night. Wear your watch to bed to see your sleep analysis."
            )
        }

        var components: [SleepScoreComponent] = []

        // MARK: Need fulfillment (0.45)

        let fulfillment = min(asleep / need, 1.0)
        components.append(SleepScoreComponent(
            name: "Duration",
            weight: ScoringConstants.Sleep.weightNeedFulfillment,
            achieved: fulfillment,
            detail: String(
                format: "Slept %@ of your %@ target.",
                Formatting.hoursMinutes(fromMinutes: asleep),
                Formatting.hoursMinutes(fromMinutes: need)
            )
        ))

        // MARK: Efficiency (0.30)

        if breakdown.inBedMinutes >= asleep {
            let efficiency = asleep / breakdown.inBedMinutes
            let achieved = min(efficiency / ScoringConstants.Sleep.fullEfficiency, 1.0)
            components.append(SleepScoreComponent(
                name: "Efficiency",
                weight: ScoringConstants.Sleep.weightEfficiency,
                achieved: achieved,
                detail: String(format: "%.0f%% of time in bed was asleep.", efficiency * 100)
            ))
        }

        // MARK: Schedule consistency (0.15)

        var timingDeviationMinutes: Double?
        if let midpoint = night.midpointMinutesFromMidnight {
            if let baseline = timingBaselineMinutes {
                let deviation = circularMinuteDifference(midpoint, baseline)
                timingDeviationMinutes = deviation
                let achieved = 1 - min(deviation / ScoringConstants.Recovery.sleepTimingScaleMinutes, 1.0)
                components.append(SleepScoreComponent(
                    name: "Timing",
                    weight: ScoringConstants.Sleep.weightConsistency,
                    achieved: achieved,
                    detail: String(format: "Schedule within %d min of your usual timing.", Int(deviation.rounded()))
                ))
            } else {
                // Midpoint known but no personal baseline yet — neutral detail.
                components.append(SleepScoreComponent(
                    name: "Timing",
                    weight: ScoringConstants.Sleep.weightConsistency,
                    achieved: 0.5,
                    detail: "Schedule baseline still building."
                ))
                timingDeviationMinutes = nil
            }
        }

        // MARK: Disturbances (0.10)

        let awakeShare = asleep > 0 ? breakdown.awakeMinutes / asleep : 0
        let disturbanceAchieved = 1 - min(awakeShare / ScoringConstants.Sleep.fullDisturbanceShare, 1.0)
        components.append(SleepScoreComponent(
            name: "Disturbances",
            weight: ScoringConstants.Sleep.weightDisturbances,
            achieved: disturbanceAchieved,
            detail: String(format: "Awake %@ during the night.", Formatting.hoursMinutes(fromMinutes: breakdown.awakeMinutes))
        ))

        // MARK: Combine

        let totalWeight = components.reduce(0) { $0 + $1.weight }
        let weighted = components.reduce(0) { $0 + $1.weight * $1.achieved }
        let score = Int((100 * weighted / totalWeight).rounded())
        let clampedScore = min(max(score, 0), 100)
        let rating = SleepRating(score: clampedScore)

        let deficit = max(0, need - asleep) >= 15
            ? Int(max(0, need - asleep).rounded())
            : nil

        let confidence: ConfidenceLevel = components.count >= 4 ? .high : .medium

        return SleepAnalysisResult(
            night: night,
            score: clampedScore,
            rating: rating,
            confidence: confidence,
            components: components,
            deficitMinutes: deficit,
            explanation: "Sleep was \(rating.rawValue.lowercased()) — \(explanationHighlight(components: components))."
        )
    }

    /// The timing deviation this analyzer computed (used by RecoveryEngine).
    /// Exposed via the "Timing" component detail; recomputed here for callers
    /// that need the raw number.
    static func timingDeviation(
        night: SleepNight,
        timingBaselineMinutes: Double?
    ) -> Double? {
        guard let midpoint = night.midpointMinutesFromMidnight,
              let baseline = timingBaselineMinutes else { return nil }
        return circularMinuteDifference(midpoint, baseline)
    }

    // MARK: - Helpers

    /// Distance between two minute-of-day values (0–720) on a circular scale,
    /// e.g. 23:50 vs 00:10 is 20 minutes, not 1430.
    private static func circularMinuteDifference(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b)
        return min(diff, 1440 - diff)
    }

    private static func explanationHighlight(components: [SleepScoreComponent]) -> String {
        if let weakest = components.min(by: { $0.achieved < $1.achieved }), weakest.achieved < 0.6 {
            return "\(weakest.name.lowercased()) was the limiting factor"
        }
        return "a balanced night across duration, efficiency, and timing"
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
