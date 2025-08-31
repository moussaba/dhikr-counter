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
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Stats")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                StatCard(title: "Total Sessions", value: "0", color: .blue)
                StatCard(title: "Total Dhikr", value: "0", color: .green)
                StatCard(title: "Average Accuracy", value: "N/A", color: .orange)
                StatCard(title: "Best Session", value: "N/A", color: .purple)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
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
    @State private var isConnected = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Watch")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack {
                Image(systemName: isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(isConnected ? .green : .orange)
                
                Text(isConnected ? "Connected" : "Not Connected")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if !isConnected {
                    Button("Connect") {
                        // WatchConnectivity implementation in Phase 3
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            
            Text("WatchConnectivity integration coming in Phase 3")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

struct RecentSessionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Sessions")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("View All") {
                    // Navigate to sessions view
                }
                .font(.caption)
            }
            
            VStack(spacing: 8) {
                Text("No sessions yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Start a dhikr session on your Apple Watch to see data here")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
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
                    SettingRow(title: "Export Format", value: "CSV")
                    SettingRow(title: "Include Raw Sensor Data", value: "Enabled")
                    SettingRow(title: "Include Detection Events", value: "Enabled")
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

// MARK: - Preview

struct CompanionContentView_Previews: PreviewProvider {
    static var previews: some View {
        CompanionContentView()
    }
}