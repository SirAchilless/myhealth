# myhealth — Testing

## Unit tests (`MyHealthWatchTests`, Swift Testing)

Coverage by area — thresholds, boundaries, missing data, outliers:

| Suite | What it locks down |
| --- | --- |
| `BaselineCalculatorTests` | median/MAD math, window filtering, sufficiency, degenerate spread, outlier resistance, sleep-need derivation and clamps |
| `RecoveryEngineTests` | neutral-day midpoint, each factor's direction, clamping, category thresholds, insufficient-data floors (never a fabricated score), confidence tiers, relative (non-medical) language |
| `SleepAnalyzerTests` | component scoring (duration/efficiency/fragmentation/timing), ratings, deficit reporting, tiny-night refusal, default need fallback, circular midnight midpoint math |
| `SleepNightAssemblerTests` | multi-source overlap de-duplication, cluster separation, nap exclusion, missing inBed approximation |
| `LoadEngineTests` | TRIMP magnitude & monotonicity, energy/duration fallbacks with exact factors, Tanaka/override max HR, ACWR bands, minimum history gating, display scaling + clamps |
| `StressEngineTests` | category thresholds, HR/HRV signal directions, sleep dampening, no-window nil, low-confidence path, window bucketing, no diagnostic language |
| `EnergyEngineTests` | follows recovery, requires recovery-or-sleep, load freshness effect, weakest-input confidence, bands |
| `CoachEngineTests` | recommendation tiers (incl. high-recovery-but-overloaded), all five questions with and without data, honest gaps |
| `MockScenarioTests` | dev provider scenario integrity (denied throws, sparse data, partial data) + pipeline refuses to fabricate without heart data |

Run: `⌘U` in Xcode (MyHealthWatch scheme, watch simulator destination).

## Mock scenarios (DEBUG)

Settings → Developer → pick a scenario, restart the app:

| Scenario | Shapes |
| --- | --- |
| Excellent | high HRV, low RHR, 7 h 42 m sleep, light load |
| Poor Recovery | low HRV, elevated RHR, short sleep, hard daily workouts |
| Insufficient Data | 1–2 days of history only |
| Permission Denied | provider refuses everything |
| Partial Data | sleep + workouts, no HRV/RHR |

Every screen must render sensibly in all five (see acceptance checklist).

## Manual device checklist (Apple Watch SE 3, 40 mm & 44 mm)

1. First launch: onboarding → permission prompt → Today in loading/no-data states.
2. Sleep: wear overnight → sleep card populates by mid-morning; stages visible.
3. Workout: start/pause/resume/end; live HR/calories/distance; summary; workout visible in Health app.
4. Widgets: add Recovery/Sleep to Smart Stack; tap → correct deep-linked screen.
5. Siri/Shortcuts: "Start a workout with myhealth" opens picker-started session.
6. Health denial: deny access → verify honest unavailable states + Settings guidance.
7. Battery: normal use ~no measurable extra drain (no sensors polled by the app).
8. VoiceOver: traverse Today/Recovery/Sleep — every metric readable without color.
9. 40 vs 44 mm: layouts readable; charts not clipped.

## Not yet executed

The unit tests were written on a non-Apple machine and **have not been run**.
The first `⌘U` on a Mac is part of the first-build checklist (README.md).
