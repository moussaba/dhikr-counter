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
                    Text("Export").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content based on selection
                switch selectedTab {
                case 0:
                    TimelineVisualizationView()
                case 1:
                    SensorDataDetailView()
                case 2:
                    ExportVisualizationView()
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
                    ForEach(dataManager.receivedSessions.prefix(3)) { session in
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

struct ExportVisualizationView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Export options
                ExportOptionsView()
                
                // Data format preview
                DataFormatPreviewView()
                
                // Export history
                ExportHistoryView()
            }
            .padding()
        }
    }
}

struct ExportOptionsView: View {
    @State private var includeRawSensorData = true
    @State private var includeDetectionEvents = true
    @State private var includeSessionMetadata = true
    @State private var exportFormat = "CSV"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Configuration")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                // Data inclusion options
                Toggle("Include Raw Sensor Data", isOn: $includeRawSensorData)
                Toggle("Include Detection Events", isOn: $includeDetectionEvents)
                Toggle("Include Session Metadata", isOn: $includeSessionMetadata)
                
                // Format selection
                HStack {
                    Text("Export Format")
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Picker("Format", selection: $exportFormat) {
                        Text("CSV").tag("CSV")
                        Text("JSON").tag("JSON")
                    }
                    .pickerStyle(.menu)
                }
            }
            
            Button(action: {
                // Export functionality in Phase 3
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Session Data")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

struct DataFormatPreviewView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CSV Export Format Preview")
                .font(.headline)
                .fontWeight(.semibold)
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text("timestamp,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,accel_mag,gyro_mag,activity_index,detection_score,detected_pinch,manual_correction,session_state,dhikr_type_estimate")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            
            Text("Compatible with Jupyter notebook analysis environment")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

struct ExportHistoryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export History")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                Text("No exports yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Exported files will be listed here with download and sharing options")
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
                    ForEach(dataManager.receivedSessions) { session in
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
    @State private var selectedMetric: SensorMetric = .accelerationMagnitude
    
    enum SensorMetric: String, CaseIterable {
        case accelerationMagnitude = "Acceleration Magnitude"
        case rotationMagnitude = "Rotation Magnitude"
        case accelerationX = "Acceleration X"
        case accelerationY = "Acceleration Y" 
        case accelerationZ = "Acceleration Z"
        case rotationX = "Rotation X"
        case rotationY = "Rotation Y"
        case rotationZ = "Rotation Z"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Sensor Data Visualization")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(SensorMetric.allCases, id: \.self) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
            }
            
            // Simple line chart
            Chart {
                ForEach(Array(chartData.prefix(1000).enumerated()), id: \.offset) { index, dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value(selectedMetric.rawValue, dataPoint.value)
                    )
                    .foregroundStyle(chartColor)
                    .interpolationMethod(.catmullRom)
                }
            }
            .frame(height: 200)
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
    
    private var chartData: [(time: Double, value: Double)] {
        guard !sensorData.isEmpty else { return [] }
        
        let startTime = sensorData.first!.timestamp.timeIntervalSinceReferenceDate
        
        return sensorData.map { reading in
            let timeOffset = reading.timestamp.timeIntervalSinceReferenceDate - startTime
            let value: Double
            
            switch selectedMetric {
            case .accelerationMagnitude:
                value = reading.accelerationMagnitude
            case .rotationMagnitude:
                value = reading.rotationMagnitude
            case .accelerationX:
                value = reading.userAcceleration.x
            case .accelerationY:
                value = reading.userAcceleration.y
            case .accelerationZ:
                value = reading.userAcceleration.z
            case .rotationX:
                value = reading.rotationRate.x
            case .rotationY:
                value = reading.rotationRate.y
            case .rotationZ:
                value = reading.rotationRate.z
            }
            
            return (time: timeOffset, value: value)
        }
    }
    
    private var chartColor: Color {
        switch selectedMetric {
        case .accelerationMagnitude, .accelerationX, .accelerationY, .accelerationZ:
            return .blue
        case .rotationMagnitude, .rotationX, .rotationY, .rotationZ:
            return .orange
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
                
                Button(action: exportData) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export Data")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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
        guard let sensorData = dataManager.getSensorData(for: session.id.uuidString) else { return }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = "session_\(session.id.uuidString.prefix(8))_\(Int(Date().timeIntervalSince1970)).\(exportFormat.lowercased())"
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        do {
            if exportFormat == "CSV" {
                let csvContent = generateCSV(sensorData: sensorData, session: session, includeMetadata: includeMetadata)
                try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            } else {
                let jsonContent = generateJSON(sensorData: sensorData, session: session, includeMetadata: includeMetadata)
                try jsonContent.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            
            exportURL = fileURL
            showingShareSheet = true
            
        } catch {
            print("Export error: \(error)")
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
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
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