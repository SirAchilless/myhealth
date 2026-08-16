import Foundation
import AppIntents

/// App Intents exposed to Siri, Shortcuts, and Smart Stack suggestions.
/// Deliberately small: navigation + workout start only.

struct OpenTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Today in myhealth"
    static var description = IntentDescription("Shows your daily health overview.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.handle(url: URL(string: "myhealth://today")!)
        return .result()
    }
}

struct OpenRecoveryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Recovery in myhealth"
    static var description = IntentDescription("Shows your recovery score and factors.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.handle(url: URL(string: "myhealth://recovery")!)
        return .result()
    }
}

struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Workout in myhealth"
    static var description = IntentDescription("Begins recording a workout.")
    static var openAppWhenRun = true

    @Parameter(title: "Type", default: .running)
    var workoutType: WorkoutTypeAppEnum

    @MainActor
    func perform() async throws -> some IntentResult {
        let url = URL(string: "myhealth://workout/start?type=\(workoutType.rawValue)")!
        AppRouter.shared.handle(url: url)
        return .result()
    }
}

enum WorkoutTypeAppEnum: String, AppEnum {
    case running
    case walking
    case cycling
    case strengthTraining
    case other

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workout Type")

    static var caseDisplayRepresentations: [WorkoutTypeAppEnum: DisplayRepresentation] {
        [
            .running: "Running",
            .walking: "Walking",
            .cycling: "Cycling",
            .strengthTraining: "Strength Training",
            .other: "Other",
        ]
    }
}

/// Shortcuts surfaced in Siri/Smart Stack suggestions.
struct MyHealthShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTodayIntent(),
            phrases: ["How am I doing in \(.applicationName)"],
            shortTitle: "Today",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: OpenRecoveryIntent(),
            phrases: ["Show my recovery in \(.applicationName)"],
            shortTitle: "Recovery",
            systemImageName: "heart.text.square"
        )
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: ["Start a workout with \(.applicationName)"],
            shortTitle: "Start Workout",
            systemImageName: "figure.run"
        )
    }
}
