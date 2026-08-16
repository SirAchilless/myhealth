import Testing
import Foundation
@testable import MyHealthWatch

struct BaselineCalculatorTests {
    @Test func medianOddCount() {
        #expect(BaselineCalculator.median([3, 1, 2]) == 2)
    }

    @Test func medianEvenCount() {
        #expect(BaselineCalculator.median([4, 1, 3, 2]) == 2.5)
    }

    @Test func medianEmpty() {
        #expect(BaselineCalculator.median([]) == nil)
    }

    @Test func medianAbsoluteDeviation() {
        // Values 1...5, median 3, deviations 2,1,0,1,2 → MAD 1.
        let mad = BaselineCalculator.medianAbsoluteDeviation([1, 2, 3, 4, 5], median: 3)
        #expect(mad == 1)
    }

    @Test func baselineExcludesOutOfWindow() {
        let now = Date()
        let values = Array(repeating: 50.0, count: 5)
        let recentDates = (0..<5).map { now.addingTimeInterval(Double(-$0) * 24 * 3600) }
        let oldDates = (30..<35).map { now.addingTimeInterval(Double(-$0) * 24 * 3600) }

        let baseline = BaselineCalculator.baseline(
            values: values + values,
            dates: recentDates + oldDates,
            window: .sevenDays,
            asOf: now
        )
        #expect(baseline?.sampleCount == 5)
    }

    @Test func baselineIsInsufficientWithFewSamples() {
        let now = Date()
        let baseline = BaselineCalculator.baseline(
            values: [50, 52],
            dates: [now, now.addingTimeInterval(-3600)],
            window: .sevenDays,
            asOf: now
        )
        #expect(baseline != nil)
        #expect(baseline?.isSufficient == false)
    }

    @Test func robustZScoreHandlesDegenerateSpread() {
        let baseline = MetricBaseline(
            window: .sevenDays,
            median: 50,
            medianAbsoluteDeviation: 0,
            sampleCount: 10,
            lastObserved: Date()
        )
        // MAD 0 → no meaningful z-score (avoids divide-by-zero).
        #expect(baseline.robustZScore(60) == nil)
    }

    @Test func robustZScoreMatchesDefinition() {
        // median 50, MAD 10 → robust sigma 14.826; value 64.826 → z ≈ 1.
        let baseline = MetricBaseline(
            window: .fourteenDays,
            median: 50,
            medianAbsoluteDeviation: 10,
            sampleCount: 10,
            lastObserved: Date()
        )
        let z = baseline.robustZScore(64.826)
        #expect(z != nil)
        #expect(abs(z! - 1.0) < 0.01)
    }

    @Test func percentDifference() {
        let baseline = MetricBaseline(
            window: .sevenDays,
            median: 40,
            medianAbsoluteDeviation: 5,
            sampleCount: 10,
            lastObserved: Date()
        )
        #expect(baseline.percentDifference(35) == -0.125)
    }

    @Test func outliersDoNotDragMedian() {
        // A single wild value barely moves the median baseline.
        let values = [48, 50, 49, 51, 50, 52, 49, 400]
        #expect(BaselineCalculator.median(values)! == 50)
    }

    // MARK: Sleep helpers

    private func night(daysAgo: Int, asleepMinutes: Double) -> SleepNight {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
        let bedtime = day.addingTimeInterval(23 * 3600)
        return SleepNight(
            date: day,
            bedtime: bedtime,
            wakeTime: bedtime.addingTimeInterval(asleepMinutes * 60),
            breakdown: SleepStageBreakdown(
                remMinutes: asleepMinutes * 0.2,
                coreMinutes: asleepMinutes * 0.5,
                deepMinutes: asleepMinutes * 0.3
            )
        )
    }

    @Test func personalSleepNeedUsesMedianAndClamps() {
        let nights = [
            night(daysAgo: 1, asleepMinutes: 460),
            night(daysAgo: 2, asleepMinutes: 480),
            night(daysAgo: 3, asleepMinutes: 500),
        ]
        let need = BaselineCalculator.personalSleepNeed(nights: nights, fallbackMinutes: 480)
        #expect(need == 480)

        // Extreme sleepers clamp to the 5–10 h band.
        let extreme = [night(daysAgo: 1, asleepMinutes: 720)]
        #expect(BaselineCalculator.personalSleepNeed(nights: extreme, fallbackMinutes: 480) == 600)
    }

    @Test func personalSleepNeedFallsBackWithoutHistory() {
        #expect(BaselineCalculator.personalSleepNeed(nights: [], fallbackMinutes: 495) == 495)
    }

    @Test func sleepMidpointBaselineComputed() {
        let nights = [night(daysAgo: 1, asleepMinutes: 480), night(daysAgo: 2, asleepMinutes: 480)]
        #expect(BaselineCalculator.sleepMidpointBaseline(nights: nights) != nil)
    }
}
