# Current State: Hybrid Audio + Accelerometer Detection

**Date**: 2025-12-05
**Branch**: `issue-48-hybrid-audio-accelerometer`
**Status**: Implementing hybrid detection - needs Xcode project file update

## Problem Being Solved

Audio detection works well in quiet environments but loses real clicks when:
- Ambient noise causes `REJECTED [TOO LOUD]`
- Voice sounds cause `REJECTED [VOICE]`
- Background noise triggers `waitingForBaseline` state

**Solution**: Hybrid detection where accelerometer (TKEO) backs up audio when audio rejects due to noise.

## Architecture: "Parallel with Audio-Priority Arbitration"

```
┌─────────────────┐     ┌─────────────────┐
│ AudioPinchDet.  │     │ StreamingPinch  │
│ (HPF + Peak)    │     │ (TKEO + NCC)    │
└────────┬────────┘     └────────┬────────┘
         │                       │
         │  AudioResult          │  PinchEvent?
         │  .confirmed(t)        │  (t, ncc, conf)
         │  .rejected(reason,t)  │
         ▼                       ▼
    ┌────────────────────────────────────┐
    │      HybridDetectionManager        │
    │  • Association window: ±75ms       │
    │  • Global refractory: 250ms        │
    │  • Arbitration logic               │
    └────────────────┬───────────────────┘
                     │
                     ▼
              Single Click Output
              (source: AUDIO | IMU_BACKUP)
```

## Decision Logic

| Audio Result | IMU in ±75ms? | Output |
|-------------|---------------|--------|
| `.confirmed` | Any | 1 click (AUDIO) |
| `.rejected(VOICE/TOO_LOUD)` | NCC ≥ 0.60 | 1 click (IMU_BACKUP) |
| `.rejected(VOICE/TOO_LOUD)` | No match | 0 clicks |
| No audio event | NCC ≥ 0.70 | 1 click (IMU_STANDALONE) |

## Files Created/Modified This Session

| File | Changes |
|------|---------|
| `DhikrCounter Watch App/AudioPinchDetector.swift` | Added `AudioDetectionResult` enum, `onDetectionResult` callback |
| `DhikrCounter Watch App/HybridDetectionManager.swift` | **NEW** - Arbitration logic (needs Xcode add) |
| `DhikrCounter Watch App/DhikrDetectionEngine.swift` | Integrated hybrid manager, routing, callbacks |

## ⚠️ IMPORTANT: Manual Step Required

**You must add `HybridDetectionManager.swift` to the Xcode project:**

1. Open `DhikrCounter.xcodeproj` in Xcode
2. In the Project Navigator, right-click on "DhikrCounter Watch App"
3. Select "Add Files to 'DhikrCounter'..."
4. Navigate to `DhikrCounter Watch App/HybridDetectionManager.swift`
5. Make sure "DhikrCounter Watch App" target is checked
6. Click "Add"

## Key Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `associationWindowMs` | 75 | Link audio/IMU events within ±75ms |
| `globalRefractoryMs` | 250 | Min time between output clicks |
| `backupNccThreshold` | 0.60 | IMU threshold when audio rejects |
| `standaloneNccThreshold` | 0.70 | IMU threshold with no audio event |
| `maxSpikeDb` | 35.0 | Audio rejects louder as "ambient" |

## Quick Resume Commands

```bash
# Check current state
git status
git log --oneline -5

# Current branch
git branch  # issue-48-hybrid-audio-accelerometer

# Build Watch app (after adding HybridDetectionManager.swift to Xcode)
xcodebuild -scheme "DhikrCounter Watch App" -configuration Debug \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" build
```

## Testing Plan

1. **Quiet environment**: Audio should confirm most clicks (no IMU backup needed)
2. **Noisy environment**: When audio rejects, IMU should rescue valid clicks
3. **Voice test**: Say "Hmm" - audio rejects as VOICE, IMU should NOT fire (no pinch motion)
4. **Door slam**: Audio rejects as TOO_LOUD, IMU should NOT fire (no pinch motion)
5. **Click during noise**: Audio rejects, but IMU detects pinch motion → count click

## Still To Do

- [ ] Add HybridDetectionManager.swift to Xcode project (manual step)
- [ ] Add UI toggle for hybrid mode in Watch Settings
- [ ] Test hybrid detection in various environments
- [ ] Tune thresholds based on real-world testing

## Open Issues

| # | Title | Status |
|---|-------|--------|
| #48 | Investigate sound addition | In progress - implementing hybrid |
| #49 | Verify event inter arrival time | Open |
| #46 | Auto Reset count | Open |
