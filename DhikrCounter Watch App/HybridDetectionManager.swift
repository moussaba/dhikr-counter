import Foundation

/// Manages hybrid audio + accelerometer pinch detection
/// Implements "Parallel with Audio-Priority Arbitration" architecture:
/// - Audio detection has priority
/// - Accelerometer (TKEO) serves as backup when audio rejects due to noise
/// - Prevents double-counting with temporal association and global refractory
@MainActor
class HybridDetectionManager: ObservableObject {

    // MARK: - Configuration

    /// Association window (±ms) to link audio and IMU events as the same physical pinch
    var associationWindowMs: Double = 75.0

    /// Global refractory period - minimum time between output clicks (ms)
    var globalRefractoryMs: Double = 250.0

    /// NCC threshold for IMU backup mode (when audio rejects)
    /// Lower threshold since audio already detected "something happened"
    var backupNccThreshold: Float = 0.60

    /// NCC threshold for standalone IMU mode (no audio event)
    /// Higher threshold to prevent false positives
    var standaloneNccThreshold: Float = 0.70

    // MARK: - Published State

    /// Total hybrid clicks detected
    @Published var clickCount: Int = 0

    /// Last click timestamp
    @Published var lastClickTime: Date?

    /// Statistics for debugging
    @Published var stats: HybridStats = HybridStats()

    /// Debug log for tuning
    @Published var debugLog: [String] = []

    // MARK: - Internal State

    /// Last output click timestamp (for global refractory)
    private var lastOutputTime: Date?

    /// Recent audio rejections waiting for IMU backup check
    private var pendingAudioRejections: [PendingRejection] = []

    /// Recent IMU events for retrospective matching
    private var recentIMUEvents: [IMUCandidate] = []

    /// Rolling buffer window (seconds)
    private let bufferWindowSec: Double = 0.5

    // MARK: - Callbacks

    /// Called when a hybrid click is confirmed
    var onHybridClick: ((HybridClickSource, Date) -> Void)?

    // MARK: - Types

    /// Source of the detected click
    enum HybridClickSource: String {
        case audio = "AUDIO"           // Audio confirmed directly
        case imuBackup = "IMU_BACKUP"  // Audio rejected but IMU confirmed
        case imuStandalone = "IMU_ONLY" // No audio event, IMU standalone
    }

    /// Statistics for debugging
    struct HybridStats: Codable {
        var audioConfirmed: Int = 0
        var imuBackup: Int = 0
        var imuStandalone: Int = 0
        var rejectedNoImuMatch: Int = 0
        var rejectedRefractory: Int = 0

        // Inter-event interval tracking
        var interEventIntervals: [Double] = []  // ms between consecutive clicks
        var minIEI: Double = 0
        var maxIEI: Double = 0
        var avgIEI: Double = 0

        // Per-source IEI tracking for analysis
        var audioIEIs: [Double] = []
        var imuBackupIEIs: [Double] = []
        var imuStandaloneIEIs: [Double] = []
    }

    /// Pending audio rejection waiting for IMU check
    private struct PendingRejection {
        let reason: AudioDetectionResult.RejectionReason
        let timestamp: Date
        let spikeDb: Float
        let expiresAt: Date
    }

    /// IMU candidate event
    private struct IMUCandidate {
        let event: PinchEvent
        let timestamp: Date
        var consumed: Bool = false
    }

    // MARK: - Initialization

    init() {
        addDebug("HybridDetectionManager initialized")
        addDebug("Config: assocWindow=±\(Int(associationWindowMs))ms, refractory=\(Int(globalRefractoryMs))ms")
        addDebug("NCC thresholds: backup=\(backupNccThreshold), standalone=\(standaloneNccThreshold)")
    }

    // MARK: - Public Methods

    /// Handle audio detection result
    func handleAudioResult(_ result: AudioDetectionResult) {
        cleanupExpiredEvents()

        switch result {
        case .confirmed(let timestamp, let spikeDb, let jump):
            handleAudioConfirmed(timestamp: timestamp, spikeDb: spikeDb, jump: jump)

        case .rejected(let reason, let timestamp, let spikeDb):
            handleAudioRejected(reason: reason, timestamp: timestamp, spikeDb: spikeDb)

        case .noEvent:
            // Nothing to do
            break
        }
    }

    /// Handle IMU (accelerometer/TKEO) detection event
    func handleIMUEvent(_ event: PinchEvent) {
        cleanupExpiredEvents()

        let now = Date()
        let candidate = IMUCandidate(event: event, timestamp: now)

        // Check if this IMU event matches a pending audio rejection
        if let matchedRejection = findMatchingRejection(for: now) {
            // IMU backup mode - audio rejected but IMU confirms
            handleIMUBackup(rejection: matchedRejection, imuEvent: event, timestamp: now)
        } else {
            // No matching audio rejection - check for standalone IMU
            // Store for potential future matching with audio rejection
            recentIMUEvents.append(candidate)

            // Also try standalone IMU detection (higher threshold)
            if event.ncc >= standaloneNccThreshold {
                handleIMUStandalone(event: event, timestamp: now)
            }
        }
    }

    /// Reset all state
    func reset() {
        clickCount = 0
        lastClickTime = nil
        lastOutputTime = nil
        pendingAudioRejections.removeAll()
        recentIMUEvents.removeAll()
        stats = HybridStats()
        debugLog.removeAll()
        addDebug("HybridDetectionManager reset")
    }

    // MARK: - Private Methods

    private func handleAudioConfirmed(timestamp: Date, spikeDb: Float, jump: Float) {
        // Check global refractory
        if !passesGlobalRefractory(timestamp) {
            stats.rejectedRefractory += 1
            addDebug(String(format: "AUDIO confirmed but blocked by refractory (%.0fms since last)",
                           timeSinceLastOutput(timestamp) * 1000))
            return
        }

        // Audio confirmed - emit click directly
        // Mark any IMU events in association window as consumed (prevent double-counting)
        consumeIMUEventsInWindow(around: timestamp)

        let ieiMs = timeSinceLastOutput(timestamp) * 1000
        emitClick(source: .audio, timestamp: timestamp)
        stats.audioConfirmed += 1
        addDebug(String(format: "CLICK [AUDIO]: +%.1fdB jump:%.1f IEI:%.0fms", spikeDb, jump, ieiMs))
    }

    private func handleAudioRejected(reason: AudioDetectionResult.RejectionReason, timestamp: Date, spikeDb: Float) {
        // Only queue for IMU backup if it's a noise-related rejection
        guard reason == .voice || reason == .tooLoud else { return }

        // Check if there's already a matching IMU event (retrospective check)
        if let matchingIMU = findMatchingIMUEvent(for: timestamp) {
            // Found a matching IMU event - confirm as backup
            if passesGlobalRefractory(timestamp) {
                markIMUEventConsumed(matchingIMU)
                emitClick(source: .imuBackup, timestamp: timestamp)
                stats.imuBackup += 1
                addDebug(String(format: "CLICK [IMU_BACKUP]: Audio rejected (%@) but IMU matched (NCC=%.2f)",
                               reason.rawValue, matchingIMU.event.ncc))
            } else {
                stats.rejectedRefractory += 1
                addDebug(String(format: "IMU_BACKUP blocked by refractory"))
            }
            return
        }

        // No IMU match yet - queue for future IMU events
        let expiry = timestamp.addingTimeInterval(associationWindowMs / 1000.0)
        let pending = PendingRejection(reason: reason, timestamp: timestamp, spikeDb: spikeDb, expiresAt: expiry)
        pendingAudioRejections.append(pending)

        addDebug(String(format: "Audio REJECTED [%@] +%.1fdB - waiting for IMU backup",
                       reason.rawValue, spikeDb))
    }

    private func handleIMUBackup(rejection: PendingRejection, imuEvent: PinchEvent, timestamp: Date) {
        // Remove the matched rejection from pending list
        pendingAudioRejections.removeAll { $0.timestamp == rejection.timestamp }

        // Check global refractory
        guard passesGlobalRefractory(timestamp) else {
            stats.rejectedRefractory += 1
            addDebug("IMU_BACKUP blocked by refractory")
            return
        }

        // Check NCC threshold for backup mode
        guard imuEvent.ncc >= backupNccThreshold else {
            stats.rejectedNoImuMatch += 1
            addDebug(String(format: "IMU_BACKUP rejected: NCC %.2f < %.2f threshold",
                           imuEvent.ncc, backupNccThreshold))
            return
        }

        // Emit backup click
        let ieiMs = timeSinceLastOutput(timestamp) * 1000
        emitClick(source: .imuBackup, timestamp: timestamp)
        stats.imuBackup += 1
        addDebug(String(format: "CLICK [IMU_BACKUP]: Audio rejected (%@) +%.1fdB, IMU (NCC=%.2f) IEI:%.0fms",
                       rejection.reason.rawValue, rejection.spikeDb, imuEvent.ncc, ieiMs))
    }

    private func handleIMUStandalone(event: PinchEvent, timestamp: Date) {
        // DISABLED: Standalone IMU mode causes too many phantom clicks from wrist motion
        // IMU is now only used as backup when audio rejects due to noise
        // To re-enable: remove this early return and uncomment the code below
        addDebug(String(format: "IMU standalone DISABLED (NCC=%.2f) - IMU only used as backup", event.ncc))
        return

        /*
        // Check global refractory
        guard passesGlobalRefractory(timestamp) else {
            stats.rejectedRefractory += 1
            return
        }

        // Check if there's any recent audio activity (confirmed or pending)
        // If audio is active, don't emit standalone to avoid double-counting
        if hasRecentAudioActivity(around: timestamp) {
            return
        }

        // Emit standalone click
        let ieiMs = timeSinceLastOutput(timestamp) * 1000
        emitClick(source: .imuStandalone, timestamp: timestamp)
        stats.imuStandalone += 1
        addDebug(String(format: "CLICK [IMU_ONLY]: No audio, IMU standalone (NCC=%.2f) IEI:%.0fms", event.ncc, ieiMs))
        */
    }

    private func emitClick(source: HybridClickSource, timestamp: Date) {
        // Calculate inter-event interval
        var ieiMs: Double = 0
        if let lastTime = lastClickTime {
            ieiMs = timestamp.timeIntervalSince(lastTime) * 1000.0
            stats.interEventIntervals.append(ieiMs)

            // Update per-source IEI
            switch source {
            case .audio:
                stats.audioIEIs.append(ieiMs)
            case .imuBackup:
                stats.imuBackupIEIs.append(ieiMs)
            case .imuStandalone:
                stats.imuStandaloneIEIs.append(ieiMs)
            }

            // Update min/max/avg IEI
            if stats.minIEI == 0 || ieiMs < stats.minIEI {
                stats.minIEI = ieiMs
            }
            if ieiMs > stats.maxIEI {
                stats.maxIEI = ieiMs
            }
            let totalIEI = stats.interEventIntervals.reduce(0, +)
            stats.avgIEI = totalIEI / Double(stats.interEventIntervals.count)
        }

        clickCount += 1
        lastClickTime = timestamp
        lastOutputTime = timestamp

        onHybridClick?(source, timestamp)
    }

    // MARK: - Helper Methods

    private func passesGlobalRefractory(_ timestamp: Date) -> Bool {
        guard let lastOutput = lastOutputTime else { return true }
        let elapsed = timestamp.timeIntervalSince(lastOutput)
        return elapsed >= (globalRefractoryMs / 1000.0)
    }

    private func timeSinceLastOutput(_ timestamp: Date) -> TimeInterval {
        guard let lastOutput = lastOutputTime else { return .infinity }
        return timestamp.timeIntervalSince(lastOutput)
    }

    private func findMatchingRejection(for timestamp: Date) -> PendingRejection? {
        let windowSec = associationWindowMs / 1000.0
        return pendingAudioRejections.first { rejection in
            let delta = abs(timestamp.timeIntervalSince(rejection.timestamp))
            return delta <= windowSec
        }
    }

    private func findMatchingIMUEvent(for timestamp: Date) -> IMUCandidate? {
        let windowSec = associationWindowMs / 1000.0
        return recentIMUEvents.first { candidate in
            guard !candidate.consumed else { return false }
            let delta = abs(timestamp.timeIntervalSince(candidate.timestamp))
            return delta <= windowSec && candidate.event.ncc >= backupNccThreshold
        }
    }

    private func consumeIMUEventsInWindow(around timestamp: Date) {
        let windowSec = associationWindowMs / 1000.0
        for i in 0..<recentIMUEvents.count {
            let delta = abs(timestamp.timeIntervalSince(recentIMUEvents[i].timestamp))
            if delta <= windowSec {
                recentIMUEvents[i].consumed = true
            }
        }
    }

    private func markIMUEventConsumed(_ candidate: IMUCandidate) {
        if let index = recentIMUEvents.firstIndex(where: { $0.timestamp == candidate.timestamp }) {
            recentIMUEvents[index].consumed = true
        }
    }

    private func hasRecentAudioActivity(around timestamp: Date) -> Bool {
        let windowSec = associationWindowMs / 1000.0
        // Check pending rejections
        let hasPendingRejection = pendingAudioRejections.contains { rejection in
            let delta = abs(timestamp.timeIntervalSince(rejection.timestamp))
            return delta <= windowSec
        }
        return hasPendingRejection
    }

    private func cleanupExpiredEvents() {
        let now = Date()

        // Remove expired pending rejections
        pendingAudioRejections.removeAll { rejection in
            let isExpired = now > rejection.expiresAt
            if isExpired {
                stats.rejectedNoImuMatch += 1
                addDebug(String(format: "Audio rejection expired [%@] - no IMU backup found",
                               rejection.reason.rawValue))
            }
            return isExpired
        }

        // Remove old IMU events (older than buffer window)
        let cutoff = now.addingTimeInterval(-bufferWindowSec)
        recentIMUEvents.removeAll { $0.timestamp < cutoff }
    }

    // MARK: - Stats Summary

    /// Get stats for transfer to iOS
    func getStatsForTransfer() -> HybridStats {
        return stats
    }

    /// Generate a summary string for debugging
    func getStatsSummary() -> String {
        var lines: [String] = []
        lines.append("=== Hybrid Detection Summary ===")
        lines.append("Total Clicks: \(clickCount)")
        lines.append("  Audio Confirmed: \(stats.audioConfirmed)")
        lines.append("  IMU Backup: \(stats.imuBackup)")
        lines.append("  IMU Standalone: \(stats.imuStandalone)")
        lines.append("")
        lines.append("Rejections:")
        lines.append("  No IMU Match: \(stats.rejectedNoImuMatch)")
        lines.append("  Refractory: \(stats.rejectedRefractory)")
        lines.append("")
        lines.append("Inter-Event Intervals:")
        lines.append("  Min: \(String(format: "%.0f", stats.minIEI))ms")
        lines.append("  Max: \(String(format: "%.0f", stats.maxIEI))ms")
        lines.append("  Avg: \(String(format: "%.0f", stats.avgIEI))ms")
        lines.append("")
        lines.append("Config:")
        lines.append("  Association Window: ±\(Int(associationWindowMs))ms")
        lines.append("  Global Refractory: \(Int(globalRefractoryMs))ms")
        lines.append("  Backup NCC: \(backupNccThreshold)")
        lines.append("  Standalone NCC: \(standaloneNccThreshold)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Debug Logging

    private func addDebug(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(timestamp)] \(message)"

        debugLog.append(entry)
        if debugLog.count > 50 {
            debugLog.removeFirst()
        }

        print("HybridDetection: \(message)")
    }
}
