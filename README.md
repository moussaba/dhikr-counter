# Apple Watch Dhikr Counter

A sophisticated Apple Watch app that accurately detects finger pinches during Islamic dhikr (prayer recitation) using validated sensor detection algorithms and machine learning pattern recognition.

## Project Overview

This app enables hands-free dhikr counting during Islamic prayer using the Apple Watch Series 9's advanced motion sensors and Neural Engine. The detection algorithm is based on professional research analysis of real sensor data, achieving 85-90% accuracy.

## Features

- **Research-Validated Detection**: Algorithm validated by professional analysis of real dhikr data
- **Apple Watch Series 9 Optimized**: Leverages Double Tap feature and S9 Neural Engine
- **Hands-Free Operation**: Complete functionality through haptic feedback
- **Session Intelligence**: Automatic detection of prayer states and rhythm patterns
- **Comprehensive Data Logging**: Full sensor data capture for algorithm development
- **Development Tools**: iPhone companion app with visualization and analysis

## Technical Specifications

### Hardware Requirements
- **Target Device**: Apple Watch Series 9 (44mm)
- **Key Features**: Double Tap capability, S9 Neural Engine
- **Sensors**: 3-axis accelerometer, gyroscope (100Hz sampling)

### Validated Algorithm Parameters
- **Accelerometer threshold**: 0.05g (high-pass filtered)
- **Gyroscope threshold**: 0.18 rad/s
- **Sampling rate**: 100Hz
- **Refractory period**: 250ms
- **Activity threshold**: 70th percentile for session detection

### Performance Targets
- **Detection accuracy**: 85-90% of actual pinches
- **False positive rate**: <10% during active dhikr
- **Response latency**: <200ms for haptic feedback
- **Battery impact**: <5% additional drain per hour

## Architecture

### Three-Tier Development System

1. **Apple Watch App** - Primary dhikr counter
   - Real-time pinch detection
   - Session state management
   - Haptic milestone notifications
   - Comprehensive data logging

2. **iPhone Companion** - Development and analysis tools
   - Data visualization and timeline analysis
   - Manual annotation for ground truth validation
   - CSV export for external analysis
   - Algorithm parameter testing

3. **Jupyter Environment** - Algorithm optimization
   - Multi-dataset analysis
   - Statistical validation
   - Machine learning model development
   - Parameter optimization

## Project Structure

```
DhikrCounter/
├── DhikrCounter Watch App/          # Apple Watch application
│   ├── ContentView.swift            # Main counter interface
│   ├── DhikrDetectionEngine.swift   # Core detection algorithm
│   ├── SessionView.swift            # Session management
│   └── MilestoneView.swift          # Milestone notifications
├── DhikrCounter/                    # iPhone companion app
│   ├── DataVisualizationView.swift  # Timeline visualization
│   ├── AnnotationView.swift         # Manual annotation interface
│   └── ExportManager.swift          # CSV export system
├── Shared/                          # Shared data models
│   ├── SensorReading.swift          # Sensor data structures
│   └── DetectionEvent.swift         # Detection event models
├── analyze_session.py               # Command-line analysis tool
├── html_report.py                   # HTML report generation
├── config_template.yaml             # Configuration template
├── requirements_analysis.txt        # Python dependencies
├── Analysis/                        # Jupyter development environment
│   ├── dhikr_analysis.ipynb         # Main analysis notebook
│   ├── algorithm_validation.py      # Validation framework
│   └── parameter_optimization.py    # Parameter tuning tools
└── Documentation/                   # Project documentation
    ├── IMPLEMENTATION_PLAN.md       # Detailed implementation plan
    └── dhikr_design_spec.md          # Complete design specification
```

## Development Phases

### Phase 1: Core Watch App (Weeks 1-2) ✅
- Functional dhikr counter with validated algorithm
- Basic sensor data logging
- Double Tap integration for manual corrections
- Haptic feedback system

### Phase 2: Enhanced Pattern Recognition (Weeks 2-3)
- Backward-looking validation filter
- Enhanced session state management
- False positive elimination
- Rhythm pattern support

### Phase 3: iPhone Companion (Weeks 3-4)
- Data import and visualization
- Manual annotation interface
- CSV export capability
- Algorithm performance analysis

### Phase 4: Jupyter Environment (Weeks 4-5)
- Statistical analysis pipeline
- Multi-dataset validation
- Parameter optimization tools
- Algorithm comparison framework

### Phase 5: ML Enhancement (Weeks 5-6)
- Automatic dhikr type recognition
- Personalized rhythm learning
- Core ML model integration
- Advanced session analytics

## Getting Started

### Prerequisites
- Xcode 15.0+
- Apple Watch Series 9 for optimal performance
- iOS 17.0+ / watchOS 10.0+
- Python 3.8+ for analysis environment

### Installation
1. Clone the repository
2. Open `DhikrCounter.xcodeproj` in Xcode
3. Build and deploy to Apple Watch Series 9
4. Install iPhone companion app
5. Set up Jupyter environment for algorithm development

## Command-Line Analysis Tool

### Overview

The `analyze_session.py` script provides comprehensive offline analysis of dhikr session data exported from the Apple Watch app. It implements the same stationary pinch detection algorithm used on the watch and generates detailed HTML reports with visualizations.

### Installation

1. **Set up Python environment**:
```bash
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements_analysis.txt
```

2. **Verify installation**:
```bash
python analyze_session.py --help
```

### Basic Usage

```bash
# Analyze a session file with default settings
python analyze_session.py --input session_data.json

# Analyze with custom configuration
python analyze_session.py --input session_data.json --config config.yaml

# Specify output directory
python analyze_session.py --input session_data.json --output results/
```

### Debug Modes

The tool includes comprehensive debugging capabilities:

```bash
# Detection debug - shows rejection statistics and analysis
python analyze_session.py --input session_data.json --debug-detection

# Threshold debug - analyzes peaks that don't cross adaptive threshold  
python analyze_session.py --input session_data.json --debug-threshold

# Enable all debug modes
python analyze_session.py --input session_data.json --debug-all
```

### Visual Debug Features

Every analysis automatically includes a **Visual Debug Plot** that shows:

- 📈 **Fusion score** with adaptive threshold
- ✅ **Accepted events** (green dots)
- 🔴 **Rejected candidates** color-coded by rejection reason:
  - **Red**: Refractory period violations
  - **Orange**: Not local peak
  - **Pink**: Gate check failures  
  - **Purple**: Minimum inter-event interval violations

### Output Files

The tool generates:

- **HTML Report** (`analysis_report.html`) - Interactive visualizations and analysis
- **CSV Events** (`detected_events.csv`) - Detected events for further analysis
- **JSON Summary** (`analysis_summary.json`) - Analysis metadata and statistics

### Configuration

Create a `config.yaml` file to customize detection parameters:

```yaml
stationary_params:
  k_mad: 5.5              # Adaptive threshold sensitivity
  acc_gate: 0.025         # Acceleration threshold (g)
  gyro_gate: 0.10         # Gyroscope threshold (rad/s)
  refractory_s: 0.12      # Refractory period (seconds)
  min_iei_s: 0.10         # Minimum inter-event interval (seconds)

output:
  export_html: true       # Generate HTML report
  export_csv: true        # Export detected events
  plot_components: true   # Include component analysis charts
```

### Supported Data Formats

- **JSON**: Complete session files from Apple Watch app
- **CSV**: Exported sensor data with metadata headers

### Example Analysis Output

```
📊 Analysis Complete!
  Events detected: 8
  Detection rate: 69.2 events/min
  Session duration: 6.9 seconds
  Results saved to: analysis_B4BFFF92_20250905_161517
```

## Usage

### Basic Operation
1. Start dhikr session on Apple Watch
2. Begin prayer recitation with finger pinches
3. Receive haptic feedback for each detected pinch
4. Get milestone notifications at 33, 66, and 100 counts
5. Use Double Tap for manual corrections when needed

### Development Workflow
1. Conduct dhikr sessions with data logging enabled
2. Export sensor data to iPhone companion app
3. Analyze performance and annotate ground truth
4. Export CSV data to Jupyter environment
5. Optimize algorithm parameters and deploy updates

## Algorithm Details

The detection engine implements a sophisticated multi-stage pipeline:

1. **Signal Processing**: 100Hz sensor data from Core Motion
2. **Feature Extraction**: Magnitude calculation and derivative computation
3. **Statistical Scoring**: Robust z-score fusion across sensor channels
4. **Adaptive Thresholding**: Segment-based 90th percentile adjustment
5. **Pattern Validation**: Backward-looking filter for sustained sequences
6. **Session Management**: Activity-based state transitions

## Contributing

This project focuses on accurate, respectful technology for Islamic prayer practices. Contributions should maintain the spiritual context and technical precision requirements.

## License

Copyright (c) 2024. This project is developed for educational and religious purposes.

## Support

For technical questions or spiritual guidance on dhikr practices, please consult with appropriate Islamic scholars and technical documentation.

---

*"And remember your Lord much and glorify [Him] in the evening and morning."* - Quran 3:41