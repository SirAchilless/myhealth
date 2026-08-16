import SwiftUI

/// Compact pill that names a status in text (color is decorative only).
struct HealthStatusBadge: View {
    let text: String
    var color: Color = MyHealthTheme.statusGood

    var body: some View {
        Text(text)
            .font(MyHealthTheme.detailText.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(0.22))
            )
            .foregroundStyle(color)
            .accessibilityLabel("Status: \(text)")
    }
}

/// Pill showing how much to trust a generated score.
struct ConfidenceBadge: View {
    let level: ConfidenceLevel

    private var color: Color {
        switch level {
        case .high: return MyHealthTheme.statusExcellent
        case .medium: return MyHealthTheme.statusGood
        case .low: return MyHealthTheme.statusModerate
        case .insufficientData: return MyHealthTheme.statusCaution
        }
    }

    var body: some View {
        HealthStatusBadge(text: "Confidence: \(level.rawValue)", color: color)
    }
}
