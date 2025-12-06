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

    // MARK: - IEI-Based Adaptive Filtering

    /// Enable IEI-based filtering (rejects clicks that deviate from learned rhythm)
    var useIEIFiltering: Bool = true

    /// Number of clicks to collect before IEI filtering kicks in (learning period)
    /// During warmup, we learn the user's natural rhythm
    var ieiWarmupClicks: Int = 8

    /// Standard deviation multiplier for outlier detection
    /// Clicks with IEI outside (mean ± stddevMultiplier * stddev) are rejected
    /// 2.5 = ~99% of normal distribution, allows for natural variation
    var ieiStddevMultiplier: Double = 2.5

    /// Minimum standard deviation (ms) to prevent over-filtering with very consistent rhythm
    /// If calculated stddev < this, use this as floor
    var ieiMinStddev: Double = 150.0

    /// Coefficient of Variation threshold - if CV > this, pattern is too variable to filter
    /// CV = stddev/mean; high CV means inconsistent rhythm, don't filter
    var ieiMaxCV: Double = 0.5

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

    /// Last event timestamp (for IEI pattern validation - updated even on rejection)
    private var lastEventTime: Date?

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
        var rejectedIEIOutlier: Int = 0   // IEI outside learned pattern

        // Inter-event interval tracking
        var interEventIntervals: [Double] = []  // ms between consecutive clicks
        var minIEI: Double = 0
        var maxIEI: Double = 0
        var avgIEI: Double = 0

        // Learned rhythm pattern (calculated after warmup)
        var learnedMeanIEI: Double = 0      // Mean IEI from warmup period
        var learnedStddevIEI: Double = 0    // Stddev from warmup period
        var learnedMinBound: Double = 0     // mean - K*stddev
        var learnedMaxBound: Double = 0     // mean + K*stddev
        var rhythmLearned: Bool = false     // True after warmup complete

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
        lastEventTime = nil
        pendingAudioRejections.removeAll()
        recentIMUEvents.removeAll()
        stats = HybridStats()
        debugLog.removeAll()
        addDebug("HybridDetectionManager reset")
    }

    // MARK: - Private Methods

    private func handleAudioConfirmed(timestamp: Date, spikeDb: Float, jump: Float) {
        // Always update lastEventTime for IEI pattern tracking (even if rejected)
        // This ensures we track event intervals, not just accepted click intervals
        defer { lastEventTime = timestamp }

        // Check global refractory
        if !passesGlobalRefractory(timestamp) {
            stats.rejectedRefractory += 1
            addDebug(String(format: "AUDIO confirmed but blocked by refractory (%.0fms since last)",
                           timeSinceLastOutput(timestamp) * 1000))
            return  // lastEventTime still updated via defer
        }

        // Check IEI-based adaptive filtering (learned rhythm)
        let ieiResult = passesIEIFilter(timestamp)
        if !ieiResult.passes {
            stats.rejectedIEIOutlier += 1
            addDebug(String(format: "AUDIO rejected [IEI OUTLIER]: +%.1fdB jump:%.1f - %@",
                           spikeDb, jump, ieiResult.reason ?? "unknown"))
            return  // lastEventTime still updated via defer
        }

        // Audio confirmed - emit click directly
        // Mark any IMU events in association window as consumed (prevent double-counting)
        consumeIMUEventsInWindow(around: timestamp)

        emitClick(source: .audio, timestamp: timestamp)
        stats.audioConfirmed += 1
        addDebug(String(format: "CLICK [AUDIO]: +%.1fdB jump:%.1f IEI:%.0fms", spikeDb, jump, ieiResult.ieiMs))
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

    /// Check if click passes IEI-based adaptive filtering
    /// Uses lastEventTime (not lastClickTime) to track intervals between events
    /// This allows resume after pause: compare to last EVENT, not last ACCEPTED click
    /// Returns (passes: Bool, reason: String?, eventIntervalMs: Double)
    private func passesIEIFilter(_ timestamp: Date) -> (passes: Bool, reason: String?, ieiMs: Double) {
        guard useIEIFiltering else {
            return (true, nil, 0)
        }

        // Use lastEventTime for pattern validation (tracks all events, not just accepted)
        guard let lastEvent = lastEventTime else {
            return (true, nil, 0)  // First event always passes
        }

        let eventIntervalMs = timestamp.timeIntervalSince(lastEvent) * 1000.0

        // During warmup: collect IEIs to learn pattern
        if clickCount < ieiWarmupClicks {
            return (true, nil, eventIntervalMs)
        }

        // At exactly warmup count: learn the rhythm pattern
        if clickCount == ieiWarmupClicks && !stats.rhythmLearned {
            learnRhythmPattern()
        }

        // If rhythm wasn't learned (too variable), don't filter
        guard stats.rhythmLearned else {
            return (true, nil, eventIntervalMs)
        }

        // Grace period: If interval is very long (>3x max bound), user paused
        // Accept this event to re-establish timing
        let pauseThresholdMs = stats.learnedMaxBound * 3.0
        if eventIntervalMs > pauseThresholdMs {
            addDebug(String(format: "IEI: Long pause detected (%.0fms > %.0fms), re-establishing rhythm",
                           eventIntervalMs, pauseThresholdMs))
            return (true, nil, eventIntervalMs)  // Re-establish after pause
        }

        // Check if event interval is within learned bounds
        if eventIntervalMs < stats.learnedMinBound {
            return (false, String(format: "Event interval %.0fms < min %.0fms (too fast)",
                                 eventIntervalMs, stats.learnedMinBound), eventIntervalMs)
        }

        if eventIntervalMs > stats.learnedMaxBound {
            return (false, String(format: "Event interval %.0fms > max %.0fms (too slow)",
                                 eventIntervalMs, stats.learnedMaxBound), eventIntervalMs)
        }

        return (true, nil, eventIntervalMs)
    }

    /// Learn the user's rhythm pattern from warmup IEIs
    private func learnRhythmPattern() {
        let warmupIEIs = stats.interEventIntervals

        guard warmupIEIs.count >= 3 else {
            addDebug("IEI Learning: Not enough data (\(warmupIEIs.count) IEIs)")
            return
        }

        // Calculate mean
        let mean = warmupIEIs.reduce(0, +) / Double(warmupIEIs.count)

        // Calculate standard deviation
        let squaredDiffs = warmupIEIs.map { pow($0 - mean, 2) }
        let variance = squaredDiffs.reduce(0, +) / Double(warmupIEIs.count)
        var stddev = sqrt(variance)

        // Apply minimum stddev floor
        stddev = max(stddev, ieiMinStddev)

        // Calculate coefficient of variation
        let cv = stddev / mean

        // If rhythm is too variable, don't enable filtering
        if cv > ieiMaxCV {
            addDebug(String(format: "IEI Learning: Rhythm too variable (CV=%.2f > %.2f), filtering DISABLED", cv, ieiMaxCV))
            return
        }

        // Calculate bounds
        let minBound = max(100, mean - ieiStddevMultiplier * stddev)  // Floor at 100ms
        let maxBound = mean + ieiStddevMultiplier * stddev

        // Store learned pattern
        stats.learnedMeanIEI = mean
        stats.learnedStddevIEI = stddev
        stats.learnedMinBound = minBound
        stats.learnedMaxBound = maxBound
        stats.rhythmLearned = true

        addDebug(String(format: "IEI Learning: Rhythm learned! mean=%.0fms, stddev=%.0fms, bounds=[%.0f-%.0f]ms",
                       mean, stddev, minBound, maxBound))
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
        lines.append("  IEI Outlier: \(stats.rejectedIEIOutlier)")
        lines.append("")
        lines.append("Inter-Event Intervals:")
        lines.append("  Min: \(String(format: "%.0f", stats.minIEI))ms")
        lines.append("  Max: \(String(format: "%.0f", stats.maxIEI))ms")
        lines.append("  Avg: \(String(format: "%.0f", stats.avgIEI))ms")
        lines.append("")
        if stats.rhythmLearned {
            lines.append("Learned Rhythm:")
            lines.append("  Mean: \(String(format: "%.0f", stats.learnedMeanIEI))ms")
            lines.append("  Stddev: \(String(format: "%.0f", stats.learnedStddevIEI))ms")
            lines.append("  Bounds: [\(String(format: "%.0f", stats.learnedMinBound))-\(String(format: "%.0f", stats.learnedMaxBound))]ms")
            lines.append("")
        }
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
        if debugLog.count > 100 {
            debugLog.removeFirst()
        }

        print("HybridDetection: \(message)")
    }
}
