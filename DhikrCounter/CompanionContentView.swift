import SwiftUI

struct CompanionContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Image(systemName: "house")
                    Text("Dashboard")
                }
            
            DataVisualizationView()
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Analysis")
                }
            
            SessionManagementView()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Sessions")
                }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
            
        }
    }
}

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Welcome section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Dhikr Counter")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Companion app for Apple Watch dhikr counting with research-validated detection algorithms.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Quick stats
                    QuickStatsView()
                    
                    // Watch connection status
                    WatchConnectionView()
                    
                    // Recent sessions
                    RecentSessionsView()
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct QuickStatsView: View {
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Stats")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                StatCard(title: "Total Sessions", value: "\(dataManager.receivedSessions.count)", color: .blue)
                StatCard(title: "Sensor Readings", value: totalReadingsText, color: .green)
                StatCard(title: "Data Size", value: totalDataSizeText, color: .orange)
                StatCard(title: "Connection Status", value: connectionStatusText, color: connectionStatusColor)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private var totalReadingsText: String {
        let totalReadings = dataManager.totalSensorReadings
        if totalReadings == 0 {
            return "0"
        } else if totalReadings >= 1000 {
            return String(format: "%.1fK", Double(totalReadings) / 1000.0)
        } else {
            return "\(totalReadings)"
        }
    }
    
    private var totalDataSizeText: String {
        let totalBytes = dataManager.estimatedTotalDataSize
        if totalBytes == 0 {
            return "0 KB"
        } else {
            return ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
        }
    }
    
    private var connectionStatusText: String {
        dataManager.isWatchConnected ? "Connected" : "Disconnected"
    }
    
    private var connectionStatusColor: Color {
        dataManager.isWatchConnected ? .green : .orange
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}


struct WatchConnectionView: View {
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Watch")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack {
                Image(systemName: dataManager.isWatchConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(dataManager.isWatchConnected ? .green : .orange)
                
                Text(dataManager.isWatchConnected ? "Connected" : "Not Connected")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if !dataManager.isWatchConnected {
                    Button("Retry") {
                        // Force reactivation and status check
                        dataManager.forceConnectionCheck()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            
            Text(dataManager.lastReceiveStatus)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

struct RecentSessionsView: View {
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Sessions")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                NavigationLink(destination: DataVisualizationView()) {
                    Text("View All")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            if dataManager.receivedSessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 4) {
                        Text("No sensor data yet")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("Transfer data from your Apple Watch to begin analysis")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(.systemBackground))
                .cornerRadius(12)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(dataManager.receivedSessions.sorted(by: { $0.startTime > $1.startTime }).prefix(3)) { session in
                        EnhancedSessionRowView(session: session)
                    }
                    
                    if dataManager.receivedSessions.count > 3 {
                        Text("+ \(dataManager.receivedSessions.count - 3) more sessions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

struct SessionManagementView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                
                Text("Session Management")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Session data management and export functionality coming in Phase 3")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Sessions")
        }
    }
}

struct SettingsView: View {
    @AppStorage("exportFormat") private var exportFormat: String = "JSON"
    
    // TKEO Configuration Parameters
    @AppStorage("tkeo_sampleRate") private var sampleRate: Double = 50.0
    @AppStorage("tkeo_bandpassLow") private var bandpassLow: Double = 3.0
    @AppStorage("tkeo_bandpassHigh") private var bandpassHigh: Double = 20.0
    @AppStorage("tkeo_gateThreshold") private var gateThreshold: Double = 3.5
    @AppStorage("tkeo_accelWeight") private var accelWeight: Double = 1.0
    @AppStorage("tkeo_gyroWeight") private var gyroWeight: Double = 1.5
    @AppStorage("tkeo_refractoryPeriod") private var refractoryPeriod: Double = 0.15
    @AppStorage("tkeo_templateConfidence") private var templateConfidence: Double = 0.6
    @AppStorage("tkeo_templateLength") private var templateLength: Double = 40
    
    var body: some View {
        NavigationStack {
            List {
                Section("TKEO Detection Algorithm") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("TKEO Pinch Detection")
                                .foregroundColor(.primary)
                            Text("Teager-Kaiser Energy Operator for micro-gesture detection")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "waveform.path.ecg")
                            .foregroundColor(.purple)
                    }
                }
                
                Section("Signal Processing") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Sample Rate")
                            Spacer()
                            Text("\(Int(sampleRate)) Hz")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Bandpass Filter")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Low: \(String(format: "%.1f", bandpassLow)) Hz")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("High: \(String(format: "%.1f", bandpassHigh)) Hz")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Low Cutoff Frequency")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(String(format: "%.1f", bandpassLow)) Hz")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Slider(value: $bandpassLow, in: 1.0...10.0, step: 0.5) {
                                    Text("Low Cutoff")
                                } minimumValueLabel: {
                                    Text("1")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } maximumValueLabel: {
                                    Text("10")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Text("Lower values capture slower hand movements")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("High Cutoff Frequency")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(String(format: "%.1f", bandpassHigh)) Hz")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Slider(value: $bandpassHigh, in: 15.0...30.0, step: 1.0) {
                                    Text("High Cutoff")
                                } minimumValueLabel: {
                                    Text("15")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } maximumValueLabel: {
                                    Text("30")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Text("Higher values capture faster transient movements")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                Section("Detection Thresholds") {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Gate Threshold")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(String(format: "%.1f", gateThreshold))σ")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $gateThreshold, in: 2.0...6.0, step: 0.5) {
                                Text("Gate Threshold")
                            } minimumValueLabel: {
                                Text("2.0")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Text("6.0")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Lower = more sensitive (more false positives)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Template Confidence (NCC)")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(String(format: "%.2f", templateConfidence))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $templateConfidence, in: 0.3...0.9, step: 0.05) {
                                Text("Template Confidence")
                            } minimumValueLabel: {
                                Text("0.3")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Text("0.9")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Higher = more strict template matching (NCC threshold)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Sensor Fusion") {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Accelerometer Weight")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(String(format: "%.1f", accelWeight))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $accelWeight, in: 0.5...2.0, step: 0.1) {
                                Text("Accelerometer Weight")
                            } minimumValueLabel: {
                                Text("0.5")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Text("2.0")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Emphasis on linear motion detection")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Gyroscope Weight")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(String(format: "%.1f", gyroWeight))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $gyroWeight, in: 0.5...3.0, step: 0.1) {
                                Text("Gyroscope Weight")
                            } minimumValueLabel: {
                                Text("0.5")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Text("3.0")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Emphasis on rotational motion detection")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Timing Parameters") {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Refractory Period")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(Int(refractoryPeriod * 1000))ms")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $refractoryPeriod, in: 0.1...0.5, step: 0.05) {
                                Text("Refractory Period")
                            } minimumValueLabel: {
                                Text("100")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Text("500")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Minimum time between detections")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Template Length")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(Int(templateLength)) samples")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $templateLength, in: 20...80, step: 5) {
                                Text("Template Length")
                            } minimumValueLabel: {
                                Text("20")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Text("80")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Window size for pattern matching (~\(Int(templateLength * 20))ms at 50Hz)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Quick Presets") {
                    VStack(spacing: 8) {
                        Button("Conservative (Low False Positives)") {
                            setConservativePreset()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        
                        Button("Balanced (Default)") {
                            setDefaultPreset()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        
                        Button("Sensitive (High Detection Rate)") {
                            setSensitivePreset()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
                
                Section("Data Export") {
                    HStack {
                        Text("Export Format")
                        Spacer()
                        Picker("Format", selection: $exportFormat) {
                            Text("JSON").tag("JSON")
                            Text("CSV").tag("CSV")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 120)
                        .onChange(of: exportFormat) { _ in
                            PhoneSessionManager.shared.updateExportFormat()
                        }
                    }
                    
                    SettingRow(title: "Include Raw Sensor Data", value: "Enabled")
                    SettingRow(title: "Include Detection Events", value: "Enabled")
                }
                
                Section("File Access") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session files are automatically saved to:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            if let url = URL(string: "shareddocuments://") {
                                if UIApplication.shared.canOpenURL(url) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "folder")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Files App → Dhikr Counter")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text("Session files in app directory")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.vertical, 4)
                }
                
                Section("About") {
                    SettingRow(title: "Version", value: "1.0")
                    SettingRow(title: "Algorithm Version", value: "Researcher Validated")
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    // MARK: - Preset Configuration Functions
    
    private func setConservativePreset() {
        bandpassLow = 2.0
        bandpassHigh = 15.0
        gateThreshold = 4.5
        accelWeight = 0.8
        gyroWeight = 1.2
        refractoryPeriod = 0.2
        templateConfidence = 0.75
        templateLength = 50
    }
    
    private func setDefaultPreset() {
        bandpassLow = 3.0
        bandpassHigh = 20.0
        gateThreshold = 3.5
        accelWeight = 1.0
        gyroWeight = 1.5
        refractoryPeriod = 0.15
        templateConfidence = 0.6
        templateLength = 40
    }
    
    private func setSensitivePreset() {
        bandpassLow = 4.0
        bandpassHigh = 25.0
        gateThreshold = 2.5
        accelWeight = 1.2
        gyroWeight = 1.8
        refractoryPeriod = 0.1
        templateConfidence = 0.45
        templateLength = 30
    }
}

struct SettingRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

struct EnhancedSessionRowView: View {
    let session: DhikrSession
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    
    var body: some View {
        NavigationLink(destination: DataVisualizationView()) {
            HStack(spacing: 12) {
                // Data visualization mini chart
                VStack {
                    Image(systemName: dataManager.hasSensorData(for: session.id.uuidString) ? "waveform.path.ecg" : "circle.dotted")
                        .font(.title2)
                        .foregroundColor(dataManager.hasSensorData(for: session.id.uuidString) ? .green : .secondary)
                }
                .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Session \(session.id.uuidString.prefix(8))")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(relativeTimeString(from: session.startTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 16) {
                        let sensorCount = dataManager.getSensorDataCount(for: session.id.uuidString)
                        Text("\(sensorCount) readings")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(String(format: "%.1fs", session.sessionDuration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
    
    private func dataSizeString(for readingCount: Int) -> String {
        let bytes = readingCount * 48 // Rough estimate
        if bytes >= 1024 {
            return String(format: "%.1fKB", Double(bytes) / 1024.0)
        } else {
            return "\(bytes)B"
        }
    }
}

struct SessionRowView: View {
    let session: DhikrSession
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(DateFormatter.sessionFormatter.string(from: session.startTime))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 12) {
                    Text("\(session.totalPinches) dhikr")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(session.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if session.detectionAccuracy > 0 {
                        Text("\(Int(session.detectionAccuracy * 100))% accuracy")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

extension DateFormatter {
    static let sessionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

extension DhikrSession {
    var formattedDuration: String {
        let minutes = Int(sessionDuration / 60)
        let seconds = Int(sessionDuration.truncatingRemainder(dividingBy: 60))
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

// MARK: - Preview

struct CompanionContentView_Previews: PreviewProvider {
    static var previews: some View {
        CompanionContentView()
    }
}