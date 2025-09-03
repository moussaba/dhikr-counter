import SwiftUI
import CoreMotion
import WatchKit
import HealthKit

class DhikrDetectionEngine: ObservableObject {
    private let motionManager = CMMotionManager()
    private let motionActivityManager = CMMotionActivityManager()
    
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
    
    // High-resolution timestamp management
    private var startEpoch: TimeInterval = 0
    
    // Background session management (HealthKit)
    private var healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    
    // WatchConnectivity integration  
    private let sessionManager = WatchSessionManager.shared
    
    init() {
        // WCSession is automatically initialized by singleton
    }
    
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
        print("🟢 Start session called - starting raw sensor data collection")
        
        // Request motion authorization first
        requestMotionPermission { [weak self] authorized in
            DispatchQueue.main.async {
                if authorized {
                    self?.startRawDataCollection()
                } else {
                    print("⚠️ Motion permission denied")
                    // Still allow session to start but log warning
                    self?.startRawDataCollection()
                }
            }
        }
    }
    
    private func requestMotionPermission(completion: @escaping (Bool) -> Void) {
        // Check if motion activity is available (this triggers permission prompt)
        if CMMotionActivityManager.isActivityAvailable() {
            let now = Date()
            let past = now.addingTimeInterval(-1) // 1 second ago
            motionActivityManager.queryActivityStarting(from: past, to: now, to: OperationQueue.main) { _, error in
                if let error = error {
                    print("Motion permission error: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("✅ Motion permission granted")
                    completion(true)
                }
            }
        } else {
            print("ℹ️ Motion activity not available, proceeding without activity permission")
            completion(true)
        }
    }
    
    private func startRawDataCollection() {
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
        
        // Start background session to prevent watchOS suspension
        startWorkoutSession()
        
        motionManager.deviceMotionUpdateInterval = 1.0 / samplingRate
        motionManager.showsDeviceMovementDisplay = true
        
        // Align epoch with Core Motion timestamp (seconds since boot)
        startEpoch = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        
        motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: OperationQueue()) { [weak self] motion, error in
            guard let self = self, let motion = motion else { 
                if let error = error {
                    print("Motion update error: \(error.localizedDescription)")
                }
                return 
            }
            self.collectRawSensorData(motion)
        }
        
        // Provide haptic feedback for session start
        WKInterfaceDevice.current().play(.start)
    }
    
    func stopSession() {
        print("Stopping sensor data collection session")
        motionManager.stopDeviceMotionUpdates()
        
        // Log some collected data before transfer
        print("⌚ Collected \(sensorDataLog.count) sensor readings")
        if sensorDataLog.count > 0 {
            let first = sensorDataLog[0]
            let last = sensorDataLog[sensorDataLog.count - 1]
            print("⌚ First reading - Accel: (\(first.userAcceleration.x), \(first.userAcceleration.y), \(first.userAcceleration.z)), Gyro: (\(first.rotationRate.x), \(first.rotationRate.y), \(first.rotationRate.z))")
            print("⌚ Last reading - Accel: (\(last.userAcceleration.x), \(last.userAcceleration.y), \(last.userAcceleration.z)), Gyro: (\(last.rotationRate.x), \(last.rotationRate.y), \(last.rotationRate.z))")
        }
        
        // Transfer session data to iPhone before stopping
        if let sessionId = currentSessionId {
            transferSessionDataToPhone(sessionId: sessionId)
        }
        
        sessionState = .inactive
        sessionStartTime = nil
        currentSessionId = nil
        
        // Stop background session
        stopWorkoutSession()
        
        // Provide haptic feedback for session stop
        WKInterfaceDevice.current().play(.stop)
    }
    
    func resetCounter() {
        pinchCount = 0
        currentMilestone = 0
        clearLogs()
        WKInterfaceDevice.current().play(.click)
    }
    
    // MARK: - Raw Sensor Data Collection
    
    private func collectRawSensorData(_ motion: CMDeviceMotion) {
        let currentTime = Date()
        
        // High-res relative time (s since boot) - as per guide requirements
        let motionTimestamp = motion.timestamp
        // Absolute epoch time in seconds (Double)
        let epochTimestamp = startEpoch + motionTimestamp
        
        // Extract all required sensor data as per guide
        let userAccel = motion.userAcceleration
        let gravity = motion.gravity          // Added gravity data
        let rotationRate = motion.rotationRate
        let attitude = motion.attitude.quaternion  // Added attitude quaternions
        
        // Create sensor reading for data logging with all required fields
        let sensorReading = SensorReading(
            timestamp: currentTime,
            motionTimestamp: motionTimestamp,     // High-resolution CMDeviceMotion timestamp
            epochTimestamp: epochTimestamp,       // Absolute epoch time
            userAcceleration: SIMD3<Double>(userAccel.x, userAccel.y, userAccel.z),
            gravity: SIMD3<Double>(gravity.x, gravity.y, gravity.z),  // Added gravity
            rotationRate: SIMD3<Double>(rotationRate.x, rotationRate.y, rotationRate.z),
            attitude: SIMD4<Double>(attitude.w, attitude.x, attitude.y, attitude.z),  // Added attitude
            activityIndex: 0.0, // No activity analysis needed
            detectionScore: nil, // No detection scores
            sessionState: SensorReading.SessionState(rawValue: sessionState.rawValue) ?? .inactive
        )
        
        // Log sensor data using the complete sensor reading
        sensorDataLog.append(sensorReading)
        
        // Maintain reasonable log size
        if sensorDataLog.count > maxLogSize {
            sensorDataLog.removeFirst()
        }
        
        // Simple state management - just go to active after setup delay
        DispatchQueue.main.async { [weak self] in
            if self?.sessionState == .setup {
                self?.sessionState = .activeDhikr
            }
        }
        
        // No pinch detection - just collect raw sensor data
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
            let medianIndex = max(0, min(sortedAccel.count / 2, sortedAccel.count - 1))
            runningAccelMedian = sortedAccel[medianIndex]
            
            let accelDeviations = accelerationBuffer.map { abs($0 - runningAccelMedian) }.sorted()
            let madIndex = max(0, min(accelDeviations.count / 2, accelDeviations.count - 1))
            runningAccelMAD = accelDeviations[madIndex]
        }
        
        // Update gyroscope statistics
        if gyroscopeBuffer.count >= minBufferSizeForStats {
            let sortedGyro = gyroscopeBuffer.sorted()
            let medianIndex = max(0, min(sortedGyro.count / 2, sortedGyro.count - 1))
            runningGyroMedian = sortedGyro[medianIndex]
            
            let gyroDeviations = gyroscopeBuffer.map { abs($0 - runningGyroMedian) }.sorted()
            let madIndex = max(0, min(gyroDeviations.count / 2, gyroDeviations.count - 1))
            runningGyroMAD = gyroDeviations[madIndex]
        }
    }
    
    private func adaptiveThresholdValue() -> Double {
        guard !scoreBuffer.isEmpty else { return 0.0 }
        
        let sortedScores = scoreBuffer.sorted()
        let percentileIndex = Int(Double(sortedScores.count) * 0.90)
        let safeIndex = max(0, min(percentileIndex, sortedScores.count - 1))
        
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
    
    private func logSensorData(accel: CMAcceleration, gyro: CMRotationRate, gravity: CMAcceleration, attitude: CMQuaternion, motionTimestamp: Double, epochTimestamp: Double, activityIndex: Double, time: Date) {
        let reading = SensorReading(
            timestamp: time,
            motionTimestamp: motionTimestamp,
            epochTimestamp: epochTimestamp,
            userAcceleration: SIMD3(accel.x, accel.y, accel.z),
            gravity: SIMD3(gravity.x, gravity.y, gravity.z),
            rotationRate: SIMD3(gyro.x, gyro.y, gyro.z),
            attitude: SIMD4(attitude.w, attitude.x, attitude.y, attitude.z),
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
        
        // Transfer sensor data and detection events
        Task { @MainActor in
            sessionManager.transferSensorData(
                sensorData: sensorDataLog,
                detectionEvents: detectionEventLog,
                sessionId: sessionId
            )
        }
        
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
    
    // Export sensor data as CSV string (compatible with guide format)
    func exportCSVData() -> String {
        guard !sensorDataLog.isEmpty else { return "" }
        
        var csvContent = SensorReading.csvHeader + "\n"
        for reading in sensorDataLog {
            csvContent += reading.csvRow() + "\n"
        }
        return csvContent
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
    
    // MARK: - Background Session Management (HealthKit)
    
    private func startWorkoutSession() {
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = .other
        cfg.locationType = .indoor
        
        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: cfg)
            workoutSession?.startActivity(with: Date())
            print("✅ Started background workout session for dhikr detection")
        } catch {
            print("⚠️ Failed to start workout session: \(error.localizedDescription)")
            // Continue without background session
        }
    }
    
    private func stopWorkoutSession() {
        workoutSession?.stopActivity(with: Date())
        workoutSession = nil
        print("🛑 Stopped background workout session")
    }
}

// MARK: - Helper Extensions

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}