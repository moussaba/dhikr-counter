# Current State: Audio-Based Pinch Detection Prototype

**Date**: 2025-12-05
**Branch**: `issue-48-audio-pinch-detection`
**Status**: Testing audio sensitivity - ring clicks are hard to detect

## Problem Being Solved

Apple Watch microphone has low sensitivity for detecting subtle finger ring clicks:
- Baseline hovers around -68 dB
- Ring clicks barely register above baseline
- Tapping ring on table works, but finger-to-finger clicks don't

## Current Detection Approach (Dual Method)

The AudioPinchDetector now uses TWO detection methods:

1. **Threshold Method**: Signal > baseline + threshold
2. **Jump Method (NEW)**: Sudden jump of 2+ dB from previous buffer

Either method triggers detection (OR logic).

## Key Parameters (Current Defaults)

| Parameter | Value | Description |
|-----------|-------|-------------|
| `onsetThresholdDb` | 1.5 dB | Above baseline to trigger |
| `minJumpDb` | 2.0 dB | Minimum sudden jump to trigger |
| `refractoryPeriod` | 250 ms | Min time between detections |
| `baselineAlpha` | 0.03 | Baseline adaptation speed |
| `bufferSize` | 512 samples | ~10ms at 48kHz (faster response) |

## Baseline Adaptation (Asymmetric)

| Signal Level | Baseline Behavior |
|--------------|-------------------|
| Below baseline | Adapts quickly (normal) |
| 0-2 dB above | Adapts quickly (normal) |
| 2 dB to threshold | Adapts slowly (1/10th speed) |
| Above threshold | No adaptation (ignores spikes) |

## Files Modified This Session

| File | Changes |
|------|---------|
| `DhikrCounter Watch App/AudioPinchDetector.swift` | Dual detection, asymmetric baseline, smaller buffer |
| `DhikrCounter Watch App/AudioTestView.swift` | Loads settings from iPhone, shows settings by default |
| `DhikrCounter Watch App/WatchSessionManager.swift` | Added `getSetting()` helper, logs audio settings |
| `DhikrCounter Watch App/ContentView.swift` | Added Audio Detection Test link in Settings |
| `DhikrCounter Watch App/Info.plist` | Added NSMicrophoneUsageDescription |
| `DhikrCounter/CompanionContentView.swift` | Added Audio Detection settings section |
| `DhikrCounter/PhoneSessionManager.swift` | Added audio settings to Watch sync |

## iOS Settings UI

In iPhone app → Settings → "Audio Detection (Experimental)":
- Toggle to enable/disable
- Onset Threshold slider: 0.5 to 10.0 dB
- Refractory Period slider: 100 to 500 ms
- Must tap "Sync Now" to send to Watch

## Debug Info

The Watch debug log shows detection method:
- `ONSET #1 [JUMP]: +1.5dB (jump:3.2)` - Detected by sudden jump
- `ONSET #2 [THRESH]: +2.1dB (jump:0.5)` - Detected by threshold

## Next Steps to Try

1. **Lower thresholds further** - Try 0.5 dB threshold, 1.0 dB jump
2. **Different rings** - Metal rings may produce louder clicks
3. **Ring position** - Closer to Watch microphone (inner wrist?)
4. **Alternative approach** - Frequency-based detection instead of energy
5. **Hybrid with motion** - Combine audio + accelerometer for confirmation

## Quick Resume Commands

```bash
# Check current state
git status
git log --oneline -5

# Current branch
git branch  # issue-48-audio-pinch-detection

# Build Watch app
xcodebuild -scheme "DhikrCounter Watch App" -configuration Debug \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" build

# Build iOS app
xcodebuild -scheme "DhikrCounter" -configuration Debug \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" build
```

## Uncommitted Changes

All changes are uncommitted. To commit:
```bash
git add -A
git commit -m "Improve audio detection sensitivity with dual detection method"
```

## Technical Notes

### watchOS Audio Constraints
- Sample rate fixed at 48kHz
- Buffer size 512 samples = ~10.7ms per buffer
- Must disconnect inputNode from mainMixerNode to avoid feedback
- Microphone sensitivity appears quite low for subtle sounds

### Detection Algorithm Flow
```
Audio Buffer (512 samples @ 48kHz)
    ↓
Compute RMS Energy (vDSP)
    ↓
Convert to dB: 20 * log10(rms)
    ↓
Update Baseline (asymmetric smoothing)
    ↓
Check Detection:
  - Method 1: rmsDb > baseline + threshold?
  - Method 2: (rmsDb - previousRmsDb) > minJumpDb?
    ↓
If either true AND refractory passed → ONSET DETECTED
```

## Open Issues

| # | Title | Status |
|---|-------|--------|
| #48 | Investigate sound addition | In progress - sensitivity issues |
| #49 | Verify event inter arrival time | Open |
| #46 | Auto Reset count | Open |
| #47 | Watch statistics disappears | ✅ Fixed (PR #50) |
