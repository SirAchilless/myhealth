import Foundation

/// Snapshot of derived scores shared with the widget extension via the App
/// Group. Contains only display-ready derived values — never raw health data.
///
/// NOTE: this file is intentionally duplicated in MyHealthWidgets/ so the two
/// targets stay independent. The two copies must be kept in sync (see
/// docs/ARCHITECTURE.md).
struct WidgetMetricSlot: Codable, Equatable {
    let valueText: String
    let labelText: String
    let generatedAt: Date
}

struct WidgetSnapshot: Codable, Equatable {
    let generatedAt: Date
    var recovery: WidgetMetricSlot?
    var sleep: WidgetMetricSlot?
    var load: WidgetMetricSlot?
    var energy: WidgetMetricSlot?

    static let placeholder = WidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 0),
        recovery: WidgetMetricSlot(valueText: "—", labelText: "", generatedAt: Date(timeIntervalSince1970: 0)),
        sleep: nil,
        load: nil,
        energy: nil
    )
}

enum WidgetSnapshotStore {
    static let appGroupID = "group.com.myhealth.shared"
    static let storageKey = "myhealth.widgetSnapshot.v1"

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// True when the snapshot is recent enough to display (2 hours).
    static func isFresh(_ snapshot: WidgetSnapshot, asOf: Date = Date()) -> Bool {
        asOf.timeIntervalSince(snapshot.generatedAt) < 2 * 60 * 60
    }
}
