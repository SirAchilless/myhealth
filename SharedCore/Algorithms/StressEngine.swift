import Foundation

/// Inputs for one analysis window (default 10 minutes of heart-rate samples).
struct StressWindowInput: Equatable {
    let start: Date
    let minutes: Double
    let averageHeartRate: Double
    /// True when the window falls inside a recorded sleep period — stress is
    /// damped there because sleep HR patterns are noisier proxies.
    var isSleepWindow: Bool = false
}

/// Computes the **myhealth Stress** wellness estimate (0–100 index; Low /
/// Moderate / Elevated). This is an app-generated wellness signal based on
/// heart-rate elevation and HRV suppression relative to personal baselines.
/// It is explicitly NOT a medical or psychological assessment.
enum StressEngine {
    /// - Parameters:
    ///   - windows: recent windows, oldest first; the newest is "now".
    ///   - restingBaseline: personal resting-HR baseline median.
    ///   - latestHRV: most recent HRV sample.
    ///   - hrvBaseline: personal HRV baseline.
    /// - Returns: `nil` when there are no windows at all.
    static func compute(
        windows: [StressWindowInput],
        restingBaseline: Double?,
        latestHRV: HRVSample?,
        hrvBaseline: MetricBaseline?,
        at date: Date = Date()
    ) -> StressResult? {
        guard let newest = windows.last else { return nil }

        // HRV suppression relative to the personal baseline.
        var hrvSuppression: Double?
        if let hrv = latestHRV, let baseline = hrvBaseline, baseline.median > 0 {
            hrvSuppression = min(max(1 - hrv.milliseconds / baseline.median, 0), 1)
        }

        let usable = windows.suffix(6) // ~last hour of windows
        var indices: [Double] = []
        var usedHeartPressure = false
        var usedHRVSuppression = false

        for window in usable {
            var components: [(value: Double, weight: Double)] = []
            if let resting = restingBaseline, resting > 0 {
                let elevation = window.averageHeartRate - resting
                let pressure = min(max(elevation / ScoringConstants.Stress.heartElevationScaleBPM, 0), 1)
                components.append((pressure, ScoringConstants.Stress.weightHeartPressure))
                usedHeartPressure = true
            }
            if let suppression = hrvSuppression {
                components.append((suppression, ScoringConstants.Stress.weightHRVSuppression))
                usedHRVSuppression = true
            }
            guard !components.isEmpty else { continue }
            let weightSum = components.reduce(0) { $0 + $1.weight }
            let raw = components.reduce(0) { $0 + $1.value * $1.weight } / weightSum
            let damped = window.isSleepWindow
                ? raw * ScoringConstants.Stress.sleepWindowDampening
                : raw
            indices.append(damped * 100)
        }

        guard !indices.isEmpty else {
            // Windows exist but no baseline to compare against.
            return StressResult(
                category: .moderate,
                index: 50,
                confidence: .low,
                explanation: "Not enough baseline data to estimate stress yet. This improves as your personal baselines build.",
                assessedAt: date
            )
        }

        // Weight the newest window most heavily (recency matters for "now").
        let weightedIndex: Double = {
            var total = 0.0
            var weights = 0.0
            for (offset, index) in indices.reversed().enumerated() {
                let weight = offset == 0 ? 3.0 : 1.0
                total += index * weight
                weights += weight
            }
            return total / weights
        }()

        let clamped = min(max(weightedIndex, 0), 100)
        let category = StressCategory(index: clamped)

        let confidence: ConfidenceLevel
        switch (usedHeartPressure, usedHRVSuppression) {
        case (true, true): confidence = .high
        case (true, false), (false, true): confidence = .medium
        case (false, false): confidence = .insufficientData
        }

        let explanation = explanation(for: category, newest: newest, hrvSuppression: hrvSuppression)

        return StressResult(
            category: category,
            index: clamped,
            confidence: confidence,
            explanation: explanation,
            assessedAt: date
        )
    }

    private static func explanation(
        for category: StressCategory,
        newest: StressWindowInput,
        hrvSuppression: Double?
    ) -> String {
        var driver: String
        if let suppression = hrvSuppression, suppression > 0.2 {
            driver = "HRV below your baseline is the main signal"
        } else {
            driver = "heart rate close to your baseline"
        }
        return "Wellness estimate — \(category.rawValue.lowercased()). Based on \(driver). Not a medical measurement."
    }

    // MARK: Window building

    /// Buckets heart-rate samples into fixed windows (oldest first).
    enum WindowBuilder {
        static func windows(
            from samples: [HeartRateSample],
            windowMinutes: Double,
            isSleepWindow: (Date) -> Bool
        ) -> [StressWindowInput] {
            guard !samples.isEmpty else { return [] }
            let sorted = samples.sorted { $0.date < $1.date }
            let windowSeconds = windowMinutes * 60
            var result: [StressWindowInput] = []
            var windowStart = sorted[0].date
            var current: [HeartRateSample] = []

            func flush() {
                guard !current.isEmpty else { return }
                let average = current.map(\.beatsPerMinute).reduce(0, +) / Double(current.count)
                let minutes = current.last!.date.timeIntervalSince(windowStart) / 60
                result.append(StressWindowInput(
                    start: windowStart,
                    minutes: max(minutes, 1),
                    averageHeartRate: average,
                    isSleepWindow: isSleepWindow(windowStart)
                ))
            }

            for sample in sorted {
                if sample.date.timeIntervalSince(windowStart) >= windowSeconds {
                    flush()
                    windowStart = sample.date
                    current = [sample]
                } else {
                    current.append(sample)
                }
            }
            flush()
            return result
        }
    }
}
