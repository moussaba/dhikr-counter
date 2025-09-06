import SwiftUI

struct SessionView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    @State private var showingSessionHistory = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Session statistics
                    SessionStatsView()
                    
                    // Detection algorithm status
                    AlgorithmStatusView()
                    
                    // Session controls
                    SessionControlsView()
                }
                .padding()
            }
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("History") {
                        showingSessionHistory = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingSessionHistory) {
            SessionHistoryView()
        }
    }
}

struct SessionStatsView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Statistics")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                StatRow(label: "Total Count", value: "\(detectionEngine.pinchCount)")
                StatRow(label: "State", value: detectionEngine.sessionState.displayText)
                StatRow(label: "Milestone", value: "\(detectionEngine.currentMilestone)/3")
                StatRow(label: "Progress", value: "\(Int(detectionEngine.progressValue * 100))%")
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }
}

struct AlgorithmStatusView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detection Algorithm")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                StatRow(label: "Sampling Rate", value: "50 Hz")
                StatRow(label: "Accel Threshold", value: "0.05g")
                StatRow(label: "Gyro Threshold", value: "0.18 rad/s")
                StatRow(label: "Refractory Period", value: "250ms")
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }
}

struct SessionControlsView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    @State private var showingDataExport = false
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Session Controls")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                // Export data button
                Button(action: {
                    showingDataExport = true
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export Session Data")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                // Clear logs button
                Button(action: {
                    detectionEngine.clearLogs()
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear Logs")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
        .sheet(isPresented: $showingDataExport) {
            DataExportView()
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

struct SessionHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Session History")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding()
                
                Text("Feature coming in Phase 3")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DataExportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Export Session Data")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                let (sensorData, detectionEvents) = detectionEngine.exportSessionData()
                
                VStack(spacing: 12) {
                    DataSummaryRow(label: "Sensor Readings", count: sensorData.count)
                    DataSummaryRow(label: "Detection Events", count: detectionEvents.count)
                    DataSummaryRow(label: "Total Pinches", count: detectionEngine.pinchCount)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)
                
                Text("Data export to iPhone companion app coming in Phase 3")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DataSummaryRow: View {
    let label: String
    let count: Int
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("\(count)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Preview

struct SessionView_Previews: PreviewProvider {
    static var previews: some View {
        SessionView()
            .environmentObject(DhikrDetectionEngine())
    }
}