import SwiftUI
import CoreMotion
import WatchKit

class DhikrDetectionEngine: ObservableObject {
    private let motionManager = CMMotionManager()
    
    // Researcher's validated parameters
    private let accelerationThreshold: Double = 0.05
    private let gyroscopeThreshold: Double = 0.18
    private let samplingRate: Double = 100.0
    private let refractoryPeriod: Double = 0.25
    private let activityThreshold: Double = 2.5
    
    // Buffer management
    private var accelerationBuffer: [Double] = []
    private var gyroscopeBuffer: [Double] = []
    private var scoreBuffer: [Double] = []
    private var timeBuffer: [Date] = []
    private let bufferSize = 50
    
    // Robust statistics for adaptive thresholding
    private var runningMedian: Double = 0
    private var runningMAD: Double = 0
    private var lastDetectionTime: Date = Date.distantPast
    
    @Published var pinchCount: Int = 0
    @Published var sessionState: SessionState = .inactive
    @Published var currentMilestone: Int = 0
    
    // Enhanced session and data logging
    private var currentSession: DhikrSession?
    private var sessionStartTime: Date?
    private var sensorDataLog: [SensorReading] = []
    private var detectionEventLog: [DetectionEvent] = []
    private let maxLogSize = 18000 // 3 minutes at 100Hz (increased from 3000)
    
    enum SessionState: String {
        case inactive
        case setup
        case activeDhikr
        case paused
        
        var displayText: String {
            switch self {
            case .inactive: return "Ready"
            case .setup: return "Starting..."
            case .activeDhikr: return "Active"
            case .paused: return "Paused"
            }
        }
    }
    
    func startSession() {
        guard motionManager.isDeviceMotionAvailable else { 
            print("Device motion not available")
            return 
        }
        
        print("Starting dhikr session")
        sessionState = .setup
        sessionStartTime = Date()
        pinchCount = 0
        currentMilestone = 0
        
        // Create new session with enhanced metadata
        currentSession = DhikrSession(startTime: sessionStartTime!, deviceInfo: .current)
        
        // Clear previous session data
        clearLogs()
        
        motionManager.deviceMotionUpdateInterval = 1.0 / samplingRate
        motionManager.showsDeviceMovementDisplay = true
        
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            self.processMotionData(motion)
        }
        
        // Provide haptic feedback for session start
        WKInterfaceDevice.current().play(.start)
    }
    
    func stopSession() {
        print("Stopping dhikr session")
        motionManager.stopDeviceMotionUpdates()
        
        // Complete the current session with final statistics
        if let session = currentSession, let startTime = sessionStartTime {
            let endTime = Date()
            let detectedPinches = detectionEventLog.filter { !$0.manualCorrection }.count
            let manualCorrections = detectionEventLog.filter { $0.manualCorrection }.count
            
            currentSession = session.completed(
                at: endTime,
                totalPinches: pinchCount,
                detectedPinches: detectedPinches,
                manualCorrections: manualCorrections,
                notes: "Session completed successfully"
            )
        }
        
        sessionState = .inactive
        sessionStartTime = nil
        
        // Provide haptic feedback for session stop
        WKInterfaceDevice.current().play(.stop)
    }
    
    func resetCounter() {
        pinchCount = 0
        currentMilestone = 0
        clearLogs()
        WKInterfaceDevice.current().play(.click)
    }
    
    // MARK: - Core Detection Algorithm Implementation
    
    private func processMotionData(_ motion: CMDeviceMotion) {
        let currentTime = Date()
        
        // Extract sensor data
        let userAccel = motion.userAcceleration
        let rotationRate = motion.rotationRate
        
        // Compute magnitudes
        let accelMag = sqrt(userAccel.x*userAccel.x + userAccel.y*userAccel.y + userAccel.z*userAccel.z)
        let gyroMag = sqrt(rotationRate.x*rotationRate.x + rotationRate.y*rotationRate.y + rotationRate.z*rotationRate.z)
        
        // Update sliding buffers
        updateBuffers(acceleration: accelMag, gyroscope: gyroMag, time: currentTime)
        
        // Compute activity index for session state management
        let activityIndex = computeActivityIndex()
        updateSessionState(activityIndex: activityIndex)
        
        // Only detect pinches during active dhikr state
        if sessionState == .activeDhikr {
            detectPinch(acceleration: accelMag, gyroscope: gyroMag, time: currentTime)
        }
        
        // Log comprehensive sensor data for development
        logSensorData(motion: motion, activityIndex: activityIndex, time: currentTime)
    }
    
    private func updateBuffers(acceleration: Double, gyroscope: Double, time: Date) {
        accelerationBuffer.append(acceleration)
        gyroscopeBuffer.append(gyroscope)
        timeBuffer.append(time)
        
        // Maintain buffer size
        while accelerationBuffer.count > bufferSize {
            accelerationBuffer.removeFirst()
            gyroscopeBuffer.removeFirst()
            timeBuffer.removeFirst()
        }
    }
    
    private func computeActivityIndex() -> Double {
        guard accelerationBuffer.count >= 10 else { return 0 }
        
        let windowSize = min(100, accelerationBuffer.count)
        let recentAccel = Array(accelerationBuffer.suffix(windowSize))
        let recentGyro = Array(gyroscopeBuffer.suffix(windowSize))
        
        let accelVariance = variance(recentAccel)
        let gyroVariance = variance(recentGyro)
        
        return sqrt(accelVariance * 100 + gyroVariance * 10)
    }
    
    private func detectPinch(acceleration: Double, gyroscope: Double, time: Date) {
        // Compute derivatives
        let accelDerivative = computeDerivative(buffer: accelerationBuffer, timeBuffer: timeBuffer)
        let gyroDerivative = computeDerivative(buffer: gyroscopeBuffer, timeBuffer: timeBuffer)
        
        // Update robust statistics
        updateRobustStatistics(acceleration: acceleration, gyroscope: gyroscope)
        
        // Robust z-score computation
        let zAccel = max(0, robustZScore(value: acceleration, median: runningMedian, mad: runningMAD))
        let zGyro = max(0, robustZScore(value: gyroscope, median: runningMedian, mad: runningMAD))
        let zAccelDeriv = max(0, robustZScore(value: accelDerivative, median: runningMedian, mad: runningMAD))
        let zGyroDeriv = max(0, robustZScore(value: gyroDerivative, median: runningMedian, mad: runningMAD))
        
        // Multi-sensor fusion score
        let score = sqrt(zAccel*zAccel + zGyro*zGyro + zAccelDeriv*zAccelDeriv + zGyroDeriv*zGyroDeriv)
        
        // Segment adaptive threshold
        scoreBuffer.append(score)
        if scoreBuffer.count > bufferSize { scoreBuffer.removeFirst() }
        
        let adaptiveThreshold = scoreBuffer.sorted()[Int(Double(scoreBuffer.count) * 0.90)]
        
        // Two-sensor gate + refractory period
        let timeSinceLastDetection = time.timeIntervalSince(lastDetectionTime)
        
        if score > adaptiveThreshold &&
           acceleration >= accelerationThreshold &&
           gyroscope >= gyroscopeThreshold &&
           timeSinceLastDetection >= refractoryPeriod {
            
            registerPinch(score: score, accel: acceleration, gyro: gyroscope, time: time, manual: false)
        }
    }
    
    private func computeDerivative(buffer: [Double], timeBuffer: [Date]) -> Double {
        guard buffer.count >= 2, timeBuffer.count >= 2 else { return 0 }
        
        let lastValue = buffer.last!
        let prevValue = buffer[buffer.count - 2]
        let timeDiff = timeBuffer.last!.timeIntervalSince(timeBuffer[timeBuffer.count - 2])
        
        return abs((lastValue - prevValue) / timeDiff)
    }
    
    private func robustZScore(value: Double, median: Double, mad: Double) -> Double {
        guard mad > 0 else { return 0 }
        return (value - median) / (1.4826 * mad)
    }
    
    private func updateRobustStatistics(acceleration: Double, gyroscope: Double) {
        if accelerationBuffer.count >= 10 {
            let sortedAccel = accelerationBuffer.sorted()
            runningMedian = sortedAccel[sortedAccel.count / 2]
            
            let deviations = accelerationBuffer.map { abs($0 - runningMedian) }.sorted()
            runningMAD = deviations[deviations.count / 2]
        }
    }
    
    private func updateSessionState(activityIndex: Double) {
        let timeSinceStart = Date().timeIntervalSince(sessionStartTime ?? Date())
        
        switch sessionState {
        case .setup:
            if timeSinceStart > 3.0 && activityIndex > activityThreshold {
                sessionState = .activeDhikr
                print("Active dhikr detected - enabling pinch detection")
            }
            
        case .activeDhikr:
            if activityIndex < 1.0 {
                sessionState = .paused
                print("Pause detected")
            }
            
        case .paused:
            if activityIndex > activityThreshold {
                sessionState = .activeDhikr
                print("Resuming dhikr detection")
            }
            
        case .inactive:
            break
        }
    }
    
    private func registerPinch(score: Double, accel: Double, gyro: Double, time: Date, manual: Bool) {
        pinchCount += 1
        lastDetectionTime = time
        
        // Check for milestones
        let newMilestone = calculateMilestone(count: pinchCount)
        let milestoneReached = newMilestone > currentMilestone
        currentMilestone = newMilestone
        
        // Provide appropriate haptic feedback
        if milestoneReached {
            provideMilestoneHaptic(milestone: newMilestone)
        } else {
            WKInterfaceDevice.current().play(.click)
        }
        
        // Update recent sensor reading with detection info
        updateRecentReadingWithDetection(time: time, manual: manual)
        
        // Log detection event  
        logDetectionEvent(score: score, accel: accel, gyro: gyro, time: time, manual: manual)
        
        print("Pinch detected! Count: \(pinchCount), Score: \(score.rounded(toPlaces: 2)), Manual: \(manual)")
    }
    
    private func calculateMilestone(count: Int) -> Int {
        if count >= 100 { return 3 }
        else if count >= 66 { return 2 }
        else if count >= 33 { return 1 }
        else { return 0 }
    }
    
    private func provideMilestoneHaptic(milestone: Int) {
        switch milestone {
        case 1: // 33 count milestone
            WKInterfaceDevice.current().play(.notification)
        case 2: // 66 count milestone
            WKInterfaceDevice.current().play(.notification)
        case 3: // 100 count milestone - completion
            WKInterfaceDevice.current().play(.success)
        default:
            WKInterfaceDevice.current().play(.click)
        }
    }
    
    private func variance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return squaredDiffs.reduce(0, +) / Double(values.count - 1)
    }
    
    // MARK: - Manual Correction (Apple Watch Series 9 Double Tap)
    
    func manualPinchIncrement() {
        let currentTime = Date()
        registerPinch(score: 0, accel: 0, gyro: 0, time: currentTime, manual: true)
        print("Manual pinch correction applied")
    }
    
    // MARK: - Data Logging for Development
    
    private func logSensorData(motion: CMDeviceMotion, activityIndex: Double, time: Date) {
        guard let session = currentSession else { return }
        
        let reading = SensorReading(
            timestamp: time,
            userAcceleration: SIMD3(motion.userAcceleration.x, motion.userAcceleration.y, motion.userAcceleration.z),
            rotationRate: SIMD3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z),
            activityIndex: activityIndex,
            detectionScore: scoreBuffer.last,
            sessionState: SensorReading.SessionState(rawValue: sessionState.rawValue) ?? .inactive,
            sessionId: session.id,
            gravity: SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z),
            attitudeX: motion.attitude.quaternion.x,
            attitudeY: motion.attitude.quaternion.y,
            attitudeZ: motion.attitude.quaternion.z,
            attitudeW: motion.attitude.quaternion.w,
            detectedPinch: false, // Will be updated when detection occurs
            manualCorrection: false, // Will be updated for manual corrections
            deviceInfo: session.deviceInfo
        )
        
        sensorDataLog.append(reading)
        
        // Maintain reasonable log size (3 minutes at 100Hz)
        if sensorDataLog.count > maxLogSize {
            sensorDataLog.removeFirst()
        }
    }
    
    private func updateRecentReadingWithDetection(time: Date, manual: Bool) {
        // Find the most recent sensor reading close to the detection time
        if let lastIndex = sensorDataLog.lastIndex(where: { abs($0.timestamp.timeIntervalSince(time)) < 0.1 }) {
            var updatedReading = sensorDataLog[lastIndex]
            // Create new reading with updated detection info (since SensorReading is immutable)
            let newReading = SensorReading(
                timestamp: updatedReading.timestamp,
                userAcceleration: updatedReading.userAcceleration,
                rotationRate: updatedReading.rotationRate,
                activityIndex: updatedReading.activityIndex,
                detectionScore: updatedReading.detectionScore,
                sessionState: updatedReading.sessionState,
                sessionId: updatedReading.sessionId,
                gravity: updatedReading.gravity,
                attitudeX: updatedReading.attitudeX,
                attitudeY: updatedReading.attitudeY,
                attitudeZ: updatedReading.attitudeZ,
                attitudeW: updatedReading.attitudeW,
                detectedPinch: true,
                manualCorrection: manual,
                deviceInfo: updatedReading.deviceInfo
            )
            sensorDataLog[lastIndex] = newReading
        }
    }
    
    private func logDetectionEvent(score: Double, accel: Double, gyro: Double, time: Date, manual: Bool) {
        let event = DetectionEvent(
            timestamp: time,
            score: score,
            accelerationPeak: accel,
            gyroscopePeak: gyro,
            validated: true,
            manualCorrection: manual
        )
        
        detectionEventLog.append(event)
    }
    
    // Export functions for companion app
    func exportSessionData() -> (sensorData: [SensorReading], detectionEvents: [DetectionEvent]) {
        return (sensorDataLog, detectionEventLog)
    }
    
    func exportCurrentSession() -> DhikrSession? {
        return currentSession
    }
    
    func exportCompleteSessionData() -> (session: DhikrSession?, sensorData: [SensorReading], detectionEvents: [DetectionEvent]) {
        return (currentSession, sensorDataLog, detectionEventLog)
    }
    
    func clearLogs() {
        sensorDataLog.removeAll()
        detectionEventLog.removeAll()
    }
    
    // Computed properties for UI
    var progressValue: Double {
        return Double(pinchCount) / 100.0
    }
    
    var milestoneText: String {
        let remaining = max(0, nextMilestoneCount - pinchCount)
        if remaining == 0 && pinchCount >= 100 {
            return "Complete! ✨"
        } else {
            return "\(remaining) to next milestone"
        }
    }
    
    private var nextMilestoneCount: Int {
        if pinchCount < 33 { return 33 }
        else if pinchCount < 66 { return 66 }
        else if pinchCount < 100 { return 100 }
        else { return 100 }
    }
}

// MARK: - Helper Extensions

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}