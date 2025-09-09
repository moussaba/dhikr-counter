# Real-Time TKEO Pinch Detection on Apple Watch

*Expert consensus analysis from GPT-5 and Gemini-Pro for implementing streaming pinch detection on watchOS*

## Executive Summary

**FEASIBILITY: CONFIRMED** ✅
- Real-time TKEO pinch detection on Apple Watch Series 6+ is technically viable at 50-100Hz
- Requires fundamental architectural shift from batch to streaming processing
- Timeline: 1-2 weeks for robust prototype
- **Expert Confidence: 8/10** (High technical feasibility, moderate tuning complexity)

## Current State Analysis

### Existing Implementation (`PinchDetector.swift`)
- **666-line Swift class** using Accelerate framework
- **Multi-template matching** with NCC correlation
- **Python-style per-axis TKEO** processing with L2 fusion
- **Bandpass filtering** (3-20Hz), adaptive MAD thresholds
- **Batch processing** of complete sensor datasets
- **iPhone-side analysis** of Watch session data

## Critical Challenges Identified

### 🚨 **SHOWSTOPPER: Baseline MAD Algorithm**
**Location**: `PinchDetector.swift:518-535`
```swift
let window = Array(z[start..<end]).sorted()  // O(n log n) per sample!
let deviations = window.map { abs($0 - med) }.sorted()
```

**Problem**: At 50Hz with 3-second window, this sorts 150 elements **twice per sensor frame**
- Completely unworkable on Watch hardware
- Would overwhelm CPU and drain battery rapidly

**Solution Options**:
1. **IIR-based EMA filters** (O(1)) - Replace with exponential moving averages
2. **Sliding window median with heaps** (O(log n)) - More complex but robust

### 🔄 **Architecture Transformation Required**

| Current (Batch) | Required (Streaming) |
|-----------------|---------------------|
| `process(frames: [SensorFrame])` | `push(frame: SensorFrame) -> PinchEvent?` |
| Stateless random access | Stateful with ring buffers |
| Complete dataset analysis | Sample-by-sample processing |
| iPhone-side processing | Watch-side complete pipeline |

## Recommended Architecture

### **Watch-Side Processing (Complete Pipeline)**
```swift
class StreamingPinchDetector {
    func push(frame: SensorFrame) -> PinchEvent?
    // State: filter histories, ring buffers, rolling baselines, refractory timers
}
```

### **iPhone-Watch Communication**
- **Downstream**: Configuration updates via `WCSession`
- **Upstream**: Only `PinchEvent` structs (low bandwidth)
- **Debug Mode**: Small signal windows for tuning/validation

### **Background Execution Strategy**
- **Primary**: `HKWorkoutSession` (unlimited duration, health/fitness justification required)
- **Alternative**: `WKExtendedRuntimeSession` (10min-1hr limits by session type)
- **App Store**: Must justify continuous background motion sensing

## Platform Research Findings

### **Accelerate Framework Support**
✅ **vDSP fully available on watchOS**
- All Accelerate capabilities including signal processing
- Optimized performance with energy savings
- Critical for efficient biquad filtering and NCC correlation

### **Background Execution Options**
- **HKWorkoutSession**: Unlimited runtime, requires workout justification
- **WKExtendedRuntimeSession**: 
  - Self-care: 10 minutes
  - Physical therapy/Mindfulness: 1 hour
  - Must be started while app is active

### **CoreMotion Sampling**
- High-frequency sampling possible with `HKWorkoutSession`
- Background sampling maintained when wrist lowered
- Single session limitation (only one workout at a time)

## Implementation Plan

### **Phase 0: Platform Validation (0.5 day)**
- [ ] Confirm `HKWorkoutSession` + `CoreMotion` 50Hz background sampling
- [ ] Test vDSP performance on Watch hardware
- [ ] Validate sensor data delivery consistency

### **Phase 1: Core Streaming DSP (2-3 days)**
- [ ] **Replace `baselineMAD`** with O(1) streaming approximation
- [ ] Create `StreamingPinchDetector` with stateful API
- [ ] Implement ring buffer for template window extraction  
- [ ] Convert manual DSP loops to vDSP (biquad filters, NCC)
- [ ] Eliminate per-sample memory allocations

### **Phase 2: Watch Integration (1-2 days)**
- [ ] `CMDeviceMotion` integration with proper timestamps
- [ ] `HKWorkoutSession` lifecycle management
- [ ] WCSession configuration synchronization
- [ ] Background processing queue setup

### **Phase 3: Tuning & Validation (3-5 days)**
- [ ] Parameter calibration with new streaming baseline
- [ ] Battery profiling and optimization
- [ ] Multi-user testing and threshold adjustment
- [ ] Latency measurement and optimization

## Critical Code Changes Required

### **1. Streaming API Conversion**
**Location**: `PinchDetector.swift:193-201`
**Change**: Batch `process(frames: [SensorFrame])` → streaming `push(frame: SensorFrame)`

### **2. Baseline Algorithm Replacement**  
**Location**: `PinchDetector.swift:518-535`
**Change**: O(n log n) sorting → O(1) IIR/EMA approximation

### **3. Peak Detection Timestamps**
**Location**: `PinchDetector.swift:540-549`  
**Change**: Index-derived time → actual `CMDeviceMotion` timestamps

### **4. Template Window Extraction**
**Location**: `PinchDetector.swift:306-329`
**Change**: Random access slicing → ring buffer causal extraction

### **5. DSP Filter Optimization**
**Location**: `PinchDetector.swift:466-498`
**Change**: Manual Swift loops → vDSP biquad with persistent state

## Performance & Battery Considerations

### **Optimizations Required**
- **vDSP throughout**: Replace all manual loops with Accelerate
- **Pre-allocated buffers**: Eliminate runtime memory allocations
- **Start at 50Hz**: Balance resolution with power consumption  
- **O(1) baseline**: Critical for sustained battery life

### **Memory Management**
- Ring buffers sized for `windowPreMs + windowPostMs`
- Pre-computed filter coefficients per sample rate
- Stable, low memory footprint (<100KB state)

### **CPU Budget**
- 6-axis biquad filtering: ~5 multiply-accumulates per sample
- TKEO computation: 2 multiplies + 1 product per axis
- Fusion and comparison: negligible overhead
- **Target**: <1ms processing time per 50Hz sample

## Expert Analysis Summary

### **GPT-5 Perspective (FOR Implementation)**
- ✅ Feasible on Series 6+ at 50-100Hz with proper streaming DSP
- ⚠️ Heavy refactoring required for stateful processing
- 🔧 Specific code locations identified for critical changes
- ⏱️ Realistic latency: ~250-300ms (acceptable for UX)
- 📅 Timeline: 1-2 weeks with disciplined approach

### **Gemini-Pro Perspective (Technical Validation)**
- ✅ Agrees on feasibility with careful platform-specific implementation
- 🚨 Emphasizes `baselineMAD` as absolute showstopper for streaming
- 🔋 Strong focus on watchOS app lifecycle and battery constraints
- 🏗️ Recommends risk-first implementation priorities
- 📱 Validates architecture but stresses background execution challenges

### **Key Agreement Points**
- Technical feasibility is high with proper streaming redesign
- Architecture (Watch-side processing) is sound and follows Apple best practices
- No fundamental technical blockers identified
- Success depends heavily on implementation discipline and tuning

### **Critical Insights**
1. **Baseline MAD replacement is make-or-break** - Must be solved first
2. **vDSP usage is essential** - Manual loops won't scale on Watch hardware  
3. **HKWorkoutSession required** - Only viable path for background sampling
4. **Streaming state management** - Ring buffers and stateful filters critical
5. **Parameter re-tuning needed** - New baseline approximation changes behavior

## Risk Assessment

### **High Risk**
- **Baseline MAD replacement**: Algorithm correctness vs performance trade-off
- **Battery life**: Continuous 50Hz processing impact unknown
- **App Store approval**: Background workout session justification required

### **Medium Risk**  
- **Parameter re-tuning**: New streaming baseline may require threshold adjustments
- **Watch hardware variation**: Performance differences across S6/S7/S8/S9
- **Background suspension**: Complex watchOS lifecycle management

### **Low Risk**
- **Core DSP operations**: Well-understood and lightweight
- **vDSP availability**: Confirmed on watchOS with full feature set
- **Template matching**: NCC correlation translates directly to streaming

## Success Criteria

### **Technical Milestones**
- [ ] 50Hz streaming processing with <1ms per-sample latency
- [ ] <5% battery drain per hour during continuous monitoring
- [ ] Successful background operation with `HKWorkoutSession`
- [ ] Detection accuracy matching iPhone batch processing

### **User Experience Goals**
- [ ] <300ms end-to-end detection latency
- [ ] Reliable operation with wrist lowered
- [ ] Seamless iPhone configuration synchronization
- [ ] Immediate haptic/audio feedback capability

## Next Steps

1. **Immediate**: Create Watch app target and test background sensor sampling
2. **Critical**: Implement O(1) baseline replacement algorithm
3. **Foundation**: Design `StreamingPinchDetector` class architecture  
4. **Optimization**: Migrate all DSP to vDSP for efficiency
5. **Integration**: Add proper watchOS lifecycle and communication

---

## GitHub Issues Created

### **Phase 1: Critical Architecture Changes (Must Do First)**
- **#27** - [CRITICAL: Replace O(n log n) baseline MAD with O(1) streaming algorithm](https://github.com/moussaba/dhikr-counter/issues/27)
- **#28** - [Port PinchDetector from iPhone to Watch with streaming API](https://github.com/moussaba/dhikr-counter/issues/28)  
- **#29** - [Optimize DSP operations with vDSP Accelerate framework](https://github.com/moussaba/dhikr-counter/issues/29)

### **Phase 2: Integration with Watch Infrastructure**
- **#30** - [Integrate StreamingPinchDetector into DhikrDetectionEngine](https://github.com/moussaba/dhikr-counter/issues/30)
- **#31** - [Add template management and synchronization](https://github.com/moussaba/dhikr-counter/issues/31)
- **#32** - [Enhance WCSession for TKEO configuration synchronization](https://github.com/moussaba/dhikr-counter/issues/32)

### **Phase 3: Optimization & Validation**  
- **#33** - [Fix peak detection to use actual CoreMotion timestamps](https://github.com/moussaba/dhikr-counter/issues/33)
- **#34** - [Memory management optimization for continuous operation](https://github.com/moussaba/dhikr-counter/issues/34)
- **#35** - [Battery profiling and TKEO-specific optimization](https://github.com/moussaba/dhikr-counter/issues/35)
- **#36** - [Parameter calibration and multi-user validation](https://github.com/moussaba/dhikr-counter/issues/36)

### **Phase 4: Polish & Production**
- **#37** - [Add TKEO debug mode and visualization](https://github.com/moussaba/dhikr-counter/issues/37)
- **#38** - [Implement ring buffer for template window extraction](https://github.com/moussaba/dhikr-counter/issues/38)

### **Key Simplifications from Original Plan**
- ✅ **Skip Phase 0**: Background sampling already confirmed working
- ✅ **WCSession ready**: File transfer infrastructure already implemented
- ✅ **HKWorkoutSession integrated**: Background execution already working  
- ✅ **Series 10 hardware**: Latest Apple hardware confirmed

**Priority**: Issue #27 (baseline MAD replacement) is **CRITICAL** and must be completed first.

---

*Generated from expert consensus analysis - GPT-5 and Gemini-Pro consultations*  
*Date: 2025-01-08 | Updated: 2025-01-09*  
*Confidence Level: 8/10 - High technical feasibility, moderate implementation complexity*