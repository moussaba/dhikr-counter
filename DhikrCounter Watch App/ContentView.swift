import SwiftUI

struct ContentView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    
    var body: some View {
        VStack(spacing: 8) {
            // Large counter display
            CounterDisplayView()
            
            // Session state and progress
            SessionInfoView()
            
            // Control buttons
            ControlButtonsView()
        }
        .padding(.horizontal, 4)
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

struct ControlButtonsView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    @State private var showingResetConfirmation = false
    
    var body: some View {
        VStack(spacing: 6) {
            // Start/Stop button
            Button(action: toggleSession) {
                HStack(spacing: 4) {
                    Image(systemName: detectionEngine.sessionState == .inactive ? "play.fill" : "stop.fill")
                        .font(.caption2)
                    Text(detectionEngine.sessionState == .inactive ? "Start" : "Stop")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity, minHeight: 20)
            }
            .buttonStyle(.borderedProminent)
            .disabled(false)
            
            HStack(spacing: 12) {
                // Manual increment button
                Button(action: {
                    detectionEngine.manualPinchIncrement()
                }) {
                    Image(systemName: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .disabled(detectionEngine.sessionState == .inactive)
                .frame(width: 40, height: 32)
                
                // Reset button
                Button(action: {
                    showingResetConfirmation = true
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .frame(width: 40, height: 32)
            }
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
        if detectionEngine.sessionState == .inactive {
            detectionEngine.startSession()
        } else {
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