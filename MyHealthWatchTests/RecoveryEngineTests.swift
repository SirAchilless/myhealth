import Testing
import Foundation
@testable import MyHealthWatch

struct RecoveryEngineTests {
    // MARK: Fixtures

    private func baseline(median: Double, mad: Double, samples: Int = 14) -> MetricBaseline {
        MetricBaseline(
            window: .fourteenDays,
            median: median,
            medianAbsoluteDeviation: mad,
            sampleCount: samples,
            lastObserved: Date()
        )
    }

    private func strongInput(
        hrv: Double? = 45,
        rhr: Double? = 55,
        asleepMinutes: Double? = 480,
        needMinutes: Double = 480,
        acwr: Double? = 1.0
    ) -> RecoveryInput {
        RecoveryInput(
            date: Date(),
            latestHRV: hrv.map { HRVSample(milliseconds: $0, date: Date()) },
            hrvBaseline: baseline(median: 45, mad: 6),
            latestRestingHeartRate: rhr,
            restingHeartRateBaseline: baseline(median: 55, mad: 4),
            lastNightAsleepMinutes: asleepMinutes,
            personalSleepNeedMinutes: needMinutes,
            sleepTimingDeviationMinutes: 10,
            acuteToChronicRatio: acwr
        )
    }

    // MARK: Behavior

    @Test func neutralDayScoresNearMidpoint() {
        let result = RecoveryEngine.compute(strongInput())
        #expect(result.hasScore)
        // All signals exactly at baseline → 50 ± small timing/load effects.
        #expect(result.score >= 45 && result.score <= 55)
        #expect(result.confidence == .high)
    }

    @Test func highHRVLiftsScore() {
        let high = RecoveryEngine.compute(strongInput(hrv: 60))
        let neutral = RecoveryEngine.compute(strongInput(hrv: 45))
        #expect(high.score > neutral.score)
        #expect(high.positiveFactors.contains { $0.metric == .heartRateVariability })
    }

    @Test func hrvBelowBaselineLowersScore() {
        let low = RecoveryEngine.compute(strongInput(hrv: 30))
        let neutral = RecoveryEngine.compute(strongInput(hrv: 45))
        #expect(low.score < neutral.score)
        #expect(low.negativeFactors.contains { $0.metric == .heartRateVariability })
    }

    @Test func elevatedRestingHRLowersScore() {
        let elevated = RecoveryEngine.compute(strongInput(rhr: 63))
        let neutral = RecoveryEngine.compute(strongInput(rhr: 55))
        #expect(elevated.score < neutral.score)
    }

    @Test func shortSleepLowersScore() {
        let short = RecoveryEngine.compute(strongInput(asleepMinutes: 330))
        let full = RecoveryEngine.compute(strongInput(asleepMinutes: 480))
        #expect(short.score < full.score)
        #expect(short.negativeFactors.contains { $0.metric == .sleepDuration })
    }

    @Test func highLoadPenalizes() {
        let overloaded = RecoveryEngine.compute(strongInput(acwr: 1.8))
        let balanced = RecoveryEngine.compute(strongInput(acwr: 1.0))
        #expect(overloaded.score < balanced.score)
    }

    @Test func scoreClampedToBounds() {
        // Extreme values in every direction must stay 0–100.
        let extreme = RecoveryInput(
            date: Date(),
            latestHRV: HRVSample(milliseconds: 5, date: Date()),
            hrvBaseline: baseline(median: 45, mad: 6),
            latestRestingHeartRate: 90,
            restingHeartRateBaseline: baseline(median: 55, mad: 4),
            lastNightAsleepMinutes: 120,
            personalSleepNeedMinutes: 480,
            sleepTimingDeviationMinutes: 300,
            acuteToChronicRatio: 2.5
        )
        let result = RecoveryEngine.compute(extreme)
        #expect(result.score >= 0 && result.score <= 100)

        let perfect = RecoveryInput(
            date: Date(),
            latestHRV: HRVSample(milliseconds: 120, date: Date()),
            hrvBaseline: baseline(median: 45, mad: 6),
            latestRestingHeartRate: 40,
            restingHeartRateBaseline: baseline(median: 55, mad: 4),
            lastNightAsleepMinutes: 600,
            personalSleepNeedMinutes: 480,
            sleepTimingDeviationMinutes: 0,
            acuteToChronicRatio: 0.5
        )
        let perfectResult = RecoveryEngine.compute(perfect)
        #expect(perfectResult.score >= 0 && perfectResult.score <= 100)
    }

    @Test func categoriesMatchThresholds() {
        #expect(RecoveryCategory(score: 0) == .veryLow)
        #expect(RecoveryCategory(score: 29) == .veryLow)
        #expect(RecoveryCategory(score: 30) == .low)
        #expect(RecoveryCategory(score: 49) == .low)
        #expect(RecoveryCategory(score: 50) == .moderate)
        #expect(RecoveryCategory(score: 69) == .moderate)
        #expect(RecoveryCategory(score: 70) == .good)
        #expect(RecoveryCategory(score: 84) == .good)
        #expect(RecoveryCategory(score: 85) == .excellent)
        #expect(RecoveryCategory(score: 100) == .excellent)
    }

    // MARK: Missing data — never fabricate

    @Test func noInputsProducesNoScore() {
        let empty = RecoveryEngine.compute(RecoveryInput(date: Date()))
        #expect(!empty.hasScore)
        #expect(empty.confidence == .insufficientData)
        #expect(empty.missingData.count >= 3)
        #expect(empty.explanation.contains("Not enough data"))
    }

    @Test func weakInputsProduceInsufficientResult() {
        // Sleep alone (0.35 available weight) is below the 0.40 floor.
        let sleepOnly = RecoveryInput(
            date: Date(),
            lastNightAsleepMinutes: 480,
            personalSleepNeedMinutes: 480
        )
        let result = RecoveryEngine.compute(sleepOnly)
        #expect(!result.hasScore)
    }

    @Test func insufficientBaselinesReportMissing() {
        let input = RecoveryInput(
            date: Date(),
            latestHRV: HRVSample(milliseconds: 45, date: Date()),
            hrvBaseline: baseline(median: 45, mad: 6, samples: 2), // too few
            latestRestingHeartRate: 55,
            restingHeartRateBaseline: baseline(median: 55, mad: 4, samples: 2),
            lastNightAsleepMinutes: 480,
            personalSleepNeedMinutes: 480
        )
        let result = RecoveryEngine.compute(input)
        // Sleep (0.25) + timing is present but below floor → no fabricated score.
        #expect(!result.hasScore)
        #expect(result.missingData.contains(.heartRateVariability))
        #expect(result.missingData.contains(.restingHeartRate))
    }

    @Test func twoCoreSignalsScoreWithLowerConfidence() {
        // HR + sleep, no HRV → still scoreable (0.55 weight) at medium confidence.
        let input = RecoveryInput(
            date: Date(),
            latestRestingHeartRate: 55,
            restingHeartRateBaseline: baseline(median: 55, mad: 4),
            lastNightAsleepMinutes: 480,
            personalSleepNeedMinutes: 480
        )
        let result = RecoveryEngine.compute(input)
        #expect(result.hasScore)
        #expect(result.confidence == .medium)
    }

    @Test func explanationIsRelativeNotMedical() {
        let result = RecoveryEngine.compute(strongInput(hrv: 30, asleepMinutes: 360))
        #expect(!result.explanation.lowercased().contains("unhealthy"))
        #expect(result.negativeFactors.first?.detail.lowercased().contains("baseline") == true)
    }
}
