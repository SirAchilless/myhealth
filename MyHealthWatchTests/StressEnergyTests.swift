import Testing
import Foundation
@testable import MyHealthWatch

struct StressEngineTests {
    private func window(_ offsetMinutes: Double, hr: Double, sleeping: Bool = false) -> StressWindowInput {
        StressWindowInput(
            start: Date().addingTimeInterval(-offsetMinutes * 60),
            minutes: 10,
            averageHeartRate: hr,
            isSleepWindow: sleeping
        )
    }

    private func hrvBaseline(median: Double) -> MetricBaseline {
        MetricBaseline(
            window: .fourteenDays,
            median: median,
            medianAbsoluteDeviation: median * 0.12,
            sampleCount: 14,
            lastObserved: Date()
        )
    }

    @Test func restingHeartReportsLowStress() {
        let result = StressEngine.compute(
            windows: [window(10, hr: 56)],
            restingBaseline: 55,
            latestHRV: HRVSample(milliseconds: 45, date: Date()),
            hrvBaseline: hrvBaseline(median: 45)
        )
        #expect(result != nil)
        #expect(result!.category == .low)
        #expect(result!.confidence == .high)
    }

    @Test func elevatedHeartReportsElevatedStress() {
        let result = StressEngine.compute(
            windows: [window(10, hr: 95)],
            restingBaseline: 55,
            latestHRV: HRVSample(milliseconds: 30, date: Date()),
            hrvBaseline: hrvBaseline(median: 45)
        )
        #expect(result!.category == .elevated)
        #expect(result!.index > 66)
    }

    @Test func categoriesMatchThresholds() {
        #expect(StressCategory(index: 0) == .low)
        #expect(StressCategory(index: 32.9) == .low)
        #expect(StressCategory(index: 33) == .moderate)
        #expect(StressCategory(index: 65.9) == .moderate)
        #expect(StressCategory(index: 66) == .elevated)
    }

    @Test func hrvSuppressionAloneDrivesEstimate() {
        // Normal HR but HRV at half the baseline → HRV suppression alone
        // (weight 0.35) must carry the index into double digits.
        let result = StressEngine.compute(
            windows: [window(10, hr: 56)],
            restingBaseline: 55,
            latestHRV: HRVSample(milliseconds: 22, date: Date()), // half of baseline
            hrvBaseline: hrvBaseline(median: 45)
        )
        #expect(result!.index > 15)
    }

    @Test func sleepWindowsAreDampened() {
        let awake = StressEngine.compute(
            windows: [window(10, hr: 90)],
            restingBaseline: 55,
            latestHRV: nil,
            hrvBaseline: nil
        )
        let asleep = StressEngine.compute(
            windows: [window(10, hr: 90, sleeping: true)],
            restingBaseline: 55,
            latestHRV: nil,
            hrvBaseline: nil
        )
        #expect(asleep!.index < awake!.index)
    }

    @Test func noWindowsReturnsNil() {
        let result = StressEngine.compute(
            windows: [],
            restingBaseline: 55,
            latestHRV: nil,
            hrvBaseline: nil
        )
        #expect(result == nil)
    }

    @Test func noBaselinesGivesLowConfidence() {
        let result = StressEngine.compute(
            windows: [window(10, hr: 70)],
            restingBaseline: nil,
            latestHRV: nil,
            hrvBaseline: nil
        )
        // Windows exist but nothing to compare against → medium index, low confidence.
        #expect(result != nil)
        #expect(result!.confidence == .low)
    }

    @Test func windowBuilderBucketsSamples() {
        let base = Date()
        // 3 samples in first 10 minutes, 2 in the next.
        let samples = [
            HeartRateSample(beatsPerMinute: 60, date: base),
            HeartRateSample(beatsPerMinute: 70, date: base.addingTimeInterval(60)),
            HeartRateSample(beatsPerMinute: 80, date: base.addingTimeInterval(120)),
            HeartRateSample(beatsPerMinute: 90, date: base.addingTimeInterval(601)),
            HeartRateSample(beatsPerMinute: 100, date: base.addingTimeInterval(661)),
        ]
        let windows = StressEngine.WindowBuilder.windows(from: samples, windowMinutes: 10) { _ in false }
        #expect(windows.count == 2)
        #expect(abs(windows[0].averageHeartRate - 70) < 0.01)
        #expect(abs(windows[1].averageHeartRate - 95) < 0.01)
    }

    @Test func explanationNeverDiagnoses() {
        let result = StressEngine.compute(
            windows: [window(10, hr: 95)],
            restingBaseline: 55,
            latestHRV: nil,
            hrvBaseline: nil
        )
        let text = result!.explanation.lowercased()
        #expect(text.contains("wellness estimate"))
        #expect(!text.contains("anxiety"))
        #expect(!text.contains("depress"))
    }
}

struct EnergyEngineTests {
    private func recovery(score: Int, confidence: ConfidenceLevel = .high) -> RecoveryResult {
        RecoveryResult(
            score: score,
            category: RecoveryCategory(score: score),
            confidence: confidence,
            positiveFactors: [],
            negativeFactors: [],
            missingData: [],
            explanation: "Test",
            date: Date()
        )
    }

    @Test func energyTracksRecovery() {
        let high = EnergyEngine.compute(recovery: recovery(score: 90), sleep: nil, load: nil)!
        let low = EnergyEngine.compute(recovery: recovery(score: 20), sleep: nil, load: nil)!
        #expect(high.score > low.score)
        #expect(high.band == .good)
        #expect(low.band == .low)
    }

    @Test func requiresRecoveryOrSleep() {
        let result = EnergyEngine.compute(recovery: nil, sleep: nil, load: nil)
        #expect(result == nil)

        let insufficient = EnergyEngine.compute(
            recovery: RecoveryResult.insufficientData(missing: [], date: Date()),
            sleep: nil,
            load: nil
        )
        #expect(insufficient == nil)
    }

    @Test func heavyDayTodayReducesEnergy() {
        func load(today: Double) -> LoadResult {
            LoadResult(
                todayLoad: today,
                todayRawPoints: today * 100,
                weekRawPoints: today * 100,
                acuteToChronicRatio: 1.0,
                band: .productive,
                confidence: .high,
                explanation: ""
            )
        }
        let fresh = EnergyEngine.compute(recovery: recovery(score: 80), sleep: nil, load: load(today: 0))!
        let drained = EnergyEngine.compute(recovery: recovery(score: 80), sleep: nil, load: load(today: 9))!
        #expect(drained.score < fresh.score)
    }

    @Test func energyNeverOutranksWeakestInput() {
        let weakSleep = SleepAnalysisResult(
            night: SleepNight(date: Date(), bedtime: nil, wakeTime: nil, breakdown: SleepStageBreakdown(coreMinutes: 480)),
            score: 90,
            rating: .excellent,
            confidence: .low,
            components: [],
            deficitMinutes: nil,
            explanation: ""
        )
        let result = EnergyEngine.compute(
            recovery: recovery(score: 90, confidence: .high),
            sleep: weakSleep,
            load: nil
        )
        #expect(result!.confidence == .low)
    }

    @Test func bandsMatchThresholds() {
        #expect(EnergyBand(score: 29) == .low)
        #expect(EnergyBand(score: 30) == .moderate)
        #expect(EnergyBand(score: 69) == .moderate)
        #expect(EnergyBand(score: 70) == .good)
    }
}
