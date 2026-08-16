import SwiftUI

/// The primary dashboard. Priority order: Recovery, Sleep, Load, Stress,
/// Energy, recommendation. Every card routes to its detail screen.
struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: AppRouter

    #if os(iOS)
    @State private var showImport = false
    #endif

    private var snapshot: HealthSnapshot { model.repository.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: MyHealthTheme.Spacing.s) {
                #if os(iOS)
                if model.needsFirstImport {
                    importCallToAction
                }
                #endif
                recoveryHero
                sleepCard
                loadCard
                stressCard
                energyCard
                if let recommendation = snapshot.recommendation {
                    RecommendationCard(recommendation: recommendation)
                }
                activityFooter
            }
            .padding(.horizontal, MyHealthTheme.Spacing.xs)
            .padding(.bottom, MyHealthTheme.Spacing.m)
        }
        .background(MyHealthTheme.appBackground)
        .navigationTitle("myhealth")
        #if os(iOS)
        .sheet(isPresented: $showImport) {
            ImportView()
                .environmentObject(model)
        }
        #endif
    }

    #if os(iOS)
    /// First-run entry point for the export-driven iPhone build.
    private var importCallToAction: some View {
        Button {
            showImport = true
        } label: {
            MetricCard(title: "Start here", systemImage: "square.and.arrow.down.fill") {
                VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                    Text("Import your Apple Health export")
                        .font(MyHealthTheme.cardTitle)
                        .foregroundStyle(MyHealthTheme.accent)
                    Text("This build reads your health data from an export.zip — no permissions needed. Everything stays on this iPhone.")
                        .font(MyHealthTheme.detailText)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Health export importer")
    }
    #endif

    // MARK: Recovery (hero)

    private var recoveryHero: some View {
        Button {
            router.open(.recovery)
        } label: {
            MetricCard(title: "Recovery", systemImage: "heart.text.square") {
                switch snapshot.recovery {
                case .available(let result):
                    HStack(alignment: .center, spacing: MyHealthTheme.Spacing.m) {
                        MetricRing(
                            progress: Double(result.score) / 100,
                            color: MyHealthTheme.color(for: result.category),
                            systemImage: "heart.fill"
                        )
                        .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                            MetricHeadline(
                                value: "\(result.score)",
                                label: result.category.rawValue,
                                color: MyHealthTheme.color(for: result.category)
                            )
                            ConfidenceBadge(level: result.confidence)
                        }
                    }
                case .loading:
                    LoadingStateView()
                case .unavailable(let reason):
                    UnavailableView(reason: reason)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens recovery details")
    }

    // MARK: Secondary cards

    private var sleepCard: some View {
        Button {
            router.open(.sleep)
        } label: {
            MetricCard(title: "Sleep", systemImage: "bed.double.fill") {
                switch snapshot.sleep {
                case .available(let result):
                    MetricHeadline(
                        value: Formatting.hoursMinutes(fromMinutes: result.night.breakdown.asleepMinutes),
                        label: ratingLabel(result),
                        color: result.rating.map { MyHealthTheme.color(for: $0) } ?? .primary
                    )
                case .loading:
                    LoadingStateView()
                case .unavailable(let reason):
                    UnavailableView(reason: reason)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens sleep details")
    }

    private var loadCard: some View {
        Button {
            router.open(.load)
        } label: {
            MetricCard(title: "Load", systemImage: "flame.fill") {
                switch snapshot.load {
                case .available(let result):
                    MetricHeadline(
                        value: result.todayLoad.map { Formatting.oneDecimal($0) } ?? "0",
                        label: result.band.rawValue,
                        color: MyHealthTheme.color(for: result.band)
                    )
                case .loading:
                    LoadingStateView()
                case .unavailable(let reason):
                    UnavailableView(reason: reason)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens load details")
    }

    private var stressCard: some View {
        Button {
            router.open(.stress)
        } label: {
            MetricCard(title: "Stress", systemImage: "waveform.path.ecg") {
                switch snapshot.stress {
                case .available(let result):
                    MetricHeadline(
                        value: result.category.rawValue,
                        label: "Wellness estimate",
                        color: MyHealthTheme.color(for: result.category)
                    )
                case .loading:
                    LoadingStateView()
                case .unavailable(let reason):
                    UnavailableView(reason: reason)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens stress details")
    }

    private var energyCard: some View {
        Button {
            router.open(.energy)
        } label: {
            MetricCard(title: "Energy", systemImage: "bolt.heart.fill") {
                switch snapshot.energy {
                case .available(let result):
                    MetricHeadline(
                        value: "\(result.score)",
                        label: result.band.rawValue,
                        color: MyHealthTheme.color(for: result.band)
                    )
                case .loading:
                    LoadingStateView()
                case .unavailable(let reason):
                    UnavailableView(reason: reason)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens energy details")
    }

    private var activityFooter: some View {
        HStack(spacing: MyHealthTheme.Spacing.m) {
            Label {
                switch snapshot.stepsToday {
                case .available(let steps): Text("\(steps.formatted()) steps")
                default: Text("— steps")
                }
            } icon: {
                Image(systemName: "figure.walk")
            }
            Label {
                switch snapshot.activeCaloriesToday {
                case .available(let kcal): Text("\(Int(kcal)) cal")
                default: Text("— cal")
                }
            } icon: {
                Image(systemName: "flame")
            }
        }
        .font(MyHealthTheme.detailText)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func ratingLabel(_ result: SleepAnalysisResult) -> String {
        result.rating?.rawValue ?? "Analyzed"
    }
}
