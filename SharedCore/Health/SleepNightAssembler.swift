import Foundation

/// Assembles raw sleep-stage intervals into `SleepNight`s.
///
/// Handles two real-world wrinkles of HealthKit sleep data:
/// 1. Multiple sources (Apple Watch + iPhone) can report overlapping intervals
///    for the same night — per-stage intervals are unioned before summing so
///    minutes are never double-counted.
/// 2. Naps are separated from the main night — a night is a cluster of samples
///    not separated by more than `separationGapHours`.
enum SleepNightAssembler {
    /// Minimum total asleep minutes for a cluster to count as a night.
    static let minimumNightAsleepMinutes: Double = 45
    /// Hours of gap that separate two clusters.
    static let separationGapHours: Double = 3

    /// Groups samples into nights, oldest first. A night is identified by the
    /// calendar day on which it *ended* (the morning the user woke up).
    static func nights(from samples: [SleepSample], calendar: Calendar = .current) -> [SleepNight] {
        let sorted = samples.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        // Split into clusters separated by large gaps.
        var clusters: [[SleepSample]] = []
        var current: [SleepSample] = [sorted[0]]
        for sample in sorted.dropFirst() {
            let gapHours = sample.start.timeIntervalSince(current[current.count - 1].end) / 3600
            if gapHours > separationGapHours {
                clusters.append(current)
                current = [sample]
            } else {
                current.append(sample)
            }
        }
        clusters.append(current)

        // Assemble each cluster, then keep meaningful nights only.
        return clusters
            .map { assemble(cluster: $0, calendar: calendar) }
            .compactMap { night -> SleepNight? in
                guard night.breakdown.asleepMinutes >= minimumNightAsleepMinutes else {
                    return nil
                }
                return night
            }
            .sorted { $0.date < $1.date }
    }

    /// The most recent night that ended within `hours` of now.
    static func lastNight(from nights: [SleepNight], within hours: Double = 20, asOf now: Date = Date()) -> SleepNight? {
        nights
            .filter { night in
                guard let wake = night.wakeTime else { return false }
                return now.timeIntervalSince(wake) <= hours * 3600
            }
            .last
    }

    // MARK: - Internals

    private static func assemble(cluster: [SleepSample], calendar: Calendar) -> SleepNight {
        var breakdown = SleepStageBreakdown()
        var starts: [Date] = []
        var ends: [Date] = []

        for stage in SleepStageKind.allCases {
            let intervals = cluster
                .filter { $0.stage == stage }
                .map { (start: $0.start, end: $0.end) }
            let minutes = unionMinutes(intervals)
            switch stage {
            case .rem: breakdown.remMinutes = minutes
            case .core: breakdown.coreMinutes = minutes
            case .deep: breakdown.deepMinutes = minutes
            case .awake: breakdown.awakeMinutes = minutes
            case .inBed: breakdown.inBedMinutes = minutes
            case .unspecifiedAsleep: breakdown.unspecifiedMinutes = minutes
            }
        }

        let asleepIntervals = cluster
            .filter { $0.stage != .inBed }
            .map { (start: $0.start, end: $0.end) }
        let inBedIntervals = cluster
            .filter { $0.stage == .inBed }
            .map { (start: $0.start, end: $0.end) }

        // Bedtime/wake from the asleep span when available (more meaningful
        // than time-in-bed), else from the in-bed span.
        let anchorIntervals = asleepIntervals.isEmpty ? inBedIntervals : asleepIntervals
        starts = anchorIntervals.map(\.start)
        ends = anchorIntervals.map(\.end)

        // If no in-bed data exists, approximate time-in-bed by the union of
        // all recorded intervals so efficiency remains scoreable.
        if breakdown.inBedMinutes == 0 {
            let all = cluster.map { (start: $0.start, end: $0.end) }
            breakdown.inBedMinutes = unionMinutes(all)
            if starts.isEmpty {
                starts = all.map(\.start)
                ends = all.map(\.end)
            }
        }

        let bedtime = starts.min()
        let wakeTime = ends.max()
        // Night identity = the morning the cluster ends.
        let anchorDay = wakeTime ?? bedtime ?? Date()

        return SleepNight(
            date: calendar.startOfDay(for: anchorDay),
            bedtime: bedtime,
            wakeTime: wakeTime,
            breakdown: breakdown
        )
    }

    /// Total minutes covered by the union of intervals (overlap-safe).
    private static func unionMinutes(_ intervals: [(start: Date, end: Date)]) -> Double {
        guard !intervals.isEmpty else { return 0 }
        let sorted = intervals.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var rangeStart = sorted[0].start
        var rangeEnd = sorted[0].end
        for interval in sorted.dropFirst() {
            if interval.start <= rangeEnd {
                rangeEnd = max(rangeEnd, interval.end)
            } else {
                total += rangeEnd.timeIntervalSince(rangeStart)
                rangeStart = interval.start
                rangeEnd = interval.end
            }
        }
        total += rangeEnd.timeIntervalSince(rangeStart)
        return total / 60
    }
}
