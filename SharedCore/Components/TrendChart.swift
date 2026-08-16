import SwiftUI
import Charts

/// Compact, watch-sized trend line chart with a VoiceOver-friendly summary.
struct TrendChart: View {
    let points: [TrendPoint]
    var color: Color = MyHealthTheme.accent
    var unitLabel: String = ""

    private var accessibilitySummary: String {
        guard let first = points.first, let last = points.last else {
            return "No trend data available."
        }
        let summary = "Trend over \(points.count) entries, from \(String(format: "%.0f", first.value)) to \(String(format: "%.0f", last.value)) \(unitLabel)."
        if last.value > first.value {
            return summary + " Trending up."
        } else if last.value < first.value {
            return summary + " Trending down."
        }
        return summary + " Flat."
    }

    var body: some View {
        Group {
            if points.count >= 2 {
                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [color.opacity(0.30), color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 56)
            } else {
                Text("Not enough data for a trend yet.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, MyHealthTheme.Spacing.m)
            }
        }
        .accessibilityLabel(accessibilitySummary)
    }
}
