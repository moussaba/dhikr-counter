import SwiftUI

struct ContentView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    @ObservedObject private var sessionManager = WatchSessionManager.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Main dhikr counter view
            MainDhikrView()
                .tag(0)

            // Settings view (swipe left to access)
            SettingsListView()
                .tag(1)
        }
        .tabViewStyle(.verticalPage) // Vertical swipe on watchOS
    }
}

/// Main dhikr counter and controls
struct MainDhikrView: View {
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

/// Settings list view showing all TKEO parameters
struct SettingsListView: View {
    @ObservedObject private var sessionManager = WatchSessionManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.blue)
                    Text("Settings")
                        .font(.headline)
                    Spacer()
                    if sessionManager.tkeoSettingsReceived {
                        Image(systemName: "checkmark.icloud.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                .padding(.bottom, 4)

                // Last sync time
                if let syncTime = sessionManager.lastSyncTime {
                    Text("Last sync: \(syncTime, formatter: timeFormatter)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Recently changed section
                if !sessionManager.recentlyChangedSettings.isEmpty {
                    Divider()
                    Text("Recently Changed")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, 4)

                    ForEach(sessionManager.recentlyChangedSettings.prefix(5)) { change in
                        RecentChangeRow(change: change)
                    }
                }

                Divider()

                // All settings
                Text("All Parameters")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                let settings = sessionManager.getAllSettingsForDisplay()
                ForEach(settings) { setting in
                    SettingRow(setting: setting)
                }

                if settings.isEmpty {
                    Text("No settings synced yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
}

/// Row showing a recently changed setting
struct RecentChangeRow: View {
    let change: ChangedSetting

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(change.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.orange)
            HStack(spacing: 4) {
                Text(change.oldValue)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .strikethrough()
                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Text(change.newValue)
                    .font(.system(size: 10))
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Row showing a single setting value
struct SettingRow: View {
    let setting: SettingValue

    var body: some View {
        HStack {
            Text(setting.displayName)
                .font(.caption2)
                .foregroundColor(setting.wasRecentlyChanged ? .orange : .primary)
            Spacer()
            Text(setting.value)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(setting.wasRecentlyChanged ? .green : .secondary)
        }
        .padding(.vertical, 1)
        .background(setting.wasRecentlyChanged ? Color.orange.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}

struct CounterDisplayView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    @ObservedObject private var sessionManager = WatchSessionManager.shared

    var body: some View {
        VStack(spacing: 2) {
            // Main counter - large and prominent
            // Note: uiRefreshTrigger forces SwiftUI to re-render even if watchOS batches updates
            Text("\(detectionEngine.pinchCount)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .contentTransition(.numericText())
                .id(detectionEngine.uiRefreshTrigger)  // Force redraw on each detection

            // Session state with sync indicator
            HStack(spacing: 4) {
                Text(detectionEngine.sessionState.displayText)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // Sync status indicator (small dot)
                SyncStatusIndicator(isSettingsSynced: sessionManager.tkeoSettingsReceived)
            }
        }
    }
}

/// Small indicator showing if settings are synced from iPhone
/// Flashes when a new sync is received
struct SyncStatusIndicator: View {
    let isSettingsSynced: Bool
    @ObservedObject private var sessionManager = WatchSessionManager.shared
    @State private var flashScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 6, height: 6)
                .scaleEffect(flashScale)
            Text(statusText)
                .font(.system(size: 8))
                .foregroundColor(indicatorColor)
        }
        .opacity(0.8)
        .onChange(of: sessionManager.syncFlashActive) { _, isFlashing in
            if isFlashing {
                // Animate the flash
                withAnimation(.easeInOut(duration: 0.3).repeatCount(3, autoreverses: true)) {
                    flashScale = 1.5
                }
                // Reset after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        flashScale = 1.0
                    }
                }
            }
        }
    }

    private var indicatorColor: Color {
        if sessionManager.syncFlashActive {
            return .cyan // Bright flash color when syncing
        }
        return isSettingsSynced ? .green : .orange
    }

    private var statusText: String {
        if sessionManager.syncFlashActive {
            return "syncing!"
        }
        return isSettingsSynced ? "synced" : "local"
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