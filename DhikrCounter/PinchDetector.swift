import Foundation

// MARK: - PinchConfig iOS Extensions

extension PinchConfig {
    // Static factory method for creating from UserDefaults with template-aware timing
    public static func fromUserDefaults(templates: [PinchTemplate] = []) -> PinchConfig {
        let userDefaults = UserDefaults.standard

        // Calculate window timing from templates if available
        var windowPreMs: Float = 150
        var windowPostMs: Float = 150

        if let firstTemplate = templates.first {
            windowPreMs = firstTemplate.preMs
            windowPostMs = firstTemplate.postMs
        }

        return PinchConfig(
            fs: userDefaults.object(forKey: "tkeo_sampleRate") != nil ? Float(userDefaults.double(forKey: "tkeo_sampleRate")) : 50.0,
            bandpassLow: userDefaults.object(forKey: "tkeo_bandpassLow") != nil ? Float(userDefaults.double(forKey: "tkeo_bandpassLow")) : 3.0,
            bandpassHigh: userDefaults.object(forKey: "tkeo_bandpassHigh") != nil ? Float(userDefaults.double(forKey: "tkeo_bandpassHigh")) : 20.0,
            accelWeight: userDefaults.object(forKey: "tkeo_accelWeight") != nil ? Float(userDefaults.double(forKey: "tkeo_accelWeight")) : 1.0,
            gyroWeight: userDefaults.object(forKey: "tkeo_gyroWeight") != nil ? Float(userDefaults.double(forKey: "tkeo_gyroWeight")) : 1.5,
            madWinSec: userDefaults.object(forKey: "tkeo_madWinSec") != nil ? Float(userDefaults.double(forKey: "tkeo_madWinSec")) : 3.0,
            gateK: userDefaults.object(forKey: "tkeo_gateThreshold") != nil ? Float(userDefaults.double(forKey: "tkeo_gateThreshold")) : 3.0,
            refractoryMs: userDefaults.object(forKey: "tkeo_refractoryPeriod") != nil ? Float(userDefaults.double(forKey: "tkeo_refractoryPeriod")) * 1000 : 150,
            minWidthMs: userDefaults.object(forKey: "tkeo_minWidthMs") != nil ? Float(userDefaults.double(forKey: "tkeo_minWidthMs")) : 70,
            maxWidthMs: userDefaults.object(forKey: "tkeo_maxWidthMs") != nil ? Float(userDefaults.double(forKey: "tkeo_maxWidthMs")) : 350,
            nccThresh: userDefaults.object(forKey: "tkeo_templateConfidence") != nil ? Float(userDefaults.double(forKey: "tkeo_templateConfidence")) : 0.6,
            windowPreMs: userDefaults.object(forKey: "tkeo_windowPreMs") as? Float ?? windowPreMs,
            windowPostMs: userDefaults.object(forKey: "tkeo_windowPostMs") as? Float ?? windowPostMs,
            ignoreStartMs: userDefaults.object(forKey: "tkeo_ignoreStartMs") != nil ? Float(userDefaults.double(forKey: "tkeo_ignoreStartMs")) : 200,
            ignoreEndMs: userDefaults.object(forKey: "tkeo_ignoreEndMs") != nil ? Float(userDefaults.double(forKey: "tkeo_ignoreEndMs")) : 200,
            gateRampMs: userDefaults.object(forKey: "tkeo_gateRampMs") != nil ? Float(userDefaults.double(forKey: "tkeo_gateRampMs")) : 0,
            gyroVetoThresh: userDefaults.object(forKey: "tkeo_gyroVetoThresh") != nil ? Float(userDefaults.double(forKey: "tkeo_gyroVetoThresh")) : 3.0,
            gyroVetoHoldMs: userDefaults.object(forKey: "tkeo_gyroVetoHoldMs") != nil ? Float(userDefaults.double(forKey: "tkeo_gyroVetoHoldMs")) : 50,
            amplitudeSurplusThresh: userDefaults.object(forKey: "tkeo_amplitudeSurplusThresh") != nil ? Float(userDefaults.double(forKey: "tkeo_amplitudeSurplusThresh")) : 2.0,
            preQuietMs: userDefaults.object(forKey: "tkeo_preQuietMs") != nil ? Float(userDefaults.double(forKey: "tkeo_preQuietMs")) : 0,
            isiThresholdMs: userDefaults.object(forKey: "tkeo_isiThresholdMs") != nil ? Float(userDefaults.double(forKey: "tkeo_isiThresholdMs")) : 220
        )
    }
}

public final class PinchDetector {
    private let config: PinchConfig
    private let templates: [PinchTemplate]
    private var debugLogger: ((String) -> Void)?
    
    public init(config: PinchConfig, templates: [PinchTemplate]) {
        self.config = config
        self.templates = templates
    }
    
    // Convenience initializer for single template (backward compatibility)
    public convenience init(config: PinchConfig, template: PinchTemplate) {
        self.init(config: config, templates: [template])
    }
    
    public func setDebugLogger(_ logger: @escaping (String) -> Void) {
        self.debugLogger = logger
    }
    
    private func debugLog(_ message: String) {
        debugLogger?(message)
    }
    
    // MARK: - Static Factory Methods
    public static func createDefaultConfig(sampleRate: Float) -> PinchConfig {
        return PinchConfig(
            fs: sampleRate,
            bandpassLow: 3.0,
            bandpassHigh: 20.0,  // 3-20Hz for pinch detection
            accelWeight: 1.0,
            gyroWeight: 1.5,
            madWinSec: 3.0,
            gateK: 3.0,
            refractoryMs: 150,
            minWidthMs: 70,
            maxWidthMs: 350,
            nccThresh: 0.55,
            windowPreMs: 150,
            windowPostMs: 150,  // Match trained template symmetry
            ignoreStartMs: 200,  // Much shorter - just true startup
            ignoreEndMs: 200,   // Much shorter - just true teardown
            gateRampMs: 0,      // Disable ramp-up  
            gyroVetoThresh: 3.0, // Much higher threshold
            gyroVetoHoldMs: 50,  // Much shorter hold
            amplitudeSurplusThresh: 2.0, // Default amplitude surplus guard
            preQuietMs: 0       // Disable pre-silence
        )
    }
    
    public static func createDefaultTemplate(fs: Float = 50.0, preMs: Float = 150, postMs: Float = 150) -> PinchTemplate {
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
            channelsMeta: "fused_signal",
            version: "1.0"
        )
    }
    
    public static func loadTrainedTemplates() -> [PinchTemplate] {
        guard let path = Bundle.main.path(forResource: "trained_templates", ofType: "json"),
              let data = NSData(contentsOfFile: path),
              let json = try? JSONSerialization.jsonObject(with: data as Data, options: []) as? [String: Any],
              let templatesArray = json["templates"] as? [[Double]] else {
            print("⚠️ Failed to load trained_templates.json, using synthetic template")
            return [createDefaultTemplate()]
        }
        
        // Calculate correct pre/post timing from actual template length
        let templateLength = templatesArray.first?.count ?? 16
        let fs: Float = 50.0
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
                version: "1.0"
            )
        }
    }
    
    public static func convertSensorReadings(_ readings: [SensorReading]) -> [SensorFrame] {
        return readings.map { reading in
            SensorFrame(
                t: reading.motionTimestamp,
                ax: Float(reading.userAcceleration[0]),
                ay: Float(reading.userAcceleration[1]),
                az: Float(reading.userAcceleration[2]),
                gx: Float(reading.rotationRate[0]),
                gy: Float(reading.rotationRate[1]),
                gz: Float(reading.rotationRate[2])
            )
        }
    }
    
    @discardableResult
    func process(frames: [SensorFrame]) -> [PinchEvent] {
        return _process(frames: frames, emit: nil)
    }
    
    // Per-axis preprocessing (Python-style)
    private func preprocessAxes(frames: [SensorFrame]) -> (ax: [Float], ay: [Float], az: [Float], 
                                                           gx: [Float], gy: [Float], gz: [Float], 
                                                           fs: Float, t: [TimeInterval]) {
        var ax = [Float](), ay = [Float](), az = [Float]()
        var gx = [Float](), gy = [Float](), gz = [Float]()
        var t = [TimeInterval]()
        
        ax.reserveCapacity(frames.count); ay.reserveCapacity(frames.count); az.reserveCapacity(frames.count)
        gx.reserveCapacity(frames.count); gy.reserveCapacity(frames.count); gz.reserveCapacity(frames.count)
        t.reserveCapacity(frames.count)
        
        let startTime = frames.first?.t ?? 0.0  // Normalize to session start
        for frame in frames {
            ax.append(frame.ax); ay.append(frame.ay); az.append(frame.az)
            gx.append(frame.gx); gy.append(frame.gy); gz.append(frame.gz)
            t.append(frame.t - startTime)  // Relative to session start
        }
        
        return (ax, ay, az, gx, gy, gz, config.fs, t)
    }
    
    // L2 fusion of positive TKEO values (Python-style)
    private func fuseL2Positive(_ axes: [[Float]]) -> [Float] {
        guard !axes.isEmpty else { return [] }
        let n = axes[0].count
        var out = [Float](repeating: 0, count: n)
        
        for i in 0..<n {
            var s: Float = 0
            for k in 0..<axes.count {
                let v = axes[k][i]
                let vp = v > 0 ? v : 0
                s += vp * vp
            }
            out[i] = sqrt(s)
        }
        return out
    }
    
    // Legacy magnitude preprocessing (kept for compatibility)
    private func preprocess(frames: [SensorFrame]) -> (accelMag: [Float], gyroMag: [Float], fs: Float, t: [TimeInterval]) {
        var accelMag = [Float]()
        var gyroMag = [Float]()
        var t = [TimeInterval]()
        
        let startTime = frames.first?.t ?? 0.0  // Normalize to session start
        for frame in frames {
            let aMag = sqrt(frame.ax * frame.ax + frame.ay * frame.ay + frame.az * frame.az)
            let gMag = sqrt(frame.gx * frame.gx + frame.gy * frame.gy + frame.gz * frame.gz)
            
            accelMag.append(aMag)
            gyroMag.append(gMag)
            t.append(frame.t - startTime)  // Relative to session start
        }
        
        return (accelMag, gyroMag, config.fs, t)
    }
    
    private func jerk(_ x: [Float], dt: Float) -> [Float] {
        guard x.count > 2 else { return Array(repeating: 0, count: x.count) }
        
        var result = [Float](repeating: 0, count: x.count)
        
        for i in 1..<x.count-1 {
            result[i] = (x[i+1] - x[i-1]) / (2.0 * dt)
        }
        
        result[0] = result[1]
        result[x.count-1] = result[x.count-2]
        
        return result
    }
    
    // MARK: - Stable RBJ Biquad Filters
    private struct Biquad {
        var b0: Float, b1: Float, b2: Float
        var a1: Float, a2: Float
        private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        
        init(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
            self.b0 = b0
            self.b1 = b1
            self.b2 = b2
            self.a1 = a1
            self.a2 = a2
        }
        
        mutating func process(_ x: Float) -> Float {
            let y = b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }
    
    private enum BiquadType { case lowpass, highpass }
    
    private func makeRBJBiquad(_ type: BiquadType, fc: Float, Q: Float, fs: Float) -> Biquad {
        // Clamp fc to (0, fs/2)
        let f = min(max(fc, 0.001), 0.49*fs)
        let w0 = 2 * Float.pi * (f / fs)
        let alpha = sin(w0) / (2 * Q)
        let cosw0 = cos(w0)
        
        var b0: Float = 0, b1: Float = 0, b2: Float = 0
        var a0: Float = 1, a1: Float = 0, a2: Float = 0
        
        switch type {
        case .lowpass:
            b0 = (1 - cosw0) / 2; b1 = 1 - cosw0; b2 = (1 - cosw0) / 2
            a0 = 1 + alpha; a1 = -2 * cosw0; a2 = 1 - alpha
        case .highpass:
            b0 = (1 + cosw0) / 2; b1 = -(1 + cosw0); b2 = (1 + cosw0) / 2
            a0 = 1 + alpha; a1 = -2 * cosw0; a2 = 1 - alpha
        }
        
        // Normalize by a0
        return Biquad(b0: b0/a0, b1: b1/a0, b2: b2/a0, a1: a1/a0, a2: a2/a0)
    }
    
    private struct BandPass {
        var hp: Biquad
        var lp: Biquad
        mutating func process(_ x: Float) -> Float { lp.process(hp.process(x)) }
    }
    
    private func makeBandPass(fs: Float, low: Float, high: Float) -> BandPass {
        let Q: Float = 0.707
        let hp = makeRBJBiquad(.highpass, fc: low, Q: Q, fs: fs)
        let lp = makeRBJBiquad(.lowpass, fc: high, Q: Q, fs: fs)
        return BandPass(hp: hp, lp: lp)
    }
    
    private func bandpass(_ x: [Float], fs: Float, low: Float, high: Float) -> [Float] {
        guard !x.isEmpty, low > 0, high > low, high < 0.49*fs else { return x }
        var bp = makeBandPass(fs: fs, low: low, high: high)
        var y = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count { y[i] = bp.process(x[i]) }
        sanitize(&y)
        return y
    }
    
    // --- NEW: zero-phase (forward-backward) bandpass ---
    private func bandpassZeroPhase(_ x: [Float], fs: Float, low: Float, high: Float) -> [Float] {
        guard !x.isEmpty, low > 0, high > low, high < 0.49*fs else { return x }
        var fwd = bandpass(x, fs: fs, low: low, high: high)
        fwd.reverse()
        var bwd = bandpass(fwd, fs: fs, low: low, high: high)
        bwd.reverse()
        var y = bwd; sanitize(&y)
        return y
    }
    
    private func sanitize(_ x: inout [Float]) {
        for i in x.indices { if !x[i].isFinite { x[i] = 0 } }
    }
    
    private func extractWindow(center idx: Int, from z: [Float], preS: Int, postS: Int, L: Int) -> (win: [Float], s: Int, e: Int) {
        let s0 = max(0, idx - preS)
        let e0 = min(z.count - 1, idx + postS)
        var w = Array(z[s0...e0])
        
        if w.count < L {
            if s0 == 0 { w = Array(repeating: z.first!, count: L - w.count) + w }
            if e0 == z.count - 1 { w += Array(repeating: z.last!, count: L - w.count) }
        }
        
        return (Array(w.prefix(L)), s0, min(e0, s0 + L - 1))
    }
    
    private func tkeo(_ x: [Float]) -> [Float] {
        guard x.count >= 3 else { return Array(repeating: 0, count: x.count) }
        
        var y = [Float](repeating: 0, count: x.count)
        
        // Python-style boundary handling: use squared values
        y[0] = x[0] * x[0]
        y[y.count - 1] = x[y.count - 1] * x[y.count - 1]
        
        // Compute TKEO for interior points with positive clamp (like Python)
        for i in 1..<(x.count - 1) {
            let v = x[i] * x[i] - x[i - 1] * x[i + 1]
            y[i] = v > 0 ? v : 0  // Clamp negatives to prevent false triggers
        }
        
        return y
    }
    
    /// O(1) streaming robust baseline and scale estimator
    /// Replaces O(n log n) sliding median/MAD with Huber-EMA + windsorized scale
    private class StreamingBaselineMAD {
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
    
    /// O(1) streaming baseline and sigma estimation - replaces O(n log n) sliding window
    private func streamingBaselineSigma(_ x: [Float], winSec: Float, fs: Float) -> ([Float], [Float]) {
        guard !x.isEmpty else { return ([], []) }
        
        let estimator = StreamingBaselineMAD(winSec: winSec, fs: fs)
        var baselines = [Float]()
        var sigmas = [Float]()

        baselines.reserveCapacity(x.count)
        sigmas.reserveCapacity(x.count)

        for sample in x {
            let (baseline, sigma) = estimator.update(sample)
            baselines.append(baseline)
            sigmas.append(sigma)
        }

        return (baselines, sigmas)
    }
    
    private func detectPeaks(z: [Float], gate: [Float], refractorySec: Float, fs: Float) -> [PeakCandidate] {
        let rN = max(1, Int(round(refractorySec * fs)))
        var peaks: [PeakCandidate] = []
        var i = 1
        
        while i < z.count - 1 {
            if z[i-1] <= gate[i-1] && z[i] > gate[i] {
                var j = i
                while j + 1 < z.count && z[j+1] >= z[j] { j += 1 }
                if z[j] > gate[j] {
                    peaks.append(PeakCandidate(index: j, value: z[j]))
                    i = j + rN
                    continue
                }
            }
            i += 1
        }
        
        return peaks
    }
    
    private func ncc(window: [Float], template: [Float]) -> Float {
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
        
        return denominator > 0 ? numerator / denominator : 0.0
    }
    
    /// Linear resampling with optional time-warp factor `scale`.
    /// Example: scale=0.9 compresses (faster gesture), 1.1 stretches (slower gesture).
    private func resampleLinear(_ x: [Float], scale: Float, targetCount L: Int) -> [Float] {
        guard !x.isEmpty, L > 0 else { return [Float](repeating: 0, count: max(L, 0)) }

        // Virtual source length after warp
        let virtualCount = max(2, Int(round(Float(x.count) * scale)))

        // Map target index -> source position (0 ..< virtualCount-1), then back into x's index space.
        var y = [Float](repeating: 0, count: L)
        for i in 0..<L {
            let u = (Float(i) / Float(max(L - 1, 1))) * Float(virtualCount - 1)
            // Map u into original x domain (scale back)
            let s = u / max(scale, 1e-6)
            let sClamped = min(max(s, 0), Float(x.count - 1))

            let i0 = Int(floor(sClamped))
            let i1 = min(i0 + 1, x.count - 1)
            let w  = sClamped - Float(i0)
            y[i] = (1 - w) * x[i0] + w * x[i1]
        }
        return y
    }

    /// Shift an array by `k` samples (positive = delay). Pads with edge samples.
    private func shiftArray(_ x: [Float], by k: Int) -> [Float] {
        guard !x.isEmpty, k != 0 else { return x }
        let n = x.count
        if k > 0 {
            let head = [Float](repeating: x.first!, count: k)
            return Array(head + x).prefix(n).map { $0 }
        } else {
            let tail = [Float](repeating: x.last!, count: -k)
            return Array(x + tail).suffix(n).map { $0 }
        }
    }
    
    // --- NEW ---
    private func mergeNear(_ evs: [PinchEvent], minGapMs: Float) -> [PinchEvent] {
        guard evs.count > 1 else { return evs }
        let gap = Double(minGapMs / 1000)
        var out: [PinchEvent] = []
        var cur = evs.sorted { $0.tPeak < $1.tPeak }[0]
        for e in evs.dropFirst() {
            let timeDiff = e.tPeak - cur.tPeak
            if timeDiff <= gap {
                // Preserve very strong NCC pairs - don't merge if both are high quality
                if max(cur.ncc, e.ncc) >= 0.90 {
                    out.append(cur); cur = e  // Keep both
                } else {
                    // Normal merge - keep the higher confidence one
                    if e.confidence > cur.confidence { cur = e }
                }
            } else {
                out.append(cur); cur = e
            }
        }
        out.append(cur); return out
    }
    
    // MARK: - Shared core
    private func _process(frames: [SensorFrame],
                          emit: ((String) -> Void)?) -> [PinchEvent] {
        func log(_ s: String) { emit?(s) }

        guard !frames.isEmpty else {
            log("❌ Empty frames array")
            return []
        }

        let t0 = CFAbsoluteTimeGetCurrent()

        // -------- Prep / stats (unchanged) --------
        let (ax, ay, az, gx, gy, gz, fs, t) = preprocessAxes(frames: frames)
        log("📊 Raw signal stats - samples: \(ax.count), duration: \(String(format: "%.1f", Float(ax.count)/fs))s")

        // Filters - Use zero-phase bandpass (NEW: eliminates phase lag)
        log("🔄 Applying zero-phase bandpass filter: \(String(format: "%.1f", config.bandpassLow))-\(String(format: "%.1f", config.bandpassHigh))Hz")
        var aX = bandpassZeroPhase(ax, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        var aY = bandpassZeroPhase(ay, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        var aZ = bandpassZeroPhase(az, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        var gX = bandpassZeroPhase(gx, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        var gY = bandpassZeroPhase(gy, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        var gZ = bandpassZeroPhase(gz, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        sanitize(&aX); sanitize(&aY); sanitize(&aZ)
        sanitize(&gX); sanitize(&gY); sanitize(&gZ)
        log("✅ Zero-phase filtering complete - no causal delay introduced")

        // TKEO computation
        var aXT = tkeo(aX), aYT = tkeo(aY), aZT = tkeo(aZ)
        var gXT = tkeo(gX), gYT = tkeo(gY), gZT = tkeo(gZ)
        sanitize(&aXT); sanitize(&aYT); sanitize(&aZT)
        sanitize(&gXT); sanitize(&gYT); sanitize(&gZT)
        log("⚡ TKEO computed: accel ranges X[\(String(format: "%.2f", aXT.min() ?? 0))-\(String(format: "%.2f", aXT.max() ?? 0))], Y[\(String(format: "%.2f", aYT.min() ?? 0))-\(String(format: "%.2f", aYT.max() ?? 0))], Z[\(String(format: "%.2f", aZT.min() ?? 0))-\(String(format: "%.2f", aZT.max() ?? 0))]")

        // L2 fusion of TKEO energies
        var accelTkeo = fuseL2Positive([aXT, aYT, aZT])
        var gyroTkeo  = fuseL2Positive([gXT, gYT, gZT])
        sanitize(&accelTkeo); sanitize(&gyroTkeo)
        log("🔗 TKEO fusion: accel_L2 range [\(String(format: "%.2f", accelTkeo.min() ?? 0))-\(String(format: "%.2f", accelTkeo.max() ?? 0))], gyro_L2 range [\(String(format: "%.2f", gyroTkeo.min() ?? 0))-\(String(format: "%.2f", gyroTkeo.max() ?? 0))]")

        // Robust z-normalization using streaming O(1) baseline/sigma (replaces O(n log n) sliding window)
        let baselineStartTime = CFAbsoluteTimeGetCurrent()
        let (aMed, aSigma) = streamingBaselineSigma(accelTkeo, winSec: config.madWinSec, fs: fs)
        let (gMed, gSigma) = streamingBaselineSigma(gyroTkeo,  winSec: config.madWinSec, fs: fs)
        let baselineTime = (CFAbsoluteTimeGetCurrent() - baselineStartTime) * 1000
        log("📈 O(1) Streaming baseline: \(String(format: "%.2f", baselineTime))ms for \(accelTkeo.count + gyroTkeo.count) samples (was O(n²) with \(accelTkeo.count * 2 * Int(round(config.madWinSec * fs)))) sort operations)")
        var accelZ = zip(accelTkeo, zip(aMed, aSigma)).map { (v, mm) in let (m, s) = mm; return s > 0 ? (v - m)/s : 0 }
        var gyroZ = zip(gyroTkeo,  zip(gMed, gSigma)).map { (v, mm) in let (m, s) = mm; return s > 0 ? (v - m)/s : 0 }
        sanitize(&accelZ); sanitize(&gyroZ)
        log("📊 Z-score ranges: accel [\(String(format: "%.2f", accelZ.min() ?? 0))-\(String(format: "%.2f", accelZ.max() ?? 0))], gyro [\(String(format: "%.2f", gyroZ.min() ?? 0))-\(String(format: "%.2f", gyroZ.max() ?? 0))]")

        // Weighted fusion + light EMA smoothing
        var fused = zip(accelZ, gyroZ).map { config.accelWeight*$0 + config.gyroWeight*$1 }
        if fused.count > 1 {
            let alpha: Float = 0.2
            for i in 1..<fused.count { fused[i] = alpha*fused[i-1] + (1 - alpha)*fused[i] }
        }
        sanitize(&fused)
        log("⚖️ Fused signal: range [\(String(format: "%.2f", fused.min() ?? 0))-\(String(format: "%.2f", fused.max() ?? 0))], weights: accel=\(config.accelWeight), gyro=\(config.gyroWeight)")

        // Adaptive gating threshold = baseline + K·σ
        let (fMed, fSigma) = streamingBaselineSigma(fused, winSec: config.madWinSec, fs: fs)
        var gate = zip(fMed, fSigma).map { (m, s) in m + config.gateK * max(s, 1e-3) }
        log("🚪 Gate threshold: K=\(config.gateK)σ, range [\(String(format: "%.2f", gate.min() ?? 0))-\(String(format: "%.2f", gate.max() ?? 0))], baseline [\(String(format: "%.2f", fMed.min() ?? 0))-\(String(format: "%.2f", fMed.max() ?? 0))]")

        // --- Bookend / motion veto (unchanged logic) ---
        let ignoreStartS = Int(round(config.ignoreStartMs * fs / 1000))
        let ignoreEndS   = Int(round(config.ignoreEndMs   * fs / 1000))
        var allow = [Bool](repeating: true, count: fused.count)
        for i in 0..<min(ignoreStartS, allow.count) { allow[i] = false }
        for i in max(0, allow.count - ignoreEndS)..<allow.count { allow[i] = false }

        var gyroMag = [Float](repeating: 0, count: gX.count)
        for i in 0..<gX.count { gyroMag[i] = sqrt(gX[i]*gX[i] + gY[i]*gY[i] + gZ[i]*gZ[i]) }
        let holdS = max(1, Int(round(config.gyroVetoHoldMs * fs / 1000)))
        var below = [Bool](repeating: false, count: gyroMag.count)
        for i in 0..<gyroMag.count { below[i] = gyroMag[i] <= config.gyroVetoThresh }
        var motionOK = [Bool](repeating: false, count: gyroMag.count)
        var run = 0
        for i in 0..<below.count { run = below[i] ? (run + 1) : 0; motionOK[i] = run >= holdS }
        for i in 0..<allow.count { allow[i] = allow[i] && motionOK[i] }

        if config.gateRampMs > 0 {
            let rampS = Int(round(config.gateRampMs * fs / 1000))
            for i in 0..<min(rampS, gate.count) {
                let w = 1 - Float(i) / Float(max(1, rampS - 1))
                gate[i] += w * (3 * max(fSigma[i], 1e-3))
            }
        }

        var gateMasked = gate
        for i in 0..<gateMasked.count where !allow[i] { gateMasked[i] = Float.greatestFiniteMagnitude }

        // Peak detection
        let peaks = detectPeaks(z: fused, gate: gateMasked, refractorySec: config.refractoryMs/1000, fs: fs)
        log("🏔️ Peak detection: \(peaks.count) candidates found, refractory=\(String(format: "%.0f", config.refractoryMs))ms")

        // -------- Template expansion & matching (NEW SHARED PART) --------
        log("🔍 === TEMPLATE EXPANSION & MATCHING ===")

        // Window sizing
        let preS  = Int(round(config.windowPreMs  * fs / 1000))
        let postS = Int(round(config.windowPostMs * fs / 1000))
        let L     = preS + postS + 1
        guard L > 0 else { 
            log("❌ Invalid window length: L=\(L)")
            return [] 
        }
        log("📐 Window config: preS=\(preS), postS=\(postS), L=\(L) samples")

        // Use only templates that already match L; if your JSON is a different length,
        // time-warp will resample them into L anyway.
        let rawTemplates: [[Float]] = templates.map { $0.data }
        log("📋 Raw templates: \(rawTemplates.count) templates, lengths: \(rawTemplates.map { $0.count })")

        // Expand templates with small time warps (±10%) and resample back to L.
        // Tweak the grid if you want more/less coverage vs speed.
        let warpGrid: [Float] = [0.95, 1.00, 1.05]  // Tightened for better precision
        var expanded: [[Float]] = []
        expanded.reserveCapacity(rawTemplates.count * warpGrid.count)

        log("🔄 Expanding templates with time warps: \(warpGrid)")
        for (tplIdx, tpl) in rawTemplates.enumerated() {
            log("📝 Template[\(tplIdx)] original length: \(tpl.count) → resampling to L=\(L)")
            for (scaleIdx, s) in warpGrid.enumerated() {
                let warped = resampleLinear(tpl, scale: s, targetCount: L)
                expanded.append(warped)
                log("  ↳ Scale \(String(format: "%.2f", s)): length \(warped.count), range [\(String(format: "%.4f", warped.min() ?? 0)), \(String(format: "%.4f", warped.max() ?? 0))]")
                
                // Test shiftArray function on first template's first scale for verification
                if tplIdx == 0 && scaleIdx == 0 {
                    let testShifts = [-2, -1, 0, 1, 2]
                    var shiftSamples: [String] = []
                    for shift in testShifts {
                        let shifted = shiftArray(warped, by: shift)
                        let sample = shifted.count > 5 ? String(format: "%.3f", shifted[5]) : "N/A"
                        shiftSamples.append("sh\(shift)[\(5)]=\(sample)")
                    }
                    log("  🧪 ShiftArray test: \(shiftSamples.joined(separator: ", "))")
                }
            }
        }
        log("📈 Total expanded templates: \(expanded.count) (= \(rawTemplates.count) × \(warpGrid.count))")

        // Max ±1-sample shift search for tighter precision (reduced from ±2)
        let maxShift = 1
        log("↔️ Shift tolerance: ±\(maxShift) samples (±\(String(format: "%.0f", Float(maxShift) * 1000 / fs))ms at \(fs)Hz)")

        var events: [PinchEvent] = []
        let nccThresh: Float = max(config.nccThresh, 0.65)  // Raised for better precision
        log("🎯 NCC threshold: \(String(format: "%.3f", nccThresh))")
        log("🔍 Processing \(peaks.count) peak candidates...")
        log("💡 Precision-focused algorithm improvements:")
        log("   • Zero-phase filtering (eliminates \(String(format: "%.1f", 1000.0/(2*fs)))ms phase lag)")
        log("   • Multi-scale templates (\(warpGrid.count) tightened warps per template)")
        log("   • ±\(maxShift) sample shift tolerance (tightened from ±2)")
        log("   • Amplitude surplus guard (≥\(String(format: "%.1f", config.amplitudeSurplusThresh))σ over local baseline)")
        log("   • ISI guard (<\(String(format: "%.0f", config.isiThresholdMs))ms unless NCC≥0.90)")
        let mergeGapMs = max(config.isiThresholdMs, 180)  // consistent with ISI, min 180ms
        log("   • Near-duplicate merging (gap≥\(String(format: "%.0f", mergeGapMs))ms, preserve strong NCC≥0.90)")

        var candidateDetails: [String] = []
        for (pkIdx, pk) in peaks.enumerated() {
            // Optional pre-quiet requirement
            if config.preQuietMs > 0 {
                let need = max(1, Int(round(config.preQuietMs * fs / 1000)))
                let sQuiet = max(0, pk.index - need)
                let quiet = (sQuiet..<pk.index).allSatisfy { fused[$0] < gate[$0] * 0.9 }
                if !quiet { 
                    candidateDetails.append("Peak[\(pkIdx)] @ \(String(format: "%.3f", t[pk.index]))s: REJECTED pre-quiet")
                    continue 
                }
            }

            // Extract window
            let (win, sIdx, eIdx) = extractWindow(center: pk.index, from: fused, preS: preS, postS: postS, L: L)

            // Best NCC across (expanded templates × small shifts)
            var bestNCC: Float = 0
            var bestTemplateIdx: Int = -1
            var bestShift: Int = 0
            var totalComparisons = 0
            var earlyStop = false
            
            for (tplIdx, tpl) in expanded.enumerated() {
                // try shifts by shifting the template (pad with edges)
                for sh in -maxShift...maxShift {
                    let tplShifted = shiftArray(tpl, by: sh)
                    let score = ncc(window: win, template: tplShifted)
                    totalComparisons += 1
                    
                    if score > bestNCC { 
                        bestNCC = score
                        bestTemplateIdx = tplIdx
                        bestShift = sh
                    }
                    if bestNCC >= 0.95 { earlyStop = true; break } // early exit
                }
                if earlyStop { break }
            }

            let originalTplIdx = bestTemplateIdx >= 0 ? bestTemplateIdx / warpGrid.count : -1
            let scaleIdx = bestTemplateIdx >= 0 ? bestTemplateIdx % warpGrid.count : -1
            let scale = scaleIdx >= 0 ? warpGrid[scaleIdx] : 1.0
            
            if bestNCC >= nccThresh {
                // Amplitude surplus guard: require configurable σ over local sigma baseline
                let surplus = max(0, pk.value - gate[pk.index])
                let localSigma = max(1e-6, fSigma[pk.index])

                guard surplus >= config.amplitudeSurplusThresh * localSigma else {
                    candidateDetails.append("Peak[\(pkIdx)] @ \(String(format: "%.3f", t[pk.index]))s: ❌ REJECTED - insufficient amplitude surplus (\(String(format: "%.2f", surplus/localSigma))σ < \(String(format: "%.1f", config.amplitudeSurplusThresh))σ)")
                    continue
                }
                
                // Inter-spike interval guard: reject if too close to previous event (unless very high NCC)
                if let lastEvent = events.last {
                    let timeSinceLast = t[pk.index] - lastEvent.tPeak
                    if timeSinceLast < Double(config.isiThresholdMs / 1000.0) && bestNCC < 0.90 {
                        candidateDetails.append("Peak[\(pkIdx)] @ \(String(format: "%.3f", t[pk.index]))s: ❌ REJECTED - ISI too short (\(String(format: "%.0f", timeSinceLast*1000))ms < \(String(format: "%.0f", config.isiThresholdMs))ms, NCC=\(String(format: "%.3f", bestNCC)) < 0.90)")
                        continue
                    }
                }

                // Confidence: blend NCC + amplitude surplus
                let ampScore = min(surplus / (3.0 * localSigma), 1.0)
                let conf = 0.6 * bestNCC + 0.4 * ampScore

                events.append(PinchEvent(tPeak: t[pk.index],
                                         tStart: t[sIdx],
                                         tEnd:   t[eIdx],
                                         confidence: conf,
                                         gateScore: pk.value,
                                         ncc: bestNCC))
                
                candidateDetails.append("Peak[\(pkIdx)] @ \(String(format: "%.3f", t[pk.index]))s: ✅ ACCEPTED - NCC=\(String(format: "%.3f", bestNCC)), tpl[\(originalTplIdx)], scale=\(String(format: "%.2f", scale)), shift=\(bestShift), surplus=\(String(format: "%.2f", surplus/localSigma))σ, comps=\(totalComparisons)\(earlyStop ? " (early)" : "")")
            } else {
                candidateDetails.append("Peak[\(pkIdx)] @ \(String(format: "%.3f", t[pk.index]))s: ❌ REJECTED - NCC=\(String(format: "%.3f", bestNCC)) < \(String(format: "%.3f", nccThresh)), best: tpl[\(originalTplIdx)], scale=\(String(format: "%.2f", scale)), shift=\(bestShift)")
            }
        }

        // Log candidate details
        for detail in candidateDetails {
            log(detail)
        }

        log("📊 Pre-merge results: \(events.count) events passed template matching")

        // Apply mergeNear to prevent duplicate events (consistent with ISI threshold)
        let mergedEvents = mergeNear(events, minGapMs: mergeGapMs)
        
        if events.count != mergedEvents.count {
            log("🔄 Merge near-duplicates: \(events.count) → \(mergedEvents.count) (gap=\(String(format: "%.0f", mergeGapMs))ms)")
            log("📋 Original events: \(events.map { String(format: "%.3f", $0.tPeak) }.joined(separator: ", "))s")
            log("📋 Merged events: \(mergedEvents.map { String(format: "%.3f", $0.tPeak) }.joined(separator: ", "))s")
        } else {
            log("✨ No duplicates to merge (gap=\(String(format: "%.0f", mergeGapMs))ms)")
        }

        let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        log("✅ _process complete in \(String(format: "%.1f", dt))ms, detected \(mergedEvents.count)")

        return mergedEvents
    }
    
    @discardableResult
    public func processWithDebugCallback(frames: [SensorFrame],
                                         debugCallback: @escaping (String) -> Void) -> [PinchEvent] {
        return _process(frames: frames, emit: debugCallback)
    }
}

private struct PeakCandidate {
    let index: Int
    let value: Float
}

