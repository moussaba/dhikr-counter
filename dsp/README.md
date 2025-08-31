# Pinch Detection Lab — Wrist Accelerometer (Energy-Envelope Method)

This repo/notebook provides an end-to-end lab for developing a **pinch detector** from wrist-worn accelerometer data (e.g., Apple Watch). It loads recordings, removes gravity, isolates the “pinch” band, converts the signal to an **energy envelope**, applies **adaptive thresholds with hysteresis and refractory**, visualizes results, and exports detected pinch events.

## What’s inside

* **Notebook:** `PinchDetectionLab.ipynb`
* **Recordings (expected):**

  * `~/Downloads/WristMotion.csv` — stationary with pinches
  * `~/Downloads/WristMotion Walking.csv` — \~22 s walking baseline
* **Auto sample data:** If the above files are missing, the notebook **creates realistic sample CSVs** in `~/Downloads` so you can run the pipeline immediately.

---

## Quick start

1. Create and activate a venv, then install deps:

```bash
python -m venv .venv
source .venv/bin/activate   # (Windows: .venv\\Scripts\\activate)
pip install -r requirements.txt
```

2. Launch Jupyter and open the notebook:

```bash
python -m ipykernel install --user --name pinch-env
jupyter notebook
```

3. Run the notebook **top-to-bottom**. If your CSVs aren’t present, it will generate sample data in `~/Downloads`.

---

## Expected data format

**CSV** with:

* A time column named one of
  `time, timestamp, ts, t, date, datetime, elapsed, elapsed_s, seconds, seconds_elapsed`
  (units can be seconds, milliseconds, or microseconds; the notebook auto-detects and normalizes)
* Accelerometer axes (any capitalization):
  Prefer Apple Watch names: `userAccelerationX`, `userAccelerationY`, `userAccelerationZ`
  Fallback patterns supported: `accel_x`, `acceleration_y`, etc.

> If detection fails, set `time_col`, `ax`, `ay`, `az` explicitly in `load_accel(...)`.

---

## Algorithm (at a glance)

1. **Magnitude & gravity removal**
   $|a|=\sqrt{x^2+y^2+z^2}$ to be orientation-robust → low-pass to estimate gravity (\~0.5 Hz) → subtract to get linear acceleration.

2. **Band-pass behavior (HP → LP)**

   * High-pass at \~4 Hz (removes gait/arm-swing at 1–3 Hz)
   * Low-pass at \~18 Hz (removes high-frequency hiss)
     Implemented as Butterworth biquads (zero-phase in notebook), with 1-pole fallbacks if SciPy is unavailable.

3. **Energy envelope**
   Band-passed signal $y[n]$ → square $z[n]=y[n]^2$ → smooth via EMA (τ≈0.2 s) or moving average to form envelope $e[n]$.

4. **Adaptive thresholds + hysteresis**
   Baseline $b[n]=\text{EMA}(e)$ and variability $v[n]=\text{EMA}(|e-b|)$.
   High/low thresholds: $T_{hi}=b+k_{hi}v$, $T_{lo}=b+k_{lo}v$.

5. **Event detection**
   State machine: cross above $T_{hi}$ for ≥ `min_duration` → **emit one event** → enforce `refractory` → return to idle below $T_{lo}$.

---

## Key parameters (defaults)

| Parameter        | Meaning                           | Default    |
| ---------------- | --------------------------------- | ---------- |
| `gravity_fc`     | Gravity LPF cutoff                | 0.5 Hz     |
| `hp_cut`         | High-pass cutoff (reject gait)    | 4 Hz       |
| `lp_cut`         | Low-pass cutoff (reject hiss)     | 18 Hz      |
| `env_method`     | Envelope smoother                 | `"ema"`    |
| `env_tau`        | Envelope EMA time constant        | 0.20 s     |
| `tau_b`, `tau_v` | Baseline / variability EMA τ      | 2.0 s each |
| `k_hi`, `k_lo`   | Threshold multipliers             | 4.0 / 2.5  |
| `refractory`     | Hold-off after a detection        | 0.30 s     |
| `min_duration`   | Min time above `T_hi` to validate | 0.10 s     |

**Tuning tips**

* False positives (walking): increase `hp_cut` to 5–6 Hz or `k_hi` to 5.0.
* Missed pinches: lower `k_hi` to 3.0–3.5 or shorten `refractory` to \~0.20 s.
* Spiky envelope: increase `env_tau` slightly (0.25–0.30 s).

---

## Outputs

* **Plots** (each in a separate figure):

  1. |a| magnitude + gravity estimate
  2. Welch PSD of gravity-removed magnitude
  3. Band-passed waveform
  4. Envelope + thresholds + detected events (markers)

* **CSV exports** in `~/Downloads/`:

  * `Stationary_PinchEvents.csv`
  * `Walking_PinchEvents.csv`
    Columns: `sample_index`, `time_sec`.

---

## Notebook structure

* **Helpers:** robust CSV loader, time normalization, axis detection
* **Filters:** Butterworth HP/LP (prefer), 1-pole fallbacks with guardrails
* **PSD:** Welch (or periodogram fallback) + optional peak estimate
* **Envelope & thresholds:** EMA or MA; adaptive baseline & variability
* **Detector:** hysteresis + refractory state machine
* **Pipeline:** one function runs everything and returns a summary

---

## Robustness & error handling (your patch)

* **Column detection:** Adds Apple Watch patterns `userAccelerationX/Y/Z`; expands time column list to include `seconds_elapsed`.
* **Sampling rate (`fs`) detection:** Ignores non-finite/non-positive diffs; safe fallbacks if diffs are empty, negative, or yield unrealistic `fs`.
* **Filter safety:** All Butterworth calls validate `fs` and cutoff (`fc < fs/2`); fall back to 1-pole filters with clear warnings if anything fails.
* **Data paths & sample data:**

  * Uses `~/Downloads/WristMotion*.csv` as defaults.
  * Auto-generates realistic sample datasets if files are missing.
* **Exports:** Writes event CSVs to `~/Downloads` (not `/mnt/data`).
* **Logging:** Prints loaded columns, detected time column, inferred `fs`, axis choices, magnitude range, and any fallback warnings.

These fixes resolved `fs = 0.0 Hz` issues and made the notebook resilient to common Apple Watch CSV schemas.

---

## Validation workflow

1. Run on **stationary with pinches** → verify clean, distinct detections.
2. Run on **walking baseline** → verify no false positives.
3. Adjust `hp_cut`, `k_hi/k_lo`, `refractory`, `min_duration` until both hold.

---

## Porting to device (Swift/Kotlin)

* Use **causal** IIR filters (biquad HP and LP) and **EMA** for envelope/baseline—O(1) memory, low CPU.
* Replace zero-phase `filtfilt` with forward-only biquads.
* Keep the same thresholds and state machine; only re-tune constants if the on-device sampling rate differs.

---

## Requirements

See `requirements.txt`:

```
numpy>=1.26
pandas>=2.2
matplotlib>=3.8
scipy>=1.11
notebook>=7.2
ipykernel>=6.29
ipywidgets>=8.1   # optional
nbformat>=5.10    # optional
```

---

## Troubleshooting

* **No time column detected:** rename or pass `time_col` directly to `load_accel(...)`.
* **Axes misidentified:** rename columns to standard names or pass `ax, ay, az` explicitly.
* **Filter errors:** check `fs` printout; ensure cutoffs satisfy `fc < fs/2`.
* **False positives while walking:** raise `hp_cut` and/or `k_hi`.
* **No events detected:** lower `k_hi`, shorten `refractory`, and confirm pinch frequency in the PSD.

---

## License

Add your preferred license here (MIT/Apache-2.0/etc.).
