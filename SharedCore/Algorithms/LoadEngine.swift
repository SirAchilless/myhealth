import Foundation

/// One day of summed load points, used for rolling windows and ACWR.
struct LoadDailyValue: Equatable {
    let day: Date
    let points: Double
}

/// Computes the **myhealth Load** metric (0–10 daily scale) and the
/// acute:chronic workload ratio. Per-workout load uses Banister TRIMP when
/// heart-rate data exists, with clearly-labeled energy/duration fallbacks.
/// Full specification: docs/ALGORITHMS.md.
enum LoadEngine {
    // MARK: Per-workout load

    /// Maximum heart rate: user override, else the Tanaka estimate
    /// 208 − 0.7 × age.
    static func maxHeartRate(ageYears: Double?, override: Int?) -> Double {
        if let override, override > 120, override < 230 { return Double(override) }
        let age = ageYears ?? ScoringConstants.Load.defaultAgeYears
        return ScoringConstants.Load.maxHeartRateIntercept
            - ScoringConstants.Load.maxHeartRateSlope * age
    }

    /// Load points for one workout. TRIMP (preferred) requires average HR and
    /// a resting-HR baseline; fallbacks are labeled on the returned method.
    static func loadPoints(
        durationMinutes: Double,
        averageHeartRate: Double?,
        activeCalories: Double?,
        restingHeartRate: Double?,
        maxHeartRate: Double
    ) -> (points: Double, method: LoadMethod) {
        if let avgHR = averageHeartRate, let resting = restingHeartRate, maxHeartRate > resting + 10 {
            let reserve = min(max((avgHR - resting) / (maxHeartRate - resting), 0), 1)
            let trimp = durationMinutes
                * ScoringConstants.Load.trimpCoefficient
                * exp(ScoringConstants.Load.trimpExponent * reserve)
            return (trimp, .trimp)
        }
        if let calories = activeCalories, calories > 0 {
            return (
                calories * ScoringConstants.Load.energyFallbackPointsPerKcal,
                .energyEstimate
            )
        }
        return (
            durationMinutes * ScoringConstants.Load.durationFallbackPointsPerMinute,
            .durationEstimate
        )
    }

    /// Attaches load points to a workout summary (single source of truth).
    static func workoutSummary(
        kind: WorkoutKind,
        start: Date,
        end: Date,
        averageHeartRate: Double?,
        activeCalories: Double?,
        distanceKilometers: Double?,
        restingHeartRate: Double?,
        maxHeartRate: Double,
        recordedByMyHealth: Bool = false,
        id: UUID = UUID()
    ) -> WorkoutSummary {
        let minutes = max(end.timeIntervalSince(start) / 60, 0)
        let (points, method) = loadPoints(
            durationMinutes: minutes,
            averageHeartRate: averageHeartRate,
            activeCalories: activeCalories,
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate
        )
        return WorkoutSummary(
            id: id,
            kind: kind,
            start: start,
            end: end,
            durationMinutes: minutes,
            averageHeartRate: averageHeartRate,
            activeCalories: activeCalories,
            distanceKilometers: distanceKilometers,
            loadPoints: points,
            loadMethod: method,
            recordedByMyHealth: recordedByMyHealth
        )
    }

    // MARK: Daily / rolling summary

    static func compute(
        today: Date,
        todayWorkouts: [WorkoutSummary],
        history: [LoadDailyValue],
        calendar: Calendar = .current
    ) -> LoadResult {
        let todayRaw = todayWorkouts.reduce(0) { $0 + $1.loadPoints }
        let todayDisplay = min(todayRaw / ScoringConstants.Load.displayScaleDivisor, ScoringConstants.Load.displayScaleMaximum)

        // History values excluding today (today's contribution arrives via
        // todayWorkouts).
        let startOfToday = calendar.startOfDay(for: today)
        let pastDaily = history
            .filter { $0.day < startOfToday }
            .sorted { $0.day < $1.day }

        // Acute window covers today + the previous 6 days (7 days total).
        let weekWindowStart = calendar.date(
            byAdding: .day,
            value: -(ScoringConstants.Load.acuteWindowDays - 1),
            to: startOfToday
        ) ?? startOfToday
        let monthWindowStart = calendar.date(
            byAdding: .day,
            value: -ScoringConstants.Load.chronicWindowDays,
            to: startOfToday
        ) ?? startOfToday

        var weekRaw = todayRaw
        var monthDayCount = 1.0
        var monthRaw = todayRaw

        for value in pastDaily {
            if value.day >= weekWindowStart { weekRaw += value.points }
            if value.day >= monthWindowStart {
                monthRaw += value.points
                monthDayCount += 1
            }
        }

        // ACWR requires enough chronic history to be meaningful.
        var ratio: Double?
        if monthDayCount >= Double(ScoringConstants.Load.minimumChronicDays) {
            let acuteMean = weekRaw / Double(ScoringConstants.Load.acuteWindowDays)
            let chronicMean = monthRaw / monthDayCount
            if chronicMean > 0.01 {
                ratio = acuteMean / chronicMean
            }
        }

        let band = TrainingLoadBand(acuteToChronicRatio: ratio)
        let confidence = loadConfidence(historyDays: Int(monthDayCount))

        var explanation: String
        if todayWorkouts.isEmpty {
            explanation = "No workouts recorded today. "
        } else {
            let methods = Set(todayWorkouts.map(\.loadMethod))
            explanation = methods.contains(.trimp)
                ? "Today's workouts add up to \(String(format: "%.1f", todayDisplay)) load. "
                : "Today's load is estimated\(methods.contains(.energyEstimate) ? " from calories" : " from duration") — no heart-rate data. "
        }
        switch band {
        case .buildingHistory:
            explanation += "Keep training — a full month of history unlocks your load trend."
        case .recovering:
            explanation += "Your week is lighter than your month: a recovering pattern."
        case .productive:
            explanation += "Your week is well balanced against your month: a productive pattern."
        case .high:
            explanation += "Your week is well above your month. Consider easier days ahead."
        }

        return LoadResult(
            todayLoad: todayWorkouts.isEmpty ? 0 : todayDisplay,
            todayRawPoints: todayRaw,
            weekRawPoints: weekRaw,
            acuteToChronicRatio: ratio,
            band: band,
            confidence: confidence,
            explanation: explanation
        )
    }

    private static func loadConfidence(historyDays: Int) -> ConfidenceLevel {
        if historyDays >= ScoringConstants.Load.chronicWindowDays { return .high }
        if historyDays >= ScoringConstants.Load.minimumChronicDays { return .medium }
        return .low
    }
}
