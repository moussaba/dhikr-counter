import Foundation
import Accelerate

// MARK: - Stable RBJ Biquad Filter Implementation
private struct Biquad {
    var b0: Float, b1: Float, b2: Float
    var a1: Float, a2: Float
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
    
    mutating func process(_ x: Float) -> Float {
        let y = b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
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
    mutating func process(_ x: Float) -> Float { lp.process(hp.process(x)) }
}

private func makeBandPass(fs: Float, low: Float, high: Float) -> BandPass {
    let Q: Float = 0.707
    let hp = makeRBJBiquad(.highpass, fc: low,  Q: Q, fs: fs)
    let lp = makeRBJBiquad(.lowpass,  fc: high, Q: Q, fs: fs)
    return BandPass(hp: hp, lp: lp)
}

// NaN/Inf sanitization
private func sanitize(_ x: inout [Float]) {
    for i in x.indices { if !x[i].isFinite { x[i] = 0 } }
}

// Sliding median and MAD for robust statistics
private func slidingMedianMAD(_ x: [Float], winSec: Float, fs: Float) -> ([Float],[Float]) {
    let W = max(3, Int(round(winSec * fs)) | 1) // odd
    var med = [Float](repeating: 0, count: x.count)
    var mad = [Float](repeating: 0, count: x.count)
    for i in 0..<x.count {
        let a = max(0, i - W/2), b = min(x.count, i + W/2 + 1)
        var w = Array(x[a..<b]); w.sort()
        let m = w[w.count/2]
        var d = w.map { abs($0 - m) }; d.sort()
        let md = d[d.count/2]
        med[i] = m; mad[i] = md
    }
    return (med, mad)
}

// Stable bandpass function using RBJ biquads
private func bandpass(_ x: [Float], fs: Float, low: Float, high: Float) -> [Float] {
    guard !x.isEmpty, low > 0, high > low, high < 0.49*fs else { return x }
    var bp = makeBandPass(fs: fs, low: low, high: high)
    var y = [Float](repeating: 0, count: x.count)
    for i in 0..<x.count { y[i] = bp.process(x[i]) }
    sanitize(&y)
    return y
}

// Gate-crossing peak detection
private func detectPeaks(z: [Float], gate: [Float], refractorySec: Float, fs: Float) -> [PeakCandidate] {
    let rN = max(1, Int(round(refractorySec * fs)))
    var peaks: [PeakCandidate] = []
    var i = 1
    while i < z.count - 1 {
        if z[i-1] <= gate[i-1], z[i] > gate[i] {
            var j = i
            while j + 1 < z.count, z[j+1] >= z[j] { j += 1 }
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

// Width measurement
private func measureWidth(_ z: [Float], gate: [Float], peak: Int, fs: Float) -> Float {
    var l = peak, r = peak
    while l > 0 && z[l] > gate[l] { l -= 1 }
    while r + 1 < z.count && z[r] > gate[r] { r += 1 }
    return Float(r - l + 1) * 1000 / fs
}

// Extract window with proper indices
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
        let preS  = Int(round(preMs  * fs / 1000))
        let postS = Int(round(postMs * fs / 1000))
        let L = preS + postS + 1
        var data = [Float](repeating: 0, count: L)
        for i in 0..<L {
            let t = Float(i) / Float(max(L-1, 1))
            data[i] = exp(-pow((t - 0.5) * 6, 2))
        }
        return PinchTemplate(fs: fs, preMs: preMs, postMs: postMs,
                             vectorLength: L, data: data,
                             channelsMeta: "fused_signal", version: "1.0")
    }
    
    public static func loadTrainedTemplates(config: PinchConfig) -> [PinchTemplate] {
        guard let path = Bundle.main.path(forResource: "trained_templates", ofType: "json"),
              let data = NSData(contentsOfFile: path),
              let json = try? JSONSerialization.jsonObject(with: data as Data, options: []) as? [String: Any],
              let templatesArray = json["templates"] as? [[Double]] else {
            print("⚠️ Failed to load trained_templates.json, using synthetic template")
            return [createDefaultTemplate(fs: config.fs, preMs: config.windowPreMs, postMs: config.windowPostMs)]
        }
        
        let expectedLength = Int(round((config.windowPreMs + config.windowPostMs) * config.fs / 1000)) + 1
        let templates = templatesArray.enumerated().compactMap { (index, templateDoubles) -> PinchTemplate? in
            let templateData = templateDoubles.map { Float($0) }
            guard templateData.count == expectedLength else {
                print("⚠️ Template \(index + 1) has length \(templateData.count), expected \(expectedLength) - skipping")
                return nil
            }
            return PinchTemplate(
                fs: config.fs,
                preMs: config.windowPreMs,
                postMs: config.windowPostMs,
                vectorLength: templateData.count,
                data: templateData,
                channelsMeta: "fused_signal_template_\(index + 1)",
                version: "1.0"
            )
        }
        
        if templates.isEmpty {
            print("⚠️ No templates matched expected length \(expectedLength), using synthetic template")
            return [createDefaultTemplate(fs: config.fs, preMs: config.windowPreMs, postMs: config.windowPostMs)]
        }
        
        print("✅ Loaded \(templates.count) trained templates of length \(expectedLength)")
        return templates
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
        
        // Calculate measured fs from timestamps
        let actualFs = frames.count > 1 ? Float(frames.count - 1) / Float(frames.last!.t - frames.first!.t) : config.fs
        
        // Step 1: Data Quality Analysis
        debugLog("=== STEP 1: DATA QUALITY ANALYSIS ===")
        debugLog("📊 Total readings: \(frames.count)")
        
        // Analyze sensor data ranges
        let axValues = frames.map { $0.ax }
        let ayValues = frames.map { $0.ay }
        let azValues = frames.map { $0.az }
        let gxValues = frames.map { $0.gx }
        let gyValues = frames.map { $0.gy }
        let gzValues = frames.map { $0.gz }
        
        debugLog("📏 Accel X: min=\(String(format: "%.3f", axValues.min() ?? 0)), max=\(String(format: "%.3f", axValues.max() ?? 0))")
        debugLog("📏 Accel Y: min=\(String(format: "%.3f", ayValues.min() ?? 0)), max=\(String(format: "%.3f", ayValues.max() ?? 0))")
        debugLog("📏 Accel Z: min=\(String(format: "%.3f", azValues.min() ?? 0)), max=\(String(format: "%.3f", azValues.max() ?? 0))")
        debugLog("🌀 Gyro X: min=\(String(format: "%.3f", gxValues.min() ?? 0)), max=\(String(format: "%.3f", gxValues.max() ?? 0))")
        debugLog("🌀 Gyro Y: min=\(String(format: "%.3f", gyValues.min() ?? 0)), max=\(String(format: "%.3f", gyValues.max() ?? 0))")
        debugLog("🌀 Gyro Z: min=\(String(format: "%.3f", gzValues.min() ?? 0)), max=\(String(format: "%.3f", gzValues.max() ?? 0))")
        
        let avgAccelMag = frames.map { sqrt($0.ax*$0.ax + $0.ay*$0.ay + $0.az*$0.az) }.reduce(0, +) / Float(frames.count)
        let avgGyroMag = frames.map { sqrt($0.gx*$0.gx + $0.gy*$0.gy + $0.gz*$0.gz) }.reduce(0, +) / Float(frames.count)
        debugLog("📊 Avg accel magnitude: \(String(format: "%.4f", avgAccelMag)) m/s²")
        debugLog("📊 Avg gyro magnitude: \(String(format: "%.4f", avgGyroMag)) rad/s")
        
        // Step 2: TKEO Configuration
        debugLog("=== STEP 2: TKEO CONFIGURATION ===")
        debugLog("⚙️ Sample rate: \(String(format: "%.0f", config.fs)) Hz")
        debugLog("🔧 Bandpass filter: \(String(format: "%.1f", config.bandpassLow)) - \(String(format: "%.1f", config.bandpassHigh)) Hz")
        debugLog("🎯 Gate threshold: \(String(format: "%.1f", config.gateK))σ above baseline")
        debugLog("🔗 Fusion weights: accel=\(String(format: "%.1f", config.accelWeight)), gyro=\(String(format: "%.1f", config.gyroWeight))")
        debugLog("⏰ Refractory period: \(String(format: "%.0f", config.refractoryMs))ms")
        debugLog("📏 Templates: \(templates.count) loaded, length: \(templates.first?.vectorLength ?? 0) samples (~\(String(format: "%.0f", Float(templates.first?.vectorLength ?? 0) * 1000.0 / config.fs))ms)")
        debugLog("🎯 Template confidence (NCC): \(String(format: "%.2f", config.nccThresh))")
        
        debugLog("=== STEP 3: SIGNAL PROCESSING ===")
        debugLog("🔄 Converting sensor readings to analysis format...")
        
        // Use stable per-axis processing with measured fs
        let (ax, ay, az, gx, gy, gz, _, t) = preprocessAxes(frames: frames)
        
        // Band-pass per axis using stable RBJ filters
        var aX = bandpass(ax, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        var aY = bandpass(ay, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        var aZ = bandpass(az, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        
        var gX = bandpass(gx, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        var gY = bandpass(gy, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        var gZ = bandpass(gz, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        
        // Sanitize after filtering
        sanitize(&aX); sanitize(&aY); sanitize(&aZ)
        sanitize(&gX); sanitize(&gY); sanitize(&gZ)
        
        // TKEO per axis with positive clamp
        var aXT = tkeo(aX), aYT = tkeo(aY), aZT = tkeo(aZ)
        var gXT = tkeo(gX), gYT = tkeo(gY), gZT = tkeo(gZ)
        
        // Sanitize TKEO outputs
        sanitize(&aXT); sanitize(&aYT); sanitize(&aZT)
        sanitize(&gXT); sanitize(&gYT); sanitize(&gZT)
        
        debugLog("⚡ TKEO computed for \(frames.count) samples")
        debugLog("📈 TKEO peaks - AX:\(String(format: "%.6f", aXT.max() ?? 0)), AY:\(String(format: "%.6f", aYT.max() ?? 0)), AZ:\(String(format: "%.6f", aZT.max() ?? 0))")
        debugLog("📈 TKEO peaks - GX:\(String(format: "%.6f", gXT.max() ?? 0)), GY:\(String(format: "%.6f", gYT.max() ?? 0)), GZ:\(String(format: "%.6f", gZT.max() ?? 0))")
        
        // Fuse across axes: L2 norm of positive TKEO values
        var accelTkeo = fuseL2Positive([aXT, aYT, aZT])
        var gyroTkeo = fuseL2Positive([gXT, gYT, gZT])
        
        // Sanitize fused outputs
        sanitize(&accelTkeo)
        sanitize(&gyroTkeo)
        
        // Use stable sliding median/MAD for robust statistics
        let (accelMed, accelMAD) = slidingMedianMAD(accelTkeo, winSec: config.madWinSec, fs: actualFs)
        let (gyroMed, gyroMAD) = slidingMedianMAD(gyroTkeo, winSec: config.madWinSec, fs: actualFs)
        
        // Normalize using robust statistics
        var accelZ = zip(accelTkeo, zip(accelMed, accelMAD)).map { (v, mm) in
            let (m, mad) = mm; return mad > 0 ? (v - m) / mad : 0
        }
        var gyroZ = zip(gyroTkeo, zip(gyroMed, gyroMAD)).map { (v, mm) in
            let (m, mad) = mm; return mad > 0 ? (v - m) / mad : 0
        }
        
        // Sanitize normalized signals
        sanitize(&accelZ); sanitize(&gyroZ)
        
        // Weighted fusion
        var fusedSignal = zip(accelZ, gyroZ).map { config.accelWeight*$0 + config.gyroWeight*$1 }
        
        // Optional light smoothing (EMA with α=0.2)
        if fusedSignal.count > 1 {
            let alpha: Float = 0.2
            for i in 1..<fusedSignal.count {
                fusedSignal[i] = alpha * fusedSignal[i-1] + (1-alpha) * fusedSignal[i]
            }
        }
        
        // Final sanitization
        sanitize(&fusedSignal)
        
        // Build robust per-sample gate using median + K·MAD
        let (fMed, fMAD) = slidingMedianMAD(fusedSignal, winSec: config.madWinSec, fs: actualFs)
        let gate = zip(fMed, fMAD).map { (m, md) in m + config.gateK * max(md, 1e-6) }
        
        let fusedMax = fusedSignal.max() ?? 0
        let fusedMean = fusedSignal.reduce(0, +) / Float(fusedSignal.count)
        let gateMax = gate.max() ?? 0
        let gateMean = gate.reduce(0, +) / Float(gate.count)
        let percentAboveGate = Float(zip(fusedSignal, gate).filter { $0 > $1 }.count) / Float(fusedSignal.count) * 100
        
        debugLog("🔗 Fusion signal - max:\(String(format: "%.6f", fusedMax)), avg:\(String(format: "%.6f", fusedMean))")
        debugLog("🚪 Gate - max:\(String(format: "%.6f", gateMax)), avg:\(String(format: "%.6f", gateMean)), % above: \(String(format: "%.1f", percentAboveGate))%")
        debugLog("📏 Measured fs: \(String(format: "%.1f", actualFs)) Hz")
        
        // Use gate-crossing peak detection with measured fs
        let peakCandidates = detectPeaks(z: fusedSignal, gate: gate, refractorySec: config.refractoryMs / 1000.0, fs: actualFs)
        
        debugLog("🏔️ Found \(peakCandidates.count) candidate peaks above gate threshold")
        
        var pinchEvents: [PinchEvent] = []
        
        debugLog("🏔️ Found \(peakCandidates.count) candidate peaks above gate threshold")
        
        // Step 4: Template Matching
        debugLog("=== STEP 4: TEMPLATE MATCHING ===")
        
        // Compute template window dimensions from time parameters
        let preS  = Int(round(config.windowPreMs  * actualFs / 1000))
        let postS = Int(round(config.windowPostMs * actualFs / 1000))
        let L     = preS + postS + 1
        
        debugLog("📏 Template window: \(String(format: "%.0f", config.windowPreMs))ms pre + \(String(format: "%.0f", config.windowPostMs))ms post = \(L) samples")
        
        // Filter templates to matching length
        let templatesL = templates.filter { $0.data.count == L }
        guard !templatesL.isEmpty else {
            debugLog("⚠️ No templates of length \(L) samples (need \(String(format: "%.0f", Float(L) * 1000 / actualFs))ms @ \(String(format: "%.1f", actualFs))Hz)")
            return []
        }
        
        debugLog("🎯 Using \(templatesL.count) templates of length \(L), NCC threshold: \(String(format: "%.2f", config.nccThresh))")
        
        var templateMatchCount = 0
        var nccScores: [Float] = []
        
        for candidate in peakCandidates {
            // Apply width constraints
            let width = measureWidth(fusedSignal, gate: gate, peak: candidate.index, fs: actualFs)
            guard width >= config.minWidthMs && width <= config.maxWidthMs else {
                debugLog("🚫 Peak at \(String(format: "%.3f", t[candidate.index]))s rejected: width \(String(format: "%.1f", width))ms outside [\(String(format: "%.0f", config.minWidthMs)), \(String(format: "%.0f", config.maxWidthMs))]ms")
                continue
            }
            
            // Extract window with proper indices
            let (window, sIdx, eIdx) = extractWindow(center: candidate.index, from: fusedSignal, preS: preS, postS: postS, L: L)
            
            // Try templates to find the best match
            var bestNccScore: Float = 0.0
            
            for template in templatesL {
                let nccScore = ncc(window: window, template: template.data)
                if nccScore > bestNccScore {
                    bestNccScore = nccScore
                }
            }
            
            nccScores.append(bestNccScore)
            
            if bestNccScore >= config.nccThresh {
                // Enhanced confidence using local surplus over gate
                let surplus = max(0, candidate.value - gate[candidate.index])
                let localScale = max(1e-6, fMAD[candidate.index])
                let ampScore = min(surplus / (3*localScale), 1.0)
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
                templateMatchCount += 1
            }
        }
        
        // Telemetry: top-5 NCC scores
        let topNCC = nccScores.sorted(by: >).prefix(5)
        let topNCCString = topNCC.map { String(format: "%.3f", $0) }.joined(separator: ", ")
        debugLog("📈 Top-5 NCC: [\(topNCCString)]")
        
        // Final analysis results
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        if pinchEvents.isEmpty {
            debugLog("❌ No peaks passed template matching")
            debugLog("   • Template may not match actual pinch signature")
            debugLog("   • Need to collect training data from confirmed pinches")
            debugLog("   • Consider lowering template confidence for initial testing")
        }
        
        debugLog("=== ANALYSIS COMPLETE ===")
        debugLog("✅ Processing time: \(String(format: "%.1f", processingTime * 1000))ms")
        debugLog("📊 Final result: \(pinchEvents.count) pinch events detected")
        
        if pinchEvents.isEmpty {
            debugLog("")
            debugLog("💡 DEBUGGING SUGGESTIONS:")
            debugLog("   1. Check if hand motion was sufficient during recording")
            debugLog("   2. Verify watch was worn properly during session")
            debugLog("   3. Try lower thresholds in settings")
            debugLog("   4. Perform more pronounced pinching gestures")
            debugLog("   5. Ensure 3-5 second recording duration minimum")
        }
        
        return pinchEvents
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
        
        for frame in frames {
            ax.append(frame.ax); ay.append(frame.ay); az.append(frame.az)
            gx.append(frame.gx); gy.append(frame.gy); gz.append(frame.gz)
            t.append(frame.t)
        }
        
        return (ax, ay, az, gx, gy, gz, actualFs, t)
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
        
        for frame in frames {
            let aMag = sqrt(frame.ax * frame.ax + frame.ay * frame.ay + frame.az * frame.az)
            let gMag = sqrt(frame.gx * frame.gx + frame.gy * frame.gy + frame.gz * frame.gz)
            
            accelMag.append(aMag)
            gyroMag.append(gMag)
            t.append(frame.t)
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
    
    
    
    private func ncc(window: [Float], template: [Float]) -> Float {
        guard window.count == template.count else { return 0 }
        let wMean = window.reduce(0, +) / Float(window.count)
        let tMean = template.reduce(0, +) / Float(template.count)
        var num: Float = 0, wss: Float = 0, tss: Float = 0
        for i in 0..<window.count {
            let wc = window[i] - wMean
            let tc = template[i] - tMean
            num += wc * tc
            wss += wc * wc
            tss += tc * tc
        }
        let den = sqrt(wss * tss)
        return den > 0 ? num / den : 0
    }
    
    // Stable debug processing with detailed logging  
    public func processWithDebugCallback(frames: [SensorFrame], debugCallback: @escaping (String) -> Void) -> [PinchEvent] {
        guard !frames.isEmpty else { 
            debugCallback("❌ Empty frames array")
            return [] 
        }
        
        debugCallback("🔬 TKEO DEBUG: 🔍 Starting stable TKEO analysis with \(frames.count) readings")
        
        // Calculate measured fs from timestamps
        let actualFs = frames.count > 1 ? Float(frames.count - 1) / Float(frames.last!.t - frames.first!.t) : config.fs
        debugCallback("🔬 TKEO DEBUG: 📏 Measured fs: \(String(format: "%.1f", actualFs)) Hz")
        
        // Use stable per-axis processing
        let (ax, ay, az, gx, gy, gz, _, t) = preprocessAxes(frames: frames)
        
        // Compute raw signal magnitudes for comparison
        var accelMag = [Float](), gyroMag = [Float]()
        for i in 0..<frames.count {
            accelMag.append(sqrt(ax[i]*ax[i] + ay[i]*ay[i] + az[i]*az[i]))
            gyroMag.append(sqrt(gx[i]*gx[i] + gy[i]*gy[i] + gz[i]*gz[i]))
        }
        
        let accelMean = accelMag.reduce(0, +) / Float(accelMag.count)
        let gyroMean = gyroMag.reduce(0, +) / Float(gyroMag.count)
        let accelMax = accelMag.max() ?? 0
        let gyroMax = gyroMag.max() ?? 0
        
        debugCallback("🔬 TKEO DEBUG: 🏃 Accel: mean=\(String(format: "%.3f", accelMean)), max=\(String(format: "%.3f", accelMax)) m/s²")
        debugCallback("🔬 TKEO DEBUG: 🌀 Gyro: mean=\(String(format: "%.3f", gyroMean)), max=\(String(format: "%.3f", gyroMax)) rad/s")
        
        // Band-pass per axis using stable RBJ filters
        var aX = bandpass(ax, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        var aY = bandpass(ay, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        var aZ = bandpass(az, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        
        var gX = bandpass(gx, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        var gY = bandpass(gy, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        var gZ = bandpass(gz, fs: actualFs, low: config.bandpassLow, high: config.bandpassHigh)
        
        // Sanitize after filtering
        sanitize(&aX); sanitize(&aY); sanitize(&aZ)
        sanitize(&gX); sanitize(&gY); sanitize(&gZ)
        
        // TKEO per axis with positive clamp
        var aXT = tkeo(aX), aYT = tkeo(aY), aZT = tkeo(aZ)
        var gXT = tkeo(gX), gYT = tkeo(gY), gZT = tkeo(gZ)
        
        // Sanitize TKEO outputs
        sanitize(&aXT); sanitize(&aYT); sanitize(&aZT)
        sanitize(&gXT); sanitize(&gYT); sanitize(&gZT)
        
        // Fuse across axes: L2 norm of positive TKEO values
        var accelTkeo = fuseL2Positive([aXT, aYT, aZT])
        var gyroTkeo = fuseL2Positive([gXT, gYT, gZT])
        
        // Sanitize fused outputs
        sanitize(&accelTkeo)
        sanitize(&gyroTkeo)
        
        let accelTkeoMean = accelTkeo.reduce(0, +) / Float(accelTkeo.count)
        let accelTkeoMax = accelTkeo.max() ?? 0
        debugCallback("🔬 TKEO DEBUG: ⚡ Accel TKEO: mean=\(String(format: "%.6f", accelTkeoMean)), max=\(String(format: "%.6f", accelTkeoMax))")
        
        let gyroTkeoMean = gyroTkeo.reduce(0, +) / Float(gyroTkeo.count)
        let gyroTkeoMax = gyroTkeo.max() ?? 0
        debugCallback("🔬 TKEO DEBUG: 🌪️ Gyro TKEO: mean=\(String(format: "%.6f", gyroTkeoMean)), max=\(String(format: "%.6f", gyroTkeoMax))")
        
        debugCallback("🔬 TKEO DEBUG: ✅ Stable TKEO processing complete - all values finite")
        
        // Return empty for debug mode
        return []
    }
}

private struct PeakCandidate {
    let index: Int
    let value: Float
}

