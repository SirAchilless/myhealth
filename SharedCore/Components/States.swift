import SwiftUI

/// Loading state for a metric card.
struct LoadingStateView: View {
    var label: String = "Loading…"

    var body: some View {
        HStack(spacing: MyHealthTheme.Spacing.s) {
            ProgressView()
            Text(label)
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Empty/missing-data state with an actionable explanation.
struct EmptyStateView: View {
    let message: String
    var systemImage: String = "chart.dashed"

    var body: some View {
        VStack(spacing: MyHealthTheme.Spacing.s) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(message)
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MyHealthTheme.Spacing.l)
        .accessibilityElement(children: .combine)
    }
}

/// Renders any `UnavailabilityReason` with honest, non-alarming copy.
struct UnavailableView: View {
    let reason: UnavailabilityReason

    private var content: (icon: String, message: String) {
        switch reason {
        case .permissionDenied:
            return (
                "lock.shield",
                "Health access is off. Allow Heart, Sleep, and Workout data for myhealth in Apple Health settings to see this."
            )
        case .noData:
            return ("moon.zzz", "No data yet. This appears after your watch records it.")
        case .insufficientHistory:
            return (
                "calendar.badge.clock",
                "We're building your baseline. Keep wearing your Apple Watch — insights improve over the next week."
            )
        case .stale:
            return ("clock.badge.exclamationmark", "This data hasn't updated recently. It will refresh when your watch syncs.")
        case .unsupported:
            return ("sensor.tag.radiowaves.forward.slash", "This metric isn't available on this device.")
        case .error(let message):
            return ("exclamationmark.triangle", "Couldn't load this right now. \(message)")
        }
    }

    var body: some View {
        EmptyStateView(message: content.message, systemImage: content.icon)
    }
}

/// Generic switch over `HealthDataState` for card bodies.
struct HealthDataStateView<Value, Content: View>: View {
    let state: HealthDataState<Value>
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading:
            LoadingStateView()
        case .available(let value):
            content(value)
        case .unavailable(let reason):
            UnavailableView(reason: reason)
        }
    }
}
