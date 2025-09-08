import Foundation
import SwiftUI

// MARK: - HTML Report Generator

class TKEOHTMLReportGenerator {
    
    /// Generate complete HTML report with embedded assets
    static func generateHTMLReport(
        from exportData: TKEOAnalysisExport,
        chartImages: [String: Data] = [:],
        options: TKEOExportOptions = .default
    ) -> String {
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>TKEO Analysis Report - Session \(exportData.sessionMetadata.sessionId.prefix(8))</title>
            \(generateCSS())
            \(generateJavaScript())
        </head>
        <body>
            <div class="container">
                \(generateHeader(from: exportData))
                \(generateSessionSummary(from: exportData))
                \(generateConfigurationSection(from: exportData))
                \(generateResultsSection(from: exportData))
                \(generateVisualizationSection(chartImages: chartImages))
                \(options.includeRawData ? generateRawDataSection(from: exportData) : "")
                \(options.includeDebugLogs ? generateDebugSection(from: exportData) : "")
                \(generateFooter(from: exportData))
            </div>
        </body>
        </html>
        """
        
        return html
    }
    
    // MARK: - HTML Sections
    
    private static func generateHeader(from exportData: TKEOAnalysisExport) -> String {
        let sessionId = exportData.sessionMetadata.sessionId.prefix(8)
        let date = DateFormatter.mediumDateTime.string(from: exportData.sessionMetadata.startTime)
        
        return """
        <header class="header">
            <div class="header-content">
                <div class="title-section">
                    <h1>🧿 TKEO Pinch Detection Analysis</h1>
                    <h2>Session \(sessionId)</h2>
                    <p class="subtitle">\(date) • \(String(format: "%.1f", exportData.sessionMetadata.duration))s duration</p>
                </div>
                <div class="logo-section">
                    <div class="app-logo">📊</div>
                </div>
            </div>
        </header>
        """
    }
    
    private static func generateSessionSummary(from exportData: TKEOAnalysisExport) -> String {
        let metadata = exportData.sessionMetadata
        let results = exportData.analysisResults
        
        // Check if actual pinch count exists
        let hasActualCount = metadata.actualPinchCount != nil && metadata.actualPinchCount! > 0
        let totalEventsText = hasActualCount ? "\(metadata.totalPinches)" : "No Actual Pinch count"
        let accuracyText = hasActualCount ? 
            String(format: "%.1f", Double(metadata.detectedPinches) / Double(metadata.totalPinches) * 100) + "%" : "N/A"
        let accuracyClass = hasActualCount ? 
            (Double(metadata.detectedPinches) / Double(metadata.totalPinches) * 100 >= 80 ? "success" : 
             Double(metadata.detectedPinches) / Double(metadata.totalPinches) * 100 >= 60 ? "warning" : "error") : ""
        
        return """
        <section class="summary-section">
            <h2>📋 Session Summary</h2>
            <div class="summary-grid">
                <div class="summary-card">
                    <div class="card-icon">🎯</div>
                    <div class="card-content">
                        <h3>Detection Results</h3>
                        <div class="metric-row">
                            <span class="metric-label">Total Events:</span>
                            <span class="metric-value">\(totalEventsText)</span>
                        </div>
                        <div class="metric-row">
                            <span class="metric-label">Detected:</span>
                            <span class="metric-value success">\(metadata.detectedPinches)</span>
                        </div>
                        <div class="metric-row">
                            <span class="metric-label">Accuracy:</span>
                            <span class="metric-value \(accuracyClass)">\(accuracyText)</span>
                        </div>
                    </div>
                </div>
                
                <div class="summary-card">
                    <div class="card-icon">⚡</div>
                    <div class="card-content">
                        <h3>Algorithm Performance</h3>
                        <div class="metric-row">
                            <span class="metric-label">Gate Events:</span>
                            <span class="metric-value">\(results.performanceMetrics.gateStageDetections)</span>
                        </div>
                        <div class="metric-row">
                            <span class="metric-label">Final Events:</span>
                            <span class="metric-value">\(results.performanceMetrics.finalDetections)</span>
                        </div>
                        <div class="metric-row">
                            <span class="metric-label">Processing:</span>
                            <span class="metric-value">\(String(format: "%.1f", results.performanceMetrics.processingTimeMs))ms</span>
                        </div>
                    </div>
                </div>
                
                <div class="summary-card">
                    <div class="card-icon">📱</div>
                    <div class="card-content">
                        <h3>Device Information</h3>
                        <div class="metric-row">
                            <span class="metric-label">Device:</span>
                            <span class="metric-value">\(metadata.deviceInfo.deviceModel)</span>
                        </div>
                        <div class="metric-row">
                            <span class="metric-label">System:</span>
                            <span class="metric-value">\(metadata.deviceInfo.systemVersion)</span>
                        </div>
                        <div class="metric-row">
                            <span class="metric-label">Sample Rate:</span>
                            <span class="metric-value">\(String(format: "%.0f", metadata.deviceInfo.samplingRate))Hz</span>
                        </div>
                    </div>
                </div>
            </div>
        </section>
        """
    }
    
    private static func generateConfigurationSection(from exportData: TKEOAnalysisExport) -> String {
        let config = exportData.algorithmConfiguration
        
        return """
        <section class="config-section">
            <h2>⚙️ Algorithm Configuration</h2>
            <div class="config-grid">
                <div class="config-group">
                    <h3>TKEO Parameters</h3>
                    <table class="config-table">
                        <tr><td>Sample Rate</td><td>\(config.tkeoParams.sampleRate)Hz</td></tr>
                        <tr><td>Accel Weight</td><td>\(config.tkeoParams.accelWeight)</td></tr>
                        <tr><td>Gyro Weight</td><td>\(config.tkeoParams.gyroWeight)</td></tr>
                        <tr><td>Gate Threshold</td><td>\(config.tkeoParams.gateThreshold)</td></tr>
                        <tr><td>Refractory Period</td><td>\(config.tkeoParams.refractoryPeriodMs)ms</td></tr>
                    </table>
                </div>
                
                <div class="config-group">
                    <h3>Filter Settings</h3>
                    <table class="config-table">
                        <tr><td>Bandpass Low</td><td>\(config.filterSettings.bandpassLow)Hz</td></tr>
                        <tr><td>Bandpass High</td><td>\(config.filterSettings.bandpassHigh)Hz</td></tr>
                        <tr><td>Filter Type</td><td>\(config.filterSettings.filterType)</td></tr>
                    </table>
                </div>
                
                <div class="config-group">
                    <h3>Template Matching</h3>
                    <table class="config-table">
                        <tr><td>NCC Threshold</td><td>\(config.templateParams.nccThreshold)</td></tr>
                        <tr><td>Window Pre</td><td>\(config.templateParams.windowPreMs)ms</td></tr>
                        <tr><td>Window Post</td><td>\(config.templateParams.windowPostMs)ms</td></tr>
                        <tr><td>Templates</td><td>\(config.templateParams.templateCount)</td></tr>
                    </table>
                </div>
            </div>
        </section>
        """
    }
    
    private static func generateResultsSection(from exportData: TKEOAnalysisExport) -> String {
        let results = exportData.analysisResults
        let events = results.detectedEvents
        
        let eventsTable = events.isEmpty ? 
            "<p class='no-data'>No pinch events detected in this session.</p>" :
            """
            <div class="table-container">
                <table class="results-table">
                    <thead>
                        <tr>
                            <th>Event ID</th>
                            <th>Peak Time</th>
                            <th>Duration</th>
                            <th>Confidence</th>
                            <th>Gate Score</th>
                            <th>NCC Score</th>
                            <th>Verified</th>
                        </tr>
                    </thead>
                    <tbody>
                        \(events.map { event in
                            let duration = event.tEnd - event.tStart
                            return """
                            <tr class="\(event.isVerified ? "verified" : "unverified")">
                                <td>\(event.eventId.prefix(8))</td>
                                <td>\(String(format: "%.3f", event.tPeak))s</td>
                                <td>\(String(format: "%.0f", duration * 1000))ms</td>
                                <td>\(String(format: "%.2f", event.confidence))</td>
                                <td>\(String(format: "%.2f", event.gateScore))</td>
                                <td>\(String(format: "%.2f", event.nccScore))</td>
                                <td>\(event.isVerified ? "✅" : "❌")</td>
                            </tr>
                            """
                        }.joined())
                    </tbody>
                </table>
            </div>
            """
        
        return """
        <section class="results-section">
            <h2>📈 Detection Results</h2>
            <div class="results-summary">
                <div class="result-metric">
                    <span class="metric-label">Gate Events:</span>
                    <span class="metric-value">\(results.performanceMetrics.gateStageDetections)</span>
                </div>
                <div class="result-metric">
                    <span class="metric-label">Verified Events:</span>
                    <span class="metric-value success">\(events.filter { $0.isVerified }.count)</span>
                </div>
                <div class="result-metric">
                    <span class="metric-label">Rejection Rate:</span>
                    <span class="metric-value">\(String(format: "%.1f", results.performanceMetrics.rejectionRate * 100))%</span>
                </div>
            </div>
            \(eventsTable)
        </section>
        """
    }
    
    private static func generateVisualizationSection(chartImages: [String: Data]) -> String {
        var chartsHTML = ""
        
        for (chartName, imageData) in chartImages {
            let base64Image = imageData.base64EncodedString()
            chartsHTML += """
            <div class="chart-container">
                <h3>\(chartName.capitalized) Plot</h3>
                <img src="data:image/png;base64,\(base64Image)" alt="\(chartName) Chart" class="chart-image" onclick="openFullscreen(this)">
            </div>
            """
        }
        
        if chartsHTML.isEmpty {
            chartsHTML = "<p class='no-data'>No chart visualizations available.</p>"
        }
        
        return """
        <section class="visualization-section">
            <h2>📊 Signal Analysis Plots</h2>
            <div class="charts-grid">
                \(chartsHTML)
            </div>
        </section>
        """
    }
    
    private static func generateRawDataSection(from exportData: TKEOAnalysisExport) -> String {
        let rawData = exportData.rawData
        let sampleCount = rawData.sensorReadings.count
        let qualityMetrics = rawData.dataQualityMetrics
        
        return """
        <section class="raw-data-section">
            <h2>📊 Raw Data Summary</h2>
            <div class="data-quality">
                <h3>Data Quality Metrics</h3>
                <table class="config-table">
                    <tr><td>Total Samples</td><td>\(qualityMetrics.totalSamples)</td></tr>
                    <tr><td>Completeness</td><td>\(String(format: "%.1f", qualityMetrics.dataCompletenessPercent))%</td></tr>
                    <tr><td>Dropped Samples</td><td>\(qualityMetrics.droppedSamples)</td></tr>
                    <tr><td>Sampling Stability</td><td>\(String(format: "%.3f", qualityMetrics.samplingRateStability))</td></tr>
                </table>
            </div>
            
            <div class="sample-preview">
                <h3>Sample Data Preview (First 10 readings)</h3>
                <div class="table-container">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Time (s)</th>
                                <th>Accel X</th>
                                <th>Accel Y</th>
                                <th>Accel Z</th>
                                <th>Gyro X</th>
                                <th>Gyro Y</th>
                                <th>Gyro Z</th>
                            </tr>
                        </thead>
                        <tbody>
                            \(rawData.sensorReadings.prefix(10).map { reading in
                                """
                                <tr>
                                    <td>\(String(format: "%.3f", reading.timestamp))</td>
                                    <td>\(String(format: "%.3f", reading.accelerationX))</td>
                                    <td>\(String(format: "%.3f", reading.accelerationY))</td>
                                    <td>\(String(format: "%.3f", reading.accelerationZ))</td>
                                    <td>\(String(format: "%.3f", reading.rotationX))</td>
                                    <td>\(String(format: "%.3f", reading.rotationY))</td>
                                    <td>\(String(format: "%.3f", reading.rotationZ))</td>
                                </tr>
                                """
                            }.joined())
                        </tbody>
                    </table>
                </div>
            </div>
        </section>
        """
    }
    
    private static func generateDebugSection(from exportData: TKEOAnalysisExport) -> String {
        let debugInfo = exportData.debugInformation
        let logs = debugInfo.processingLogs.prefix(50) // Limit to 50 most recent logs
        
        return """
        <section class="debug-section">
            <h2>🔍 Debug Information</h2>
            <div class="debug-logs">
                <h3>Processing Logs</h3>
                <div class="log-container">
                    \(logs.enumerated().map { (index, log) in
                        "<div class='log-entry'><span class='log-number'>\(index + 1).</span> \(log.htmlEscaped)</div>"
                    }.joined())
                </div>
            </div>
            
            \(debugInfo.templateMatchingDetails.isEmpty ? "" : """
            <div class="template-matching">
                <h3>Template Matching Details</h3>
                <div class="table-container">
                    <table class="debug-table">
                        <thead>
                            <tr>
                                <th>Template</th>
                                <th>Event Time</th>
                                <th>NCC Score</th>
                                <th>Window</th>
                                <th>Matched</th>
                            </tr>
                        </thead>
                        <tbody>
                            \(debugInfo.templateMatchingDetails.map { result in
                                """
                                <tr class="\(result.matched ? "matched" : "unmatched")">
                                    <td>\(result.templateIndex)</td>
                                    <td>\(String(format: "%.3f", result.eventTimestamp))s</td>
                                    <td>\(String(format: "%.3f", result.nccScore))</td>
                                    <td>\(String(format: "%.3f", result.windowStart))-\(String(format: "%.3f", result.windowEnd))s</td>
                                    <td>\(result.matched ? "✅" : "❌")</td>
                                </tr>
                                """
                            }.joined())
                        </tbody>
                    </table>
                </div>
            </div>
            """)
        </section>
        """
    }
    
    private static func generateFooter(from exportData: TKEOAnalysisExport) -> String {
        let exportDate = DateFormatter.mediumDateTime.string(from: exportData.exportMetadata.exportDate)
        
        return """
        <footer class="footer">
            <div class="footer-content">
                <div class="footer-info">
                    <p>Generated by Dhikr Counter v\(exportData.sessionMetadata.deviceInfo.appVersion)</p>
                    <p>Export Date: \(exportDate)</p>
                    <p>Report Version: \(exportData.exportMetadata.exportVersion)</p>
                </div>
                <div class="footer-logo">
                    <p>🧿 Advanced TKEO Signal Processing</p>
                </div>
            </div>
        </footer>
        """
    }
    
    // MARK: - CSS Styles
    
    private static func generateCSS() -> String {
        return """
        <style>
        :root {
            --primary-color: #007AFF;
            --secondary-color: #5856D6;
            --success-color: #34C759;
            --warning-color: #FF9500;
            --error-color: #FF3B30;
            --background-color: #F2F2F7;
            --card-background: #FFFFFF;
            --text-primary: #000000;
            --text-secondary: #8E8E93;
            --border-color: #E5E5EA;
            --shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background-color: var(--background-color);
            color: var(--text-primary);
            line-height: 1.6;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
            color: white;
            padding: 2rem;
            border-radius: 16px;
            margin-bottom: 2rem;
            box-shadow: var(--shadow);
        }
        
        .header-content {
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .title-section h1 {
            font-size: 2.5rem;
            font-weight: 700;
            margin-bottom: 0.5rem;
        }
        
        .title-section h2 {
            font-size: 1.5rem;
            font-weight: 500;
            opacity: 0.9;
        }
        
        .subtitle {
            font-size: 1rem;
            opacity: 0.8;
            margin-top: 0.5rem;
        }
        
        .app-logo {
            font-size: 4rem;
            opacity: 0.8;
        }
        
        section {
            background: var(--card-background);
            border-radius: 16px;
            padding: 1.5rem;
            margin-bottom: 1.5rem;
            box-shadow: var(--shadow);
        }
        
        section h2 {
            font-size: 1.5rem;
            font-weight: 600;
            margin-bottom: 1rem;
            color: var(--text-primary);
        }
        
        section h3 {
            font-size: 1.25rem;
            font-weight: 600;
            margin-bottom: 0.75rem;
            color: var(--text-primary);
        }
        
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1rem;
        }
        
        .summary-card {
            background: var(--background-color);
            border-radius: 12px;
            padding: 1.5rem;
            display: flex;
            align-items: flex-start;
            gap: 1rem;
        }
        
        .card-icon {
            font-size: 2rem;
            flex-shrink: 0;
        }
        
        .card-content {
            flex: 1;
        }
        
        .metric-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0.25rem 0;
        }
        
        .metric-label {
            color: var(--text-secondary);
        }
        
        .metric-value {
            font-weight: 600;
        }
        
        .metric-value.success { color: var(--success-color); }
        .metric-value.warning { color: var(--warning-color); }
        .metric-value.error { color: var(--error-color); }
        
        .config-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 1.5rem;
        }
        
        .config-group {
            background: var(--background-color);
            border-radius: 12px;
            padding: 1rem;
        }
        
        .config-table, .results-table, .data-table, .debug-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 0.5rem;
        }
        
        .config-table th, .config-table td,
        .results-table th, .results-table td,
        .data-table th, .data-table td,
        .debug-table th, .debug-table td {
            padding: 0.5rem;
            text-align: left;
            border-bottom: 1px solid var(--border-color);
        }
        
        .results-table th, .data-table th, .debug-table th {
            background: var(--background-color);
            font-weight: 600;
        }
        
        .results-table tr.verified { background: rgba(52, 199, 89, 0.1); }
        .results-table tr.unverified { background: rgba(255, 149, 0, 0.1); }
        
        .debug-table tr.matched { background: rgba(52, 199, 89, 0.1); }
        .debug-table tr.unmatched { background: rgba(255, 59, 48, 0.1); }
        
        .table-container {
            overflow-x: auto;
            border-radius: 8px;
            border: 1px solid var(--border-color);
        }
        
        .charts-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 1.5rem;
        }
        
        .chart-container {
            text-align: center;
        }
        
        .chart-image {
            width: 100%;
            max-width: 600px;
            height: auto;
            border-radius: 8px;
            border: 1px solid var(--border-color);
            cursor: pointer;
            transition: transform 0.2s ease;
        }
        
        .chart-image:hover {
            transform: scale(1.02);
        }
        
        .log-container {
            background: #1E1E1E;
            color: #FFFFFF;
            border-radius: 8px;
            padding: 1rem;
            max-height: 400px;
            overflow-y: auto;
            font-family: 'Monaco', 'Menlo', monospace;
            font-size: 0.875rem;
        }
        
        .log-entry {
            margin-bottom: 0.25rem;
            word-break: break-all;
        }
        
        .log-number {
            color: var(--secondary-color);
            font-weight: 600;
            margin-right: 0.5rem;
        }
        
        .no-data {
            color: var(--text-secondary);
            font-style: italic;
            text-align: center;
            padding: 2rem;
        }
        
        .footer {
            background: var(--background-color);
            border-radius: 12px;
            padding: 1.5rem;
            margin-top: 2rem;
            text-align: center;
        }
        
        .footer-content {
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .footer-info {
            color: var(--text-secondary);
            font-size: 0.875rem;
        }
        
        .footer-logo {
            font-size: 1.25rem;
            opacity: 0.8;
        }
        
        @media (max-width: 768px) {
            .container { padding: 1rem; }
            .header-content { flex-direction: column; gap: 1rem; }
            .footer-content { flex-direction: column; gap: 1rem; }
            .summary-grid { grid-template-columns: 1fr; }
            .config-grid { grid-template-columns: 1fr; }
            .charts-grid { grid-template-columns: 1fr; }
        }
        
        @media print {
            .header { background: var(--primary-color) !important; }
            .chart-image { max-height: 300px; }
            .log-container { max-height: 200px; }
        }
        </style>
        """
    }
    
    // MARK: - JavaScript
    
    private static func generateJavaScript() -> String {
        return """
        <script>
        function openFullscreen(img) {
            const modal = document.createElement('div');
            modal.style.cssText = `
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background: rgba(0, 0, 0, 0.9);
                display: flex;
                justify-content: center;
                align-items: center;
                z-index: 1000;
                cursor: pointer;
            `;
            
            const fullImg = document.createElement('img');
            fullImg.src = img.src;
            fullImg.style.cssText = `
                max-width: 95%;
                max-height: 95%;
                object-fit: contain;
                border-radius: 8px;
            `;
            
            modal.appendChild(fullImg);
            document.body.appendChild(modal);
            
            modal.onclick = function() {
                document.body.removeChild(modal);
            };
        }
        
        // Add smooth scrolling for hash links
        document.addEventListener('DOMContentLoaded', function() {
            const links = document.querySelectorAll('a[href^="#"]');
            links.forEach(link => {
                link.addEventListener('click', function(e) {
                    e.preventDefault();
                    const target = document.querySelector(this.getAttribute('href'));
                    if (target) {
                        target.scrollIntoView({ behavior: 'smooth' });
                    }
                });
            });
        });
        </script>
        """
    }
}

// MARK: - Helper Extensions

extension DateFormatter {
    static let mediumDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

extension String {
    var htmlEscaped: String {
        return self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#x27;")
    }
}