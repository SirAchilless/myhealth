# myhealth — Health Data Reference

## The availability state machine

Every metric resolves to a `HealthDataState<Value>`:

| State | Meaning | UI |
| --- | --- | --- |
| `loading` | Query in flight | spinner |
| `available(value)` | Real data | value |
| `unavailable(.permissionDenied)` | Health access denied/unavailable | explanation + guidance |
| `unavailable(.noData)` | Queried, nothing there | "No data yet" |
| `unavailable(.insufficientHistory)` | Too little history to score | "Building your baseline" |
| `unavailable(.stale)` | Data too old to trust | refresh hint |
| `unavailable(.unsupported)` | Metric not on this hardware | not-available note |
| `unavailable(.error(msg))` | Query failed | retry-able error |

Production code never renders a placeholder number, and no random data exists
outside the DEBUG mock provider.

## HealthKit types used

| Type | Identifier | Direction | Used for |
| --- | --- | --- | --- |
| Heart rate | `HKQuantityTypeIdentifier.heartRate` | read | stress windows, current HR, workout HR |
| Resting HR | `.restingHeartRate` | read | recovery factor, stress baseline, TRIMP |
| HRV | `.heartRateVariabilitySDNN` | read | recovery factor, stress suppression |
| Sleep analysis | `HKCategoryTypeIdentifier.sleepAnalysis` | read | sleep score, timing, deficits |
| Steps | `.stepCount` | read | Today footer |
| Active energy | `.activeEnergyBurned` | read | Today footer, load fallback |
| VO2 max | `.vo2Max` | read | cardio fitness display |
| Walking HR avg | `.walkingHeartRateAverage` | read | heart section |
| Workouts | `HKObjectType.workoutType()` | read + write | history, load; write for app-recorded sessions |

Characteristics: date of birth (non-sensitive) → Tanaka max-HR estimate.

Sleep stages are read via `HKCategoryValueSleepAnalysis` values
(`asleepCore`, `asleepDeep`, `asleepREM`, `awake`, `inBed`, legacy `asleep`/
`asleepUnspecified` mapped to unspecified-asleep). Nights are assembled by
`SleepNightAssembler` (gap > 3 h separates clusters; per-stage interval
unions prevent double-counting across Watch/iPhone sources; nights < 45 min
asleep are treated as naps and excluded).

## Query patterns

- One-shot `HKSampleQuery` / `HKStatisticsQuery` wrapped in async/await per
  refresh; `HKObserverQuery` for change notification while the app runs.
- Refresh triggers: app activation, HealthKit observer callbacks (30 s
  debounce), workout completion. **No polling loops** (battery rule).
- Workout recording uses `HKWorkoutSession` + `HKLiveWorkoutBuilder` with
  `HKLiveWorkoutDataSource` (system-generated HR/energy/distance samples) and
  metadata key `com.myhealth.recorded` to identify app-recorded sessions.

## Authorization notes (HealthKit reality)

- HealthKit exposes **write** authorization status, not read status. After
  the prompt, denial on the read side is indistinguishable from "no data", so
  myhealth shows helpful "no data" copy that mentions re-checking Health
  access, and Settings shows the strongest available signal.
- The app never writes anything except workouts recorded within it.
- Usage strings (in `MyHealthWatch/Info.plist`) explain each category.

## Sensor reality on Apple Watch SE 3

HR / resting HR / HRV (SDNN) / sleep stages / workouts / activity all
available via HealthKit. ECG and blood oxygen are not (US) — the app simply
never references them. Availability-driven design means the same code adapts
to any watch.
