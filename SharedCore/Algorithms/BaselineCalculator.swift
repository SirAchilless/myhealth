import Foundation

/// Robust personal baselines using median and median absolute deviation (MAD).
/// Robust statistics resist the outliers common in wearable data far better
/// than mean ± standard deviation.
enum BaselineCalculator {
    // MARK: Core statistics

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 1 {
            return sorted[count / 2]
        }
        return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
    }

    static func medianAbsoluteDeviation(_ values: [Double], median: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        return median(values.map { abs($0 - median) })
    }

    // MARK: Baseline construction

    /// Builds a baseline from dated samples inside the trailing window ending
    /// at `asOf`. Returns `nil` when no samples exist; the result's
    /// `isSufficient` reports whether enough samples were found.
    static func baseline(
        values: [Double],
        dates: [Date],
        window: BaselineWindow,
        asOf: Date = Date()
    ) -> MetricBaseline? {
        guard values.count == dates.count, !values.isEmpty else { return nil }
        let cutoff = asOf.addingTimeInterval(-Double(window.days) * 24 * 60 * 60)
        var inWindow: [(value: Double, date: Date)] = []
        for (value, date) in zip(values, dates) where date >= cutoff {
            inWindow.append((value, date))
        }
        guard !inWindow.isEmpty else { return nil }
        guard let median = median(inWindow.map(\.value)) else { return nil }
        let mad = medianAbsoluteDeviation(inWindow.map(\.value), median: median) ?? 0
        return MetricBaseline(
            window: window,
            median: median,
            medianAbsoluteDeviation: mad,
            sampleCount: inWindow.count,
            lastObserved: inWindow.map(\.date).max()
        )
    }

    /// Baseline over one value per day (e.g. nightly sleep minutes).
    static func baseline(
        dailyValues: [(day: Date, value: Double)],
        window: BaselineWindow,
        asOf: Date = Date()
    ) -> MetricBaseline? {
        baseline(
            values: dailyValues.map(\.value),
            dates: dailyValues.map(\.day),
            window: window,
            asOf: asOf
        )
    }

    // MARK: Sleep helpers

    /// Personal nightly sleep need: median asleep minutes across recent nights,
    /// clamped to a sane 5–10 hour range, falling back to the default.
    static func personalSleepNeed(nights: [SleepNight], fallbackMinutes: Double) -> Double {
        let minutes = nights
            .prefix(ScoringConstants.Sleep.needBaselineNights)
            .map { $0.breakdown.asleepMinutes }
            .filter { $0 >= ScoringConstants.Sleep.minimumScoreableAsleepMinutes }
        guard let medianMinutes = median(minutes) else { return fallbackMinutes }
        return min(max(medianMinutes, 300), 600)
    }

    /// Median sleep-midpoint (minutes from midnight) across recent nights —
    /// the user's personal schedule anchor.
    static func sleepMidpointBaseline(nights: [SleepNight]) -> Double? {
        let midpoints = nights.compactMap(\.midpointMinutesFromMidnight)
        guard !midpoints.isEmpty else { return nil }
        return median(midpoints)
    }
}
