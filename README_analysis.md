# Stationary Pinch Detection Analysis Tool

A command-line Python tool that implements the stationary pinch detection algorithm from `advanced_pinch_detector.ipynb` for offline analysis of DhikrCounter Watch App session data.

## Features

- **Dual Format Support**: Works with both CSV and JSON session files exported from DhikrCounter Watch App
- **Advanced Algorithm**: Implements 4-component z-score fusion with robust MAD-based statistics
- **Interactive Reports**: Generates professional HTML reports with Chart.js visualizations
- **Configurable Parameters**: YAML-based configuration for easy experimentation
- **Comprehensive Output**: CSV exports, analysis summaries, and detailed visualizations

## Installation

1. **Prerequisites**: Python 3.7+ with virtual environment
2. **Dependencies**: Install required packages
   ```bash
   source venv/bin/activate
   pip install numpy pandas scipy pyyaml
   ```

## Quick Start

1. **Minimal Usage** (uses defaults, outputs to current directory):
   ```bash
   python analyze_session.py --input session_data.csv
   ```

2. **With custom config**:
   ```bash
   python analyze_session.py --input session_data.csv --config config_template.yaml
   ```

3. **With custom output directory**:
   ```bash
   python analyze_session.py --input session_data.csv --output results/
   ```

4. **Full configuration**:
   ```bash
   python analyze_session.py --input session_data.csv --config config_template.yaml --output results/ --detector stationary
   ```

## File Formats

### CSV Session Files
Expected format from DhikrCounter Watch App CSV export:
```csv
# Session metadata as comments
time_s,epoch_s,userAccelerationX,userAccelerationY,userAccelerationZ,gravityX,gravityY,gravityZ,rotationRateX,rotationRateY,rotationRateZ,attitude_qW,attitude_qX,attitude_qY,attitude_qZ
0.000000,1757042534.450947,0.001295,-0.016554,-0.037696,...
```

### JSON Session Files
Expected format from DhikrCounter Watch App JSON export:
```json
{
  "metadata": {
    "sessionId": "B4BFFF92-CC48-4805-B1A7-D21B06B9774F",
    "duration": 7,
    "totalReadings": 691
  },
  "sensorData": [
    {
      "time_s": 87205.167743625003,
      "userAcceleration": {"x": 0.024916, "y": -0.010204, "z": 0.008506},
      "rotationRate": {"x": -0.189019, "y": 0.098172, "z": 0.141207},
      "gravity": {"x": -0.518477, "y": 0.661037, "z": -0.542411}
    }
  ]
}
```

## Algorithm Details

### Stationary Detection
The stationary detector implements a 4-component z-score fusion algorithm:

1. **Signal Preprocessing**:
   - High-pass moving mean filter on acceleration
   - Compute derivatives of acceleration and gyroscope signals

2. **Robust Z-score Calculation**:
   - Uses Median Absolute Deviation (MAD) for outlier resistance
   - Computes z-scores for: acceleration, gyroscope, acceleration derivative, gyroscope derivative

3. **Fusion Score**:
   ```
   score = √(z_a² + z_g² + z_da² + z_dg²)
   ```

4. **Adaptive Thresholding**:
   - Dynamic threshold using rolling MAD statistics
   - Configurable k_mad multiplier

5. **Event Validation**:
   - Local peak detection
   - Gate checks (minimum acceleration/gyroscope thresholds)
   - Refractory period enforcement
   - Inter-event interval validation

## Configuration

The YAML configuration file (`config_template.yaml`) contains all algorithm parameters:

### Key Parameters

```yaml
stationary_params:
  k_mad: 5.5           # MAD multiplier for adaptive threshold
  acc_gate: 0.025      # Acceleration gate threshold (g)
  gyro_gate: 0.10      # Gyroscope gate threshold (rad/s)
  hp_win: 0.5          # High-pass filter window (seconds)
  thr_win: 3.0         # Threshold computation window (seconds)
  refractory_s: 0.12   # Refractory period between events (seconds)
```

### Tuning Guidelines

- **Sensitivity**: Lower `k_mad` = more sensitive (more events)
- **Noise Reduction**: Higher `acc_gate`/`gyro_gate` = less noise
- **Temporal Resolution**: Smaller `refractory_s` = closer events allowed

## Output Files

Each analysis generates:

1. **`analysis_report.html`**: Interactive report with Chart.js visualizations
2. **`detected_events.csv`**: Event list with timestamps and metrics
3. **`analysis_summary.json`**: Session metadata and detection statistics

### HTML Report Features

- **Session Metadata**: Complete session information including collection time, app version, and data quality metrics
- **Raw Sensor Data**: 3-axis acceleration and gyroscope plots with magnitude overlays  
- **Fusion Score Timeline**: Shows detection score vs. adaptive threshold
- **Processed Signal Plots**: High-pass filtered acceleration and gyroscope with event markers
- **Component Analysis**: Individual z-score components (stationary only)
- **Event Statistics**: Detection rate, inter-event intervals, and event table
- **Parameter Summary**: Algorithm configuration used
- **Professional Styling**: Responsive design with Chart.js interactive visualizations

## Examples

### Example 1: Minimal Usage
```bash
# Analyze a CSV session file with defaults
python analyze_session.py --input data/session_24603A17_1757042582.csv

# Output:
# Using default configuration (no config file specified)
# Using current directory for output (no output directory specified)
# ✓ Detected 38 pinch events
# ✓ Detection rate: 79.5 events/min
# ✓ Results saved to: analysis_24603A17_20250904_203019/
```

### Example 2: JSON Analysis with Verbose Output
```bash
python analyze_session.py \
  --input data/session_B4BFFF92_1757042391.json \
  --config config_template.yaml \
  --output results/ \
  --verbose

# Shows detailed event information:
# 🎯 First few events:
#   Event 1: t=1.66s, score=18.6
#   Event 2: t=8.19s, score=4.4
```

### Example 3: Custom Configuration
Create a custom config file for sensitive detection:

```yaml
# sensitive_config.yaml
stationary_params:
  k_mad: 4.0           # Lower threshold (more sensitive)
  acc_gate: 0.020      # Lower acceleration gate
  gyro_gate: 0.08      # Lower gyroscope gate
  refractory_s: 0.08   # Shorter refractory period

output:
  chart_style: "clinical"
  include_debug: true
```

```bash
python analyze_session.py \
  --input data/session_24603A17_1757042582.csv \
  --config sensitive_config.yaml \
  --output results/
```

## Command-Line Options

```
usage: analyze_session.py [-h] --input INPUT [--config CONFIG] [--output OUTPUT]
                         [--batch] [--detector {stationary,walking}] 
                         [--verbose]

required arguments:
  --input, -i    Input session data file (CSV or JSON)

optional arguments:
  --config, -c   Configuration YAML file (uses defaults if not provided)
  --output, -o   Output directory (uses current directory if not provided)
  --batch        Process multiple files in input directory (future)
  --detector     Override detector type from config
  --verbose, -v  Enable verbose output
```

## Validation

The tool has been validated against the original notebook implementation:

- **Algorithm Fidelity**: Identical signal processing and detection logic
- **Parameter Compatibility**: Uses same default parameters as notebook
- **Format Support**: Handles both DhikrCounter export formats
- **Output Verification**: Results match notebook analysis patterns

## Performance

Typical performance on modern hardware:
- **Processing Speed**: ~100Hz data processed at 10x real-time
- **Memory Usage**: ~50MB for 30-minute sessions
- **File Support**: Sessions up to 1 hour (360,000 samples)

## Troubleshooting

### Common Issues

1. **"No module named numpy"**
   ```bash
   # Activate virtual environment first
   source venv/bin/activate
   pip install numpy pandas scipy pyyaml
   ```

2. **"Missing required columns"**
   - Ensure input file is from DhikrCounter Watch App export
   - Check file format matches expected CSV/JSON structure

3. **"Session too short"**
   - Minimum duration: 1.0 seconds (configurable in `analysis.min_duration_s`)
   - Check session recording was successful

4. **No events detected**
   - Try lowering `k_mad` parameter (more sensitive)
   - Check `acc_gate` and `gyro_gate` thresholds
   - Verify session contains actual movement data

5. **Want to use different parameters without config file**
   - Override individual parameters using `--detector` option
   - Create a minimal config file with just the parameters you want to change
   - The tool merges your config with defaults, so you only need to specify what you want to change

### Debug Mode

Enable verbose logging:
```bash
python analyze_session.py --input session.csv --config config.yaml --output results/ --verbose
```

## Future Enhancements

- [ ] Walking detection mode implementation
- [ ] Batch processing for multiple files
- [ ] Real-time processing capability
- [ ] Additional export formats (MATLAB, R)
- [ ] Machine learning validation metrics

## References

1. Original algorithm: `dsp/advanced_pinch_detector.ipynb`
2. DhikrCounter Watch App session export formats
3. Robust statistics using MAD (Median Absolute Deviation)
4. Chart.js visualization library

---

**Generated by**: DhikrCounter Pinch Detection Analysis Tool  
**Version**: 1.0  
**Compatible with**: DhikrCounter iOS/watchOS App v1.0+