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
    var onsetThresholdDb: Float = 15.0

    /// Minimum time between detections (seconds)
    var refractoryPeriod: TimeInterval = 0.25

    /// Smoothing factor for baseline (0-1, lower = slower adaptation)
    var baselineAlpha: Float = 0.01

    /// Buffer size for audio tap (samples)
    let bufferSize: AVAudioFrameCount = 1024

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
        debugLog.removeAll()
        addDebug("Detector reset")
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

    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Compute RMS of the buffer
        let samples = channelData[0]
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameLength))

        // Convert to dB
        let rmsDb = 20 * log10(max(rms, 1e-10))

        // Update baseline with exponential smoothing
        if runningBaseline < -59.0 {
            // Initialize baseline
            runningBaseline = rmsDb
        } else {
            runningBaseline = baselineAlpha * rmsDb + (1 - baselineAlpha) * runningBaseline
        }

        // Check for onset
        let currentTime = Date().timeIntervalSince1970
        let timeSinceLastOnset = currentTime - lastOnsetTimestamp
        let threshold = runningBaseline + onsetThresholdDb

        let isOnset = rmsDb > threshold && timeSinceLastOnset > refractoryPeriod

        // Update UI on main thread
        Task { @MainActor in
            self.currentRMSdB = rmsDb
            self.baselineRMSdB = self.runningBaseline

            if isOnset {
                self.lastOnsetTimestamp = currentTime
                self.onsetCount += 1
                self.lastOnsetTime = Date()

                let spikeDb = rmsDb - self.runningBaseline
                self.addDebug(String(format: "ONSET #%d: %.1f dB above baseline", self.onsetCount, spikeDb))

                // Fire callback
                self.onOnsetDetected?(Date(), spikeDb)
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
