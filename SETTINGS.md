# TKEO Pinch Detection Settings

This document explains each parameter in the TKEO (Teager-Kaiser Energy Operator) pinch detection algorithm and its impact on detection sensitivity and accuracy.

## Overview

The pinch detection algorithm uses a multi-stage pipeline:
1. **Signal Fusion** - Combines accelerometer and gyroscope data
2. **Bandpass Filtering** - Isolates frequencies relevant to pinch gestures
3. **TKEO Energy Calculation** - Computes instantaneous energy of the signal
4. **Adaptive Thresholding** - Uses MAD (Median Absolute Deviation) for dynamic baseline
5. **Peak Detection** - Identifies candidate pinch events
6. **Validation** - Template matching and rejection filters

---

## Primary Sensitivity Parameters

These are the most impactful parameters for tuning detection sensitivity.

### Gate K (Gate Threshold)
- **Key:** `tkeo_gateThreshold`
- **Default:** 3.5
- **Range:** 1.0 - 6.0
- **Unit:** Standard deviations (σ)

**What it does:** Sets the threshold for a signal peak to be considered a pinch candidate. The threshold is calculated as `MAD_baseline × gateK`.

**Impact:**
- **Lower values (1.0-2.5):** More sensitive, detects lighter pinches, but increases false positives from noise and movement
- **Higher values (4.0-6.0):** Less sensitive, requires stronger pinches, but very few false positives
- **Recommended starting point:** 2.5-3.5

**When to adjust:**
- Getting too few detections? → Lower gateK
- Getting false positives during normal movement? → Raise gateK

---

### NCC Threshold (Template Confidence)
- **Key:** `tkeo_templateConfidence`
- **Default:** 0.6
- **Range:** 0.3 - 0.9
- **Unit:** Normalized correlation coefficient (0-1)

**What it does:** Minimum correlation score required when matching a candidate against trained pinch templates.

**Impact:**
- **Lower values (0.3-0.5):** Accepts more varied pinch patterns, but may accept non-pinch movements
- **Higher values (0.7-0.9):** Requires very close match to trained templates, may reject valid but atypical pinches
- **Recommended:** 0.55-0.65

**When to adjust:**
- Valid pinches being rejected? → Lower threshold
- Non-pinch movements being detected? → Raise threshold

---

### Gyro Veto Threshold
- **Key:** `tkeo_gyroVetoThresh`
- **Default:** 2.5
- **Range:** 0.5 - 5.0
- **Unit:** radians/second (rad/s)

**What it does:** Rejects candidates that occur during significant wrist rotation. High gyroscope activity typically indicates arm movement rather than a finger pinch.

**Impact:**
- **Lower values (0.5-1.5):** Strict motion rejection, may miss pinches during slight movement
- **Higher values (3.0-5.0):** Allows pinches during more movement, but may accept false positives from gestures
- **Recommended:** 2.0-3.0

**When to adjust:**
- Pinches not detected while walking/moving? → Raise threshold
- Getting false positives from arm movements? → Lower threshold

---

### Amplitude Surplus
- **Key:** `tkeo_amplitudeSurplus`
- **Default:** 2.5
- **Range:** 1.0 - 5.0
- **Unit:** Standard deviations (σ)

**What it does:** Additional amplitude check requiring the peak to exceed the local baseline by this many standard deviations.

**Impact:**
- **Lower values (1.0-2.0):** Accepts weaker signals, more sensitive
- **Higher values (3.0-5.0):** Requires stronger, more distinct peaks
- **Recommended:** 2.0-3.0

**When to adjust:**
- Similar to gateK, but specifically filters based on peak prominence

---

## Timing Parameters

These control the temporal aspects of detection.

### ISI Threshold (Inter-Spike Interval)
- **Key:** `tkeo_isiThreshold`
- **Default:** 220
- **Range:** 100 - 500
- **Unit:** milliseconds (ms)

**What it does:** Minimum time required between consecutive pinch detections. Prevents a single pinch from being counted multiple times.

**Impact:**
- **Lower values (100-150):** Allows rapid consecutive pinches, but may double-count single pinches
- **Higher values (300-500):** Ensures separation, but may miss rapid deliberate pinches
- **Recommended:** 200-300 for normal dhikr pace

**When to adjust:**
- Double-counting single pinches? → Raise ISI
- Can't count rapid pinches? → Lower ISI

---

### Refractory Period
- **Key:** `tkeo_refractoryMs`
- **Default:** 150
- **Range:** 50 - 300
- **Unit:** milliseconds (ms)

**What it does:** Hard lockout period after a detection during which no new candidates are considered.

**Impact:**
- Similar to ISI but acts earlier in the pipeline
- **Lower values:** More responsive to rapid pinches
- **Higher values:** More conservative, prevents artifacts

---

### Gyro Veto Hold
- **Key:** `tkeo_gyroVetoHoldMs`
- **Default:** 100
- **Range:** 0 - 300
- **Unit:** milliseconds (ms)

**What it does:** After high gyroscope activity, requires this duration of "quiet" before enabling detection again.

**Impact:**
- **Lower values (0-50):** Quick recovery after movement
- **Higher values (150-300):** Ensures arm has settled before detecting
- **Recommended:** 80-150

---

### Min/Max Width
- **Key:** `tkeo_minWidthMs`, `tkeo_maxWidthMs`
- **Defaults:** 70ms, 350ms
- **Unit:** milliseconds (ms)

**What they do:** Define the acceptable duration range for a pinch event. Events shorter or longer are rejected.

**Impact:**
- **minWidth:** Filters out very brief noise spikes (too fast to be a real pinch)
- **maxWidth:** Filters out slow movements that aren't pinches

**Typical pinch duration:** 80-250ms

---

### Window Pre/Post
- **Key:** `tkeo_windowPreMs`, `tkeo_windowPostMs`
- **Defaults:** 150ms, 150ms
- **Unit:** milliseconds (ms)

**What they do:** Define the time window around a peak for template matching. Extracts this window from the signal and compares to templates.

**Impact:**
- Must be wide enough to capture the full pinch waveform
- Too wide may include noise from adjacent events
- **Should match template training parameters**

---

### Ignore Start/End
- **Key:** `tkeo_ignoreStartMs`, `tkeo_ignoreEndMs`
- **Defaults:** 200ms, 200ms
- **Unit:** milliseconds (ms)

**What they do:** Ignore detections at the very start and end of a session to avoid artifacts from session start/stop.

**Impact:**
- Prevents false positives from putting on/taking off the watch
- 200-500ms is typically sufficient

---

## Signal Processing Parameters

These affect how the raw sensor data is processed.

### Sample Rate
- **Key:** `tkeo_sampleRate`
- **Default:** 50.0
- **Unit:** Hz (samples per second)

**What it does:** The rate at which sensor data is collected and processed.

**Note:** This should match the actual sensor update rate. Changing this without changing sensor configuration will cause timing issues.

---

### Bandpass Low/High
- **Key:** `tkeo_bandpassLow`, `tkeo_bandpassHigh`
- **Defaults:** 3.0 Hz, 20.0 Hz
- **Unit:** Hertz (Hz)

**What they do:** Define the frequency band of interest. Frequencies outside this range are attenuated.

**Impact:**
- **Low cutoff (3 Hz):** Removes slow drift and gravity effects
- **High cutoff (20 Hz):** Removes high-frequency noise
- **Pinch gestures typically have energy in 5-15 Hz range**

---

### Accel/Gyro Weights
- **Key:** `tkeo_accelWeight`, `tkeo_gyroWeight`
- **Defaults:** 1.0, 1.5
- **Unit:** Multiplier

**What they do:** Relative weights for combining accelerometer and gyroscope signals into the fused signal.

**Impact:**
- Higher gyro weight emphasizes rotational aspects of pinch
- Higher accel weight emphasizes linear motion
- **Recommended:** Keep gyro slightly higher (1.2-1.5) as pinches have a distinctive rotational signature

---

### MAD Window
- **Key:** `tkeo_madWinSec`
- **Default:** 3.0
- **Unit:** seconds

**What it does:** Duration of the sliding window for computing the MAD (Median Absolute Deviation) baseline.

**Impact:**
- **Shorter (1-2s):** Adapts quickly to changing conditions, but may be unstable
- **Longer (4-5s):** Stable baseline, but slow to adapt
- **Recommended:** 2.5-3.5 seconds

---

### Gate Ramp
- **Key:** `tkeo_gateRampMs`
- **Default:** 0
- **Unit:** milliseconds (ms)

**What it does:** Gradually ramps up the threshold at session start to avoid startup transients.

**Impact:**
- Set to 500-1000ms if getting false positives at session start
- Set to 0 if you want immediate detection capability

---

### Pre-Quiet
- **Key:** `tkeo_preQuietMs`
- **Default:** 0
- **Unit:** milliseconds (ms)

**What it does:** Requires a "quiet" period before a peak to be considered valid.

**Impact:**
- Helps reject peaks that are part of ongoing motion
- Set to 100-200ms for stricter filtering

---

## Validation Parameters

### Use Template Validation
- **Key:** `tkeo_useTemplateValidation`
- **Default:** true
- **Type:** Boolean

**What it does:** Enables/disables template matching validation.

**Impact:**
- **Enabled:** Uses trained templates to validate candidates (recommended)
- **Disabled:** Relies only on energy-based detection (more false positives, but detects any strong peak)

---

## Tuning Recommendations

### For More Sensitive Detection (catching light pinches)
1. Lower `gateK` to 2.0-2.5
2. Lower `nccThresh` to 0.5
3. Lower `amplitudeSurplus` to 1.5-2.0
4. Raise `gyroVetoThresh` to 3.0

### For Fewer False Positives (strict detection)
1. Raise `gateK` to 4.0-5.0
2. Raise `nccThresh` to 0.7
3. Raise `amplitudeSurplus` to 3.0
4. Lower `gyroVetoThresh` to 1.5-2.0

### For Active Movement (walking while doing dhikr)
1. Raise `gyroVetoThresh` to 3.5-4.0
2. Raise `gyroVetoHoldMs` to 150-200
3. Slightly raise `gateK` to compensate for motion noise

### For Rapid Counting
1. Lower `isiThreshold` to 150-180
2. Lower `refractoryMs` to 100
3. Keep other settings moderate

---

## Debugging Tips

1. **Check the Watch detector metadata** in session details to see rejection statistics
2. **"Rejected by Template"** - Lower `nccThresh` or check if templates match your pinch style
3. **"Rejected by Gyro Veto"** - Raise `gyroVetoThresh` if you're moving during dhikr
4. **"Rejected by Amplitude"** - Lower `amplitudeSurplus` for lighter pinches
5. **"Rejected by ISI"** - Raise `isiThreshold` if double-counting, lower if missing rapid pinches
