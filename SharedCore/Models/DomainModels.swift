import Foundation

/// Structured errors used across myhealth (see docs/ARCHITECTURE.md §Error handling).
enum MyHealthError: Error, Equatable {
    case healthKitUnavailable
    case healthAuthorizationDenied
    case insufficientHealthData
    case sensorUnavailable
    case workoutUnavailable
    case persistenceFailure
    case backgroundRefreshUnavailable
    case unknownError
}

/// Why a metric cannot be shown. Every health surface resolves to one of these.
enum UnavailabilityReason: Equatable, Hashable {
    case permissionDenied
    case noData
    case insufficientHistory
    case stale
    case unsupported
    case error(String)
}

/// The state machine every myhealth metric renders through (docs/HEALTH_DATA.md).
/// A value is only ever shown in the `.available` case — never fabricated.
enum HealthDataState<Value> {
    case loading
    case available(Value)
    case unavailable(UnavailabilityReason)

    var value: Value? {
        if case .available(let value) = self { return value }
        return nil
    }

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

extension HealthDataState: Equatable where Value: Equatable {}

/// A single heart-rate measurement in beats per minute.
struct HeartRateSample: Equatable, Hashable, Codable {
    let beatsPerMinute: Double
    let date: Date
}

/// A single heart-rate-variability measurement (SDNN, milliseconds) from HealthKit.
struct HRVSample: Equatable, Hashable, Codable {
    let milliseconds: Double
    let date: Date
}

/// One point in a trend chart.
struct TrendPoint: Identifiable, Equatable, Hashable, Codable {
    let date: Date
    let value: Double
    var id: Date { date }
}

enum BaselineWindow: Int, CaseIterable, Codable {
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30

    var days: Int { rawValue }
}

/// Robust (median/MAD) personal baseline for one metric over a rolling window.
struct MetricBaseline: Equatable {
    let window: BaselineWindow
    let median: Double
    /// Median absolute deviation — used as a robust spread estimate.
    let medianAbsoluteDeviation: Double
    let sampleCount: Int
    /// Last observation date used for the baseline (staleness checks).
    let lastObserved: Date?

    /// Robust z-score: (x − median) / (1.4826 × MAD). `nil` when spread is
    /// degenerate or the baseline has too few samples to trust.
    func robustZScore(_ x: Double) -> Double? {
        guard isSufficient else { return nil }
        let robustSigma = 1.4826 * medianAbsoluteDeviation
        guard robustSigma > 0.0001 else { return nil }
        return (x - median) / robustSigma
    }

    /// Signed percent difference from the baseline median, e.g. −0.12 = 12% below.
    func percentDifference(_ x: Double) -> Double? {
        guard abs(median) > 0.0001 else { return nil }
        return (x - median) / median
    }

    var isSufficient: Bool {
        sampleCount >= ScoringConstants.Baseline.minimumSamples
    }
}

enum Day {
    static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func dayIdentifier(_ date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }
}

enum Formatting {
    static func hoursMinutes(fromMinutes minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return String(format: "%dh %02dm", total / 60, total % 60)
    }

    static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func duration(fromSeconds seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
