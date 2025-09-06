"""
HTML Report Generation for Pinch Detection Analysis

Generates interactive HTML reports with Chart.js visualizations.
"""

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List

import numpy as np


class HTMLReportGenerator:
    """Generates interactive HTML reports with Chart.js visualizations."""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.output_config = config.get('output', {})
        self.chart_config = {
            'height': self.output_config.get('chart_height', 400),
            'responsive': self.output_config.get('chart_responsive', True),
            'animation': self.output_config.get('chart_animation', True),
            'style': self.output_config.get('chart_style', 'research')
        }
    
    def generate_report(self, results: Dict[str, Any], output_dir: Path, debug_results: Dict[str, Any] = None) -> Path:
        """
        Generate comprehensive HTML report.
        
        Args:
            results: Detection results from analyzer
            output_dir: Directory to save report
            
        Returns:
            Path to generated HTML file
        """
        
        # Prepare data for visualization
        chart_data = self._prepare_chart_data(results, debug_results)
        
        # Generate HTML content
        html_content = self._generate_html(results, chart_data, debug_results)
        
        # Save report
        report_path = output_dir / 'analysis_report.html'
        with open(report_path, 'w', encoding='utf-8') as f:
            f.write(html_content)
        
        print(f"✓ Generated HTML report: {report_path}")
        return report_path
    
    def _prepare_chart_data(self, results: Dict[str, Any], debug_results: Dict[str, Any] = None) -> Dict[str, Any]:
        """Prepare data for Chart.js visualization."""
        
        data = results['data']
        events = results['events']
        
        # Time series data - use precise seconds from start
        time_raw = data['time'].tolist()
        start_time = time_raw[0]
        time = [round(t - start_time, 3) for t in time_raw]  # Precise seconds from start
        
        # Calculate max time for tick generation
        max_time = max(time)
        tick_interval = max(1, int(max_time / 20))  # Reasonable number of ticks
        x_ticks = list(range(0, int(max_time) + tick_interval, tick_interval))
        x_axis_config = {
            'tick_interval': tick_interval,
            'max_time': int(max_time)
        }
        
        score = results['score'].tolist()
        threshold = results['threshold'].tolist()
        
        # Acceleration data
        if 'a_hp' in results:
            acc_signal = results['a_hp'].tolist()
            acc_label = 'High-Pass Acceleration'
        else:
            acc_signal = data['acc_mag'].tolist()
            acc_label = 'Acceleration Magnitude'
        
        # Gyroscope data
        gyro_signal = data['gyro_mag'].tolist()
        
        # Raw sensor data (3-axis)
        raw_data = {
            'acceleration': {
                'x': data['acc_xyz'][:, 0].tolist(),
                'y': data['acc_xyz'][:, 1].tolist(), 
                'z': data['acc_xyz'][:, 2].tolist(),
                'magnitude': data['acc_mag'].tolist()
            },
            'gyroscope': {
                'x': data['gyro_xyz'][:, 0].tolist(),
                'y': data['gyro_xyz'][:, 1].tolist(),
                'z': data['gyro_xyz'][:, 2].tolist(),
                'magnitude': data['gyro_mag'].tolist()
            }
        }
        
        # Event markers - use precise seconds from start
        event_times = [round(e['time'] - start_time, 3) for e in events]
        event_scores = [e['score'] for e in events]
        event_acc = [e['acc_peak'] for e in events]
        event_gyro = [e['gyro_peak'] for e in events]
        
        # Component analysis (for stationary detector)
        components = {}
        if 'components' in results and self.output_config.get('plot_components', True):
            comp_data = results['components']
            components = {
                'z_a': comp_data['z_a'].tolist(),
                'z_g': comp_data['z_g'].tolist(),
                'z_da': comp_data['z_da'].tolist(),
                'z_dg': comp_data['z_dg'].tolist()
            }
        
        # Visual debug data (rejected candidates) - convert to hundreds of milliseconds
        rejected_candidates = {}
        if 'rejected_candidates' in results:
            rejected = results['rejected_candidates']
            for category, candidates in rejected.items():
                if candidates:
                    rejected_candidates[category] = {
                        'times': [round(c['time'] - start_time, 3) for c in candidates],
                        'scores': [c['score'] for c in candidates],
                        'acc_peaks': [c['acc_peak'] for c in candidates],
                        'gyro_peaks': [c['gyro_peak'] for c in candidates]
                    }
                else:
                    rejected_candidates[category] = {
                        'times': [], 'scores': [], 'acc_peaks': [], 'gyro_peaks': []
                    }

        # Extract missed peaks data from threshold debug results
        missed_peaks_data = {'times': [], 'scores': []}
        if debug_results and 'threshold' in debug_results:
            threshold_data = debug_results['threshold']
            missed_peaks = threshold_data.get('missed_peaks', [])
            for i, peak in enumerate(missed_peaks):
                # Convert time to precise seconds from start
                peak_time = float(round(peak['time'] - start_time, 3))
                peak_score = float(peak['score'])
                missed_peaks_data['times'].append(peak_time)
                missed_peaks_data['scores'].append(peak_score)
        
        # Calculate inter-arrival times for all peaks (detected + missed)
        all_peak_times = []
        all_peak_types = []
        
        # Add detected events
        for event_time in event_times:
            all_peak_times.append(event_time)
            all_peak_types.append('detected')
        
        # Add missed peaks
        for missed_time in missed_peaks_data['times']:
            all_peak_times.append(missed_time)
            all_peak_types.append('missed')
        
        # Sort all peaks by time
        if all_peak_times:
            sorted_pairs = sorted(zip(all_peak_times, all_peak_types))
            all_peak_times_sorted, all_peak_types_sorted = zip(*sorted_pairs)
            
            # Calculate inter-arrival times in milliseconds
            inter_arrival_times = []
            inter_arrival_types = []
            for i in range(1, len(all_peak_times_sorted)):
                interval_ms = (all_peak_times_sorted[i] - all_peak_times_sorted[i-1]) * 1000  # Convert to ms (times are in seconds)
                inter_arrival_times.append(float(interval_ms))
                # Type is based on the second peak in the pair
                inter_arrival_types.append(all_peak_types_sorted[i])
            
            inter_arrival_data = {
                'times': list(range(len(inter_arrival_times))),  # Sequential indices
                'intervals': inter_arrival_times,
                'types': inter_arrival_types
            }
        else:
            inter_arrival_data = {'times': [], 'intervals': [], 'types': []}

        return {
            'time': time,
            'fusion_score': {
                'data': score,
                'threshold': threshold,
                'events': {'times': event_times, 'scores': event_scores},
                'missed_peaks': missed_peaks_data
            },
            'acceleration': {
                'data': acc_signal,
                'label': acc_label,
                'events': {'times': event_times, 'values': event_acc},
                'gate': results['params'].get('acc_gate', 0.025)
            },
            'gyroscope': {
                'data': gyro_signal,
                'label': 'Gyroscope Magnitude',
                'events': {'times': event_times, 'values': event_gyro},
                'gate': results['params'].get('gyro_gate', 0.10)
            },
            'raw_data': raw_data,
            'components': components,
            'rejected_candidates': rejected_candidates,
            'inter_arrival': inter_arrival_data,
            'x_ticks': x_ticks,
            'x_axis_config': x_axis_config
        }
    
    def _generate_html(self, results: Dict[str, Any], chart_data: Dict[str, Any], debug_results: Dict[str, Any] = None) -> str:
        """Generate complete HTML report."""
        
        # Analysis summary
        data = results['data']
        events = results['events']
        metadata = data.get('metadata', {})
        
        duration = data['time'][-1] - data['time'][0]
        rate = len(events) / duration * 60 if duration > 0 else 0
        
        # Event statistics
        event_stats = self._calculate_event_statistics(events, duration)
        
        # Session metadata formatting
        session_metadata = self._format_session_metadata(metadata, data, results['detector_type'])
        
        # Get Chart.js theme colors
        colors = self._get_chart_colors()
        
        html = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pinch Detection Analysis Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        {self._get_css_styles()}
    </style>
</head>
<body>
    <div class="container">
        <header class="header">
            <h1>Pinch Detection Analysis Report</h1>
            <div class="subtitle">
                {results['detector_type'].title()} Detection • Generated {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
            </div>
        </header>
        
        <div class="summary-grid">
            <div class="summary-card">
                <div class="metric-value">{len(events)}</div>
                <div class="metric-label">Events Detected</div>
            </div>
            <div class="summary-card">
                <div class="metric-value">{rate:.1f}</div>
                <div class="metric-label">Events/min</div>
            </div>
            <div class="summary-card">
                <div class="metric-value">{duration:.1f}s</div>
                <div class="metric-label">Session Duration</div>
            </div>
            <div class="summary-card">
                <div class="metric-value">{data['fs']:.1f}Hz</div>
                <div class="metric-label">Sampling Rate</div>
            </div>
        </div>
        
        <div class="section">
            <h2>Session Information</h2>
            {session_metadata}
        </div>
        
        <div class="section">
            <h2>Detection Results</h2>
            <div class="chart-container">
                <canvas id="fusionChart"></canvas>
            </div>
        </div>
        
        <div class="section">
            <h2>Inter-Arrival Time Analysis</h2>
            <p><em>Time intervals between consecutive peaks (detected and missed) in milliseconds. Shows rhythm and timing variability.</em></p>
            <div class="chart-container">
                <canvas id="interArrivalChart"></canvas>
            </div>
        </div>
        
        <div class="section">
            <h2>Raw Sensor Data</h2>
            <div class="chart-row">
                <div class="chart-container half">
                    <canvas id="rawAccelerationChart"></canvas>
                </div>
                <div class="chart-container half">
                    <canvas id="rawGyroscopeChart"></canvas>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>Processed Sensor Signals</h2>
            <div class="chart-row">
                <div class="chart-container half">
                    <canvas id="accelerationChart"></canvas>
                </div>
                <div class="chart-container half">
                    <canvas id="gyroscopeChart"></canvas>
                </div>
            </div>
        </div>
        
        {self._generate_components_section(chart_data) if chart_data['components'] else ''}
        
        {self._generate_events_table(events)}
        
        <div class="section">
            <h2>Detection Parameters</h2>
            <div class="params-grid">
                {self._generate_parameters_html(results['params'])}
            </div>
        </div>
        
        {self._generate_algorithm_explanation(results['detector_type'])}
        
        {self._generate_debug_sections(debug_results) if debug_results and results['detector_type'] != 'streaming' else ''}
        
        {self._generate_visual_debug_section(chart_data) if chart_data.get('rejected_candidates') and results['detector_type'] != 'streaming' else ''}
        
        <footer class="footer">
            Generated by DhikrCounter Pinch Detection Analysis Tool
        </footer>
    </div>
    
    <script>
        {self._generate_javascript(chart_data, colors)}
    </script>
</body>
</html>
        """
        
        return html
    
    def _format_session_metadata(self, metadata: Dict[str, Any], data: Dict[str, Any], detector_type: str = 'stationary') -> str:
        """Format session metadata for display."""
        from datetime import datetime
        
        # Session basic info
        session_id = metadata.get('sessionId', 'Unknown')
        if '-' in session_id:
            session_id_short = session_id.split('-')[0]
        else:
            session_id_short = session_id
        
        # Collection time
        collection_time = "Unknown"
        if 'startTime' in metadata:
            try:
                # Handle different timestamp formats
                start_time = metadata['startTime']
                if isinstance(start_time, (int, float)):
                    if start_time > 1e10:  # Likely milliseconds
                        start_time = start_time / 1000
                    collection_time = datetime.fromtimestamp(start_time).strftime('%Y-%m-%d %H:%M:%S')
            except (ValueError, OSError):
                pass
        
        # Check if we have epoch time in the data
        if collection_time == "Unknown" and 'df' in data and 'epoch_s' in data['df'].columns:
            try:
                first_epoch = data['df']['epoch_s'].iloc[0]
                if first_epoch > 1e9:  # Valid Unix timestamp
                    collection_time = datetime.fromtimestamp(first_epoch).strftime('%Y-%m-%d %H:%M:%S')
            except (ValueError, OSError, IndexError):
                pass
        
        # App version and other metadata
        app_version = metadata.get('version', 'Unknown')
        update_interval = metadata.get('update_interval_s', data['fs'] and 1.0/data['fs'] or 'Unknown')
        using_frame = metadata.get('using_frame', 'Unknown')
        
        # Calculate data quality metrics
        duration = data['time'][-1] - data['time'][0]
        expected_samples = int(duration * data['fs'])
        actual_samples = len(data['time'])
        data_completeness = (actual_samples / expected_samples * 100) if expected_samples > 0 else 0
        
        return f"""
        <div class="metadata-section compact">
            <h3>📋 Session: {session_id_short}</h3>
            <div class="metadata-compact">
                <span><strong>Collected:</strong> {collection_time}</span> • 
                <span><strong>Source:</strong> {Path(data['filepath']).name}</span> • 
                <span><strong>Duration:</strong> {duration:.1f}s @ {data['fs']:.0f}Hz</span> • 
                <span><strong>Samples:</strong> {len(data['time']):,} ({data_completeness:.1f}%)</span>
            </div>
        </div>"""
    
    def _calculate_event_statistics(self, events: List[Dict[str, Any]], duration: float) -> Dict[str, Any]:
        """Calculate event statistics."""
        if not events:
            return {'median_iei': 0, 'min_iei': 0, 'max_iei': 0}
        
        if len(events) < 2:
            return {'median_iei': duration, 'min_iei': duration, 'max_iei': duration}
        
        event_times = [e['time'] for e in events]
        ieis = np.diff(event_times)
        
        return {
            'median_iei': float(np.median(ieis)),
            'min_iei': float(np.min(ieis)),
            'max_iei': float(np.max(ieis))
        }
    
    def _get_chart_colors(self) -> Dict[str, str]:
        """Get color scheme based on chart style."""
        if self.chart_config['style'] == 'clinical':
            return {
                'primary': '#2563eb',
                'secondary': '#dc2626',
                'success': '#16a34a',
                'warning': '#d97706',
                'accent': '#7c3aed',
                'grid': '#e5e7eb',
                'text': '#374151'
            }
        elif self.chart_config['style'] == 'minimal':
            return {
                'primary': '#000000',
                'secondary': '#666666',
                'success': '#333333',
                'warning': '#999999',
                'accent': '#444444',
                'grid': '#e0e0e0',
                'text': '#000000'
            }
        else:  # research style (default)
            return {
                'primary': '#1f77b4',
                'secondary': '#ff7f0e',
                'success': '#2ca02c',
                'warning': '#d62728',
                'accent': '#9467bd',
                'grid': '#f0f0f0',
                'text': '#333333'
            }
    
    def _get_css_styles(self) -> str:
        """Generate CSS styles for the report."""
        colors = self._get_chart_colors()
        
        return f"""
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: {colors['text']};
            background-color: #ffffff;
        }}
        
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }}
        
        .header {{
            text-align: center;
            margin-bottom: 2rem;
            padding-bottom: 1rem;
            border-bottom: 2px solid {colors['primary']};
        }}
        
        .header h1 {{
            color: {colors['primary']};
            font-size: 2.5rem;
            font-weight: 300;
            margin-bottom: 0.5rem;
        }}
        
        .subtitle {{
            color: #666;
            font-size: 1.1rem;
        }}
        
        .summary-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            margin-bottom: 2rem;
        }}
        
        .summary-card {{
            background: #f8f9fa;
            padding: 1.5rem;
            border-radius: 8px;
            text-align: center;
            border-left: 4px solid {colors['primary']};
        }}
        
        .metric-value {{
            font-size: 2rem;
            font-weight: bold;
            color: {colors['primary']};
            margin-bottom: 0.5rem;
        }}
        
        .metric-label {{
            font-size: 0.9rem;
            color: #666;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }}
        
        .section {{
            margin-bottom: 3rem;
        }}
        
        .section h2 {{
            color: {colors['primary']};
            font-size: 1.5rem;
            margin-bottom: 1rem;
            padding-bottom: 0.5rem;
            border-bottom: 1px solid #eee;
        }}
        
        .info-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 1rem;
        }}
        
        .info-item {{
            padding: 0.5rem 0;
        }}
        
        .info-label {{
            font-weight: bold;
            margin-right: 1rem;
        }}
        
        .info-value {{
            color: #666;
        }}
        
        .chart-container {{
            background: white;
            padding: 1rem;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 1rem;
            position: relative;
            height: {self.chart_config['height'] + 40}px;
        }}
        
        .chart-container.half {{
            width: 48%;
            display: inline-block;
            margin-right: 2%;
        }}
        
        .chart-row {{
            display: flex;
            gap: 2%;
        }}
        
        .chart-row .chart-container {{
            flex: 1;
        }}
        
        .events-table {{
            width: 100%;
            border-collapse: collapse;
            background: white;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        
        .events-table th {{
            background: {colors['primary']};
            color: white;
            padding: 1rem;
            text-align: left;
            font-weight: 600;
        }}
        
        .events-table td {{
            padding: 0.75rem 1rem;
            border-bottom: 1px solid #eee;
        }}
        
        .events-table tr:hover {{
            background-color: #f8f9fa;
        }}
        
        .params-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
        }}
        
        .param-item {{
            background: #f8f9fa;
            padding: 1rem;
            border-radius: 4px;
            border-left: 3px solid {colors['accent']};
        }}
        
        .param-name {{
            font-weight: bold;
            color: {colors['primary']};
            margin-bottom: 0.25rem;
        }}
        
        .param-value {{
            color: #666;
            font-family: monospace;
        }}
        
        .metadata-section {{
            background: #f8f9fa;
            padding: 1.5rem;
            border-radius: 8px;
            margin-bottom: 1rem;
        }}
        
        .metadata-section h3 {{
            color: {colors['primary']};
            font-size: 1.1rem;
            margin: 0 0 1rem 0;
            padding-bottom: 0.5rem;
            border-bottom: 1px solid #ddd;
        }}
        
        .metadata-section h3:not(:first-child) {{
            margin-top: 1.5rem;
        }}
        
        .metadata-section.compact {{
            background: #f8f9fa;
            padding: 1rem 1.5rem;
            border-radius: 8px;
            margin-bottom: 1rem;
        }}
        
        .metadata-section.compact h3 {{
            font-size: 1rem;
            margin: 0 0 0.5rem 0;
            border: none;
            padding: 0;
        }}
        
        .metadata-compact {{
            font-size: 0.9rem;
            line-height: 1.4;
            color: #666;
        }}
        
        .metadata-compact span {{
            white-space: nowrap;
        }}
        
        .timestamp {{
            font-family: monospace;
            background: #e9ecef;
            padding: 0.2rem 0.4rem;
            border-radius: 3px;
            font-weight: bold;
        }}
        
        .debug-subsection {{
            background: #f8f9fa;
            padding: 1.5rem;
            border-radius: 8px;
            margin-bottom: 1.5rem;
            border-left: 4px solid {colors['accent']};
        }}
        
        .debug-subsection h3 {{
            color: {colors['primary']};
            font-size: 1.1rem;
            margin: 0 0 1rem 0;
            padding-bottom: 0.5rem;
            border-bottom: 1px solid #ddd;
        }}
        
        .debug-stats {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            margin-bottom: 1rem;
        }}
        
        .stat-item {{
            background: white;
            padding: 0.75rem;
            border-radius: 4px;
            border-left: 3px solid {colors['primary']};
        }}
        
        .stat-label {{
            font-weight: bold;
            color: {colors['primary']};
            margin-right: 0.5rem;
        }}
        
        .stat-value {{
            color: #666;
            font-family: monospace;
            font-weight: bold;
        }}
        
        .debug-table-container {{
            margin-top: 1rem;
        }}
        
        .debug-table-container h4 {{
            color: {colors['primary']};
            font-size: 1rem;
            margin-bottom: 0.5rem;
        }}
        
        .debug-table {{
            width: 100%;
            border-collapse: collapse;
            background: white;
            border-radius: 4px;
            overflow: hidden;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            font-size: 0.9rem;
        }}
        
        .debug-table th {{
            background: {colors['primary']};
            color: white;
            padding: 0.5rem;
            text-align: left;
            font-weight: 600;
            font-size: 0.85rem;
        }}
        
        .debug-table td {{
            padding: 0.5rem;
            border-bottom: 1px solid #eee;
        }}
        
        .debug-table tr:hover {{
            background-color: #f8f9fa;
        }}
        
        .visual-debug-summary {{
            background: #f8f9fa;
            padding: 1rem;
            border-radius: 6px;
            margin-bottom: 1rem;
            border-left: 4px solid {colors['accent']};
        }}
        
        .visual-debug-summary p {{
            margin: 0.5rem 0;
        }}
        
        .visual-debug-summary em {{
            color: #666;
            font-style: italic;
        }}
        
        .footer {{
            text-align: center;
            padding: 2rem 0;
            color: #999;
            border-top: 1px solid #eee;
            margin-top: 3rem;
        }}
        
        @media (max-width: 768px) {{
            .chart-container.half {{
                width: 100%;
                margin-right: 0;
                margin-bottom: 1rem;
            }}
            
            .chart-row {{
                flex-direction: column;
            }}
            
            .summary-grid {{
                grid-template-columns: 1fr;
            }}
        }}
        """
    
    def _generate_components_section(self, chart_data: Dict[str, Any]) -> str:
        """Generate components analysis section."""
        if not chart_data['components']:
            return ''
            
        return """
        <div class="section">
            <h2>Component Analysis</h2>
            <div class="chart-row">
                <div class="chart-container half">
                    <canvas id="componentsChart1"></canvas>
                </div>
                <div class="chart-container half">
                    <canvas id="componentsChart2"></canvas>
                </div>
            </div>
        </div>
        """
    
    def _generate_events_table(self, events: List[Dict[str, Any]]) -> str:
        """Generate events table HTML."""
        if not events:
            return """
            <div class="section">
                <h2>Detected Events</h2>
                <p>No events detected in this session.</p>
            </div>
            """
        
        # Limit to first 10 events for display
        display_events = events[:10]
        
        rows = []
        for i, event in enumerate(display_events, 1):
            rows.append(f"""
            <tr>
                <td>{i}</td>
                <td>{event['time']:.2f}s</td>
                <td>{event['score']:.2f}</td>
                <td>{event['acc_peak']:.3f}g</td>
                <td>{event['gyro_peak']:.3f}rad/s</td>
            </tr>
            """)
        
        table_note = ""
        if len(events) > 10:
            table_note = f"<p><em>Showing first 10 of {len(events)} events. See CSV export for complete list.</em></p>"
        
        return f"""
        <div class="section">
            <h2>Detected Events</h2>
            <table class="events-table">
                <thead>
                    <tr>
                        <th>#</th>
                        <th>Time</th>
                        <th>Score</th>
                        <th>Acc Peak</th>
                        <th>Gyro Peak</th>
                    </tr>
                </thead>
                <tbody>
                    {''.join(rows)}
                </tbody>
            </table>
            {table_note}
        </div>
        """
    
    def _generate_parameters_html(self, params: Dict[str, Any]) -> str:
        """Generate parameters display HTML."""
        param_items = []
        
        for key, value in params.items():
            # Format parameter name
            display_name = key.replace('_', ' ').title()
            
            # Format value
            if isinstance(value, float):
                display_value = f"{value:.3f}"
            else:
                display_value = str(value)
            
            param_items.append(f"""
            <div class="param-item">
                <div class="param-name">{display_name}</div>
                <div class="param-value">{display_value}</div>
            </div>
            """)
        
        return ''.join(param_items)
    
    def _generate_algorithm_explanation(self, detector_type: str) -> str:
        """Generate algorithm-specific explanation section."""
        if detector_type == 'streaming':
            return """
        <div class="section">
            <h2>Streaming Algorithm Overview</h2>
            <div class="algorithm-explanation">
                <p>The <strong>Streaming Physiological Detector</strong> is designed for real-time implementation on smartwatch devices. Key features:</p>
                <ul>
                    <li><strong>Real-time Processing:</strong> Processes sensor data sample-by-sample with ≤200ms latency</li>
                    <li><strong>Physiological Constraints:</strong> Enforces minimum 300ms interval between events (human finger tapping limit)</li>
                    <li><strong>Two-threshold System:</strong> Liberal threshold (4.5σ) identifies candidates, confirmation threshold (5.5σ) validates events</li>
                    <li><strong>Decision Buffer:</strong> 200ms buffer allows evaluation of candidate quality before confirmation</li>
                    <li><strong>Online Baseline Tracking:</strong> Continuously adapts to signal changes using robust statistics</li>
                </ul>
                <p><strong>Note:</strong> This algorithm prioritizes physiological plausibility over raw signal amplitude, 
                   making it ideal for detecting intentional finger movements while rejecting noise and artifacts.</p>
            </div>
        </div>
            """
        else:
            return ""
    
    def _generate_javascript(self, chart_data: Dict[str, Any], colors: Dict[str, str]) -> str:
        """Generate JavaScript for Chart.js visualizations."""
        
        # Convert data to JSON
        chart_data_json = json.dumps(chart_data)
        colors_json = json.dumps(colors)
        
        return f"""
        const chartData = {chart_data_json};
        const colors = {colors_json};
        
        // Chart.js default configuration
        Chart.defaults.responsive = {str(self.chart_config['responsive']).lower()};
        Chart.defaults.maintainAspectRatio = false;
        Chart.defaults.animation = {str(self.chart_config['animation']).lower()};
        
        // Common chart options
        const commonOptions = {{
            responsive: true,
            maintainAspectRatio: false,
            plugins: {{
                legend: {{
                    position: 'top',
                }},
            }},
            scales: {{
                x: {{
                    type: 'linear',
                    title: {{
                        display: true,
                        text: 'Time (seconds)'
                    }},
                    grid: {{
                        color: colors.grid
                    }},
                    min: 0,
                    max: Math.ceil(chartData.x_axis_config.max_time / chartData.x_axis_config.tick_interval) * chartData.x_axis_config.tick_interval,
                    ticks: {{
                        stepSize: chartData.x_axis_config.tick_interval,
                        precision: 0
                    }}
                }},
                y: {{
                    grid: {{
                        color: colors.grid
                    }}
                }}
            }}
        }};
        
        // Fusion Score Chart
        const fusionCtx = document.getElementById('fusionChart').getContext('2d');
        new Chart(fusionCtx, {{
            type: 'line',
            data: {{
                datasets: [
                    {{
                        label: 'Fusion Score',
                        data: chartData.time.map((t, i) => ({{x: t, y: chartData.fusion_score.data[i]}})),
                        borderColor: colors.primary,
                        backgroundColor: colors.primary + '20',
                        borderWidth: 1.5,
                        fill: false,
                        pointRadius: 0,
                    }},
                    {{
                        label: 'Adaptive Threshold',
                        data: chartData.time.map((t, i) => ({{x: t, y: chartData.fusion_score.threshold[i]}})),
                        borderColor: colors.secondary,
                        backgroundColor: colors.secondary + '20',
                        borderWidth: 2,
                        borderDash: [5, 5],
                        fill: false,
                        pointRadius: 0,
                    }},
                    {{
                        label: 'Detected Events',
                        data: chartData.fusion_score.events.times.map((time, idx) => ({{
                            x: time,
                            y: chartData.fusion_score.events.scores[idx]
                        }})),
                        type: 'scatter',
                        backgroundColor: colors.warning,
                        borderColor: colors.warning,
                        pointRadius: 6,
                        pointHoverRadius: 8,
                    }},
                    {{
                        label: 'Missed Peaks',
                        data: chartData.fusion_score.missed_peaks && chartData.fusion_score.missed_peaks.times.length > 0 
                            ? chartData.fusion_score.missed_peaks.times.map((time, idx) => ({{
                                x: time,
                                y: chartData.fusion_score.missed_peaks.scores[idx]
                            }}))
                            : [],
                        type: 'scatter',
                        backgroundColor: '#000000',
                        borderColor: '#000000',
                        pointRadius: 4,
                        pointHoverRadius: 6,
                        pointStyle: 'triangle',
                    }}
                ]
            }},
            options: {{
                ...commonOptions,
                plugins: {{
                    ...commonOptions.plugins,
                    title: {{
                        display: true,
                        text: 'Fusion Score and Adaptive Threshold'
                    }}
                }},
                scales: {{
                    ...commonOptions.scales,
                    y: {{
                        ...commonOptions.scales.y,
                        title: {{
                            display: true,
                            text: 'Score'
                        }}
                    }}
                }}
            }}
        }});
        
        // Inter-Arrival Time Chart
        const interArrivalCtx = document.getElementById('interArrivalChart').getContext('2d');
        new Chart(interArrivalCtx, {{
            type: 'line',
            data: {{
                labels: chartData.inter_arrival.times,
                datasets: [
                    {{
                        label: 'Inter-Arrival Times',
                        data: chartData.inter_arrival.intervals,
                        borderColor: colors.primary,
                        backgroundColor: chartData.inter_arrival.types.map(type => 
                            type === 'detected' ? colors.success + '40' : '#00000040'
                        ),
                        pointBackgroundColor: chartData.inter_arrival.types.map(type => 
                            type === 'detected' ? colors.success : '#000000'
                        ),
                        pointBorderColor: chartData.inter_arrival.types.map(type => 
                            type === 'detected' ? colors.success : '#000000'
                        ),
                        borderWidth: 2,
                        fill: false,
                        pointRadius: 4,
                        pointHoverRadius: 6,
                    }}
                ]
            }},
            options: {{
                ...commonOptions,
                plugins: {{
                    ...commonOptions.plugins,
                    title: {{
                        display: true,
                        text: 'Inter-Arrival Times Between Peaks'
                    }},
                    legend: {{
                        display: true,
                        labels: {{
                            generateLabels: function(chart) {{
                                return [
                                    {{
                                        text: 'Detected Peak Intervals',
                                        fillStyle: colors.success,
                                        strokeStyle: colors.success,
                                        pointStyle: 'circle'
                                    }},
                                    {{
                                        text: 'Missed Peak Intervals', 
                                        fillStyle: '#000000',
                                        strokeStyle: '#000000',
                                        pointStyle: 'circle'
                                    }}
                                ];
                            }}
                        }}
                    }}
                }},
                scales: {{
                    ...commonOptions.scales,
                    x: {{
                        ...commonOptions.scales.x,
                        title: {{
                            display: true,
                            text: 'Peak Sequence #'
                        }}
                    }},
                    y: {{
                        ...commonOptions.scales.y,
                        title: {{
                            display: true,
                            text: 'Interval (ms)'
                        }},
                        beginAtZero: true
                    }}
                }}
            }}
        }});
        
        // Acceleration Chart
        const accCtx = document.getElementById('accelerationChart').getContext('2d');
        new Chart(accCtx, {{
            type: 'line',
            data: {{
                datasets: [
                    {{
                        label: chartData.acceleration.label,
                        data: chartData.time.map((t, i) => ({{x: t, y: chartData.acceleration.data[i]}})),
                        borderColor: colors.success,
                        backgroundColor: colors.success + '20',
                        borderWidth: 1,
                        fill: false,
                        pointRadius: 0,
                    }},
                    {{
                        label: 'Events',
                        data: chartData.acceleration.events.times.map((time, idx) => ({{
                            x: time,
                            y: chartData.acceleration.events.values[idx]
                        }})),
                        type: 'scatter',
                        backgroundColor: colors.warning,
                        borderColor: colors.warning,
                        pointRadius: 4,
                    }},
                    {{
                        label: 'Acceleration Gate',
                        data: chartData.time.map(t => ({{x: t, y: chartData.acceleration.gate}})),
                        borderColor: colors.danger,
                        backgroundColor: 'transparent',
                        borderWidth: 2,
                        borderDash: [5, 5],
                        fill: false,
                        pointRadius: 0,
                    }},
                    {{
                        label: '-Acceleration Gate',
                        data: chartData.time.map(t => ({{x: t, y: -chartData.acceleration.gate}})),
                        borderColor: colors.danger,
                        backgroundColor: 'transparent',
                        borderWidth: 2,
                        borderDash: [5, 5],
                        fill: false,
                        pointRadius: 0,
                    }}
                ]
            }},
            options: {{
                ...commonOptions,
                plugins: {{
                    ...commonOptions.plugins,
                    title: {{
                        display: true,
                        text: 'Acceleration Signal'
                    }}
                }},
                scales: {{
                    ...commonOptions.scales,
                    y: {{
                        ...commonOptions.scales.y,
                        title: {{
                            display: true,
                            text: 'Acceleration (g)'
                        }}
                    }}
                }}
            }}
        }});
        
        // Gyroscope Chart
        const gyroCtx = document.getElementById('gyroscopeChart').getContext('2d');
        new Chart(gyroCtx, {{
            type: 'line',
            data: {{
                datasets: [
                    {{
                        label: chartData.gyroscope.label,
                        data: chartData.time.map((t, i) => ({{x: t, y: chartData.gyroscope.data[i]}})),
                        borderColor: colors.accent,
                        backgroundColor: colors.accent + '20',
                        borderWidth: 1,
                        fill: false,
                        pointRadius: 0,
                    }},
                    {{
                        label: 'Events',
                        data: chartData.gyroscope.events.times.map((time, idx) => ({{
                            x: time,
                            y: chartData.gyroscope.events.values[idx]
                        }})),
                        type: 'scatter',
                        backgroundColor: colors.warning,
                        borderColor: colors.warning,
                        pointRadius: 4,
                    }},
                    {{
                        label: 'Gyroscope Gate',
                        data: chartData.time.map(t => ({{x: t, y: chartData.gyroscope.gate}})),
                        borderColor: colors.danger,
                        backgroundColor: 'transparent',
                        borderWidth: 2,
                        borderDash: [5, 5],
                        fill: false,
                        pointRadius: 0,
                    }},
                    {{
                        label: '-Gyroscope Gate',
                        data: chartData.time.map(t => ({{x: t, y: -chartData.gyroscope.gate}})),
                        borderColor: colors.danger,
                        backgroundColor: 'transparent',
                        borderWidth: 2,
                        borderDash: [5, 5],
                        fill: false,
                        pointRadius: 0,
                    }}
                ]
            }},
            options: {{
                ...commonOptions,
                plugins: {{
                    ...commonOptions.plugins,
                    title: {{
                        display: true,
                        text: 'Gyroscope Signal'
                    }}
                }},
                scales: {{
                    ...commonOptions.scales,
                    y: {{
                        ...commonOptions.scales.y,
                        title: {{
                            display: true,
                            text: 'Angular Rate (rad/s)'
                        }}
                    }}
                }}
            }}
        }});
        
        // Raw Acceleration Chart (3-axis)
        const rawAccCtx = document.getElementById('rawAccelerationChart').getContext('2d');
        new Chart(rawAccCtx, {{
            type: 'line',
            data: {{
                labels: chartData.time,
                datasets: [
                    {{
                        label: 'Acceleration X',
                        data: chartData.raw_data.acceleration.x,
                        borderColor: colors.primary,
                        borderWidth: 1,
                        fill: false,
                        pointRadius: 0,
                    }},
                    {{
                        label: 'Acceleration Y', 
                        data: chartData.raw_data.acceleration.y,
                        borderColor: colors.success,
                        borderWidth: 1,
                        fill: false,
                        pointRadius: 0,
                    }},
                    {{
                        label: 'Acceleration Z',
                        data: chartData.raw_data.acceleration.z,
                        borderColor: colors.warning,
                        borderWidth: 1,
                        fill: false,
                        pointRadius: 0,
                    }},
                    {{
                        label: 'Magnitude',
                        data: chartData.raw_data.acceleration.magnitude,
                        borderColor: colors.secondary,
                        borderWidth: 2,
                        fill: false,
                        pointRadius: 0,
                        borderDash: [3, 3],
                    }}
                ]
            }},
            options: {{
                ...commonOptions,
                plugins: {{
                    ...commonOptions.plugins,
                    title: {{
                        display: true,
                        text: 'Raw Acceleration Data (3-Axis + Magnitude)'
                    }}
                }},
                scales: {{
                    ...commonOptions.scales,
                    y: {{
                        ...commonOptions.scales.y,
                        title: {{
                            display: true,
                            text: 'Acceleration (g)'
                        }}
                    }}
                }}
            }}
        }});
        
        // Raw Gyroscope Chart (3-axis)
        const rawGyroCtx = document.getElementById('rawGyroscopeChart').getContext('2d');
        new Chart(rawGyroCtx, {{
            type: 'line',
            data: {{
                labels: chartData.time,
                datasets: [
                    {{
                        label: 'Gyroscope X',
                        data: chartData.raw_data.gyroscope.x,
                        borderColor: colors.primary,
                        borderWidth: 1,
                        fill: false,
                        pointRadius: 0,
                    }},
                    {{
                        label: 'Gyroscope Y',
                        data: chartData.raw_data.gyroscope.y,
                        borderColor: colors.success,
                        borderWidth: 1,
                        fill: false,
                        pointRadius: 0,
                    }},
                    {{
                        label: 'Gyroscope Z',
                        data: chartData.raw_data.gyroscope.z,
                        borderColor: colors.warning,
                        borderWidth: 1,
                        fill: false,
                        pointRadius: 0,
                    }},
                    {{
                        label: 'Magnitude',
                        data: chartData.raw_data.gyroscope.magnitude,
                        borderColor: colors.secondary,
                        borderWidth: 2,
                        fill: false,
                        pointRadius: 0,
                        borderDash: [3, 3],
                    }}
                ]
            }},
            options: {{
                ...commonOptions,
                plugins: {{
                    ...commonOptions.plugins,
                    title: {{
                        display: true,
                        text: 'Raw Gyroscope Data (3-Axis + Magnitude)'
                    }}
                }},
                scales: {{
                    ...commonOptions.scales,
                    y: {{
                        ...commonOptions.scales.y,
                        title: {{
                            display: true,
                            text: 'Angular Rate (rad/s)'
                        }}
                    }}
                }}
            }}
        }});
        
        // Component Analysis Charts (if available)
        {self._generate_components_js(chart_data, colors)}
        
        // Visual Debug Chart (if available)
        {self._generate_visual_debug_js(chart_data, colors)}
        """
    
    def _generate_components_js(self, chart_data: Dict[str, Any], colors: Dict[str, str]) -> str:
        """Generate JavaScript for component analysis charts."""
        if not chart_data['components']:
            return ""
            
        return f"""
        // Component Analysis Chart 1 (Acceleration components)
        const comp1Ctx = document.getElementById('componentsChart1').getContext('2d');
        new Chart(comp1Ctx, {{
            type: 'line',
            data: {{
                labels: chartData.time,
                datasets: [
                    {{
                        label: 'Z-score Acceleration',
                        data: chartData.components.z_a,
                        borderColor: colors.primary,
                        borderWidth: 1,
                        fill: false,
                        pointRadius: 0,
                    }},
                    {{
                        label: 'Z-score Acc Derivative',
                        data: chartData.components.z_da,
                        borderColor: colors.success,
                        borderWidth: 1,
                        fill: false,
                        pointRadius: 0,
                    }}
                ]
            }},
            options: {{
                ...commonOptions,
                plugins: {{
                    ...commonOptions.plugins,
                    title: {{
                        display: true,
                        text: 'Acceleration Components'
                    }}
                }},
                scales: {{
                    ...commonOptions.scales,
                    y: {{
                        ...commonOptions.scales.y,
                        title: {{
                            display: true,
                            text: 'Z-score'
                        }}
                    }}
                }}
            }}
        }});
        
        // Component Analysis Chart 2 (Gyroscope components)
        const comp2Ctx = document.getElementById('componentsChart2').getContext('2d');
        new Chart(comp2Ctx, {{
            type: 'line',
            data: {{
                labels: chartData.time,
                datasets: [
                    {{
                        label: 'Z-score Gyroscope',
                        data: chartData.components.z_g,
                        borderColor: colors.accent,
                        borderWidth: 1,
                        fill: false,
                        pointRadius: 0,
                    }},
                    {{
                        label: 'Z-score Gyro Derivative',
                        data: chartData.components.z_dg,
                        borderColor: colors.secondary,
                        borderWidth: 1,
                        fill: false,
                        pointRadius: 0,
                    }}
                ]
            }},
            options: {{
                ...commonOptions,
                plugins: {{
                    ...commonOptions.plugins,
                    title: {{
                        display: true,
                        text: 'Gyroscope Components'
                    }}
                }},
                scales: {{
                    ...commonOptions.scales,
                    y: {{
                        ...commonOptions.scales.y,
                        title: {{
                            display: true,
                            text: 'Z-score'
                        }}
                    }}
                }}
            }}
        }});
        """
    
    def _generate_visual_debug_js(self, chart_data: Dict[str, Any], colors: Dict[str, str]) -> str:
        """Generate JavaScript for visual debug chart."""
        if not chart_data.get('rejected_candidates'):
            return ""
        
        return f"""
        // Visual Debug Chart
        const visualDebugCtx = document.getElementById('visualDebugChart');
        if (visualDebugCtx && chartData.rejected_candidates) {{
            const rejectedColors = {{
                'refractory': '#ff6b6b',      // Red
                'not_peak': '#ffa500',        // Orange  
                'gates': '#ff69b4',           // Pink
                'min_iei': '#9370db'          // Purple
            }};
            
            const rejectedLabels = {{
                'refractory': 'Rejected: Refractory Period',
                'not_peak': 'Rejected: Not Local Peak', 
                'gates': 'Rejected: Gate Checks',
                'min_iei': 'Rejected: Min Inter-Event Interval'
            }};
            
            // Build datasets for visual debug chart
            const visualDebugDatasets = [
                // Fusion score line
                {{
                    label: 'Fusion Score',
                    data: chartData.fusion_score.data,
                    borderColor: colors.primary,
                    borderWidth: 2,
                    fill: false,
                    pointRadius: 0,
                    type: 'line'
                }},
                // Adaptive threshold line
                {{
                    label: 'Adaptive Threshold',
                    data: chartData.fusion_score.threshold,
                    borderColor: colors.secondary,
                    borderWidth: 1,
                    borderDash: [5, 5],
                    fill: false,
                    pointRadius: 0,
                    type: 'line'
                }},
                // Accepted events
                {{
                    label: 'Accepted Events',
                    data: chartData.fusion_score.events.times.map((time, idx) => ({{
                        x: time,
                        y: chartData.fusion_score.events.scores[idx]
                    }})),
                    backgroundColor: colors.success,
                    borderColor: colors.success,
                    pointRadius: 6,
                    pointHoverRadius: 8,
                    type: 'scatter',
                    showLine: false
                }},
                // Missed peaks
                {{
                    label: 'Missed Peaks',
                    data: chartData.fusion_score.missed_peaks && chartData.fusion_score.missed_peaks.times.length > 0 
                        ? chartData.fusion_score.missed_peaks.times.map((time, idx) => ({{
                            x: time,
                            y: chartData.fusion_score.missed_peaks.scores[idx]
                        }}))
                        : [],
                    backgroundColor: '#000000',
                    borderColor: '#000000',
                    pointRadius: 4,
                    pointHoverRadius: 6,
                    pointStyle: 'triangle',
                    type: 'scatter',
                    showLine: false
                }}
            ];
            
            // Add rejected candidate datasets
            Object.keys(chartData.rejected_candidates).forEach(category => {{
                const rejected = chartData.rejected_candidates[category];
                if (rejected.times && rejected.times.length > 0) {{
                    visualDebugDatasets.push({{
                        label: rejectedLabels[category],
                        data: rejected.times.map((time, idx) => ({{
                            x: time,
                            y: rejected.scores[idx]
                        }})),
                        backgroundColor: rejectedColors[category],
                        borderColor: rejectedColors[category],
                        pointRadius: 4,
                        pointHoverRadius: 6,
                        type: 'scatter',
                        showLine: false
                    }});
                }}
            }});
            
            new Chart(visualDebugCtx, {{
                type: 'line',
                data: {{
                    labels: chartData.time,
                    datasets: visualDebugDatasets
                }},
                options: {{
                    ...commonOptions,
                    plugins: {{
                        ...commonOptions.plugins,
                        title: {{
                            display: true,
                            text: 'Visual Debug: Fusion Score with Rejected Candidates'
                        }},
                        legend: {{
                            display: true,
                            position: 'top'
                        }}
                    }},
                    scales: {{
                        ...commonOptions.scales,
                        y: {{
                            ...commonOptions.scales.y,
                            title: {{
                                display: true,
                                text: 'Fusion Score'
                            }}
                        }}
                    }}
                }}
            }});
        }}
        """
    
    def _generate_debug_sections(self, debug_results: Dict[str, Any]) -> str:
        """Generate debug sections for detection and threshold analysis."""
        if not debug_results:
            return ""
        
        sections = []
        
        # Detection debug section
        if 'detection' in debug_results:
            detection_html = self._generate_detection_debug_html(debug_results['detection'])
            sections.append(detection_html)
        
        # Threshold debug section
        if 'threshold' in debug_results:
            threshold_html = self._generate_threshold_debug_html(debug_results['threshold'])
            sections.append(threshold_html)
        
        if sections:
            return f"""
            <div class="section">
                <h2>🔍 Debug Analysis</h2>
                {''.join(sections)}
            </div>
            """
        return ""
    
    def _generate_detection_debug_html(self, detection_results: Dict[str, Any]) -> str:
        """Generate HTML for detection debug results."""
        if not detection_results or 'rejection_stats' not in detection_results:
            return ""
        
        stats = detection_results.get('rejection_stats', {})
        total_rejected = stats.get('total_rejected', 0)
        candidates = detection_results.get('candidates', 0)
        final_events = detection_results.get('final_events', 0)
        
        # Build rejection breakdown
        rejection_rows = []
        for key, count in stats.items():
            if key.startswith('rejected_') and count > 0:
                reason = key.replace('rejected_', '').replace('_', ' ').title()
                pct = 100 * count / candidates if candidates > 0 else 0
                rejection_rows.append(f"<tr><td>{reason}</td><td>{count}</td><td>{pct:.1f}%</td></tr>")
        
        # Top rejected examples
        rejected_examples = []
        if 'rejected_details' in detection_results:
            for detail in detection_results['rejected_details'][:5]:  # Show top 5
                rejected_examples.append(
                    f"<tr><td>{detail['time']:.2f}s</td><td>{detail['score']:.2f}</td><td>{detail['reason']}</td></tr>"
                )
        
        return f"""
        <div class="debug-subsection">
            <h3>📊 Detection Analysis</h3>
            <div class="debug-stats">
                <div class="stat-item">
                    <span class="stat-label">Total Candidates:</span>
                    <span class="stat-value">{candidates}</span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">Accepted Events:</span>
                    <span class="stat-value">{final_events}</span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">Total Rejected:</span>
                    <span class="stat-value">{total_rejected}</span>
                </div>
            </div>
            
            {'<div class="debug-table-container"><h4>Rejection Breakdown</h4><table class="debug-table"><tr><th>Reason</th><th>Count</th><th>Percentage</th></tr>' + ''.join(rejection_rows) + '</table></div>' if rejection_rows else ''}
            
            {'<div class="debug-table-container"><h4>Top Rejected Candidates</h4><table class="debug-table"><tr><th>Time</th><th>Score</th><th>Reason</th></tr>' + ''.join(rejected_examples) + '</table></div>' if rejected_examples else ''}
        </div>
        """
    
    def _generate_threshold_debug_html(self, threshold_results: Dict[str, Any]) -> str:
        """Generate HTML for threshold debug results."""
        if not threshold_results:
            return ""
        
        # Extract stats from threshold results
        missed_peaks = threshold_results.get('missed_peaks', [])
        stats = threshold_results.get('stats', {})
        
        # Build missed peaks table
        missed_peaks_rows = []
        for peak in missed_peaks[:10]:  # Show top 10
            margin = peak['score'] - peak['threshold']
            pct_below = abs(margin) / peak['threshold'] * 100
            reason = f"{margin:.2f} below ({pct_below:.1f}%)"
            missed_peaks_rows.append(
                f"<tr><td>{peak['time']:.2f}s</td><td>{peak['score']:.2f}</td><td>{peak['threshold']:.2f}</td><td>{reason}</td></tr>"
            )
        
        return f"""
        <div class="debug-subsection">
            <h3>📉 Threshold Analysis</h3>
            <div class="debug-stats">
                <div class="stat-item">
                    <span class="stat-label">Total Peaks:</span>
                    <span class="stat-value">{threshold_results.get('all_peaks', 0)}</span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">Peaks Above Threshold:</span>
                    <span class="stat-value">{threshold_results.get('above_threshold', 0)}</span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">Missed Peaks:</span>
                    <span class="stat-value">{len(missed_peaks)}</span>
                </div>
            </div>
            
            {'<div class="debug-table-container"><h4>Missed Peak Details</h4><table class="debug-table"><tr><th>Time</th><th>Score</th><th>Threshold</th><th>Reason</th></tr>' + ''.join(missed_peaks_rows) + '</table></div>' if missed_peaks_rows else '<p>No missed peaks to analyze.</p>'}
        </div>
        """
    
    def _generate_visual_debug_section(self, chart_data: Dict[str, Any]) -> str:
        """Generate visual debug plot section with rejected candidates."""
        if not chart_data.get('rejected_candidates'):
            return ""
        
        rejected = chart_data['rejected_candidates']
        
        # Count rejected candidates by category
        rejection_counts = []
        category_labels = {
            'refractory': 'Refractory Period',
            'not_peak': 'Not Local Peak', 
            'gates': 'Gate Checks',
            'min_iei': 'Min Inter-Event Interval'
        }
        
        total_rejected = 0
        for category, data in rejected.items():
            count = len(data['times']) if data['times'] else 0
            total_rejected += count
            if count > 0:
                rejection_counts.append((category_labels.get(category, category), count))
        
        rejection_summary = ' • '.join([f"{label}: {count}" for label, count in rejection_counts])
        
        return f"""
        <div class="section">
            <h2>📈 Visual Debug Plot</h2>
            <div class="visual-debug-summary">
                <p><strong>Rejected Candidates:</strong> {rejection_summary} (Total: {total_rejected})</p>
                <p><em>This plot shows all rejected candidates color-coded by rejection reason overlaid on the fusion score.</em></p>
            </div>
            <div class="chart-container">
                <canvas id="visualDebugChart"></canvas>
            </div>
        </div>
        """