import SwiftUI

/// Sleep detail: duration, score, stages, consistency, deficit, trend.
struct SleepDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: MyHealthTheme.Spacing.s) {
                switch model.repository.snapshot.sleep {
                case .available(let result):
                    headerSection(result)
                    stagesSection(result)
                    componentsSection(result)
                    if let deficit = result.deficitMinutes, deficit > 0 {
                        MetricCard(title: "Sleep shortfall", systemImage: "moon.dust") {
                            Text("\(Formatting.hoursMinutes(fromMinutes: Double(deficit))) under your target. A short recovery window tonight helps.")
                                .font(MyHealthTheme.detailText)
                                .foregroundStyle(.secondary)
                        }
                    }
                    trendSection
                case .loading:
                    LoadingStateView(label: "Analyzing sleep…")
                case .unavailable(let reason):
                    UnavailableView(reason: reason)
                }
            }
            .padding(.horizontal, MyHealthTheme.Spacing.xs)
        }
        .background(MyHealthTheme.appBackground)
        .navigationTitle("Sleep")
    }

    private func headerSection(_ result: SleepAnalysisResult) -> some View {
        MetricCard(title: "Last night", systemImage: "bed.double.fill") {
            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                MetricHeadline(
                    value: Formatting.hoursMinutes(fromMinutes: result.night.breakdown.asleepMinutes),
                    label: headlineLabel(result),
                    color: result.rating.map { MyHealthTheme.color(for: $0) } ?? .primary
                )
                if let score = result.score {
                    ConfidenceBadge(level: result.confidence)
                    Text("Sleep score \(score) of 100.")
                        .font(MyHealthTheme.detailText)
                        .foregroundStyle(.secondary)
                }
                if let bedtime = result.night.bedtime, let wake = result.night.wakeTime {
                    Text("\(timeText(bedtime)) → \(timeText(wake))")
                        .font(MyHealthTheme.detailText)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stagesSection(_ result: SleepAnalysisResult) -> some View {
        MetricCard(title: "Stages", systemImage: "chart.bar.fill") {
            let breakdown = result.night.breakdown
            let total = max(breakdown.asleepMinutes, 1)
            VStack(spacing: MyHealthTheme.Spacing.s) {
                StageGaugeRow(name: "Deep", minutes: breakdown.deepMinutes, totalMinutes: total, color: MyHealthTheme.statusExcellent)
                StageGaugeRow(name: "Core", minutes: breakdown.coreMinutes, totalMinutes: total, color: MyHealthTheme.statusGood)
                StageGaugeRow(name: "REM", minutes: breakdown.remMinutes, totalMinutes: total, color: MyHealthTheme.statusModerate)
                StageGaugeRow(name: "Awake", minutes: breakdown.awakeMinutes, totalMinutes: total, color: MyHealthTheme.statusCaution)
            }
        }
    }

    private func componentsSection(_ result: SleepAnalysisResult) -> some View {
        MetricCard(title: "Score breakdown", systemImage: "slider.horizontal.3") {
            VStack(spacing: MyHealthTheme.Spacing.m) {
                if result.components.isEmpty {
                    Text("No breakdown available.")
                        .font(MyHealthTheme.detailText)
                        .foregroundStyle(.secondary)
                }
                ForEach(result.components) { component in
                    VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                        HStack {
                            Text(component.name)
                                .font(MyHealthTheme.cardTitle)
                            Spacer()
                            Text("\(Int(component.achieved * 100))%")
                                .font(MyHealthTheme.detailText)
                                .foregroundStyle(.secondary)
                        }
                        MetricGauge(progress: component.achieved, color: MyHealthTheme.accent)
                        Text(component.detail)
                            .font(MyHealthTheme.detailText)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var trendSection: some View {
        MetricCard(title: "Sleep trend", systemImage: "chart.line.uptrend.xyaxis") {
            if case .available(let heart) = model.repository.snapshot.heart {
                TrendChart(points: heart.sleepTrend, color: MyHealthTheme.statusGood, unitLabel: "minutes")
            } else {
                Text("Trend appears after a few nights.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func headlineLabel(_ result: SleepAnalysisResult) -> String {
        result.rating?.rawValue ?? "Analyzed"
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
