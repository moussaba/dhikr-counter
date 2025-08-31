import SwiftUI

struct ContentView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                // Large counter display
                CounterDisplayView()
                
                // Session state and progress
                SessionInfoView()
                
                // Control buttons
                ControlButtonsView()
            }
            .padding()
            .navigationTitle("Dhikr")
        }
    }
}

struct CounterDisplayView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    
    var body: some View {
        VStack(spacing: 4) {
            // Main counter - large and prominent
            Text("\(detectionEngine.pinchCount)")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .contentTransition(.numericText())
            
            // Session state indicator
            Text(detectionEngine.sessionState.displayText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct SessionInfoView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    
    var body: some View {
        VStack(spacing: 8) {
            // Progress bar for milestones
            ProgressView(value: detectionEngine.progressValue)
                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                .scaleEffect(y: 2.0)
            
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
        VStack(spacing: 8) {
            // Start/Stop button
            Button(action: toggleSession) {
                HStack {
                    Image(systemName: detectionEngine.sessionState == .inactive ? "play.fill" : "stop.fill")
                    Text(detectionEngine.sessionState == .inactive ? "Start" : "Stop")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(false)
            
            HStack(spacing: 12) {
                // Manual increment button
                Button(action: {
                    detectionEngine.manualPinchIncrement()
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(detectionEngine.sessionState == .inactive)
                
                // Reset button
                Button(action: {
                    showingResetConfirmation = true
                }) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
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