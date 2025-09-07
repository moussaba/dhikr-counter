import SwiftUI

struct ContentView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    @ObservedObject private var sessionManager = WatchSessionManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            // Large counter display
            CounterDisplayView()
            
            // Session state and progress
            SessionInfoView()
                .layoutPriority(0) // Can shrink if needed
            
            // Data transfer status (when active)
            if sessionManager.isTransferring {
                DataTransferStatusView()
                    .layoutPriority(1)
            }
            
            // Control buttons
            ControlButtonsView()
                .layoutPriority(2) // Higher priority to prevent overlap
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

struct CounterDisplayView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    
    var body: some View {
        VStack(spacing: 2) {
            // Main counter - large and prominent
            Text("\(detectionEngine.pinchCount)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .contentTransition(.numericText())
            
            // Session state indicator
            Text(detectionEngine.sessionState.displayText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct SessionInfoView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    
    var body: some View {
        VStack(spacing: 4) {
            // Timer display (always visible, shows current session or last session duration)
            HStack(spacing: 4) {
                Text(detectionEngine.timerText)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(detectionEngine.sessionState != .inactive ? .blue : .secondary)
                    .contentTransition(.numericText())
                
                // Show indicator for last session vs current session
                if detectionEngine.sessionState == .inactive && detectionEngine.lastSessionDuration > 0 {
                    Text("last")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress bar for milestones
            ProgressView(value: detectionEngine.progressValue)
                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                .scaleEffect(y: 1.5)
            
            // Milestone text
            Text(detectionEngine.milestoneText)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }
}

struct DataTransferStatusView: View {
    @ObservedObject private var sessionManager = WatchSessionManager.shared
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "iphone")
                    .foregroundColor(.blue)
                Text("Transferring...")
                    .font(.caption2)
                    .foregroundColor(.blue)
                
                Spacer()
                
                // Show percentage if progress is available
                if sessionManager.transferProgress > 0 {
                    Text("\(Int(sessionManager.transferProgress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                }
            }
            
            // Show determinate progress bar if we have progress, otherwise indeterminate
            if sessionManager.transferProgress > 0 {
                ProgressView(value: sessionManager.transferProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .scaleEffect(y: 1.5)
            } else {
                ProgressView()
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .scaleEffect(y: 1.5)
            }
            
            Text(sessionManager.transferStatus)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }
}

struct ControlButtonsView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    @State private var showingResetConfirmation = false
    
    var body: some View {
        VStack(spacing: 4) {
            // Manual increment and reset buttons (top row)
            HStack(spacing: 8) {
                // Manual increment button
                Button(action: {
                    detectionEngine.manualPinchIncrement()
                }) {
                    Image(systemName: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(detectionEngine.sessionState == .inactive)
                .frame(maxWidth: .infinity)
                
                // Reset button
                Button(action: {
                    showingResetConfirmation = true
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
            }
            
            // Start/Stop button (bottom, full width)
            Button(action: toggleSession) {
                HStack(spacing: 4) {
                    Image(systemName: detectionEngine.sessionState == .inactive ? "play.fill" : "stop.fill")
                        .font(.caption2)
                    Text(detectionEngine.sessionState == .inactive ? "Start" : "Stop")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(false)
        }
        .confirmationDialog("Reset Counter", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) {
                detectionEngine.resetCounter()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will reset your dhikr count to 0.")
        }
    }
    
    private func toggleSession() {
        print("🔵 Start button tapped - current state: \(detectionEngine.sessionState)")
        if detectionEngine.sessionState == .inactive {
            print("🔵 Calling startSession()")
            detectionEngine.startSession()
        } else {
            print("🔵 Calling stopSession()")
            detectionEngine.stopSession()
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DhikrDetectionEngine())
    }
}