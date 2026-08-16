import SwiftUI

/// Concise onboarding: welcome → data-source explanation (HealthKit on
/// watchOS, Health-export import on iPhone) → optional personalization →
/// baseline state.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    @State private var step: Step = .welcome
    @State private var requestingHealth = false
    @State private var sleepNeedHours: Double = 8.0
    @State private var trainingDays: Double = 4
    @State private var preferredActivity: AppSettings.PreferredActivity = .running

    enum Step: Int, CaseIterable {
        case welcome
        case permissions
        case personalization
        case buildingBaseline
    }

    var body: some View {
        TabView(selection: $step) {
            welcome.tag(Step.welcome)
            #if os(watchOS)
            permissions.tag(Step.permissions)
            #else
            importGuide.tag(Step.permissions)
            #endif
            personalization.tag(Step.personalization)
            buildingBaseline.tag(Step.buildingBaseline)
        }
        #if os(watchOS)
        .tabViewStyle(.verticalPage)
        #endif
        .background(MyHealthTheme.appBackground)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: MyHealthTheme.Spacing.m) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 44))
                .foregroundStyle(MyHealthTheme.accent)
            Text("myhealth")
                .font(MyHealthTheme.metricNumber)
            VStack(spacing: MyHealthTheme.Spacing.xs) {
                Text("Understand your day.")
                Text("Train smarter.")
                Text("Recover better.")
            }
            .font(MyHealthTheme.bodyText)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Button("Get Started") {
                Haptics.click(enabled: model.hapticsEnabled)
                step = .permissions
            }
            .tint(MyHealthTheme.accent)
        }
        .padding(.horizontal, MyHealthTheme.Spacing.m)
    }

    private var permissions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.m) {
                Label("Health access", systemImage: "heart.fill")
                    .font(MyHealthTheme.cardTitle)
                    .foregroundStyle(MyHealthTheme.accent)

                Text("myhealth works entirely on your watch. To build your daily picture it reads:")
                    .font(MyHealthTheme.bodyText)

                VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.s) {
                    rationale("heart.fill", "Heart", "Current, resting, and variability for recovery and stress.")
                    rationale("bed.double.fill", "Sleep", "Stages and timing for your sleep score.")
                    rationale("figure.run", "Workouts", "Duration, heart rate, and calories for training load.")
                    rationale("flame.fill", "Activity", "Steps and energy for your daily context.")
                }

                Text("Nothing leaves your devices. Workouts you record are saved to Apple Health.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)

                Button {
                    requestHealthAccess()
                } label: {
                    if requestingHealth {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Allow Health Access")
                            .font(MyHealthTheme.cardTitle)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonBorderShape(.roundedRectangle(radius: MyHealthTheme.cardCornerRadius))
                .tint(MyHealthTheme.accent)
                .disabled(requestingHealth)
            }
            .padding(.horizontal, MyHealthTheme.Spacing.m)
        }
    }

    private var personalization: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.m) {
                Label("Personalize (optional)", systemImage: "person.crop.circle")
                    .font(MyHealthTheme.cardTitle)
                    .foregroundStyle(MyHealthTheme.accent)

                VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.s) {
                    Text("Sleep target: \(Int(sleepNeedHours)) h")
                        .font(MyHealthTheme.bodyText)
                    Slider(value: $sleepNeedHours, in: 5...10, step: 0.5)
                        .tint(MyHealthTheme.accent)
                }

                VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.s) {
                    Text("Training days / week: \(Int(trainingDays))")
                        .font(MyHealthTheme.bodyText)
                    Slider(value: $trainingDays, in: 1...7, step: 1)
                        .tint(MyHealthTheme.accent)
                }

                VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.s) {
                    Text("Preferred activity")
                        .font(MyHealthTheme.bodyText)
                    Picker("Preferred activity", selection: $preferredActivity) {
                        ForEach(AppSettings.PreferredActivity.allCases) { activity in
                            Text(activity.displayName).tag(activity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("You can change all of this later in Settings. Your sleep target auto-adjusts as myhealth learns your normal nights.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)

                Button("Continue") {
                    model.settingsStore.settings.sleepNeedHours = sleepNeedHours
                    model.settingsStore.settings.trainingDaysPerWeek = Int(trainingDays)
                    model.settingsStore.settings.preferredActivity = preferredActivity
                    step = .buildingBaseline
                    Task {
                        await model.repository.refresh()
                    }
                }
                .font(MyHealthTheme.cardTitle)
                .frame(maxWidth: .infinity)
                .buttonBorderShape(.roundedRectangle(radius: MyHealthTheme.cardCornerRadius))
                .tint(MyHealthTheme.accent)
            }
            .padding(.horizontal, MyHealthTheme.Spacing.m)
        }
    }

    private var buildingBaseline: some View {
        VStack(spacing: MyHealthTheme.Spacing.m) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(MyHealthTheme.accent)
            Text("Ready to build your baseline.")
                .font(MyHealthTheme.cardTitle)
            #if os(watchOS)
            Text("Keep wearing your Apple Watch — to bed too. Your insights will improve as myhealth learns your normal patterns over the next week.")
                .font(MyHealthTheme.bodyText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            #else
            Text("Import your Apple Health export from the Today screen whenever you're ready — myhealth will compute your recovery, sleep, load, stress, and energy from it, entirely on this iPhone.")
                .font(MyHealthTheme.bodyText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            #endif
            Button("Start using myhealth") {
                Haptics.success(enabled: model.hapticsEnabled)
                model.completeOnboarding()
            }
            .tint(MyHealthTheme.accent)
        }
        .padding(.horizontal, MyHealthTheme.Spacing.m)
    }

    #if !os(watchOS)
    /// iPhone (sideload) onboarding: this build reads an Apple Health export
    /// instead of HealthKit — no permissions required.
    private var importGuide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.m) {
                Label("Bring your health data", systemImage: "square.and.arrow.down.fill")
                    .font(MyHealthTheme.cardTitle)
                    .foregroundStyle(MyHealthTheme.accent)

                Text("This build of myhealth works entirely from an Apple Health export — no Health permissions needed:")
                    .font(MyHealthTheme.bodyText)

                VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.s) {
                    rationale("heart.text.square", "Insights", "Recovery, sleep, training load, stress, and energy — computed from your export on this iPhone.")
                    rationale("lock.shield.fill", "Private", "Your export never leaves the device. No network access at all.")
                    rationale("arrow.triangle.2.circlepath", "Fresh data", "Re-import anytime to see newer data.")
                }

                Text("Next: export your data from the Health app (profile → Export All Health Data), save export.zip to Files, then import it from the Today screen.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)

                Button("Continue") {
                    step = .personalization
                }
                .font(MyHealthTheme.cardTitle)
                .frame(maxWidth: .infinity)
                .buttonBorderShape(.roundedRectangle(radius: MyHealthTheme.cardCornerRadius))
                .tint(MyHealthTheme.accent)
            }
            .padding(.horizontal, MyHealthTheme.Spacing.m)
        }
    }
    #endif

    // MARK: Helpers

    private func rationale(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: MyHealthTheme.Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(MyHealthTheme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(MyHealthTheme.bodyText.weight(.semibold))
                Text(detail)
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func requestHealthAccess() {
        requestingHealth = true
        Task {
            await model.repository.requestAuthorization()
            requestingHealth = false
            Haptics.success(enabled: model.hapticsEnabled)
            step = .personalization
        }
    }
}
