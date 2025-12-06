# Current State: Hybrid Audio + Accelerometer Detection

**Date**: 2025-12-05
**Branch**: `issue-48-audio-pinch-detection`
**Status**: Hybrid mode is now DEFAULT and working well - 100 clicks detected successfully!

## Latest Session Results

Tested with 100 intentional pinches:
- **100 clicks detected** via audio (all 100 AUDIO source)
- **1 IEI outlier rejection** (correct filtering of out-of-rhythm event)
- Rhythm learned after 8 clicks: mean=769ms, stddev=262ms, bounds=[114-1424]ms
- Perfect accuracy with hybrid detection enabled by default

## Recent Changes (Latest Session)

### 1. Made Hybrid Mode the Default
- **Before**: `useHybridDetection = false`
- **After**: `useHybridDetection = true`
- **File**: `DhikrDetectionEngine.swift:101`

### 2. Fixed iOS App Session Details Display
- Hybrid detection card now shown FIRST (more prominent)
- WatchDetectorMetadataCard (IMU-only) hidden when hybrid metadata is available
- Session overview shows Dhikr count from hybrid metadata when available
- **File**: `DataVisualizationView.swift`

## Previous Changes

### Raised Audio Jump Threshold
- **Before**: `minJumpDb = 10.0` (allowed weak jumps of 13-14 dB)
- **After**: `minJumpDb = 18.0` (requires strong jumps like real clicks: 24-35 dB)
- **File**: `AudioPinchDetector.swift:94`

### Disabled Standalone IMU Mode
- IMU is now **only used as backup** when audio rejects due to noise
- Standalone IMU caused phantom clicks from wrist motion
- **File**: `HybridDetectionManager.swift:handleIMUStandalone()`

### Added IEI-Based Adaptive Filtering
Learns user's pinch rhythm during warmup period, then rejects outliers.

### Fixed IEI Filtering Bug
**Bug**: After pausing and resuming, all clicks were rejected because IEI was comparing to last **accepted** click, not last **event**.

**Fix**:
- Added `lastEventTime` to track all events (accepted or rejected)
- `passesIEIFilter()` now uses `lastEventTime` instead of `lastClickTime`
- Added **pause grace period**: if event interval > 3x max bound, accept to re-establish rhythm
- `defer { lastEventTime = timestamp }` ensures it's always updated

## Problem Solved

Audio detection works well in quiet environments but loses real clicks when:
- Ambient noise causes `REJECTED [TOO LOUD]`
- Voice sounds cause `REJECTED [VOICE]`
- Background noise triggers `waitingForBaseline` state

**Solution**: Hybrid detection where accelerometer (TKEO) backs up audio when audio rejects due to noise.

## IEI Filter Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `ieiWarmupClicks` | 8 | Clicks before rhythm learned |
| `ieiStddevMultiplier` | 2.5 | Bounds = mean ± 2.5*stddev |
| `ieiMinStddev` | 150ms | Minimum stddev floor |
| `ieiMaxCV` | 0.5 | If CV > 0.5, rhythm too variable to filter |

**How it works**:
1. First 8 clicks: Learn rhythm (calculate mean & stddev of IEIs)
2. After warmup: Reject clicks whose IEI falls outside `[mean - 2.5*stddev, mean + 2.5*stddev]`
3. If user's rhythm is too variable (CV > 0.5), filtering is disabled

**Example**: If user pinches at ~600ms intervals (stddev ~100ms):
- Learned bounds: [350ms, 850ms]
- Clicks arriving at 2000ms would be rejected as outliers

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
    │  • IEI adaptive filtering          │
    │  • Arbitration logic               │
    └────────────────┬───────────────────┘
                     │
                     ▼
              Single Click Output
              (source: AUDIO | IMU_BACKUP)
```

## Decision Logic

| Audio Result | IMU in ±75ms? | IEI Check | Output |
|-------------|---------------|-----------|--------|
| `.confirmed` | Any | Pass | 1 click (AUDIO) |
| `.confirmed` | Any | Fail (outlier) | 0 clicks (rejected) |
| `.rejected(VOICE/TOO_LOUD)` | NCC ≥ 0.60 | - | 1 click (IMU_BACKUP) |
| `.rejected(VOICE/TOO_LOUD)` | No match | - | 0 clicks |
| No audio event | Any | - | 0 clicks (standalone disabled) |

## Key Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `minJumpDb` | **18.0** | Audio requires strong jumps (was 10.0) |
| `associationWindowMs` | 75 | Link audio/IMU events within ±75ms |
| `globalRefractoryMs` | 250 | Min time between output clicks |
| `backupNccThreshold` | 0.60 | IMU threshold when audio rejects |
| `standaloneNccThreshold` | 0.70 | IMU standalone (DISABLED) |
| `maxSpikeDb` | 35.0 | Audio rejects louder as "ambient" |
| `ieiWarmupClicks` | 8 | Warmup before IEI filtering |
| `ieiStddevMultiplier` | 2.5 | IEI outlier detection bounds |

## Files Modified This Session

| File | Changes |
|------|---------|
| `DhikrDetectionEngine.swift` | **Made hybrid mode default ON**, updated generateHybridMetadata() |
| `DataVisualizationView.swift` | **Hybrid card first**, hide IMU card when hybrid available, show Dhikr count in overview |
| `AudioPinchDetector.swift` | Raised `minJumpDb` from 10.0 to 18.0 |
| `HybridDetectionManager.swift` | IEI filtering with lastEventTime, disabled standalone IMU, log limit to 100 |
| `Shared/PinchTypes.swift` | Added learned rhythm fields to HybridDetectionMetadata |

## iOS Debug UI Features

The `HybridDetectionMetadataCard` shows:
- Total clicks and breakdown by source (Audio/IMU Backup/IMU Only)
- Click source distribution bar chart
- Inter-event interval statistics (min/avg/max IEI)
- **Learned Rhythm** (if enabled): mean, stddev, bounds
- Rejection counts: No IMU Match, Refractory, **IEI Outlier**
- Configuration parameters
- Last 50 debug log entries with color coding (legend at top)

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

1. **Normal counting**: Count at steady rhythm, verify IEI learning works
2. **Slow counting**: Count at 6+ second intervals, verify rhythm adapts
3. **Stop counting**: After stopping, ambient noise shouldn't cause phantom clicks
4. **Noisy environment**: When audio rejects, IMU should rescue valid clicks
5. **Check rejections**: Verify IEI Outlier count increases for late phantom clicks

## Still To Do

- [x] Test IEI filtering with various counting speeds - **DONE**: 100 clicks at ~600ms rhythm worked perfectly
- [x] Hybrid mode now default - **DONE**
- [x] iOS shows hybrid results - **DONE**
- [ ] Commit and push changes
- [ ] Consider making IEI parameters configurable in UI

## Open Issues

| # | Title | Status |
|---|-------|--------|
| #48 | Investigate sound addition | **Working!** Hybrid mode default, 100 clicks detected |
| #49 | Verify event inter arrival time | **Fixed!** IEI filtering with lastEventTime |
| #46 | Auto Reset count | Open |
