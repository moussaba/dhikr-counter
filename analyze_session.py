#!/usr/bin/env python3
"""
Stationary Pinch Detection Analysis Tool

A command-line tool that implements the stationary pinch detection algorithm
from advanced_pinch_detector.ipynb for offline analysis of session data.

Usage:
    python analyze_session.py --input session_data.csv --config config.yaml --output results/
    python analyze_session.py --input session_data.json --config config.yaml --output results/

Debug modes (consolidates debug_detection.py, threshold_debug.py, visual_debug.py):
    python analyze_session.py --input session.csv --debug-detection    # Rejection analysis
    python analyze_session.py --input session.csv --debug-threshold    # Missed peaks analysis  
    python analyze_session.py --input session.csv --debug-visual       # Visual debug plots
    python analyze_session.py --input session.csv --debug-all          # All debug modes

Supports both CSV and JSON session files exported from DhikrCounter Watch App.
"""

import argparse
import json
import os
import sys
import time
import warnings
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Tuple, List, Optional

import numpy as np
import pandas as pd
import yaml
from scipy import signal as sp_signal

from html_report import HTMLReportGenerator

# Suppress warnings for cleaner output
warnings.filterwarnings('ignore')

# Debug classes
class DebugDetector:
    """Debug version of stationary detector with detailed rejection analysis."""
    
    def __init__(self, config):
        self.params = config.get('stationary_params', {})
        self.debug_stats = {}
    
    def debug_detect(self, data):
        """Run detection with detailed debugging information."""
        
        print(f"\n🔍 DEBUG DETECTION ANALYSIS")
        print(f"=" * 50)
        
        t, fs = data['time'], data['fs']
        a, g = data['acc_mag'], data['gyro_mag']
        n = len(t)
        
        print(f"📊 Input Data:")
        print(f"  Duration: {t[-1] - t[0]:.2f}s")
        print(f"  Samples: {n}")
        print(f"  Sample rate: {fs:.1f} Hz")
        print(f"  Acceleration range: {a.min():.3f} to {a.max():.3f} g")
        print(f"  Gyroscope range: {g.min():.3f} to {g.max():.3f} rad/s")
        
        # Signal processing
        print(f"\n🔧 Signal Processing:")
        a_hp = SignalProcessor.hp_moving_mean(a, fs, self.params.get('hp_win', 0.5))
        da = np.gradient(a_hp, 1.0/fs)
        dg = np.gradient(g, 1.0/fs)
        
        print(f"  High-pass acceleration range: {a_hp.min():.3f} to {a_hp.max():.3f} g")
        print(f"  Acceleration derivative range: {da.min():.3f} to {da.max():.3f} g/s")
        print(f"  Gyroscope derivative range: {dg.min():.3f} to {dg.max():.3f} rad/s²")
        
        # Z-scores
        print(f"\n📈 Z-score Analysis:")
        thr_win = self.params.get('thr_win', 3.0)
        z_a = SignalProcessor.robust_z(a_hp, fs, thr_win)
        z_g = SignalProcessor.robust_z(g, fs, thr_win)
        z_da = SignalProcessor.robust_z(np.abs(da), fs, thr_win)
        z_dg = SignalProcessor.robust_z(np.abs(dg), fs, thr_win)
        
        print(f"  Z-score acceleration: {z_a.min():.2f} to {z_a.max():.2f}")
        print(f"  Z-score gyroscope: {z_g.min():.2f} to {z_g.max():.2f}")
        print(f"  Z-score acc derivative: {z_da.min():.2f} to {z_da.max():.2f}")
        print(f"  Z-score gyro derivative: {z_dg.min():.2f} to {z_dg.max():.2f}")
        
        # Fusion score
        score = np.sqrt(
            np.maximum(z_a, 0)**2 + 
            np.maximum(z_g, 0)**2 + 
            np.maximum(z_da, 0)**2 + 
            np.maximum(z_dg, 0)**2
        )
        
        print(f"  Fusion score range: {score.min():.2f} to {score.max():.2f}")
        
        # Adaptive threshold
        k_mad = self.params.get('k_mad', 5.5)
        threshold = SignalProcessor.adaptive_threshold(score, fs, thr_win, k_mad)
        
        print(f"  Adaptive threshold range: {threshold.min():.2f} to {threshold.max():.2f}")
        print(f"  k_mad parameter: {k_mad}")
        
        # Find all candidates above threshold
        candidates = np.where(score > threshold)[0]
        print(f"\n🎯 Threshold Analysis:")
        print(f"  Candidates above threshold: {len(candidates)}")
        
        if len(candidates) == 0:
            print(f"  ❌ NO CANDIDATES - threshold too high!")
            print(f"  💡 Solution: Reduce k_mad from {k_mad} to {k_mad * 0.7:.1f}")
            return {'candidates': 0, 'final_events': 0, 'rejection_stats': {}}
        
        # Show score distribution of candidates
        candidate_scores = score[candidates]
        print(f"  Candidate scores: {candidate_scores.min():.2f} to {candidate_scores.max():.2f}")
        print(f"  Median candidate score: {np.median(candidate_scores):.2f}")
        
        # Analyze rejection stages
        print(f"\n🚫 Rejection Analysis:")
        
        # Apply gates and filters
        acc_gate = self.params.get('acc_gate', 0.025)
        gyro_gate = self.params.get('gyro_gate', 0.10)
        refractory_s = self.params.get('refractory_s', 0.12)
        min_iei_s = self.params.get('min_iei_s', 0.10)
        
        rejected_acc_gates = 0
        rejected_gyro_gates = 0
        rejected_refractory = 0
        rejected_not_peak = 0
        rejected_min_iei = 0
        final_events = []
        
        # Simple peak detection and filtering simulation
        from scipy.signal import find_peaks
        peaks, _ = find_peaks(score, height=threshold.min())
        peaks = np.intersect1d(peaks, candidates)  # Only peaks above threshold
        
        print(f"  Initial peaks above threshold: {len(peaks)}")
        
        # Gate filtering
        for peak in peaks:
            a_peak = a[peak]
            g_peak = g[peak]
            
            # Separate gating checks
            acc_gate_pass = a_peak >= acc_gate
            gyro_gate_pass = g_peak >= gyro_gate
            
            if not acc_gate_pass:
                rejected_acc_gates += 1
            if not gyro_gate_pass:
                rejected_gyro_gates += 1
                
            # Reject if either gate fails
            if not (acc_gate_pass and gyro_gate_pass):
                continue
                
            # Simple refractory check
            if final_events:
                time_since_last = t[peak] - final_events[-1]['time']
                if time_since_last < refractory_s:
                    rejected_refractory += 1
                    continue
                if time_since_last < min_iei_s:
                    rejected_min_iei += 1
                    continue
            
            final_events.append({
                'time': t[peak],
                'index': peak,
                'score': score[peak],
                'acc_peak': a_peak,
                'gyro_peak': g_peak
            })
        
        print(f"  Rejected by accelerometer gate: {rejected_acc_gates}")
        print(f"  Rejected by gyroscope gate: {rejected_gyro_gates}")
        print(f"  Rejected by refractory period: {rejected_refractory}")
        print(f"  Rejected by min inter-event interval: {rejected_min_iei}")
        print(f"  Final detected events: {len(final_events)}")
        
        # Summary statistics
        total_gate_rejected = rejected_acc_gates + rejected_gyro_gates
        total_rejected = total_gate_rejected + rejected_refractory + rejected_min_iei
        if len(peaks) > 0:
            print(f"\n📊 Rejection Statistics:")
            print(f"  Accelerometer gate: {rejected_acc_gates}/{len(peaks)} ({100*rejected_acc_gates/len(peaks):.1f}%)")
            print(f"  Gyroscope gate: {rejected_gyro_gates}/{len(peaks)} ({100*rejected_gyro_gates/len(peaks):.1f}%)")
            print(f"  Refractory: {rejected_refractory}/{len(peaks)} ({100*rejected_refractory/len(peaks):.1f}%)")
            print(f"  Min IEI: {rejected_min_iei}/{len(peaks)} ({100*rejected_min_iei/len(peaks):.1f}%)")
            print(f"  Success rate: {len(final_events)}/{len(peaks)} ({100*len(final_events)/len(peaks):.1f}%)")
        
        return {
            'candidates': len(candidates),
            'peaks': len(peaks),
            'final_events': len(final_events),
            'rejection_stats': {
                'rejected_acc_gates': rejected_acc_gates,
                'rejected_gyro_gates': rejected_gyro_gates,
                'rejected_refractory': rejected_refractory,
                'rejected_min_iei': rejected_min_iei,
                'total_rejected': total_rejected
            }
        }


class ThresholdDebugger:
    """Analyzes why certain peaks don't cross the adaptive threshold."""
    
    def __init__(self, config):
        self.params = config.get('stationary_params', {})
    
    def analyze_missed_peaks(self, data):
        """Analyze peaks that don't cross the adaptive threshold."""
        
        print(f"\n🔍 THRESHOLD DEBUG ANALYSIS")
        print(f"=" * 60)
        
        t, fs = data['time'], data['fs']
        a, g = data['acc_mag'], data['gyro_mag']
        
        # Signal processing (same as detector)
        a_hp = SignalProcessor.hp_moving_mean(a, fs, self.params.get('hp_win', 0.5))
        da = np.gradient(a_hp, 1.0/fs)
        dg = np.gradient(g, 1.0/fs)
        
        # Z-scores
        thr_win = self.params.get('thr_win', 3.0)
        z_a = SignalProcessor.robust_z(a_hp, fs, thr_win)
        z_g = SignalProcessor.robust_z(g, fs, thr_win)
        z_da = SignalProcessor.robust_z(np.abs(da), fs, thr_win)
        z_dg = SignalProcessor.robust_z(np.abs(dg), fs, thr_win)
        
        # Fusion score
        score = np.sqrt(
            np.maximum(z_a, 0)**2 + 
            np.maximum(z_g, 0)**2 + 
            np.maximum(z_da, 0)**2 + 
            np.maximum(z_dg, 0)**2
        )
        
        # Adaptive threshold
        k_mad = self.params.get('k_mad', 5.5)
        threshold = SignalProcessor.adaptive_threshold(score, fs, thr_win, k_mad)
        
        print(f"📊 Score and Threshold Statistics:")
        print(f"   Fusion score range: {score.min():.2f} to {score.max():.2f}")
        print(f"   Threshold range: {threshold.min():.2f} to {threshold.max():.2f}")
        print(f"   k_mad parameter: {k_mad}")
        
        # Find local peaks in fusion score (regardless of threshold)
        from scipy.signal import find_peaks
        
        # Find all local maxima with minimum height and distance
        min_height = np.percentile(score, 75)  # Top 25% of scores
        min_distance = int(0.05 * fs)  # At least 50ms apart
        
        all_peaks, peak_properties = find_peaks(
            score, 
            height=min_height,
            distance=min_distance,
            prominence=1.0  # Must be reasonably prominent
        )
        
        print(f"\n🏔️  Local Peak Analysis:")
        print(f"   Found {len(all_peaks)} local peaks with score > {min_height:.2f}")
        
        # Categorize peaks
        above_threshold = []
        below_threshold = []
        
        for peak_idx in all_peaks:
            peak_score = score[peak_idx]
            peak_threshold = threshold[peak_idx]
            peak_time = t[peak_idx]
            
            peak_info = {
                'index': peak_idx,
                'time': peak_time,
                'score': peak_score,
                'threshold': peak_threshold,
                'margin': peak_score - peak_threshold
            }
            
            if peak_score > peak_threshold:
                above_threshold.append(peak_info)
            else:
                below_threshold.append(peak_info)
        
        print(f"   Peaks above threshold: {len(above_threshold)}")
        print(f"   Peaks below threshold: {len(below_threshold)} ⚠️")
        
        # Analyze missed peaks (below threshold)
        if below_threshold:
            print(f"\n🎯 MISSED PEAKS ANALYSIS:")
            print(f"   These peaks are ignored because score < threshold:")
            print(f"   {'Time':<8} {'Score':<6} {'Thresh':<6} {'Margin':<7} {'% Below'}")
            print(f"   {'-'*8} {'-'*6} {'-'*6} {'-'*7} {'-'*7}")
            
            # Sort by how close they are to threshold (most promising first)
            below_threshold.sort(key=lambda x: x['margin'], reverse=True)
            
            for peak in below_threshold[:15]:  # Show top 15 missed peaks
                percent_below = abs(peak['margin'] / peak['threshold'] * 100)
                print(f"   {peak['time']:<8.2f} {peak['score']:<6.2f} {peak['threshold']:<6.2f} "
                      f"{peak['margin']:<7.2f} {percent_below:<6.1f}%")
            
            # Find the threshold statistics around missed peaks
            missed_margins = [p['margin'] for p in below_threshold]
            print(f"\n📈 Missed Peak Statistics:")
            print(f"   Closest to threshold: {max(missed_margins):.2f} below")
            print(f"   Average margin: {np.mean(missed_margins):.2f} below")
            print(f"   Median margin: {np.median(missed_margins):.2f} below")
            
            # Calculate what k_mad would catch the closest missed peaks
            best_missed_peaks = below_threshold[:5]  # Top 5 closest
            if best_missed_peaks:
                # Find what k_mad would be needed
                needed_reductions = []
                for peak in best_missed_peaks:
                    # Calculate local MAD statistics to see what k_mad would work
                    w = max(3, int(round(thr_win * fs)))
                    window_start = max(0, peak['index'] - w//2)
                    window_end = min(len(score), peak['index'] + w//2)
                    local_scores = score[window_start:window_end]
                    
                    if len(local_scores) > 3:
                        local_median = np.median(local_scores)
                        local_mad = np.median(np.abs(local_scores - local_median))
                        
                        if local_mad > 1e-9:
                            # What k_mad would make threshold = peak score?
                            needed_k_mad = (peak['score'] - local_median) / (1.4826 * local_mad)
                            current_k_mad = (peak['threshold'] - local_median) / (1.4826 * local_mad)
                            
                            reduction_factor = needed_k_mad / current_k_mad
                            needed_reductions.append(reduction_factor)
                
                if needed_reductions:
                    avg_reduction = np.mean(needed_reductions)
                    recommended_k_mad = k_mad * avg_reduction
                    
                    print(f"\n💡 RECOMMENDATIONS:")
                    print(f"   Current k_mad: {k_mad}")
                    print(f"   To catch closest missed peaks:")
                    print(f"   → Reduce k_mad to: {recommended_k_mad:.2f}")
                    print(f"   → Reduction factor: {avg_reduction:.2f}x")
                    
                    if recommended_k_mad < 1.5:
                        print(f"   ⚠️  Warning: k_mad < 1.5 may cause many false positives")
                    elif recommended_k_mad < 2.0:
                        print(f"   ⚠️  Caution: k_mad < 2.0 may increase noise detection")
        
        else:
            print(f"\n✅ All significant local peaks are above threshold!")
            print(f"   The algorithm is capturing all prominent spikes.")
        
        return {
            'all_peaks': len(all_peaks),
            'above_threshold': len(above_threshold),
            'below_threshold': len(below_threshold),
            'missed_peaks': below_threshold[:5] if below_threshold else []
        }

class SessionDataLoader:
    """Handles loading and preprocessing of session data from CSV/JSON files."""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.input_config = config.get('input', {})
        
    def load_data(self, filepath: str) -> Dict[str, Any]:
        """
        Load session data from CSV or JSON file.
        
        Args:
            filepath: Path to session data file
            
        Returns:
            Dictionary containing processed session data
        """
        filepath = Path(filepath)
        
        if not filepath.exists():
            raise FileNotFoundError(f"Session file not found: {filepath}")
        
        # Auto-detect format or use file extension
        if self.input_config.get('auto_detect_format', True):
            if filepath.suffix.lower() == '.json':
                return self._load_json(filepath)
            elif filepath.suffix.lower() == '.csv':
                return self._load_csv(filepath)
            else:
                raise ValueError(f"Unsupported file format: {filepath.suffix}")
        
        # If auto-detection is disabled, try both formats
        try:
            if filepath.suffix.lower() == '.json':
                return self._load_json(filepath)
            else:
                return self._load_csv(filepath)
        except Exception as e:
            raise ValueError(f"Failed to load data from {filepath}: {e}")
    
    def _load_json(self, filepath: Path) -> Dict[str, Any]:
        """Load data from JSON session file."""
        print(f"Loading JSON session file: {filepath.name}")
        
        with open(filepath, 'r') as f:
            data = json.load(f)
        
        # Extract metadata
        metadata = data.get('metadata', {})
        sensor_data = data.get('sensorData', [])
        
        if not sensor_data:
            raise ValueError("No sensor data found in JSON file")
        
        # Convert to DataFrame for processing
        rows = []
        for reading in sensor_data:
            row = {
                'time_s': reading.get('time_s', 0),
                'epoch_s': reading.get('epoch_s', 0),
                'userAccelerationX': reading.get('userAcceleration', {}).get('x', 0),
                'userAccelerationY': reading.get('userAcceleration', {}).get('y', 0), 
                'userAccelerationZ': reading.get('userAcceleration', {}).get('z', 0),
                'rotationRateX': reading.get('rotationRate', {}).get('x', 0),
                'rotationRateY': reading.get('rotationRate', {}).get('y', 0),
                'rotationRateZ': reading.get('rotationRate', {}).get('z', 0),
                'gravityX': reading.get('gravity', {}).get('x', 0),
                'gravityY': reading.get('gravity', {}).get('y', 0),
                'gravityZ': reading.get('gravity', {}).get('z', 0),
            }
            rows.append(row)
        
        df = pd.DataFrame(rows)
        
        # Process the data
        return self._process_dataframe(df, metadata, filepath)
    
    def _load_csv(self, filepath: Path) -> Dict[str, Any]:
        """Load data from CSV session file."""
        print(f"Loading CSV session file: {filepath.name}")
        
        # Read CSV, skipping comment lines
        df = pd.read_csv(filepath, comment='#')
        
        # Extract metadata from comments
        metadata = self._extract_csv_metadata(filepath)
        
        return self._process_dataframe(df, metadata, filepath)
    
    def _extract_csv_metadata(self, filepath: Path) -> Dict[str, Any]:
        """Extract metadata from CSV comment lines."""
        metadata = {}
        
        with open(filepath, 'r') as f:
            for line in f:
                if line.startswith('#'):
                    if 'Session ID:' in line:
                        metadata['sessionId'] = line.split('Session ID:')[1].strip()
                    elif 'Duration:' in line:
                        duration_str = line.split('Duration:')[1].strip().replace('s', '')
                        try:
                            metadata['duration'] = float(duration_str)
                        except ValueError:
                            pass
                    elif 'Total Readings:' in line:
                        try:
                            metadata['totalReadings'] = int(line.split('Total Readings:')[1].strip())
                        except ValueError:
                            pass
                    elif 'update_interval_s=' in line:
                        try:
                            metadata['update_interval_s'] = float(line.split('update_interval_s=')[1].strip())
                        except ValueError:
                            pass
                else:
                    break  # Stop at first data line
        
        return metadata
    
    def _process_dataframe(self, df: pd.DataFrame, metadata: Dict[str, Any], filepath: Path) -> Dict[str, Any]:
        """Process DataFrame into analysis-ready format."""
        
        # Validate required columns
        csv_cols = self.input_config.get('csv_columns', {})
        required_cols = [
            csv_cols.get('time', 'time_s'),
            csv_cols.get('acceleration_x', 'userAccelerationX'),
            csv_cols.get('acceleration_y', 'userAccelerationY'),
            csv_cols.get('acceleration_z', 'userAccelerationZ'),
            csv_cols.get('rotation_x', 'rotationRateX'),
            csv_cols.get('rotation_y', 'rotationRateY'),
            csv_cols.get('rotation_z', 'rotationRateZ'),
        ]
        
        missing_cols = [col for col in required_cols if col not in df.columns]
        if missing_cols:
            raise ValueError(f"Missing required columns: {missing_cols}")
        
        # Extract time series
        time_col = csv_cols.get('time', 'time_s')
        t = df[time_col].values
        
        # Handle time normalization
        if t[0] > 1000:  # Likely absolute time, normalize to start at 0
            t = t - t[0]
        
        # Calculate sampling rate
        dt = np.median(np.diff(t))
        fs = 1.0 / dt if dt > 0 else 100.0
        
        # Validate sampling rate
        expected_fs = self.input_config.get('expected_fs', 100.0)
        if abs(fs - expected_fs) > 10:  # Allow 10Hz tolerance
            print(f"Warning: Sampling rate {fs:.1f}Hz differs from expected {expected_fs:.1f}Hz")
        
        # Extract acceleration and gyroscope data
        acc_x = df[csv_cols.get('acceleration_x', 'userAccelerationX')].values
        acc_y = df[csv_cols.get('acceleration_y', 'userAccelerationY')].values
        acc_z = df[csv_cols.get('acceleration_z', 'userAccelerationZ')].values
        
        gyro_x = df[csv_cols.get('rotation_x', 'rotationRateX')].values
        gyro_y = df[csv_cols.get('rotation_y', 'rotationRateY')].values
        gyro_z = df[csv_cols.get('rotation_z', 'rotationRateZ')].values
        
        # Compute magnitudes
        acc_mag = np.sqrt(acc_x**2 + acc_y**2 + acc_z**2)
        gyro_mag = np.sqrt(gyro_x**2 + gyro_y**2 + gyro_z**2)
        
        # Data validation
        duration = t[-1] - t[0]
        min_duration = self.config.get('analysis', {}).get('min_duration_s', 1.0)
        
        if duration < min_duration:
            raise ValueError(f"Session too short: {duration:.2f}s < {min_duration}s")
        
        # Check for gaps
        max_gap = self.config.get('analysis', {}).get('max_gap_s', 0.1)
        time_gaps = np.diff(t)
        large_gaps = time_gaps > max_gap
        
        if np.any(large_gaps):
            gap_count = np.sum(large_gaps)
            max_gap_found = np.max(time_gaps)
            print(f"Warning: Found {gap_count} time gaps > {max_gap}s (max: {max_gap_found:.3f}s)")
        
        print(f"✓ Loaded {len(t)} samples")
        print(f"  Duration: {duration:.2f} seconds")
        print(f"  Sampling rate: {fs:.1f} Hz")
        print(f"  Acceleration range: {acc_mag.min():.3f} to {acc_mag.max():.3f} g")
        print(f"  Gyroscope range: {gyro_mag.min():.3f} to {gyro_mag.max():.3f} rad/s")
        
        return {
            'time': t,
            'fs': fs,
            'acc_mag': acc_mag,
            'gyro_mag': gyro_mag,
            'acc_xyz': np.column_stack([acc_x, acc_y, acc_z]),
            'gyro_xyz': np.column_stack([gyro_x, gyro_y, gyro_z]),
            'df': df,
            'metadata': metadata,
            'filepath': str(filepath)
        }


class SignalProcessor:
    """Signal processing functions for pinch detection."""
    
    @staticmethod
    def hp_moving_mean(x, fs, win=0.5):
        """High-pass filter using moving mean subtraction."""
        w = max(1, int(round(win * fs)))
        return x - pd.Series(x).rolling(w, 1, center=True).mean().values
    
    @staticmethod
    def robust_z(x, fs, win=3.0):
        """Robust z-score using MAD (Median Absolute Deviation)."""
        w = max(3, int(round(win * fs)))
        s = pd.Series(x)
        
        # Rolling median and MAD
        med = s.rolling(w, max(1, w//4), center=True).median()
        mad = s.rolling(w, max(1, w//4), center=True).apply(
            lambda v: np.median(np.abs(v - np.median(v))), raw=False
        )
        
        # Handle zero MAD
        mad = mad.replace(0, np.nan).fillna(
            mad.median() if np.isfinite(mad.median()) else 1.0
        )
        
        # Robust z-score
        return ((s - med) / (1.4826 * mad + 1e-9)).values
    
    @staticmethod
    def adaptive_threshold(score, fs, win=3.0, k_mad=5.5):
        """Compute adaptive threshold using MAD."""
        w = max(3, int(round(win * fs)))
        return pd.Series(score).rolling(w, max(1, int(round(0.75*fs))), center=True).apply(
            lambda v: np.median(v) + k_mad * (1.4826 * np.median(np.abs(v - np.median(v))) + 1e-9),
            raw=False
        ).values


class StationaryDetector:
    """Stationary pinch detection using 4-component z-score fusion."""
    
    def __init__(self, config: Dict[str, Any]):
        self.params = config.get('stationary_params', {})
        
    def detect(self, data: Dict[str, Any], collect_rejections: bool = False) -> Dict[str, Any]:
        """
        Detect pinch events in stationary data.
        
        Args:
            data: Processed session data
            collect_rejections: If True, collect rejected candidates for visual debug
            
        Returns:
            Detection results with events and analysis data
        """
        print(f"Running stationary pinch detection...")
        
        t, fs = data['time'], data['fs']
        a, g = data['acc_mag'], data['gyro_mag']
        
        # High-pass filter and derivatives
        a_hp = SignalProcessor.hp_moving_mean(a, fs, self.params.get('hp_win', 0.5))
        da = np.gradient(a_hp, 1.0/fs)
        dg = np.gradient(g, 1.0/fs)
        
        # Robust z-scores for all components
        thr_win = self.params.get('thr_win', 3.0)
        z_a = SignalProcessor.robust_z(a_hp, fs, thr_win)
        z_g = SignalProcessor.robust_z(g, fs, thr_win)
        z_da = SignalProcessor.robust_z(np.abs(da), fs, thr_win)
        z_dg = SignalProcessor.robust_z(np.abs(dg), fs, thr_win)
        
        # Fusion score (4-component)
        score = np.sqrt(
            np.maximum(z_a, 0)**2 + 
            np.maximum(z_g, 0)**2 + 
            np.maximum(z_da, 0)**2 + 
            np.maximum(z_dg, 0)**2
        )
        
        # Adaptive threshold
        k_mad = self.params.get('k_mad', 5.5)
        threshold = SignalProcessor.adaptive_threshold(score, fs, thr_win, k_mad)
        
        # Event detection with validation
        if collect_rejections:
            events, rejected_candidates = self._detect_events_with_rejections(data, score, threshold, a_hp)
        else:
            events = self._detect_events(data, score, threshold, a_hp)
            rejected_candidates = None
        
        print(f"✓ Detected {len(events)} pinch events")
        
        result = {
            'detector_type': 'stationary',
            'events': events,
            'score': score,
            'threshold': threshold,
            'components': {'z_a': z_a, 'z_g': z_g, 'z_da': z_da, 'z_dg': z_dg},
            'a_hp': a_hp,
            'params': self.params,
            'data': data
        }
        
        if rejected_candidates is not None:
            result['rejected_candidates'] = rejected_candidates
            
        return result
    
    def _detect_events(self, data: Dict[str, Any], score: np.ndarray, 
                      threshold: np.ndarray, a_hp: np.ndarray) -> List[Dict[str, Any]]:
        """Detect and validate pinch events."""
        
        t, fs = data['time'], data['fs']
        g = data['gyro_mag']
        n = len(score)
        
        # Parameters
        refr = int(round(self.params.get('refractory_s', 0.12) * fs))
        pw = int(round(self.params.get('peakwin_s', 0.04) * fs))
        gate = int(round(self.params.get('gatewin_s', 0.18) * fs))
        min_iei = int(round(self.params.get('min_iei_s', 0.10) * fs))
        acc_gate = self.params.get('acc_gate', 0.025)
        gyro_gate = self.params.get('gyro_gate', 0.10)
        
        events = []
        last = -10**9
        
        for i in np.where(score > threshold)[0]:
            # Refractory period check
            if i - last < refr:
                continue
                
            # Local maxima check
            i0 = max(0, i - pw)
            i1 = min(n, i + pw + 1)
            if i != i0 + np.argmax(score[i0:i1]):
                continue
                
            # Gate checks
            g0 = max(0, i - gate)
            g1 = min(n, i + gate + 1)
            # Separate gate checks for debugging
            acc_gate_max = np.nanmax(a_hp[g0:g1])
            gyro_gate_max = np.nanmax(g[g0:g1])
            
            if acc_gate_max < acc_gate or gyro_gate_max < gyro_gate:
                continue
                
            # Minimum inter-event interval
            if len(events) > 0 and (i - events[-1]['index']) < min_iei:
                continue
                
            events.append({
                'index': i,
                'time': float(t[i]),
                'score': float(score[i]),
                'threshold': float(threshold[i]),
                'acc_peak': float(a_hp[i]),
                'gyro_peak': float(g[i])
            })
            
            last = i
        
        return events
    
    def _detect_events_with_rejections(self, data: Dict[str, Any], score: np.ndarray, 
                                     threshold: np.ndarray, a_hp: np.ndarray) -> Tuple[List[Dict[str, Any]], Dict[str, List[Dict[str, Any]]]]:
        """Detect and validate pinch events while collecting rejected candidates."""
        
        t, fs = data['time'], data['fs']
        g = data['gyro_mag']
        n = len(score)
        
        # Parameters
        refr = int(round(self.params.get('refractory_s', 0.12) * fs))
        pw = int(round(self.params.get('peakwin_s', 0.04) * fs))
        gate = int(round(self.params.get('gatewin_s', 0.18) * fs))
        min_iei = int(round(self.params.get('min_iei_s', 0.10) * fs))
        acc_gate = self.params.get('acc_gate', 0.025)
        gyro_gate = self.params.get('gyro_gate', 0.10)
        
        # Find all candidates above threshold
        candidates = np.where(score > threshold)[0]
        
        # Track events and rejections
        events = []
        rejected_candidates = {
            'refractory': [],
            'not_peak': [],
            'acc_gates': [],
            'gyro_gates': [],
            'min_iei': []
        }
        
        last = -10**9
        
        for idx in candidates:
            candidate = {
                'index': int(idx),
                'time': float(t[idx]),
                'score': float(score[idx]),
                'threshold': float(threshold[idx]),
                'acc_peak': float(a_hp[idx]),
                'gyro_peak': float(g[idx])
            }
            
            # Check rejection reasons in order
            if idx - last < refr:
                rejected_candidates['refractory'].append(candidate)
                continue
                
            # Local maxima check
            i0 = max(0, idx - pw)
            i1 = min(n, idx + pw + 1)
            if idx != i0 + np.argmax(score[i0:i1]):
                rejected_candidates['not_peak'].append(candidate)
                continue
                
            # Gate checks
            g0 = max(0, idx - gate)
            g1 = min(n, idx + gate + 1)
            # Separate gate checks for debugging
            acc_gate_max = np.nanmax(a_hp[g0:g1])
            gyro_gate_max = np.nanmax(g[g0:g1])
            
            acc_gate_pass = acc_gate_max >= acc_gate
            gyro_gate_pass = gyro_gate_max >= gyro_gate
            
            if not acc_gate_pass:
                rejected_candidates['acc_gates'].append(candidate)
            if not gyro_gate_pass:
                rejected_candidates['gyro_gates'].append(candidate)
                
            # Reject if either gate fails
            if not (acc_gate_pass and gyro_gate_pass):
                continue
                
            # Minimum inter-event interval
            if len(events) > 0 and (idx - events[-1]['index']) < min_iei:
                rejected_candidates['min_iei'].append(candidate)
                continue
                
            # All checks passed!
            events.append(candidate)
            last = idx
        
        return events, rejected_candidates


class StreamingBaselineTracker:
    """Online baseline and MAD estimation for streaming detection."""
    
    def __init__(self, alpha: float = 1/1000, hampel_k: float = 3.0):
        self.alpha = alpha  # EMA decay rate
        self.hampel_k = hampel_k  # Outlier detection threshold
        self.mean = 0.0
        self.mad = 1.0  # Start with reasonable default
        self.initialized = False
        
    def update(self, value: float):
        """Update baseline statistics, skipping outliers."""
        if not self.initialized:
            self.mean = value
            self.mad = abs(value - self.mean) + 1e-6
            self.initialized = True
            return
            
        # Hampel outlier detection - don't update stats during events
        if abs(value - self.mean) <= self.hampel_k * self.mad:
            # Normal sample - update statistics
            self.mean = (1 - self.alpha) * self.mean + self.alpha * value
            self.mad = (1 - self.alpha) * self.mad + self.alpha * abs(value - self.mean)
            
    def get_threshold(self, k_mad: float = 3.0) -> float:
        """Get adaptive threshold."""
        return self.mean + k_mad * 1.4826 * self.mad


class StreamingSignalProcessor:
    """Real-time signal processing for streaming detection."""
    
    def __init__(self, fs: float = 100.0):
        self.fs = fs
        # Simple high-pass filter state (1st order IIR)
        self.hp_alpha = 0.99  # For ~0.5Hz high-pass at 100Hz
        self.acc_hp_state = np.array([0.0, 0.0, 0.0])
        self.gyro_hp_state = np.array([0.0, 0.0, 0.0])
        self.acc_hp_prev = np.array([0.0, 0.0, 0.0])
        self.gyro_hp_prev = np.array([0.0, 0.0, 0.0])
        
    def compute_fusion_score(self, acc_xyz: np.ndarray, gyro_xyz: np.ndarray) -> float:
        """Compute fusion score for single sample."""
        # High-pass filter for acceleration (remove gravity/drift)
        acc_hp = self.hp_alpha * (self.acc_hp_state + acc_xyz - self.acc_hp_prev)
        self.acc_hp_state = acc_hp
        self.acc_hp_prev = acc_xyz
        
        # Light high-pass for gyroscope  
        gyro_hp = self.hp_alpha * (self.gyro_hp_state + gyro_xyz - self.gyro_hp_prev)
        self.gyro_hp_state = gyro_hp
        self.gyro_hp_prev = gyro_xyz
        
        # Compute magnitudes
        acc_mag = np.linalg.norm(acc_hp)
        gyro_mag = np.linalg.norm(gyro_hp)
        
        # Fusion (weighted combination)
        return 0.6 * acc_mag + 0.4 * gyro_mag


class StreamingPhysiologicalDetector:
    """
    Real-time streaming detector using physiological constraints.
    
    Implements the algorithm recommended by GPT-5 and Gemini Pro:
    - Liberal candidate generation with lower threshold
    - Decision buffer to wait for stronger peaks  
    - Hard 300ms physiological constraint
    - O(1) per sample processing
    """
    
    def __init__(self, config: Dict[str, Any]):
        self.params = config.get('streaming_params', {})
        
        # Core parameters
        self.min_interval = self.params.get('min_interval_s', 0.300)  # 300ms physiological limit
        self.decision_latency = self.params.get('decision_latency_s', 0.200)  # 200ms decision window
        self.liberal_threshold = self.params.get('k_mad_liberal', 3.0)  # Lower threshold for candidates
        self.confirm_threshold = self.params.get('k_mad_confirm', 3.8)  # Higher threshold for confirmation
        
        # State variables
        self.last_confirmed_time = -10.0  # Last accepted event time
        self.candidate_peak = None  # Current candidate: {time, amplitude, score, acc_peak, gyro_peak}
        
        # Signal processing components
        self.baseline_tracker = StreamingBaselineTracker()
        self.signal_processor = StreamingSignalProcessor()
        
        # Peak detection state
        self.prev_score = 0.0
        self.in_peak = False
        self.peak_start_time = 0.0
        
    def detect_streaming(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Simulate streaming detection on batch data for testing/comparison.
        In real watch implementation, this would be called sample-by-sample.
        """
        print(f"Running streaming physiological detection...")
        
        t = data['time']
        acc_xyz = data['acc_xyz']
        gyro_xyz = data['gyro_xyz']
        fs = data['fs']
        
        # Initialize signal processor with correct sample rate
        self.signal_processor = StreamingSignalProcessor(fs)
        
        events = []
        scores = []
        thresholds = []
        
        # Process each sample sequentially
        for i in range(len(t)):
            timestamp = t[i]
            acc_sample = acc_xyz[i]
            gyro_sample = gyro_xyz[i] 
            
            # Process single sample
            event = self.process_sample(timestamp, acc_sample, gyro_sample)
            
            # Record score and threshold for analysis
            current_score = self.signal_processor.compute_fusion_score(acc_sample, gyro_sample)
            current_threshold = self.baseline_tracker.get_threshold(self.liberal_threshold)
            scores.append(current_score)
            thresholds.append(current_threshold)
            
            if event:
                events.append(event)
        
        # Check for final candidate confirmation
        if self.candidate_peak and len(t) > 0:
            final_time = t[-1]
            if final_time >= self.candidate_peak['time'] + self.decision_latency:
                final_event = self._confirm_candidate()
                if final_event:
                    events.append(final_event)
        
        print(f"✓ Detected {len(events)} events (streaming)")
        
        return {
            'detector_type': 'streaming_physiological',
            'events': events,
            'score': np.array(scores),
            'threshold': np.array(thresholds),
            'params': self.params,
            'data': data
        }
    
    def process_sample(self, timestamp: float, acc_xyz: np.ndarray, gyro_xyz: np.ndarray) -> Optional[Dict[str, Any]]:
        """
        Process a single sensor sample. 
        This is the core real-time function for watch implementation.
        """
        # 1. Compute fusion score
        score = self.signal_processor.compute_fusion_score(acc_xyz, gyro_xyz)
        
        # 2. Update baseline tracker  
        self.baseline_tracker.update(score)
        
        # 3. Check if candidate needs confirmation
        if (self.candidate_peak and 
            timestamp >= self.candidate_peak['time'] + self.decision_latency):
            confirmed_event = self._confirm_candidate()
            if confirmed_event:
                return confirmed_event
        
        # 4. Enforce physiological refractory period
        if timestamp < self.last_confirmed_time + self.min_interval:
            return None  # In dead zone
        
        # 5. Peak detection and candidate management
        self._update_peak_detection(timestamp, score, acc_xyz, gyro_xyz)
        
        return None  # No immediate detection
    
    def _update_peak_detection(self, timestamp: float, score: float, acc_xyz: np.ndarray, gyro_xyz: np.ndarray):
        """Update peak detection state and manage candidates."""
        threshold = self.baseline_tracker.get_threshold(self.liberal_threshold)
        
        # Simple peak detection using score progression
        is_rising = score > self.prev_score
        above_threshold = score > threshold
        
        if above_threshold and is_rising and not self.in_peak:
            # Starting a new peak
            self.in_peak = True
            self.peak_start_time = timestamp
            
        elif self.in_peak and not is_rising:
            # Peak is ending - this was the maximum
            if above_threshold:  # Only consider if still above threshold
                new_candidate = {
                    'time': timestamp,
                    'score': self.prev_score,  # Use previous (peak) score
                    'threshold': threshold,
                    'acc_peak': np.linalg.norm(acc_xyz),
                    'gyro_peak': np.linalg.norm(gyro_xyz)
                }
                
                # Update candidate if this is better than current
                if (self.candidate_peak is None or 
                    new_candidate['score'] > self.candidate_peak['score']):
                    self.candidate_peak = new_candidate
            
            self.in_peak = False
        
        self.prev_score = score
    
    def _confirm_candidate(self) -> Optional[Dict[str, Any]]:
        """Confirm the current candidate as a real event."""
        if not self.candidate_peak:
            return None
            
        # Additional confirmation threshold check
        confirm_threshold = self.baseline_tracker.get_threshold(self.confirm_threshold)
        if self.candidate_peak['score'] < confirm_threshold:
            # Candidate doesn't meet confirmation threshold
            self.candidate_peak = None
            return None
        
        # Confirm the event
        event = {
            'index': -1,  # Not applicable for streaming
            'time': float(self.candidate_peak['time']),
            'score': float(self.candidate_peak['score']),
            'threshold': float(self.candidate_peak['threshold']),
            'acc_peak': float(self.candidate_peak['acc_peak']),
            'gyro_peak': float(self.candidate_peak['gyro_peak'])
        }
        
        self.last_confirmed_time = self.candidate_peak['time']
        self.candidate_peak = None
        
        return event


def get_default_config() -> Dict[str, Any]:
    """Get default configuration values."""
    return {
        'stationary_params': {
            'k_mad': 5.5,
            'acc_gate': 0.025,
            'gyro_gate': 0.10,
            'hp_win': 0.5,
            'thr_win': 3.0,
            'refractory_s': 0.12,
            'peakwin_s': 0.04,
            'gatewin_s': 0.18,
            'min_iei_s': 0.10,
        },
        'streaming_params': {
            'min_interval_s': 0.300,  # 300ms physiological constraint
            'decision_latency_s': 0.200,  # 200ms decision window
            'k_mad_liberal': 3.2,  # Liberal threshold for candidates - balanced
            'k_mad_confirm': 4.2,  # Confirmation threshold - balanced
            'baseline_alpha': 0.001,  # EMA decay for baseline tracking
            'hampel_k': 3.0,  # Outlier detection threshold
        },
        'walking_params': {
            'k_mad': 3.0,
            'acc_gate': 0.025,
            'gyro_gate': 0.10,
            'hp_win': 0.5,
            'bp_lo': 4.0,
            'bp_hi': 30.0,
            'env_win': 0.06,
            'thr_win': 3.0,
            'align_tol_s': 0.50,
            'rise_max_s': 0.40,
            'decay_dt_s': 0.14,
            'decay_frac_max': 0.90,
            'energy_ratio_min': 0.001,
            'low_lo': 0.7,
            'low_hi': 3.0,
            'corr_lag_s': 0.10,
            'corr_min': 0.15,
            'refractory_s': 0.12,
            'peakwin_s': 0.15,
            'gatewin_s': 0.20,
            'min_iei_s': 0.10,
        },
        'input': {
            'auto_detect_format': True,
            'expected_fs': 100.0,
            'csv_columns': {
                'time': 'time_s',
                'epoch': 'epoch_s',
                'acceleration_x': 'userAccelerationX',
                'acceleration_y': 'userAccelerationY',
                'acceleration_z': 'userAccelerationZ',
                'rotation_x': 'rotationRateX',
                'rotation_y': 'rotationRateY',
                'rotation_z': 'rotationRateZ',
                'gravity_x': 'gravityX',
                'gravity_y': 'gravityY',
                'gravity_z': 'gravityZ',
            },
            'json_paths': {
                'metadata': 'metadata',
                'sensor_data': 'sensorData',
                'time': 'time_s',
                'epoch': 'epoch_s',
                'acceleration': 'userAcceleration',
                'rotation': 'rotationRate',
                'gravity': 'gravity',
            }
        },
        'output': {
            'directory_template': 'analysis_{session_id}_{timestamp}',
            'export_csv': True,
            'export_html': True,
            'export_plots': True,
            'chart_style': 'research',
            'chart_height': 400,
            'chart_responsive': True,
            'chart_animation': True,
            'include_debug': False,
            'plot_components': True,
            'plot_fusion_score': True,
            'plot_events': True,
        },
        'analysis': {
            'detector_type': 'stationary',
            'remove_gravity': False,
            'filter_outliers': True,
            'min_duration_s': 1.0,
            'max_gap_s': 0.1,
            'parallel_processing': False,
            'chunk_size': 10000,
        }
    }


def clean_analysis_directories(auto_confirm: bool = False):
    """Delete all analysis_*_*_* directories safely."""
    import glob
    import shutil
    
    # Get current working directory
    current_dir = Path.cwd()
    print(f"Looking for analysis directories in: {current_dir}")
    
    # Find all directories matching the pattern analysis_*_*_*
    pattern = "analysis_*_*_*"
    directories = glob.glob(str(current_dir / pattern))
    
    # Filter to ensure they are directories and match our exact pattern
    analysis_dirs = []
    for path in directories:
        path_obj = Path(path)
        if path_obj.is_dir():
            # Verify it matches our expected pattern: analysis_SESSIONID_TIMESTAMP
            parts = path_obj.name.split('_')
            if len(parts) >= 3 and parts[0] == 'analysis':
                analysis_dirs.append(path_obj)
    
    if not analysis_dirs:
        print("No analysis directories found matching pattern 'analysis_*_*_*'")
        return
    
    # Show what would be deleted
    print(f"\nFound {len(analysis_dirs)} analysis directories:")
    for dir_path in sorted(analysis_dirs):
        print(f"  - {dir_path.name}")
    
    # Confirm deletion
    if auto_confirm:
        print(f"\nAuto-deleting {len(analysis_dirs)} directories...")
        deleted_count = 0
        for dir_path in analysis_dirs:
            try:
                shutil.rmtree(dir_path)
                print(f"Deleted: {dir_path.name}")
                deleted_count += 1
            except Exception as e:
                print(f"Error deleting {dir_path.name}: {e}")
        print(f"Successfully deleted {deleted_count} directories.")
    else:
        try:
            response = input(f"\nDelete these {len(analysis_dirs)} directories? [y/N]: ").strip().lower()
            if response in ['y', 'yes']:
                deleted_count = 0
                for dir_path in analysis_dirs:
                    try:
                        shutil.rmtree(dir_path)
                        print(f"Deleted: {dir_path.name}")
                        deleted_count += 1
                    except Exception as e:
                        print(f"Error deleting {dir_path.name}: {e}")
                print(f"\nSuccessfully deleted {deleted_count} directories.")
            else:
                print("Deletion cancelled.")
        except (KeyboardInterrupt, EOFError):
            print("\nDeletion cancelled.")


def load_config(config_path: Optional[str] = None) -> Dict[str, Any]:
    """Load configuration from YAML file or return defaults."""
    
    # Start with default configuration
    config = get_default_config()
    
    # If no config path provided, return defaults
    if config_path is None:
        print("Using default configuration (no config file specified)")
        return config
    
    config_path = Path(config_path)
    
    if not config_path.exists():
        print(f"Config file not found: {config_path}")
        print("Using default configuration")
        return config
    
    try:
        with open(config_path, 'r') as f:
            user_config = yaml.safe_load(f)
        
        # Merge user config with defaults (user config takes precedence)
        def merge_config(default: Dict, user: Dict) -> Dict:
            """Recursively merge user config with defaults."""
            merged = default.copy()
            for key, value in user.items():
                if key in merged and isinstance(merged[key], dict) and isinstance(value, dict):
                    merged[key] = merge_config(merged[key], value)
                else:
                    merged[key] = value
            return merged
        
        config = merge_config(config, user_config)
        print(f"Loaded configuration from: {config_path}")
        
    except Exception as e:
        print(f"Error loading config file {config_path}: {e}")
        print("Using default configuration")
    
    return config


def create_output_directory(config: Dict[str, Any], session_data: Dict[str, Any], 
                           output_base: Optional[str] = None) -> Path:
    """Create output directory with configured naming."""
    
    # Use current directory if no output base specified
    if output_base is None:
        output_base = "."
        print("Using current directory for output (no output directory specified)")
    
    # Extract session info
    metadata = session_data.get('metadata', {})
    session_id = metadata.get('sessionId', 'unknown')
    if '-' in session_id:
        session_id = session_id.split('-')[0]  # Use first part of UUID
    
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    detector_type = config.get('analysis', {}).get('detector_type', 'stationary')
    
    # Apply template
    template = config.get('output', {}).get('directory_template', 'analysis_{session_id}_{timestamp}')
    dirname = template.format(
        session_id=session_id,
        timestamp=timestamp,
        detector_type=detector_type
    )
    
    output_dir = Path(output_base) / dirname
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"✓ Created output directory: {output_dir}")
    return output_dir


def save_results(results: Dict[str, Any], output_dir: Path, config: Dict[str, Any], debug_results: Dict[str, Any] = None):
    """Save analysis results to files."""
    
    output_config = config.get('output', {})
    
    # Save events to CSV
    if output_config.get('export_csv', True) and results['events']:
        events_df = pd.DataFrame(results['events'])
        csv_path = output_dir / 'detected_events.csv'
        events_df.to_csv(csv_path, index=False)
        print(f"✓ Saved {len(results['events'])} events to: {csv_path}")
    
    # Generate HTML report
    if output_config.get('export_html', True):
        html_generator = HTMLReportGenerator(config)
        report_path = html_generator.generate_report(results, output_dir, debug_results)
    
    # Save analysis summary
    summary = {
        'detector_type': results['detector_type'],
        'total_events': len(results['events']),
        'session_duration': float(results['data']['time'][-1] - results['data']['time'][0]),
        'detection_rate_per_min': len(results['events']) / (results['data']['time'][-1] - results['data']['time'][0]) * 60,
        'parameters': results['params'],
        'session_info': results['data']['metadata']
    }
    
    summary_path = output_dir / 'analysis_summary.json'
    with open(summary_path, 'w') as f:
        json.dump(summary, f, indent=2)
    print(f"✓ Saved analysis summary to: {summary_path}")


def main():
    """Main entry point."""
    
    parser = argparse.ArgumentParser(
        description='Stationary Pinch Detection Analysis Tool',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --input session_data.csv --config config.yaml --output results/
  %(prog)s --input session_data.json --config config.yaml --output results/
  %(prog)s --input data/ --config config.yaml --output results/ --batch
  
Algorithm Comparison:
  %(prog)s --input session.csv --detector stationary --output results_batch/
  %(prog)s --input session.csv --detector streaming --output results_streaming/
        """
    )
    
    parser.add_argument('--input', '-i', required=False,
                       help='Input session data file (CSV or JSON)')
    parser.add_argument('--config', '-c', default=None,
                       help='Configuration YAML file (optional, uses defaults if not provided)')
    parser.add_argument('--output', '-o', default=None,
                       help='Output directory (optional, uses current directory if not provided)')
    parser.add_argument('--batch', action='store_true',
                       help='Process multiple files in input directory')
    parser.add_argument('--detector', choices=['stationary', 'streaming', 'walking'],
                       help='Override detector type from config')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Enable verbose output')
    
    # Debug modes
    parser.add_argument('--debug-detection', action='store_true',
                       help='Show detailed rejection statistics and analysis')
    parser.add_argument('--debug-threshold', action='store_true',
                       help='Analyze peaks that don\'t cross adaptive threshold')
    parser.add_argument('--debug-visual', action='store_true',
                       help='Generate visual debug plots with rejection categories')
    parser.add_argument('--debug-all', action='store_true',
                       help='Enable all debug modes')
    parser.add_argument('--clean', action='store_true',
                       help='Delete all analysis_*_*_* directories (auto-confirm if used with --input)')
    
    args = parser.parse_args()
    
    # Handle clean flag - if no input specified, clean and exit
    if args.clean and not args.input:
        clean_analysis_directories()
        return
    
    # If clean flag is specified with input, clean first then continue
    if args.clean and args.input:
        clean_analysis_directories(auto_confirm=True)
    
    # Validate required arguments when not just cleaning
    if not args.input:
        parser.error("the following arguments are required: --input/-i")
    
    # Handle debug flags
    if args.debug_all:
        args.debug_detection = True
        args.debug_threshold = True
        args.debug_visual = True
    
    try:
        # Load configuration
        if args.config:
            print("Loading configuration...")
        config = load_config(args.config)
        
        # Override detector type if specified
        if args.detector:
            if 'analysis' not in config:
                config['analysis'] = {}
            config['analysis']['detector_type'] = args.detector
        
        # Initialize components
        loader = SessionDataLoader(config)
        
        detector_type = config.get('analysis', {}).get('detector_type', 'stationary')
        if detector_type == 'stationary':
            detector = StationaryDetector(config)
        elif detector_type == 'streaming':
            detector = StreamingPhysiologicalDetector(config)
        else:
            raise NotImplementedError(f"Detector type '{detector_type}' not implemented yet")
        
        # Process input
        if args.batch:
            # TODO: Implement batch processing
            raise NotImplementedError("Batch processing not implemented yet")
        else:
            # Single file processing
            print(f"\nProcessing single file: {args.input}")
            
            # Load data
            session_data = loader.load_data(args.input)
            
            # Create output directory
            output_dir = create_output_directory(config, session_data, args.output)
            
            # Run detection (always collect rejections for visual debug)
            print(f"\nRunning {detector_type} detection...")
            if detector_type == 'streaming':
                results = detector.detect_streaming(session_data)
            else:
                results = detector.detect(session_data, collect_rejections=True)
            
            # Run debug analysis if requested
            debug_results = {}
            
            # Always run visual debug by default
            debug_results['visual'] = True
            
            # Always run basic threshold analysis for missed peaks markers
            threshold_debugger = ThresholdDebugger(config)
            debug_results['threshold'] = threshold_debugger.analyze_missed_peaks(session_data)
            
            if args.debug_detection:
                debug_detector = DebugDetector(config)
                debug_results['detection'] = debug_detector.debug_detect(session_data)
            
            # Save results (pass debug_results to be included)
            print(f"\nSaving results...")
            save_results(results, output_dir, config, debug_results)
            
            # Print summary
            duration = session_data['time'][-1] - session_data['time'][0]
            rate = len(results['events']) / duration * 60
            
            print(f"\n📊 Analysis Complete!")
            print(f"  Events detected: {len(results['events'])}")
            print(f"  Detection rate: {rate:.1f} events/min")
            print(f"  Session duration: {duration:.1f} seconds")
            print(f"  Results saved to: {output_dir}")
            
            if args.verbose and results['events']:
                print(f"\n🎯 First few events:")
                for i, event in enumerate(results['events'][:3]):
                    print(f"  Event {i+1}: t={event['time']:.2f}s, score={event['score']:.1f}")
    
    except Exception as e:
        print(f"❌ Error: {e}", file=sys.stderr)
        return 1
    
    return 0


if __name__ == '__main__':
    sys.exit(main())