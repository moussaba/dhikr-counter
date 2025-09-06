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
                    StatCard(title: "Sample Rate", value: "50 Hz", color: .orange)
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
                
                // Validation data
                ValidationDataCard(session: session)
                
                // Sensor data preview
                if let sensorData = dataManager.getSensorData(for: session.id.uuidString) {
                    SensorDataPreviewCard(sensorData: sensorData, session: session)
                    
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
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    @State private var isEditingNotes = false
    @State private var notesText: String = ""
    
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
                
                // Motion interruption count
                let interruptionCount = dataManager.getMotionInterruptionCount(for: session.id.uuidString)
                if interruptionCount > 0 {
                    OverviewItem(title: "Data Gaps", value: "\(interruptionCount) interruption\(interruptionCount == 1 ? "" : "s")")
                        .foregroundColor(.orange)
                }
            }
            
            // Notes section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Session Notes")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Button(isEditingNotes ? "Save" : "Edit") {
                        if isEditingNotes {
                            // Save notes
                            dataManager.updateSessionNotes(sessionId: session.id.uuidString, notes: notesText.isEmpty ? nil : notesText)
                        } else {
                            // Start editing
                            notesText = session.sessionNotes ?? ""
                        }
                        isEditingNotes.toggle()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                
                if isEditingNotes {
                    TextField("Add notes about this session...", text: $notesText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                } else {
                    Text(session.sessionNotes?.isEmpty == false ? session.sessionNotes! : "No notes added")
                        .font(.caption)
                        .foregroundColor(session.sessionNotes?.isEmpty == false ? .primary : .secondary)
                        .italic(session.sessionNotes?.isEmpty != false)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .onAppear {
            notesText = session.sessionNotes ?? ""
        }
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

struct ValidationDataCard: View {
    let session: DhikrSession
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    @State private var actualPinchCountText: String = ""
    @State private var showingNumberPad = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Validation Data")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Set the actual number of pinches performed during this session for algorithm validation:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Actual Pinch Count")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if let actualCount = session.actualPinchCount {
                            Text("\(actualCount)")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        } else {
                            Text("Not Set")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button("Edit") {
                        actualPinchCountText = session.actualPinchCount?.description ?? ""
                        showingNumberPad = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .alert("Enter Actual Pinch Count", isPresented: $showingNumberPad) {
            TextField("Number of pinches", text: $actualPinchCountText)
                .keyboardType(.numberPad)
            
            Button("Save") {
                saveActualPinchCount()
            }
            
            Button("Clear") {
                clearActualPinchCount()
            }
            .foregroundColor(.red)
            
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter the actual number of pinches you performed during this session for validation purposes.")
        }
    }
    
    private func saveActualPinchCount() {
        if actualPinchCountText.isEmpty {
            clearActualPinchCount()
        } else if let count = Int(actualPinchCountText), count >= 0 {
            dataManager.updateActualPinchCount(for: session.id.uuidString, actualPinchCount: count)
        }
        actualPinchCountText = ""
    }
    
    private func clearActualPinchCount() {
        dataManager.updateActualPinchCount(for: session.id.uuidString, actualPinchCount: nil)
        actualPinchCountText = ""
    }
}

struct SensorDataPreviewCard: View {
    let sensorData: [SensorReading]
    let session: DhikrSession? // Optional session for chart naming
    @State private var selectedAccelerationMetric: AccelerationMetric = .userAccelMagnitude
    @State private var selectedRotationMetric: RotationMetric = .rotationMagnitude
    @State private var showingFullScreenChart = false
    @State private var fullScreenChartType: ChartType = .acceleration
    
    enum AccelerationMetric: String, CaseIterable {
        case userAccelMagnitude = "UserAccel Magnitude (Pinch Spikes)"
        case gravityWaves = "Gravity Waves (Gait)"
        case userAccelAxes = "UserAccel Axes"
        case gravityAxes = "Gravity Axes"
        case totalAccelMagnitude = "Total Accel Magnitude"
    }
    
    enum RotationMetric: String, CaseIterable {
        case rotationMagnitude = "Rotation Magnitude (Pinch Spikes)"
        case rotationAxes = "Rotation Axes"
        case xAxis = "X Axis"
        case yAxis = "Y Axis"
        case zAxis = "Z Axis"
    }
    
    enum ChartType {
        case acceleration
        case rotation
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sensor Data Visualization")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Research-grade plots: high-res timestamps, gravity waves, pinch spikes, all sensor axes")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }
            
            // Acceleration Chart
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Acceleration Analysis")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(accelerationChartDescription)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
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
                    switch selectedAccelerationMetric {
                    case .userAccelAxes:
                        ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("UserAccel", dataPoint.userAccelX),
                                series: .value("Axis", "UserAccel X")
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("UserAccel", dataPoint.userAccelY),
                                series: .value("Axis", "UserAccel Y")
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("UserAccel", dataPoint.userAccelZ),
                                series: .value("Axis", "UserAccel Z")
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        
                    case .gravityAxes:
                        ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("Gravity", dataPoint.gravityX),
                                series: .value("Axis", "Gravity X")
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("Gravity", dataPoint.gravityY),
                                series: .value("Axis", "Gravity Y")
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("Gravity", dataPoint.gravityZ),
                                series: .value("Axis", "Gravity Z")
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        
                    default:
                        // Single metric plots (magnitude, etc.)
                        ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value(selectedAccelerationMetric.rawValue, dataPoint.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
                .frame(height: 150)
                .contentShape(Rectangle())
                .onTapGesture {
                    fullScreenChartType = .acceleration
                    showingFullScreenChart = true
                }
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gyroscope Analysis")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(rotationChartDescription)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
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
                    switch selectedRotationMetric {
                    case .rotationAxes:
                        ForEach(Array(rotationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("Rotation", dataPoint.x),
                                series: .value("Axis", "Rotation X")
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        ForEach(Array(rotationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("Rotation", dataPoint.y),
                                series: .value("Axis", "Rotation Y")
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        ForEach(Array(rotationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value("Rotation", dataPoint.z),
                                series: .value("Axis", "Rotation Z")
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        
                    default:
                        // Single metric plots (magnitude, individual axes)
                        ForEach(Array(rotationChartData.enumerated()), id: \.offset) { index, dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.time),
                                y: .value(selectedRotationMetric.rawValue, dataPoint.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
                .frame(height: 150)
                .contentShape(Rectangle())
                .onTapGesture {
                    fullScreenChartType = .rotation
                    showingFullScreenChart = true
                }
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
                    Text("50 Hz")
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
        .sheet(isPresented: $showingFullScreenChart) {
            FullScreenChartView(
                sensorData: sensorData,
                session: session,
                chartType: fullScreenChartType,
                accelerationMetric: selectedAccelerationMetric,
                rotationMetric: selectedRotationMetric
            )
        }
    }
    
    private var accelerationChartData: [(time: Double, userAccelX: Double, userAccelY: Double, userAccelZ: Double, gravityX: Double, gravityY: Double, gravityZ: Double, value: Double)] {
        guard !sensorData.isEmpty else { return [] }
        
        // Use high-resolution motion timestamps per research guide 
        let startTime = sensorData.first!.motionTimestamp
        
        // Downsample data for performance - aim for ~200 points for smooth curves
        let downsampleFactor = max(1, sensorData.count / 200)
        let downsampledData = stride(from: 0, to: sensorData.count, by: downsampleFactor).map {
            sensorData[$0]
        }
        
        return downsampledData.map { reading in
            let timeOffset = reading.motionTimestamp - startTime
            let value: Double
            
            switch selectedAccelerationMetric {
            case .userAccelMagnitude:
                // UserAcceleration magnitude (pinch spikes)
                value = sqrt(pow(reading.userAcceleration.x, 2) + pow(reading.userAcceleration.y, 2) + pow(reading.userAcceleration.z, 2))
            case .gravityWaves:
                // Gravity magnitude (smooth gait waves)
                value = sqrt(pow(reading.gravity.x, 2) + pow(reading.gravity.y, 2) + pow(reading.gravity.z, 2))
            case .totalAccelMagnitude:
                // Total acceleration magnitude (gravity + userAccel)
                let totalX = reading.gravity.x + reading.userAcceleration.x
                let totalY = reading.gravity.y + reading.userAcceleration.y
                let totalZ = reading.gravity.z + reading.userAcceleration.z
                value = sqrt(pow(totalX, 2) + pow(totalY, 2) + pow(totalZ, 2))
            case .userAccelAxes, .gravityAxes:
                value = 0.0 // Not used for multi-axis plots
            }
            
            return (
                time: timeOffset,
                userAccelX: reading.userAcceleration.x,
                userAccelY: reading.userAcceleration.y,
                userAccelZ: reading.userAcceleration.z,
                gravityX: reading.gravity.x,
                gravityY: reading.gravity.y,
                gravityZ: reading.gravity.z,
                value: value
            )
        }
    }
    
    private var rotationChartData: [(time: Double, x: Double, y: Double, z: Double, value: Double)] {
        guard !sensorData.isEmpty else { return [] }
        
        // Use high-resolution motion timestamps per research guide 
        let startTime = sensorData.first!.motionTimestamp
        
        // Downsample data for performance - aim for ~200 points for smooth curves
        let downsampleFactor = max(1, sensorData.count / 200)
        let downsampledData = stride(from: 0, to: sensorData.count, by: downsampleFactor).map {
            sensorData[$0]
        }
        
        return downsampledData.map { reading in
            let timeOffset = reading.motionTimestamp - startTime
            let value: Double
            
            switch selectedRotationMetric {
            case .rotationMagnitude:
                // Rotation magnitude (pinch spikes)
                value = sqrt(pow(reading.rotationRate.x, 2) + pow(reading.rotationRate.y, 2) + pow(reading.rotationRate.z, 2))
            case .xAxis:
                value = reading.rotationRate.x
            case .yAxis:
                value = reading.rotationRate.y
            case .zAxis:
                value = reading.rotationRate.z
            case .rotationAxes:
                value = 0.0 // Not used for multi-axis plots
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
        // Use high-resolution motion timestamps for precise duration
        return sensorData.last!.motionTimestamp - sensorData.first!.motionTimestamp
    }
    
    private var accelerationChartDescription: String {
        switch selectedAccelerationMetric {
        case .userAccelMagnitude:
            return "Shows pinch spikes (6-22Hz band) - high-frequency movements"
        case .gravityWaves:
            return "Shows smooth gait waves (0-2Hz band) - like Sensor Logger"
        case .userAccelAxes:
            return "Gravity-removed acceleration on X/Y/Z axes (g units)"
        case .gravityAxes:
            return "Gravity component showing arm tilt and gait waves (g units)"
        case .totalAccelMagnitude:
            return "Total acceleration magnitude (gravity + userAccel)"
        }
    }
    
    private var rotationChartDescription: String {
        switch selectedRotationMetric {
        case .rotationMagnitude:
            return "Shows pinch spikes - angular velocity magnitude (rad/s)"
        case .rotationAxes:
            return "Angular velocity on X/Y/Z axes (rad/s)"
        case .xAxis:
            return "X-axis angular velocity (rad/s)"
        case .yAxis:
            return "Y-axis angular velocity (rad/s)"
        case .zAxis:
            return "Z-axis angular velocity (rad/s)"
        }
    }
}

struct SessionExportView: View {
    let session: DhikrSession
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("exportFormat") private var exportFormat: String = "JSON"
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
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Format: \(exportFormat)")
                                .fontWeight(.medium)
                            Spacer()
                            Text("(Set in Settings)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Change format in Settings → Data Export")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
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
                // Use Documents directory for iOS file sharing compatibility
                guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    throw NSError(domain: "ExportError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not access Documents directory"])
                }
                
                let fileName = "session_\(self.session.id.uuidString.prefix(8))_\(Int(Date().timeIntervalSince1970)).\(self.exportFormat.lowercased())"
                var fileURL = documentsDirectory.appendingPathComponent(fileName)
                
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
                
                // Write file with proper options for iOS sharing
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                
                // Set basic file attributes (avoid collaboration features that cause errors)
                do {
                    var resourceValues = URLResourceValues()
                    resourceValues.isExcludedFromBackup = true
                    try fileURL.setResourceValues(resourceValues)
                } catch {
                    print("⚠️ Could not set file resource values (non-critical): \(error)")
                    // Continue without setting resource values - file sharing will still work
                }
                
                // Verify file was created and has content
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                
                guard fileSize > 0 else {
                    throw NSError(domain: "ExportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Generated file is empty"])
                }
                
                print("✅ Successfully created export file: \(fileURL.path)")
                print("📁 File size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")
                
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
            csv += "# app=DhikrCounter version=1.0\n"
            csv += "# using_frame=xArbitraryZVertical\n"  // Updated to match actual reference frame 
            csv += "# update_interval_s=0.020000\n"  // 50Hz = 0.02s interval
            csv += "# Session ID: \(session.id.uuidString)\n"
            csv += "# Start Time: \(session.startTime)\n"
            csv += "# Duration: \(session.sessionDuration)s\n"
            csv += "# Total Readings: \(sensorData.count)\n"
            if let actualCount = session.actualPinchCount {
                csv += "# Actual Pinch Count: \(actualCount)\n"
            } else {
                csv += "# Actual Pinch Count: Not Set\n"
            }
            csv += "#\n"
        }
        
        // Research-grade CSV format per pinch collection advice document
        csv += "time_s,epoch_s,userAccelerationX,userAccelerationY,userAccelerationZ,gravityX,gravityY,gravityZ,rotationRateX,rotationRateY,rotationRateZ,attitude_qW,attitude_qX,attitude_qY,attitude_qZ\n"
        
        for reading in sensorData {
            // Use high-resolution timestamps as per research guide
            let timeS = String(format: "%.6f", reading.motionTimestamp)
            let epochS = String(format: "%.6f", reading.epochTimestamp)
            
            // All sensor values with 6-decimal precision 
            let userAccelX = String(format: "%.6f", reading.userAcceleration.x)
            let userAccelY = String(format: "%.6f", reading.userAcceleration.y) 
            let userAccelZ = String(format: "%.6f", reading.userAcceleration.z)
            let gravityX = String(format: "%.6f", reading.gravity.x)
            let gravityY = String(format: "%.6f", reading.gravity.y)
            let gravityZ = String(format: "%.6f", reading.gravity.z)
            let rotationX = String(format: "%.6f", reading.rotationRate.x)
            let rotationY = String(format: "%.6f", reading.rotationRate.y)
            let rotationZ = String(format: "%.6f", reading.rotationRate.z)
            let attitudeW = String(format: "%.6f", reading.attitude.w)
            let attitudeX = String(format: "%.6f", reading.attitude.x)
            let attitudeY = String(format: "%.6f", reading.attitude.y)
            let attitudeZ = String(format: "%.6f", reading.attitude.z)
            
            csv += "\(timeS),\(epochS),\(userAccelX),\(userAccelY),\(userAccelZ),\(gravityX),\(gravityY),\(gravityZ),\(rotationX),\(rotationY),\(rotationZ),\(attitudeW),\(attitudeX),\(attitudeY),\(attitudeZ)\n"
        }
        
        return csv
    }
    
    private func generateJSON(sensorData: [SensorReading], session: DhikrSession, includeMetadata: Bool) -> String {
        var json: [String: Any] = [:]
        
        if includeMetadata {
            var metadata: [String: Any] = [
                "app": "DhikrCounter",
                "version": "1.0", 
                "using_frame": "xArbitraryZVertical",  // Updated to match actual reference frame
                "update_interval_s": 0.020000,  // 50Hz = 0.02s interval
                "sessionId": session.id.uuidString,
                "startTime": session.startTime.timeIntervalSinceReferenceDate,
                "duration": session.sessionDuration,
                "totalReadings": sensorData.count
            ]
            if let actualCount = session.actualPinchCount {
                metadata["actualPinchCount"] = actualCount
            }
            json["metadata"] = metadata
        }
        
        let readings = sensorData.map { reading in
            return [
                "time_s": reading.motionTimestamp,
                "epoch_s": reading.epochTimestamp,
                "userAcceleration": [
                    "x": reading.userAcceleration.x,
                    "y": reading.userAcceleration.y,
                    "z": reading.userAcceleration.z
                ],
                "gravity": [
                    "x": reading.gravity.x,
                    "y": reading.gravity.y,
                    "z": reading.gravity.z
                ],
                "rotationRate": [
                    "x": reading.rotationRate.x,
                    "y": reading.rotationRate.y,
                    "z": reading.rotationRate.z
                ],
                "attitude": [
                    "w": reading.attitude.w,
                    "x": reading.attitude.x,
                    "y": reading.attitude.y,
                    "z": reading.attitude.z
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
        // Create activity view controller with basic configuration
        let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        // Disable collaboration features that cause iOS errors
        activityViewController.excludedActivityTypes = [
            .collaborationInviteWithLink,
            .collaborationCopyLink
        ]
        
        // Set completion handler to clean up exported files
        activityViewController.completionWithItemsHandler = { _, completed, _, _ in
            // Only clean up if sharing completed successfully
            if completed {
                // Clean up exported files from Documents directory after sharing
                for item in activityItems {
                    if let url = item as? URL, url.lastPathComponent.hasPrefix("session_") {
                        DispatchQueue.global(qos: .background).async {
                            try? FileManager.default.removeItem(at: url)
                            print("🗑️ Cleaned up exported file: \(url.lastPathComponent)")
                        }
                    }
                }
            }
        }
        
        return activityViewController
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Image with Filename Helper

class ImageWithFilename: NSObject, UIActivityItemSource {
    let image: UIImage
    let filename: String
    
    init(image: UIImage, filename: String) {
        self.image = image
        self.filename = filename
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return image
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return image
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return filename.replacingOccurrences(of: ".png", with: "")
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "public.png"
    }
}

// MARK: - Full Screen Chart View

struct FullScreenChartView: View {
    let sensorData: [SensorReading]
    let session: DhikrSession?
    let chartType: SensorDataPreviewCard.ChartType
    let accelerationMetric: SensorDataPreviewCard.AccelerationMetric
    let rotationMetric: SensorDataPreviewCard.RotationMetric
    
    @Environment(\.presentationMode) var presentationMode
    @State private var showingShareSheet = false
    @State private var chartImage: UIImage?
    @State private var tempFileURL: URL?
    @State private var isExporting = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Research-Grade Sensor Analysis")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)
                
                Text(chartDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Full-screen chart
                chartView
                    .frame(maxHeight: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .padding(.horizontal)
                
                // Stats section
                HStack(spacing: 30) {
                    VStack {
                        Text("Samples")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(sensorData.count)")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    
                    VStack {
                        Text("Duration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1fs", duration))
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    
                    VStack {
                        Text("Rate")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("50 Hz")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarItems(
                leading: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button(action: exportChart) {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(isExporting ? "Exporting..." : "Export")
                    }
                }
                .disabled(isExporting)
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let tempFileURL = tempFileURL {
                ShareSheet(activityItems: [tempFileURL])
            }
        }
    }
    
    @ViewBuilder
    private var chartView: some View {
        switch chartType {
        case .acceleration:
            accelerationChart
        case .rotation:
            rotationChart
        }
    }
    
    private var accelerationChart: some View {
        Chart {
            switch accelerationMetric {
            case .userAccelAxes:
                ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value("UserAccel", dataPoint.userAccelX),
                        series: .value("Axis", "UserAccel X")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value("UserAccel", dataPoint.userAccelY),
                        series: .value("Axis", "UserAccel Y")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value("UserAccel", dataPoint.userAccelZ),
                        series: .value("Axis", "UserAccel Z")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                
            case .gravityAxes:
                ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value("Gravity", dataPoint.gravityX),
                        series: .value("Axis", "Gravity X")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value("Gravity", dataPoint.gravityY),
                        series: .value("Axis", "Gravity Y")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value("Gravity", dataPoint.gravityZ),
                        series: .value("Axis", "Gravity Z")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                
            default:
                ForEach(Array(accelerationChartData.enumerated()), id: \.offset) { index, dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value(accelerationMetric.rawValue, dataPoint.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                }
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisValueLabel {
                    if let timeValue = value.as(Double.self) {
                        Text(String(format: "%.1fs", timeValue))
                            .font(.caption)
                    }
                }
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let yValue = value.as(Double.self) {
                        Text(String(format: "%.3f", yValue))
                            .font(.caption)
                    }
                }
                AxisGridLine()
            }
        }
    }
    
    private var rotationChart: some View {
        Chart {
            switch rotationMetric {
            case .rotationAxes:
                ForEach(Array(rotationChartData.enumerated()), id: \.offset) { index, dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value("Rotation", dataPoint.x),
                        series: .value("Axis", "Rotation X")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(Array(rotationChartData.enumerated()), id: \.offset) { index, dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value("Rotation", dataPoint.y),
                        series: .value("Axis", "Rotation Y")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(Array(rotationChartData.enumerated()), id: \.offset) { index, dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value("Rotation", dataPoint.z),
                        series: .value("Axis", "Rotation Z")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                
            default:
                ForEach(Array(rotationChartData.enumerated()), id: \.offset) { index, dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value(rotationMetric.rawValue, dataPoint.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                }
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisValueLabel {
                    if let timeValue = value.as(Double.self) {
                        Text(String(format: "%.1fs", timeValue))
                            .font(.caption)
                    }
                }
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let yValue = value.as(Double.self) {
                        Text(String(format: "%.3f", yValue))
                            .font(.caption)
                    }
                }
                AxisGridLine()
            }
        }
    }
    
    // Chart export functionality
    private func exportChart() {
        isExporting = true
        
        // Render on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            // Optimize rendering size based on orientation and device capabilities
            let isVertical = UIDevice.current.orientation.isPortrait || UIDevice.current.orientation == .unknown
            let width: CGFloat = isVertical ? 800 : 1200
            let height: CGFloat = isVertical ? 1000 : 600
            
            let renderer = ImageRenderer(content: self.chartView.frame(width: width, height: height))
            // Use lower scale for vertical mode to prevent memory issues
            renderer.scale = isVertical ? min(2.0, UIScreen.main.scale) : UIScreen.main.scale
            
            if let image = renderer.uiImage {
                // Generate unique filename
                let filename = self.generateUniqueFilename()
                
                // Create temporary file with proper name for sharing
                if let imageData = image.pngData() {
                    let tempDirectory = FileManager.default.temporaryDirectory
                    let fileURL = tempDirectory.appendingPathComponent(filename)
                    
                    do {
                        try imageData.write(to: fileURL)
                        
                        DispatchQueue.main.async {
                            self.isExporting = false
                            self.chartImage = image
                            self.tempFileURL = fileURL
                            self.showingShareSheet = true
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.isExporting = false
                            print("Failed to create temp file: \(error)")
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isExporting = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isExporting = false
                }
            }
        }
    }
    
    private func generateUniqueFilename() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        let chartTypeString = chartType == .acceleration ? "Accel" : "Gyro"
        let metricString: String
        
        switch chartType {
        case .acceleration:
            metricString = accelerationMetric.rawValue.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
        case .rotation:
            metricString = rotationMetric.rawValue.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
        }
        
        let sessionPrefix = session?.id.uuidString.prefix(8) ?? "Unknown"
        
        return "DhikrChart_\(sessionPrefix)_\(chartTypeString)_\(metricString)_\(timestamp).png"
    }
    
    // Computed properties
    private var chartDescription: String {
        switch chartType {
        case .acceleration:
            switch accelerationMetric {
            case .userAccelMagnitude:
                return "UserAcceleration Magnitude showing pinch spikes (6-22Hz band) - gravity-removed high-frequency movements"
            case .gravityWaves:
                return "Gravity Magnitude showing smooth gait waves (0-2Hz band) - arm tilt and walking motion patterns like Sensor Logger"
            case .userAccelAxes:
                return "Individual UserAcceleration axes (X/Y/Z) - gravity-removed acceleration components in g units"
            case .gravityAxes:
                return "Individual Gravity axes (X/Y/Z) - gravity component showing arm orientation and gait patterns in g units"
            case .totalAccelMagnitude:
                return "Total Acceleration Magnitude - combination of gravity and user acceleration"
            }
        case .rotation:
            switch rotationMetric {
            case .rotationMagnitude:
                return "Rotation Rate Magnitude showing pinch spikes - angular velocity magnitude in rad/s"
            case .rotationAxes:
                return "Individual Rotation axes (X/Y/Z) - angular velocity components in rad/s"
            case .xAxis:
                return "X-axis angular velocity in rad/s"
            case .yAxis:
                return "Y-axis angular velocity in rad/s"
            case .zAxis:
                return "Z-axis angular velocity in rad/s"
            }
        }
    }
    
    private var accelerationChartData: [(time: Double, userAccelX: Double, userAccelY: Double, userAccelZ: Double, gravityX: Double, gravityY: Double, gravityZ: Double, value: Double)] {
        guard !sensorData.isEmpty else { return [] }
        
        // Use high-resolution motion timestamps per research guide 
        let startTime = sensorData.first!.motionTimestamp
        
        // Optimized data points for performance vs quality balance
        let downsampleFactor = max(1, sensorData.count / 300)
        let downsampledData = stride(from: 0, to: sensorData.count, by: downsampleFactor).map {
            sensorData[$0]
        }
        
        return downsampledData.map { reading in
            let timeOffset = reading.motionTimestamp - startTime
            let value: Double
            
            switch accelerationMetric {
            case .userAccelMagnitude:
                value = sqrt(pow(reading.userAcceleration.x, 2) + pow(reading.userAcceleration.y, 2) + pow(reading.userAcceleration.z, 2))
            case .gravityWaves:
                value = sqrt(pow(reading.gravity.x, 2) + pow(reading.gravity.y, 2) + pow(reading.gravity.z, 2))
            case .totalAccelMagnitude:
                let totalX = reading.gravity.x + reading.userAcceleration.x
                let totalY = reading.gravity.y + reading.userAcceleration.y
                let totalZ = reading.gravity.z + reading.userAcceleration.z
                value = sqrt(pow(totalX, 2) + pow(totalY, 2) + pow(totalZ, 2))
            case .userAccelAxes, .gravityAxes:
                value = 0.0
            }
            
            return (
                time: timeOffset,
                userAccelX: reading.userAcceleration.x,
                userAccelY: reading.userAcceleration.y,
                userAccelZ: reading.userAcceleration.z,
                gravityX: reading.gravity.x,
                gravityY: reading.gravity.y,
                gravityZ: reading.gravity.z,
                value: value
            )
        }
    }
    
    private var rotationChartData: [(time: Double, x: Double, y: Double, z: Double, value: Double)] {
        guard !sensorData.isEmpty else { return [] }
        
        // Use high-resolution motion timestamps per research guide 
        let startTime = sensorData.first!.motionTimestamp
        
        // Optimized data points for performance vs quality balance
        let downsampleFactor = max(1, sensorData.count / 300)
        let downsampledData = stride(from: 0, to: sensorData.count, by: downsampleFactor).map {
            sensorData[$0]
        }
        
        return downsampledData.map { reading in
            let timeOffset = reading.motionTimestamp - startTime
            let value: Double
            
            switch rotationMetric {
            case .rotationMagnitude:
                value = sqrt(pow(reading.rotationRate.x, 2) + pow(reading.rotationRate.y, 2) + pow(reading.rotationRate.z, 2))
            case .xAxis:
                value = reading.rotationRate.x
            case .yAxis:
                value = reading.rotationRate.y
            case .zAxis:
                value = reading.rotationRate.z
            case .rotationAxes:
                value = 0.0
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
        return sensorData.last!.motionTimestamp - sensorData.first!.motionTimestamp
    }
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