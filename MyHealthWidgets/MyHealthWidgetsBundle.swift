import WidgetKit
import SwiftUI

@main
struct MyHealthWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RecoveryWidget()
        SleepWidget()
        LoadWidget()
        EnergyWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let isFresh: Bool
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder, isFresh: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // Hourly refresh budget; the app pushes fresher snapshots whenever it
        // recalculates.
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [currentEntry()], policy: .after(nextUpdate)))
    }

    private func currentEntry() -> SnapshotEntry {
        guard let snapshot = WidgetSnapshotStore.load() else {
            return SnapshotEntry(date: .now, snapshot: nil, isFresh: false)
        }
        return SnapshotEntry(
            date: .now,
            snapshot: snapshot,
            isFresh: WidgetSnapshotStore.isFresh(snapshot)
        )
    }
}

// MARK: - Shared widget view

/// Renders one metric slot across all accessory families. Color never carries
/// meaning alone — every family also shows text.
struct MetricWidgetView: View {
    let title: String
    let icon: String
    let slot: WidgetMetricSlot?
    let isFresh: Bool
    let tint: Color
    let deepLink: URL

    @Environment(\.widgetFamily) private var family

    private var displayText: String {
        guard let slot else { return "—" }
        return isFresh ? slot.valueText : "\(slot.valueText)?"
    }

    private var labelText: String {
        guard let slot, isFresh, !slot.labelText.isEmpty else { return "Open myhealth" }
        return slot.labelText
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.25), lineWidth: 4)
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: icon)
                            .font(.system(size: 10))
                        Text(displayText)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                }
                .containerBackground(for: .widget) { Color.clear }

            case .accessoryInline:
                Label("\(title) \(displayText) · \(labelText)", systemImage: icon)
                    .containerBackground(for: .widget) { Color.clear }

            case .accessoryCorner:
                Text(displayText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .widgetLabel {
                        Label(title, systemImage: icon)
                    }
                    .containerBackground(for: .widget) { Color.clear }

            default: // accessoryRectangular and others
                VStack(alignment: .leading, spacing: 1) {
                    Label(title, systemImage: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(displayText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(labelText)
                        .font(.system(size: 12))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                .containerBackground(for: .widget) { Color.clear }
            }
        }
        .widgetURL(deepLink)
        .accessibilityLabel("\(title): \(displayText), \(labelText)")
    }
}

// MARK: - Widgets

struct RecoveryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MyHealthRecovery", provider: SnapshotProvider()) { entry in
            MetricWidgetView(
                title: "Recovery",
                icon: "heart.text.square",
                slot: entry.snapshot?.recovery,
                isFresh: entry.isFresh,
                tint: .green,
                deepLink: URL(string: "myhealth://recovery")!
            )
        }
        .configurationDisplayName("Recovery")
        .description("Your daily recovery score.")
        .supportedFamilies([
            .accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner,
        ])
    }
}

struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MyHealthSleep", provider: SnapshotProvider()) { entry in
            MetricWidgetView(
                title: "Sleep",
                icon: "bed.double",
                slot: entry.snapshot?.sleep,
                isFresh: entry.isFresh,
                tint: .cyan,
                deepLink: URL(string: "myhealth://sleep")!
            )
        }
        .configurationDisplayName("Sleep")
        .description("Last night's sleep duration and rating.")
        .supportedFamilies([
            .accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner,
        ])
    }
}

struct LoadWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MyHealthLoad", provider: SnapshotProvider()) { entry in
            MetricWidgetView(
                title: "Load",
                icon: "flame",
                slot: entry.snapshot?.load,
                isFresh: entry.isFresh,
                tint: .orange,
                deepLink: URL(string: "myhealth://load")!
            )
        }
        .configurationDisplayName("Load")
        .description("Today's training load.")
        .supportedFamilies([
            .accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner,
        ])
    }
}

struct EnergyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MyHealthEnergy", provider: SnapshotProvider()) { entry in
            MetricWidgetView(
                title: "Energy",
                icon: "bolt.heart",
                slot: entry.snapshot?.energy,
                isFresh: entry.isFresh,
                tint: .mint,
                deepLink: URL(string: "myhealth://energy")!
            )
        }
        .configurationDisplayName("Energy")
        .description("Today's energy estimate.")
        .supportedFamilies([
            .accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner,
        ])
    }
}
