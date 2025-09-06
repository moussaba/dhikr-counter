#!/usr/bin/env python3
"""
Advanced TKEO-based Pinch Detection Pipeline
Based on research findings for Apple Watch micro-gesture detection

Implements:
- Teager-Kaiser Energy Operator (TKEO) for burst detection
- Band-pass filtering (3-20 Hz) 
- Jerk computation for transient emphasis
- Enhanced gyroscope fusion
- Template verification via normalized cross-correlation
- Two-stage detection: liberal gate + verification
"""

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from scipy import signal
from scipy.signal import butter, filtfilt
from scipy.interpolate import interp1d
import argparse
import os
import json
from pathlib import Path
import yaml
from datetime import datetime
import warnings
warnings.filterwarnings('ignore')

class BandPassFilter:
    """Band-pass filter for 3-20 Hz pinch frequency range"""
    
    def __init__(self, fs=100, low_freq=1.0, high_freq=8.0, order=2):
        self.fs = fs
        self.low_freq = low_freq
        self.high_freq = high_freq
        self.order = order
        
        # Design Butterworth band-pass filter
        nyquist = fs / 2
        low = low_freq / nyquist
        high = high_freq / nyquist
        self.b, self.a = butter(order, [low, high], btype='band')
        
        # For real-time processing, store filter state
        self.zi_x = signal.lfilter_zi(self.b, self.a)
        self.zi_y = signal.lfilter_zi(self.b, self.a)
        self.zi_z = signal.lfilter_zi(self.b, self.a)
    
    def filter_batch(self, data):
        """Filter entire signal (for offline analysis)"""
        filtered = np.zeros_like(data)
        for i in range(data.shape[1]):
            filtered[:, i] = filtfilt(self.b, self.a, data[:, i])
        return filtered
    
    def filter_sample(self, sample):
        """Filter single sample (for real-time simulation)"""
        # Not implemented for this prototype - using batch processing
        pass

class TKEOOperator:
    """Teager-Kaiser Energy Operator for transient detection"""
    
    @staticmethod
    def compute_tkeo(x):
        """
        Compute TKEO: ψ[x[n]] = x[n]² - x[n-1]*x[n+1]
        Emphasizes instantaneous frequency and amplitude modulation
        
        Args:
            x: Input signal (renamed to avoid shadowing scipy.signal)
        
        Returns:
            tkeo: Non-negative TKEO values (clamped to prevent false triggers)
        """
        if len(x) < 3:
            return np.zeros_like(x)
        
        tkeo = np.zeros_like(x)
        
        # Handle boundaries
        tkeo[0] = x[0]**2
        tkeo[-1] = x[-1]**2
        
        # Vectorized computation for interior points
        tkeo[1:-1] = x[1:-1]**2 - x[:-2] * x[2:]
        
        # Clamp to non-negative to prevent false triggers from negative lobes
        tkeo = np.maximum(tkeo, 0.0)
        
        return tkeo
    
    @staticmethod
    def compute_magnitude_tkeo(data):
        """Compute TKEO on signal magnitude"""
        magnitude = np.linalg.norm(data, axis=1)
        return TKEOOperator.compute_tkeo(magnitude)

class JerkComputer:
    """Compute jerk (first derivative) to emphasize rapid changes"""
    
    @staticmethod
    def compute_jerk(data, dt=0.01):
        """
        Compute jerk using central differences for cleaner transient emphasis
        Args:
            data: Nx3 array (acceleration or gyro data)
            dt: sampling interval
        
        Returns:
            jerk: First derivative computed with central differences (interior)
                 and one-sided differences (edges) for better alignment with peaks
        """
        # Use np.gradient for cleaner central differences
        # This avoids phase artifacts from forward differences
        jerk = np.gradient(data, dt, axis=0)
        return jerk

class BaselineTracker:
    """Adaptive baseline tracking with hysteresis"""
    
    def __init__(self, alpha=0.02, hampel_k=3.0):
        self.alpha = alpha  # EWMA coefficient (higher = faster adaptation)
        self.hampel_k = hampel_k  # MAD threshold multiplier
        self.mean = 0.0
        self.sigma = 1e-6  # Initialize with tiny value to be replaced by data-driven estimate
        self.history = []
        self.history_size = 1000  # Keep last 1000 samples for MAD
        self.initialized = False  # Track initialization state
    
    def update(self, value):
        """Update baseline statistics with new value using robust updating"""
        # Initialize on first sample
        if not self.initialized:
            self.mean = value
            self.initialized = True
        else:
            # Robust update: only update mean if value is not an outlier
            deviation = abs(value - self.mean)
            if deviation <= self.hampel_k * self.sigma:
                self.mean = (1 - self.alpha) * self.mean + self.alpha * value
        
        # Always update history for sigma calculation
        self.history.append(value)
        if len(self.history) > self.history_size:
            self.history.pop(0)
        
        # Update sigma every 100 samples (for efficiency)
        if len(self.history) % 100 == 0:
            self._update_sigma()
    
    def _update_sigma(self):
        """Update sigma estimate from Median Absolute Deviation"""
        if len(self.history) > 10:
            hist_array = np.array(self.history)
            median_val = np.median(hist_array)
            mad = np.median(np.abs(hist_array - median_val))
            # Convert MAD to sigma equivalent (MAD * 1.4826 ≈ σ for normal distribution)
            self.sigma = mad * 1.4826
            if self.sigma < 1e-6:  # Prevent division by zero
                self.sigma = 1e-6
    
    def get_threshold(self, k_multiplier=3.0):
        """Get adaptive threshold using sigma-scaled multiplier"""
        return self.mean + k_multiplier * self.sigma

class TemplateVerifier:
    """Template-based verification using normalized cross-correlation"""
    
    def __init__(self, template_length=16, max_lag=3):  # 160ms at 100Hz, ±30ms lag tolerance
        self.template_length = template_length
        self.templates = []
        self.confidence_threshold = 0.65
        self.max_lag = max_lag  # Maximum samples to search for timing jitter
    
    def add_template(self, signal_window):
        """Add a template pattern from known pinch event"""
        if len(signal_window) != self.template_length:
            # Resample to template length if needed
            x_old = np.linspace(0, 1, len(signal_window))
            x_new = np.linspace(0, 1, self.template_length)
            f = interp1d(x_old, signal_window, kind='linear')
            signal_window = f(x_new)
        
        # Normalize template
        normalized = self._normalize_signal(signal_window)
        self.templates.append(normalized)
    
    def _normalize_signal(self, signal):
        """Normalize signal to zero mean, unit variance"""
        signal = np.array(signal)
        if np.std(signal) > 1e-6:
            return (signal - np.mean(signal)) / np.std(signal)
        else:
            return signal - np.mean(signal)
    
    def verify_candidate(self, signal_window):
        """Verify candidate against stored templates"""
        if len(self.templates) == 0:
            return 0.0, False
        
        if len(signal_window) != self.template_length:
            # Resample to template length
            x_old = np.linspace(0, 1, len(signal_window))
            x_new = np.linspace(0, 1, self.template_length)
            f = interp1d(x_old, signal_window, kind='linear')
            signal_window = f(x_new)
        
        # Normalize candidate
        candidate_norm = self._normalize_signal(signal_window)
        
        # Compute NCC with all templates
        max_ncc = -1.0
        for template in self.templates:
            ncc = self._normalized_cross_correlation(candidate_norm, template)
            max_ncc = max(max_ncc, ncc)
        
        # Decision
        is_valid = max_ncc >= self.confidence_threshold
        return max_ncc, is_valid
    
    def _normalized_cross_correlation(self, signal, template):
        """Compute normalized cross-correlation with lag search for timing jitter tolerance
        
        Args:
            signal: Normalized candidate signal
            template: Normalized template signal
            
        Returns:
            max_correlation: Best correlation across all tested lags
        """
        if len(signal) != len(template):
            return 0.0
        
        max_correlation = -1.0
        
        # Search across small lags to handle timing jitter
        for lag in range(-self.max_lag, self.max_lag + 1):
            if lag == 0:
                # Zero lag case
                correlation = np.dot(signal, template) / len(template)
            elif lag > 0:
                # Positive lag: template shifted right relative to signal
                if lag >= len(signal):
                    continue
                signal_part = signal[:-lag] if lag < len(signal) else signal[:0]
                template_part = template[lag:]
                min_len = min(len(signal_part), len(template_part))
                if min_len > 0:
                    correlation = np.dot(signal_part[:min_len], template_part[:min_len]) / min_len
                else:
                    correlation = 0.0
            else:
                # Negative lag: template shifted left relative to signal
                abs_lag = abs(lag)
                if abs_lag >= len(signal):
                    continue
                signal_part = signal[abs_lag:]
                template_part = template[:-abs_lag] if abs_lag < len(template) else template[:0]
                min_len = min(len(signal_part), len(template_part))
                if min_len > 0:
                    correlation = np.dot(signal_part[:min_len], template_part[:min_len]) / min_len
                else:
                    correlation = 0.0
            
            max_correlation = max(max_correlation, correlation)
        
        return max_correlation

class AdvancedPinchDetector:
    """Main detector class implementing the two-stage pipeline"""
    
    def __init__(self, config=None):
        self.config = config or self._default_config()
        
        # Initialize components
        self.bandpass_filter = BandPassFilter(
            fs=self.config['fs'],
            low_freq=self.config['bandpass_low'],
            high_freq=self.config['bandpass_high']
        )
        
        self.tkeo_operator = TKEOOperator()
        self.jerk_computer = JerkComputer()
        
        # Separate baseline trackers for accel, gyro, and fusion
        self.accel_baseline = BaselineTracker(
            alpha=self.config['baseline_alpha'],
            hampel_k=self.config['hampel_k']
        )
        self.gyro_baseline = BaselineTracker(
            alpha=self.config['baseline_alpha'],
            hampel_k=self.config['hampel_k']
        )
        self.fusion_baseline = BaselineTracker(
            alpha=self.config['baseline_alpha'],
            hampel_k=self.config['hampel_k']
        )
        
        # Ensure fusion gate threshold is configured
        self.config.setdefault('gate_k_fusion', 3.0)
        
        self.template_verifier = TemplateVerifier(
            template_length=self.config['template_length']
        )
        # Wire template confidence from config
        self.template_verifier.confidence_threshold = self.config['template_confidence']
        
        # Detection state
        self.last_event_time = -float('inf')
        self.refractory_period = self.config['refractory_period_s']
        
        # Debug tracking
        self.debug_data = {
            'timestamps': [],
            'raw_accel': [],
            'raw_gyro': [],
            'filtered_accel': [],
            'filtered_gyro': [],
            'accel_jerk': [],
            'gyro_jerk': [],
            'accel_tkeo': [],
            'gyro_tkeo': [],
            'fusion_score': [],
            'accel_threshold': [],
            'gyro_threshold': [],
            'gate_triggers': [],
            'gate_events': [],        # All gate trigger events (before template verification)
            'template_scores': [],
            'final_detections': []    # Events that pass template verification
        }
    
    def _default_config(self):
        """Default configuration parameters"""
        return {
            'fs': 100,  # Sampling frequency
            'bandpass_low': 3.0,  # Hz
            'bandpass_high': 20.0,  # Hz  
            'baseline_alpha': 0.02,  # EWMA coefficient
            'hampel_k': 3.0,  # MAD multiplier
            'gate_k_accel': 3.0,  # Liberal gate threshold for accel
            'gate_k_gyro': 3.0,   # Liberal gate threshold for gyro
            'fusion_weight_accel': 1.0,  # Accel weight in fusion
            'fusion_weight_gyro': 1.5,   # Gyro weight (higher for micro-gestures)
            'fusion_method': 'additive',  # 'additive' or 'multiplicative'
            'template_length': 16,  # 160ms at 100Hz
            'template_confidence': 0.65,  # NCC threshold
            'refractory_period_s': 0.2,  # 200ms minimum between events
            'verification_window_s': 0.16,  # 160ms verification window
        }
    
    def _compute_fusion_score(self, accel_tkeo, gyro_tkeo):
        """Compute fusion score using configured method
        
        Args:
            accel_tkeo: Accelerometer TKEO values
            gyro_tkeo: Gyroscope TKEO values
            
        Returns:
            fusion_score: Combined sensor signal
        """
        if self.config['fusion_method'] == 'multiplicative':
            # Multiplicative fusion: high score only when both sensors active
            # Helps suppress noise appearing on single sensor
            weighted_accel = self.config['fusion_weight_accel'] * accel_tkeo
            weighted_gyro = self.config['fusion_weight_gyro'] * gyro_tkeo
            # Add small epsilon to prevent zero multiplication
            epsilon = 1e-10
            fusion_score = (weighted_accel + epsilon) * (weighted_gyro + epsilon)
        else:
            # Default additive fusion
            fusion_score = (self.config['fusion_weight_accel'] * accel_tkeo + 
                          self.config['fusion_weight_gyro'] * gyro_tkeo)
        
        return fusion_score
    
    def _validate_sampling_rate(self, timestamps, tolerance_pct=2.0):
        """Validate sampling rate against configuration and warn on mismatches
        
        Args:
            timestamps: Array of timestamps from session
            tolerance_pct: Percentage tolerance for sampling rate mismatch
            
        Returns:
            measured_fs: Actual measured sampling rate
        """
        if len(timestamps) < 2:
            print("Warning: Insufficient timestamps for sampling rate validation")
            return self.config['fs']
        
        # Calculate measured sampling rate
        duration = timestamps[-1] - timestamps[0]
        measured_fs = (len(timestamps) - 1) / duration
        
        # Check for significant mismatch
        config_fs = self.config['fs']
        deviation_pct = abs(measured_fs - config_fs) / config_fs * 100
        
        if deviation_pct > tolerance_pct:
            print(f"WARNING: Sampling rate mismatch detected!")
            print(f"  Configured: {config_fs:.1f} Hz")
            print(f"  Measured: {measured_fs:.1f} Hz")
            print(f"  Deviation: {deviation_pct:.1f}%")
            print(f"  This may affect filter performance and detection window sizing.")
        else:
            print(f"Sampling rate validation: {measured_fs:.1f} Hz (within {tolerance_pct}% of configured {config_fs:.1f} Hz)")
        
        return measured_fs
    
    def add_calibration_template(self, fusion_score, event_indices):
        """Add templates from known pinch events using precomputed fusion score
        
        Args:
            fusion_score: Precomputed fusion score from full session processing
            event_indices: List of sample indices where pinch events occur
        """
        for event_idx in event_indices:
            # Extract window around event from precomputed fusion score
            half_window = self.config['template_length'] // 2
            start_idx = max(0, event_idx - half_window)
            end_idx = min(len(fusion_score), event_idx + half_window)
            
            if end_idx - start_idx < self.config['template_length']:
                continue
                
            # Get actual window indices
            window_indices = range(start_idx, start_idx + self.config['template_length'])
            
            # Extract template from precomputed fusion score
            # This ensures identical processing to detection pipeline
            template_fusion_score = fusion_score[window_indices]
            
            # Add to template verifier
            self.template_verifier.add_template(template_fusion_score)
    
    def process_session(self, accel_data, gyro_data, timestamps):
        """Process entire session and return detected events"""
        # Validate sampling rate
        measured_fs = self._validate_sampling_rate(timestamps)
        
        # Use measured sampling rate for time-based calculations
        dt = 1.0 / measured_fs
        n_samples = len(accel_data)
        
        # Apply band-pass filtering
        print("Applying band-pass filtering...")
        accel_filtered = self.bandpass_filter.filter_batch(accel_data)
        gyro_filtered = self.bandpass_filter.filter_batch(gyro_data)
        
        # Compute TKEO per-axis on band-passed data (not on jerk magnitude)
        print("Computing TKEO...")
        # Apply TKEO to each axis of band-passed data to preserve oscillatory structure
        accel_tkeo_axes = np.array([self.tkeo_operator.compute_tkeo(accel_filtered[:, k]) for k in range(3)])
        gyro_tkeo_axes = np.array([self.tkeo_operator.compute_tkeo(gyro_filtered[:, k]) for k in range(3)])
        
        # Fuse across axes: L2 norm of positive TKEO values
        accel_tkeo = np.sqrt(np.sum(np.maximum(accel_tkeo_axes, 0.0)**2, axis=0))
        gyro_tkeo = np.sqrt(np.sum(np.maximum(gyro_tkeo_axes, 0.0)**2, axis=0))
        
        # Keep jerk for auxiliary analysis (optional - can be used in plots)
        accel_jerk = self.jerk_computer.compute_jerk(accel_filtered, dt) 
        gyro_jerk = self.jerk_computer.compute_jerk(gyro_filtered, dt)
        
        # Create fusion score using configured method
        fusion_score = self._compute_fusion_score(accel_tkeo, gyro_tkeo)
        
        # Process sample by sample for baseline tracking and detection
        print("Processing samples for detection...")
        detected_events = []
        gate_events = []          # All events that trigger the gate
        gate_triggers = []
        template_scores = []
        
        accel_thresholds = []
        gyro_thresholds = []
        fusion_thresholds = []
        
        verification_window_samples = int(self.config['verification_window_s'] * self.config['fs'])
        
        # Warm-up period to prevent initial over-thresholding
        warmup_samples = int(0.5 * self.config['fs'])
        
        for i in range(n_samples):
            # Update all baselines
            self.accel_baseline.update(accel_tkeo[i])
            self.gyro_baseline.update(gyro_tkeo[i])
            self.fusion_baseline.update(fusion_score[i])
            
            # Get adaptive thresholds
            accel_threshold = self.accel_baseline.get_threshold(self.config['gate_k_accel'])
            gyro_threshold = self.gyro_baseline.get_threshold(self.config['gate_k_gyro']) 
            fusion_threshold = self.fusion_baseline.get_threshold(self.config['gate_k_fusion'])
            
            accel_thresholds.append(accel_threshold)
            gyro_thresholds.append(gyro_threshold)
            fusion_thresholds.append(fusion_threshold)
            
            # Skip gating during warm-up period
            if i < warmup_samples:
                gate_triggers.append(False)
                continue
            
            # Stage 1: Gate on fusion score (more robust than per-sensor OR)
            gate_triggered = fusion_score[i] > fusion_threshold
            
            gate_triggers.append(gate_triggered)
            
            # Check refractory period for gate events
            current_time = timestamps[i]
            
            # Record gate events (before refractory/template checks)
            if gate_triggered:
                gate_events.append({
                    'index': i,
                    'time': current_time,
                    'accel_tkeo': accel_tkeo[i],
                    'gyro_tkeo': gyro_tkeo[i],
                    'fusion_score': fusion_score[i],
                    'accel_threshold': accel_threshold,
                    'gyro_threshold': gyro_threshold
                })
            
            # Apply refractory period check
            if current_time - self.last_event_time < self.refractory_period:
                template_scores.append(0.0)
                continue
            
            # Stage 2: Template verification
            template_score = 0.0
            is_valid_event = False
            
            if gate_triggered:
                # Extract verification window
                start_idx = max(0, i - verification_window_samples//2)
                end_idx = min(n_samples, i + verification_window_samples//2)
                
                if end_idx - start_idx >= verification_window_samples:
                    window_indices = range(start_idx, start_idx + verification_window_samples)
                    fusion_window = fusion_score[window_indices]
                    
                    # Verify against templates
                    template_score, is_valid_event = self.template_verifier.verify_candidate(fusion_window)
                    
                    # DEBUG: For ultra-low thresholds, bypass template verification
                    if self.template_verifier.confidence_threshold <= 0.05:
                        is_valid_event = True
                        template_score = 0.8  # Assign default confidence
            
            template_scores.append(template_score)
            
            if is_valid_event:
                detected_events.append({
                    'index': i,
                    'time': current_time,
                    'confidence': template_score,
                    'accel_tkeo': accel_tkeo[i],
                    'gyro_tkeo': gyro_tkeo[i],
                    'fusion_score': fusion_score[i]
                })
                self.last_event_time = current_time
        
        # Store debug data
        self.debug_data.update({
            'timestamps': timestamps,
            'raw_accel': accel_data,
            'raw_gyro': gyro_data,
            'filtered_accel': accel_filtered,
            'filtered_gyro': gyro_filtered,
            'accel_jerk': accel_jerk,
            'gyro_jerk': gyro_jerk,
            'accel_tkeo': accel_tkeo,
            'gyro_tkeo': gyro_tkeo,
            'fusion_score': fusion_score,
            'accel_threshold': np.array(accel_thresholds),
            'gyro_threshold': np.array(gyro_thresholds),
            'gate_triggers': np.array(gate_triggers),
            'gate_events': gate_events,        # All gate events
            'template_scores': np.array(template_scores),
            'final_detections': detected_events  # Template-verified events
        })
        
        # Print detailed statistics
        print(f"\n=== DETAILED DETECTION STATISTICS ===")
        print(f"Total gate triggers: {len(gate_events)}")
        print(f"Template-verified events: {len(detected_events)}")
        if len(gate_events) > 0:
            print(f"Template verification rate: {len(detected_events) / len(gate_events) * 100:.1f}%")
            print(f"Template rejection rate: {(len(gate_events) - len(detected_events)) / len(gate_events) * 100:.1f}%")
        
        return detected_events

def load_session_data(file_path):
    """Load session data from CSV file"""
    print(f"Loading session data from {file_path}")
    
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"Session file not found: {file_path}")
    
    # Load CSV data, skipping comment lines that start with #
    df = pd.read_csv(file_path, comment='#')
    
    # Extract required columns
    required_columns = [
        'time_s', 'userAccelerationX', 'userAccelerationY', 'userAccelerationZ',
        'rotationRateX', 'rotationRateY', 'rotationRateZ'
    ]
    
    missing_columns = [col for col in required_columns if col not in df.columns]
    if missing_columns:
        raise ValueError(f"Missing required columns: {missing_columns}")
    
    # Extract data
    timestamps = df['time_s'].values
    timestamps = timestamps - timestamps[0]  # Start from 0
    
    accel_data = df[['userAccelerationX', 'userAccelerationY', 'userAccelerationZ']].values
    gyro_data = df[['rotationRateX', 'rotationRateY', 'rotationRateZ']].values
    
    print(f"Loaded {len(timestamps)} samples, duration: {timestamps[-1]:.1f} seconds")
    
    return timestamps, accel_data, gyro_data

def load_analyze_session_templates(analysis_results_dir, timestamps, confidence_threshold=3.0):
    """Load templates from analyze_session.py results (more accurate than streaming)
    
    Args:
        analysis_results_dir: Directory containing analyze_session results
        timestamps: Session timestamps for index conversion
        confidence_threshold: Minimum score threshold for template selection
    
    Returns:
        List of sample indices for template extraction
    """
    print(f"\nLoading templates from analyze_session results (more accurate)...")
    
    # Look for detected events CSV file from analyze_session
    events_file = os.path.join(analysis_results_dir, 'detected_events.csv')
    
    if not os.path.exists(events_file):
        print(f"Warning: Analyze session events file not found at {events_file}")
        print("Trying alternative file name...")
        # Try alternative naming patterns
        for alt_name in ['events.csv', 'analysis_events.csv', 'pinch_events.csv']:
            alt_path = os.path.join(analysis_results_dir, alt_name)
            if os.path.exists(alt_path):
                events_file = alt_path
                break
        else:
            print("No analyze_session results found, falling back to simulated templates...")
            return create_simulated_templates(timestamps)
    
    try:
        # Load analyze_session detections
        df = pd.read_csv(events_file)
        print(f"Loaded {len(df)} analyze_session detections")
        
        # Display available columns for debugging
        print(f"Available columns: {list(df.columns)}")
        
        # Filter by score threshold (analyze_session uses 'score' field)
        if 'score' in df.columns:
            high_conf = df[df['score'] >= confidence_threshold]
            print(f"Filtered to {len(high_conf)} high-score events (score >= {confidence_threshold})")
        else:
            # Fallback: use all events if no score column
            high_conf = df
            print(f"No score column found, using all {len(high_conf)} events")
        
        if len(high_conf) == 0:
            print(f"No events above score threshold {confidence_threshold}, using simulated templates")
            return create_simulated_templates(timestamps)
        
        # Convert event times to sample indices
        template_indices = []
        fs = len(timestamps) / (timestamps[-1] - timestamps[0])  # Calculate actual sampling rate
        
        for _, event in high_conf.iterrows():
            # analyze_session.py uses 'time' field for event times
            event_time = event.get('time', event.get('time_s', 0))
            
            # Find closest timestamp in session
            idx = np.argmin(np.abs(timestamps - event_time))
            
            # Validate index is within reasonable bounds
            if 0 <= idx < len(timestamps):
                template_indices.append(idx)
        
        # Limit to 15-20 templates and spread them across session
        if len(template_indices) > 20:
            # Select subset spread across session
            indices = np.linspace(0, len(template_indices)-1, 15, dtype=int)
            template_indices = [template_indices[i] for i in indices]
        elif len(template_indices) < 5:
            # If too few templates, add some simulated ones
            print(f"Only {len(template_indices)} templates found, adding simulated ones...")
            simulated_indices = create_simulated_templates(timestamps)
            # Take subset that don't conflict
            for sim_idx in simulated_indices:
                # Check if simulated template is far enough from existing ones
                if all(abs(sim_idx - exist_idx) > fs * 0.5 for exist_idx in template_indices):
                    template_indices.append(sim_idx)
                    if len(template_indices) >= 12:  # Reasonable number
                        break
        
        template_times = [timestamps[i] for i in template_indices]
        print(f"Using {len(template_indices)} analyze_session detections as templates")
        print(f"Template times: {[f'{t:.1f}s' for t in template_times[:8]]}{'...' if len(template_times) > 8 else ''}")
        
        # Show score distribution of selected templates
        if 'score' in df.columns:
            selected_scores = []
            for idx in template_indices:
                # Find matching event by time
                event_time = timestamps[idx]
                matching_events = high_conf[abs(high_conf['time'] - event_time) < 0.1]
                if len(matching_events) > 0:
                    selected_scores.append(matching_events.iloc[0]['score'])
            if selected_scores:
                print(f"Template scores: {np.min(selected_scores):.1f} to {np.max(selected_scores):.1f} (avg: {np.mean(selected_scores):.1f})")
        
        return template_indices
        
    except Exception as e:
        print(f"Error loading analyze_session templates: {e}")
        print("Falling back to simulated templates...")
        return create_simulated_templates(timestamps)

def create_simulated_templates(timestamps):
    """Fallback: Create templates from simulated manual event identification"""
    print("Creating simulated templates...")
    
    # Simulate 12 template events spread across the session
    session_duration = timestamps[-1]
    n_templates = 12
    
    # Create templates at regular intervals (simulating manual marking)
    template_times = np.linspace(session_duration * 0.1, session_duration * 0.9, n_templates)
    template_indices = []
    
    for t in template_times:
        idx = np.argmin(np.abs(timestamps - t))
        template_indices.append(idx)
    
    print(f"Created {len(template_indices)} simulated templates")
    return template_indices

def save_templates_for_reuse(detector, output_dir, session_info):
    """Save trained templates for reuse in future sessions
    
    Args:
        detector: TKEO detector with loaded templates
        output_dir: Directory to save template data
        session_info: Session metadata for template provenance
    """
    import json
    
    templates_data = {
        'templates': [template.tolist() for template in detector.template_verifier.templates],
        'template_length': detector.template_verifier.template_length,
        'confidence_threshold': detector.template_verifier.confidence_threshold,
        'max_lag': detector.template_verifier.max_lag,
        'config': detector.config,
        'source_session': {
            'filename': session_info.get('filename'),
            'duration': session_info.get('duration'),
            'fs': session_info.get('fs'),
            'created': datetime.now().isoformat()
        }
    }
    
    templates_file = os.path.join(output_dir, 'trained_templates.json')
    with open(templates_file, 'w') as f:
        json.dump(templates_data, f, indent=2)
    
    print(f"✓ Saved {len(detector.template_verifier.templates)} templates to: {templates_file}")
    return templates_file

def load_trained_templates(templates_file, detector):
    """Load previously trained templates from another session
    
    Args:
        templates_file: Path to saved trained_templates.json file
        detector: TKEO detector instance to load templates into
        
    Returns:
        True if templates loaded successfully, False otherwise
    """
    if not os.path.exists(templates_file):
        return False
        
    try:
        with open(templates_file, 'r') as f:
            templates_data = json.load(f)
        
        # Validate compatibility
        saved_config = templates_data.get('config', {})
        current_config = detector.config
        
        # Check critical parameters that must match
        critical_params = ['fs', 'bandpass_low', 'bandpass_high', 'template_length']
        for param in critical_params:
            if abs(saved_config.get(param, 0) - current_config.get(param, 0)) > 0.1:
                print(f"Warning: Template parameter mismatch - {param}: saved={saved_config.get(param)} vs current={current_config.get(param)}")
        
        # Load templates into detector
        templates = [np.array(template) for template in templates_data['templates']]
        detector.template_verifier.templates = templates
        detector.template_verifier.template_length = templates_data['template_length']
        detector.template_verifier.confidence_threshold = templates_data['confidence_threshold']
        detector.template_verifier.max_lag = templates_data.get('max_lag', 3)
        
        source_info = templates_data.get('source_session', {})
        print(f"✓ Loaded {len(templates)} trained templates from: {source_info.get('filename', 'unknown')}")
        print(f"  Training session duration: {source_info.get('duration', 0):.1f}s")
        print(f"  Template created: {source_info.get('created', 'unknown')}")
        
        return True
        
    except Exception as e:
        print(f"Error loading trained templates: {e}")
        return False

def create_templates_for_detector(timestamps, accel_data, gyro_data, detector, analysis_results_dir=None, trained_templates_file=None):
    """Create templates using best available method with full session preprocessing
    
    Args:
        timestamps: Session timestamps
        accel_data: Accelerometer data 
        gyro_data: Gyroscope data
        detector: TKEO detector instance
        analysis_results_dir: Directory with analyze_session.py results (for training new templates)
        trained_templates_file: Path to pre-trained templates from another session
    
    Returns:
        List of template indices used (empty if using pre-trained templates)
    """
    
    # Priority 1: Use pre-trained templates from another session (production mode)
    if trained_templates_file:
        print(f"\nAttempting to load pre-trained templates from: {trained_templates_file}")
        if load_trained_templates(trained_templates_file, detector):
            print("Using pre-trained templates - no session preprocessing needed")
            return []  # No indices needed since templates are already loaded
        else:
            print("Failed to load pre-trained templates, falling back to other methods...")
    
    # Priority 2: Use analyze_session results (training mode)
    if analysis_results_dir:
        # Try to load from analyze_session algorithm first (more accurate)
        template_indices = load_analyze_session_templates(analysis_results_dir, timestamps)
    else:
        # Priority 3: Fallback to simulated templates
        print("No analysis results directory provided, using simulated templates")
        template_indices = create_simulated_templates(timestamps)
    
    # Preprocess full session to ensure template consistency
    print("Preprocessing full session for template extraction...")
    dt = 1.0 / detector.config['fs']
    
    # Apply same processing pipeline as detection
    accel_filtered = detector.bandpass_filter.filter_batch(accel_data)
    gyro_filtered = detector.bandpass_filter.filter_batch(gyro_data)
    
    accel_jerk = detector.jerk_computer.compute_jerk(accel_filtered, dt)
    gyro_jerk = detector.jerk_computer.compute_jerk(gyro_filtered, dt)
    
    accel_tkeo = detector.tkeo_operator.compute_magnitude_tkeo(accel_jerk)
    gyro_tkeo = detector.tkeo_operator.compute_magnitude_tkeo(gyro_jerk)
    
    # Create fusion score using detector's method
    fusion_score = detector._compute_fusion_score(accel_tkeo, gyro_tkeo)
    
    # Add templates to detector using precomputed features
    detector.add_calibration_template(fusion_score, template_indices)
    
    return template_indices

def generate_html_report(detector, session_info, output_dir, time_range=None, y_range=None):
    """Generate comprehensive HTML report with debug plots"""
    
    debug_data = detector.debug_data
    timestamps = debug_data['timestamps']
    
    # Apply time range filtering if specified
    if time_range is not None:
        start_time, end_time = time_range
        time_mask = (timestamps >= start_time) & (timestamps <= end_time)
        timestamps = timestamps[time_mask]
        
        # Filter all time-series data
        for key in ['raw_accel', 'raw_gyro', 'filtered_accel', 'filtered_gyro', 
                   'accel_jerk', 'gyro_jerk', 'accel_tkeo', 'gyro_tkeo', 
                   'fusion_score', 'accel_threshold', 'gyro_threshold', 'gate_triggers']:
            if key in debug_data and len(debug_data[key]) == len(time_mask):
                debug_data[key] = debug_data[key][time_mask]
        
        # Filter template scores if they exist
        if 'template_scores' in debug_data:
            template_scores = debug_data['template_scores']
            if len(template_scores) == len(time_mask):
                debug_data['template_scores'] = template_scores[time_mask]
        
        # Filter events to time range
        debug_data['gate_events'] = [e for e in debug_data['gate_events'] if start_time <= e['time'] <= end_time]
        debug_data['final_detections'] = [e for e in debug_data['final_detections'] if start_time <= e['time'] <= end_time]
    
    # Create plots
    fig, axes = plt.subplots(6, 1, figsize=(15, 20))
    fig.suptitle(f'Advanced TKEO Pinch Detection Analysis\nSession: {session_info["filename"]}', fontsize=16)
    plt.subplots_adjust(hspace=0.4)  # Better spacing between plots
    
    # Plot 1: Raw sensor data
    ax = axes[0]
    ax.plot(timestamps, np.linalg.norm(debug_data['raw_accel'], axis=1), 'b-', alpha=0.7, label='Accel Magnitude')
    ax.plot(timestamps, np.linalg.norm(debug_data['raw_gyro'], axis=1), 'r-', alpha=0.7, label='Gyro Magnitude')
    
    # Mark gate events (orange)
    for event in debug_data['gate_events']:
        ax.axvline(x=event['time'], color='orange', linestyle=':', alpha=0.6, linewidth=1, label='Gate Events' if event == debug_data['gate_events'][0] else "")
    
    # Mark final detections (green)
    for event in debug_data['final_detections']:
        ax.axvline(x=event['time'], color='green', linestyle='--', alpha=0.8, linewidth=2, label='Template Verified' if event == debug_data['final_detections'][0] else "")
    
    ax.set_title(f'Raw Sensor Data: Gate Events ({len(debug_data["gate_events"])}) vs Final Detections ({len(debug_data["final_detections"])})')
    ax.set_ylabel('Magnitude')
    ax.legend()
    ax.grid(True, alpha=0.3)
    
    # Apply y-axis range if specified
    if y_range is not None:
        ax.set_ylim(y_range)
    
    # Plot 2: Filtered data
    ax = axes[1] 
    ax.plot(timestamps, np.linalg.norm(debug_data['filtered_accel'], axis=1), 'b-', alpha=0.7, label='Filtered Accel')
    ax.plot(timestamps, np.linalg.norm(debug_data['filtered_gyro'], axis=1), 'r-', alpha=0.7, label='Filtered Gyro')
    ax.set_title(f'Band-Pass Filtered Data ({detector.config["bandpass_low"]}-{detector.config["bandpass_high"]} Hz)')
    ax.set_ylabel('Magnitude')
    ax.legend()
    ax.grid(True, alpha=0.3)
    
    if y_range is not None:
        ax.set_ylim(y_range)
    
    # Plot 3: Jerk signals
    ax = axes[2]
    ax.plot(timestamps, np.linalg.norm(debug_data['accel_jerk'], axis=1), 'b-', alpha=0.7, label='Accel Jerk')
    ax.plot(timestamps, np.linalg.norm(debug_data['gyro_jerk'], axis=1), 'r-', alpha=0.7, label='Gyro Jerk')
    ax.set_title('Jerk Signals (First Derivative)')
    ax.set_ylabel('Jerk Magnitude')
    ax.legend()
    ax.grid(True, alpha=0.3)
    
    if y_range is not None:
        ax.set_ylim(y_range)
    
    # Plot 4: TKEO signals with thresholds
    ax = axes[3]
    ax.plot(timestamps, debug_data['accel_tkeo'], 'b-', alpha=0.7, label='Accel TKEO')
    ax.plot(timestamps, debug_data['gyro_tkeo'], 'r-', alpha=0.7, label='Gyro TKEO')
    ax.plot(timestamps, debug_data['accel_threshold'], 'b--', alpha=0.5, label='Accel Threshold')
    ax.plot(timestamps, debug_data['gyro_threshold'], 'r--', alpha=0.5, label='Gyro Threshold')
    
    # Mark gate triggers
    gate_indices = np.where(debug_data['gate_triggers'])[0]
    if len(gate_indices) > 0:
        ax.scatter(timestamps[gate_indices], debug_data['accel_tkeo'][gate_indices], 
                  c='orange', s=20, alpha=0.6, label='Gate Triggers')
    
    ax.set_title('TKEO Signals with Adaptive Thresholds')
    ax.set_ylabel('TKEO Value')
    ax.legend()
    ax.grid(True, alpha=0.3)
    
    if y_range is not None:
        ax.set_ylim(y_range)
    
    # Plot 5: Fusion score and template verification
    ax = axes[4]
    ax.plot(timestamps, debug_data['fusion_score'], 'purple', alpha=0.8, label='Fusion Score')
    # Handle potential length mismatch in template_scores
    template_scores = debug_data['template_scores']
    if len(template_scores) == len(timestamps):
        ax.plot(timestamps, template_scores, 'orange', alpha=0.7, label='Template NCC Score')
    elif len(template_scores) > 0:
        # Truncate or pad to match timestamps
        min_len = min(len(template_scores), len(timestamps))
        ax.plot(timestamps[:min_len], template_scores[:min_len], 'orange', alpha=0.7, label='Template NCC Score')
        if len(template_scores) != len(timestamps):
            print(f"Note: template_scores ({len(template_scores)}) adjusted to match timestamps ({len(timestamps)})")
    ax.axhline(y=detector.template_verifier.confidence_threshold, color='red', 
               linestyle=':', label=f'NCC Threshold ({detector.template_verifier.confidence_threshold})')
    
    # Mark final detections
    for event in debug_data['final_detections']:
        ax.axvline(x=event['time'], color='green', linestyle='--', alpha=0.8, linewidth=2)
        ax.scatter(event['time'], event['confidence'], c='green', s=100, marker='*', zorder=10)
    
    ax.set_title('Fusion Score and Template Verification')
    ax.set_ylabel('Score')
    ax.legend()
    ax.grid(True, alpha=0.3)
    
    if y_range is not None:
        ax.set_ylim(y_range)
    
    # Plot 6: Detection summary with gate vs final comparison
    ax = axes[5]
    
    # Create detection timelines
    gate_timeline = np.zeros_like(timestamps)
    final_timeline = np.zeros_like(timestamps)
    
    # Mark gate events
    for event in debug_data['gate_events']:
        idx = np.argmin(np.abs(timestamps - event['time']))
        gate_timeline[idx] = 0.6
    
    # Mark final detections
    for event in debug_data['final_detections']:
        idx = np.argmin(np.abs(timestamps - event['time']))
        final_timeline[idx] = 1.0
    
    # Plot both timelines
    ax.plot(timestamps, gate_timeline, 'o-', color='orange', markersize=6, linewidth=1, 
            label=f'Gate Events ({len(debug_data["gate_events"])})', alpha=0.8)
    ax.plot(timestamps, final_timeline, 'go-', markersize=8, linewidth=2, 
            label=f'Template Verified ({len(debug_data["final_detections"])})')
    
    # Fill gate active regions
    ax.fill_between(timestamps, 0, debug_data['gate_triggers'].astype(float) * 0.3, 
                    alpha=0.2, color='orange', label='Gate Active')
    
    # Calculate and show rejection rate
    rejection_rate = 0
    if len(debug_data['gate_events']) > 0:
        rejection_rate = (len(debug_data['gate_events']) - len(debug_data['final_detections'])) / len(debug_data['gate_events']) * 100
    
    ax.set_title(f'Gate vs Template Verification - Rejection Rate: {rejection_rate:.1f}%')
    ax.set_xlabel('Time (seconds)')
    ax.set_ylabel('Detection Level')
    ax.legend()
    ax.grid(True, alpha=0.3)
    ax.set_ylim(-0.1, 1.3)
    
    if y_range is not None and len(y_range) == 2:  # Only set if valid range provided
        ax.set_ylim(y_range)
    
    # Save plot
    plt.tight_layout()
    plot_path = os.path.join(output_dir, 'tkeo_detection_analysis.png')
    plt.savefig(plot_path, dpi=300, bbox_inches='tight')
    print(f"✓ Generated plot: {plot_path}")
    plt.close()
    
    # Generate HTML report
    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Advanced TKEO Pinch Detection Report</title>
        <style>
            body {{ font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #fafafa; }}
            .header {{ 
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
                color: white; padding: 20px; border-radius: 12px; margin-bottom: 20px; 
                box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            }}
            .header h1 {{ margin: 0 0 15px 0; font-size: 24px; }}
            .info-grid {{ 
                display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
                gap: 15px; font-size: 14px; 
            }}
            .info-item {{ background: rgba(255,255,255,0.15); padding: 10px; border-radius: 8px; }}
            .info-item strong {{ display: block; margin-bottom: 5px; }}
            
            .section {{ margin: 25px 0; }}
            .section h2 {{ color: #333; border-bottom: 2px solid #667eea; padding-bottom: 10px; }}
            
            .metrics-grid {{ 
                display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); 
                gap: 15px; margin: 20px 0; 
            }}
            .metric-card {{ 
                background: white; padding: 20px; border-radius: 10px; 
                box-shadow: 0 2px 10px rgba(0,0,0,0.05); border-left: 4px solid #667eea;
            }}
            .metric-value {{ font-size: 24px; font-weight: bold; color: #667eea; }}
            .metric-label {{ color: #666; font-size: 14px; margin-top: 5px; }}
            
            .config-table {{ 
                background: white; border-radius: 10px; overflow: hidden; 
                box-shadow: 0 2px 10px rgba(0,0,0,0.05); 
            }}
            .config-table table {{ border-collapse: collapse; width: 100%; margin: 0; }}
            .config-table th {{ background: #667eea; color: white; padding: 12px; }}
            .config-table td {{ padding: 12px; border-bottom: 1px solid #eee; }}
            .config-table tr:last-child td {{ border-bottom: none; }}
            
            .plot {{ text-align: center; margin: 30px 0; }}
            .plot img {{ max-width: 100%; border-radius: 10px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }}
            
            .events-table {{ 
                background: white; border-radius: 10px; overflow: hidden; 
                box-shadow: 0 2px 10px rgba(0,0,0,0.05); 
            }}
            .events-table table {{ width: 100%; }}
            .events-table th {{ background: #28a745; color: white; padding: 12px; }}
            .events-table td {{ padding: 10px; border-bottom: 1px solid #eee; text-align: center; }}
            .events-table tr:nth-child(even) {{ background: #f8f9fa; }}
        </style>
    </head>
    <body>
        <div class="header">
            <h1>TKEO Pinch Detection Analysis</h1>
            <div class="info-grid">
                <div class="info-item">
                    <strong>Session</strong>
                    {session_info['filename']}
                </div>
                <div class="info-item">
                    <strong>Duration</strong>
                    {session_info['duration']:.1f} seconds
                </div>
                <div class="info-item">
                    <strong>Analysis Time</strong>
                    {datetime.now().strftime('%H:%M:%S')}
                </div>
                <div class="info-item">
                    <strong>Filter Range</strong>
                    {detector.config['bandpass_low']}-{detector.config['bandpass_high']} Hz
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>Detection Results</h2>
            <div class="metrics-grid">
                <div class="metric-card">
                    <div class="metric-value">{len(debug_data['final_detections'])}</div>
                    <div class="metric-label">Final Detections</div>
                </div>
                <div class="metric-card">
                    <div class="metric-value">{len(debug_data['gate_events'])}</div>
                    <div class="metric-label">Gate Events</div>
                </div>
                <div class="metric-card">
                    <div class="metric-value">{((len(debug_data['gate_events']) - len(debug_data['final_detections'])) / max(1, len(debug_data['gate_events'])) * 100):.1f}%</div>
                    <div class="metric-label">Rejection Rate</div>
                </div>
                <div class="metric-card">
                    <div class="metric-value">{len(debug_data['final_detections']) / (session_info['duration'] / 60.0):.1f}</div>
                    <div class="metric-label">Events/Minute</div>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>Algorithm Configuration</h2>
            <div class="config-table">
                <table>
                    <tr><th>Parameter</th><th>Value</th></tr>
                    <tr><td>Template NCC Threshold</td><td>{detector.template_verifier.confidence_threshold}</td></tr>
                    <tr><td>Gate Thresholds</td><td>Accel: {detector.config['gate_k_accel']}σ, Gyro: {detector.config['gate_k_gyro']}σ</td></tr>
                    <tr><td>Fusion Weights</td><td>Accel: {detector.config['fusion_weight_accel']}, Gyro: {detector.config['fusion_weight_gyro']}</td></tr>
                    <tr><td>Refractory Period</td><td>{detector.config['refractory_period_s'] * 1000:.0f} ms</td></tr>
                </table>
            </div>
        </div>
        
        <div class="section">
            <h2>Detailed Analysis Plots</h2>
            <div class="plot">
                <img src="tkeo_detection_analysis.png" alt="TKEO Detection Analysis" style="width: 100%; height: auto;">
            </div>
        </div>
        
        <div class="section">
            <h2>Detected Events</h2>
            <div class="events-table">
                <table>
                    <tr><th>Event #</th><th>Time (s)</th><th>Confidence</th><th>Fusion Score</th></tr>
    """
    
    for i, event in enumerate(debug_data['final_detections']):
        html_content += f"""
                    <tr>
                        <td>{i+1}</td>
                        <td>{event['time']:.2f}</td>
                        <td>{event['confidence']:.3f}</td>
                        <td>{event['fusion_score']:.4f}</td>
                    </tr>
        """
    
    html_content += """
                </table>
            </div>
        </div>
        
        <div class="section">
            <h2>Algorithm Notes</h2>
            <p><strong>Two-Stage Detection:</strong></p>
            <ul>
                <li><strong>Stage 1 (Gate):</strong> Liberal TKEO-based burst detection with adaptive thresholds</li>
                <li><strong>Stage 2 (Verify):</strong> Template matching via normalized cross-correlation</li>
            </ul>
            <p><strong>Signal Processing Pipeline:</strong></p>
            <ol>
                <li>Band-pass filtering (3-20 Hz) - captures transient energy</li>
                <li>Jerk computation - emphasizes rapid changes</li>
                <li>TKEO operator - detects instantaneous energy bursts</li>
                <li>Adaptive baseline tracking - handles varying noise levels</li>
                <li>Template verification - reduces false positives</li>
            </ol>
        </div>
    </body>
    </html>
    """
    
    html_path = os.path.join(output_dir, 'tkeo_detection_report.html')
    with open(html_path, 'w') as f:
        f.write(html_content)
    
    print(f"✓ Generated HTML report: {html_path}")
    print(f"  - {len(debug_data['final_detections'])} final detections")
    print(f"  - {len(debug_data['gate_events'])} gate events")
    print(f"  - Plot file: {plot_path}")
    
    # Verify both files exist
    if not os.path.exists(plot_path):
        print(f"⚠️  Warning: Plot file not found at {plot_path}")
    if not os.path.exists(html_path):
        print(f"⚠️  Warning: HTML file not found at {html_path}")
    
    return html_path

def main():
    parser = argparse.ArgumentParser(description='Advanced TKEO-based Pinch Detection')
    parser.add_argument('--input', required=False, help='Path to session CSV file')
    parser.add_argument('--output', default=None, help='Output directory')
    parser.add_argument('--config', default=None, help='Configuration YAML file')
    parser.add_argument('--analysis-results', default=None, help='Path to analyze_session.py results directory for template training')
    parser.add_argument('--trained-templates', default=None, help='Path to trained_templates.json file from previous session (production mode)')
    parser.add_argument('--save-templates', action='store_true', help='Save trained templates for reuse in future sessions')
    parser.add_argument('--streaming-results', default=None, help='[DEPRECATED] Use --analysis-results instead. Path to streaming algorithm results directory')
    parser.add_argument('--clean', action='store_true', help='Delete all tkeo_analysis_session_* directories and exit')
    parser.add_argument('--time-range', nargs=2, type=float, metavar=('START', 'END'), help='Plot time range in seconds (e.g., --time-range 0 10)')
    parser.add_argument('--y-range', nargs=2, type=float, metavar=('MIN', 'MAX'), help='Y-axis range for plots (e.g., --y-range 0 2.0)')
    
    args = parser.parse_args()
    
    # Handle clean option
    if args.clean:
        import glob
        import shutil
        
        patterns = ['tkeo_analysis_session_*', 'tkeo_analysis_*']
        deleted_count = 0
        
        for pattern in patterns:
            dirs_to_delete = glob.glob(pattern)
            for dir_path in dirs_to_delete:
                if os.path.isdir(dir_path):
                    print(f"Deleting: {dir_path}")
                    shutil.rmtree(dir_path)
                    deleted_count += 1
        
        print(f"✓ Clean complete: {deleted_count} directories deleted")
        
        # If clean only (no input specified), exit after clean
        if not args.input:
            return
    
    # Validate required arguments for normal operation
    if not args.input:
        parser.error("--input is required unless using --cleanup")
    
    # Setup output directory
    if args.output is None:
        input_path = Path(args.input)
        session_name = input_path.stem
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_dir = f"tkeo_analysis_{session_name}_{timestamp}"
    else:
        output_dir = args.output
    
    os.makedirs(output_dir, exist_ok=True)
    print(f"Output directory: {output_dir}")
    
    # Load configuration
    config = None
    if args.config and os.path.exists(args.config):
        with open(args.config, 'r') as f:
            config_data = yaml.safe_load(f)
            config = config_data.get('tkeo_params', {})
    
    # Load session data
    timestamps, accel_data, gyro_data = load_session_data(args.input)
    
    session_info = {
        'filename': os.path.basename(args.input),
        'duration': timestamps[-1],
        'samples': len(timestamps),
        'fs': len(timestamps) / timestamps[-1]
    }
    
    # Initialize detector
    detector = AdvancedPinchDetector(config)
    
    # Create templates using best available method
    # Priority: trained templates > analyze_session results > streaming results (backward compatibility)
    trained_templates = args.trained_templates if hasattr(args, 'trained_templates') else None
    analysis_dir = args.analysis_results if hasattr(args, 'analysis_results') else None
    if analysis_dir is None and hasattr(args, 'streaming_results') and args.streaming_results:
        print("Warning: --streaming-results is deprecated. Consider using analyze_session.py results with --analysis-results")
        analysis_dir = args.streaming_results  # Backward compatibility
    
    template_indices = create_templates_for_detector(timestamps, accel_data, gyro_data, detector, analysis_dir, trained_templates)
    
    # Process session
    print(f"\nProcessing session with TKEO detector...")
    detected_events = detector.process_session(accel_data, gyro_data, timestamps)
    
    print(f"\n=== DETECTION RESULTS ===")
    print(f"Total events detected: {len(detected_events)}")
    print(f"Session duration: {timestamps[-1]:.1f} seconds")
    print(f"Event rate: {len(detected_events) / (timestamps[-1] / 60.0):.1f} events/minute")
    
    if len(detected_events) > 0:
        confidences = [e['confidence'] for e in detected_events]
        print(f"Average confidence: {np.mean(confidences):.3f}")
        print(f"Confidence range: {np.min(confidences):.3f} - {np.max(confidences):.3f}")
    
    # Save trained templates if requested
    if hasattr(args, 'save_templates') and args.save_templates:
        print(f"\nSaving trained templates for reuse...")
        save_templates_for_reuse(detector, output_dir, session_info)
    
    # Generate HTML report
    print(f"\nGenerating HTML report...")
    html_path = generate_html_report(detector, session_info, output_dir, 
                                     time_range=args.time_range, y_range=args.y_range)
    
    # Save detailed results
    results = {
        'session_info': session_info,
        'config': detector.config,
        'template_count': len(detector.template_verifier.templates),
        'detected_events': detected_events,
        'gate_triggers': int(np.sum(detector.debug_data['gate_triggers'])),
        'verification_rate': len(detected_events) / max(1, np.sum(detector.debug_data['gate_triggers']))
    }
    
    with open(os.path.join(output_dir, 'results.json'), 'w') as f:
        json.dump(results, f, indent=2, default=str)
    
    print(f"\n=== ANALYSIS COMPLETE ===")
    print(f"HTML Report: {html_path}")
    print(f"Results saved in: {output_dir}")
    
    return detected_events

if __name__ == '__main__':
    main()