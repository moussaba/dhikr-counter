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
    
    // Buffer management constants
    private let bufferSize = 50
    private let minBufferSizeForStats = 10
    private let maxLogSize = 3000 // 30 seconds at 100Hz
    private let robustStatsMADConstant = 1.4826
    private let sessionSetupDelay = 3.0 // seconds
    private let pauseDetectionThreshold = 1.0 // activity index
    
    // Buffer management
    private var accelerationBuffer: [Double] = []
    private var gyroscopeBuffer: [Double] = []
    private var scoreBuffer: [Double] = []
    private var timeBuffer: [Date] = []
    
    // Robust statistics for adaptive thresholding
    private var runningAccelMedian: Double = 0
    private var runningGyroMedian: Double = 0
    private var runningAccelMAD: Double = 0
    private var runningGyroMAD: Double = 0
    private var lastDetectionTime: Date = Date.distantPast
    
    @Published var pinchCount: Int = 0
    @Published var sessionState: SessionState = .inactive
    @Published var currentMilestone: Int = 0
    
    // Data logging and transfer
    private var sessionStartTime: Date?
    private var sensorDataLog: [SensorReading] = []
    private var detectionEventLog: [DetectionEvent] = []
    private var currentSessionId: UUID?
    
    // WatchConnectivity integration
    @Published var dataManager = WatchDataManager()
    
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
        print("🟢 toggleSession() called - attempting to start session")
        
        if !motionManager.isDeviceMotionAvailable {
            print("⚠️ Device motion not available - likely simulator limitation")
            print("🟡 Starting session in simulator mode (motion disabled)")
            
            // For simulator: start session without motion detection
            sessionState = .setup
            sessionStartTime = Date()
            pinchCount = 0
            currentMilestone = 0
            currentSessionId = UUID()
            clearLogs()
            
            // Provide haptic feedback
            WKInterfaceDevice.current().play(.start)
            
            // Simulate transition to active state after setup delay
            DispatchQueue.main.asyncAfter(deadline: .now() + sessionSetupDelay) {
                print("🟢 Simulator: Auto-transitioning to active state")
                self.sessionState = .activeDhikr
            }
            return
        }
        
        print("🟢 Starting dhikr session with motion detection")
        sessionState = .setup
        sessionStartTime = Date()
        pinchCount = 0
        currentMilestone = 0
        currentSessionId = UUID()
        
        // Clear previous session data
        clearLogs()
        
        motionManager.deviceMotionUpdateInterval = 1.0 / samplingRate
        motionManager.showsDeviceMovementDisplay = true
        
        motionManager.startDeviceMotionUpdates(to: OperationQueue()) { [weak self] motion, error in
            guard let self = self, let motion = motion else { 
                if let error = error {
                    print("Motion update error: \(error.localizedDescription)")
                }
                return 
            }
            self.processMotionData(motion)
        }
        
        // Provide haptic feedback for session start
        WKInterfaceDevice.current().play(.start)
    }
    
    func stopSession() {
        print("Stopping dhikr session")
        motionManager.stopDeviceMotionUpdates()
        
        // Transfer session data to iPhone before stopping
        if let sessionId = currentSessionId {
            transferSessionDataToPhone(sessionId: sessionId)
        }
        
        sessionState = .inactive
        sessionStartTime = nil
        currentSessionId = nil
        
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
        
        // Dispatch UI updates to main queue
        DispatchQueue.main.async { [weak self] in
            self?.updateSessionState(activityIndex: activityIndex)
        }
        
        // Only detect pinches during active dhikr state
        if sessionState == .activeDhikr {
            detectPinch(acceleration: accelMag, gyroscope: gyroMag, time: currentTime)
        }
        
        // Log data for development
        logSensorData(accel: userAccel, gyro: rotationRate, activityIndex: activityIndex, time: currentTime)
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
        guard accelerationBuffer.count >= minBufferSizeForStats else { return 0 }
        
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
        
        // Robust z-score computation with separate statistics
        let zAccel = max(0, robustZScore(value: acceleration, median: runningAccelMedian, mad: runningAccelMAD))
        let zGyro = max(0, robustZScore(value: gyroscope, median: runningGyroMedian, mad: runningGyroMAD))
        let zAccelDeriv = max(0, robustZScore(value: accelDerivative, median: runningAccelMedian, mad: runningAccelMAD))
        let zGyroDeriv = max(0, robustZScore(value: gyroDerivative, median: runningGyroMedian, mad: runningGyroMAD))
        
        // Multi-sensor fusion score
        let score = sqrt(zAccel*zAccel + zGyro*zGyro + zAccelDeriv*zAccelDeriv + zGyroDeriv*zGyroDeriv)
        
        // Segment adaptive threshold
        scoreBuffer.append(score)
        if scoreBuffer.count > bufferSize { scoreBuffer.removeFirst() }
        
        let adaptiveThreshold = adaptiveThresholdValue()
        
        // Two-sensor gate + refractory period
        let timeSinceLastDetection = time.timeIntervalSince(lastDetectionTime)
        
        if score > adaptiveThreshold &&
           acceleration >= accelerationThreshold &&
           gyroscope >= gyroscopeThreshold &&
           timeSinceLastDetection >= refractoryPeriod {
            
            DispatchQueue.main.async { [weak self] in
                self?.registerPinch(score: score, accel: acceleration, gyro: gyroscope, time: time, manual: false)
            }
        }
    }
    
    private func computeDerivative(buffer: [Double], timeBuffer: [Date]) -> Double {
        guard buffer.count >= 2, timeBuffer.count >= 2 else { return 0 }
        
        guard let lastValue = buffer.last,
              let prevValue = buffer.dropLast().last,
              let lastTime = timeBuffer.last,
              let prevTime = timeBuffer.dropLast().last else { return 0 }
        
        let timeDiff = lastTime.timeIntervalSince(prevTime)
        guard timeDiff > 0 else { return 0 }
        
        return abs((lastValue - prevValue) / timeDiff)
    }
    
    private func robustZScore(value: Double, median: Double, mad: Double) -> Double {
        guard mad > 0 else { return 0 }
        return (value - median) / (robustStatsMADConstant * mad)
    }
    
    private func updateRobustStatistics(acceleration: Double, gyroscope: Double) {
        // Update acceleration statistics
        if accelerationBuffer.count >= minBufferSizeForStats {
            let sortedAccel = accelerationBuffer.sorted()
            runningAccelMedian = sortedAccel[sortedAccel.count / 2]
            
            let accelDeviations = accelerationBuffer.map { abs($0 - runningAccelMedian) }.sorted()
            runningAccelMAD = accelDeviations[accelDeviations.count / 2]
        }
        
        // Update gyroscope statistics
        if gyroscopeBuffer.count >= minBufferSizeForStats {
            let sortedGyro = gyroscopeBuffer.sorted()
            runningGyroMedian = sortedGyro[sortedGyro.count / 2]
            
            let gyroDeviations = gyroscopeBuffer.map { abs($0 - runningGyroMedian) }.sorted()
            runningGyroMAD = gyroDeviations[gyroDeviations.count / 2]
        }
    }
    
    private func adaptiveThresholdValue() -> Double {
        guard !scoreBuffer.isEmpty else { return 0.0 }
        
        let sortedScores = scoreBuffer.sorted()
        let percentileIndex = Int(Double(sortedScores.count) * 0.90)
        let safeIndex = min(percentileIndex, sortedScores.count - 1)
        
        return sortedScores[safeIndex]
    }
    
    private func updateSessionState(activityIndex: Double) {
        let timeSinceStart = Date().timeIntervalSince(sessionStartTime ?? Date())
        
        switch sessionState {
        case .setup:
            if timeSinceStart > sessionSetupDelay && activityIndex > activityThreshold {
                sessionState = .activeDhikr
                print("Active dhikr detected - enabling pinch detection")
            }
            
        case .activeDhikr:
            if activityIndex < pauseDetectionThreshold {
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
    
    private func logSensorData(accel: CMAcceleration, gyro: CMRotationRate, activityIndex: Double, time: Date) {
        let reading = SensorReading(
            timestamp: time,
            userAcceleration: SIMD3(accel.x, accel.y, accel.z),
            rotationRate: SIMD3(gyro.x, gyro.y, gyro.z),
            activityIndex: activityIndex,
            detectionScore: scoreBuffer.last,
            sessionState: SensorReading.SessionState(rawValue: sessionState.rawValue) ?? .inactive
        )
        
        sensorDataLog.append(reading)
        
        // Maintain reasonable log size
        if sensorDataLog.count > maxLogSize {
            sensorDataLog.removeFirst()
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
    
    // MARK: - Data Transfer to iPhone
    
    private func transferSessionDataToPhone(sessionId: UUID) {
        guard !sensorDataLog.isEmpty else {
            print("No sensor data to transfer")
            return
        }
        
        // Create session metadata
        let session = createSessionSummary(sessionId: sessionId)
        
        // Transfer metadata first
        dataManager.transferSessionMetadata(session: session)
        
        // Transfer sensor data and detection events
        dataManager.transferSessionData(
            sensorData: sensorDataLog,
            detectionEvents: detectionEventLog,
            sessionId: sessionId
        )
        
        print("Initiated data transfer for session \(sessionId)")
    }
    
    private func createSessionSummary(sessionId: UUID) -> DhikrSession {
        let startTime = sessionStartTime ?? Date()
        let endTime = Date()
        
        let detectedPinches = detectionEventLog.filter { !$0.manualCorrection }.count
        let manualCorrections = detectionEventLog.filter { $0.manualCorrection }.count
        
        // Create initial session and then complete it
        let initialSession = DhikrSession(startTime: startTime, deviceInfo: DeviceInfo.current)
        return initialSession.completed(
            at: endTime,
            totalPinches: pinchCount,
            detectedPinches: detectedPinches,
            manualCorrections: manualCorrections,
            notes: "Dhikr session completed"
        )
    }
    
    func manualTransferCurrentSession() {
        guard let sessionId = currentSessionId else {
            print("No active session to transfer")
            return
        }
        
        transferSessionDataToPhone(sessionId: sessionId)
    }
    
    // Export function for companion app
    func exportSessionData() -> (sensorData: [SensorReading], detectionEvents: [DetectionEvent]) {
        return (sensorDataLog, detectionEventLog)
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