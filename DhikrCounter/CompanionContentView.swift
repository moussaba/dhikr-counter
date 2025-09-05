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
    
    var body: some View {
        NavigationStack {
            List {
                Section("Detection Algorithm") {
                    SettingRow(title: "Accelerometer Threshold", value: "0.05g")
                    SettingRow(title: "Gyroscope Threshold", value: "0.18 rad/s")
                    SettingRow(title: "Sampling Rate", value: "100 Hz")
                    SettingRow(title: "Refractory Period", value: "250ms")
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
        NavigationLink(destination: SessionDetailView(session: session)) {
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