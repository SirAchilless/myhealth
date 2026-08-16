import SwiftUI

/// Live workout screen: elapsed time and heart rate dominate; workout-specific
/// metrics follow. Large numerals, high contrast, no typing required.
struct WorkoutSessionView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var controller: WorkoutSessionController
    @Environment(\.dismiss) private var dismiss

    @State private var confirmEnd = false

    init(controller: WorkoutSessionController) {
        self.controller = controller
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MyHealthTheme.Spacing.m) {
                switch controller.phase {
                case .idle, .running, .paused:
                    liveMetrics
                    controls
                case .ended:
                    if let summary = controller.completedSummary {
                        WorkoutSummaryView(summary: summary) {
                            dismiss()
                        }
                    } else {
                        LoadingStateView(label: "Saving workout…")
                    }
                case .failed(let message):
                    EmptyStateView(message: "Workout error: \(message)", systemImage: "exclamationmark.triangle")
                    Button("Dismiss") { dismiss() }
                }
            }
            .padding(.horizontal, MyHealthTheme.Spacing.xs)
        }
        .background(MyHealthTheme.appBackground)
        .navigationTitle(controller.kind.displayName)
        .confirmationDialog(
            "End workout?",
            isPresented: $confirmEnd,
            titleVisibility: .visible
        ) {
            Button("End workout", role: .destructive) {
                controller.end()
            }
            Button("Keep going", role: .cancel) {}
        }
    }

    private var liveMetrics: some View {
        VStack(spacing: MyHealthTheme.Spacing.s) {
            // Elapsed time — the anchor metric.
            VStack(spacing: 0) {
                Text(Formatting.duration(fromSeconds: controller.elapsedSeconds))
                    .font(MyHealthTheme.metricNumberLarge)
                    .foregroundStyle(controller.phase == .paused ? .secondary : .primary)
                    .minimumScaleFactor(0.5)
                    .monospacedDigit()
                Text(controller.phase == .paused ? "Paused" : " ")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(MyHealthTheme.statusModerate)
            }

            // Heart rate + zone.
            HStack(alignment: .bottom, spacing: MyHealthTheme.Spacing.l) {
                VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                    Text(controller.currentHeartRate.map { "\($0)" } ?? "–")
                        .font(MyHealthTheme.metricNumber)
                        .foregroundStyle(MyHealthTheme.statusCaution)
                    Text("BPM")
                        .font(MyHealthTheme.detailText)
                        .foregroundStyle(.secondary)
                }
                if let zone = controller.currentZone {
                    VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                        Text("Z\(zone)")
                            .font(MyHealthTheme.metricNumber)
                            .foregroundStyle(zoneColor(zone))
                        Text("Zone")
                            .font(MyHealthTheme.detailText)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            // Calories + distance.
            HStack(spacing: MyHealthTheme.Spacing.l) {
                Label("\(Int(controller.activeCalories))", systemImage: "flame.fill")
                if controller.kind != .strengthTraining {
                    Label(String(format: "%.2f km", controller.distanceKilometers), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
            }
            .font(MyHealthTheme.bodyText)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    private var controls: some View {
        VStack(spacing: MyHealthTheme.Spacing.s) {
            switch controller.phase {
            case .running:
                Button {
                    controller.pause()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(MyHealthTheme.statusModerate)
            case .paused:
                Button {
                    controller.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(MyHealthTheme.statusExcellent)
            default:
                EmptyView()
            }

            Button(role: .destructive) {
                confirmEnd = true
            } label: {
                Text("End")
                    .font(MyHealthTheme.cardTitle)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonBorderShape(.roundedRectangle(radius: MyHealthTheme.cardCornerRadius))
    }

    private func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return MyHealthTheme.statusGood
        case 2: return MyHealthTheme.statusExcellent
        case 3: return MyHealthTheme.statusModerate
        case 4: return MyHealthTheme.statusCaution
        default: return MyHealthTheme.statusLow
        }
    }
}

/// Post-workout summary, matching the product spec layout.
struct WorkoutSummaryView: View {
    let summary: WorkoutSummary
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: MyHealthTheme.Spacing.m) {
            Text("WORKOUT COMPLETE")
                .font(MyHealthTheme.cardTitle)
                .foregroundStyle(MyHealthTheme.statusExcellent)

            Text(Formatting.duration(fromSeconds: summary.durationMinutes * 60))
                .font(MyHealthTheme.metricNumberLarge)
                .minimumScaleFactor(0.5)

            Text(summary.kind.displayName)
                .font(MyHealthTheme.bodyText)
                .foregroundStyle(.secondary)

            VStack(spacing: MyHealthTheme.Spacing.s) {
                summaryRow("Avg HR", value: summary.averageHeartRate.map { "\(Int($0)) bpm" } ?? "—")
                summaryRow("Calories", value: summary.activeCalories.map { "\(Int($0))" } ?? "—")
                if let km = summary.distanceKilometers, km > 0.05 {
                    summaryRow("Distance", value: String(format: "%.2f km", km))
                }
                summaryRow("Load", value: Formatting.oneDecimal(summary.loadPoints))
            }
            .padding(MyHealthTheme.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: MyHealthTheme.cardCornerRadius)
                    .fill(MyHealthTheme.cardBackground)
            )

            Text(loadMethodNote)
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)

            Button("Done", action: onDone)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
    }

    private var loadMethodNote: String {
        switch summary.loadMethod {
        case .trimp: return "Load computed from heart-rate intensity."
        case .energyEstimate: return "Load estimated from calories (no heart-rate data)."
        case .durationEstimate: return "Load estimated from duration only."
        }
    }

    private func summaryRow(_ name: String, value: String) -> some View {
        HStack {
            Text(name)
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(MyHealthTheme.bodyText.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}
