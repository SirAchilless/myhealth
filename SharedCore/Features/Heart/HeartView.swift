import SwiftUI

/// Heart section: current HR, resting HR, HRV, cardio fitness — each shown
/// relative to personal baselines with neutral, non-medical language.
struct HeartView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: MyHealthTheme.Spacing.s) {
                switch model.repository.snapshot.heart {
                case .available(let heart):
                    currentHeartRateCard(heart)
                    restingHeartRateCard(heart)
                    hrvCard(heart)
                    cardioFitnessCard(heart)
                    disclaimer
                case .loading:
                    LoadingStateView(label: "Loading heart data…")
                case .unavailable(let reason):
                    UnavailableView(reason: reason)
                    disclaimer
                }
            }
            .padding(.horizontal, MyHealthTheme.Spacing.xs)
        }
        .background(MyHealthTheme.appBackground)
        .navigationTitle("Heart")
    }

    private func currentHeartRateCard(_ heart: HeartSnapshot) -> some View {
        MetricCard(title: "Current HR", systemImage: "heart.fill") {
            if let current = heart.currentHeartRate {
                MetricHeadline(
                    value: "\(Int(current.beatsPerMinute))",
                    label: "bpm",
                    color: .primary
                )
            } else {
                Text("No recent heart-rate sample.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func restingHeartRateCard(_ heart: HeartSnapshot) -> some View {
        MetricCard(title: "Resting HR", systemImage: "figure.stand") {
            if let resting = heart.restingHeartRate {
                VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                    MetricHeadline(value: "\(Int(resting))", label: "bpm", color: .primary)
                    baselineText(value: resting, baseline: heart.restingHeartRateBaseline, unit: "bpm", higherIsWorse: true)
                    if heart.restingHeartRateTrend.count >= 2 {
                        TrendChart(points: heart.restingHeartRateTrend, color: MyHealthTheme.statusGood, unitLabel: "bpm")
                    }
                }
            } else {
                EmptyStateView(message: "Resting heart rate appears after a full day of wear.", systemImage: "figure.stand")
            }
        }
    }

    private func hrvCard(_ heart: HeartSnapshot) -> some View {
        MetricCard(title: "HRV (SDNN)", systemImage: "waveform") {
            if let hrv = heart.latestHRV {
                VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                    MetricHeadline(value: String(format: "%.0f", hrv.milliseconds), label: "ms", color: .primary)
                    baselineText(value: hrv.milliseconds, baseline: heart.hrvBaseline, unit: "ms", higherIsWorse: false)
                    if heart.hrvTrend.count >= 2 {
                        TrendChart(points: heart.hrvTrend, color: MyHealthTheme.accent, unitLabel: "ms")
                    }
                }
            } else {
                EmptyStateView(message: "HRV is measured mainly during sleep and Breath sessions.", systemImage: "waveform")
            }
        }
    }

    private func cardioFitnessCard(_ heart: HeartSnapshot) -> some View {
        MetricCard(title: "Cardio fitness", systemImage: "lungs.fill") {
            if let vo2 = heart.vo2Max {
                VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                    MetricHeadline(
                        value: String(format: "%.1f", vo2),
                        label: "ml/kg · min (estimate)",
                        color: .primary
                    )
                    if let walking = heart.walkingHeartRateAverage {
                        Text("Walking average \(Int(walking)) bpm.")
                            .font(MyHealthTheme.detailText)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                EmptyStateView(
                    message: "Apple estimates cardio fitness after outdoor walks or runs.",
                    systemImage: "lungs"
                )
            }
        }
    }

    private var disclaimer: some View {
        Text("Heart metrics are shown relative to your own recent baseline. They are informational, not medical findings.")
            .font(MyHealthTheme.detailText)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func baselineText(
        value: Double,
        baseline: MetricBaseline?,
        unit: String,
        higherIsWorse: Bool
    ) -> some View {
        if let baseline, baseline.isSufficient {
            if let percent = baseline.percentDifference(value) {
                let percentText = String(format: "%.0f", abs(percent * 100))
                let direction = percent > 0.005 ? "above" : percent < -0.005 ? "below" : "at"
                Text("\(percentText)% \(direction) your recent baseline (\(String(format: "%.0f", baseline.median)) \(unit)).")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Baseline still building (\(baseline?.sampleCount ?? 0) days so far).")
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
    }
}
