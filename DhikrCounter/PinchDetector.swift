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
    
    public static func loadTrainedTemplates(config: PinchConfig? = nil) -> [PinchTemplate] {
        guard let path = Bundle.main.path(forResource: "trained_templates", ofType: "json"),
              let data = NSData(contentsOfFile: path),
              let json = try? JSONSerialization.jsonObject(with: data as Data, options: []) as? [String: Any],
              let templatesArray = json["templates"] as? [[Double]] else {
            print("⚠️ Failed to load trained_templates.json, using synthetic template")
            let cfg = config ?? PinchConfig()
            return [createDefaultTemplate(fs: cfg.fs, preMs: cfg.windowPreMs, postMs: cfg.windowPostMs)]
        }
        
        // Load templates and filter by length if config is provided
        let cfg = config ?? PinchConfig()
        let expectedL = Int(round((cfg.windowPreMs + cfg.windowPostMs) * cfg.fs / 1000)) + 1
        
        var validTemplates: [PinchTemplate] = []
        for (index, templateDoubles) in templatesArray.enumerated() {
            let templateData = templateDoubles.map { Float($0) }
            if templateData.count == expectedL {
                validTemplates.append(PinchTemplate(
                    fs: cfg.fs,
                    preMs: cfg.windowPreMs,
                    postMs: cfg.windowPostMs,
                    vectorLength: templateData.count,
                    data: templateData,
                    channelsMeta: "fused_signal_template_\(index + 1)",
                    version: "1.0"
                ))
            } else {
                print("⚠️ Template \(index + 1) length \(templateData.count) != expected \(expectedL), skipping")
            }
        }
        
        if validTemplates.isEmpty {
            print("⚠️ No valid templates found, using synthetic template")
            return [createDefaultTemplate(fs: cfg.fs, preMs: cfg.windowPreMs, postMs: cfg.windowPostMs)]
        }
        
        print("✅ Loaded \(validTemplates.count)/\(templatesArray.count) valid trained templates")
        return validTemplates
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
        
        let (accelMedian, accelMad) = baselineMAD(accelTkeo, winSec: config.madWinSec, fs: fs)
        let (gyroMedian, gyroMad) = baselineMAD(gyroTkeo, winSec: config.madWinSec, fs: fs)
        
        var accelNorm = [Float](repeating: 0, count: accelTkeo.count)
        var gyroNorm = [Float](repeating: 0, count: gyroTkeo.count)
        
        for i in 0..<accelTkeo.count {
            if accelMad[i] > 0 {
                accelNorm[i] = (accelTkeo[i] - accelMedian[i]) / accelMad[i]
            }
            if gyroMad[i] > 0 {
                gyroNorm[i] = (gyroTkeo[i] - gyroMedian[i]) / gyroMad[i]
            }
        }
        
        var fusedSignal = [Float](repeating: 0, count: accelNorm.count)
        for i in 0..<fusedSignal.count {
            fusedSignal[i] = config.accelWeight * accelNorm[i] + config.gyroWeight * gyroNorm[i]
        }
        
        let fusedMax = fusedSignal.max() ?? 0
        let fusedMean = fusedSignal.reduce(0, +) / Float(fusedSignal.count)
        let fusedStd = sqrt(fusedSignal.map { pow($0 - fusedMean, 2) }.reduce(0, +) / Float(fusedSignal.count))
        debugLog("🔗 Fusion signal - max:\(String(format: "%.6f", fusedMax)), avg:\(String(format: "%.6f", fusedMean)), std:\(String(format: "%.6f", fusedStd))")
        debugLog("🚪 Gate threshold: \(String(format: "%.6f", fusedMean + config.gateK * fusedStd)) (μ + \(String(format: "%.1f", config.gateK))σ)")
        
        let threshold = Array(repeating: config.gateK, count: fusedSignal.count)
        let peakCandidates = detectPeaks(fusedSignal, thresh: threshold, refractory: config.refractoryMs / 1000.0)
        
        debugLog("🏔️ Found \(peakCandidates.count) candidate peaks above gate threshold")
        
        var pinchEvents: [PinchEvent] = []
        
        // Individual peak details omitted to reduce log volume
        
        // Step 4: Template Matching
        debugLog("=== STEP 4: TEMPLATE MATCHING ===")
        debugLog("🎯 Template-based verification of candidate peaks...")
        debugLog("📏 Template window: \(String(format: "%.0f", config.windowPreMs))ms pre + \(String(format: "%.0f", config.windowPostMs))ms post = \(String(format: "%.0f", config.windowPreMs + config.windowPostMs))ms total")
        debugLog("🔍 Template confidence: \(String(format: "%.2f", config.nccThresh)) (NCC threshold)")
        
        var templateMatchCount = 0
        
        for candidate in peakCandidates {
            let L = templates.first?.vectorLength ?? 0
            guard L > 0 else { continue }
            
            // Preserve pre:post ratio but enforce exact L samples
            let totalMs = config.windowPreMs + config.windowPostMs
            let preRatio = totalMs > 0 ? config.windowPreMs / totalMs : 0.5
            let preSamples = Int(round(Float(L - 1) * preRatio))
            let postSamples = L - 1 - preSamples
            
            var startIdx = max(0, candidate.index - preSamples)
            var endIdx = min(fusedSignal.count - 1, candidate.index + postSamples)
            var window = Array(fusedSignal[startIdx...endIdx])
            
            // Pad or trim to exactly L samples if near boundaries
            if window.count < L {
                let deficit = L - window.count
                if startIdx == 0 {
                    let pad = [Float](repeating: fusedSignal.first ?? 0, count: deficit)
                    window = pad + window
                } else {
                    let pad = [Float](repeating: fusedSignal.last ?? 0, count: deficit)
                    window = window + pad
                }
            } else if window.count > L {
                window = Array(window[0..<L])
            }
            
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
        let nyquist = fs / 2.0
        let lowNorm = low / nyquist
        let highNorm = high / nyquist
        
        guard lowNorm > 0 && highNorm < 1.0 && lowNorm < highNorm else {
            return x
        }
        
        var output = [Float](repeating: 0, count: x.count)
        
        let b0: Float = highNorm - lowNorm
        let b1: Float = -2.0 * cos(.pi * (highNorm + lowNorm)) * b0
        let b2: Float = b0
        
        let a1: Float = -2.0 * cos(.pi * (highNorm + lowNorm))
        let a2: Float = 2.0 * cos(.pi * (highNorm - lowNorm)) - 1.0
        
        var x1: Float = 0, x2: Float = 0
        var y1: Float = 0, y2: Float = 0
        
        for i in 0..<x.count {
            let input = x[i]
            let result = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            
            x2 = x1; x1 = input
            y2 = y1; y1 = result
            
            output[i] = result
        }
        
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
    
    private func detectPeaks(_ z: [Float], thresh: [Float], refractory: Float) -> [PeakCandidate] {
        var peaks: [PeakCandidate] = []
        var lastPeakTime: Float = -refractory
        
        for i in 1..<z.count-1 {
            let currentTime = Float(i) / config.fs
            
            if z[i] > thresh[i] && z[i] > z[i-1] && z[i] > z[i+1] {
                if currentTime - lastPeakTime >= refractory {
                    peaks.append(PeakCandidate(index: i, value: z[i]))
                    lastPeakTime = currentTime
                }
            }
        }
        
        return peaks
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
        
        // Fuse across axes: L2 norm of positive TKEO values (Python-style)
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
        
        // Global median statistics with high precision
        let accelMedianGlobal = validAccelTkeo.isEmpty ? 0.0 : validAccelTkeo.sorted()[validAccelTkeo.count / 2]
        let gyroMedianGlobal = validGyroTkeo.isEmpty ? 0.0 : validGyroTkeo.sorted()[validGyroTkeo.count / 2]
        
        // Count zeros and near-zeros (GPT-5 recommendation)
        let eps: Float = 1e-6
        let accelZeros = validAccelTkeo.filter { $0 == 0 }.count
        let gyroZeros = validGyroTkeo.filter { $0 == 0 }.count
        let accelNearZeros = validAccelTkeo.filter { value in abs(value) <= eps }.count
        let gyroNearZeros = validGyroTkeo.filter { value in abs(value) <= eps }.count
        
        let nonZeroAccel = validAccelTkeo.filter { $0 != 0 }
        let meanNonZeroAccel = nonZeroAccel.isEmpty ? 0.0 : nonZeroAccel.reduce(0, +) / Float(nonZeroAccel.count)
        let nonZeroGyro = validGyroTkeo.filter { $0 != 0 }
        let meanNonZeroGyro = nonZeroGyro.isEmpty ? 0.0 : nonZeroGyro.reduce(0, +) / Float(nonZeroGyro.count)
        
        debugCallback("🔬 TKEO DEBUG: 📊 Global Reference - Accel median: \(String(format: "%.6f", accelMedianGlobal)) (valid: \(validAccelTkeo.count)/\(accelTkeo.count))")
        debugCallback("🔬 TKEO DEBUG: 📊 Global Reference - Gyro median: \(String(format: "%.6f", gyroMedianGlobal)) (valid: \(validGyroTkeo.count)/\(gyroTkeo.count))")
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

