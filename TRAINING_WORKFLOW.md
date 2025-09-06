# TKEO Pinch Detection Training Workflow

This document describes how to train and deploy personalized pinch detection templates for production use.

## Overview

The TKEO detector supports a **training workflow** where you:
1. **Capture training data** with deliberate pinches
2. **Extract high-quality templates** using analyze_session.py
3. **Save templates** for reuse across sessions
4. **Deploy templates** for real-time detection

This mimics real-world Apple Watch app behavior where users complete a calibration phase.

## Workflow Steps

### Phase 1: Training Data Collection

**Collect calibration session with clear, deliberate pinches:**

```bash
# This would be done in the Apple Watch app during setup
# User performs 10-15 clear pinch gestures
# Session saved as: training_session.csv
```

### Phase 2: Template Extraction

**Use analyze_session.py to get high-quality pinch detections:**

```bash
# Run analyze_session on training data
python analyze_session.py --input training_session.csv --config config.yaml --output training_results/

# This creates: training_results/analysis_SESSION_TIMESTAMP/ 
#   - detected_events.csv (high-quality pinch detections)
#   - analysis_report.html
#   - analysis_summary.json
```

### Phase 3: Template Training & Storage

**Train TKEO detector with analyze_session results and save templates:**

```bash
# Train templates and save for reuse
python tkeo_pinch_detector.py \
  --input training_session.csv \
  --config tkeo_config_additive.yaml \
  --analysis-results training_results/analysis_SESSION_TIMESTAMP/ \
  --save-templates \
  --output training_output/

# This creates: training_output/tkeo_analysis_SESSION_TIMESTAMP/
#   - trained_templates.json (reusable templates)
#   - tkeo_detection_report.html
#   - results.json
```

### Phase 4: Production Deployment

**Use trained templates for new sessions:**

```bash
# Production detection using trained templates
python tkeo_pinch_detector.py \
  --input new_session.csv \
  --config tkeo_config_additive.yaml \
  --trained-templates training_output/tkeo_analysis_SESSION_TIMESTAMP/trained_templates.json \
  --output detection_results/

# Fast detection - no session preprocessing needed!
```

## File Structure

```
project/
├── training_session.csv                    # Original training data
├── training_results/
│   └── analysis_SESSION_TIMESTAMP/
│       ├── detected_events.csv            # High-quality detections
│       └── analysis_report.html
├── training_output/
│   └── tkeo_analysis_SESSION_TIMESTAMP/
│       ├── trained_templates.json         # 🔑 REUSABLE TEMPLATES
│       └── tkeo_detection_report.html
└── detection_results/
    └── tkeo_analysis_SESSION_TIMESTAMP/    # Production detection results
```

## Template File Format

The `trained_templates.json` file contains:

```json
{
  "templates": [
    [0.23, 0.45, 0.67, ...],  // Template 1 (fusion score pattern)
    [0.12, 0.34, 0.56, ...],  // Template 2
    ...
  ],
  "template_length": 16,      // Template window size (samples)
  "confidence_threshold": 0.65, // NCC verification threshold
  "max_lag": 3,               // Timing jitter tolerance
  "config": {                 // Original detector configuration
    "fs": 100,
    "bandpass_low": 1.0,
    "bandpass_high": 8.0,
    ...
  },
  "source_session": {
    "filename": "training_session.csv",
    "duration": 45.2,
    "fs": 100.0,
    "created": "2025-01-09T10:30:00"
  }
}
```

## Production Considerations

### Template Compatibility

Templates are validated for compatibility:
- ✅ **Sampling rate** must match
- ✅ **Filter parameters** must match  
- ✅ **Template length** must match
- ⚠️ Warnings shown for parameter mismatches

### Template Quality

For best results:
- **Training session**: 30-60 seconds with 10-15 clear pinches
- **Diverse patterns**: Include various pinch strengths/speeds
- **Clean environment**: Minimize background motion during training
- **analyze_session score**: Use events with score >= 3.0

### Apple Watch Integration

In the real app:
1. **Onboarding**: "Please perform 10 pinches to calibrate detection"
2. **Template extraction**: Run analyze_session.py on device or server
3. **Template storage**: Save trained_templates.json to device storage
4. **Runtime detection**: Load templates once, detect continuously

## Command Reference

### Training Commands

```bash
# Full training pipeline
python analyze_session.py --input training.csv --config config.yaml --output training_results/
python tkeo_pinch_detector.py --input training.csv --analysis-results training_results/analysis_*/ --save-templates

# Training with multiplicative fusion
python tkeo_pinch_detector.py --input training.csv --config tkeo_config_multiplicative.yaml --analysis-results training_results/analysis_*/ --save-templates
```

### Production Commands

```bash
# Production detection
python tkeo_pinch_detector.py --input new_session.csv --trained-templates trained_templates.json

# With custom config
python tkeo_pinch_detector.py --input new_session.csv --config tkeo_config_additive.yaml --trained-templates trained_templates.json
```

## Performance Benefits

**Training Mode** (first time):
- Full session preprocessing required
- Template extraction from analyze_session results
- ~10-30 seconds processing time

**Production Mode** (subsequent sessions):
- ✅ **No session preprocessing** needed
- ✅ **Instant template loading** from JSON
- ✅ **~1-3 seconds** processing time  
- ✅ **Personalized patterns** for better accuracy

This workflow enables the personalized, fast pinch detection suitable for real-time Apple Watch applications.