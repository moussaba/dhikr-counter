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

    /// Factory method for Watch-optimized defaults
    public static func watchDefaults() -> PinchConfig {
        return PinchConfig(
            fs: 50.0,
            bandpassLow: 3.0,
            bandpassHigh: 20.0,
            accelWeight: 1.0,
            gyroWeight: 1.5,
            madWinSec: 3.0,
            gateK: 3.0,
            refractoryMs: 150,
            minWidthMs: 70,
            maxWidthMs: 350,
            nccThresh: 0.55,
            windowPreMs: 150,
            windowPostMs: 150,
            ignoreStartMs: 200,
            ignoreEndMs: 200,
            gateRampMs: 0,
            gyroVetoThresh: 3.0,
            gyroVetoHoldMs: 50,
            amplitudeSurplusThresh: 2.0,
            preQuietMs: 0,
            isiThresholdMs: 220
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
