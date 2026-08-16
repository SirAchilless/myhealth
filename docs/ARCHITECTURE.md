# myhealth — Architecture

## Overview

myhealth is an independent watchOS 11+ app (no iPhone companion) built with
SwiftUI, HealthKit, SwiftData, WidgetKit, and App Intents. Everything runs
on-device; there are no network calls and no third-party dependencies.

```
HealthKit ──▶ HealthKitManager ──▶ HealthDataRepository ──▶ Engines ──▶ ViewModels/SwiftUI
 (system)      (queries, auth)      (normalize, cache,        (pure)      (AppModel + views)
                                     states, persistence)
                                      │
                                      ├──▶ SwiftData (daily summaries, workout cache)
                                      └──▶ App Group snapshot ──▶ WidgetKit extension
```

## Targets

| Target | Bundle ID | Purpose |
| --- | --- | --- |
| MyHealthWatch | `com.myhealth.watch` | The watch app (Swift 5 language mode, watchOS 11.0+) — live HealthKit |
| MyHealthWidgets | `com.myhealth.watch.widgets` | Smart Stack / accessory widgets (watch) |
| MyHealthWatchTests | `com.myhealth.watchtests` | Swift Testing unit tests (hosted in the watch app) |
| MyHealthIPhone | `com.myhealth.ios` | **iPhone edition for sideloading** — insight from an imported Apple Health export; no entitlements, no HealthKit |

Platform-neutral code (models, engines, health layer, import pipeline,
persistence, theme, components, feature UI) lives in `SharedCore/`, which is
a folder-synchronized group referenced by both app targets. Watch-only pieces
(workout session via `HKWorkoutSession`, App Intents, entry point) stay in
`MyHealthWatch/`; iPhone-only pieces (entry point, Import screen) in
`MyHealthIPhone/`.

### iPhone edition data flow (sideload builds)

```
Apple Health app → export.zip (user-shared)
   → ZipEntryReader (dependency-free zip + raw-deflate via libcompression)
   → AppleHealthExportParser (streaming XMLParser; bounded aggregates only)
   → ParsedHealthExport (Codable, persisted by HealthImportStore)
   → ImportedHealthDataProvider (implements HealthDataProviding)
   → the SAME repository → engines → screens as the watch build
```

The project uses Xcode 16+ folder-synchronized groups: every file under a
target's folders is automatically a member of that target.

**Deliberate duplication:** `MyHealthWidgets/WidgetSnapshotStore.swift` mirrors
`SharedCore/Persistence/WidgetSnapshotStore.swift` so the extension stays
independent of app code. If you edit one, edit the other.

**CI:** `.github/workflows/build-ipa.yml` builds the iPhone edition unsigned
(`CODE_SIGNING_ALLOWED=NO`) and packages `myhealth.ipa` — Sideloadly re-signs
it with the user's Apple ID at install time, so no secrets live in CI.

## Layers

### 1. Health (`MyHealthWatch/Health/`)

- **`HealthDataProviding`** — the port abstraction (protocol). Engines and
  view models never import HealthKit.
- **`HealthKitManager`** — production implementation: authorization, one-shot
  async sample/statistics queries, and observer queries that notify while the
  app runs. No polling, no background loops (battery rule, docs/PRIVACY.md).
- **`SleepNightAssembler`** — groups raw sleep intervals into nights; unions
  overlapping per-stage intervals so multi-source (Watch + iPhone) data is
  never double-counted.
- **`MockHealthDataProvider`** — DEBUG-only deterministic scenarios
  (Settings → Developer). Production builds contain none of this data.
- **`HealthDataRepository`** — orchestrates one refresh pipeline: gather →
  baseline → analyze → publish. Single-flight with coalescing; each metric
  resolves independently so one failure can't blank others. Persists the day's
  summary and pushes the widget snapshot.

### 2. Algorithms (`MyHealthWatch/Algorithms/`)

Pure value-type computations over plain inputs — no HealthKit, no UI:
`RecoveryEngine`, `SleepAnalyzer`, `LoadEngine`, `StressEngine`,
`EnergyEngine`, `CoachEngine`, `BaselineCalculator`. All constants live in
`ScoringConstants`. Formulas and rationale: docs/ALGORITHMS.md.

### 3. Domain models (`MyHealthWatch/Models/`)

Framework-free value types + `HealthDataState<T>` availability machine.

### 4. Persistence (`MyHealthWatch/Persistence/`)

SwiftData (`DailyHealthSummaryRecord`, `WorkoutRecord`) behind
`PersistenceStore`; `WidgetSnapshotStore` writes derived scores to the App
Group. Persistence failures never crash — history degrades gracefully.

### 5. Presentation (`Features/`, `Components/`, `Theme/`)

`MyHealthTheme` (semantic colors, type, spacing), a small component library
(cards, rings, gauges, badges, trend chart, state views), and per-feature
screens. Every status has text alongside color (accessibility rule).

### 6. App Intents (`Intents/`)

Open Today / Open Recovery / Start Workout, routed through the same
`myhealth://` deep links the widgets use.

## Error handling

`MyHealthError` enumerates the failure families (healthKitUnavailable,
healthAuthorizationDenied, insufficientHealthData, sensorUnavailable,
workoutUnavailable, persistenceFailure, backgroundRefreshUnavailable,
unknownError). Unavailability is a first-class UI state via
`HealthDataState.unavailable(UnavailabilityReason)`. Missing health data
never produces a crash or a fabricated value.

## Concurrency

- View models and the repository are `@MainActor`.
- HealthKit delegate callbacks (`HKWorkoutSessionDelegate`,
  `HKLiveWorkoutBuilderDelegate`) are `nonisolated` and hop to the main actor.
- Engines are synchronous pure functions called from the main actor — cheap
  (microseconds) and testable.
- One-second workout ticker is the only repeating timer in the app, active
  only during an active session.

## Known limitations

- HealthKit read-authorization cannot be queried per type; denial surfaces as
  "no data" states with guidance copy (docs/HEALTH_DATA.md).
- Background recalculation relies on watchOS scheduling (activation + observer
  callbacks while running); no long-running background execution is assumed.
- The project has not yet been compiled (built for the first time on a Mac —
  see README "First build").
