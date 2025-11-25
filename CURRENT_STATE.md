# Current State: Phase 4 - Watch Deployment

**Date**: 2025-11-25
**Branch**: `phase4-watch-deployment`
**Last Commit**: `62ae4ad` - "Add debug statistics tracking for streaming pinch detector"

## Project Context
Implementing real-time pinch detection for Apple Watch to eliminate iPhone dependency. Following the plan in `WATCH_REALTIME_DETECTION_PLAN.md`.

**Issues being addressed**: #28 (Port PinchDetector to Watch), #30 (Integrate StreamingPinchDetector), #22 (Real-time TKEO on Watch)

## Phase 1: ✅ COMPLETED
- StreamingPinchDetector.swift core streaming DSP pipeline
- Single-sample processing API: `process(frame: SensorFrame) -> PinchEvent?`
- Causal filtering, TKEO operators, L2 sensor fusion
- Reuses O(1) StreamingBaselineMad

## Phase 2: ✅ COMPLETED
- StreamingPeakDetector state machine (belowGate → rising → falling)
- Gate threshold computation per sample
- Refractory period tracking
- `useTemplateValidation` toggle for energy-only mode

## Phase 3: ✅ COMPLETED
- Pre-expanded templates with time-warp grid
- vDSP-accelerated NCC computation
- Quality gates: amplitude surplus, ISI threshold, gyro veto
- TemplateRecorder for capturing new patterns
- Debug statistics tracking for validation

## Phase 4: 🔄 IN PROGRESS - Watch Deployment

### Goal
Deploy StreamingPinchDetector to Watch target with real-time haptic feedback for pinch detection.

### Implementation Plan

#### Step 1: Create Shared Types for Watch Target
**Files to create**: `Shared/PinchTypes.swift`

The Watch target needs access to shared types that are currently in `PinchDetector.swift`:
- `SensorFrame` - Input sensor data structure
- `PinchEvent` - Detection result structure
- `PinchConfig` - Algorithm configuration
- `PinchTemplate` - Template data for matching

**Approach**: Create a shared Swift file that can be included in both iOS and watchOS targets.

#### Step 2: Add StreamingPinchDetector to Watch Target
**Files to add**:
- `DhikrCounter Watch App/StreamingPinchDetector.swift` (copy from iOS)

**Key considerations**:
- File already uses `import Accelerate` which is available on watchOS
- No UIKit dependencies - pure computation
- ~1200 lines, includes all streaming components:
  - `StreamingDetectorStats` - Debug statistics
  - `StreamingPinchDetector` - Main detector
  - `CausalBandpassFilter` - IIR filtering
  - `TKEOOperator` - Energy operator
  - `StreamingBaselineMad` - O(1) baseline estimation
  - `StreamingPeakDetector` - State machine
  - `StreamingTemplateMatcher` - Template matching
  - `CircularBuffer` - Signal history
  - `TemplateRecorder` - Pattern capture

#### Step 3: Update DhikrDetectionEngine
**File**: `DhikrCounter Watch App/DhikrDetectionEngine.swift`

**Current state**: Collects raw sensor data at 50Hz but does NOT perform pinch detection.

**Changes required**:
```swift
// Add property
private var streamingDetector: StreamingPinchDetector?

// In startRawDataCollection():
// Initialize detector with config and templates
let config = PinchConfig()  // Use defaults
let templates = loadBundledTemplates()
streamingDetector = StreamingPinchDetector(
    config: config,
    templates: templates,
    useTemplateValidation: true  // or false for energy-only mode
)

// In collectRawSensorData(_:):
// Create SensorFrame from CMDeviceMotion
let frame = SensorFrame(
    t: motion.timestamp,
    ax: Float(motion.userAcceleration.x),
    ay: Float(motion.userAcceleration.y),
    az: Float(motion.userAcceleration.z),
    gx: Float(motion.rotationRate.x),
    gy: Float(motion.rotationRate.y),
    gz: Float(motion.rotationRate.z)
)

// Process and detect
if let event = streamingDetector?.process(frame: frame) {
    DispatchQueue.main.async {
        self.registerStreamingPinch(event: event)
    }
}
```

#### Step 4: Add Haptic Feedback
**In DhikrDetectionEngine**:
```swift
private func registerStreamingPinch(event: PinchEvent) {
    pinchCount += 1
    lastDetectionTime = Date()

    // Haptic feedback
    let newMilestone = calculateMilestone(count: pinchCount)
    if newMilestone > currentMilestone {
        currentMilestone = newMilestone
        provideMilestoneHaptic(milestone: newMilestone)
    } else {
        WKInterfaceDevice.current().play(.click)
    }

    // Log detection for data transfer
    logDetectionEvent(score: event.confidence, ...)
}
```

#### Step 5: Bundle Default Templates
**Options**:
1. **Bundle JSON file**: Include `default_template.json` in Watch app bundle
2. **Hardcoded default**: Use `PinchDetector.createDefaultTemplate()`
3. **Transfer from iPhone**: Use WatchConnectivity to sync templates

**Recommended**: Start with hardcoded default, add template sync later.

### Thread Safety Architecture

```
┌─────────────────────────────────────────┐
│         CMMotionManager (50Hz)          │
│         (motionQueue - serial)          │
└───────────────────┬─────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│     StreamingPinchDetector.process()    │
│         (on motionQueue)                │
└───────────────────┬─────────────────────┘
                    │
                    ▼ PinchEvent?
┌─────────────────────────────────────────┐
│     DispatchQueue.main.async {}         │
│     - registerStreamingPinch()          │
│     - WKInterfaceDevice.play(.click)    │
│     - Update UI state                   │
└─────────────────────────────────────────┘
```

### Files to Modify/Create

| File | Action | Notes |
|------|--------|-------|
| `Shared/PinchTypes.swift` | CREATE | Shared types for both targets |
| `DhikrCounter Watch App/StreamingPinchDetector.swift` | CREATE | Copy from iOS target |
| `DhikrCounter Watch App/DhikrDetectionEngine.swift` | MODIFY | Integrate streaming detector |
| `DhikrCounter.xcodeproj` | MODIFY | Add files to Watch target (manual in Xcode) |

### Validation Checklist

- [ ] Build succeeds for Watch target
- [ ] Detector initializes without crash
- [ ] Haptic feedback fires on pinch detection
- [ ] No excessive battery drain (monitor in Xcode)
- [ ] Processing time <0.5ms per sample (20ms budget at 50Hz)
- [ ] Memory footprint stable (no leaks)
- [ ] Works with template validation enabled
- [ ] Works with template validation disabled (energy-only)

### Performance Targets

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Processing latency | <0.5ms/sample | CFAbsoluteTimeGetCurrent() |
| Detection latency | <200ms | Time from motion to haptic |
| Memory footprint | <10MB | Xcode Memory Gauge |
| Battery impact | <5% additional | Energy Impact in Xcode |

### Risk Mitigation

1. **vDSP availability**: Already tested - Accelerate framework works on watchOS
2. **Memory constraints**: CircularBuffer has fixed size, no unbounded growth
3. **CPU spikes**: All operations are O(1) or O(n) where n is small constant
4. **Template loading**: Use fallback to default if bundle load fails

## Notes for Resume

- Branch created: `phase4-watch-deployment`
- Need to add files to Watch target in Xcode project
- Current DhikrDetectionEngine only collects data, doesn't detect
- Streaming detector ready to integrate (1200 lines, well-tested)
