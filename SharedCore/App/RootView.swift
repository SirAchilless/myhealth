import SwiftUI

/// App root: onboarding gate + tab shell + lifecycle-driven refresh.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.isOnboarded {
                mainTabs
            } else {
                OnboardingView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard model.isOnboarded, phase == .active else { return }
            Task { await model.repository.refresh() }
        }
        .task {
            guard model.isOnboarded else { return }
            await model.repository.refresh()
        }
    }

    private var mainTabs: some View {
        TabView(selection: $router.selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(AppTab.today)

            HealthHubView()
                .tabItem { Label("Health", systemImage: "heart.fill") }
                .tag(AppTab.health)

            WorkoutsListView()
                .tabItem { Label("Workouts", systemImage: "figure.run") }
                .tag(AppTab.workouts)

            CoachView()
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right.fill") }
                .tag(AppTab.coach)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
    }
}
