# myhealth

A watch-first health, recovery, sleep, training-load, stress, and energy app
for **Apple Watch SE 3** (and any watchOS 11+ Apple Watch), plus an
**iPhone edition** designed for sideloading that computes the same insights
from an **Apple Health export** you import. Everything runs on-device: no
account, no cloud, no tracking, no third-party dependencies.

> Raise your wrist and know how you're doing in 3–5 seconds.

## Two builds, one codebase

| Build | Target | Data source | Distribution |
| --- | --- | --- | --- |
| **Apple Watch app** | `MyHealthWatch` (+ Smart Stack widgets) | Live HealthKit | Xcode / App Store / TestFlight (requires a Mac + developer signing) |
| **iPhone edition** | `MyHealthIPhone` | Imported Apple Health `export.zip` | **Unsigned IPA from GitHub Actions → Sideloadly** |

Sideloaded apps can't use a paired Apple Watch, and sideloading with a free
Apple ID works best with zero entitlements — so the iPhone edition uses no
HealthKit at all. You export your data from Apple Health, import it into
myhealth, and every insight (recovery, sleep, load, stress, energy, coach,
heart, trends) is computed on-device from that export.

## 📱 Get it on your iPhone (GitHub Actions + Sideloadly)

1. **Push this repo to GitHub** (the workflow lives at
   `.github/workflows/build-ipa.yml`):
   ```sh
   git init && git add . && git commit -m "myhealth"
   git branch -M main
   git remote add origin git@github.com:YOU/myhealth.git
   git push -u origin main
   ```
2. GitHub Actions builds an **unsigned `myhealth.ipa`** automatically on every
   push (also runnable manually via *workflow_dispatch*). Open the run →
   **Artifacts** → download `myhealth-ipa`. Tag a release (`git tag v1 && git
   push --tags`) and the IPA is attached to the GitHub Release.
3. **Sideloadly**: install [Sideloadly](https://sideloadly.io/) on a PC/Mac,
   connect your iPhone, drag `myhealth.ipa` in, enter your Apple ID, and
   install. First launch: Settings → General → VPN & Device Management →
   trust your Apple ID.
   - Free Apple ID: app expires after **7 days** (re-sideload to refresh);
     3 sideloaded apps max per device. Paid account: 1 year.
4. **In the app**: finish onboarding, then
   **Health app → your picture → Export All Health Data → save export.zip to
   Files**, come back to myhealth → Today → **Import your Apple Health
   export**. Re-import anytime for fresh data.

The build needs no signing secrets — Sideloadly signs the app with *your*
Apple ID at install time.

## What's inside

| Area | Highlights |
| --- | --- |
| **Today** | Recovery, Sleep, Load, Stress, Energy cards + daily recommendation |
| **Health** | Detail screens with factors, stages, baselines, trends, Heart section |
| **Workouts** | Watch: native recording with live HR + zones. iPhone: history from your export |
| **Coach** | Deterministic, local answers to "How am I doing?", "Should I train?", … |
| **Settings** | Data source status, haptics, units, sleep target, privacy, data deletion |
| **Widgets** (watch) | Smart Stack accessories for Recovery / Sleep / Load / Energy |
| **Intents** (watch) | Open Today / Recovery, Start Workout |
| **Import** (iPhone) | Apple Health export.zip / export.xml — streaming parser, bounded memory |

Every score is **personal-baseline-relative, explainable, and
confidence-rated**; missing data is shown honestly, never filled with
placeholder values.

## Project layout

```
MyHealth.xcodeproj        Xcode 16+ project (folder-synchronized targets)
MyHealthWatch/            watchOS app entry + watch-only pieces
  (workout session, App Intents, entitlements, assets)
MyHealthIPhone/           iPhone edition entry + Import screen
SharedCore/               shared: models, engines, health layer, import
                          pipeline, persistence, theme, components, features
MyHealthWidgets/          WidgetKit extension (watch Smart Stack)
MyHealthWatchTests/       Swift Testing unit tests (engines + import parser)
.github/workflows/        build-ipa.yml — unsigned IPA for Sideloadly
docs/                     ANALYSIS, SPEC, ARCHITECTURE, ALGORITHMS,
                          HEALTH_DATA, PRIVACY, TESTING, RELEASE
reference/goose/          quarantined reference repo (NO license — do not copy)
```

The Goose reference analysis and the KEEP/ADAPT/REPLACE/DEFER/REMOVE matrix
that shaped this app are in `docs/ANALYSIS.md`.

## How the import pipeline works

`export.zip` → `ZipEntryReader` (dependency-free zip extraction, raw deflate
via libcompression) → `AppleHealthExportParser` (streaming `XMLParser`; keeps
only bounded aggregates: last 36 h HR, 60 d HRV, daily resting HR, 21 nights
sleep, 35 d workouts, daily steps/energy, VO2 max, DOB) → `ParsedHealthExport`
(Codable, persisted in Application Support) → `ImportedHealthDataProvider`
(implements the same `HealthDataProviding` port as HealthKit) → the existing
engines and screens, unchanged. Re-import replaces the snapshot.

## ⚠️ First build (do this on a Mac)

This project was authored and reviewed on a non-Apple machine, so **it has
not yet been compiled**. Two paths:

- **iPhone IPA (no Mac needed locally):** push to GitHub — the Actions
  workflow compiles it. If the build fails, the log will show the exact
  compile error; expect at most trivial fixes.
- **Watch app / Xcode:** open `MyHealth.xcodeproj` in **Xcode 26+**, pick
  your team, confirm HealthKit + App Groups capabilities, build the
  **MyHealthWatch** scheme, run tests (`⌘U`), then follow the device
  checklist in `docs/TESTING.md`. The `MyHealthIPhone` target also builds
  directly from Xcode for local simulator testing.

## HealthKit permissions (watch build only)

Requested at onboarding: heart rate, resting heart rate, HRV (SDNN), sleep
analysis, steps, active energy, VO2 max, walking heart-rate average, and
workouts. The watch app writes only workouts you record in it. The iPhone
edition uses no HealthKit. See `docs/HEALTH_DATA.md` and `docs/PRIVACY.md`.

## Documentation

- `docs/ANALYSIS.md` — Stage 1 reference analysis (A–T) + decision matrix
- `docs/SPEC.md` — product spec, screens, flows
- `docs/ARCHITECTURE.md` — layers, targets, concurrency, errors, import flow
- `docs/ALGORITHMS.md` — every formula, weight, and safety boundary
- `docs/HEALTH_DATA.md` — HealthKit mapping, availability states, import bounds
- `docs/PRIVACY.md` — privacy architecture and retention
- `docs/TESTING.md` — test suites, mock scenarios, device checklist
- `docs/RELEASE.md` — signing, App Store metadata, submission checklist

## Medical disclaimer

myhealth is a wellness application. It does not diagnose, treat, or monitor
disease and is not a substitute for medical advice. Stress and Energy are
app-generated wellness estimates.
