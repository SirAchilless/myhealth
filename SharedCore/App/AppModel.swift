import Foundation
import Combine

/// Root dependency container + app state. Owns the repository, settings, and
/// onboarding state; view models and views read through it.
///
/// - watchOS: data comes from HealthKit live.
/// - iOS (sideload builds): data comes from an imported Apple Health export
///   (`ImportedHealthDataProvider`) — no HealthKit permission needed.
@MainActor
final class AppModel: ObservableObject {
    let settingsStore: AppSettingsStore

    /// Published so an import can swap in a new repository and refresh the UI.
    @Published private(set) var repository: HealthDataRepository

    #if os(iOS)
    /// Persistence for the last imported Apple Health export.
    private(set) var importStore: HealthImportStore

    enum ImportState: Equatable {
        case idle
        case parsing
        case ready(ImportSummary)
        case failed(String)
    }

    @Published var importState: ImportState = .idle

    /// True until the user has imported a health export (drives the Today CTA).
    var needsFirstImport: Bool {
        #if DEBUG
        return !importStore.hasImport && activeMockScenario == nil
        #else
        return !importStore.hasImport
        #endif
    }
    #endif

    private static let onboardingKey = "myhealth.onboarded.v1"

    @Published var isOnboarded: Bool {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: Self.onboardingKey) }
    }

    init() {
        let settingsStore = AppSettingsStore()
        self.settingsStore = settingsStore

        #if os(iOS)
        let importStore = HealthImportStore()
        self.importStore = importStore
        #endif

        let provider: HealthDataProviding
        #if os(watchOS)
        #if DEBUG
        let mock = UserDefaults.standard
            .string(forKey: Self.mockScenarioKey)
            .flatMap(MockScenario.init(rawValue:))
        provider = mock.map(MockHealthDataProvider.init(scenario:)) ?? HealthKitManager()
        #else
        provider = HealthKitManager()
        #endif
        #else
        #if DEBUG
        let mock = UserDefaults.standard
            .string(forKey: Self.mockScenarioKey)
            .flatMap(MockScenario.init(rawValue:))
        if let mock {
            provider = MockHealthDataProvider(scenario: mock)
        } else {
            provider = ImportedHealthDataProvider(export: importStore.load())
        }
        #else
        provider = ImportedHealthDataProvider(export: importStore.load())
        #endif
        #endif

        self.repository = HealthDataRepository(
            provider: provider,
            persistence: .shared,
            settings: { [weak settingsStore] in settingsStore?.settings ?? .default }
        )
        self.isOnboarded = UserDefaults.standard.bool(forKey: Self.onboardingKey)
    }

    var settings: AppSettings { settingsStore.settings }

    var hapticsEnabled: Bool { settingsStore.settings.hapticsEnabled }

    func completeOnboarding() {
        isOnboarded = true
        Task { await repository.refresh() }
    }

    func deleteAllLocalData() {
        #if os(iOS)
        importStore.delete()
        #endif
        repository.deleteLocalData()
    }

    #if os(iOS)
    /// Imports an Apple Health export (export.zip or export.xml), rebuilds the
    /// repository on the parsed data, and refreshes all insights.
    func importHealthExport(from url: URL) async {
        importState = .parsing
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let settingsStore = self.settingsStore
            let (parsed, summary) = try await Task.detached(priority: .userInitiated) {
                try AppleHealthExportParser.parse(fileData: data)
            }.value

            importStore.save(parsed)
            let provider = ImportedHealthDataProvider(export: parsed)
            repository = HealthDataRepository(
                provider: provider,
                persistence: .shared,
                settings: { [weak settingsStore] in settingsStore?.settings ?? .default }
            )
            Haptics.success(enabled: hapticsEnabled)
            importState = .ready(summary)
            await repository.refresh()
        } catch {
            importState = .failed(error.localizedDescription)
        }
    }
    #endif

    // MARK: Developer (DEBUG-only mock scenario selection)

    #if DEBUG
    static let mockScenarioKey = "myhealth.mockScenario"

    var activeMockScenario: MockScenario? {
        MockScenario(rawValue: UserDefaults.standard.string(forKey: Self.mockScenarioKey) ?? "")
    }

    /// Switching scenarios requires an app relaunch to rebuild the provider.
    func selectMockScenario(_ scenario: MockScenario?) {
        let defaults = UserDefaults.standard
        if let scenario {
            defaults.set(scenario.rawValue, forKey: Self.mockScenarioKey)
        } else {
            defaults.removeObject(forKey: Self.mockScenarioKey)
        }
    }
    #endif
}

extension HealthDataRepository {
    /// Local-data deletion also clears the widget snapshot so no stale
    /// derived scores survive the reset.
    func deleteLocalData() {
        PersistenceStore.shared.deleteAllLocalData()
        if let defaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroupID) {
            defaults.removeObject(forKey: WidgetSnapshotStore.storageKey)
        }
    }
}
