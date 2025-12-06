# Current State: Hybrid Audio + Accelerometer Detection

**Date**: 2025-12-05
**Branch**: `issue-48-audio-pinch-detection`
**Status**: Hybrid detection implemented with iOS debug UI - needs threshold tuning

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
              (source: AUDIO | IMU_BACKUP | IMU_ONLY)
```

## Decision Logic

| Audio Result | IMU in ±75ms? | Output |
|-------------|---------------|--------|
| `.confirmed` | Any | 1 click (AUDIO) |
| `.rejected(VOICE/TOO_LOUD)` | NCC ≥ 0.60 | 1 click (IMU_BACKUP) |
| `.rejected(VOICE/TOO_LOUD)` | No match | 0 clicks |
| No audio event | NCC ≥ 0.70 | 1 click (IMU_STANDALONE) |

## Known Issue: IMU_ONLY Phantom Clicks

From testing, we observed **phantom IMU_ONLY clicks**, particularly:
- At session start before audio is active
- During session when hand/wrist moves without pinching
- At session end when stopping

**Potential fixes**:
1. Raise `standaloneNccThreshold` from 0.70 to 0.80+
2. Disable standalone IMU mode entirely (only use as backup)
3. Add additional velocity/motion check before standalone click

## Files Modified This Session

| File | Changes |
|------|---------|
| `DhikrCounter Watch App/HybridDetectionManager.swift` | Added IEI tracking, stats summary, Codable stats |
| `DhikrCounter Watch App/DhikrDetectionEngine.swift` | Added `generateHybridMetadata()` method |
| `DhikrCounter Watch App/WatchSessionManager.swift` | Added `hybridDetectionMetadata` to SessionData |
| `Shared/PinchTypes.swift` | Added `HybridDetectionMetadata` struct |
| `DhikrCounter/PhoneSessionManager.swift` | Added hybrid metadata receiving and storage |
| `DhikrCounter/DataVisualizationView.swift` | Added `HybridDetectionMetadataCard` UI |

## Key Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `associationWindowMs` | 75 | Link audio/IMU events within ±75ms |
| `globalRefractoryMs` | 250 | Min time between output clicks |
| `backupNccThreshold` | 0.60 | IMU threshold when audio rejects |
| `standaloneNccThreshold` | 0.70 | IMU threshold with no audio event (needs tuning!) |
| `maxSpikeDb` | 35.0 | Audio rejects louder as "ambient" |

## iOS Debug UI Features

The new `HybridDetectionMetadataCard` shows:
- Total clicks and breakdown by source (Audio/IMU Backup/IMU Only)
- Click source distribution bar chart
- Inter-event interval statistics (min/avg/max IEI)
- Rejection counts (No IMU Match, Refractory)
- Configuration parameters
- Last 30 debug log entries with color coding

## Quick Resume Commands

```bash
# Check current state
git status
git log --oneline -5

# Current branch
git branch

# Build Watch app
xcodebuild -scheme "DhikrCounter Watch App" -configuration Debug \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" build

# Build iOS app
xcodebuild -scheme "DhikrCounter" -configuration Debug \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
```

## Testing Plan

1. **Quiet environment**: Audio should confirm most clicks (no IMU backup needed)
2. **Noisy environment**: When audio rejects, IMU should rescue valid clicks
3. **Voice test**: Say "Hmm" - audio rejects as VOICE, IMU should NOT fire (no pinch motion)
4. **Door slam**: Audio rejects as TOO_LOUD, IMU should NOT fire (no pinch motion)
5. **Click during noise**: Audio rejects, but IMU detects pinch motion → count click
6. **IEI analysis**: Check for suspiciously short IEIs (<200ms) that indicate phantom clicks

## Still To Do

- [ ] Tune standalone NCC threshold (0.70 seems too low, causing phantom clicks)
- [ ] Consider disabling IMU_ONLY mode entirely
- [ ] Test hybrid detection in various environments
- [ ] Analyze IEI distributions to identify optimal thresholds

## Open Issues

| # | Title | Status |
|---|-------|--------|
| #48 | Investigate sound addition | In progress - hybrid implemented |
| #49 | Verify event inter arrival time | Open |
| #46 | Auto Reset count | Open |
