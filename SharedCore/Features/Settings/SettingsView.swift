import SwiftUI

/// Settings: permissions, preferences, privacy, data management, about.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                permissionsSection
                preferencesSection
                privacySection
                dataSection
                aboutSection
                #if DEBUG
                developerSection
                #endif
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: Sections

    private var permissionsSection: some View {
        #if os(watchOS)
        Section("Health") {
            HStack {
                Text("Health access")
                Spacer()
                switch model.repository.authorizationStatus() {
                case .granted: Text("Allowed").foregroundStyle(.green)
                case .denied: Text("Denied").foregroundStyle(.orange)
                case .notDetermined: Text("Ask me").foregroundStyle(.secondary)
                case .healthKitUnavailable: Text("Unavailable").foregroundStyle(.secondary)
                }
            }
            Text("myhealth reads heart, sleep, activity, and workout data from Apple Health, and saves workouts you record. Manage access in Settings › Health.")
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
        #else
        Section("Data source") {
            HStack {
                Text("Source")
                Spacer()
                Text(model.needsFirstImport ? "No import yet" : "Apple Health export")
                    .foregroundStyle(.secondary)
            }
            Text("This build runs entirely on an Apple Health export you import — no Health permissions and no network access.")
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
        #endif
    }

    private var preferencesSection: some View {
        Section("Preferences") {
            Toggle("Haptics", isOn: hapticsBinding)
            Toggle("Metric units", isOn: metricBinding)

            NavigationLink("Recovery & training") {
                TrainingPreferencesView()
            }
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            NavigationLink("Privacy & data") { PrivacyView() }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            NavigationLink("Manage data") { DataManagementView() }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion).foregroundStyle(.secondary)
            }
            Text("myhealth is a wellness app. It does not provide medical advice, diagnosis, or treatment.")
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
    }

    #if DEBUG
    private var developerSection: some View {
        Section("Developer (debug)") {
            if model.activeMockScenario == nil {
                Text("Mock data is disabled.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            } else {
                Label("Mock: \(model.activeMockScenario!.displayName)", systemImage: "testtube.2")
                    .foregroundStyle(.orange)
            }
            ForEach(MockScenario.allCases) { scenario in
                Button(scenario.displayName) {
                    model.selectMockScenario(
                        model.activeMockScenario == scenario ? nil : scenario
                    )
                }
            }
            Text("Scenario applies after the app restarts. Mock data exists only in debug builds.")
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
    }
    #endif

    // MARK: Bindings

    private var hapticsBinding: Binding<Bool> {
        Binding(
            get: { model.settingsStore.settings.hapticsEnabled },
            set: { model.settingsStore.settings.hapticsEnabled = $0 }
        )
    }

    private var metricBinding: Binding<Bool> {
        Binding(
            get: { model.settingsStore.settings.metricUnits },
            set: { model.settingsStore.settings.metricUnits = $0 }
        )
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// Training- and recovery-related preferences.
struct TrainingPreferencesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Sleep") {
                VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.s) {
                    Text("Nightly target: \(Int(model.settingsStore.settings.sleepNeedHours)) h")
                    Slider(
                        value: Binding(
                            get: { model.settingsStore.settings.sleepNeedHours },
                            set: { model.settingsStore.settings.sleepNeedHours = $0 }
                        ),
                        in: 5...10, step: 0.5
                    )
                    .tint(MyHealthTheme.accent)
                    Text("Used until a personal baseline from your last 14 nights takes over.")
                        .font(MyHealthTheme.detailText)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Training") {
                Picker("Preferred activity", selection: activityBinding) {
                    ForEach(AppSettings.PreferredActivity.allCases) { activity in
                        Text(activity.displayName).tag(activity)
                    }
                }
                Stepper("Days per week: \(model.settingsStore.settings.trainingDaysPerWeek)",
                        value: trainingDaysBinding,
                        in: 1...7)
            }
            Section("Heart rate") {
                VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.s) {
                    Text("Max HR: \(maxHRText)")
                        .font(MyHealthTheme.bodyText)
                    Slider(
                        value: Binding(
                            get: {
                                Double(model.settingsStore.settings.maxHeartRateOverride ?? Int(LoadEngine.maxHeartRate(ageYears: nil, override: nil).rounded()))
                            },
                            set: { model.settingsStore.settings.maxHeartRateOverride = Int($0) }
                        ),
                        in: 150...210, step: 1
                    )
                    .tint(MyHealthTheme.accent)
                    Text("Leave near the estimate unless you know your true maximum. Zones and load use this.")
                        .font(MyHealthTheme.detailText)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Recovery & training")
    }

    private var activityBinding: Binding<AppSettings.PreferredActivity> {
        Binding(
            get: { model.settingsStore.settings.preferredActivity },
            set: { model.settingsStore.settings.preferredActivity = $0 }
        )
    }

    private var trainingDaysBinding: Binding<Int> {
        Binding(
            get: { model.settingsStore.settings.trainingDaysPerWeek },
            set: { model.settingsStore.settings.trainingDaysPerWeek = $0 }
        )
    }

    private var maxHRText: String {
        let value = model.repository.maxHeartRateValue
        return "\(Int(value.rounded())) bpm"
    }
}

/// Privacy explanation (plain language, per product spec).
struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.m) {
                section("Local first",
                       "All analysis runs on your watch. myhealth has no servers, no accounts, and makes no network requests.")
                section("What we read",
                       "Heart rate, resting heart rate, heart-rate variability, sleep stages, workouts, steps, and active energy — from Apple Health on this device.")
                section("What we write",
                       "Only workouts you record in myhealth are saved to Apple Health.")
                section("What stays",
                       "Daily summaries (scores and the inputs behind them) are stored on-device with SwiftData. Raw health samples are never copied. Widgets see derived scores only.")
                section("AI",
                       "None. Coach answers are generated by rules on your watch. If cloud AI is ever added, it will be opt-in with clear disclosure of anything transmitted.")
                section("No logging of health data",
                       "Diagnostics never include raw health measurements or personal identifiers.")
                section("Delete anytime",
                       "Settings › Data › Delete removes every score, summary, and workout myhealth stored. Apple Health data itself is untouched.")
            }
            .padding(MyHealthTheme.Spacing.m)
        }
        .background(MyHealthTheme.appBackground)
        .navigationTitle("Privacy")
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
            Text(title)
                .font(MyHealthTheme.cardTitle)
                .foregroundStyle(MyHealthTheme.accent)
            Text(body)
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
    }
}

/// Data management: retention summary + full local wipe.
struct DataManagementView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmDelete = false
    @State private var deleted = false

    var body: some View {
        List {
            #if os(iOS)
            Section("Apple Health export") {
                NavigationLink("Import or re-import export…") {
                    ImportView()
                }
                Text("Insights on this build come entirely from your imported export.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
            #endif
            Section("Stored locally") {
                row("Daily summaries", "Scores and inputs, long-term (up to 2 years)")
                row("Workout cache", "Your last workouts for fast history (up to 1,000)")
                row("Widget snapshot", "Latest derived scores, replaces on refresh")
                #if os(iOS)
                row("Health import", "Bounded aggregates of your last Apple Health export")
                #endif
            }
            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text(deleted ? "Deleted" : "Delete all myhealth data")
                }
                .disabled(deleted)
                Text("Removes myhealth's summaries, cached workouts, and widget data from this watch. Your Apple Health data is not modified.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Manage data")
        .confirmationDialog(
            "Delete all myhealth data on this watch?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                model.deleteAllLocalData()
                deleted = true
                Haptics.success(enabled: model.hapticsEnabled)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(_ name: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
            Text(name).font(MyHealthTheme.bodyText)
            Text(detail)
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
    }
}
