import Foundation
import AVFoundation
import Accelerate

/// Audio-based pinch detection using Apple Watch microphone
/// Detects sudden onset sounds (clicks/taps) from finger rings or covers
@MainActor
class AudioPinchDetector: ObservableObject {

    // MARK: - Published State

    @Published var isListening = false
    @Published var currentRMSdB: Float = -60.0
    @Published var baselineRMSdB: Float = -60.0
    @Published var lastOnsetTime: Date?
    @Published var onsetCount: Int = 0
    @Published var debugLog: [String] = []

    // MARK: - Audio Engine

    private var audioEngine: AVAudioEngine?
    private let audioQueue = DispatchQueue(label: "com.dhikrcounter.audio", qos: .userInteractive)

    // MARK: - Detection Parameters

    /// Threshold above baseline (in dB) to trigger onset detection
    /// With AND logic, can be lower since jump threshold provides additional filtering
    var onsetThresholdDb: Float = 8.0

    /// Minimum time between detections (seconds)
    var refractoryPeriod: TimeInterval = 0.25

    /// Smoothing factor for baseline adaptation (0-1)
    /// Higher = faster recovery after noise spikes
    var baselineAlpha: Float = 0.03

    /// Don't let spikes raise the baseline - use asymmetric smoothing
    var useAsymmetricBaseline: Bool = true

    /// Buffer size for audio tap (samples) - smaller = faster response
    let bufferSize: AVAudioFrameCount = 512

    // MARK: - Peak Detection State

    /// Track the previous RMS for derivative-based detection
    private var previousRmsDb: Float = -60.0

    /// Minimum jump in dB from one buffer to next to count as onset
    /// Based on testing: real clicks show 15-30 dB jumps, noise shows 2-7 dB
    var minJumpDb: Float = 10.0

    /// Maximum spike above baseline (dB) to accept as a click
    /// Spikes louder than this are likely ambient noise (door slam, cough, loud voice)
    /// Ring clicks are typically +15-30 dB; loud ambient can be +35-50 dB
    var maxSpikeDb: Float = 35.0

    // MARK: - High-Pass Filter State

    /// Biquad filter state (z^-1 and z^-2 for input and output)
    /// Must persist between buffers to avoid discontinuities
    private var hpfState: (x1: Float, x2: Float, y1: Float, y2: Float) = (0, 0, 0, 0)

    /// High-pass filter coefficients for ~3kHz cutoff @ 48kHz sample rate
    /// Butterworth 2nd order HPF - generated using standard biquad formula
    /// These coefficients filter out low-frequency ambient noise while preserving
    /// the high-frequency content of ring clicks (typically 2-8 kHz)
    private let hpfB0: Float = 0.7328934    // Feedforward coefficient b0
    private let hpfB1: Float = -1.4657868   // Feedforward coefficient b1
    private let hpfB2: Float = 0.7328934    // Feedforward coefficient b2
    private let hpfA1: Float = -1.3965850   // Feedback coefficient a1
    private let hpfA2: Float = 0.5349886    // Feedback coefficient a2

    /// Enable/disable high-pass filtering (for A/B testing)
    var useHighPassFilter: Bool = true

    // MARK: - Click Fingerprint Validation State

    /// Tracks a pending spike that needs decay validation
    /// A click must: spike up quickly, then decay quickly (unlike voice which stays elevated)
    private var pendingSpike: PendingSpike?

    /// How many buffers to wait for decay validation (~50ms = 4-5 buffers at 512 samples/48kHz)
    var decayCheckBuffers: Int = 5

    /// Signal must drop below (baseline + this) to confirm decay
    var decayThresholdDb: Float = 5.0

    /// Maximum buffers the signal can stay elevated before rejecting as voice (~100ms max)
    var maxElevatedBuffers: Int = 10

    /// Counter for how many consecutive buffers signal has been elevated
    private var elevatedBufferCount: Int = 0

    /// Flag to wait for signal to return to baseline after voice rejection
    /// Prevents immediate re-triggering while signal is still elevated
    private var waitingForBaseline: Bool = false

    /// Structure to track a spike pending validation
    private struct PendingSpike {
        let timestamp: Date
        let spikeDb: Float
        let jump: Float
        var buffersWaited: Int = 0
    }

    // MARK: - Internal State

    private var lastOnsetTimestamp: TimeInterval = 0
    private var runningBaseline: Float = -60.0
    private var isInitialized = false

    // MARK: - Callbacks

    /// Called when an onset (click sound) is detected
    var onOnsetDetected: ((Date, Float) -> Void)?

    // MARK: - Initialization

    init() {
        addDebug("AudioPinchDetector initialized")
    }

    deinit {
        // Clean up audio engine directly since we can't call MainActor methods in deinit
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    // MARK: - Public Methods

    /// Request microphone permission
    func requestPermission() async -> Bool {
        addDebug("Requesting microphone permission...")

        if #available(watchOS 10.0, *) {
            let status = AVAudioApplication.shared.recordPermission

            switch status {
            case .granted:
                addDebug("Microphone permission already granted")
                return true
            case .denied:
                addDebug("Microphone permission denied")
                return false
            case .undetermined:
                addDebug("Requesting microphone permission from user...")
                let granted = await AVAudioApplication.requestRecordPermission()
                addDebug("Permission result: \(granted)")
                return granted
            @unknown default:
                addDebug("Unknown permission status")
                return false
            }
        } else {
            // Fallback for older watchOS
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    Task { @MainActor in
                        self.addDebug("Permission result (legacy): \(granted)")
                    }
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Start listening for audio onset events
    func startListening() {
        guard !isListening else {
            addDebug("Already listening")
            return
        }

        addDebug("Starting audio capture...")

        audioQueue.async { [weak self] in
            self?.setupAndStartAudioEngine()
        }
    }

    /// Stop listening
    func stopListening() {
        guard isListening else { return }

        addDebug("Stopping audio capture...")

        audioQueue.async { [weak self] in
            self?.teardownAudioEngine()
        }
    }

    /// Reset detection state
    func reset() {
        onsetCount = 0
        lastOnsetTime = nil
        lastOnsetTimestamp = 0
        runningBaseline = -60.0
        previousRmsDb = -60.0
        pendingSpike = nil
        elevatedBufferCount = 0
        waitingForBaseline = false
        resetHighPassFilter()  // Reset HPF state to avoid artifacts
        debugLog.removeAll()
        addDebug("Detector reset (HPF: \(useHighPassFilter ? "ON" : "OFF"))")
    }

    // MARK: - Audio Engine Setup

    private func setupAndStartAudioEngine() {
        do {
            // Configure audio session
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [])
            try session.setActive(true)

            // Create audio engine
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode

            // Get hardware format
            let hwFormat = inputNode.outputFormat(forBus: 0)

            Task { @MainActor in
                self.addDebug("Audio format: \(hwFormat.sampleRate) Hz, \(hwFormat.channelCount) ch")
            }

            // Install tap on input node
            // Important: On watchOS, we tap directly on inputNode without connecting to mixer
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) { [weak self] buffer, time in
                self?.processAudioBuffer(buffer, time: time)
            }

            // Start engine
            try engine.start()

            self.audioEngine = engine
            self.isInitialized = true

            Task { @MainActor in
                self.isListening = true
                self.addDebug("Audio engine started successfully")
            }

        } catch {
            Task { @MainActor in
                self.addDebug("Failed to start audio engine: \(error.localizedDescription)")
            }
        }
    }

    private func teardownAudioEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isInitialized = false

        Task { @MainActor in
            self.isListening = false
            self.addDebug("Audio engine stopped")
        }
    }

    // MARK: - High-Pass Filter

    /// Apply 2nd order Butterworth high-pass filter to isolate high-frequency click sounds
    /// This filters out low-frequency ambient noise (body movement, AC hum, etc.)
    /// while preserving the sharp transients from ring clicks (typically 2-8 kHz)
    ///
    /// Expected effect: Baseline drops from ~-68dB to ~-85dB, effectively +15-20dB sensitivity
    private func applyHighPassFilter(_ samples: UnsafePointer<Float>, count: Int) -> [Float] {
        var output = [Float](repeating: 0, count: count)

        // Direct Form II Biquad implementation
        // y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
        var x1 = hpfState.x1
        var x2 = hpfState.x2
        var y1 = hpfState.y1
        var y2 = hpfState.y2

        for i in 0..<count {
            let x0 = samples[i]

            // Compute filtered output
            let y0 = hpfB0 * x0 + hpfB1 * x1 + hpfB2 * x2 - hpfA1 * y1 - hpfA2 * y2

            output[i] = y0

            // Shift state
            x2 = x1
            x1 = x0
            y2 = y1
            y1 = y0
        }

        // Persist state for next buffer (critical to avoid discontinuities!)
        hpfState = (x1, x2, y1, y2)

        return output
    }

    /// Reset filter state (call when stopping/restarting detection)
    private func resetHighPassFilter() {
        hpfState = (0, 0, 0, 0)
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let samples = channelData[0]

        // Compute signal level - either with HPF or raw
        let signalDb: Float
        if useHighPassFilter {
            // NEW APPROACH: High-pass filter + Peak detection
            // 1. Apply HPF to isolate high-frequency click sounds (removes ambient noise)
            let filtered = applyHighPassFilter(samples, count: frameLength)

            // 2. Use PEAK detection instead of RMS
            // A 0.5ms click gets diluted by ~20x in a 10.7ms RMS window
            // Peak detection finds the actual spike
            var peak: Float = 0
            filtered.withUnsafeBufferPointer { ptr in
                vDSP_maxmgv(ptr.baseAddress!, 1, &peak, vDSP_Length(frameLength))
            }

            // Convert peak to dB
            signalDb = 20 * log10(max(peak, 1e-10))
        } else {
            // OLD APPROACH: Broadband RMS (for A/B comparison)
            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameLength))
            signalDb = 20 * log10(max(rms, 1e-10))
        }

        // Update baseline with asymmetric smoothing
        // Fast decay when quiet, slow rise when loud (to adapt to ambient noise changes)
        if runningBaseline < -90.0 {
            // Initialize baseline
            runningBaseline = signalDb
        } else if useAsymmetricBaseline {
            let aboveBaseline = signalDb - runningBaseline

            if aboveBaseline < 2.0 {
                // Signal is at or below baseline - adapt quickly (normal alpha)
                runningBaseline = baselineAlpha * signalDb + (1 - baselineAlpha) * runningBaseline
            } else if aboveBaseline < onsetThresholdDb {
                // Signal is elevated but below detection threshold
                // Adapt slowly upward (1/10th speed) to handle ambient noise increase
                let slowAlpha = baselineAlpha * 0.1
                runningBaseline = slowAlpha * signalDb + (1 - slowAlpha) * runningBaseline
            }
            // If signal is above threshold (actual spike), don't update baseline
        } else {
            // Symmetric smoothing (old behavior)
            runningBaseline = baselineAlpha * signalDb + (1 - baselineAlpha) * runningBaseline
        }

        // Check for onset using TWO methods:
        // 1. Absolute: signal above baseline + threshold
        // 2. Derivative: sudden jump from previous buffer
        let currentTime = Date().timeIntervalSince1970
        let timeSinceLastOnset = currentTime - lastOnsetTimestamp
        let threshold = runningBaseline + onsetThresholdDb
        let decayLevel = runningBaseline + decayThresholdDb

        // Method 1: Above absolute threshold
        let aboveThreshold = signalDb > threshold

        // Method 2: Sudden jump (derivative)
        let jump = signalDb - previousRmsDb
        let suddenJump = jump > minJumpDb

        // Track if signal is currently elevated (for duration checking)
        let isElevated = signalDb > decayLevel

        // Store for next iteration
        previousRmsDb = signalDb

        // ============================================================
        // CLICK FINGERPRINT VALIDATION
        // A real click: spikes up instantly, decays within ~50-100ms
        // Voice/sustained sounds: rise gradually, stay elevated
        // ============================================================

        // Update UI on main thread
        Task { @MainActor in
            self.currentRMSdB = signalDb
            self.baselineRMSdB = self.runningBaseline

            // STATE MACHINE for click validation
            if let pending = self.pendingSpike {
                // We have a pending spike - check if it decayed (confirming it's a click)
                var updatedPending = pending
                updatedPending.buffersWaited += 1

                if !isElevated {
                    // Signal dropped back down - this IS a click!
                    // Confirm the detection
                    if timeSinceLastOnset > self.refractoryPeriod {
                        self.lastOnsetTimestamp = currentTime
                        self.onsetCount += 1
                        self.lastOnsetTime = Date()

                        let filterMode = self.useHighPassFilter ? "HPF" : "RAW"
                        self.addDebug(String(format: "CLICK #%d [%@]: +%.1fdB (jump:%.1f, decay:%d bufs)",
                                             self.onsetCount, filterMode, pending.spikeDb, pending.jump, updatedPending.buffersWaited))

                        // Fire callback
                        self.onOnsetDetected?(pending.timestamp, pending.spikeDb)
                    }
                    self.pendingSpike = nil
                    self.elevatedBufferCount = 0

                } else if updatedPending.buffersWaited >= self.maxElevatedBuffers {
                    // Signal stayed elevated too long - reject as voice/sustained sound
                    self.addDebug(String(format: "REJECTED [VOICE]: +%.1fdB stayed elevated %d buffers",
                                         pending.spikeDb, updatedPending.buffersWaited))
                    self.pendingSpike = nil
                    self.elevatedBufferCount = 0
                    // IMPORTANT: Wait for signal to return to baseline before accepting new spikes
                    self.waitingForBaseline = true

                } else {
                    // Still waiting for decay
                    self.pendingSpike = updatedPending
                    self.elevatedBufferCount += 1
                }

            } else if self.waitingForBaseline {
                // After voice rejection, wait for signal to drop before accepting new spikes
                if !isElevated {
                    self.waitingForBaseline = false
                    // Now ready to detect new clicks
                }
                // Otherwise keep waiting silently

            } else if aboveThreshold && suddenJump && timeSinceLastOnset > self.refractoryPeriod {
                // New potential spike detected - start validation
                let spikeDb = signalDb - self.runningBaseline

                // Check if spike is TOO LOUD (ambient noise like door slam, cough)
                if spikeDb > self.maxSpikeDb {
                    self.addDebug(String(format: "REJECTED [TOO LOUD]: +%.1fdB > max %.0fdB",
                                         spikeDb, self.maxSpikeDb))
                    // Don't even start validation - immediately reject
                    // Also wait for baseline to prevent rapid re-triggering
                    self.waitingForBaseline = true
                } else {
                    // Valid range - start decay validation
                    self.pendingSpike = PendingSpike(
                        timestamp: Date(),
                        spikeDb: spikeDb,
                        jump: jump
                    )
                    self.elevatedBufferCount = 1
                    // Don't count yet - wait for decay validation
                }
            }
        }
    }

    // MARK: - Debug Logging

    private func addDebug(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(timestamp)] \(message)"

        if Thread.isMainThread {
            debugLog.append(entry)
            if debugLog.count > 100 {
                debugLog.removeFirst()
            }
        } else {
            Task { @MainActor in
                self.debugLog.append(entry)
                if self.debugLog.count > 100 {
                    self.debugLog.removeFirst()
                }
            }
        }

        print("AudioPinchDetector: \(message)")
    }
}

// MARK: - Audio Event Structure

/// Represents a detected audio onset event
struct AudioOnsetEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let epochTime: TimeInterval
    let amplitudeDb: Float
    let spikeAboveBaselineDb: Float

    init(timestamp: Date = Date(), amplitudeDb: Float, spikeDb: Float) {
        self.id = UUID()
        self.timestamp = timestamp
        self.epochTime = timestamp.timeIntervalSince1970
        self.amplitudeDb = amplitudeDb
        self.spikeAboveBaselineDb = spikeDb
    }
}
