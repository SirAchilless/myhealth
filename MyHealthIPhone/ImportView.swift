import SwiftUI
import UniformTypeIdentifiers

/// Apple Health export import screen (iPhone builds). Everything the app
/// shows is computed from this import — nothing is read from HealthKit.
struct ImportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false
    @State private var showHowTo = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MyHealthTheme.Spacing.m) {
                    if showHowTo {
                        howToCard
                    }
                    importCard
                    resultCard
                    privacyCard
                }
                .padding(MyHealthTheme.Spacing.m)
            }
            .background(MyHealthTheme.appBackground.ignoresSafeArea())
            .navigationTitle("Import")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.zip, .xml, .data],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                Task { await model.importHealthExport(from: url) }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Sections

    private var howToCard: some View {
        MetricCard(title: "How to get your export", systemImage: "questionmark.circle") {
            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.s) {
                step("1", "Open the Health app on your iPhone.")
                step("2", "Tap your picture (top right), then find “Export All Health Data”.")
                step("3", "Wait for the archive — it can take several minutes.")
                step("4", "In the share sheet, save export.zip to Files.")
                step("5", "Come back here and tap Import below.")
            }
        }
    }

    private var importCard: some View {
        MetricCard(title: "Import", systemImage: "square.and.arrow.down") {
            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.s) {
                Button {
                    showFilePicker = true
                } label: {
                    switch model.importState {
                    case .parsing:
                        HStack {
                            ProgressView()
                            Text("Parsing… this can take a minute for large exports")
                                .font(MyHealthTheme.detailText)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity)
                    default:
                        Label("Choose export.zip or export.xml", systemImage: "doc.badge.plus")
                            .font(MyHealthTheme.cardTitle)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonBorderShape(.roundedRectangle(radius: MyHealthTheme.cardCornerRadius))
                .tint(MyHealthTheme.accent)
                .disabled(isParsing)

                Button {
                    withAnimation { showHowTo.toggle() }
                } label: {
                    Text(showHowTo ? "Hide steps" : "Show export steps")
                        .font(MyHealthTheme.detailText)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        switch model.importState {
        case .ready(let summary):
            MetricCard(title: "Import complete", systemImage: "checkmark.circle.fill") {
                VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                    row("Sleep nights", "\(summary.sleepNightCount)")
                    row("Workouts", "\(summary.workoutCount)")
                    row("HRV days", "\(summary.hrvSampleCount)")
                    row("Resting HR days", "\(summary.restingHeartRateDayCount)")
                    Text("Insights are refreshed. Re-import anytime to bring in newer data.")
                        .font(MyHealthTheme.detailText)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            MetricCard(title: "Import failed", systemImage: "exclamationmark.triangle.fill") {
                Text(message)
                    .font(MyHealthTheme.bodyText)
                    .foregroundStyle(MyHealthTheme.statusCaution)
            }
        default:
            EmptyView()
        }
    }

    private var privacyCard: some View {
        MetricCard(title: "Privacy", systemImage: "lock.shield.fill") {
            Text("Your export stays entirely on this iPhone. myhealth has no network access — nothing is uploaded anywhere.")
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private var isParsing: Bool {
        if case .parsing = model.importState { return true }
        return false
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: MyHealthTheme.Spacing.s) {
            Text(number)
                .font(MyHealthTheme.detailText.weight(.bold))
                .foregroundStyle(MyHealthTheme.accent)
                .frame(width: 18)
            Text(text)
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).font(MyHealthTheme.detailText).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(MyHealthTheme.bodyText.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}
