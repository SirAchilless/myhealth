# myhealth — Stage 2: Product Specification

## Product requirements

1. Answer *"How am I doing today, and what should I do next?"* in 3–5 seconds
   of wrist time.
2. Watch-first: glanceable cards, large numerals, minimal input, Digital Crown
   scroll, haptics for meaningful events.
3. Fully offline: every feature works with no phone, Wi-Fi, or cloud.
4. Honest: every metric shows availability + confidence; never a fabricated
   value; explainable scores.
5. Non-medical: wellness language only, relative-to-baseline phrasing.
6. Private: local-first, no network access, deletable data, no health values in
   logs.
7. Works across both SE 3 sizes (40/44 mm) with adaptive layouts.

## Screens

| Screen | Content | States |
| --- | --- | --- |
| Onboarding | Welcome → HealthKit permission rationale (why each category) → optional personalization (typical sleep need, weekly training days, preferred activity) → baseline-building state | fresh / denied / partial |
| Today | Recovery card (score, category, confidence), Sleep card (duration, rating), Load card, Stress card, Energy card, daily recommendation | all `HealthDataState`s + insufficient-data explanations |
| Health hub | Navigation to Recovery / Sleep / Load / Stress / Energy / Heart |
| Recovery detail | Score, category, confidence, positive/negative factors with per-factor detail, missing data list, 7/14-day trend chart | available / insufficient / denied |
| Sleep detail | Duration, score, stages breakdown, bedtime/wake, efficiency, consistency, trend, deficit | available / no-data / denied |
| Load detail | Today load, 7-day chart, ACWR + status band, recent workouts with per-workout load | available / insufficient history |
| Stress detail | Current category, index, explanation, 12-h mini trend | available / no HR data |
| Energy detail | Score, capacity phrase, inputs summary | available / insufficient |
| Heart | Current HR, resting HR, HRV, cardio fitness (VO2max), walking HR avg — each vs baseline, trends | per-metric states |
| Workouts | Type picker (Run / Walk / Cycle / Strength / Other) → live session → summary; history list |
| Workout session | Elapsed, HR + zone, calories, distance (when applicable); pause/resume/end | running / paused / ended / failed |
| Coach | Quick questions (How am I doing? Should I train? Why is recovery low? How did I sleep? What today?) + answer view; daily recommendation | per-input availability |
| Settings | Permissions status, haptics, units, sleep need, training days, privacy, data management (delete all), about/version |
| Privacy | Plain-language privacy explanation, retention, AI statement |

## User flows

- **Cold start:** onboarding once → Today. Subsequent launches go straight to
  Today and refresh asynchronously (loading states, never blank/fake values).
- **Refresh:** on app activation, after workouts, and via anchored-object
  observer updates while running. No polling loops.
- **Workout:** Workouts tab → type → Start (haptic) → live metrics → End →
  confirm → summary → auto-saved to HealthKit → Today/Load update.
- **Widget tap:** Smart Stack card → deep link into matching detail screen.

## Scoring specification (summary)

Defined in `docs/ALGORITHMS.md`; constants live in
`MyHealthWatch/Algorithms/ScoringConstants.swift` only. Score categories:

- Recovery: 0–29 Very Low · 30–49 Low · 50–69 Moderate · 70–84 Good · 85–100 Excellent
- Sleep: rating word mapping Excellent/Good/Fair/Poor from score bands
- Load: 0–10 scale + ACWR band (Recovering < 0.8 · Productive 0.8–1.3 · High > 1.3)
- Stress: Low < 33 · Moderate 33–66 · Elevated > 66
- Energy: Low < 30 · Moderate 30–69 · Good ≥ 70

## Data model

Value types (domain): `HeartRateSample`, `HRVSample`, `SleepSample`,
`SleepNight`, `WorkoutSummary`, `TrendPoint`, `MetricBaseline`, engine result
structs, `HealthDataState<T>` + `UnavailabilityReason`.

Persisted (SwiftData): `DailyHealthSummaryRecord`, `WorkoutRecord`.
UserDefaults: onboarding flag + `AppSettings`. App Group: `WidgetSnapshot` JSON.

## Non-goals

No medical diagnosis/claims, no WHOOP/external-device support, no cloud, no AI
processing of health data, no iPhone companion in v1.
