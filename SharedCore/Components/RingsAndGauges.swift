import SwiftUI

/// Circular progress ring (0–1). Always paired with a text value by callers.
struct MetricRing: View {
    /// Progress clamped to 0–1.
    let progress: Double
    var color: Color = MyHealthTheme.accent
    var lineWidth: CGFloat = MyHealthTheme.ringLineWidth
    var systemImage: String? = nil

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .accessibilityHidden(true) // callers provide textual values
    }
}

/// Inline gauge bar (0–1) for compact contexts.
struct MetricGauge: View {
    let progress: Double
    var color: Color = MyHealthTheme.accent
    var height: CGFloat = 6

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: max(geo.size.width * clamped, height))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Small label + gauge row, e.g. "Deep 1h 12m" with a share bar.
struct StageGaugeRow: View {
    let name: String
    let minutes: Double
    let totalMinutes: Double
    var color: Color = MyHealthTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
            HStack {
                Text(name)
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Formatting.hoursMinutes(fromMinutes: minutes))
                    .font(MyHealthTheme.detailText.weight(.semibold))
            }
            MetricGauge(
                progress: totalMinutes > 0 ? minutes / totalMinutes : 0,
                color: color
            )
        }
        .accessibilityElement(children: .combine)
    }
}
