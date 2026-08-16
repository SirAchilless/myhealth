import SwiftUI

/// myhealth design system: semantic colors, typography, spacing, radii.
/// Status colors are never the only signal — every status also renders text.
enum MyHealthTheme {
    // MARK: Color

    /// Primary brand accent (mint green — vitality, not tied to any status).
    static let accent = Color(red: 0.18, green: 0.78, blue: 0.588)

    static let backgroundTop = Color(red: 0.055, green: 0.086, blue: 0.118)
    static let backgroundBottom = Color(red: 0.039, green: 0.063, blue: 0.09)

    static let cardBackground = Color.white.opacity(0.07)
    static let cardStroke = Color.white.opacity(0.10)

    // Status palette (each always paired with a text label).
    static let statusExcellent = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let statusGood = Color(red: 0.35, green: 0.78, blue: 0.95)
    static let statusModerate = Color(red: 0.98, green: 0.80, blue: 0.30)
    static let statusCaution = Color(red: 0.98, green: 0.55, blue: 0.30)
    static let statusLow = Color(red: 0.95, green: 0.38, blue: 0.42)

    static func color(for category: RecoveryCategory) -> Color {
        switch category {
        case .excellent: return statusExcellent
        case .good: return statusGood
        case .moderate: return statusModerate
        case .low: return statusCaution
        case .veryLow: return statusLow
        }
    }

    static func color(for rating: SleepRating) -> Color {
        switch rating {
        case .excellent: return statusExcellent
        case .good: return statusGood
        case .fair: return statusModerate
        case .poor: return statusCaution
        }
    }

    static func color(for band: TrainingLoadBand) -> Color {
        switch band {
        case .recovering: return statusGood
        case .productive: return statusExcellent
        case .high: return statusCaution
        case .buildingHistory: return statusModerate
        }
    }

    static func color(for category: StressCategory) -> Color {
        switch category {
        case .low: return statusExcellent
        case .moderate: return statusModerate
        case .elevated: return statusCaution
        }
    }

    static func color(for band: EnergyBand) -> Color {
        switch band {
        case .low: return statusCaution
        case .moderate: return statusModerate
        case .good: return statusExcellent
        }
    }

    // MARK: Typography

    static let metricNumber = Font.system(size: 34, weight: .bold, design: .rounded)
    static let metricNumberLarge = Font.system(size: 44, weight: .bold, design: .rounded)
    static let metricUnit = Font.system(size: 15, weight: .medium, design: .rounded)
    static let cardTitle = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let bodyText = Font.system(size: 14, weight: .regular, design: .rounded)
    static let detailText = Font.system(size: 12, weight: .regular, design: .rounded)

    // MARK: Layout

    enum Spacing {
        static let xs: CGFloat = 3
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 16
    }

    static let cardCornerRadius: CGFloat = 14
    static let ringLineWidth: CGFloat = 6

    /// Standard card background gradient for the app.
    static var appBackground: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Subtle upward gradient used behind headline metrics.
    static func statusGradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.28), color.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
