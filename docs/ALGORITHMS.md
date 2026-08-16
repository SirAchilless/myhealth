# myhealth — Algorithms

Every score is transparent, personal-baseline-relative, and honest about
missing data. No formula is copied from any proprietary product; the building
blocks are published exercise-science and statistics methods. All constants
live in `MyHealthWatch/Algorithms/ScoringConstants.swift`.

Common rules:
- **Missing input → excluded + weight redistributed.** Below a minimum of
  available weight, no score is produced at all (an explanatory state is
  shown instead).
- **Baseline-relative language only.** "12% below your recent baseline",
  never "unhealthy".
- **No medical claims.** Stress and Energy are explicitly labeled wellness
  estimates.

---

## Baselines

- **Inputs:** per-day values (resting HR, sleep minutes, load points) or
  sparse samples (HRV SDNN, ms).
- **Method:** median and median absolute deviation (MAD) over a rolling
  7/14/30-day window (default 14). Robust z-score = (x − median) / (1.4826 ×
  MAD). MAD ≈ 0 or < 5 samples → baseline insufficient → factor excluded.
- **Why robust:** wearable data is outlier-prone (missed readings, illness,
  alcohol); median/MAD resist contamination far better than mean/σ.
- **Confidence role:** ≥ 10 samples = strong baseline; 5–9 usable but lowers
  confidence.

## Recovery (0–100)

| Factor | Weight | Normalization |
| --- | --- | --- |
| HRV (SDNN) | 0.35 | robust z, clamp ±2 → contribution −1…+1 (higher better) |
| Resting HR | 0.20 | robust z, clamp ±2 → **negated** (lower better) |
| Sleep duration vs personal need | 0.25 | (fulfillment − 1) / 0.25, clamped |
| Sleep timing consistency | 0.10 | −(midpoint deviation / 90 min), clamped 0…−1 |
| Recent load (ACWR) | 0.10 | −((ratio − 1.3)/0.7) above 1.3; +0.3-capped bonus below 0.8 |

- **Output:** `50 + 50 × Σ(wᵢcᵢ) / Σ(wᵢ available)`, rounded, clamped 0–100.
- **Insufficient:** available weight < 0.40 → no score; missing inputs listed.
- **Confidence:** 3/3 core factors (HRV+RHR+sleep) → High (if any baseline
  ≥ 10 samples) else Medium; 2/3 → Medium; 1 → Low; 0 → Insufficient.
- **Categories:** 0–29 Very Low · 30–49 Low · 50–69 Moderate · 70–84 Good ·
  85–100 Excellent.
- **Safety:** says nothing about health status, illness, or fitness; purely
  relative to the user's own recent data.

## Sleep (0–100)

| Component | Weight | Achieved |
| --- | --- | --- |
| Need fulfillment | 0.45 | min(asleep / personalNeed, 1) |
| Efficiency | 0.30 | min(asleep / inBed ÷ 0.95, 1) |
| Schedule consistency | 0.15 | 1 − min(midpointDeviation / 90 min, 1), circular over midnight |
| Disturbances | 0.10 | 1 − min(awakeShare / 0.30, 1) |

- Personal need: median asleep minutes over the last ≤ 14 nights, clamped
  5–10 h; default 8 h (user-adjustable) until history exists.
- **Insufficient:** < 60 min asleep (or no night) → no score.
- **Confidence:** High with all 4 components; Medium otherwise.
- Stages (Deep/Core/REM) are displayed informationally, not scored (science
  on "optimal" stage shares is not settled enough to score honestly).
- **Deficit** shown when ≥ 15 min below need.

## Load (0–10 daily) + ACWR

- **Per workout:** Banister TRIMP = minutes × 0.64 × e^(1.92 × HR-reserve),
  reserve = (avgHR − resting) / (maxHR − resting). MaxHR = user override or
  Tanaka 208 − 0.7 × age.
- **Fallbacks (labeled, confidence-lowering):** active kcal × 0.025; else
  minutes × 0.05.
- **Day load:** Σ workout points; displayed as min(points / 10, 10).
- **ACWR:** mean daily load 7d ÷ 28d, reported after ≥ 14 days of history.
  Bands: < 0.8 Recovering · 0.8–1.3 Productive · > 1.3 High.
- **Safety:** training-load ratio is a monitoring convention, not an injury
  predictor; copy avoids promising anything.

## Stress (Low / Moderate / Elevated)

- 10-minute windows of heart rate. Pressure = clamp((avgHR − restingBaseline)
  / 40 bpm, 0, 1). HRV suppression = clamp(1 − HRV / baselineMedian, 0, 1).
- Window index = 100 × (0.65 × pressure + 0.35 × suppression); windows inside
  recorded sleep × 0.6. Reported value weights the newest window 3×.
- **Confidence:** both signals High; one Medium; none → no meaningful score.
- **Safety:** always labeled "wellness estimate … not a medical measurement".
  Never mentions anxiety, depression, or any condition.

## Energy (0–100)

- 0.5 × Recovery + 0.3 × Sleep + 0.2 × (100 − min(todayLoad × 10, 100)),
  renormalized over available inputs. Requires Recovery **or** Sleep.
- **Confidence** = the weakest input's confidence (energy can't outrank its
  shakiest component).

## Coach (deterministic)

Rule-based over `CoachContext` — the same engine results the UI shows.
Priority: insufficient data → build-baseline guidance; recovery ≥ 70 → train
(unless ACWR High → moderate); 50–69 → moderate; < 50 → recovery focus.
Every answer lists data gaps instead of guessing. No LLM, no network.

## What myhealth intentionally does NOT claim

- No medical-grade accuracy, diagnosis, disease prediction, or treatment.
- No guarantee that following guidance improves outcomes.
- No fabricated values: every displayed number traces to a real sample or a
  labeled estimate (load fallbacks), and unavailability is shown honestly.
