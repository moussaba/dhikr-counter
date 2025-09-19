import Foundation

/// Phase 1: Streaming DSP Core for real-time pinch detection
/// Implements single-sample processing with causal filtering only
public final class StreamingPinchDetector {
    private let config: PinchConfig
    private let templates: [PinchTemplate]
    private let useTemplateValidation: Bool

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
    private var peakDetector: StreamingPeakDetector
    private var templateMatcher: StreamingTemplateMatcher

    // State tracking
    private var isInitialized: Bool = false

    public init(config: PinchConfig, templates: [PinchTemplate], useTemplateValidation: Bool = true) {
        self.config = config
        self.templates = templates
        self.useTemplateValidation = useTemplateValidation

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

        // Initialize peak detector for Phase 2
        self.peakDetector = StreamingPeakDetector(
            refractoryMs: config.refractoryMs,
            gateK: config.gateK,
            fs: config.fs
        )

        // Initialize template matcher for Phase 3
        self.templateMatcher = StreamingTemplateMatcher(
            templates: templates,
            config: config
        )
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

        // Phase 3: Update template matcher with current signal for windowing
        templateMatcher.addSample(fusedSignal, timestamp: frame.t)

        // Phase 2: Peak detection with streaming state machine
        let gateThreshold = baseline + config.gateK * max(sigma, 1e-3)
        if let peakCandidate = peakDetector.process(signal: fusedSignal, gate: gateThreshold, timestamp: frame.t) {
            if useTemplateValidation {
                // Phase 3: Template matching for detected peak
                if let templateMatch = templateMatcher.matchTemplate(around: peakCandidate.timestamp) {
                    return PinchEvent(
                        tPeak: peakCandidate.timestamp,
                        tStart: templateMatch.windowStart,
                        tEnd: templateMatch.windowEnd,
                        confidence: templateMatch.confidence,
                        gateScore: peakCandidate.value,
                        ncc: templateMatch.nccScore
                    )
                } else {
                    // Peak detected but no good template match - reject
                    return nil
                }
            } else {
                // Phase 2 mode: Return peak without template validation
                return PinchEvent(
                    tPeak: peakCandidate.timestamp,
                    tStart: peakCandidate.timestamp - 0.1, // Simple window
                    tEnd: peakCandidate.timestamp + 0.1,
                    confidence: 1.0, // High confidence for peak-only mode
                    gateScore: peakCandidate.value,
                    ncc: 0.0 // No NCC in peak-only mode
                )
            }
        }

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
        peakDetector.reset()
        templateMatcher.reset()
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

// MARK: - StreamingPeakDetector

/// Phase 2: Peak detection state machine for real-time operation
/// Converts batch peak detection algorithm to streaming with proper state transitions
private final class StreamingPeakDetector {

    // Peak detection states
    private enum PeakState {
        case belowGate      // Signal is below gate threshold
        case rising         // Signal crossed above gate, currently rising
        case falling        // Signal reached peak and is now falling
    }

    // Peak candidate for when peak is confirmed
    struct PeakCandidate {
        let timestamp: Double
        let value: Float
    }

    // Configuration
    private let refractoryMs: Float
    private let gateK: Float
    private let fs: Float

    // State variables
    private var state: PeakState = .belowGate
    private var previousSignal: Float = 0
    private var previousGate: Float = 0
    private var peakValue: Float = 0
    private var peakTimestamp: Double = 0
    private var lastPeakTime: Double = 0
    private var risingStartTime: Double = 0

    init(refractoryMs: Float, gateK: Float, fs: Float) {
        self.refractoryMs = refractoryMs
        self.gateK = gateK
        self.fs = fs
    }

    /// Process single sample and return peak candidate if detected
    func process(signal: Float, gate: Float, timestamp: Double) -> PeakCandidate? {
        defer {
            previousSignal = signal
            previousGate = gate
        }

        let refractoryTimeSec = Double(refractoryMs) / 1000.0

        switch state {
        case .belowGate:
            // Check for signal crossing above gate threshold
            // Batch algorithm: z[i-1] <= gate[i-1] && z[i] > gate[i]
            if previousSignal <= previousGate && signal > gate {
                // Signal crossed above gate - start rising phase
                state = .rising
                peakValue = signal
                peakTimestamp = timestamp
                risingStartTime = timestamp
            }

        case .rising:
            // Signal is above gate, track peak while rising
            if signal >= previousSignal {
                // Still rising - update peak
                peakValue = signal
                peakTimestamp = timestamp
            } else {
                // Signal started falling - transition to falling state
                state = .falling
            }

        case .falling:
            // Signal has peaked and is falling
            // Check if we should confirm this as a valid peak

            // Must still be above gate at peak location (batch: z[j] > gate[j])
            // and respect refractory period
            if peakValue > gate && (timestamp - lastPeakTime) >= refractoryTimeSec {
                // Valid peak detected!
                lastPeakTime = timestamp
                state = .belowGate  // Reset state for next peak

                return PeakCandidate(timestamp: peakTimestamp, value: peakValue)
            } else {
                // Invalid peak (below gate or in refractory period)
                state = .belowGate
            }

            // If signal goes back above gate while falling, restart rising phase
            if signal > gate && signal > previousSignal {
                state = .rising
                peakValue = signal
                peakTimestamp = timestamp
                risingStartTime = timestamp
            }
        }

        return nil
    }

    func reset() {
        state = .belowGate
        previousSignal = 0
        previousGate = 0
        peakValue = 0
        peakTimestamp = 0
        lastPeakTime = 0
        risingStartTime = 0
    }
}

// MARK: - StreamingTemplateMatcher

/// Phase 3: Template matching for streaming peak detection
/// Maintains signal history buffer and performs NCC matching against templates
private final class StreamingTemplateMatcher {

    // Template match result
    struct TemplateMatch {
        let templateId: Int
        let nccScore: Float
        let confidence: Float
        let windowStart: Double
        let windowEnd: Double
    }

    // Configuration
    private let templates: [PinchTemplate]
    private let config: PinchConfig
    private let nccThreshold: Float

    // Signal history buffer for window extraction
    private var signalBuffer: CircularBuffer<Float>
    private var timestampBuffer: CircularBuffer<Double>
    private let bufferSize: Int

    init(templates: [PinchTemplate], config: PinchConfig) {
        self.templates = templates
        self.config = config
        self.nccThreshold = config.nccThresh

        // Calculate buffer size needed for template matching
        // Need enough history to extract windows around peaks
        let templateLength = templates.first?.vectorLength ?? 16
        let maxWindowMs = Float(150 + 250) // preMs + postMs from batch implementation
        let bufferDurationMs = maxWindowMs * 2.0 // Extra safety margin
        self.bufferSize = Int(bufferDurationMs * config.fs / 1000.0)

        self.signalBuffer = CircularBuffer<Float>(capacity: bufferSize)
        self.timestampBuffer = CircularBuffer<Double>(capacity: bufferSize)
    }

    /// Add new signal sample to history buffer
    func addSample(_ signal: Float, timestamp: Double) {
        signalBuffer.append(signal)
        timestampBuffer.append(timestamp)
    }

    /// Extract template window and find best matching template
    func matchTemplate(around peakTimestamp: Double) -> TemplateMatch? {
        guard !templates.isEmpty,
              let templateLength = templates.first?.vectorLength,
              signalBuffer.count >= templateLength else {
            return nil
        }

        // Find the index closest to peak timestamp in our buffer
        let timestamps = timestampBuffer.toArray()
        let signals = signalBuffer.toArray()

        guard let peakIndex = findClosestIndex(to: peakTimestamp, in: timestamps) else {
            return nil
        }

        // Extract window around peak (similar to batch extractWindow)
        let preMs: Float = 150.0  // From batch implementation
        let postMs: Float = 250.0 // From batch implementation
        let preS = Int(preMs * config.fs / 1000.0)
        let postS = Int(postMs * config.fs / 1000.0)

        let window = extractStreamingWindow(
            center: peakIndex,
            from: signals,
            preS: preS,
            postS: postS,
            targetLength: templateLength
        )

        guard window.count == templateLength else {
            return nil
        }

        // Find best matching template using NCC
        var bestNCC: Float = 0
        var bestTemplateId: Int = 0

        for (templateId, template) in templates.enumerated() {
            let nccScore = computeNCC(window: window, template: template.data)
            if nccScore > bestNCC {
                bestNCC = nccScore
                bestTemplateId = templateId
            }
        }

        // Check if best match exceeds threshold
        guard bestNCC >= nccThreshold else {
            return nil
        }

        // Calculate window timing
        let windowStartIndex = max(0, peakIndex - preS)
        let windowEndIndex = min(timestamps.count - 1, peakIndex + postS)
        let windowStart = timestamps[windowStartIndex]
        let windowEnd = timestamps[windowEndIndex]

        return TemplateMatch(
            templateId: bestTemplateId,
            nccScore: bestNCC,
            confidence: bestNCC, // Use NCC as confidence for now
            windowStart: windowStart,
            windowEnd: windowEnd
        )
    }

    /// Reset all internal state
    func reset() {
        signalBuffer.removeAll()
        timestampBuffer.removeAll()
    }

    // MARK: - Helper Methods

    private func findClosestIndex(to timestamp: Double, in timestamps: [Double]) -> Int? {
        guard !timestamps.isEmpty else { return nil }

        var closestIndex = 0
        var minDiff = abs(timestamps[0] - timestamp)

        for (index, ts) in timestamps.enumerated() {
            let diff = abs(ts - timestamp)
            if diff < minDiff {
                minDiff = diff
                closestIndex = index
            }
        }

        return closestIndex
    }

    private func extractStreamingWindow(center: Int, from signals: [Float], preS: Int, postS: Int, targetLength: Int) -> [Float] {
        let startIndex = max(0, center - preS)
        let endIndex = min(signals.count - 1, center + postS)

        var window = Array(signals[startIndex...endIndex])

        // Pad if necessary (edge handling like batch implementation)
        if window.count < targetLength {
            let shortfall = targetLength - window.count
            if startIndex == 0 {
                // Pad at beginning
                let padding = Array(repeating: signals.first ?? 0, count: shortfall)
                window = padding + window
            } else if endIndex == signals.count - 1 {
                // Pad at end
                let padding = Array(repeating: signals.last ?? 0, count: shortfall)
                window = window + padding
            }
        }

        // Trim to exact length
        return Array(window.prefix(targetLength))
    }

    private func computeNCC(window: [Float], template: [Float]) -> Float {
        guard window.count == template.count else { return 0.0 }

        let windowMean = window.reduce(0, +) / Float(window.count)
        let templateMean = template.reduce(0, +) / Float(template.count)

        let windowCentered = window.map { $0 - windowMean }
        let templateCentered = template.map { $0 - templateMean }

        var numerator: Float = 0
        for i in 0..<windowCentered.count {
            numerator += windowCentered[i] * templateCentered[i]
        }

        let windowSumSq = windowCentered.map { $0 * $0 }.reduce(0, +)
        let templateSumSq = templateCentered.map { $0 * $0 }.reduce(0, +)

        let denominator = sqrt(windowSumSq * templateSumSq)
        guard denominator > 1e-6 else { return 0.0 }

        return numerator / denominator
    }
}

// MARK: - CircularBuffer

/// Efficient circular buffer for signal history
private struct CircularBuffer<T> {
    private var buffer: [T?]
    private var head: Int = 0
    private var tail: Int = 0
    private var _count: Int = 0
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    var count: Int { _count }
    var isEmpty: Bool { _count == 0 }

    mutating func append(_ element: T) {
        buffer[tail] = element
        tail = (tail + 1) % capacity

        if _count < capacity {
            _count += 1
        } else {
            head = (head + 1) % capacity
        }
    }

    mutating func removeAll() {
        head = 0
        tail = 0
        _count = 0
        buffer = Array(repeating: nil, count: capacity)
    }

    func toArray() -> [T] {
        guard _count > 0 else { return [] }

        var result: [T] = []
        result.reserveCapacity(_count)

        for i in 0..<_count {
            let index = (head + i) % capacity
            if let element = buffer[index] {
                result.append(element)
            }
        }

        return result
    }
}