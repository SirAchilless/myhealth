import SwiftUI

/// Stress detail: category, index, explanation. Always framed as a wellness
/// estimate — never a diagnosis.
struct StressDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: MyHealthTheme.Spacing.s) {
                switch model.repository.snapshot.stress {
                case .available(let result):
                    MetricCard(title: "Current", systemImage: "waveform.path.ecg") {
                        VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                            MetricHeadline(
                                value: result.category.rawValue,
                                label: "Index \(Int(result.index.rounded())) of 100",
                                color: MyHealthTheme.color(for: result.category)
                            )
                            ConfidenceBadge(level: result.confidence)
                            MetricGauge(
                                progress: result.index / 100,
                                color: MyHealthTheme.color(for: result.category)
                            )
                            Text(result.explanation)
                                .font(MyHealthTheme.detailText)
                                .foregroundStyle(.secondary)
                        }
                    }
                    breathingCard
                case .loading:
                    LoadingStateView(label: "Checking stress signals…")
                case .unavailable(let reason):
                    UnavailableView(reason: reason)
                    breathingCard
                }
            }
            .padding(.horizontal, MyHealthTheme.Spacing.xs)
        }
        .background(MyHealthTheme.appBackground)
        .navigationTitle("Stress")
    }

    private var breathingCard: some View {
        MetricCard(title: "A moment of calm", systemImage: "leaf") {
            Text("Slow breathing can help. Breathe in for 4, out for 6, for a minute or two.")
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
    }
}
