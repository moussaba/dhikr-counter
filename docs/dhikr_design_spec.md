# Apple Watch Dhikr Counter - Complete Design Specification

## Project Overview

Building an Apple Watch app to accurately count finger pinches during Islamic dhikr (prayer recitation) using validated sensor detection algorithms and machine learning pattern recognition.

## Hardware Platform

**Target Device**: Apple Watch Series 9 (44mm)
- **Key Advantage**: Built-in Double Tap feature provides proven pinch detection reference
- **Technical Benefits**: S9 Neural Engine with 2x faster ML processing
- **Available Sensors**: 3-axis accelerometer, gyroscope, heart rate sensor
- **Double Tap Integration**: Use as UI input for manual corrections and session controls

## Validated Algorithm Foundation

### Core Detection Parameters (Researcher Validated)
- **Accelerometer threshold**: 0.05g (high-pass filtered)
- **Gyroscope threshold**: 0.18 rad/s
- **Sampling rate**: 100Hz
- **Refractory period**: 250ms
- **Activity index threshold**: 70th percentile for session state detection

### Multi-Stage Detection Pipeline
1. **Signal processing**: userAcceleration + rotationRate magnitude calculation
2. **Feature extraction**: Derivatives and multi-sensor fusion scoring
3. **Session state management**: Activity index based active/pause detection
4. **Pattern validation**: Backward-looking filter for sustained dhikr patterns
5. **Haptic feedback**: Configurable milestone notifications (33, 66, 100)

## Enhanced Pattern Recognition Filter

### Backward-Looking Validation System
**Purpose**: Eliminate isolated false positives while preserving all legitimate pinches

**Core Logic**:
- Buffer candidate pinches in sliding window (configurable 5-30 seconds)
- Validate patterns when minimum sequence detected (2+ pinches)
- Retroactively count all validated candidates to prevent loss
- Support varied dhikr rhythms from rapid (0.5s intervals) to contemplative (30s intervals)

**Configuration Parameters**:
- `maxDeltaBetweenPinches`: Maximum interval for pattern validation (default 30s)
- `minPatternSize`: Minimum pinches required for validation (default 2)
- `patternConfidenceThreshold`: Statistical confidence for pattern detection

### Session State Management
**Four-state system**:
- **Inactive**: App not running detection
- **Setup**: Initial positioning and calibration period
- **Active Dhikr**: Pattern-validated pinch detection enabled
- **Paused**: Temporary pause between dhikr types or breaks

## Three-Tier Development Architecture

### Tier 1: Apple Watch App
**Primary Functions**:
- Functional dhikr counter for immediate user value
- Comprehensive sensor data logging (100Hz accelerometer + gyroscope)
- Detection event logging with timestamps and confidence scores
- Manual correction tracking (Double Tap integration)
- Chunked data export to companion app

**Implementation Approach**:
- Swift + SwiftUI for watchOS
- Core Motion framework for sensor access
- WatchConnectivity for data transfer
- Local storage with automatic cleanup

### Tier 2: iPhone Companion App
**Development Tool Functions**:
- Data import and session management
- Detection accuracy visualization (timeline with sensor overlays)
- Manual annotation interface for ground truth labeling
- CSV export for Jupyter analysis
- Algorithm parameter testing interface

**Key Features**:
- Timeline visualization showing raw sensor data with detection markers
- Manual pinch annotation for algorithm validation
- Session comparison tools for algorithm A/B testing
- Standardized CSV export format for external analysis

### Tier 3: Jupyter Notebook Development Environment
**Algorithm Development Platform**:
- Multiple dataset analysis across different dhikr styles
- Statistical validation with manual annotations
- Machine learning model development for dhikr type recognition
- Parameter optimization using historical data
- Export of optimized parameters for Swift implementation

## Phased Implementation Approach

### Phase 1: Core Watch App (Weeks 1-2)
**Deliverables**:
- Functional dhikr counter with researcher's baseline algorithm
- Basic sensor data logging capability
- Double Tap integration for manual corrections
- Data export to companion app

**Success Criteria**:
- 85-90% detection accuracy during real dhikr sessions
- Reliable data export of sensor information
- Functional haptic feedback system

### Phase 2: Companion App Development (Weeks 2-3)
**Deliverables**:
- Data import and session management
- Basic timeline visualization of detection events
- CSV export capability
- Manual annotation interface

**Success Criteria**:
- Successful data transfer from watch
- Clear visualization of algorithm performance
- Standardized data format for analysis

### Phase 3: Advanced Pattern Recognition (Weeks 3-4)
**Deliverables**:
- Backward-looking pattern validation filter
- Enhanced session state management
- Configurable dhikr rhythm parameters
- Improved false positive elimination

**Success Criteria**:
- Reduced false positive rate below 10%
- Support for varied dhikr timing patterns
- Robust session boundary detection

### Phase 4: Jupyter Development Environment (Weeks 4-5)
**Deliverables**:
- Standardized data analysis pipeline
- Algorithm comparison framework
- ML model development for dhikr type recognition
- Parameter optimization tools

**Success Criteria**:
- Automated analysis of multiple datasets
- Algorithm performance benchmarking
- Optimized parameters for Swift deployment

### Phase 5: ML Enhancement Integration (Weeks 5-6)
**Deliverables**:
- Automatic dhikr type recognition (Astaghfirullah vs Subhanallah)
- Personalized rhythm learning
- Advanced session analytics
- Core ML model integration for on-device processing

**Success Criteria**:
- Automatic dhikr type classification with 80%+ accuracy
- Personalized detection parameter adaptation
- Enhanced user experience with contextual feedback

## Technical Requirements

### Data Collection Specifications
**Sensor data logging**:
- 100Hz sampling rate for accelerometer and gyroscope
- Timestamp precision for relative timing analysis
- Session metadata (start/stop times, manual corrections, user annotations)
- Efficient storage and transfer protocols

**Export format**:
```csv
timestamp,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,detected_pinch,manual_correction,session_state,dhikr_type
```

### Algorithm Performance Targets
- **Detection accuracy**: 85-90% for individual pinches
- **False positive rate**: <10% during active dhikr
- **Latency**: <200ms for haptic feedback
- **Battery impact**: <5% additional drain per hour of use

### User Experience Requirements
- **No visual dependency**: Complete functionality through haptic feedback
- **Intuitive controls**: Double Tap for corrections, Digital Crown for navigation
- **Configurable milestones**: 33, 66, 100 count notifications
- **Session continuity**: Maintain counting across app backgrounding

## Integration with Apple Watch Series 9 Features

### Double Tap Utilization
**Primary functions**:
- Manual pinch increment during detection failures
- Session start/stop control
- Quick reset gesture
- Navigation through milestone confirmation

**Implementation considerations**:
- Study Apple's Double Tap detection implementation
- Ensure compatibility with custom pinch detection
- Avoid interference between detection algorithms

### Neural Engine Optimization
**Performance enhancements**:
- Real-time ML inference for pattern recognition
- On-device dhikr type classification
- Personalized detection parameter learning
- Advanced signal processing capabilities

## Success Metrics

### Technical Performance
- Detection accuracy >85% validated across multiple sessions
- False positive rate <10% during active dhikr periods
- Battery life impact <5% per hour
- Data export success rate >95%

### User Experience
- Successful dhikr counting without visual attention
- Reliable milestone notifications
- Intuitive manual correction workflow
- Seamless session management

### Development Efficiency
- Rapid algorithm iteration cycle (<24 hours from data to deployment)
- Comprehensive performance analytics
- Robust ground truth validation system
- Scalable data collection across multiple users

## Risk Mitigation

### Technical Risks
- **Data transfer reliability**: Implement robust retry mechanisms and offline storage
- **Algorithm translation**: Validate Python algorithms in Swift before deployment
- **Performance constraints**: Profile and optimize real-time processing on watch hardware

### User Experience Risks
- **Detection accuracy**: Comprehensive testing across varied dhikr styles and environmental conditions
- **Battery impact**: Implement power-efficient sensor processing and data management
- **Interfering gestures**: Careful integration of Double Tap to avoid conflicts

## Future Enhancement Opportunities

### Advanced Features
- Multi-user support with personalized detection profiles
- Social features for dhikr session sharing and community engagement
- Integration with Islamic calendar and prayer time applications
- Advanced analytics and spiritual practice insights

### Platform Expansion
- iPhone standalone mode for users without Apple Watch
- iPad companion with enhanced visualization and analysis tools
- Integration with other Islamic applications and platforms

---

*This specification provides the foundation for developing a sophisticated, accurate, and user-friendly dhikr counting application that leverages cutting-edge sensor technology while respecting the spiritual nature of Islamic prayer practices.*