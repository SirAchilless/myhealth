import SwiftUI

/// Energy detail: today's capacity estimate and its inputs.
struct EnergyDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: MyHealthTheme.Spacing.s) {
                switch model.repository.snapshot.energy {
                case .available(let result):
                    MetricCard(title: "Energy", systemImage: "bolt.heart.fill") {
                        VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                            HStack(alignment: .center, spacing: MyHealthTheme.Spacing.m) {
                                MetricRing(
                                    progress: Double(result.score) / 100,
                                    color: MyHealthTheme.color(for: result.band),
                                    systemImage: "bolt.fill"
                                )
                                .frame(width: 52, height: 52)
                                MetricHeadline(
                                    value: "\(result.score)",
                                    label: result.band.rawValue,
                                    color: MyHealthTheme.color(for: result.band)
                                )
                            }
                            ConfidenceBadge(level: result.confidence)
                            Text(result.capacityPhrase)
                                .font(MyHealthTheme.bodyText)
                            Text(result.explanation)
                                .font(MyHealthTheme.detailText)
                                .foregroundStyle(.secondary)
                        }
                    }
                    inputsCard
                case .loading:
                    LoadingStateView(label: "Estimating energy…")
                case .unavailable(let reason):
                    UnavailableView(reason: reason)
                }
            }
            .padding(.horizontal, MyHealthTheme.Spacing.xs)
        }
        .background(MyHealthTheme.appBackground)
        .navigationTitle("Energy")
    }

    private var inputsCard: some View {
        MetricCard(title: "Inputs", systemImage: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.s) {
                inputRow("Recovery", value: model.repository.snapshot.recovery.value.map { "\($0.score)" })
                inputRow("Sleep", value: model.repository.snapshot.sleep.value.flatMap { $0.score.map { "\($0)" } })
                inputRow("Load today", value: model.repository.snapshot.load.value?.todayLoad.map { Formatting.oneDecimal($0) })
                Text("Energy blends recovery, sleep, and how much you've already trained today. It's a wellness estimate, not a measurement.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func inputRow(_ name: String, value: String?) -> some View {
        HStack {
            Text(name)
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—")
                .font(MyHealthTheme.detailText.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}
