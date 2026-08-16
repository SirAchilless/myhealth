import Foundation
import Combine

enum AppTab: Hashable {
    case today
    case health
    case workouts
    case coach
    case settings
}

enum AppRoute: Hashable {
    case recovery
    case sleep
    case load
    case stress
    case energy
    case heart
}

/// Central navigation + deep-link router. Widgets, App Intents, and in-app
/// cards all route through the same `myhealth://` scheme.
@MainActor
final class AppRouter: ObservableObject {
    /// Set by the app entry point at launch; App Intents use it to steer the
    /// live UI (they run in-process when opening the app).
    static var shared = AppRouter()

    @Published var selectedTab: AppTab = .today
    @Published var healthPath: [AppRoute] = []
    /// Set when a workout should begin (from deep link or App Intent).
    @Published var pendingWorkoutStart: WorkoutKind?

    func handle(url: URL) {
        guard url.scheme == "myhealth" else { return }
        let host = url.host ?? ""
        switch host {
        case "today":
            selectedTab = .today
        case "recovery", "sleep", "load", "stress", "energy", "heart":
            selectedTab = .health
            healthPath = [route(for: host)]
        case "workouts":
            selectedTab = .workouts
        case "workout":
            // myhealth://workout/start?type=running
            if url.path == "/start" {
                let typeRaw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "type" })?
                    .value
                let kind = WorkoutKind(rawValue: typeRaw ?? "") ?? .running
                selectedTab = .workouts
                pendingWorkoutStart = kind
            }
        case "coach":
            selectedTab = .coach
        case "settings":
            selectedTab = .settings
        default:
            selectedTab = .today
        }
    }

    func open(_ route: AppRoute) {
        selectedTab = .health
        healthPath = [route]
    }

    private func route(for host: String) -> AppRoute {
        switch host {
        case "recovery": return .recovery
        case "sleep": return .sleep
        case "load": return .load
        case "stress": return .stress
        case "energy": return .energy
        case "heart": return .heart
        default: return .recovery
        }
    }
}
