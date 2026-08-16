import Testing
import Foundation
@testable import MyHealthWatch

struct SleepAnalyzerTests {
    // MARK: Fixtures

    private func night(
        rem: Double = 90,
        core: Double = 260,
        deep: Double = 92,
        awake: Double = 20,
        inBed: Double = 480,
        bedtimeHour: Double = 23
    ) -> SleepNight {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let bedtime = day.addingTimeInterval(bedtimeHour * 3600 - 3600) // e.g. 22:00
        return SleepNight(
            date: day,
            bedtime: bedtime,
            wakeTime: bedtime.addingTimeInterval(inBed * 60),
            breakdown: SleepStageBreakdown(
                remMinutes: rem,
                coreMinutes: core,
                deepMinutes: deep,
                awakeMinutes: awake,
                inBedMinutes: inBed
            )
        )
    }

    // MARK: Scoring

    @Test func fullNeedAndEfficiencyScoresHigh() {
        let result = SleepAnalyzer.analyze(
            night: night(rem: 90, core: 268, deep: 92, awake: 10, inBed: 470), // 450 asleep
            personalNeedMinutes: 450,
            timingBaselineMinutes: nil
        )
        #expect(result.hasScore)
        #expect(result.score! >= 80)
        #expect(result.rating == .excellent || result.rating == .good)
        #expect(result.confidence == .high)
    }

    @Test func shortSleepScoresLower() {
        let short = SleepAnalyzer.analyze(
            night: night(rem: 45, core: 170, deep: 55, awake: 20, inBed: 310), // 270 asleep
            personalNeedMinutes: 480,
            timingBaselineMinutes: nil
        )
        let full = SleepAnalyzer.analyze(
            night: night(rem: 90, core: 280, deep: 100, awake: 20, inBed: 510), // 470 asleep
            personalNeedMinutes: 480,
            timingBaselineMinutes: nil
        )
        #expect(short.score! < full.score!)
        #expect(short.deficitMinutes != nil)
        #expect(full.deficitMinutes == nil)
    }

    @Test func fragmentedSleepLosesDisturbancePoints() {
        let calm = SleepAnalyzer.analyze(
            night: night(awake: 8),
            personalNeedMinutes: 460,
            timingBaselineMinutes: nil
        )
        let fragmented = SleepAnalyzer.analyze(
            night: night(awake: 140),
            personalNeedMinutes: 460,
            timingBaselineMinutes: nil
        )
        #expect(fragmented.score! < calm.score!)
    }

    @Test func lateMidpointAgainstBaselineLosesConsistency() {
        let onTime = SleepAnalyzer.analyze(
            night: night(bedtimeHour: 22.8),
            personalNeedMinutes: 450,
            timingBaselineMinutes: night(bedtimeHour: 22.8).midpointMinutesFromMidnight
        )
        let late = SleepAnalyzer.analyze(
            night: night(bedtimeHour: 3.5), // very late night
            personalNeedMinutes: 450,
            timingBaselineMinutes: night(bedtimeHour: 22.8).midpointMinutesFromMidnight
        )
        #expect(late.score! < onTime.score!)
    }

    @Test func ratingsMatchThresholds() {
        #expect(SleepRating(score: 0) == .poor)
        #expect(SleepRating(score: 49) == .poor)
        #expect(SleepRating(score: 50) == .fair)
        #expect(SleepRating(score: 69) == .fair)
        #expect(SleepRating(score: 70) == .good)
        #expect(SleepRating(score: 84) == .good)
        #expect(SleepRating(score: 85) == .excellent)
    }

    // MARK: Missing data — never fabricate

    @Test func tinyNightProducesNoScore() {
        let napish = SleepNight(
            date: Date(),
            bedtime: Date(),
            wakeTime: Date().addingTimeInterval(40 * 60),
            breakdown: SleepStageBreakdown(coreMinutes: 40)
        )
        let result = SleepAnalyzer.analyze(night: napish, personalNeedMinutes: 480, timingBaselineMinutes: nil)
        #expect(!result.hasScore)
        #expect(result.confidence == .insufficientData)
        #expect(result.score == nil)
    }

    @Test func needFallsBackToDefaultAndClamps() {
        let result = SleepAnalyzer.analyze(
            night: night(),
            personalNeedMinutes: nil,
            timingBaselineMinutes: nil
        )
        // Default 480 clamps into range; scoring still works.
        #expect(result.hasScore)
    }

    @Test func circularMidpointWrapsMidnight() {
        // 23:50 midpoint vs 00:10 baseline = 20 minutes apart, not 23h40m.
        let lateNight = night(bedtimeHour: 22.7)
        let anchor = lateNight.midpointMinutesFromMidnight! + 20 // shift baseline 20 min
        let deviation = SleepAnalyzer.timingDeviation(night: lateNight, timingBaselineMinutes: anchor)
        #expect(deviation != nil)
        #expect(abs(deviation! - 20) < 1.5)
    }
}

// MARK: - Night assembler

struct SleepNightAssemblerTests {
    private func interval(_ stage: SleepStageKind, _ startMinutes: Double, _ endMinutes: Double, base: Date) -> SleepSample {
        SleepSample(
            stage: stage,
            start: base.addingTimeInterval(startMinutes * 60),
            end: base.addingTimeInterval(endMinutes * 60)
        )
    }

    @Test func overlappingIntervalsFromTwoSourcesAreNotDoubleCounted() {
        let base = Date()
        // Watch reports 22:00–02:00 core; iPhone reports 22:30–01:30 core.
        let samples = [
            interval(.core, 0, 240, base: base),
            interval(.core, 30, 150, base: base),
        ]
        let nights = SleepNightAssembler.nights(from: samples)
        #expect(nights.count == 1)
        #expect(abs(nights[0].breakdown.coreMinutes - 240) < 0.01)
    }

    @Test func clustersSeparateIntoNights() {
        let base = Date()
        var samples: [SleepSample] = []
        // Night A: 0–300 min
        samples.append(interval(.core, 0, 300, base: base))
        // Night B: starts 12 h later (gap > 3 h)
        let offset = 12 * 60.0
        samples.append(interval(.core, offset, offset + 300, base: base))
        let nights = SleepNightAssembler.nights(from: samples)
        #expect(nights.count == 2)
    }

    @Test func shortNapsAreExcluded() {
        let base = Date()
        let samples = [interval(.core, 0, 25, base: base)] // 25 min nap
        #expect(SleepNightAssembler.nights(from: samples).isEmpty)
    }

    @Test func lastNightIsMostRecentWithinWindow() {
        let base = Date()
        let recent = interval(.core, -200, 0, base: base) // ended now
        let older = interval(.core, -30 * 24 * 60, -30 * 24 * 60 + 300, base: base)
        let nights = SleepNightAssembler.nights(from: [recent, older])
        let last = SleepNightAssembler.lastNight(from: nights)
        #expect(last != nil)
        #expect(last!.wakeTime! > base.addingTimeInterval(-3600))
    }

    @Test func missingInBedIsApproximated() {
        // Apple Watch data sometimes lacks explicit inBed; efficiency must
        // still be scoreable from the asleep span.
        let base = Date()
        let samples = [interval(.core, 0, 400, base: base)]
        let nights = SleepNightAssembler.nights(from: samples)
        #expect(nights.count == 1)
        #expect(nights[0].breakdown.inBedMinutes >= 400)
    }
}
