import Testing
import Foundation
@testable import MyHealthWatch

struct CoachEngineTests {
    // MARK: Fixtures

    private func recovery(score: Int) -> RecoveryResult {
        RecoveryResult(
            score: score,
            category: RecoveryCategory(score: score),
            confidence: .high,
            positiveFactors: score >= 70
                ? [RecoveryFactor(metric: .heartRateVariability, contribution: 0.5, detail: "HRV 58 ms, 25% above your recent baseline.")]
                : [],
            negativeFactors: score < 50
                ? [
                    RecoveryFactor(metric: .sleepDuration, contribution: -0.7, detail: "Slept 5h 30m vs your 8h 0m target."),
                    RecoveryFactor(metric: .restingHeartRate, contribution: -0.4, detail: "Resting HR 63 bpm, 9 bpm above your recent baseline."),
                ]
                : [],
            missingData: [],
            explanation: "Test",
            date: Date()
        )
    }

    private func sleep(score: Int, asleepMinutes: Double = 460, deficit: Int? = nil) -> SleepAnalysisResult {
        SleepAnalysisResult(
            night: SleepNight(
                date: Date(),
                bedtime: Date().addingTimeInterval(-8 * 3600),
                wakeTime: Date(),
                breakdown: SleepStageBreakdown(
                    remMinutes: asleepMinutes * 0.22,
                    coreMinutes: asleepMinutes * 0.48,
                    deepMinutes: asleepMinutes * 0.30
                )
            ),
            score: score,
            rating: SleepRating(score: score),
            confidence: .high,
            components: [],
            deficitMinutes: deficit,
            explanation: ""
        )
    }

    private func load(band: TrainingLoadBand, ratio: Double?) -> LoadResult {
        LoadResult(
            todayLoad: 5,
            todayRawPoints: 50,
            weekRawPoints: 300,
            acuteToChronicRatio: ratio,
            band: band,
            confidence: .medium,
            explanation: ""
        )
    }

    private func context(
        recovery: RecoveryResult? = nil,
        sleepResult: SleepAnalysisResult? = nil,
        loadResult: LoadResult? = nil
    ) -> CoachContext {
        CoachContext(
            recovery: recovery,
            sleep: sleepResult,
            load: loadResult,
            stress: nil,
            energy: nil,
            recentWorkouts: [],
            date: Date()
        )
    }

    // MARK: Recommendation

    @Test func noDataBuildsBaseline() {
        let recommendation = CoachEngine.recommendation(for: context())
        #expect(recommendation.tone == .buildData)
        #expect(recommendation.title.contains("baseline"))
    }

    @Test func highRecoverySuggestsTraining() {
        let recommendation = CoachEngine.recommendation(
            for: context(recovery: recovery(score: 82))
        )
        #expect(recommendation.tone == .train)
    }

    @Test func highRecoveryButOverloadedWeekSuggestsModerate() {
        let recommendation = CoachEngine.recommendation(
            for: context(recovery: recovery(score: 82), loadResult: load(band: .high, ratio: 1.6))
        )
        #expect(recommendation.tone == .moderate)
    }

    @Test func moderateRecoverySuggestsModerate() {
        let recommendation = CoachEngine.recommendation(
            for: context(recovery: recovery(score: 55))
        )
        #expect(recommendation.tone == .moderate)
    }

    @Test func lowRecoveryPrioritizesRest() {
        let recommendation = CoachEngine.recommendation(
            for: context(recovery: recovery(score: 30))
        )
        #expect(recommendation.tone == .recover)
    }

    // MARK: Questions

    @Test func whyRecoveryLowExplainsFactors() {
        let answer = CoachEngine.answer(
            .whyRecoveryLow,
            context: context(recovery: recovery(score: 35))
        )
        #expect(answer.headline == "Main factors")
        #expect(answer.body.contains("target"))
        #expect(answer.body.contains("baseline"))
    }

    @Test func whyRecoveryLowHandlesHealthyDay() {
        let answer = CoachEngine.answer(
            .whyRecoveryLow,
            context: context(recovery: recovery(score: 80))
        )
        #expect(answer.headline == "Recovery isn't low")
    }

    @Test func shouldITrainTiersByScore() {
        let yes = CoachEngine.answer(.shouldITrain, context: context(recovery: recovery(score: 78)))
        #expect(yes.headline.contains("harder"))

        let moderate = CoachEngine.answer(.shouldITrain, context: context(recovery: recovery(score: 60)))
        #expect(moderate.headline.contains("moderate"))

        let rest = CoachEngine.answer(.shouldITrain, context: context(recovery: recovery(score: 40)))
        #expect(rest.headline.contains("easy"))
    }

    @Test func shouldITrainWithoutDataIsHonest() {
        let answer = CoachEngine.answer(.shouldITrain, context: context())
        #expect(answer.headline == "Go by feel")
        #expect(!answer.dataGaps.isEmpty)
    }

    @Test func howDidISleepIncludesStagesAndDeficit() {
        let answer = CoachEngine.answer(
            .howDidISleep,
            context: context(sleepResult: sleep(score: 58, asleepMinutes: 420, deficit: 60))
        )
        #expect(answer.body.contains("Deep"))
        #expect(answer.body.contains("REM"))
        #expect(answer.body.contains("short of your target"))
    }

    @Test func howDidISleepHandlesNoData() {
        let answer = CoachEngine.answer(.howDidISleep, context: context())
        #expect(answer.headline == "No sleep analysis yet")
    }

    @Test func answersNeverInventData() {
        // With an empty context every answer must mention what's missing
        // rather than quoting numbers.
        for question in CoachQuestion.allCases {
            let answer = CoachEngine.answer(question, context: context())
            if question != .whatToday {
                #expect(!answer.body.contains("%"))
            }
        }
    }
}

// MARK: - Mock scenarios (development data integrity)

struct MockScenarioTests {
    @Test func deniedScenarioThrows() async {
        let provider = MockHealthDataProvider(scenario: .permissionDenied)
        #expect(provider.authorizationStatus() == .denied)
        await #expect(throws: MyHealthError.self) {
            _ = try await provider.hrvSamples(days: 7)
        }
    }

    @Test func insufficientScenarioHasSparseData() async {
        let provider = MockHealthDataProvider(scenario: .insufficientData)
        let hrv = try? await provider.hrvSamples(days: 30)
        #expect((hrv ?? []).count <= 2)
        let resting = try? await provider.restingHeartRateSamples(days: 30)
        #expect((resting ?? []).count <= 2)
    }

    @Test func partialScenarioKeepsSleepDropsHeart() async {
        let provider = MockHealthDataProvider(scenario: .partialData)
        let sleep = try? await provider.sleepSamples(nights: 3)
        #expect((sleep ?? []).count > 0)
        let hrv = try? await provider.hrvSamples(days: 3)
        #expect((hrv ?? []).isEmpty)
    }

    @Test func mockExercisesFullPipelineWithoutFabricatedScores() {
        // The engine must refuse a score when the mock provides no heart data.
        let input = RecoveryInput(
            date: Date(),
            latestHRV: nil,
            hrvBaseline: nil,
            latestRestingHeartRate: nil,
            restingHeartRateBaseline: nil,
            lastNightAsleepMinutes: 460,
            personalSleepNeedMinutes: 480
        )
        let result = RecoveryEngine.compute(input)
        #expect(!result.hasScore)
    }
}
