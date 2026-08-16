# myhealth — Release Preparation

## Signing & capabilities (Xcode, on a Mac)

1. Open `MyHealth.xcodeproj`, select the **MyHealthWatch** target → Signing &
   Team: choose your team (bundle IDs are `com.myhealth.watch` and
   `com.myhealth.watch.widgets`; change the prefix to your own domain if you
   don't own `com.myhealth`).
2. Capabilities required (automatic signing registers them):
   - **HealthKit** (app target)
   - **App Groups** → `group.com.myhealth.shared` (app + widget targets)
3. The widget extension embeds automatically via the project's Embed App
   Extensions phase.

## App Store metadata (drafts)

- **Name:** myhealth
- **Subtitle:** Recovery, sleep & training insights
- **Description (draft):**
  myhealth turns your Apple Watch's health signals into a simple daily
  picture: Recovery, Sleep, Training Load, Stress, and Energy — each scored
  against your own personal baselines, explained in plain language, and
  computed entirely on your watch.

  • Recovery score built from heart-rate variability, resting heart rate,
  sleep, and recent training load — relative to *your* normal
  • Sleep analysis with stages, efficiency, schedule consistency, and trends
  • myhealth Load (0–10) with week-vs-month training balance
  • Stress and Energy wellness estimates, clearly labeled as such
  • Native workout recording for running, walking, cycling, strength & more
  • A deterministic on-watch coach that answers "How am I doing?" and
  "Should I train?" from your data
  • Smart Stack widgets for Recovery, Sleep, Load, and Energy
  • No account, no cloud, no tracking — everything stays on your devices

  myhealth is a wellness app. It does not provide medical advice, diagnosis,
  or treatment.
- **Keywords:** recovery, sleep, hrv, training load, stress, energy, wellness, apple watch
- **Privacy nutrition label:** Data Not Collected (all processing on-device).
- **HealthKit usage strings:** see docs/PRIVACY.md (keep in sync with
  Info.plist).

## Screenshots

Required: Apple Watch 40 mm and 44 mm (watchOS 26 SDK set). Recommended set:
Today (populated), Recovery detail, Sleep detail, live workout, Smart Stack
widgets. Use the DEBUG mock "Excellent" scenario for populated captures —
**never ship screenshots containing a real person's health data**.

## Icon

`MyHealthWatch/Resources/Assets.xcassets/AppIcon.appiconset` contains a
generated placeholder (mint ring + dot on dark). Replace `appicon-1024.png`
with the final icon (1024×1024, no alpha, no rounded corners) before
submission. Keep it original — no WHOOP/Goose/Apple trade dress.

## Review notes (for App Review)

- The app uses HealthKit read for heart/sleep/activity/workouts and writes
  only user-recorded workouts; usage strings in Info.plist explain each.
- Widget extension displays only derived on-device scores.
- No account creation, no external services, no data collection.
- Workouts recorded in-app save to Apple Health automatically.

## Pre-submission checklist

- [ ] First-build checklist (README.md) fully passed on a Mac
- [ ] Unit tests green (`⌘U`)
- [ ] 40 mm + 44 mm device pass (docs/TESTING.md checklist)
- [ ] All five mock scenarios render correctly
- [ ] HealthKit denial paths verified
- [ ] Final icon replaces the placeholder
- [ ] Version/build numbers bumped; release notes written
- [ ] Privacy label entered (Data Not Collected)
- [ ] Archive → validate → upload from Xcode
