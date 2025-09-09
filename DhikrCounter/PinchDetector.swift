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
    
    mutating func process(_ x: Float) -> Float { 
        return lp.process(hp.process(x)) 
    }
}

private func makeBandPass(fs: Float, low: Float, high: Float) -> BandPass {
    let Q: Float = 0.707
    let hp = makeRBJBiquad(.highpass, fc: low,  Q: Q, fs: fs)
    let lp = makeRBJBiquad(.lowpass,  fc: high, Q: Q, fs: fs)
    return BandPass(hp: hp, lp: lp)
}

// MARK: - Sanitization and Robust Gating
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
    
    public static func createDefaultTemplate() -> PinchTemplate {
        let templateLength = 40
        var templateData = [Float](repeating: 0.1, count: templateLength)
        
        // Create a synthetic pinch template (bell curve)
        for i in 0..<templateLength {
            let t = Float(i) / Float(templateLength - 1)
            templateData[i] = exp(-pow((t - 0.5) * 6, 2))
        }
        
        return PinchTemplate(
            fs: 50.0,
            preMs: 150.0,
            postMs: 250.0,
            vectorLength: templateLength,
            data: templateData,
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
        
        // Use Python-style per-axis processing (no jerk, no magnitude-first)
        let (ax, ay, az, gx, gy, gz, fs, t) = preprocessAxes(frames: frames)
        
        // Band-pass per axis (no jerk)
        let aX = bandpass(ax, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        let aY = bandpass(ay, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        let aZ = bandpass(az, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        
        let gX = bandpass(gx, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        let gY = bandpass(gy, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        let gZ = bandpass(gz, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        
        // TKEO per axis with positive clamp (Python-style)
        let aXT = tkeo(aX), aYT = tkeo(aY), aZT = tkeo(aZ)
        let gXT = tkeo(gX), gYT = tkeo(gY), gZT = tkeo(gZ)
        
        debugLog("⚡ TKEO computed for \(frames.count) samples")
        debugLog("📈 TKEO peaks - AX:\(String(format: "%.6f", aXT.max() ?? 0)), AY:\(String(format: "%.6f", aYT.max() ?? 0)), AZ:\(String(format: "%.6f", aZT.max() ?? 0))")
        debugLog("📈 TKEO peaks - GX:\(String(format: "%.6f", gXT.max() ?? 0)), GY:\(String(format: "%.6f", gYT.max() ?? 0)), GZ:\(String(format: "%.6f", gZT.max() ?? 0))")
        
        // Fuse across axes: L2 norm of positive TKEO values (Python-style)
        let accelTkeo = fuseL2Positive([aXT, aYT, aZT])
        let gyroTkeo = fuseL2Positive([gXT, gYT, gZT])
        
        // Sanitize TKEO outputs before stats computation
        var accelTkeoClean = accelTkeo
        var gyroTkeoClean = gyroTkeo
        sanitize(&accelTkeoClean)
        sanitize(&gyroTkeoClean)
        
        let (accelMed, accelMad) = slidingMedianMAD(accelTkeoClean, winSec: config.madWinSec, fs: fs)
        let (gyroMed, gyroMad) = slidingMedianMAD(gyroTkeoClean, winSec: config.madWinSec, fs: fs)

        var accelZ = zip(accelTkeoClean, zip(accelMed, accelMad)).map { (v, mm) in
            let (m, mad) = mm; return mad > 0 ? (v - m) / mad : 0
        }
        var gyroZ = zip(gyroTkeoClean, zip(gyroMed, gyroMad)).map { (v, mm) in
            let (m, mad) = mm; return mad > 0 ? (v - m) / mad : 0
        }

        sanitize(&accelZ)
        sanitize(&gyroZ)

        let fused = zip(accelZ, gyroZ).map { config.accelWeight*$0 + config.gyroWeight*$1 }
        var fusedSignal = fused
        sanitize(&fusedSignal)

        let (fMed, fMAD) = slidingMedianMAD(fusedSignal, winSec: config.madWinSec, fs: fs)
        let gate = zip(fMed, fMAD).map { (m, md) in m + config.gateK * max(md, 1e-6) }

        let fusedMax = fusedSignal.max() ?? 0
        let fusedMean = fusedSignal.reduce(0, +) / Float(fusedSignal.count)
        let fusedStd = sqrt(fusedSignal.map { pow($0 - fusedMean, 2) }.reduce(0, +) / Float(fusedSignal.count))
        let gateAvg = gate.reduce(0, +) / Float(gate.count)
        debugLog("🔗 Fusion signal - max:\(String(format: "%.6f", fusedMax)), avg:\(String(format: "%.6f", fusedMean)), std:\(String(format: "%.6f", fusedStd))")
        debugLog("🚪 Gate - avg:\(String(format: "%.6f", gateAvg)) (median + \(String(format: "%.1f", config.gateK))·MAD)")
        
        let peakCandidates = detectPeaks(fusedSignal, gate: gate, refractorySec: config.refractoryMs / 1000.0)
        
        debugLog("🏔️ Found \(peakCandidates.count) candidate peaks above gate threshold")
        
        var pinchEvents: [PinchEvent] = []
        
        // Individual peak details omitted to reduce log volume
        
        // Step 4: Template Matching
        debugLog("=== STEP 4: TEMPLATE MATCHING ===")
        debugLog("🎯 Template-based verification of candidate peaks...")
        debugLog("📏 Template window: \(String(format: "%.0f", config.windowPreMs))ms pre + \(String(format: "%.0f", config.windowPostMs))ms post = \(String(format: "%.0f", config.windowPreMs + config.windowPostMs))ms total")
        debugLog("🔍 Template confidence: \(String(format: "%.2f", config.nccThresh)) (NCC threshold)")
        
        var templateMatchCount = 0
        
        // Enforce template length from time parameters
        let preS = Int(round(config.windowPreMs * fs / 1000))
        let postS = Int(round(config.windowPostMs * fs / 1000))
        let L = preS + postS + 1
        
        // Validate template lengths
        for template in templates {
            guard template.data.count == L else {
                debugLog("⚠️ Template length \(template.data.count) != expected \(L) samples")
                continue
            }
        }
        
        func extractWindow(center idx: Int, from z: [Float]) -> [Float] {
            let s = max(0, idx - preS)
            let e = min(z.count - 1, idx + postS)
            var w = Array(z[s...e])
            if w.count < L {
                if s == 0 { 
                    w = Array(repeating: z.first!, count: L - w.count) + w 
                }
                if e == z.count - 1 { 
                    w += Array(repeating: z.last!, count: L - w.count) 
                }
            }
            return Array(w.prefix(L))
        }
        
        for candidate in peakCandidates {
            let window = extractWindow(center: candidate.index, from: fusedSignal)
            guard window.count == L else { continue }
            
            // Try templates to find the best match (with early termination optimization)
            var bestNccScore: Float = 0.0
            var bestTemplateIndex = -1
            let earlyTerminationThreshold: Float = 0.95 // Stop if we get very high confidence
            
            for (templateIndex, template) in templates.enumerated() {
                let nccScore = ncc(window: window, template: template.data)
                if nccScore > bestNccScore {
                    bestNccScore = nccScore
                    bestTemplateIndex = templateIndex
                    
                    // Early termination: if we get very high confidence, no need to test remaining templates
                    if nccScore >= earlyTerminationThreshold {
                        break
                    }
                }
            }
            
            if bestNccScore >= config.nccThresh {
                let confidence = 0.6 * bestNccScore + 0.4 * min(candidate.value / 5.0, 1.0)
                
                let event = PinchEvent(
                    tPeak: t[candidate.index],
                    tStart: t[startIdx],
                    tEnd: t[endIdx],
                    confidence: confidence,
                    gateScore: candidate.value,
                    ncc: bestNccScore
                )
                pinchEvents.append(event)
                templateMatchCount += 1
                // Peak passed template matching (details omitted for concise logging)
            } else {
                // Peak failed template matching (details omitted for concise logging)  
            }
        }
        
        // Minimal telemetry logging
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        let samplesAboveGate = zip(fusedSignal, gate).map { $0 > $1 ? 1 : 0 }.reduce(0, +)
        let pctAboveGate = Float(samplesAboveGate) * 100.0 / Float(fusedSignal.count)
        let actualFs = Float(frames.count - 1) / Float((frames.last?.t ?? 0) - (frames.first?.t ?? 0))
        
        // Collect top-5 NCC scores from successful matches
        let top5NCC = pinchEvents.map { $0.ncc }.sorted(by: >).prefix(5)
        
        debugLog("=== TELEMETRY ===")
        debugLog("📊 fs(measured): \(String(format: "%.1f", actualFs)) Hz")
        debugLog("📊 Candidates: \(peakCandidates.count) → \(pinchEvents.count) accepted")
        debugLog("📊 Top-5 NCC: \(top5NCC.map { String(format: "%.3f", $0) }.joined(separator: ", "))")
        debugLog("📊 % samples above gate: \(String(format: "%.1f", pctAboveGate))%")
        
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
    
    private func bandpass(_ x: [Float], fs: Float, low: Float, high: Float) -> [Float] {
        guard !x.isEmpty else { return x }
        
        var filter = makeBandPass(fs: fs, low: low, high: high)
        var output = [Float](repeating: 0, count: x.count)
        
        for i in 0..<x.count {
            output[i] = filter.process(x[i])
        }
        
        // Sanitize output to prevent NaN/Inf propagation
        sanitize(&output)
        
        return output
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
    
    private func baselineMAD(_ z: [Float], winSec: Float, fs: Float) -> (median: [Float], mad: [Float]) {
        let winSamples = Int(winSec * fs)
        var median = [Float](repeating: 0, count: z.count)
        var mad = [Float](repeating: 0, count: z.count)
        
        for i in 0..<z.count {
            let start = max(0, i - winSamples/2)
            let end = min(z.count, i + winSamples/2)
            
            let window = Array(z[start..<end]).sorted()
            let med = window[window.count / 2]
            
            let deviations = window.map { abs($0 - med) }.sorted()
            let madValue = deviations[deviations.count / 2]
            
            median[i] = med
            mad[i] = madValue
        }
        
        return (median, mad)
    }
    
    private func detectPeaks(_ z: [Float], gate: [Float], refractorySec: Float) -> [PeakCandidate] {
        let rN = max(1, Int(round(refractorySec * config.fs)))
        var peaks: [PeakCandidate] = []
        var i = 1
        
        while i < z.count - 1 {
            // Gate-crossing: was below gate, now above
            if z[i-1] <= gate[i-1] && z[i] > gate[i] {
                // Climb to local maximum
                var j = i
                while j + 1 < z.count && z[j+1] >= z[j] { 
                    j += 1 
                }
                
                // Ensure peak is still above local gate
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
    
    // Python-style debug processing with detailed logging  
    public func processWithDebugCallback(frames: [SensorFrame], debugCallback: @escaping (String) -> Void) -> [PinchEvent] {
        guard !frames.isEmpty else { 
            debugCallback("❌ Empty frames array")
            return [] 
        }
        
        debugCallback("🔬 TKEO DEBUG: 🔍 Starting TKEO analysis with \(frames.count) readings")
        
        // Use Python-style per-axis processing (no jerk, no magnitude-first)
        let (ax, ay, az, gx, gy, gz, fs, t) = preprocessAxes(frames: frames)
        
        // Compute raw signal magnitudes for comparison with Python
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
        
        // Band-pass per axis (no jerk) using stable RBJ filters
        let aX = bandpass(ax, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        let aY = bandpass(ay, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        let aZ = bandpass(az, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        
        let gX = bandpass(gx, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        let gY = bandpass(gy, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        let gZ = bandpass(gz, fs: fs, low: config.bandpassLow, high: config.bandpassHigh)
        
        // TKEO per axis with positive clamp (Python-style)
        let aXT = tkeo(aX), aYT = tkeo(aY), aZT = tkeo(aZ)
        let gXT = tkeo(gX), gYT = tkeo(gY), gZT = tkeo(gZ)
        
        // Fuse across axes: L2 norm of positive TKEO values (Python-style)
        var accelTkeo = fuseL2Positive([aXT, aYT, aZT])
        var gyroTkeo = fuseL2Positive([gXT, gYT, gZT])
        
        // Sanitize TKEO outputs before analysis
        sanitize(&accelTkeo)
        sanitize(&gyroTkeo)
        
        let accelTkeoMean = accelTkeo.isEmpty ? 0.0 : accelTkeo.reduce(0, +) / Float(accelTkeo.count)
        let accelTkeoMax = accelTkeo.max() ?? 0
        let accelInfCount = accelTkeo.filter { !$0.isFinite }.count
        debugCallback("🔬 TKEO DEBUG: ⚡ Accel TKEO: mean=\(String(format: "%.6f", accelTkeoMean)), max=\(String(format: "%.6f", accelTkeoMax)), inf/nan: \(accelInfCount)")
        
        let gyroTkeoMean = gyroTkeo.isEmpty ? 0.0 : gyroTkeo.reduce(0, +) / Float(gyroTkeo.count)
        let gyroTkeoMax = gyroTkeo.max() ?? 0
        let gyroInfCount = gyroTkeo.filter { !$0.isFinite }.count
        debugCallback("🔬 TKEO DEBUG: 🌪️ Gyro TKEO: mean=\(String(format: "%.6f", gyroTkeoMean)), max=\(String(format: "%.6f", gyroTkeoMax)), inf/nan: \(gyroInfCount)")
        
        // Global median statistics with high precision
        let accelSorted = accelTkeo.sorted()
        let gyroSorted = gyroTkeo.sorted()
        let accelMedianGlobal = accelSorted.isEmpty ? 0.0 : accelSorted[accelSorted.count / 2]
        let gyroMedianGlobal = gyroSorted.isEmpty ? 0.0 : gyroSorted[gyroSorted.count / 2]
        
        // Count zeros and near-zeros (GPT-5 recommendation)
        let eps: Float = 1e-6
        let accelZeros = accelTkeo.filter { $0 == 0 }.count
        let gyroZeros = gyroTkeo.filter { $0 == 0 }.count
        let accelNearZeros = accelTkeo.filter { value in abs(value) <= eps }.count
        let gyroNearZeros = gyroTkeo.filter { value in abs(value) <= eps }.count
        
        let nonZeroAccel = accelTkeo.filter { $0 != 0 }
        let meanNonZeroAccel = nonZeroAccel.isEmpty ? 0.0 : nonZeroAccel.reduce(0, +) / Float(nonZeroAccel.count)
        let nonZeroGyro = gyroTkeo.filter { $0 != 0 }
        let meanNonZeroGyro = nonZeroGyro.isEmpty ? 0.0 : nonZeroGyro.reduce(0, +) / Float(nonZeroGyro.count)
        
        debugCallback("🔬 TKEO DEBUG: 📊 Global Reference - Accel median: \(String(format: "%.6f", accelMedianGlobal)) (count: \(accelTkeo.count))")
        debugCallback("🔬 TKEO DEBUG: 📊 Global Reference - Gyro median: \(String(format: "%.6f", gyroMedianGlobal)) (count: \(gyroTkeo.count))")
        debugCallback("🔬 TKEO DEBUG: 🔍 Accel TKEO zeros: \(accelZeros), near-zeros: \(accelNearZeros), non-zero mean: \(String(format: "%.3f", meanNonZeroAccel))")
        debugCallback("🔬 TKEO DEBUG: 🔍 Gyro TKEO zeros: \(gyroZeros), near-zeros: \(gyroNearZeros), non-zero mean: \(String(format: "%.3f", meanNonZeroGyro))")
        
        // Skip the complex normalization and just do basic thresholding for now
        // This will help us verify the TKEO values are correct before worrying about detection
        debugCallback("🔬 TKEO DEBUG: ✅ Python-style TKEO processing complete")
        
        // Return empty for now since we're just debugging TKEO values
        return []
    }
}

private struct PeakCandidate {
    let index: Int
    let value: Float
}

