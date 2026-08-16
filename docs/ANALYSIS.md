# myhealth — Stage 1: Repository Analysis

Analysis of the reference project [b-nnett/goose](https://github.com/b-nnett/goose)
(inspected August 2026; a local snapshot is quarantined under `reference/goose/`)
and its consequences for the myhealth Apple Watch SE 3 app.

---

## A. Goose Architecture Analysis

Goose is an **iPhone-only WHOOP 5.0 companion**, not a general health app:

- **GooseSwift (iOS app)** — SwiftUI shell (Home / Health / Coach / More tabs),
  CoreBluetooth client, ActivityKit Live Activity extension. Deployment target
  iOS 26. `GooseAppModel` is a large `@MainActor ObservableObject` that owns BLE,
  the Rust bridge, SQLite-backed stores, and several serial dispatch pipelines.
- **Rust core (`Rust/core`, ~41 modules)** — all substantive logic lives in Rust:
  BLE frame parsing (CRC-validated), a schema-v14 SQLite store with evidence and
  provenance tables, metric algorithms, calibration (OLS), health-sync planning,
  and ~34 CLI validators/gates. Stated principle: *"All logic lives in Rust."*
- **Bridge** — a synchronous JSON-over-C-ABI bridge (`goose_bridge_handle_json`)
  routing ~100 methods from Swift into Rust.

**Consequences for myhealth:** the architecture premise is inverted. Goose is a
reverse-engineered BLE device client where the phone is the compute host. myhealth
is a **HealthKit-first Apple Watch app** where the system already collects the
data. There is no parsing layer to own, no evidence chain to preserve, and no
reason to pay the complexity tax of a Rust staticlib cross-compiled for
watchOS (the Goose build script only configures iOS targets). The layered idea —
source → normalize → domain models → engines → view models → UI — is kept; every
implementation is Swift.

Goose uses **zero third-party Swift dependencies** (Apple frameworks only) — a
discipline myhealth keeps.

## B. Goose Feature Inventory

| Area | What exists | State |
| --- | --- | --- |
| BLE | WHOOP 5.0 scan/pair/reconnect, custom GATT services, CRC-checked frame protocol, command sends behind fail-closed gating | Working, WHOOP-specific |
| Live streams | HR (1 s), live HRV RMSSD, RHR/HRV window estimates, motion | Working |
| Historical sync | Band memory download w/ retries + timeouts | Experimental |
| Overnight capture | 12 h session, raw spool + SQLite mirror, evidence export | Experimental; defeated by iOS suspension (no background-modes entitlement) |
| Sleep | Score v0 (shipped) + v1 (weights defined, partially wired): staging, need, 28-night debt, schedule consistency, HR dip | v0 shipped; v1 partial |
| Recovery | `goose_recovery_v0`: weighted HRV/RHR/respiratory/temp/sleep/prior-strain | Shipped |
| Strain | Zone-load + HR-reserve hybrid, 0–21 scale (WHOOP convention) | Shipped |
| Stress | HR elevation + HRV suppression, motion-damped windows (Rust + Swift variants) | Shipped |
| Energy | "Energy Bank": sleep charges, stress-weighted drains | Shipped |
| Cardio load | TRIMP/zone load + 7:28 ACWR with status bands | **Empty stub** |
| Vitals | Respiratory rate, skin temp, SpO2 (decoder missing) | Zeros/placeholders |
| Workouts | Passive auto-detection + manual GPS workouts (CoreLocation/MapKit), Live Activity | Working, phone GPS based |
| Coach | ChatGPT/Codex OAuth + OpenAI streaming chat with local tool calls | Experimental; cloud-dependent |
| HealthKit | Body-mass read only; writes are dry-run plans in Rust | Minimal |
| Persistence | Rust-owned SQLite, ~30 tables, idempotent upserts, privacy-linted exports | Solid |
| Tests | ~30 Rust integration test files, fixtures, release gates; **no Swift tests** | Rust-only |

## C. Keep / Adapt / Replace / Defer / Remove Matrix

| Goose feature | Decision | myhealth implementation | Reason |
| --- | --- | --- | --- |
| Multi-factor baseline-relative recovery | **ADAPT** | `RecoveryEngine`: robust z-scores vs 7/14/30-day personal baselines over HRV SDNN, resting HR, sleep vs personal need, timing consistency, recent-load penalty | Core product value; formulas re-derived from robust statistics, not copied |
| Weighted sleep score | **ADAPT** | `SleepAnalyzer`: need fulfillment, efficiency, schedule consistency, disturbances; stages shown informationally | Published sleep-science concepts; HealthKit sleep stages replace band staging |
| 0–21 strain scale | **REMOVE** | `LoadEngine` produces **myhealth Load 0–10** from Banister TRIMP + 7:28 ACWR bands | 0–21 is a WHOOP product convention; avoid proprietary semantics |
| Stress windows (HR elevation + HRV suppression, motion-damped) | **ADAPT** | `StressEngine`: 10-min windows from HealthKit HR samples + HRV suppression vs baseline | Sound wellness heuristic; fully re-derived constants |
| Energy Bank charge/drain model | **ADAPT (simplified)** | `EnergyEngine`: 0–100 composite of recovery, sleep, load freshness | Watch users need a glanceable number, not a simulation; original formula |
| Confidence / evidence discipline | **KEEP** | `ConfidenceLevel` on every score; no score rendered when insufficient | Core honesty requirement |
| Fail-closed missing-data states | **KEEP** | `HealthDataState<T>` (loading/available/unavailable{denied, noData, insufficientHistory, stale, error}) on every metric | Never display a fabricated value |
| Coach | **REPLACE** | `CoachEngine`: deterministic, local, rule-based answers from `CoachContext` | Cloud LLM chat violates watch-first + privacy-first goals |
| WHOOP BLE stack | **REMOVE** | — | Device-coupled; Apple Watch is the sensor |
| Rust core + bridge | **REMOVE** | Pure Swift engines (value types, unit-tested) | No parsing layer exists; Swift removes FFI/cross-compile/packaging risk |
| SQLite/Rust store | **REPLACE** | SwiftData (`DailyHealthSummary` etc.) + App Group JSON snapshot for widgets | Native, low-ceremony watchOS persistence |
| ActivityKit Live Activity | **REPLACE** | WidgetKit Smart Stack accessory widgets + deep links | Lock-screen Live Activities are an iPhone concept |
| Overnight Guard background capture | **REMOVE** | Apple Watch collects sleep natively; app recalculates on wake/activation | watchOS has no general background execution; HealthKit already owns the night |
| OLS calibration machinery | **DEFER** | — | Needs label data users don't have yet |
| iPhone GPS workout flows | **REPLACE** | `HKWorkoutSession` + `HKLiveWorkoutBuilder` on watch | Native watch workout stack with auto-saved data |
| Onboarding / tabs shell | **ADAPT** | watchOS `TabView`: Today / Health / Workouts / Coach / Settings | Same IA, watch-native presentation |
| Mock/dev scenarios | **KEEP** | `MockHealthDataProvider` behind DEBUG toggle (excellent / poor / insufficient / denied / partial) | Required for tests + UI state coverage |

## D. myhealth Product Architecture

```
HealthKit (system-collected; watch sensors)
      ↓
HealthKitManager            (authorization, anchored/observer/statistics queries,
      ↓                      workout session + live builder)
HealthDataRepository        (orchestrates queries, caches, exposes domain state)
      ↓
Normalizer / Assembler      (raw samples → SleepNight, daily aggregates)
      ↓
Domain Models               (value types: samples, summaries, states)
      ↓
Algorithm Engines           (RecoveryEngine, SleepAnalyzer, LoadEngine,
      ↓                      StressEngine, EnergyEngine, CoachEngine — pure Swift)
View Models (@MainActor)  → SwiftUI views
      ↓
SwiftData store + App Group snapshot → WidgetKit extension
```

Engines are pure value-type computations over plain inputs — no HealthKit import —
so they are unit-testable without a device.

## E. Apple Watch SE 3 Capability Map

| Capability | SE 3 status | Consequence |
| --- | --- | --- |
| S10 SiP, 64 GB | Yes | Plenty for all computation |
| Optical heart rate (2nd gen) | Yes | HR stream, resting HR, HRV SDNN, walk-back alerts |
| Sleep stages + sleep score (watchOS) | Yes | Core sleep input via HealthKit |
| HRV (SDNN samples in HealthKit) | Yes (collected during sleep/Breathe) | Primary recovery input |
| Sleep apnea notifications | Yes | System feature; not re-implemented |
| Wrist temperature | Listed on spec page | Queried opportunistically; availability-driven UI |
| ECG | No | Never referenced |
| Blood oxygen | No (US) | Never referenced |
| Always-on display | Yes | Refresh rate care + always-on states considered |
| Sizes 40/44 mm (324×394, 368×448 px) | Yes | Adaptive layouts via dynamic type + compact charts |
| Battery (18 h) | — | No polling; event-driven recalculation only |

Design rule: **the app never assumes a sensor exists** — every metric resolves
its `HealthDataState` at runtime.

## F. HealthKit Data Mapping

| Metric | HK type | Query pattern |
| --- | --- | --- |
| HR stream | `HKQuantityTypeIdentifier.heartRate` | sample query + anchored observer for live updates |
| Resting HR | `.restingHeartRate` | sample query, daily + history for baseline |
| HRV | `.heartRateVariabilitySDNN` | sample query, morning + history for baseline |
| Sleep | `HKCategoryTypeIdentifier.sleepAnalysis` (`HKCategoryValueSleepAnalysis`) | sample query per night; stages core/deep/REM/awake/inBed |
| Steps / energy | `.stepCount`, `.activeEnergyBurned` | `HKStatisticsCollectionQuery` daily sums |
| VO2 max (cardio fitness) | `.vo2Max` | latest sample |
| Walking HR average | `.walkingHeartRateAverage` | latest sample |
| Workouts | `HKObjectType.workoutType()` | sample query for history; `HKWorkoutSession`/`HKLiveWorkoutBuilder` for recording (auto-save) |
| Date of birth | characteristics | Tanaka HR-max estimate for zones (non-sensitive) |

Read-only except workouts recorded by the app (saved via workout builder).

## G. myhealth Data Model

Persisted (SwiftData): `DailyHealthSummaryRecord` (per-day scores + inputs),
`WorkoutRecord`, `AppSettings` (struct, UserDefaults), `TrendPoint` (struct,
derived). Full definitions in `docs/ARCHITECTURE.md`.

## H–L. Algorithm Proposals (summaries; full specs in `docs/ALGORITHMS.md`)

- **H. Recovery (0–100):** 50 ± weighted robust z-scores. Weights: HRV 0.35,
  resting HR 0.20, sleep-vs-need 0.25, timing consistency 0.10, recent-load
  penalty 0.10. Missing factors redistribute weight; < 40% weight available →
  no score (explanatory state). Categories: 0–29 Very Low, 30–49 Low, 50–69
  Moderate, 70–84 Good, 85–100 Excellent.
- **I. Sleep (0–100):** need fulfillment 0.45 (personal need = 14-night median,
  default 8 h), efficiency (asleep ÷ in-bed) 0.30, schedule consistency
  (midpoint deviation vs 7-day median) 0.15, disturbances (awake share) 0.10.
- **J. Load (0–10):** per-workout Banister TRIMP = minutes × 0.64 ×
  e^(1.92 × HR-reserve); day load = Σ TRIMP ÷ 100 × 10 (clamped); ACWR =
  7-day ÷ 28-day daily load with bands < 0.8 Recovering, 0.8–1.3 Productive,
  > 1.3 High. Energy- and duration-based fallbacks (labeled, lower confidence)
  when avg HR is unavailable.
- **K. Stress (Low / Moderate / Elevated):** 10-min windows; index = 100 ×
  (0.65 × HR-elevation pressure + 0.35 × HRV suppression), × 0.6 during sleep
  windows. Always labeled a wellness estimate; never diagnostic.
- **L. Energy (0–100):** clamp(0.5 × recovery + 0.3 × sleep + 0.2 ×
  (100 − min(load×10, 100))); requires recovery or sleep, else unavailable.

## M. watchOS Screen Map

Today (dashboard) · Health hub → Recovery / Sleep / Load / Stress / Energy /
Heart · Workouts → type picker → live session → summary → history · Coach ·
Settings → Privacy / Data / About · Onboarding (welcome → permissions →
personalization → baseline state).

## N. Navigation Flow

`TabView` (Today, Health, Workouts, Coach, Settings) + `NavigationStack` per
tab. Deep links `myhealth://today|recovery|sleep|load|stress|energy|heart|
workouts|workout/start?type=` from widgets and App Intents.

## O. Privacy Architecture

Local-only by default; no network calls, no tracking, no logs of health values.
HealthKit read-only + app-recorded workouts. Settings exposes permission
status, retention explanation, AI statement (none used), and full local-data
deletion. Widgets read only an App Group JSON snapshot of derived scores.

## P. iPhone Companion Requirements

None. myhealth ships as an independent watchOS app. A minimal companion is a
possible future addition; `WatchConnectivity` deliberately unused.

## Q. Server Requirements

None. Deterministic local coach; no backend.

## R. Technical Risks

1. **No compile verification on Windows** (this build machine) — mitigated by
   conservative API use and a documented Mac first-build checklist.
2. HealthKit authorization UX (denied states must guide to Settings).
3. HRV sample sparsity on some users → confidence system degrades gracefully.
4. Widget refresh budget → hourly timeline + snapshot-on-change.
5. SwiftData/App Group provisioning requires capabilities enabled on the
   developer account (documented in README).
6. Unit tests execute on Mac; logic is hand-verified here.

## S. Development Phases

As executed: quarantine reference → analysis/spec docs → project scaffold →
HealthKit layer → engines + tests → dashboards → workouts → coach → widgets →
onboarding/settings/accessibility → release docs → consistency review.

## T. Stage 1 Conclusion

Goose validates the *product idea* (recovery/sleep/load/stress/energy/coach on
a watch) but almost none of its *implementation* transfers: it is an unlicensed,
iPhone-hosted, BLE-device-coupled prototype. myhealth is built HealthKit-first,
watch-first, pure Swift, offline, explainable, and honest about missing data —
keeping only Goose's intellectual contributions: factor weighting concepts,
confidence discipline, and fail-closed data states.
