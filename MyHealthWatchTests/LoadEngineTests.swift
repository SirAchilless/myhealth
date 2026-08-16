import Testing
import Foundation
@testable import MyHealthWatch

struct LoadEngineTests {
    // MARK: Per-workout load

    @Test func trimpRequiresHeartRateAndResting() {
        let result = LoadEngine.loadPoints(
            durationMinutes: 60,
            averageHeartRate: 150,
            activeCalories: 600,
            restingHeartRate: 60,
            maxHeartRate: 190
        )
        // Reserve = 90/130 ≈ 0.692 → 60 × 0.64 × e^1.329 ≈ 159.
        #expect(result.method == .trimp)
        #expect(result.points > 100 && result.points < 220)
    }

    @Test func harderEffortYieldsMorePoints() {
        let easy = LoadEngine.loadPoints(durationMinutes: 30, averageHeartRate: 110, activeCalories: 200, restingHeartRate: 60, maxHeartRate: 190)
        let hard = LoadEngine.loadPoints(durationMinutes: 30, averageHeartRate: 165, activeCalories: 500, restingHeartRate: 60, maxHeartRate: 190)
        #expect(hard.points > easy.points * 2)
    }

    @Test func energyFallbackWhenNoRestingHR() {
        let result = LoadEngine.loadPoints(
            durationMinutes: 60,
            averageHeartRate: nil,
            activeCalories: 400,
            restingHeartRate: nil,
            maxHeartRate: 190
        )
        #expect(result.method == .energyEstimate)
        #expect(abs(result.points - 10.0) < 0.01) // 400 × 0.025
    }

    @Test func durationFallbackOfLastResort() {
        let result = LoadEngine.loadPoints(
            durationMinutes: 60,
            averageHeartRate: nil,
            activeCalories: nil,
            restingHeartRate: nil,
            maxHeartRate: 190
        )
        #expect(result.method == .durationEstimate)
        #expect(abs(result.points - 3.0) < 0.01) // 60 × 0.05
    }

    @Test func maxHeartRateUsesOverrideThenTanaka() {
        #expect(LoadEngine.maxHeartRate(ageYears: 30, override: 195) == 195)
        #expect(LoadEngine.maxHeartRate(ageYears: 30, override: nil) == 187) // 208 − 21
        #expect(LoadEngine.maxHeartRate(ageYears: nil, override: nil) == 183.5) // 208 − 0.7×35
    }

    // MARK: Daily summary + ACWR

    private func workout(daysAgo: Int, points: Double, duration: Double = 60, hr: Double? = 150) -> WorkoutSummary {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
        return WorkoutSummary(
            id: UUID(),
            kind: .running,
            start: day.addingTimeInterval(18 * 3600),
            end: day.addingTimeInterval(18 * 3600 + duration * 60),
            durationMinutes: duration,
            averageHeartRate: hr,
            activeCalories: 500,
            distanceKilometers: 8,
            loadPoints: points,
            loadMethod: .trimp,
            recordedByMyHealth: false
        )
    }

    private func history(days: Int, pointsPerDay: Double) -> [LoadDailyValue] {
        let calendar = Calendar.current
        return (1...days).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: Date()))
                .map { LoadDailyValue(day: $0, points: pointsPerDay) }
        }
    }

    @Test func balancedWeekIsProductive() {
        // Acute mean = chronic mean → ratio ≈ 1.0.
        let result = LoadEngine.compute(
            today: Date(),
            todayWorkouts: [workout(daysAgo: 0, points: 50)],
            history: history(days: 28, pointsPerDay: 50)
        )
        #expect(result.acuteToChronicRatio != nil)
        #expect(abs(result.acuteToChronicRatio! - 1.0) < 0.05)
        #expect(result.band == .productive)
        #expect(result.confidence == .high)
    }

    @Test func spikeWeekIsHighLoad() {
        let result = LoadEngine.compute(
            today: Date(),
            todayWorkouts: [workout(daysAgo: 0, points: 150)],
            history: history(days: 28, pointsPerDay: 30)
        )
        #expect(result.band == .high)
        #expect(result.acuteToChronicRatio! > 1.3)
    }

    @Test func lightWeekIsRecovering() {
        // Heavy month (28 × 80) but the past week tapers to nothing.
        let calendar = Calendar.current
        let history: [LoadDailyValue] = (1...28).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: Date())) else { return nil }
            let points: Double = offset <= 6 ? 20 : 80
            return LoadDailyValue(day: day, points: points)
        }
        let result = LoadEngine.compute(
            today: Date(),
            todayWorkouts: [],
            history: history
        )
        #expect(result.band == .recovering)
        #expect(result.acuteToChronicRatio! < 0.8)
    }

    @Test func shortHistoryReportsNoRatio() {
        let result = LoadEngine.compute(
            today: Date(),
            todayWorkouts: [workout(daysAgo: 0, points: 50)],
            history: history(days: 7, pointsPerDay: 50)
        )
        #expect(result.acuteToChronicRatio == nil)
        #expect(result.band == .buildingHistory)
        #expect(result.confidence == .low)
    }

    @Test func displayLoadScalesToTenAndClamps() {
        let result = LoadEngine.compute(
            today: Date(),
            todayWorkouts: [workout(daysAgo: 0, points: 70)],
            history: []
        )
        #expect(abs(result.todayLoad! - 7.0) < 0.01)

        let extreme = LoadEngine.compute(
            today: Date(),
            todayWorkouts: [workout(daysAgo: 0, points: 4000)],
            history: []
        )
        #expect(extreme.todayLoad! <= 10.0)
    }

    @Test func emptyDayIsZeroLoadNotMissing() {
        let result = LoadEngine.compute(today: Date(), todayWorkouts: [], history: [])
        #expect(result.todayLoad == 0)
        #expect(result.todayRawPoints == 0)
    }
}
