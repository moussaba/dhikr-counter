import Foundation

/// Phase 1: Streaming DSP Core for real-time pinch detection
/// Implements single-sample processing with causal filtering only
public final class StreamingPinchDetector {
    private let config: PinchConfig
    private let templates: [PinchTemplate]

    // Streaming DSP components - reusing existing types from PinchDetector
    private var accelXFilter: CausalBandpassFilter
    private var accelYFilter: CausalBandpassFilter
    private var accelZFilter: CausalBandpassFilter
    private var gyroXFilter: CausalBandpassFilter
    private var gyroYFilter: CausalBandpassFilter
    private var gyroZFilter: CausalBandpassFilter

    private var tkeoAX: TKEOOperator
    private var tkeoAY: TKEOOperator
    private var tkeoAZ: TKEOOperator
    private var tkeoGX: TKEOOperator
    private var tkeoGY: TKEOOperator
    private var tkeoGZ: TKEOOperator

    private var baselineEstimator: StreamingBaselineMad

    // State tracking
    private var isInitialized: Bool = false

    public init(config: PinchConfig, templates: [PinchTemplate]) {
        self.config = config
        self.templates = templates

        // Initialize causal bandpass filters for each sensor axis
        self.accelXFilter = CausalBandpassFilter(fs: config.fs, low: config.bandpassLow, high: config.bandpassHigh)
        self.accelYFilter = CausalBandpassFilter(fs: config.fs, low: config.bandpassLow, high: config.bandpassHigh)
        self.accelZFilter = CausalBandpassFilter(fs: config.fs, low: config.bandpassLow, high: config.bandpassHigh)
        self.gyroXFilter = CausalBandpassFilter(fs: config.fs, low: config.bandpassLow, high: config.bandpassHigh)
        self.gyroYFilter = CausalBandpassFilter(fs: config.fs, low: config.bandpassLow, high: config.bandpassHigh)
        self.gyroZFilter = CausalBandpassFilter(fs: config.fs, low: config.bandpassLow, high: config.bandpassHigh)

        // Initialize TKEO operators (3-sample sliding buffers)
        self.tkeoAX = TKEOOperator()
        self.tkeoAY = TKEOOperator()
        self.tkeoAZ = TKEOOperator()
        self.tkeoGX = TKEOOperator()
        self.tkeoGY = TKEOOperator()
        self.tkeoGZ = TKEOOperator()

        // Initialize baseline estimator - reuse existing StreamingBaselineMAD from PinchDetector
        self.baselineEstimator = StreamingBaselineMad(winSec: config.madWinSec, fs: config.fs)
    }

    /// Process single sensor frame and return potential pinch event
    @discardableResult
    public func process(frame: SensorFrame) -> PinchEvent? {
        // Phase 1: Build streaming pipeline: filter → TKEO → L2 fusion → baseline/sigma

        // 1. Apply causal bandpass filtering to each axis
        let filteredAX = accelXFilter.process(frame.ax)
        let filteredAY = accelYFilter.process(frame.ay)
        let filteredAZ = accelZFilter.process(frame.az)
        let filteredGX = gyroXFilter.process(frame.gx)
        let filteredGY = gyroYFilter.process(frame.gy)
        let filteredGZ = gyroZFilter.process(frame.gz)

        // 2. Apply TKEO to filtered signals
        let tkeoAXVal = tkeoAX.process(filteredAX)
        let tkeoAYVal = tkeoAY.process(filteredAY)
        let tkeoAZVal = tkeoAZ.process(filteredAZ)
        let tkeoGXVal = tkeoGX.process(filteredGX)
        let tkeoGYVal = tkeoGY.process(filteredGY)
        let tkeoGZVal = tkeoGZ.process(filteredGZ)

        // 3. L2 fusion of TKEO outputs
        let accelTKEO = sqrt(tkeoAXVal*tkeoAXVal + tkeoAYVal*tkeoAYVal + tkeoAZVal*tkeoAZVal)
        let gyroTKEO = sqrt(tkeoGXVal*tkeoGXVal + tkeoGYVal*tkeoGYVal + tkeoGZVal*tkeoGZVal)
        let fusedSignal = config.accelWeight * accelTKEO + config.gyroWeight * gyroTKEO

        // 4. Update baseline and sigma estimation
        let (baseline, sigma) = baselineEstimator.update(fusedSignal)

        // Phase 1 scope: Only validate fused signal output
        // Return nil for now - peak detection and template matching in later phases
        return nil
    }

    /// Reset all internal state
    public func reset() {
        accelXFilter.reset()
        accelYFilter.reset()
        accelZFilter.reset()
        gyroXFilter.reset()
        gyroYFilter.reset()
        gyroZFilter.reset()

        tkeoAX.reset()
        tkeoAY.reset()
        tkeoAZ.reset()
        tkeoGX.reset()
        tkeoGY.reset()
        tkeoGZ.reset()

        baselineEstimator = StreamingBaselineMad(winSec: config.madWinSec, fs: config.fs)
        isInitialized = false
    }

    /// Get current fused signal value and baseline/sigma for debugging/validation
    public func processSampleForDebug(frame: SensorFrame) -> (fusedSignal: Float, baseline: Float, sigma: Float) {
        // Same processing as process() but return intermediate values for validation
        let filteredAX = accelXFilter.process(frame.ax)
        let filteredAY = accelYFilter.process(frame.ay)
        let filteredAZ = accelZFilter.process(frame.az)
        let filteredGX = gyroXFilter.process(frame.gx)
        let filteredGY = gyroYFilter.process(frame.gy)
        let filteredGZ = gyroZFilter.process(frame.gz)

        let tkeoAXVal = tkeoAX.process(filteredAX)
        let tkeoAYVal = tkeoAY.process(filteredAY)
        let tkeoAZVal = tkeoAZ.process(filteredAZ)
        let tkeoGXVal = tkeoGX.process(filteredGX)
        let tkeoGYVal = tkeoGY.process(filteredGY)
        let tkeoGZVal = tkeoGZ.process(filteredGZ)

        let accelTKEO = sqrt(tkeoAXVal*tkeoAXVal + tkeoAYVal*tkeoAYVal + tkeoAZVal*tkeoAZVal)
        let gyroTKEO = sqrt(tkeoGXVal*tkeoGXVal + tkeoGYVal*tkeoGYVal + tkeoGZVal*tkeoGZVal)
        let fusedSignal = config.accelWeight * accelTKEO + config.gyroWeight * gyroTKEO

        let (baseline, sigma) = baselineEstimator.update(fusedSignal)

        return (fusedSignal, baseline, sigma)
    }
}

// MARK: - CausalBandpassFilter

/// Wraps existing Biquad filters from PinchDetector for streaming use
private final class CausalBandpassFilter {
    private var highpass: StreamingBiquad
    private var lowpass: StreamingBiquad

    init(fs: Float, low: Float, high: Float) {
        self.highpass = StreamingBiquad.makeHighpass(fc: low, Q: 0.707, fs: fs)
        self.lowpass = StreamingBiquad.makeLowpass(fc: high, Q: 0.707, fs: fs)
    }

    func process(_ x: Float) -> Float {
        let hpOut = highpass.process(x)
        let lpOut = lowpass.process(hpOut)
        return lpOut.isFinite ? lpOut : 0.0
    }

    func reset() {
        highpass.reset()
        lowpass.reset()
    }
}

// MARK: - TKEOOperator

/// Streaming TKEO operator with 3-sample sliding buffer
private final class TKEOOperator {
    private var x1: Float = 0  // x[i-1]
    private var x0: Float = 0  // x[i]
    private var sampleCount: Int = 0

    func process(_ x: Float) -> Float {
        defer {
            x1 = x0
            x0 = x
            sampleCount += 1
        }

        // Need at least 3 samples for TKEO
        guard sampleCount >= 2 else {
            // For first two samples, return squared value (boundary handling)
            return x * x
        }

        // TKEO: x[i]² - x[i-1] * x[i+1]
        // Since we're streaming, we compute: x0² - x1 * x (current)
        let tkeoValue = x0 * x0 - x1 * x

        // Clamp negatives to prevent false triggers (matches batch implementation)
        return tkeoValue > 0 ? tkeoValue : 0
    }

    func reset() {
        x1 = 0
        x0 = 0
        sampleCount = 0
    }
}

// MARK: - StreamingBiquad

/// Standalone biquad implementation for streaming use
private final class StreamingBiquad {
    private var b0: Float, b1: Float, b2: Float
    private var a1: Float, a2: Float
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    init(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    func process(_ x: Float) -> Float {
        let y = b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }

    func reset() {
        x1 = 0
        x2 = 0
        y1 = 0
        y2 = 0
    }

    static func makeLowpass(fc: Float, Q: Float, fs: Float) -> StreamingBiquad {
        let f = min(max(fc, 0.001), 0.49*fs)
        let w0 = 2 * Float.pi * (f / fs)
        let alpha = sin(w0) / (2 * Q)
        let cosw0 = cos(w0)

        let b0 = (1 - cosw0) / 2
        let b1 = 1 - cosw0
        let b2 = (1 - cosw0) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosw0
        let a2 = 1 - alpha

        return StreamingBiquad(b0: b0/a0, b1: b1/a0, b2: b2/a0, a1: a1/a0, a2: a2/a0)
    }

    static func makeHighpass(fc: Float, Q: Float, fs: Float) -> StreamingBiquad {
        let f = min(max(fc, 0.001), 0.49*fs)
        let w0 = 2 * Float.pi * (f / fs)
        let alpha = sin(w0) / (2 * Q)
        let cosw0 = cos(w0)

        let b0 = (1 + cosw0) / 2
        let b1 = -(1 + cosw0)
        let b2 = (1 + cosw0) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosw0
        let a2 = 1 - alpha

        return StreamingBiquad(b0: b0/a0, b1: b1/a0, b2: b2/a0, a1: a1/a0, a2: a2/a0)
    }
}

// MARK: - StreamingBaselineMad

/// Copy of O(1) streaming robust baseline and scale estimator from PinchDetector
private final class StreamingBaselineMad {
    private var baseline: Float = 0.0
    private var scale: Float = 0.01
    private let alpha: Float
    private let beta: Float
    private let huberC: Float = 2.5
    private let winsorC: Float = 3.5
    private let scaleMin: Float = 1e-6
    private let absDevToSigma: Float = 1.2533141  // √(π/2) for mean absolute deviation → σ
    private var initialized: Bool = false

    init(winSec: Float, fs: Float) {
        // Match effective window: α ≈ 2/(N_eff + 1) where N_eff ≈ winSec * fs
        let nEff = winSec * fs
        self.alpha = 2.0 / (nEff + 1.0)
        self.beta = 2.0 / (nEff + 1.0)
    }

    func update(_ x: Float) -> (baseline: Float, sigma: Float) {
        if !initialized {
            baseline = x
            scale = max(abs(x) * 0.1, scaleMin)
            initialized = true
            return (baseline, scale * absDevToSigma)
        }

        // Robust baseline update with Huber influence function
        let residual = x - baseline
        let scaleSafe = max(scale, scaleMin)
        let u = residual / scaleSafe
        let uClamped = min(max(u, -huberC), huberC)  // Huber clipping
        baseline += alpha * scaleSafe * uClamped

        // Windsorized scale update (EW "MAD-like")
        let absResidual = abs(residual)
        let absWindsorized = min(absResidual, winsorC * scaleSafe)
        scale = (1.0 - beta) * scale + beta * absWindsorized

        return (baseline, scale * absDevToSigma)
    }
}