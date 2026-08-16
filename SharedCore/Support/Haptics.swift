import Foundation

#if canImport(WatchKit)
import WatchKit

/// Meaningful haptics only — start/pause/end of workouts, confirmations, and
/// important state changes. Never on passive scrolling.
enum Haptics {
    static func play(_ type: WKHapticType, enabled: Bool) {
        guard enabled else { return }
        WKInterfaceDevice.current().play(type)
    }

    static func success(enabled: Bool) { play(.success, enabled: enabled) }
    static func start(enabled: Bool) { play(.start, enabled: enabled) }
    static func stop(enabled: Bool) { play(.stop, enabled: enabled) }
    static func click(enabled: Bool) { play(.click, enabled: enabled) }
    static func retry(enabled: Bool) { play(.retry, enabled: enabled) }
}

#elseif canImport(UIKit)
import UIKit

/// iOS equivalent using UIKit feedback generators.
enum Haptics {
    static func success(enabled: Bool) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func retry(enabled: Bool) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func start(enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func stop(enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func click(enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
#endif
