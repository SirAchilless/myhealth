import SwiftUI

/// Workouts tab: start a workout (watchOS) and review history (all platforms).
/// On iPhone builds the history comes from the imported Apple Health export.
struct WorkoutsListView: View {
    @EnvironmentObject private var model: AppModel

    #if os(watchOS)
    @EnvironmentObject private var router: AppRouter
    @State private var activeSession: WorkoutSessionController?
    @State private var showPicker = false
    #endif

    var body: some View {
        #if os(watchOS)
        NavigationStack {
            content
                .navigationTitle("Workouts")
                .navigationDestination(isPresented: Binding(
                    get: { activeSession != nil },
                    set: { if !$0 { activeSession = nil } }
                )) {
                    if let controller = activeSession {
                        WorkoutSessionView(controller: controller)
                    }
                }
                .sheet(isPresented: $showPicker) {
                    WorkoutTypePickerView { kind in
                        showPicker = false
                        beginWorkout(kind: kind)
                    }
                }
                .onChange(of: router.pendingWorkoutStart) { _, kind in
                    guard let kind else { return }
                    router.pendingWorkoutStart = nil
                    beginWorkout(kind: kind)
                }
        }
        #else
        NavigationStack {
            content
                .navigationTitle("Workouts")
        }
        #endif
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: MyHealthTheme.Spacing.s) {
                #if os(watchOS)
                startButton
                #else
                if model.needsFirstImport {
                    EmptyStateView(
                        message: "Your workouts appear here after you import an Apple Health export.",
                        systemImage: "square.and.arrow.down"
                    )
                }
                #endif
                history
            }
            .padding(.horizontal, MyHealthTheme.Spacing.xs)
        }
        .background(MyHealthTheme.appBackground)
    }

    #if os(watchOS)
    private var startButton: some View {
        Button {
            showPicker = true
        } label: {
            Label("Start Workout", systemImage: "figure.run")
                .font(MyHealthTheme.cardTitle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MyHealthTheme.Spacing.s)
        }
        .buttonBorderShape(.roundedRectangle(radius: MyHealthTheme.cardCornerRadius))
        .tint(MyHealthTheme.accent)
    }

    private func beginWorkout(kind: WorkoutKind) {
        let repository = model.repository
        let controller = WorkoutSessionController(
            kind: kind,
            hapticsEnabled: { [weak model] in model?.hapticsEnabled ?? true },
            maxHeartRate: { [weak repository] in repository?.maxHeartRateValue ?? 190 },
            restingHeartRate: { [weak repository] in repository?.cachedRestingHeartRate },
            onSave: { [weak model] summary in
                PersistenceStore.shared.upsertWorkout(summary)
                Task { await model?.repository.refresh() }
            }
        )
        activeSession = controller
        controller.start()
    }
    #endif

    private var history: some View {
        MetricCard(title: "History", systemImage: "clock.arrow.circlepath") {
            switch model.repository.snapshot.workouts {
            case .available(let workouts):
                if workouts.isEmpty {
                    EmptyStateView(
                        message: "No workouts yet. Recorded sessions from myhealth and other apps appear here.",
                        systemImage: "figure.walk"
                    )
                } else {
                    VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.m) {
                        ForEach(workouts.prefix(10)) { workout in
                            workoutRow(workout)
                        }
                    }
                }
            case .loading:
                LoadingStateView()
            case .unavailable(let reason):
                UnavailableView(reason: reason)
            }
        }
    }

    private func workoutRow(_ workout: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
            HStack {
                Label(workout.kind.displayName, systemImage: workout.kind.systemImage)
                    .font(MyHealthTheme.cardTitle)
                Spacer()
                Text(Formatting.oneDecimal(workout.loadPoints))
                    .font(MyHealthTheme.detailText.weight(.semibold))
                    .foregroundStyle(MyHealthTheme.accent)
            }
            Text(rowDetail(workout))
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func rowDetail(_ workout: WorkoutSummary) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        var parts = [formatter.string(from: workout.start), Formatting.duration(fromSeconds: workout.durationMinutes * 60)]
        if let hr = workout.averageHeartRate {
            parts.append("\(Int(hr)) bpm")
        }
        if let km = workout.distanceKilometers, km > 0.05 {
            parts.append(String(format: "%.1f km", km))
        }
        return parts.joined(separator: " · ")
    }
}
