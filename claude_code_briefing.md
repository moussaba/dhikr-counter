# Claude Code Development Briefing - Dhikr Counter Project

## Project Context

You are developing an Apple Watch app that detects finger pinches during Islamic dhikr (prayer recitation) using motion sensors. A professional researcher has analyzed real sensor data and provided validated detection parameters. The app needs to count pinches accurately without requiring visual attention during prayer.

## Validated Technical Foundation

### Hardware Platform
- **Target**: Apple Watch Series 9 (44mm GPS)
- **Key Feature**: Double Tap capability for UI interaction
- **Sensors**: 3-axis accelerometer, gyroscope at 100Hz sampling
- **Processing**: S9 Neural Engine for real-time ML inference

### Proven Algorithm Parameters
**From researcher analysis of real dhikr data**:
- **Accelerometer threshold**: 0.05g (high-pass filtered)
- **Gyroscope threshold**: 0.18 rad/s
- **Sampling rate**: 100Hz (99.3Hz validated)
- **Refractory period**: 250ms between detections
- **Activity threshold**: 70th percentile for session state detection
- **Score fusion**: Multi-sensor z-score combination with derivatives

### Detection Pipeline Architecture
1. **Raw sensor input**: Core Motion `userAcceleration` and `rotationRate`
2. **Signal processing**: Magnitude calculation and derivative computation
3. **Statistical scoring**: Robust z-score fusion across multiple sensor channels
4. **Adaptive thresholding**: Segment-based 90th percentile (researcher recommended)
5. **Pattern validation**: Backward-looking filter for sustained dhikr sequences
6. **Session state management**: Activity index based active/pause detection

## Development Requirements

### Phase 1: Core Watch App (Priority 1)
**Functional requirements**:
- Real-time pinch detection using validated algorithm
- Haptic feedback for individual pinches and milestones (33, 66, 100)
- Session state management (inactive, setup, active, paused)
- Manual correction via Double Tap gesture
- Basic UI with large counter display and progress indicators

**Technical implementation**:
- Swift + SwiftUI for watchOS
- Core Motion framework for 100Hz sensor access
- WatchKit for haptic feedback integration
- Background operation capability for continuous detection

**Data logging requirements**:
- Comprehensive sensor data capture (accelerometer, gyroscope, timestamps)
- Detection event logging with confidence scores
- Manual correction tracking
- Session metadata (start/stop times, dhikr type estimates)
- Local storage with efficient data structures

### Phase 2: Enhanced Pattern Recognition (Priority 2)
**Backward-looking validation filter**:
- Buffer candidate pinches in configurable time window (5-30 seconds)
- Validate patterns when minimum sequence detected (2+ pinches)
- Retroactively count all validated candidates
- Support varied dhikr rhythms (0.5s to 30s intervals)

**Session intelligence**:
- Automatic dhikr type recognition (Astaghfirullah vs Subhanallah)
- Rhythm pattern learning and adaptation
- Enhanced false positive elimination
- Contextual milestone notifications

### Phase 3: iPhone Companion App (Priority 3)
**Development tool functions**:
- Data import via WatchConnectivity framework
- Timeline visualization with detection overlays
- Manual annotation interface for ground truth validation
- CSV export for external analysis (Jupyter compatibility)
- Algorithm parameter adjustment and testing

**Data management**:
- Session storage and organization
- Batch export capabilities
- Manual annotation workflow
- Performance metrics tracking

## User Experience Design

### Core Interaction Model
**Primary use case**: Hands-free operation during prayer
- Start session with Digital Crown or Double Tap
- Automatic pinch detection with haptic confirmation
- Milestone notifications without visual attention
- Manual corrections via Double Tap when needed

### UI Component Specifications
**Main screen layout**:
- Large counter display (60pt bold rounded font)
- Session state indicator text
- Dhikr type detection label (when available)
- Milestone progress bar
- Control buttons (start/stop, reset, manual adjust)

**Apple Watch Series 9 Integration**:
- Double Tap for manual pinch increment
- Double Tap for session start/stop (configurable)
- Digital Crown for count adjustment
- Side button for quick reset (with confirmation)

## Data Architecture

### Sensor Data Format
```swift
struct SensorReading {
    let timestamp: Date
    let userAcceleration: SIMD3<Double>
    let rotationRate: SIMD3<Double>
    let activityIndex: Double
    let detectionScore: Double
}
```

### Detection Event Format
```swift
struct DetectionEvent {
    let timestamp: Date
    let accelerationPeak: Double
    let gyroscopePeak: Double
    let combinedScore: Double
    let validated: Bool
    let manualCorrection: Bool
}
```

### Export Data Structure
**CSV format for analysis**:
```
timestamp,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,accel_mag,gyro_mag,activity_index,detection_score,detected_pinch,manual_correction,session_state,dhikr_type_estimate
```

## Algorithm Implementation Details

### Core Detection Engine
**Real-time processing loop** (100Hz):
1. Read CMDeviceMotion data
2. Compute sensor magnitudes and derivatives
3. Update activity index (1-second rolling window)
4. Calculate multi-sensor fusion score
5. Apply adaptive threshold with two-sensor gate
6. Validate against pattern recognition filter
7. Register validated pinches with haptic feedback

### Statistical Processing
**Robust statistics for adaptive thresholds**:
- Running median and MAD (Median Absolute Deviation) calculation
- Z-score normalization with consistency constants
- Segment-based threshold adaptation (90th percentile recommended)
- Online algorithm implementation for memory efficiency

### Pattern Recognition Logic
**Backward validation system**:
- Sliding window candidate buffer management
- Pattern confidence scoring based on rhythm consistency
- Retroactive validation to prevent pinch loss
- Configurable parameters for different dhikr styles

## Development Tools Integration

### Claude Code Usage
**Primary development tasks**:
- Swift/SwiftUI implementation of watch app
- Core Motion sensor processing pipeline
- Statistical algorithm implementation
- WatchConnectivity data transfer system
- iPhone companion app development

**Code generation approach**:
- Modular component development
- Test-driven implementation with validation data
- Performance optimization for real-time constraints
- Error handling and edge case management

### External Analysis Environment
**Jupyter notebook setup**:
- Python data analysis pipeline
- Algorithm validation framework
- ML model development environment
- Parameter optimization and testing

## Performance Requirements

### Real-time Constraints
- **Detection latency**: <200ms from pinch to haptic feedback
- **Processing overhead**: <5% additional battery drain per hour
- **Memory usage**: Efficient buffer management for continuous operation
- **Background operation**: Maintain detection during prayer sessions

### Accuracy Targets
- **Detection rate**: 85-90% of actual pinches counted
- **False positive rate**: <10% during active dhikr periods
- **Pattern recognition**: 80%+ accuracy for dhikr type classification
- **Session boundary detection**: 90%+ accuracy for start/stop identification

## Quality Assurance Strategy

### Testing Methodology
**Real-world validation**:
- Multiple dhikr sessions across different prayer types
- Various environmental conditions (sitting, standing, walking)
- Different user techniques and rhythm patterns
- Extended session testing (15+ minute sessions)

**Data validation**:
- Manual annotation of ground truth pinch timing
- Algorithm performance comparison across parameter sets
- Statistical significance testing for accuracy claims
- Cross-validation using multiple user datasets

## Development Constraints

### Technical Limitations
- Apple Watch processing power constraints
- WatchConnectivity transfer limitations
- Battery optimization requirements
- Real-time processing demands

### Implementation Priorities
1. **Functional accuracy**: Core detection must work reliably
2. **User experience**: Seamless operation during prayer
3. **Development tools**: Enable rapid algorithm iteration
4. **Performance optimization**: Minimize resource usage

## Success Definition

**Primary goal**: Deliver a functional dhikr counter that enables accurate, hands-free pinch counting during Islamic prayer with 85-90% detection accuracy.

**Secondary goals**: 
- Create comprehensive development infrastructure for algorithm improvement
- Enable data-driven optimization through real-world usage analysis
- Establish foundation for advanced features like automatic dhikr recognition

---

*This briefing provides Claude Code with the complete context needed to implement a sophisticated, validated dhikr counting application with proven detection algorithms and comprehensive development infrastructure.*