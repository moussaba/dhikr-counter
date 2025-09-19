# Real-Time Watch Pinch Detection Implementation Plan

**Issues**: #28 (Port PinchDetector to Watch), #30 (Integrate StreamingPinchDetector), #22 (Real-time TKEO on Watch)

**Goal**: Implement real-time pinch detection directly on Apple Watch with immediate haptic feedback, eliminating iPhone dependency.

## Architecture Design

### Core Component: `StreamingPinchDetector`
- **API**: `process(frame: SensorFrame) -> PinchEvent?` (single-sample processing)
- **Stateful pipeline**: Maintains filter states, baselines, buffers internally
- **Fixed-size buffers**: Use `Deque` from swift-collections for circular buffers
- **Component-based**: Small stateful helpers for each pipeline stage

### Key Changes from Batch Processing
1. **Replace batch arrays** with streaming state machines
2. **Causal filtering only** - eliminate `bandpassZeroPhase` (lines 403-412)
3. **Ring buffer** for template window extraction (L ≈ 17-22 samples)
4. **Pre-expanded templates** at initialization

## Technical Solutions

### 1. Causality Constraint (Critical Change)
- **Remove**: `bandpassZeroPhase()` - uses future data, non-causal
- **Use**: Existing `bandpass()` function (lines 394-401) - already causal
- **Accept**: Small phase delay (~10-20ms) - template matching handles timing shifts
- **Leverage**: Existing `shiftArray()` and time-warp mechanisms compensate

### 2. Streaming API Design
```swift
public final class StreamingPinchDetector {
    public init(config: PinchConfig, templates: [PinchTemplate])

    @discardableResult
    public func process(frame: SensorFrame) -> PinchEvent?

    public func reset()
}
```

### 3. Internal Components
- `CausalBandpassFilter`: Wraps existing `BandPass` struct (lines 381-385)
- `TKEOOperator`: 3-sample buffer for streaming TKEO (1-sample delay)
- `StreamingBaselineMAD`: Reuse existing class (lines 451-491) - already perfect
- `StreamingPeakDetector`: State machine for gate crossing + refractory

### 4. Watch Optimizations
- **Memory**: Eliminate intermediate arrays, fixed-size circular buffers
- **CPU**: Template matching only on peak candidates (not every sample)
- **Battery**: Optional pause/resume based on app state
- **Latency**: ~150ms total (filter delay + postS window completion)

## Implementation Sequence (Risk-Minimized)

### Phase 1: Streaming DSP Core (Week 1)
- [ ] Create `StreamingPinchDetector` class structure
- [ ] Implement causal filter components
  - [ ] `CausalBandpassFilter` (wraps existing `BandPass`)
  - [ ] `TKEOOperator` with 3-sample sliding buffer
- [ ] Build streaming pipeline: filter → TKEO → L2 fusion → baseline/sigma
- [ ] **Validation**: Compare fused signal output vs batch processor

### Phase 2: Peak Detection State Machine (Week 1-2)
- [ ] Implement `StreamingPeakDetector` state machine
  - [ ] States: `belowGate`, `rising`, `falling`
  - [ ] Gate threshold computation per sample
  - [ ] Refractory period tracking
- [ ] Integrate gyro veto as run-length counter (replace array logic lines 693-697)
- [ ] **Validation**: Verify peak timing matches batch version (±phase delay)

### Phase 3: Template Matching Integration (Week 2)
- [ ] Pre-expand templates at initialization
  - [ ] Time-warp grid: [0.95, 1.00, 1.05]
  - [ ] Resample all to L samples
- [ ] Add ring buffer window extraction (capacity ~32-40 samples)
- [ ] Port NCC correlation (reuse lines 534-554)
- [ ] Port quality gates:
  - [ ] Amplitude surplus guard (lines 823-830)
  - [ ] ISI threshold (lines 832-839)
- [ ] **Validation**: End-to-end event detection comparison

### Phase 4: Watch Integration (Week 3)
- [ ] Create `StreamingPinchDetector.swift` in Watch target
- [ ] Connect to `CMMotionManager` at 50Hz
- [ ] Add haptic feedback: `WKInterfaceDevice.current().play(.click)`
- [ ] Integrate with existing `DhikrDetectionEngine`
- [ ] Thread safety: dedicated serial DispatchQueue
- [ ] **Validation**: On-device testing and profiling

### Phase 5: Optimization & Polish (Week 3-4)
- [ ] Battery/CPU profiling with Instruments
- [ ] Parameter tuning for causal pipeline
- [ ] Background processing and lifecycle management
- [ ] Configuration sync via WatchConnectivity (optional)
- [ ] Unit tests comparing streaming vs batch detection

## Watch-Specific Parameters

### Recommended Starting Values
```swift
fs: 50.0 Hz
bandpass: 3.0-20.0 Hz (causal IIR only)
windowPre: 120-150ms
windowPost: 120-150ms
gateK: 2.8-3.2 (may need tuning for causal)
amplitudeSurplusThresh: 1.5 (more sensitive than iPhone)
nccThresh: 0.60-0.65 (compensate for causal timing)
refractoryMs: 150-200ms
isiThresholdMs: 200-220ms
```

### Memory Budget
- Ring buffer: ~32-40 samples × 1 fused signal = ~160 floats (640 bytes)
- Expanded templates: 12 templates × 3 warps × 17 samples = ~2KB
- Filter states: ~6 biquads × 5 floats each = ~120 bytes
- **Total**: <5KB for core processing state

## Success Criteria

1. **Performance**: <0.5ms per-sample processing time at 50Hz
2. **Latency**: <200ms from gesture peak to haptic feedback
3. **Battery**: <5% additional drain during active detection
4. **Quality**: >90% detection rate parity with iPhone batch processing
5. **Memory**: <10MB total app footprint

## Risk Mitigation

### High Risk Items
- **Causality impact on detection quality** → Extensive validation with recorded data
- **Watch CPU/battery constraints** → Early profiling with Instruments
- **Template matching performance** → Pre-computation and efficient NCC

### Fallback Strategies
- Reduce template count if CPU bound (12 → 6 templates)
- Lower sample rate if battery critical (50Hz → 25Hz)
- Simplified quality gates if latency critical
- Two-stage feedback: fast gate confirmation + delayed NCC confirmation

## Key Code References

### Reuse From Existing PinchDetector.swift
- `Biquad` struct (lines 336-354): Perfect for streaming
- `BandPass` struct (lines 381-385): Causal filter cascade
- `makeBandPass()` (lines 387-392): Filter factory
- `StreamingBaselineMAD` (lines 451-491): Already streaming-ready
- `resampleLinear()` (lines 557-578): Template preprocessing
- `ncc()` (lines 534-554): Template correlation
- `shiftArray()` (lines 581-591): Time alignment

### Replace/Avoid
- `bandpassZeroPhase()` (lines 403-412): Non-causal, uses future data
- Array-based TKEO (lines 431-447): Replace with streaming 3-sample buffer
- Batch peak detection (lines 513-532): Replace with state machine
- Large array operations throughout `_process()`: Convert to per-sample

## Expert Recommendations Summary

**GPT-5 Focus**: Detailed streaming state machine design, concrete API proposals, Watch-specific optimization strategies

**Gemini Focus**: Clean architecture principles, phased validation approach, component isolation for testing

**Combined Approach**: Stateful streaming detector with causal filtering, pre-computed templates, and validation-driven development