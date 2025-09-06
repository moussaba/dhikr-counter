# Swift TKEO Implementation Guidelines

*Generated from GPT-5 consensus analysis for iPhone-side pinch detection*

## Verdict
Strong user value proposition with manageable implementation risks; technically feasible on-device in Swift with Accelerate, Swift Concurrency, and Swift Charts.

## Technical Feasibility

**Achievable**: The TKEO pipeline (band-pass, jerk, TKEO, MAD thresholds, NCC template check) is straightforward to implement using Accelerate/vDSP for filtering, resampling, vector math, and correlation. Processing 100–200 Hz watch streams in near-real-time on iPhone is well within budget (<5 ms per 10k samples on modern devices).

**Core dependencies:**
- Accelerate (vDSP) for FIR/IIR filtering, convolution, MAD, NCC
- Swift Concurrency for background processing
- Swift Charts for overlay visualization

**No fundamental blockers**; attention needed for time alignment and sample-rate normalization.

## Implementation Timeline

**Effort estimate (single iOS dev with Accelerate experience):**
- Core pipeline (filtering, TKEO, gating): 2–3 days
- Template training/loading + NCC: 1–2 days
- Integration with Charts + UI config: 1–2 days
- Validation/tuning: 3–5 days with datasets

## Data Models

```swift
struct SensorFrame {
    let t: TimeInterval
    let ax, ay, az: Float  // m/s²
    let gx, gy, gz: Float  // rad/s
}

struct PinchEvent {
    let tPeak, tStart, tEnd: TimeInterval
    let confidence, gateScore, ncc: Float
}

struct PinchConfig {
    let fs: Float
    let bandpassLow: Float = 3.0
    let bandpassHigh: Float = 20.0
    let accelWeight: Float = 1.0
    let gyroWeight: Float = 1.5
    let madWinSec: Float = 3.0
    let gateK: Float = 3.5
    let refractoryMs: Float = 150
    let minWidthMs: Float = 60
    let maxWidthMs: Float = 400
    let nccThresh: Float = 0.6
    let windowPreMs: Float = 150
    let windowPostMs: Float = 250
}
```

## Core API

```swift
final class PinchDetector {
    init(config: PinchConfig, template: PinchTemplate)
    func process(frames: [SensorFrame]) -> [PinchEvent]
}
```

## Implementation Pipeline

### 1. Preprocessing
- **Resample** both accel and gyro to uniform fs (e.g., 100–128 Hz) using `vDSP_desamp` or polyphase FIR to maintain phase
- **Compute magnitudes** or axis selection:
  - Accel jerk: central difference per axis, then magnitude (recommend magnitude for orientation robustness)
  - `jerk[n] = (a[n+1] − a[n−1]) / (2*dt)`
  - For streaming, accept 1-sample latency or use causal IIR differentiator
  - Gyro: use rotationRate magnitude; optional jerk if it improves SNR
- **Band-pass 3–20 Hz** with zero-phase option for post-processing (filtfilt-like via forward/backward biquad)

### 2. TKEO + Fusion
- **TKEO**: `psi[n] = x[n]^2 − x[n−1]*x[n+1]` (central, 1-sample latency)
- For causal: `psi_c[n] = x[n]^2 − x[n−1]*x[n]` (slightly biased but online)
- **Rectify and smooth** with short moving average (20–30 ms) to stabilize peaks
- **Normalize** each channel by rolling median/MAD to reduce inter-session variance
- **Fuse**: `fused = 1.0*accelPsiNorm + 1.5*gyroPsiNorm`

### 3. Adaptive Baseline + Liberal Gate
- **Maintain rolling baseline** over `madWinSec` (2–4 s)
- **Threshold** = `median + k*MAD` (k≈3.0–4.0)
- Use **hysteresis** (enter at kHi, exit at kLo)
- **Detect local maxima** above threshold, merge peaks closer than `refractoryMs`
- **Enforce width bounds**
- **Gate score** = `(peak − median)/MAD` clipped to [0, 6]

### 4. Template Verification (NCC)
- **Extract window** `[−windowPreMs, +windowPostMs]` around peak from fused signal
- **Normalize window** to zero-mean/unit-variance
- **Compute NCC** with stored template(s) using `vDSP_normalize` + `vDSP_dotpr`
- **Accept if** `NCC ≥ nccThresh`
- **Confidence** = `0.6*NCC + 0.4*min(gateScore/5.0, 1.0)`

## Swift Integration Notes

### Filtering
- Use `vDSP_biquad` for IIR filters
- Design coefficients via Butterworth helper (precompute coefficients per fs)

### Resampling  
- Use vDSP or BNNS; prefer vDSP with polyphase FIR for quality

### Concurrency
- Run pipeline on `Task.detached`
- Stream chunks to keep memory low

### Charts Overlay
```swift
// Provide RuleMark at event tPeak with color gradient by confidence
RuleMark(x: .value("Time", event.tPeak))
    .foregroundStyle(Color.green.opacity(event.confidence))
    .annotation(position: .top) {
        Text(String(format: "%.2f", event.confidence))
    }

// Optional: shade [tStart, tEnd] with translucent RectangleMark  
RectangleMark(
    xStart: .value("Start", event.tStart),
    xEnd: .value("End", event.tEnd)
)
.foregroundStyle(Color.blue.opacity(0.2))
```

## Template Management

### Training
- From labeled windows, resample to standard fs, align on peak, z-normalize, average, re-normalize
- Store as JSON: `{fs, preMs, postMs, vectorLength, data[], channelsMeta, version}`

### Loading
- Validate metadata (fs, lengths)
- If mismatch, resample template to current fs
- Support multiple templates (per user or left/right) and pick max NCC

## Configuration Management

- `PinchConfig` persisted in UserDefaults or plist/JSON
- Expose developer UI for tuning (sliders for k, cutoffs, weights)
- Version configs and templates; include defaults and safe bounds
- Log chosen parameters in results for reproducibility

## Key Implementation Functions

```swift
// Core processing functions (pseudocode)
func preprocess(frames: [SensorFrame]) -> (accelMag: [Float], gyroMag: [Float], fs: Float, t: [TimeInterval])
func jerk(_ x: [Float], dt: Float) -> [Float]  
func bandpass(_ x: [Float], fs: Float, low: Float, high: Float) -> [Float]
func tkeo(_ x: [Float]) -> [Float]
func baselineMAD(_ z: [Float], winSec: Float, fs: Float) -> (median: [Float], mad: [Float])
func detectPeaks(_ z: [Float], thresh: [Float], refractory: Float) -> [PeakCandidate]
func ncc(window: [Float], template: [Float]) -> Float
```

## Validation Strategy

- Start with magnitude-only fusion; add per-axis fusion if needed
- Sweep parameters on labeled dataset; report ROC
- Calibrate `nccThresh` and `gateK` to hit desired precision/recall
- Add unit tests for each stage (filter stability, TKEO correctness, NCC invariance)

## Real-time Post-processing Considerations

- Run in batches (1–5 s) with overlap equal to max window size to avoid boundary effects
- Memory: keep rolling buffers for baseline/MAD; O(1) per sample
- Latency: with central differences and NCC, end-to-end latency ≈ pre+post window length; acceptable for post-session analysis

## Industry Context

- TKEO widely used for EMG/IMU event detection due to sensitivity to transient bursts
- Adaptive thresholds + template matching is best-practice for robust gesture detection without full ML
- Apple's Double Tap suggests similar multi-sensor fusion; using `userAcceleration` avoids gravity coupling

## Long-term Implications

- **Maintainability**: Encapsulate DSP in module with deterministic unit tests; version coefficients and templates
- **Scalability**: Adding new gestures can reuse pipeline with gesture-specific templates and weights  
- **Extensibility**: Optional per-user template personalization; runtime A/B configs

## Confidence Score
8/10 - High confidence in technical feasibility and iOS integration using well-understood DSP blocks; some uncertainty in parameter tuning and template generalization across users/hardware without labeled datasets.

---

## Gemini-Pro Consensus Analysis

### Key Agreement Points:
- ✅ **Technical feasibility is high** - TKEO algorithm is well-defined and Swift/Accelerate can handle it efficiently
- ✅ **Architecture is sound** - iPhone processing of Watch sensor data follows Apple's best practices
- ✅ **No fundamental blockers** - Core technology stack is appropriate and mature

### Critical Insights:
1. **Success depends heavily on tuning** - The biggest risk isn't implementation but achieving reliable performance through extensive parameter calibration
2. **User value is conditional** - High potential but only if accuracy/latency meet user expectations
3. **Timeline may be optimistic** - The 7-12 day estimate doesn't account for extensive tuning phase

### Key Recommendations:
- Allocate significant time for empirical testing and calibration with diverse users
- Prioritize robust WatchConnectivity data pipeline with graceful error handling
- Use Accelerate framework from day one for performance
- Plan for iterative parameter tuning as the primary development challenge

### Gemini-Pro Verdict:
*"The proposal is technically sound and leverages a standard, battery-conscious architecture, but its success is critically dependent on extensive real-world tuning and calibration of the TKEO algorithm to achieve reliable performance."*

**Consensus Confidence Score:** 8/10 - High confidence in technical approach, moderate uncertainty in tuning complexity

---

*This implementation guide provides the foundation for porting the Python TKEO pinch detection algorithm to Swift for iPhone-side post-processing of Watch session data.*