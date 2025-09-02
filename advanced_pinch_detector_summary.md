# Advanced Pinch Detection Algorithm - Technical Summary

## Problem Statement

We are developing a wearable device that detects "pinch gestures" using wrist-mounted accelerometer and gyroscope sensors. The goal is to accurately identify discrete pinch movements (like prayer bead counting or similar repetitive finger actions) in real-time from noisy sensor data.

**Target Performance**: ~60 events per minute with minimal false positives and false negatives.

**Key Challenge**: Pinch signatures vary dramatically between stationary and walking states due to motion artifacts, requiring different detection strategies.

## Dual-Mode Detection Architecture

The system implements two specialized detectors:

### 1. Stationary Pinch Detector
**Use Case**: When user is sitting, standing still, or making minimal body movement
**Approach**: 4-component z-score fusion with robust statistics

### 2. Walking Pinch Detector  
**Use Case**: When user is walking, moving, or in dynamic environments
**Approach**: Advanced signal processing with envelope detection and multi-stage validation

## Core Mathematical Framework

### Signal Preprocessing

#### Input Signals
- **Accelerometer**: 3-axis acceleration (m/s²) → magnitude `acc_mag = √(ax² + ay² + az²)`
- **Gyroscope**: 3-axis angular velocity (rad/s) → magnitude `gyro_mag = √(gx² + gy² + gz²)`
- **Sampling Rate**: ~100 Hz typical

#### High-Pass Filtering
```python
a_hp = a - moving_average(a, window=0.5s)
```
**Purpose**: Remove DC bias and slow drift, isolate high-frequency pinch movements

#### Robust Statistics (MAD-based)
Traditional standard deviation is sensitive to outliers. We use **Median Absolute Deviation (MAD)**:

```python
median = rolling_median(signal, window)
mad = rolling_median(|signal - median|, window)
robust_zscore = (signal - median) / (1.4826 * mad)
```

**Why 1.4826?** This constant makes MAD equivalent to standard deviation for normal distributions, but much more robust to outliers.

## Stationary Detector Algorithm

### 4-Component Fusion Score
```python
z_acc = robust_zscore(acceleration_hp)
z_gyro = robust_zscore(gyroscope_magnitude) 
z_acc_deriv = robust_zscore(|d/dt(acceleration_hp)|)
z_gyro_deriv = robust_zscore(|d/dt(gyroscope_magnitude)|)

fusion_score = √(max(z_acc,0)² + max(z_gyro,0)² + max(z_acc_deriv,0)² + max(z_gyro_deriv,0)²)
```

**Mathematical Rationale**:
- **Acceleration term**: Captures wrist motion during pinch
- **Gyroscope term**: Captures rotational component  
- **Derivative terms**: Capture "jerk" (rate of change) - pinches have characteristic sharp acceleration/deceleration
- **Square root combination**: Euclidean norm provides balanced fusion
- **max(z,0)**: Only positive z-scores contribute (above-baseline activity)

### Adaptive Thresholding
```python
threshold(t) = rolling_median(score) + k_mad * rolling_MAD(score)
```
**Parameters**: 
- `k_mad = 5.5`: Multiplier for adaptive threshold
- `window = 3.0s`: Rolling window for threshold computation

**Why Adaptive?** Signal characteristics change over time due to:
- Sensor drift
- Changing grip/orientation  
- Environmental factors
- User variability

### Event Validation Pipeline
1. **Threshold Check**: `score > adaptive_threshold`
2. **Local Maxima**: Event must be peak within ±0.04s window
3. **Signal Gates**: 
   - Acceleration: `max(acc_hp) > 0.025g` in ±0.18s window
   - Gyroscope: `max(gyro) > 0.10 rad/s` in ±0.18s window
4. **Refractory Period**: Minimum 0.12s between events
5. **Inter-Event Interval**: Minimum 0.10s spacing

### Stationary Parameters
```python
STATIONARY_PARAMS = {
    'k_mad': 5.5,           # Adaptive threshold multiplier
    'acc_gate': 0.025,      # Acceleration gate (g)
    'gyro_gate': 0.10,      # Gyroscope gate (rad/s)  
    'hp_win': 0.5,          # High-pass window (s)
    'thr_win': 3.0,         # Threshold computation window (s)
    'refractory_s': 0.12,   # Refractory period (s)
    'peakwin_s': 0.04,      # Peak detection window (s)  
    'gatewin_s': 0.18,      # Gate validation window (s)
    'min_iei_s': 0.10       # Minimum inter-event interval (s)
}
```

## Walking Detector Algorithm

Walking introduces significant motion artifacts that can overwhelm pinch signals. The walking detector uses envelope-based processing and multiple validation stages.

### Signal Processing Pipeline

#### 1. Bandpass Filtering
```python
acc_bp = bandpass_filter(acc_hp, 6-22 Hz)
gyro_bp = bandpass_filter(gyro, 6-22 Hz)  
```
**Rationale**: Pinch frequencies typically 6-22 Hz, walking gait ~0.5-3 Hz

#### 2. RMS Envelope Detection
```python
acc_envelope = sqrt(rolling_mean(acc_bp², window=0.06s))
gyro_envelope = sqrt(rolling_mean(gyro_bp², window=0.06s))
```
**Purpose**: Extract amplitude modulation that characterizes pinch events during walking

#### 3. 2-Component Fusion Score
```python  
z_acc_env = robust_zscore(acc_envelope)
z_gyro_env = robust_zscore(gyro_envelope)
score = √(max(z_acc_env,0)² + max(z_gyro_env,0)²)
```

**Why Only 2 Components?** Walking motion makes derivative terms too noisy.

### Advanced Validation Stages

#### 1. Basic Validation
- Adaptive threshold: `k_mad = 4.0` (more sensitive than stationary)
- Signal gates: Same as stationary
- Local peak detection

#### 2. Peak Alignment Check
```python
acc_peak_time = argmax(acc_envelope, window)
gyro_peak_time = argmax(gyro_envelope, window)
if |acc_peak_time - gyro_peak_time| > 0.15s: reject
```
**Rationale**: True pinches show synchronized acceleration and gyroscope peaks

#### 3. Waveform Shape Analysis
```python
# Rise time analysis
rise_time = time_10%_to_90%_of_peak
if rise_time > 0.20s: reject

# Decay analysis  
decay_ratio = amplitude_after_0.14s / peak_amplitude
if decay_ratio > 0.75: reject
```
**Purpose**: Pinches have characteristic sharp rise and decay profiles

#### 4. Energy Ratio Validation
```python
E_high = sum(bandpass_signal²[6-22Hz])
E_low = sum(bandpass_signal²[0.7-3Hz])  
energy_ratio = E_high / E_low
if energy_ratio < 0.01: reject
```
**Rationale**: Pinches have higher energy in pinch frequencies vs gait frequencies

#### 5. Cross-Correlation Analysis
```python
correlation = max_correlation(acc_segment, gyro_segment, lag_window=0.10s)
if correlation < 0.30: reject
```
**Purpose**: Genuine pinches show correlated acceleration/gyroscope patterns

### Walking Parameters
```python
WALKING_PARAMS = {
    # Core detection (more sensitive)
    'k_mad': 4.0,
    'acc_gate': 0.025, 
    'gyro_gate': 0.10,
    
    # Signal processing
    'bp_lo': 6.0, 'bp_hi': 22.0,     # Bandpass filter range
    'env_win': 0.06,                 # Envelope window
    'thr_win': 3.0,                  # Threshold window
    
    # Walking-specific validation thresholds
    'align_tol_s': 0.15,             # Peak alignment tolerance
    'rise_max_s': 0.20,              # Maximum rise time  
    'decay_frac_max': 0.75,          # Maximum decay fraction
    'energy_ratio_min': 0.01,        # Minimum energy ratio
    'corr_min': 0.30,                # Minimum correlation
    'corr_lag_s': 0.10,              # Correlation lag window
    
    # Frequency bands for energy analysis
    'low_lo': 0.7, 'low_hi': 3.0,    # Gait frequency band
    
    # Event detection  
    'refractory_s': 0.12,
    'peakwin_s': 0.04,
    'gatewin_s': 0.20,               # Slightly larger for walking
    'min_iei_s': 0.10
}
```

## Key Mathematical Insights

### 1. Robust Statistics vs Standard Statistics
**Standard approach**: `z = (x - μ) / σ` (sensitive to outliers)
**Robust approach**: `z = (x - median) / (1.4826 * MAD)` (outlier resistant)

### 2. Multi-Component Fusion  
**Linear combination**: `score = w₁z₁ + w₂z₂ + ...` (weights needed)
**Euclidean norm**: `score = √(z₁² + z₂² + ...)` (automatic weighting)

### 3. Adaptive vs Fixed Thresholding
**Fixed**: Same threshold for all times (fails with signal variation)  
**Adaptive**: `threshold = f(local_signal_characteristics)` (robust to changes)

### 4. Envelope Detection Mathematics
**Hilbert transform**: Complex, computationally expensive
**RMS envelope**: `√(rolling_mean(signal²))` - simpler, effective approximation

## Performance Characteristics

### Stationary Detector
- **Typical Performance**: 70-80 events/min on stationary data
- **Strengths**: High sensitivity, good for subtle pinches
- **Weaknesses**: Prone to motion artifacts during walking

### Walking Detector  
- **Typical Performance**: 10-15 events/min on walking data (conservative by design)
- **Strengths**: Very low false positive rate during motion
- **Weaknesses**: May miss subtle pinches due to strict validation

## Implementation Notes

### Computational Complexity
- **Stationary**: O(N) for each signal processing stage
- **Walking**: O(N log N) due to correlation analysis
- **Memory**: ~3-5 seconds of buffered data needed for robust statistics

### Real-Time Considerations  
- **Latency**: ~1-2 seconds due to windowing requirements
- **Processing**: Can run in real-time on modern embedded systems
- **Power**: Moderate computational load suitable for wearable devices

## Current Performance Issues

### Walking Detector Challenges
Recent analysis revealed the walking detector has severe performance limitations:

**Debug Analysis Results**:
- Initial candidates above threshold: 795
- **"Not Peak" rejections: 614 (77.2%)** ← Major bottleneck
- Rise/decay rejections: 125 (15.7%)  
- Final accepted events: 10 (only 1.3% acceptance rate)

**Root Cause**: The local peak validation algorithm is too strict for noisy walking data, rejecting legitimate events due to minor variations in peak timing.

**Potential Solutions**:
1. Relax peak detection window parameters
2. Implement fuzzy peak detection  
3. Use simplified validation pipeline for walking scenarios
4. Develop hybrid approach that adapts validation strictness based on motion level

This technical summary provides the mathematical foundation and implementation details needed to understand, debug, and improve the pinch detection algorithm.