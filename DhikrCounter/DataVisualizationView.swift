import SwiftUI
import Charts

struct DataVisualizationView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            VStack {
                // Tab picker
                Picker("Visualization Type", selection: $selectedTab) {
                    Text("Sessions").tag(0)
                    Text("Sensor Data").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content based on selection
                switch selectedTab {
                case 0:
                    TimelineVisualizationView()
                case 1:
                    SensorDataDetailView()
                default:
                    TimelineVisualizationView()
                }
            }
            .navigationTitle("Data Analysis")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct TimelineVisualizationView: View {
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Recent sensor data display
                RecentSensorDataView()
                
                // Detection events list
                DetectionEventsListView()
                
                // Raw sensor data stats
                SensorDataStatsView()
            }
            .padding()
        }
    }
}

struct RecentSensorDataView: View {
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Sensor Data")
                .font(.headline)
                .fontWeight(.semibold)
            
            if dataManager.receivedSessions.isEmpty {
                VStack(spacing: 8) {
                    Text("No sensor data received")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Start a session on your Apple Watch and tap Stop to see sensor data here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(dataManager.receivedSessions.sorted(by: { $0.startTime > $1.startTime }).prefix(3)) { session in
                        SensorSessionRowView(session: session)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

struct SensorSessionRowView: View {
    let session: DhikrSession
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    
    var body: some View {
        NavigationLink(destination: SessionDetailView(session: session)) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session \(session.id.uuidString.prefix(8))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(DateFormatter.sessionFormatter.string(from: session.startTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let notes = session.sessionNotes, notes.contains("sensor readings") {
                        let readingCount = notes.split(separator: " ").first(where: { $0.allSatisfy { $0.isNumber } }) ?? "0"
                        Text("\(readingCount) sensor readings")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    // Show if sensor data is available
                    if dataManager.hasSensorData(for: session.id.uuidString) {
                        Text("📊 Raw data available")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct SensorDataStatsView: View {
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sensor Data Statistics")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                StatCard(title: "Sessions Received", value: "\(dataManager.receivedSessions.count)", color: .blue)
                StatCard(title: "Transfer Status", value: dataManager.isWatchConnected ? "Connected" : "Disconnected", color: dataManager.isWatchConnected ? .green : .orange)
                StatCard(title: "Last Transfer", value: dataManager.receivedSessions.isEmpty ? "None" : "Recently", color: .purple)
                StatCard(title: "Debug Messages", value: "\(dataManager.debugMessages.count)", color: .gray)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

struct DetectionEventsListView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Raw Data Mode")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                Text("Detection disabled - collecting raw sensor data only")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("The Watch app is configured to send raw accelerometer and gyroscope readings for research analysis")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

struct AnalysisVisualizationView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Performance metrics
                PerformanceMetricsView()
                
                // Algorithm analysis
                AlgorithmAnalysisView()
                
                // Session comparison
                SessionComparisonView()
            }
            .padding()
        }
    }
}

struct PerformanceMetricsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Algorithm Performance")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                MetricCard(title: "Detection Accuracy", value: "N/A", target: "85-90%", color: .blue)
                MetricCard(title: "False Positive Rate", value: "N/A", target: "<10%", color: .red)
                MetricCard(title: "Response Latency", value: "N/A", target: "<200ms", color: .green)
                MetricCard(title: "Battery Impact", value: "N/A", target: "<5%/hr", color: .orange)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let target: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text("Target: \(target)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct AlgorithmAnalysisView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Detection Algorithm Analysis")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                AlgorithmParameterRow(name: "Accelerometer Threshold", current: "0.05g", optimal: "TBD")
                AlgorithmParameterRow(name: "Gyroscope Threshold", current: "0.18 rad/s", optimal: "TBD")
                AlgorithmParameterRow(name: "Activity Threshold", current: "2.5", optimal: "TBD")
                AlgorithmParameterRow(name: "Refractory Period", current: "250ms", optimal: "TBD")
            }
            
            Text("Parameter optimization based on real session data coming in Phase 4")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

struct AlgorithmParameterRow: View {
    let name: String
    let current: String
    let optimal: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Text("Current: \(current)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("Optimal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(optimal)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct SessionComparisonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Comparison")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                Text("No sessions available for comparison")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("A/B testing and session comparison tools coming in Phase 3")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}


// MARK: - Preview

// MARK: - New Views

struct SensorDataDetailView: View {
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if dataManager.receivedSessions.isEmpty {
                    EmptyStateView(title: "No Sensor Data", 
                                 message: "Transfer a session from your Apple Watch to view detailed sensor readings")
                } else {
                    ForEach(dataManager.receivedSessions.sorted(by: { $0.startTime > $1.startTime })) { session in
                        SensorDataSessionCard(session: session)
                    }
                }
            }
            .padding()
        }
    }
}

struct SensorDataSessionCard: View {
    let session: DhikrSession
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session \(session.id.uuidString.prefix(8))")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if dataManager.hasSensorData(for: session.id.uuidString) {
                    NavigationLink(destination: SessionDetailView(session: session)) {
                        Text("View Data")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            
            Text(DateFormatter.sessionFormatter.string(from: session.startTime))
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if let sensorData = dataManager.getSensorData(for: session.id.uuidString) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                    StatCard(title: "Sensor Readings", value: "\(sensorData.count)", color: .blue)
                    StatCard(title: "Duration", value: String(format: "%.1fs", session.sessionDuration), color: .green)
                    StatCard(title: "Sample Rate", value: "100 Hz", color: .orange)
                    StatCard(title: "File Size", value: "\(Int(Double(sensorData.count) * 0.25))KB", color: .purple)
                }
            } else {
                Text("No sensor data available for this session")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

struct SessionDetailView: View {
    let session: DhikrSession
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    @State private var showingExportSheet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Session overview
                SessionOverviewCard(session: session)
                
                // Sensor data preview
                if let sensorData = dataManager.getSensorData(for: session.id.uuidString) {
                    SensorDataPreviewCard(sensorData: sensorData)
                    
                    // Export button
                    Button(action: { showingExportSheet = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Session Data")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }
            }
            .padding()
        }
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExportSheet) {
            SessionExportView(session: session)
        }
    }
}

struct SessionOverviewCard: View {
    let session: DhikrSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Overview")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                OverviewItem(title: "Session ID", value: session.id.uuidString.prefix(8).description)
                OverviewItem(title: "Start Time", value: DateFormatter.sessionFormatter.string(from: session.startTime))
                OverviewItem(title: "Duration", value: String(format: "%.1fs", session.sessionDuration))
                OverviewItem(title: "Status", value: "Completed")
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

struct OverviewItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct SensorDataPreviewCard: View {
    let sensorData: [SensorReading]
    @State private var selectedAccelerationMetric: AccelerationMetric = .allAxes
    @State private var selectedRotationMetric: RotationMetric = .allAxes
    
    enum AccelerationMetric: String, CaseIterable {
        case allAxes = "All Axes"
        case magnitude = "Magnitude"
        case xAxis = "X Axis"
        case yAxis = "Y Axis"
        case zAxis = "Z Axis"
    }
    
    enum RotationMetric: String, CaseIterable {
        case allAxes = "All Axes"
        case magnitude = "Magnitude"
        case xAxis = "X Axis"
        case yAxis = "Y Axis"
        case zAxis = "Z Axis"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sensor Data Visualization")
                .font(.headline)
                .fontWeight(.semibold)
            
            // Acceleration Chart
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Acceleration")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Picker("Acceleration Metric", selection: $selectedAccelerationMetric) {
                        ForEach(AccelerationMetric.allCases, id: \.self) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                }
                
                Chart {
                    if selectedAccelerationMetric == .allAxes {
                        ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("Acceleration", dataPoint.x),
                                series: .value("Axis", "X")
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .miter))
                        }
                        
                        ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("Acceleration", dataPoint.y),
                                series: .value("Axis", "Y")
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .miter))
                        }
                        
                        ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("Acceleration", dataPoint.z),
                                series: .value("Axis", "Z")
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .miter))
                        }
                    } else {
                        ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value(selectedAccelerationMetric.rawValue, dataPoint.value)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .miter))
                        }
                    }
                }
                .frame(height: 150)
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisValueLabel {
                            if let timeValue = value.as(Double.self) {
                                Text(String(format: "%.1fs", timeValue))
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let yValue = value.as(Double.self) {
                                Text(String(format: "%.2f", yValue))
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
            }
            
            // Gyroscope/Rotation Chart
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Gyroscope")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Picker("Rotation Metric", selection: $selectedRotationMetric) {
                        ForEach(RotationMetric.allCases, id: \.self) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                }
                
                Chart {
                    if selectedRotationMetric == .allAxes {
                        ForEach(Array(rotationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("Rotation", dataPoint.x),
                                series: .value("Axis", "X")
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .miter))
                        }
                        
                        ForEach(Array(rotationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("Rotation", dataPoint.y),
                                series: .value("Axis", "Y")
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .miter))
                        }
                        
                        ForEach(Array(rotationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("Rotation", dataPoint.z),
                                series: .value("Axis", "Z")
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .miter))
                        }
                    } else {
                        ForEach(Array(rotationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value(selectedRotationMetric.rawValue, dataPoint.value)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .miter))
                        }
                    }
                }
                .frame(height: 150)
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisValueLabel {
                            if let timeValue = value.as(Double.self) {
                                Text(String(format: "%.1fs", timeValue))
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let yValue = value.as(Double.self) {
                                Text(String(format: "%.2f", yValue))
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
            }
            
            // Data summary
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Readings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(sensorData.count)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Sample Rate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("100 Hz")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Duration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1fs", duration))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private var accelerationChartData: [(time: Double, x: Double, y: Double, z: Double, value: Double)] {
        guard !sensorData.isEmpty else { return [] }
        
        let startTime = sensorData.first!.timestamp.timeIntervalSinceReferenceDate
        
        // Downsample data for better visual jagged effect and performance
        let downsampleFactor = max(1, sensorData.count / 100) // Aim for ~100 points max
        let downsampledData = stride(from: 0, to: sensorData.count, by: downsampleFactor).map {
            sensorData[$0]
        }
        
        return downsampledData.map { reading in
            let timeOffset = reading.timestamp.timeIntervalSinceReferenceDate - startTime
            let value: Double
            
            switch selectedAccelerationMetric {
            case .magnitude:
                value = reading.accelerationMagnitude
            case .xAxis:
                value = reading.userAcceleration.x
            case .yAxis:
                value = reading.userAcceleration.y
            case .zAxis:
                value = reading.userAcceleration.z
            case .allAxes:
                value = 0.0 // Not used when showing all axes
            }
            
            return (
                time: timeOffset,
                x: reading.userAcceleration.x,
                y: reading.userAcceleration.y,
                z: reading.userAcceleration.z,
                value: value
            )
        }
    }
    
    private var rotationChartData: [(time: Double, x: Double, y: Double, z: Double, value: Double)] {
        guard !sensorData.isEmpty else { return [] }
        
        let startTime = sensorData.first!.timestamp.timeIntervalSinceReferenceDate
        
        // Downsample data for better visual jagged effect and performance
        let downsampleFactor = max(1, sensorData.count / 100) // Aim for ~100 points max
        let downsampledData = stride(from: 0, to: sensorData.count, by: downsampleFactor).map {
            sensorData[$0]
        }
        
        return downsampledData.map { reading in
            let timeOffset = reading.timestamp.timeIntervalSinceReferenceDate - startTime
            let value: Double
            
            switch selectedRotationMetric {
            case .magnitude:
                value = reading.rotationMagnitude
            case .xAxis:
                value = reading.rotationRate.x
            case .yAxis:
                value = reading.rotationRate.y
            case .zAxis:
                value = reading.rotationRate.z
            case .allAxes:
                value = 0.0 // Not used when showing all axes
            }
            
            return (
                time: timeOffset,
                x: reading.rotationRate.x,
                y: reading.rotationRate.y,
                z: reading.rotationRate.z,
                value: value
            )
        }
    }
    
    private var duration: Double {
        guard sensorData.count > 1 else { return 0 }
        return sensorData.last!.timestamp.timeIntervalSince(sensorData.first!.timestamp)
    }
}

struct SessionExportView: View {
    let session: DhikrSession
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var exportFormat = "CSV"
    @State private var includeMetadata = true
    @State private var showingShareSheet = false
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var exportError: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Export Session Data")
                    .font(.title2)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Export Options")
                        .font(.headline)
                    
                    Picker("Format", selection: $exportFormat) {
                        Text("CSV").tag("CSV")
                        Text("JSON").tag("JSON")
                    }
                    .pickerStyle(.segmented)
                    
                    Toggle("Include Metadata", isOn: $includeMetadata)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                Spacer()
                
                if let error = exportError {
                    Text("Export failed: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Button(action: exportData) {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.trailing, 4)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(isExporting ? "Exporting..." : "Export Data")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
                .padding()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
    }
    
    private func exportData() {
        guard let sensorData = dataManager.getSensorData(for: session.id.uuidString) else {
            exportError = "No sensor data available for this session"
            return
        }
        
        isExporting = true
        exportError = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Use temporary directory for sharing
                let tempDirectory = FileManager.default.temporaryDirectory
                let fileName = "session_\(self.session.id.uuidString.prefix(8))_\(Int(Date().timeIntervalSince1970)).\(self.exportFormat.lowercased())"
                let fileURL = tempDirectory.appendingPathComponent(fileName)
                
                // Remove existing file if it exists
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                
                let content: String
                if self.exportFormat == "CSV" {
                    content = self.generateCSV(sensorData: sensorData, session: self.session, includeMetadata: self.includeMetadata)
                } else {
                    content = self.generateJSON(sensorData: sensorData, session: self.session, includeMetadata: self.includeMetadata)
                }
                
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                
                // Verify file was created and has content
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                
                guard fileSize > 0 else {
                    throw NSError(domain: "ExportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Generated file is empty"])
                }
                
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.exportURL = fileURL
                    self.showingShareSheet = true
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.exportError = error.localizedDescription
                    print("Export error: \(error)")
                }
            }
        }
    }
    
    private func generateCSV(sensorData: [SensorReading], session: DhikrSession, includeMetadata: Bool) -> String {
        var csv = ""
        
        if includeMetadata {
            csv += "# Session ID: \(session.id.uuidString)\n"
            csv += "# Start Time: \(session.startTime)\n"
            csv += "# Duration: \(session.sessionDuration)s\n"
            csv += "# Total Readings: \(sensorData.count)\n"
            csv += "#\n"
        }
        
        csv += "timestamp,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z\n"
        
        for reading in sensorData {
            csv += "\(reading.timestamp.timeIntervalSinceReferenceDate),"
            csv += "\(reading.userAcceleration.x),\(reading.userAcceleration.y),\(reading.userAcceleration.z),"
            csv += "\(reading.rotationRate.x),\(reading.rotationRate.y),\(reading.rotationRate.z)\n"
        }
        
        return csv
    }
    
    private func generateJSON(sensorData: [SensorReading], session: DhikrSession, includeMetadata: Bool) -> String {
        var json: [String: Any] = [:]
        
        if includeMetadata {
            json["metadata"] = [
                "sessionId": session.id.uuidString,
                "startTime": session.startTime.timeIntervalSinceReferenceDate,
                "duration": session.sessionDuration,
                "totalReadings": sensorData.count
            ]
        }
        
        let readings = sensorData.map { reading in
            return [
                "timestamp": reading.timestamp.timeIntervalSinceReferenceDate,
                "userAcceleration": [
                    "x": reading.userAcceleration.x,
                    "y": reading.userAcceleration.y,
                    "z": reading.userAcceleration.z
                ],
                "rotationRate": [
                    "x": reading.rotationRate.x,
                    "y": reading.rotationRate.y,
                    "z": reading.rotationRate.z
                ]
            ]
        }
        
        json["sensorData"] = readings
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{\"error\": \"Failed to encode JSON\"}"
        }
        
        return jsonString
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        // Set completion handler to clean up temporary files
        activityViewController.completionWithItemsHandler = { _, _, _, _ in
            // Clean up temporary files if they exist
            for item in activityItems {
                if let url = item as? URL, url.path.contains("tmp") {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        
        return activityViewController
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct EmptyStateView: View {
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(40)
    }
}

// MARK: - Preview

struct DataVisualizationView_Previews: PreviewProvider {
    static var previews: some View {
        DataVisualizationView()
    }
}