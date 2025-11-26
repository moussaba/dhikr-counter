import Foundation

// MARK: - Shared Types for Pinch Detection
// This file is shared between iOS and watchOS targets

/// Single sensor sample for streaming processing
public struct SensorFrame {
    public let t: TimeInterval
    public let ax, ay, az: Float  // m/s² (user acceleration)
    public let gx, gy, gz: Float  // rad/s (rotation rate)

    public init(t: TimeInterval, ax: Float, ay: Float, az: Float, gx: Float, gy: Float, gz: Float) {
        self.t = t
        self.ax = ax
        self.ay = ay
        self.az = az
        self.gx = gx
        self.gy = gy
        self.gz = gz
    }
}

/// Detected pinch event result
public struct PinchEvent {
    public let tPeak, tStart, tEnd: TimeInterval
    public let confidence, gateScore, ncc: Float

    public init(tPeak: TimeInterval, tStart: TimeInterval, tEnd: TimeInterval, confidence: Float, gateScore: Float, ncc: Float) {
        self.tPeak = tPeak
        self.tStart = tStart
        self.tEnd = tEnd
        self.confidence = confidence
        self.gateScore = gateScore
        self.ncc = ncc
    }
}

/// Configuration for pinch detection algorithm
public struct PinchConfig {
    public let fs: Float
    public let bandpassLow: Float
    public let bandpassHigh: Float
    public let accelWeight: Float
    public let gyroWeight: Float
    public let madWinSec: Float
    public let gateK: Float
    public let refractoryMs: Float
    public let minWidthMs: Float
    public let maxWidthMs: Float
    public let nccThresh: Float
    public let windowPreMs: Float
    public let windowPostMs: Float

    // Bookend spike protection parameters
    public let ignoreStartMs: Float
    public let ignoreEndMs: Float
    public let gateRampMs: Float
    public let gyroVetoThresh: Float     // rad/s
    public let gyroVetoHoldMs: Float     // require quiet for this long before enabling
    public let amplitudeSurplusThresh: Float  // σ over local MAD baseline required
    public let preQuietMs: Float         // pre-silence requirement
    public let isiThresholdMs: Float     // inter-spike interval threshold (ms)

    /// Convenience initializer with default values optimized for Watch
    public init(
        fs: Float = 50.0,
        bandpassLow: Float = 3.0,
        bandpassHigh: Float = 20.0,
        accelWeight: Float = 1.0,
        gyroWeight: Float = 1.5,
        madWinSec: Float = 3.0,
        gateK: Float = 3.5,
        refractoryMs: Float = 150,
        minWidthMs: Float = 60,
        maxWidthMs: Float = 400,
        nccThresh: Float = 0.55,
        windowPreMs: Float = 150,
        windowPostMs: Float = 250,
        ignoreStartMs: Float = 500,
        ignoreEndMs: Float = 500,
        gateRampMs: Float = 1000,
        gyroVetoThresh: Float = 1.2,
        gyroVetoHoldMs: Float = 180,
        amplitudeSurplusThresh: Float = 2.0,
        preQuietMs: Float = 150,
        isiThresholdMs: Float = 220
    ) {
        self.fs = fs
        self.bandpassLow = bandpassLow
        self.bandpassHigh = bandpassHigh
        self.accelWeight = accelWeight
        self.gyroWeight = gyroWeight
        self.madWinSec = madWinSec
        self.gateK = gateK
        self.refractoryMs = refractoryMs
        self.minWidthMs = minWidthMs
        self.maxWidthMs = maxWidthMs
        self.nccThresh = nccThresh
        self.windowPreMs = windowPreMs
        self.windowPostMs = windowPostMs
        self.ignoreStartMs = ignoreStartMs
        self.ignoreEndMs = ignoreEndMs
        self.gateRampMs = gateRampMs
        self.gyroVetoThresh = gyroVetoThresh
        self.gyroVetoHoldMs = gyroVetoHoldMs
        self.amplitudeSurplusThresh = amplitudeSurplusThresh
        self.preQuietMs = preQuietMs
        self.isiThresholdMs = isiThresholdMs
    }

    /// Factory method for Watch-optimized defaults (tuned for better precision)
    public static func watchDefaults() -> PinchConfig {
        return PinchConfig(
            fs: 50.0,
            bandpassLow: 3.0,
            bandpassHigh: 20.0,
            accelWeight: 1.0,
            gyroWeight: 1.5,
            madWinSec: 3.0,
            gateK: 3.5,                    // Increased from 3.0 for fewer false positives
            refractoryMs: 150,
            minWidthMs: 70,
            maxWidthMs: 350,
            nccThresh: 0.60,               // Increased from 0.55 for better template matching
            windowPreMs: 150,
            windowPostMs: 150,
            ignoreStartMs: 200,
            ignoreEndMs: 200,
            gateRampMs: 0,
            gyroVetoThresh: 2.5,           // Decreased from 3.0 for motion rejection
            gyroVetoHoldMs: 100,           // Increased from 50 for longer quiet period
            amplitudeSurplusThresh: 2.5,   // Increased from 2.0 for stronger signals only
            preQuietMs: 0,
            isiThresholdMs: 250            // Increased from 220 for better separation
        )
    }
}

/// Template for pinch pattern matching
public struct PinchTemplate {
    public let fs: Float
    public let preMs: Float
    public let postMs: Float
    public let vectorLength: Int
    public let data: [Float]
    public let channelsMeta: String
    public let version: String

    public init(fs: Float, preMs: Float, postMs: Float, vectorLength: Int, data: [Float], channelsMeta: String, version: String) {
        self.fs = fs
        self.preMs = preMs
        self.postMs = postMs
        self.vectorLength = vectorLength
        self.data = data
        self.channelsMeta = channelsMeta
        self.version = version
    }

    /// Load trained templates from bundle
    /// Returns array of trained templates, or falls back to default Gaussian if loading fails
    public static func loadTrainedTemplates(fs: Float = 50.0) -> [PinchTemplate] {
        guard let path = Bundle.main.path(forResource: "trained_templates", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let templatesArray = json["templates"] as? [[Double]] else {
            print("⚠️ Failed to load trained_templates.json, using synthetic template")
            return [createDefault(fs: fs)]
        }

        // Calculate correct pre/post timing from actual template length
        let templateLength = templatesArray.first?.count ?? 16
        // Template length = preS + postS + 1, so: preS + postS = templateLength - 1
        let totalSamples = templateLength - 1  // preS + postS combined
        let preS = totalSamples / 2
        let postS = totalSamples - preS  // Handle odd numbers correctly
        let preMs = Float(preS) / fs * 1000
        let postMs = Float(postS) / fs * 1000

        print("✅ Loaded \(templatesArray.count) trained templates from JSON")
        print("📏 Template timing: \(templateLength) samples = \(String(format: "%.0f", preMs + postMs))ms total (\(String(format: "%.0f", preMs))ms + \(String(format: "%.0f", postMs))ms)")

        return templatesArray.enumerated().map { (index, templateDoubles) in
            let templateData = templateDoubles.map { Float($0) }
            return PinchTemplate(
                fs: fs,
                preMs: preMs,
                postMs: postMs,
                vectorLength: templateData.count,
                data: templateData,
                channelsMeta: "fused_signal_template_\(index + 1)",
                version: "trained_v1"
            )
        }
    }

    /// Create a default Gaussian template for pinch detection
    public static func createDefault(fs: Float = 50.0, preMs: Float = 150, postMs: Float = 150) -> PinchTemplate {
        let preS = Int(round(preMs * fs / 1000))
        let postS = Int(round(postMs * fs / 1000))
        let L = preS + postS + 1

        var data = [Float](repeating: 0, count: L)
        for i in 0..<L {
            let t = Float(i) / Float(max(L-1, 1))
            data[i] = exp(-pow((t - 0.5) * 6, 2))
        }

        return PinchTemplate(
            fs: fs,
            preMs: preMs,
            postMs: postMs,
            vectorLength: L,
            data: data,
            channelsMeta: "fused_tkeo",
            version: "default_gaussian_v1"
        )
    }
}

// MARK: - Watch Detector Metadata

/// Metadata about Watch's pinch detection configuration and results
/// Transferred from Watch to iPhone with session data for debugging/comparison
public struct WatchDetectorMetadata: Codable {
    // Config source
    public let configSource: String  // "synced" or "defaults"
    public let settingsReceivedFromPhone: Bool

    // All config parameters
    public let fs: Float
    public let bandpassLow: Float
    public let bandpassHigh: Float
    public let accelWeight: Float
    public let gyroWeight: Float
    public let madWinSec: Float
    public let gateK: Float
    public let refractoryMs: Float
    public let minWidthMs: Float
    public let maxWidthMs: Float
    public let nccThresh: Float
    public let windowPreMs: Float
    public let windowPostMs: Float
    public let ignoreStartMs: Float
    public let ignoreEndMs: Float
    public let gateRampMs: Float
    public let gyroVetoThresh: Float
    public let gyroVetoHoldMs: Float
    public let amplitudeSurplusThresh: Float
    public let preQuietMs: Float
    public let isiThresholdMs: Float
    public let useTemplateValidation: Bool

    // Detection statistics
    public let totalPinchesDetected: Int
    public let candidatesRejectedByTemplate: Int
    public let candidatesRejectedByGyroVeto: Int
    public let candidatesRejectedByAmplitude: Int
    public let candidatesRejectedByISI: Int
    public let totalCandidatesEvaluated: Int

    // Signal statistics
    public let avgGateScore: Float
    public let avgNCC: Float
    public let avgConfidence: Float
    public let sessionDurationSeconds: Float

    public init(
        configSource: String,
        settingsReceivedFromPhone: Bool,
        fs: Float,
        bandpassLow: Float,
        bandpassHigh: Float,
        accelWeight: Float,
        gyroWeight: Float,
        madWinSec: Float,
        gateK: Float,
        refractoryMs: Float,
        minWidthMs: Float,
        maxWidthMs: Float,
        nccThresh: Float,
        windowPreMs: Float,
        windowPostMs: Float,
        ignoreStartMs: Float,
        ignoreEndMs: Float,
        gateRampMs: Float,
        gyroVetoThresh: Float,
        gyroVetoHoldMs: Float,
        amplitudeSurplusThresh: Float,
        preQuietMs: Float,
        isiThresholdMs: Float,
        useTemplateValidation: Bool,
        totalPinchesDetected: Int,
        candidatesRejectedByTemplate: Int,
        candidatesRejectedByGyroVeto: Int,
        candidatesRejectedByAmplitude: Int,
        candidatesRejectedByISI: Int,
        totalCandidatesEvaluated: Int,
        avgGateScore: Float,
        avgNCC: Float,
        avgConfidence: Float,
        sessionDurationSeconds: Float
    ) {
        self.configSource = configSource
        self.settingsReceivedFromPhone = settingsReceivedFromPhone
        self.fs = fs
        self.bandpassLow = bandpassLow
        self.bandpassHigh = bandpassHigh
        self.accelWeight = accelWeight
        self.gyroWeight = gyroWeight
        self.madWinSec = madWinSec
        self.gateK = gateK
        self.refractoryMs = refractoryMs
        self.minWidthMs = minWidthMs
        self.maxWidthMs = maxWidthMs
        self.nccThresh = nccThresh
        self.windowPreMs = windowPreMs
        self.windowPostMs = windowPostMs
        self.ignoreStartMs = ignoreStartMs
        self.ignoreEndMs = ignoreEndMs
        self.gateRampMs = gateRampMs
        self.gyroVetoThresh = gyroVetoThresh
        self.gyroVetoHoldMs = gyroVetoHoldMs
        self.amplitudeSurplusThresh = amplitudeSurplusThresh
        self.preQuietMs = preQuietMs
        self.isiThresholdMs = isiThresholdMs
        self.useTemplateValidation = useTemplateValidation
        self.totalPinchesDetected = totalPinchesDetected
        self.candidatesRejectedByTemplate = candidatesRejectedByTemplate
        self.candidatesRejectedByGyroVeto = candidatesRejectedByGyroVeto
        self.candidatesRejectedByAmplitude = candidatesRejectedByAmplitude
        self.candidatesRejectedByISI = candidatesRejectedByISI
        self.totalCandidatesEvaluated = totalCandidatesEvaluated
        self.avgGateScore = avgGateScore
        self.avgNCC = avgNCC
        self.avgConfidence = avgConfidence
        self.sessionDurationSeconds = sessionDurationSeconds
    }

    /// Generate a summary string for display in debug UI
    public func summary() -> String {
        var lines: [String] = []

        lines.append("=== Watch Detector Metadata ===")
        lines.append("Config Source: \(configSource)")
        lines.append("Settings from Phone: \(settingsReceivedFromPhone ? "Yes" : "No")")
        lines.append("")

        lines.append("--- Detection Parameters ---")
        lines.append("Sample Rate: \(String(format: "%.0f", fs)) Hz")
        lines.append("Bandpass: \(String(format: "%.1f", bandpassLow))-\(String(format: "%.1f", bandpassHigh)) Hz")
        lines.append("Weights: accel=\(String(format: "%.1f", accelWeight)), gyro=\(String(format: "%.1f", gyroWeight))")
        lines.append("Gate K: \(String(format: "%.2f", gateK))σ")
        lines.append("NCC Threshold: \(String(format: "%.2f", nccThresh))")
        lines.append("Refractory: \(String(format: "%.0f", refractoryMs))ms")
        lines.append("Width: \(String(format: "%.0f", minWidthMs))-\(String(format: "%.0f", maxWidthMs))ms")
        lines.append("Gyro Veto: \(String(format: "%.2f", gyroVetoThresh)) rad/s, \(String(format: "%.0f", gyroVetoHoldMs))ms hold")
        lines.append("Amplitude Surplus: \(String(format: "%.1f", amplitudeSurplusThresh))σ")
        lines.append("ISI Threshold: \(String(format: "%.0f", isiThresholdMs))ms")
        lines.append("Template Validation: \(useTemplateValidation ? "Yes" : "No")")
        lines.append("")

        lines.append("--- Detection Statistics ---")
        lines.append("Session Duration: \(String(format: "%.1f", sessionDurationSeconds))s")
        lines.append("Total Pinches: \(totalPinchesDetected)")
        lines.append("Candidates Evaluated: \(totalCandidatesEvaluated)")
        lines.append("Rejected by Template: \(candidatesRejectedByTemplate)")
        lines.append("Rejected by Gyro Veto: \(candidatesRejectedByGyroVeto)")
        lines.append("Rejected by Amplitude: \(candidatesRejectedByAmplitude)")
        lines.append("Rejected by ISI: \(candidatesRejectedByISI)")
        lines.append("")

        lines.append("--- Signal Statistics ---")
        lines.append("Avg Gate Score: \(String(format: "%.3f", avgGateScore))")
        lines.append("Avg NCC: \(String(format: "%.3f", avgNCC))")
        lines.append("Avg Confidence: \(String(format: "%.3f", avgConfidence))")

        return lines.joined(separator: "\n")
    }
}
