import SwiftUI

struct DataVisualizationView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            VStack {
                // Tab picker
                Picker("Visualization Type", selection: $selectedTab) {
                    Text("Timeline").tag(0)
                    Text("Analysis").tag(1)
                    Text("Export").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content based on selection
                switch selectedTab {
                case 0:
                    TimelineVisualizationView()
                case 1:
                    AnalysisVisualizationView()
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
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Session \(session.id.uuidString.prefix(8))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(DateFormatter.sessionFormatter.string(from: session.startTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let notes = session.sessionNotes, notes.contains("sensor readings") {
                    let readingCount = notes.split(separator: " ").first(where: { $0.allSatisfy { $0.isNumber } }) ?? "0"
                    Text("\(readingCount) sensor readings")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            Image(systemName: "waveform.path.ecg")
                .font(.caption)
                .foregroundColor(.secondary)
        }
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

struct DataVisualizationView_Previews: PreviewProvider {
    static var previews: some View {
        DataVisualizationView()
    }
}