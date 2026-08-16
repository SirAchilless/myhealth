import Foundation
import Combine

/// Everything the Heart screen shows, plus baseline-relative context.
struct HeartSnapshot: Equatable {
    var currentHeartRate: HeartRateSample?
    var restingHeartRate: Double?
    var restingHeartRateBaseline: MetricBaseline?
    var latestHRV: HRVSample?
    var hrvBaseline: MetricBaseline?
    var vo2Max: Double?
    var walkingHeartRateAverage: Double?

    var recoveryTrend: [TrendPoint] = []
    var hrvTrend: [TrendPoint] = []
    var restingHeartRateTrend: [TrendPoint] = []
    var sleepTrend: [TrendPoint] = []
    var loadTrend: [TrendPoint] = []
}

/// The complete set of states the UI renders for the current day.
struct HealthSnapshot: Equatable {
    var recovery: HealthDataState<RecoveryResult> = .loading
    var sleep: HealthDataState<SleepAnalysisResult> = .loading
    var load: HealthDataState<LoadResult> = .loading
    var stress: HealthDataState<StressResult> = .loading
    var energy: HealthDataState<EnergyResult> = .loading
    var heart: HealthDataState<HeartSnapshot> = .loading
    var workouts: HealthDataState<[WorkoutSummary]> = .loading
    var stepsToday: HealthDataState<Int> = .loading
    var activeCaloriesToday: HealthDataState<Double> = .loading
    var recommendation: CoachRecommendation?
    var lastRefreshed: Date?
}

/// Orchestrates the data pipeline:
/// HealthKit → repository (normalize/caches) → engines → published snapshot.
///
/// Guarantees:
/// - One `refresh()` in flight at a time; extra calls coalesce.
/// - Each metric resolves independently — one failing query never blanks
///   other metrics.
/// - No polling. Refresh happens on activation, on HealthKit observer
///   callbacks (while running), and after workouts.
@MainActor
final class HealthDataRepository: ObservableObject {
    @Published private(set) var snapshot = HealthSnapshot()

    private let provider: HealthDataProviding
    private let persistence: PersistenceStore
    private let settings: () -> AppSettings
    private var isRefreshing = false
    private var pendingRefresh = false
    private var observing = false

    init(
        provider: HealthDataProviding,
        persistence: PersistenceStore,
        settings: @escaping () -> AppSettings
    ) {
        self.provider = provider
        self.persistence = persistence
        self.settings = settings
    }

    // MARK: Public API

    func requestAuthorization() async {
        _ = try? await provider.requestAuthorization()
    }

    func authorizationStatus() -> HealthAuthorizationStatus {
        provider.authorizationStatus()
    }

    // Cached identity/heart facts the workout controller needs synchronously.
    private(set) var cachedAgeYears: Double?
    private(set) var cachedRestingHeartRate: Double?

    /// Max HR with the user's override applied (Tanaka estimate otherwise).
    var maxHeartRateValue: Double {
        LoadEngine.maxHeartRate(ageYears: cachedAgeYears, override: settings().maxHeartRateOverride)
    }

    func refresh() async {
        if isRefreshing {
            pendingRefresh = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        installObserverIfNeeded()

        let status = provider.authorizationStatus()
        let denied = (status == .denied)

        // MARK: Gather raw data (each section independent).

        let hrvSamples = (try? await provider.hrvSamples(days: 35)) ?? []
        let restingSamples = (try? await provider.restingHeartRateSamples(days: 35)) ?? []
        let sleepSamples = (try? await provider.sleepSamples(nights: 21)) ?? []
        let todayStart = Calendar.current.startOfDay(for: Date())
        let heartSamples = (try? await provider.heartRateSamples(
            from: todayStart.addingTimeInterval(-12 * 3600),
            to: Date()
        )) ?? []
        let rawWorkouts = (try? await provider.workouts(days: 35)) ?? []
        let steps = (try? await provider.stepCount(on: Date())) ?? nil
        let activeCalories = (try? await provider.activeEnergyKilocalories(on: Date())) ?? nil
        let vo2Max = try? await provider.latestVO2Max()
        let walkingHR = try? await provider.latestWalkingHeartRateAverage()
        let birthDate = provider.dateOfBirth()

        // MARK: Baselines.

        let hrvBaseline = BaselineCalculator.baseline(
            values: hrvSamples.map(\.milliseconds),
            dates: hrvSamples.map(\.date),
            window: ScoringConstants.Baseline.preferredWindow
        )
        let restingDaily = Dictionary(grouping: restingSamples, by: { Day.dayIdentifier($0.date) })
            .compactMapValues { samples -> HeartRateSample? in
                samples.max(by: { $0.date < $1.date })
            }
        let restingSorted = restingDaily.values.sorted { $0.date < $1.date }
        let restingBaseline = BaselineCalculator.baseline(
            values: restingSorted.map(\.beatsPerMinute),
            dates: restingSorted.map(\.date),
            window: ScoringConstants.Baseline.preferredWindow
        )

        // MARK: Sleep.

        let nights = SleepNightAssembler.nights(from: sleepSamples)
        let nightHistory = nights.dropLast() // everything before last night
        let personalNeed = BaselineCalculator.personalSleepNeed(
            nights: Array(nightHistory),
            fallbackMinutes: settings().sleepNeedHours * 60
        )
        let midpointBaseline = BaselineCalculator.sleepMidpointBaseline(nights: Array(nightHistory))

        let lastNight = SleepNightAssembler.lastNight(from: nights)

        var sleepResult: SleepAnalysisResult?
        if denied {
            snapshot.sleep = .unavailable(.permissionDenied)
        } else if let lastNight {
            let analysis = SleepAnalyzer.analyze(
                night: lastNight,
                personalNeedMinutes: personalNeed,
                timingBaselineMinutes: midpointBaseline
            )
            sleepResult = analysis
            snapshot.sleep = .available(analysis)
        } else {
            snapshot.sleep = .unavailable(.noData)
        }

        // MARK: Workouts + load.

        let ageYears: Double? = birthDate.map { date in
            Double(Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 30)
        }
        cachedAgeYears = ageYears
        cachedRestingHeartRate = restingBaseline?.median ?? restingSorted.last?.beatsPerMinute
        let maxHR = LoadEngine.maxHeartRate(
            ageYears: ageYears,
            override: settings().maxHeartRateOverride
        )
        let restingMedian = restingBaseline?.median ?? restingSorted.last?.beatsPerMinute

        let workoutSummaries = rawWorkouts.map { raw in
            LoadEngine.workoutSummary(
                kind: raw.kind,
                start: raw.start,
                end: raw.end,
                averageHeartRate: raw.averageHeartRate,
                activeCalories: raw.activeCalories,
                distanceKilometers: raw.distanceKilometers,
                restingHeartRate: restingMedian,
                maxHeartRate: maxHR,
                recordedByMyHealth: raw.recordedByMyHealth
            )
        }

        // Per-day load sums (excluding today — today's workouts arrive separately).
        var dailyLoadHistory: [LoadDailyValue] = []
        for offset in 1...34 {
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            let dayID = Day.dayIdentifier(day)
            let points = workoutSummaries
                .filter { Day.dayIdentifier($0.start) == dayID }
                .reduce(0) { $0 + $1.loadPoints }
            dailyLoadHistory.append(LoadDailyValue(day: day, points: points))
        }

        let todayWorkouts = workoutSummaries.filter { $0.start >= todayStart }
        let loadResult = LoadEngine.compute(
            today: Date(),
            todayWorkouts: todayWorkouts,
            history: dailyLoadHistory
        )
        snapshot.load = denied ? .unavailable(.permissionDenied) : .available(loadResult)

        // MARK: Recovery.

        let latestHRV = hrvSamples.last(where: { $0.date >= todayStart.addingTimeInterval(-36 * 3600) })
            ?? hrvSamples.last
        let latestResting = restingSorted.last(where: { $0.date >= todayStart.addingTimeInterval(-36 * 3600) })
            ?? restingSorted.last
        let timingDeviation = lastNight.flatMap { night in
            SleepAnalyzer.timingDeviation(night: night, timingBaselineMinutes: midpointBaseline)
        }

        var recoveryResult: RecoveryResult?
        if denied {
            snapshot.recovery = .unavailable(.permissionDenied)
        } else {
            let input = RecoveryInput(
                date: Date(),
                latestHRV: latestHRV,
                hrvBaseline: hrvBaseline,
                latestRestingHeartRate: latestResting?.beatsPerMinute,
                restingHeartRateBaseline: restingBaseline,
                lastNightAsleepMinutes: lastNight.map { $0.breakdown.asleepMinutes },
                personalSleepNeedMinutes: personalNeed,
                sleepTimingDeviationMinutes: timingDeviation,
                acuteToChronicRatio: loadResult.acuteToChronicRatio
            )
            let result = RecoveryEngine.compute(input)
            recoveryResult = result
            snapshot.recovery = result.hasScore
                ? .available(result)
                : .unavailable(.insufficientHistory)
        }

        // MARK: Stress.

        var stressResult: StressResult?
        if denied {
            snapshot.stress = .unavailable(.permissionDenied)
        } else {
            let sleepRanges = nights.compactMap { night -> (Date, Date)? in
                guard let bedtime = night.bedtime, let wake = night.wakeTime else { return nil }
                return (bedtime, wake)
            }
            let windows = StressEngine.WindowBuilder.windows(
                from: heartSamples,
                windowMinutes: ScoringConstants.Stress.windowMinutes
            ) { date in
                sleepRanges.contains { date >= $0.0 && date <= $1.0 }
            }
            let result = StressEngine.compute(
                windows: windows,
                restingBaseline: restingBaseline?.median,
                latestHRV: latestHRV,
                hrvBaseline: hrvBaseline
            )
            stressResult = result
            snapshot.stress = result.map { .available($0) } ?? .unavailable(.noData)
        }

        // MARK: Energy.

        let energyResult = EnergyEngine.compute(
            recovery: recoveryResult,
            sleep: sleepResult,
            load: loadResult
        )
        snapshot.energy = energyResult.map { .available($0) } ?? .unavailable(.insufficientHistory)

        // MARK: Heart + trends.

        var heart = HeartSnapshot()
        heart.currentHeartRate = heartSamples.last
        heart.restingHeartRate = latestResting?.beatsPerMinute
        heart.restingHeartRateBaseline = restingBaseline
        heart.latestHRV = latestHRV
        heart.hrvBaseline = hrvBaseline
        heart.vo2Max = vo2Max.flatMap { $0 }
        heart.walkingHeartRateAverage = walkingHR.flatMap { $0 }

        // Trends prefer persisted history; fall back to what HealthKit gave us.
        // (dailySummaries returns newest-first; charts want oldest-first.)
        let stored = persistence.dailySummaries(days: 30).reversed()
        heart.recoveryTrend = stored.compactMap { record in
            guard let score = record.recoveryScore, let date = dateFromDay(record.day) else {
                return nil
            }
            return TrendPoint(date: date, value: Double(score))
        }
        heart.hrvTrend = hrvSamples
            .suffix(14)
            .map { TrendPoint(date: $0.date, value: $0.milliseconds) }
        heart.restingHeartRateTrend = restingSorted
            .suffix(14)
            .map { TrendPoint(date: $0.date, value: $0.beatsPerMinute) }
        heart.sleepTrend = nights
            .suffix(14)
            .map { TrendPoint(date: $0.date, value: $0.breakdown.asleepMinutes) }
        heart.loadTrend = dailyLoadHistory
            .suffix(14)
            .map { TrendPoint(date: $0.day, value: $0.points) }

        snapshot.heart = denied ? .unavailable(.permissionDenied) : .available(heart)

        // MARK: Workouts list, activity, coach.

        snapshot.workouts = denied
            ? .unavailable(.permissionDenied)
            : .available(workoutSummaries.sorted { $0.start > $1.start })
        snapshot.stepsToday = denied ? .unavailable(.permissionDenied) : .available(steps ?? 0)
        snapshot.activeCaloriesToday = denied
            ? .unavailable(.permissionDenied)
            : .available(activeCalories ?? 0)

        let coachContext = CoachContext(
            recovery: recoveryResult,
            sleep: sleepResult,
            load: loadResult,
            stress: stressResult,
            energy: energyResult,
            recentWorkouts: Array(workoutSummaries.sorted { $0.start > $1.start }.prefix(5)),
            date: Date()
        )
        snapshot.recommendation = CoachEngine.recommendation(for: coachContext)
        snapshot.lastRefreshed = Date()

        persist(
            recovery: recoveryResult,
            sleepResult: sleepResult,
            loadResult: loadResult,
            energyResult: energyResult,
            heart: heart,
            steps: steps,
            activeCalories: activeCalories,
            workouts: workoutSummaries
        )
        publishWidgetSnapshot(
            recovery: recoveryResult,
            sleepResult: sleepResult,
            loadResult: loadResult,
            energyResult: energyResult
        )

        if pendingRefresh {
            pendingRefresh = false
            Task { await self.refresh() }
        }
    }

    // MARK: - Internals

    private func installObserverIfNeeded() {
        guard !observing else { return }
        observing = true
        provider.startObserving { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshDebounced()
            }
        }
    }

    private var lastObserverRefresh: Date?
    private let observerDebounce: TimeInterval = 30

    private func refreshDebounced() {
        let now = Date()
        if let last = lastObserverRefresh, now.timeIntervalSince(last) < observerDebounce {
            return
        }
        lastObserverRefresh = now
        Task { await self.refresh() }
    }

    private func dateFromDay(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return Calendar.current.date(from: components)
    }

    private func persist(
        recovery: RecoveryResult?,
        sleepResult: SleepAnalysisResult?,
        loadResult: LoadResult?,
        energyResult: EnergyResult?,
        heart: HeartSnapshot,
        steps: Int?,
        activeCalories: Double?,
        workouts: [WorkoutSummary]
    ) {
        let record = DailyHealthSummaryRecord(
            day: Day.dayIdentifier(Date()),
            updatedAt: Date(),
            hrvMilliseconds: heart.latestHRV?.milliseconds,
            restingHeartRate: heart.restingHeartRate,
            sleepMinutes: sleepResult?.night.breakdown.asleepMinutes,
            sleepScore: sleepResult?.score,
            activeKilocalories: activeCalories,
            stepCount: steps,
            recoveryScore: recovery?.hasScore == true ? recovery?.score : nil,
            recoveryConfidence: recovery?.hasScore == true ? recovery?.confidence.rawValue : nil,
            loadRawPoints: loadResult?.todayRawPoints,
            stressIndex: snapshot.stress.value?.index,
            energyScore: energyResult?.score
        )
        persistence.upsertDailySummary(record)
        for workout in workouts.prefix(20) {
            persistence.upsertWorkout(workout)
        }
    }

    private func publishWidgetSnapshot(
        recovery: RecoveryResult?,
        sleepResult: SleepAnalysisResult?,
        loadResult: LoadResult?,
        energyResult: EnergyResult?
    ) {
        var snapshot = WidgetSnapshot(generatedAt: Date())
        if let recovery, recovery.hasScore {
            snapshot.recovery = WidgetMetricSlot(
                valueText: "\(recovery.score)",
                labelText: recovery.category.rawValue,
                generatedAt: Date()
            )
        }
        if let sleepResult, sleepResult.hasScore {
            snapshot.sleep = WidgetMetricSlot(
                valueText: Formatting.hoursMinutes(fromMinutes: sleepResult.night.breakdown.asleepMinutes),
                labelText: sleepResult.rating?.rawValue ?? "",
                generatedAt: Date()
            )
        }
        if let loadResult, let todayLoad = loadResult.todayLoad, loadResult.confidence != .insufficientData {
            snapshot.load = WidgetMetricSlot(
                valueText: Formatting.oneDecimal(todayLoad),
                labelText: loadResult.band.rawValue,
                generatedAt: Date()
            )
        }
        if let energyResult {
            snapshot.energy = WidgetMetricSlot(
                valueText: "\(energyResult.score)",
                labelText: energyResult.band.rawValue,
                generatedAt: Date()
            )
        }
        WidgetSnapshotStore.save(snapshot)
    }
}
