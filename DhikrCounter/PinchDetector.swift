import Foundation
import Accelerate

public struct SensorFrame {
    let t: TimeInterval
    let ax, ay, az: Float  // m/s²
    let gx, gy, gz: Float  // rad/s
}

public struct PinchEvent {
    let tPeak, tStart, tEnd: TimeInterval
    let confidence, gateScore, ncc: Float
}

public struct PinchConfig {
    let fs: Float
    let bandpassLow: Float
    let bandpassHigh: Float
    let accelWeight: Float
    let gyroWeight: Float
    let madWinSec: Float
    let gateK: Float
    let refractoryMs: Float
    let minWidthMs: Float
    let maxWidthMs: Float
    let nccThresh: Float
    let windowPreMs: Float
    let windowPostMs: Float
    
    // Convenience initializer with default values to reduce brittleness
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
        nccThresh: Float = 0.6,
        windowPreMs: Float = 150,
        windowPostMs: Float = 250
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
    }
    
    // Static factory method for creating from UserDefaults
    public static func fromUserDefaults() -> PinchConfig {
        let userDefaults = UserDefaults.standard
        return PinchConfig(
            fs: userDefaults.object(forKey: "tkeo_sampleRate") as? Float ?? 50.0,
            bandpassLow: userDefaults.object(forKey: "tkeo_bandpassLow") as? Float ?? 3.0,
            bandpassHigh: userDefaults.object(forKey: "tkeo_bandpassHigh") as? Float ?? 20.0,
            accelWeight: userDefaults.object(forKey: "tkeo_accelWeight") as? Float ?? 1.0,
            gyroWeight: userDefaults.object(forKey: "tkeo_gyroWeight") as? Float ?? 1.5,
            madWinSec: userDefaults.object(forKey: "tkeo_madWinSec") as? Float ?? 3.0,
            gateK: userDefaults.object(forKey: "tkeo_gateK") as? Float ?? 3.5,
            refractoryMs: userDefaults.object(forKey: "tkeo_refractoryMs") as? Float ?? 150,
            minWidthMs: userDefaults.object(forKey: "tkeo_minWidthMs") as? Float ?? 60,
            maxWidthMs: userDefaults.object(forKey: "tkeo_maxWidthMs") as? Float ?? 400,
            nccThresh: userDefaults.object(forKey: "tkeo_nccThresh") as? Float ?? 0.6,
            windowPreMs: userDefaults.object(forKey: "tkeo_windowPreMs") as? Float ?? 150,
            windowPostMs: userDefaults.object(forKey: "tkeo_windowPostMs") as? Float ?? 250
        )
    }
}

public struct PinchTemplate {
    let fs: Float
    let preMs: Float
    let postMs: Float
    let vectorLength: Int
    let data: [Float]
    let channelsMeta: String
    let version: String
}

// MARK: - Stable RBJ Biquad Filters

private struct Biquad {
    var b0: Float, b1: Float, b2: Float
    var a1: Float, a2: Float
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
    
    mutating func process(_ x: Float) -> Float {
        let y = b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}

private enum BiquadType { case lowpass, highpass }

private func makeRBJBiquad(_ type: BiquadType, fc: Float, Q: Float, fs: Float) -> Biquad {
    // clamp fc to (0, fs/2)
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
    
    // normalize by a0
    return Biquad(b0: b0/a0, b1: b1/a0, b2: b2/a0, a1: a1/a0, a2: a2/a0)
}

private struct BandPass {
    var hp: Biquad
    var lp: Biquad
    
    mutating func process(_ x: Float) -> Float {
        return lp.process(hp.process(x))
    }
}

private func makeBandPass(fs: Float, low: Float, high: Float) -> BandPass {
    let Q: Float = 0.707
    let hp = makeRBJBiquad(.highpass, fc: low, Q: Q, fs: fs)
    let lp = makeRBJBiquad(.lowpass, fc: high, Q: Q, fs: fs)
    return BandPass(hp: hp, lp: lp)
}

// MARK: - Utility Functions

private func sanitize(_ x: inout [Float]) {
    for i in x.indices {
        if !x[i].isFinite {
            x[i] = 0
        }
    }
}

private func slidingMedianMAD(_ x: [Float], winSec: Float, fs: Float) -> ([Float], [Float]) {
    let W = max(3, Int(round(winSec * fs)) | 1) // odd
    var med = [Float](repeating: 0, count: x.count)
    var mad = [Float](repeating: 0, count: x.count)
    
    for i in 0..<x.count {
        let a = max(0, i - W/2)
        let b = min(x.count, i + W/2 + 1)
        var w = Array(x[a..<b])
        w.sort()
        
        let m = w[w.count/2]
        var d = w.map { abs($0 - m) }
        d.sort()
        let md = d[d.count/2]
        
        med[i] = m
        mad[i] = md
    }
    
    return (med, mad)
}

private struct PeakCandidate {
    let index: Int
    let value: Float
}

// MARK: - Peak Detection

private func detectPeaks(z: [Float], gate: [Float], refractorySec: Float, fs: Float) -> [PeakCandidate] {
    let rN = max(1, Int(round(refractorySec * fs)))
    var peaks: [PeakCandidate] = []
    var i = 1
    
    while i < z.count - 1 {
        if z[i-1] <= gate[i-1] && z[i] > gate[i] {
            // Gate crossing detected, climb to local maximum
            var j = i
            while j + 1 < z.count && z[j+1] >= z[j] {
                j += 1
            }
            
            // Ensure peak remains above gate
            if z[j] > gate[j] {
                peaks.append(PeakCandidate(index: j, value: z[j]))
                i = j + rN
            } else {
                i += 1
            }
        } else {
            i += 1
        }
    }
    
    return peaks
}

// MARK: - Width Measurement

private func measureWidth(_ z: [Float], gate: [Float], peak: Int, fs: Float) -> Float {
    var l = peak, r = peak
    while l > 0 && z[l] > gate[l] { l -= 1 }
    while r + 1 < z.count && z[r] > gate[r] { r += 1 }
    return Float(r - l + 1) * 1000.0 / fs  // ms
}

// MARK: - EMA Smoothing

private func ema(_ x: [Float], alpha: Float) -> [Float] {
    guard !x.isEmpty else { return x }
    var y = x
    for i in 1..<x.count {
        y[i] = alpha * y[i-1] + (1 - alpha) * x[i]
    }
    return y
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
            bandpassHigh: 20.0,
            accelWeight: 1.0,
            gyroWeight: 1.5,
            madWinSec: 3.0,
            gateK: 3.5,
            refractoryMs: 150,
            minWidthMs: 60,
            maxWidthMs: 400,
            nccThresh: 0.6,
            windowPreMs: 150,
            windowPostMs: 250
        )
    }
    
    public static func createDefaultTemplate(fs: Float = 50.0,
                                           preMs: Float = 150,
                                           postMs: Float = 250) -> PinchTemplate {
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
        
        print("✅ Loaded \(templatesArray.count) trained templates from JSON")
        return templatesArray.enumerated().map { (index, templateDoubles) in
            let templateData = templateDoubles.map { Float($0) }
            return PinchTemplate(
                fs: 50.0,
                preMs: 150.0,
                postMs: 250.0,
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
    
    func process(frames: [SensorFrame]) -> [PinchEvent] {
        guard !frames.isEmpty else { return [] }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Calculate measured fs from actual timestamps
        let actualFs = frames.count > 1 ? Float(frames.count - 1) / Float(frames.last!.t - frames.first!.t) : config.fs
        
        debugLog("=== PINCH DETECTION START ===")
        debugLog("📊 Total readings: \(frames.count)")
        debugLog("⚙️ Measured fs: \(String(format: "%.1f", actualFs)) Hz (config: \(String(format: "%.1f", config.fs)) Hz)")
        
        // Step 1: Per-axis preprocessing 
        var ax = frames.map { $0.ax }
        var ay = frames.map { $0.ay }
        var az = frames.map { $0.az }
        var gx = frames.map { $0.gx }
        var gy = frames.map { $0.gy }
        var gz = frames.map { $0.gz }
        let t = frames.map { $0.t }
        
        // Step 2: Stable RBJ Biquad Bandpass Filtering
        ax = bandpass(ax, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        ay = bandpass(ay, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        az = bandpass(az, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        
        gx = bandpass(gx, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        gy = bandpass(gy, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        gz = bandpass(gz, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        
        // Step 3: TKEO computation per axis
        var aXT = tkeo(ax), aYT = tkeo(ay), aZT = tkeo(az)
        var gXT = tkeo(gx), gYT = tkeo(gy), gZT = tkeo(gz)
        
        // Step 4: NaN/Inf sanitization after filtering
        sanitize(&aXT); sanitize(&aYT); sanitize(&aZT)
        sanitize(&gXT); sanitize(&gYT); sanitize(&gZT)
        
        // Step 5: L2 fusion of TKEO values
        let accelTkeo = fuseL2Positive([aXT, aYT, aZT])
        let gyroTkeo = fuseL2Positive([gXT, gYT, gZT])
        
        // Step 6: Robust MAD-based normalization
        let (accMed, accMad) = slidingMedianMAD(accelTkeo, winSec: config.madWinSec, fs: actualFs)
        let (gyrMed, gyrMad) = slidingMedianMAD(gyroTkeo, winSec: config.madWinSec, fs: actualFs)
        
        var accelZ = zip(accelTkeo, zip(accMed, accMad)).map { (v, mm) in
            let (m, mad) = mm; return mad > 0 ? (v - m) / mad : 0
        }
        var gyroZ = zip(gyroTkeo, zip(gyrMed, gyrMad)).map { (v, mm) in
            let (m, mad) = mm; return mad > 0 ? (v - m) / mad : 0
        }
        
        sanitize(&accelZ); sanitize(&gyroZ)
        
        // Step 7: Weighted fusion 
        var fusedSignal = zip(accelZ, gyroZ).map { config.accelWeight * $0 + config.gyroWeight * $1 }
        sanitize(&fusedSignal)
        
        // Optional light EMA smoothing
        let fusedSmoothed = ema(fusedSignal, alpha: 0.2)
        
        // Step 8: Robust per-sample gating
        let (fMed, fMAD) = slidingMedianMAD(fusedSmoothed, winSec: config.madWinSec, fs: actualFs)
        let gate = zip(fMed, fMAD).map { (m, md) in m + config.gateK * max(md, 1e-6) }
        
        // Step 9: Gate-crossing peak detection with measured fs
        let peakCandidates = detectPeaks(z: fusedSmoothed, gate: gate, 
                                       refractorySec: config.refractoryMs / 1000.0, 
                                       fs: actualFs)
        
        debugLog("🏔️ Found \(peakCandidates.count) peak candidates")
        
        // Step 10: Template window setup
        let preS = Int(round(config.windowPreMs * actualFs / 1000))
        let postS = Int(round(config.windowPostMs * actualFs / 1000))
        let L = preS + postS + 1
        
        // Filter templates to matching length
        let templatesL = templates.filter { $0.data.count == L }
        if templatesL.isEmpty {
            debugLog("⚠️ No templates match required length L=\(L)")
            return []
        }
        
        debugLog("🎯 Using \(templatesL.count) templates of length \(L)")
        
        // Step 11: NCC Template Matching with Width Constraints
        var pinchEvents: [PinchEvent] = []
        var nccScores: [Float] = []
        var acceptedCount = 0
        let totalAboveGate = fusedSmoothed.enumerated().filter { (i, val) in val > gate[i] }.count
        
        for candidate in peakCandidates {
            // Width constraint check
            let width = measureWidth(fusedSmoothed, gate: gate, peak: candidate.index, fs: actualFs)
            if width < config.minWidthMs || width > config.maxWidthMs {
                continue
            }
            
            // Extract window with proper indices for tStart/tEnd
            let (window, sIdx, eIdx) = extractWindow(center: candidate.index, from: fusedSmoothed, 
                                                   preS: preS, postS: postS, L: L)
            
            // NCC against all valid templates
            var bestNccScore: Float = 0.0
            for template in templatesL {
                let score = ncc(window: window, template: template.data)
                if score > bestNccScore {
                    bestNccScore = score
                }
            }
            
            nccScores.append(bestNccScore)
            
            if bestNccScore >= config.nccThresh {
                // Enhanced confidence with local surplus
                let surplus = max(0, candidate.value - gate[candidate.index])
                let localScale = max(1e-6, fMAD[candidate.index])
                let ampScore = min(surplus / (3 * localScale), 1.0)
                let confidence = 0.6 * bestNccScore + 0.4 * ampScore
                
                let event = PinchEvent(
                    tPeak: t[candidate.index],
                    tStart: t[sIdx],
                    tEnd: t[eIdx],
                    confidence: confidence,
                    gateScore: candidate.value,
                    ncc: bestNccScore
                )
                pinchEvents.append(event)
                acceptedCount += 1
            }
        }
        
        // Step 12: Telemetry logging
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        let pctAboveGate = totalAboveGate > 0 ? Float(totalAboveGate) / Float(fusedSmoothed.count) * 100 : 0
        let top5NCC = Array(nccScores.sorted(by: >).prefix(5))
        
        debugLog("=== TELEMETRY ===")
        debugLog("📈 fs(measured): \(String(format: "%.1f", actualFs)) Hz")
        debugLog("🎯 Candidates: \(peakCandidates.count) -> accepted: \(acceptedCount)")
        debugLog("📈 % above gate: \(String(format: "%.1f", pctAboveGate))%")
        debugLog("🏆 Top-5 NCC: \(top5NCC.map { String(format: "%.3f", $0) }.joined(separator: ", "))")
        debugLog("⏱️ Processing time: \(String(format: "%.1f", processingTime * 1000))ms")
        debugLog("✅ Final: \(pinchEvents.count) pinch events detected")
        
        return pinchEvents
    }
    
    // Window extraction with proper indices for tStart/tEnd
    private func extractWindow(center idx: Int, from z: [Float], preS: Int, postS: Int, L: Int) -> (win: [Float], s: Int, e: Int) {
        let s0 = max(0, idx - preS)
        let e0 = min(z.count - 1, idx + postS)
        var w = Array(z[s0...e0])
        
        if w.count < L {
            if s0 == 0 {
                w = Array(repeating: z.first!, count: L - w.count) + w
            }
            if e0 == z.count - 1 {
                w += Array(repeating: z.last!, count: L - w.count)
            }
        }
        
        return (Array(w.prefix(L)), s0, min(e0, s0 + L - 1))
    }
    
    // Use top-level functions for stable implementations
    private func fuseL2Positive(_ axes: [[Float]]) -> [Float] {
        guard !axes.isEmpty else { return [] }
        let n = axes[0].count
        var out = [Float](repeating: 0, count: n)
        
        for i in 0..<n {
            var s: Float = 0
            for k in 0..<axes.count {
                let v = axes[k][i]
                let vp = max(v, 0)  // Positive clamp
                s += vp * vp
            }
            out[i] = sqrt(s)
        }
        return out
    }
    
    private func bandpass(_ x: [Float], fs: Float, low: Float, high: Float) -> [Float] {
        guard !x.isEmpty, low > 0, high > low, high < 0.49*fs else { return x }
        
        var filter = makeBandPass(fs: fs, low: low, high: high)
        var y = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count {
            y[i] = filter.process(x[i])
        }
        sanitize(&y)
        return y
    }
    
    private func tkeo(_ x: [Float]) -> [Float] {
        guard x.count >= 3 else { return Array(repeating: 0, count: x.count) }
        
        var y = [Float](repeating: 0, count: x.count)
        
        // Boundary handling: use squared values
        y[0] = x[0] * x[0]
        y[y.count - 1] = x[y.count - 1] * x[y.count - 1]
        
        // Compute TKEO for interior points with positive clamp
        for i in 1..<(x.count - 1) {
            let v = x[i] * x[i] - x[i - 1] * x[i + 1]
            y[i] = max(v, 0)  // Clamp negatives to prevent false triggers
        }
        
        return y
    }
    
    private func ncc(window: [Float], template: [Float]) -> Float {
        guard window.count == template.count else { return 0.0 }
        
        let windowMean = window.reduce(0, +) / Float(window.count)
        let templateMean = template.reduce(0, +) / Float(template.count)
        
        let windowCentered = window.map { $0 - windowMean }
        let templateCentered = template.map { $0 - templateMean }
        
        let numerator = zip(windowCentered, templateCentered).map(*).reduce(0, +)
        
        let windowSumSq = windowCentered.map { $0 * $0 }.reduce(0, +)
        let templateSumSq = templateCentered.map { $0 * $0 }.reduce(0, +)
        
        let denominator = sqrt(windowSumSq * templateSumSq)
        
        return denominator > 0 ? numerator / denominator : 0.0
    }
    
    // Debug processing using stable filtering and sanitization
    public func processWithDebugCallback(frames: [SensorFrame], debugCallback: @escaping (String) -> Void) -> [PinchEvent] {
        guard !frames.isEmpty else { 
            debugCallback("❌ Empty frames array")
            return [] 
        }
        
        debugCallback("🔬 TKEO DEBUG: 🔍 Starting TKEO analysis with \(frames.count) readings")
        
        // Calculate measured fs from actual timestamps
        let actualFs = frames.count > 1 ? Float(frames.count - 1) / Float(frames.last!.t - frames.first!.t) : config.fs
        
        // Per-axis preprocessing 
        var ax = frames.map { $0.ax }
        var ay = frames.map { $0.ay }
        var az = frames.map { $0.az }
        var gx = frames.map { $0.gx }
        var gy = frames.map { $0.gy }
        var gz = frames.map { $0.gz }
        
        // Compute raw signal magnitudes for comparison
        let accelMag = frames.map { sqrt($0.ax*$0.ax + $0.ay*$0.ay + $0.az*$0.az) }
        let gyroMag = frames.map { sqrt($0.gx*$0.gx + $0.gy*$0.gy + $0.gz*$0.gz) }
        
        let accelMean = accelMag.reduce(0, +) / Float(accelMag.count)
        let gyroMean = gyroMag.reduce(0, +) / Float(gyroMag.count)
        let accelMax = accelMag.max() ?? 0
        let gyroMax = gyroMag.max() ?? 0
        
        debugCallback("🔬 TKEO DEBUG: 🏃 Accel: mean=\(String(format: "%.3f", accelMean)), max=\(String(format: "%.3f", accelMax)) m/s²")
        debugCallback("🔬 TKEO DEBUG: 🌀 Gyro: mean=\(String(format: "%.3f", gyroMean)), max=\(String(format: "%.3f", gyroMax)) rad/s")
        
        // Stable RBJ Biquad Bandpass Filtering
        ax = bandpass(ax, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        ay = bandpass(ay, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        az = bandpass(az, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        
        gx = bandpass(gx, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        gy = bandpass(gy, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        gz = bandpass(gz, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        
        // TKEO per axis with positive clamp
        var aXT = tkeo(ax), aYT = tkeo(ay), aZT = tkeo(az)
        var gXT = tkeo(gx), gYT = tkeo(gy), gZT = tkeo(gz)
        
        // NaN/Inf sanitization after filtering
        sanitize(&aXT); sanitize(&aYT); sanitize(&aZT)
        sanitize(&gXT); sanitize(&gYT); sanitize(&gZT)
        
        // L2 fusion of TKEO values
        let accelTkeo = fuseL2Positive([aXT, aYT, aZT])
        let gyroTkeo = fuseL2Positive([gXT, gYT, gZT])
        
        let validAccelTkeo = accelTkeo.filter { $0.isFinite }
        let accelTkeoMean = validAccelTkeo.isEmpty ? 0.0 : validAccelTkeo.reduce(0, +) / Float(validAccelTkeo.count)
        let accelTkeoMax = validAccelTkeo.max() ?? 0
        debugCallback("🔬 TKEO DEBUG: ⚡ Accel TKEO: mean=\(String(format: "%.3f", accelTkeoMean)), max=\(String(format: "%.3f", accelTkeoMax)) (valid: \(validAccelTkeo.count)/\(accelTkeo.count))")
        
        let validGyroTkeo = gyroTkeo.filter { $0.isFinite }
        let gyroTkeoMean = validGyroTkeo.isEmpty ? 0.0 : validGyroTkeo.reduce(0, +) / Float(validGyroTkeo.count)
        let gyroTkeoMax = validGyroTkeo.max() ?? 0
        debugCallback("🔬 TKEO DEBUG: 🌪️ Gyro TKEO: mean=\(String(format: "%.3f", gyroTkeoMean)), max=\(String(format: "%.3f", gyroTkeoMax)) (valid: \(validGyroTkeo.count)/\(gyroTkeo.count))")
        
        debugCallback("🔬 TKEO DEBUG: ✅ Stable TKEO processing complete with sanitization")
        
        // Return empty for debug-only usage
        return []
    }
}

