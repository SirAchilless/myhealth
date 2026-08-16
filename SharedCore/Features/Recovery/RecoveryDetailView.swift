import SwiftUI

/// Recovery detail: score, factors, missing data, and trend.
struct RecoveryDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: MyHealthTheme.Spacing.s) {
                switch model.repository.snapshot.recovery {
                case .available(let result):
                    scoreSection(result)
                    factorsSection(result)
                    if !result.missingData.isEmpty {
                        missingSection(result)
                    }
                    trendSection
                    Text(result.explanation)
                        .font(MyHealthTheme.detailText)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .loading:
                    LoadingStateView(label: "Analyzing recovery…")
                case .unavailable(let reason):
                    UnavailableView(reason: reason)
                    trendSection
                }
            }
            .padding(.horizontal, MyHealthTheme.Spacing.xs)
        }
        .background(MyHealthTheme.appBackground)
        .navigationTitle("Recovery")
    }

    private func scoreSection(_ result: RecoveryResult) -> some View {
        MetricCard(title: "Score", systemImage: "heart.text.square") {
            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                MetricHeadline(
                    value: "\(result.score)",
                    label: result.category.rawValue,
                    color: MyHealthTheme.color(for: result.category)
                )
                ConfidenceBadge(level: result.confidence)
                Text(result.explanation)
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func factorsSection(_ result: RecoveryResult) -> some View {
        MetricCard(title: "Factors", systemImage: "list.bullet") {
            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.m) {
                if result.positiveFactors.isEmpty && result.negativeFactors.isEmpty {
                    Text("All signals are close to your baseline today.")
                        .font(MyHealthTheme.detailText)
                        .foregroundStyle(.secondary)
                }
                ForEach(result.positiveFactors) { factor in
                    factorRow(factor, color: MyHealthTheme.statusExcellent, sign: "+")
                }
                ForEach(result.negativeFactors) { factor in
                    factorRow(factor, color: MyHealthTheme.statusCaution, sign: "−")
                }
            }
        }
    }

    private func factorRow(_ factor: RecoveryFactor, color: Color, sign: String) -> some View {
        VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
            HStack {
                Text("\(sign) \(factor.metric.displayName)")
                    .font(MyHealthTheme.cardTitle)
                    .foregroundStyle(color)
                Spacer()
                Text(percentText(factor))
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
            Text(factor.detail)
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func percentText(_ factor: RecoveryFactor) -> String {
        let points = Int(abs(factor.contribution * 25).rounded())
        return "\(points) pt"
    }

    private func missingSection(_ result: RecoveryResult) -> some View {
        MetricCard(title: "Missing data", systemImage: "questionmark.circle") {
            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                ForEach(result.missingData) { metric in
                    Label(metric.displayName, systemImage: "minus.circle")
                        .font(MyHealthTheme.detailText)
                        .foregroundStyle(.secondary)
                }
                Text("Scores improve as these sources build history.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trendSection: some View {
        MetricCard(title: "Trend", systemImage: "chart.line.uptrend.xyaxis") {
            heartTrend
        }
    }

    @ViewBuilder
    private var heartTrend: some View {
        if case .available(let heart) = model.repository.snapshot.heart {
            TrendChart(points: heart.recoveryTrend, color: MyHealthTheme.accent)
        } else {
            Text("Trend appears after a few scored days.")
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
    }
}
