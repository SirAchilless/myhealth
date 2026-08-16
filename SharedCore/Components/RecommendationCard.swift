import SwiftUI

/// The daily coach recommendation shown at the bottom of Today.
struct RecommendationCard: View {
    let recommendation: CoachRecommendation

    private var color: Color {
        switch recommendation.tone {
        case .train: return MyHealthTheme.statusExcellent
        case .moderate: return MyHealthTheme.statusGood
        case .recover: return MyHealthTheme.statusCaution
        case .buildData: return MyHealthTheme.statusModerate
        }
    }

    private var icon: String {
        switch recommendation.tone {
        case .train: return "bolt.heart"
        case .moderate: return "figure.cooldown"
        case .recover: return "leaf"
        case .buildData: return "hourglass"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: MyHealthTheme.Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                Text(recommendation.title)
                    .font(MyHealthTheme.cardTitle)
                    .foregroundStyle(color)
                Text(recommendation.detail)
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(MyHealthTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MyHealthTheme.cardCornerRadius, style: .continuous)
                .fill(MyHealthTheme.statusGradient(color))
        )
        .accessibilityElement(children: .combine)
    }
}
