import SwiftUI

/// The base card every metric surface is built from: a titled, rounded,
/// high-contrast container that is tappable when a destination is provided.
struct MetricCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.s) {
            Label(title, systemImage: systemImage)
                .font(MyHealthTheme.cardTitle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
        .padding(MyHealthTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MyHealthTheme.cardCornerRadius, style: .continuous)
                .fill(MyHealthTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: MyHealthTheme.cardCornerRadius, style: .continuous)
                        .strokeBorder(MyHealthTheme.cardStroke, lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
    }
}

/// Headline number + label pair used inside cards, e.g. `82` / `Excellent`.
struct MetricHeadline: View {
    let value: String
    let label: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
            Text(value)
                .font(MyHealthTheme.metricNumber)
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(MyHealthTheme.metricUnit)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
