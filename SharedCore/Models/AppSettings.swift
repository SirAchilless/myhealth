import Foundation

/// User preferences. Persisted as JSON in standard UserDefaults — never to
/// HealthKit, never off-device.
struct AppSettings: Codable, Equatable {
    enum PreferredActivity: String, Codable, CaseIterable, Identifiable {
        case running
        case walking
        case cycling
        case strengthTraining
        case other

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .running: return "Running"
            case .walking: return "Walking"
            case .cycling: return "Cycling"
            case .strengthTraining: return "Strength"
            case .other: return "Other"
            }
        }
    }

    /// Personal nightly sleep target in hours. Used until a personal baseline
    /// (14-night median) takes over.
    var sleepNeedHours: Double = 8.0

    /// Typical training days per week (used by coach guidance).
    var trainingDaysPerWeek: Int = 4

    var preferredActivity: PreferredActivity = .running

    var hapticsEnabled: Bool = true

    var metricUnits: Bool = true

    /// Optional manual maximum-heart-rate override (bpm). When absent, the
    /// Tanaka estimate 208 − 0.7 × age is used.
    var maxHeartRateOverride: Int?

    /// Categories the user opted into for local notifications.
    var dailySummaryNotificationEnabled: Bool = false

    static let `default` = AppSettings()

    static let storageKey = "myhealth.appSettings.v1"
}

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: AppSettings.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings.default
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: AppSettings.storageKey)
        }
    }
}
