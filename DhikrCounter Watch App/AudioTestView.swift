import SwiftUI

/// Test view for audio-based pinch detection
/// Use this to experiment with microphone-based click detection
struct AudioTestView: View {
    @StateObject private var audioDetector = AudioPinchDetector()
    @State private var permissionGranted = false
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Status indicator
                statusSection

                // Level meters
                if audioDetector.isListening {
                    levelMetersSection
                }

                // Detection count
                detectionSection

                // Controls
                controlsSection

                // Settings
                if showingSettings {
                    settingsSection
                }
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("Audio Test")
        .task {
            permissionGranted = await audioDetector.requestPermission()
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: "gear")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        if !permissionGranted {
            return .red
        } else if audioDetector.isListening {
            return .green
        } else {
            return .yellow
        }
    }

    private var statusText: String {
        if !permissionGranted {
            return "No microphone access"
        } else if audioDetector.isListening {
            return "Listening..."
        } else {
            return "Ready"
        }
    }

    // MARK: - Level Meters

    private var levelMetersSection: some View {
        VStack(spacing: 8) {
            // Current level
            LevelMeter(
                label: "Level",
                valueDb: audioDetector.currentRMSdB,
                minDb: -60,
                maxDb: 0,
                thresholdDb: audioDetector.baselineRMSdB + audioDetector.onsetThresholdDb
            )

            // Baseline + threshold indicator
            HStack {
                Text("Baseline:")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(String(format: "%.0f dB", audioDetector.baselineRMSdB))
                    .font(.system(size: 10, design: .monospaced))

                Spacer()

                Text("Threshold:")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(String(format: "+%.0f dB", audioDetector.onsetThresholdDb))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.orange)
            }
        }
        .padding(8)
        .background(Color(.darkGray).opacity(0.3))
        .cornerRadius(8)
    }

    // MARK: - Detection Section

    private var detectionSection: some View {
        VStack(spacing: 4) {
            Text("\(audioDetector.onsetCount)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.green)

            Text("clicks detected")
                .font(.caption2)
                .foregroundColor(.secondary)

            if let lastTime = audioDetector.lastOnsetTime {
                Text("Last: \(lastTime, style: .time)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        HStack(spacing: 12) {
            Button {
                if audioDetector.isListening {
                    audioDetector.stopListening()
                } else {
                    audioDetector.startListening()
                }
            } label: {
                Label(
                    audioDetector.isListening ? "Stop" : "Start",
                    systemImage: audioDetector.isListening ? "stop.fill" : "mic.fill"
                )
                .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(audioDetector.isListening ? .red : .blue)
            .disabled(!permissionGranted)

            Button {
                audioDetector.reset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detection Settings")
                .font(.caption)
                .fontWeight(.semibold)

            // Threshold slider
            VStack(alignment: .leading, spacing: 2) {
                Text("Onset Threshold: \(Int(audioDetector.onsetThresholdDb)) dB")
                    .font(.system(size: 10))
                Slider(value: $audioDetector.onsetThresholdDb, in: 5...30, step: 1)
            }

            // Refractory period
            VStack(alignment: .leading, spacing: 2) {
                Text("Refractory: \(Int(audioDetector.refractoryPeriod * 1000)) ms")
                    .font(.system(size: 10))
                Slider(value: $audioDetector.refractoryPeriod, in: 0.1...0.5, step: 0.05)
            }
        }
        .padding(8)
        .background(Color(.darkGray).opacity(0.3))
        .cornerRadius(8)
    }
}

// MARK: - Level Meter Component

struct LevelMeter: View {
    let label: String
    let valueDb: Float
    let minDb: Float
    let maxDb: Float
    let thresholdDb: Float?

    private var normalizedValue: CGFloat {
        let clamped = max(minDb, min(maxDb, valueDb))
        return CGFloat((clamped - minDb) / (maxDb - minDb))
    }

    private var normalizedThreshold: CGFloat? {
        guard let threshold = thresholdDb else { return nil }
        let clamped = max(minDb, min(maxDb, threshold))
        return CGFloat((clamped - minDb) / (maxDb - minDb))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.0f dB", valueDb))
                    .font(.system(size: 10, design: .monospaced))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))

                    // Level bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(levelColor)
                        .frame(width: geo.size.width * normalizedValue)

                    // Threshold marker
                    if let thresh = normalizedThreshold {
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2)
                            .offset(x: geo.size.width * thresh - 1)
                    }
                }
            }
            .frame(height: 16)
        }
    }

    private var levelColor: Color {
        if let thresh = thresholdDb, valueDb > thresh {
            return .green
        } else if valueDb > -20 {
            return .yellow
        } else {
            return .blue
        }
    }
}

#Preview {
    NavigationStack {
        AudioTestView()
    }
}
