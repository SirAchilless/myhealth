# myhealth — Privacy

myhealth is local-first by design.

## Principles

1. **On-device only.** All computation happens on the watch. The app makes no
   network requests, has no accounts, no analytics, no advertising, and no
   tracking of any kind.
2. **Minimal HealthKit use.** Read access is limited to the categories in
   docs/HEALTH_DATA.md; write access is limited to workouts the user records
   in the app.
3. **Derived data only.** SwiftData stores daily summaries (scores + the
   inputs behind them) and a small workout cache. Raw HealthKit samples are
   never copied into the app's database.
4. **No health data in logs.** The app does not log raw measurements or
   identifiers. Diagnostics never include health values.
5. **Widgets see scores, not samples.** The App Group contains a tiny JSON of
   derived display values (`WidgetSnapshot`) with a two-hour freshness
   window, and nothing else.
6. **No AI processing.** The coach is deterministic on-device rule
   evaluation. If cloud AI is ever introduced it will be opt-in, disclosed,
   minimal, and disable-able — and this document will say exactly what is
   transmitted. (Nothing is transmitted today.)

## Retention

| Data | Where | Retention |
| --- | --- | --- |
| Daily summaries | SwiftData on device | long-term, capped at 2 years |
| Workout cache | SwiftData on device | capped at 1,000 rows |
| Widget snapshot | App Group | replaced on each refresh |
| Raw samples | never stored by myhealth | n/a (owned by Apple Health) |
| Settings | UserDefaults | until deleted |

## User controls

- **Permissions:** Settings shows Health access status and how to change it.
- **Deletion:** Settings → Data → Delete all myhealth data removes every
  summary, cached workout, and widget snapshot. Apple Health data itself is
  untouched.
- **Haptics** and unit preferences are user-controlled.

## HealthKit usage strings (summary)

- **Read:** "myhealth reads your heart rate, heart-rate variability, resting
  heart rate, sleep, workouts, and activity from Apple Health to compute
  your personal recovery, sleep, load, stress, and energy insights on your
  watch. All processing happens on your devices."
- **Write:** "Workouts you record with myhealth are saved to Apple Health."

## App Store privacy nutrition label (intended)

- Data **not collected** — no data leaves the device.
- Health & fitness data: used for app functionality only, on-device.

## Security

- No secrets, tokens, or API keys exist anywhere in the app (there are no
  services to authenticate to).
- The only app-to-extension sharing is the read-only derived snapshot in the
  App Group container.
