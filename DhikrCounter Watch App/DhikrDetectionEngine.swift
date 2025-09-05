import SwiftUI
import CoreMotion
import WatchKit
import HealthKit

class DhikrDetectionEngine: NSObject, ObservableObject {
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
    private let maxLogSize = 12000 // 2 minutes at 100Hz (was 3000/30s)
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
    
    // Data logging and transfer (with synchronization)
    private var sessionStartTime: Date?
    private var sensorDataLog: [SensorReading] = []
    private var detectionEventLog: [DetectionEvent] = []
    private var currentSessionId: UUID?
    private let dataLogQueue = DispatchQueue(label: "com.dhikrcounter.datalog", qos: .userInitiated)
    
    // High-resolution timestamp management
    private var startEpoch: TimeInterval = 0
    
    // Session monitoring
    private var lastDataTimestamp: Date = Date()
    private var sessionTimeoutTimer: Timer?
    private let sessionTimeoutInterval: TimeInterval = 3.0 // Alert if no data for 3 seconds
    
    // Background session management (HealthKit)
    private var healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var extendedRuntimeSession: WKExtendedRuntimeSession?
    
    // WatchConnectivity integration  
    private let sessionManager = WatchSessionManager.shared
    
    override init() {
        super.init()
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
        
        print("🟢 Starting sensor data collection at \(samplingRate) Hz")
        
        sessionState = .setup
        sessionStartTime = Date()
        pinchCount = 0
        currentMilestone = 0
        currentSessionId = UUID()
        
        // Clear previous session data
        clearLogs()
        
        // Start background session to prevent watchOS suspension
        startWorkoutSession()
        startExtendedRuntimeSession()
        
        // Start session monitoring
        startSessionMonitoring()
        
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
        print("🛑 Stopping sensor data collection session")
        
        // Stop motion updates first
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        
        // Log data summary before transfer
        print("📊 Collection Summary:")
        print("   📦 Total sensor readings: \(sensorDataLog.count)")
        if sensorDataLog.count > 0 {
            let first = sensorDataLog[0]
            let last = sensorDataLog[sensorDataLog.count - 1]
            let duration = last.motionTimestamp - first.motionTimestamp
            print("   ⏱️ Session duration: \(String(format: "%.2f", duration)) seconds")
            print("   📈 Average sampling rate: \(String(format: "%.1f", Double(sensorDataLog.count) / duration)) Hz")
        }
        
        // Transfer enhanced sensor data to iPhone
        if let sessionId = currentSessionId {
            print("🚚 Starting data transfer...")
            transferSessionDataToPhone(sessionId: sessionId) { [weak self] success in
                if success {
                    print("✅ Transfer completed successfully - clearing sensor data from memory")
                    self?.clearLogs()
                } else {
                    print("❌ Transfer failed - keeping sensor data for retry")
                }
            }
        }
        
        sessionState = .inactive
        sessionStartTime = nil
        currentSessionId = nil
        
        // Stop background session
        stopWorkoutSession()
        stopExtendedRuntimeSession()
        
        // Stop session monitoring
        stopSessionMonitoring()
        
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
        
        // Update last data timestamp for monitoring
        lastDataTimestamp = currentTime
        
        // High-res relative time (s since boot) - as per guide requirements
        let motionTimestamp = motion.timestamp
        // Absolute epoch time in seconds (Double)
        let epochTimestamp = startEpoch + motionTimestamp
        
        // Extract all required sensor data as per guide
        let userAccel = motion.userAcceleration
        let gravity = motion.gravity          // Added gravity data
        let rotationRate = motion.rotationRate
        let attitude = motion.attitude.quaternion  // Added attitude quaternions
        
        // Debug output every 500 samples (5 seconds at 100Hz) 
        if sensorDataLog.count % 500 == 0 {
            print("📊 Collected \(sensorDataLog.count + 1) samples")
        }
        
        // Create sensor reading for data logging with all required fields (local copies to avoid memory issues)
        let userAccelX = userAccel.x
        let userAccelY = userAccel.y
        let userAccelZ = userAccel.z
        let gravityX = gravity.x
        let gravityY = gravity.y
        let gravityZ = gravity.z
        let rotationX = rotationRate.x
        let rotationY = rotationRate.y
        let rotationZ = rotationRate.z
        let attitudeW = attitude.w
        let attitudeX = attitude.x
        let attitudeY = attitude.y
        let attitudeZ = attitude.z
        
        let sensorReading = SensorReading(
            timestamp: currentTime,
            motionTimestamp: motionTimestamp,
            epochTimestamp: epochTimestamp,
            userAcceleration: SIMD3<Double>(userAccelX, userAccelY, userAccelZ),
            gravity: SIMD3<Double>(gravityX, gravityY, gravityZ),
            rotationRate: SIMD3<Double>(rotationX, rotationY, rotationZ),
            attitude: SIMD4<Double>(attitudeW, attitudeX, attitudeY, attitudeZ),
            activityIndex: 0.0,
            detectionScore: nil,
            sessionState: SensorReading.SessionState(rawValue: sessionState.rawValue) ?? .inactive
        )
        
        // Log sensor data using synchronized queue to prevent memory corruption
        dataLogQueue.async { [weak self] in
            guard let self = self else { return }
            self.sensorDataLog.append(sensorReading)
            
            // Maintain reasonable log size (remove in chunks to avoid frequent reallocations)
            if self.sensorDataLog.count > self.maxLogSize {
                let excessCount = self.sensorDataLog.count - self.maxLogSize + 200
                self.sensorDataLog.removeFirst(excessCount)
            }
        }
        
        // Simple state management - just go to active after setup delay
        DispatchQueue.main.async { [weak self] in
            if self?.sessionState == .setup {
                self?.sessionState = .activeDhikr
                print("🟢 Session active - collecting sensor data")
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
    
    private func transferSessionDataToPhone(sessionId: UUID, completion: @escaping (Bool) -> Void) {
        dataLogQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.sensorDataLog.isEmpty else {
                print("No sensor data to transfer")
                completion(false)
                return
            }
            
            // Create safe copies of data on background queue
            let sensorDataCopy = Array(self.sensorDataLog)
            let detectionEventsCopy = Array(self.detectionEventLog)
            
            DispatchQueue.main.async {
                Task { @MainActor in
                    self.sessionManager.transferSensorData(
                        sensorData: sensorDataCopy,
                        detectionEvents: detectionEventsCopy,
                        sessionId: sessionId
                    )
                    
                    // For now, assume transfer is successful since transferSensorData doesn't provide completion callback
                    // TODO: Enhance WatchSessionManager to provide completion callback
                    completion(true)
                }
                
                print("Initiated data transfer for session \(sessionId)")
            }
        }
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
        
        transferSessionDataToPhone(sessionId: sessionId) { success in
            print("Manual transfer \(success ? "succeeded" : "failed")")
        }
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
        sensorDataLog.removeAll(keepingCapacity: false)
        detectionEventLog.removeAll(keepingCapacity: false)
        
        // Also clear buffers to free memory
        accelerationBuffer.removeAll(keepingCapacity: false)
        gyroscopeBuffer.removeAll(keepingCapacity: false)
        scoreBuffer.removeAll(keepingCapacity: false)
        timeBuffer.removeAll(keepingCapacity: false)
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
        // Check if HealthKit is available and app has proper entitlements
        guard HKHealthStore.isHealthDataAvailable() else {
            print("⚠️ HealthKit not available on this device - continuing without background session")
            return
        }
        
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = .other
        cfg.locationType = .indoor
        
        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: cfg)
            workoutSession?.startActivity(with: Date())
            print("✅ Started background workout session")
        } catch {
            print("⚠️ Failed to start workout session: \(error.localizedDescription)")
            print("   App may be suspended by watchOS during long sessions")
            // Continue without background session
        }
    }
    
    private func stopWorkoutSession() {
        if let session = workoutSession {
            session.stopActivity(with: Date())
            workoutSession = nil
            print("🛑 Stopped background workout session")
        }
    }
    
    // MARK: - Extended Runtime Session Management
    
    private func startExtendedRuntimeSession() {
        print("🔋 Starting extended runtime session to prevent watch sleep")
        
        extendedRuntimeSession = WKExtendedRuntimeSession()
        extendedRuntimeSession?.delegate = self
        
        extendedRuntimeSession?.start(at: Date())
    }
    
    private func stopExtendedRuntimeSession() {
        if let session = extendedRuntimeSession {
            session.invalidate()
            extendedRuntimeSession = nil
            print("🛑 Stopped extended runtime session")
        }
    }
    
    // MARK: - Session Monitoring
    
    private func startSessionMonitoring() {
        print("🔍 Starting session monitoring")
        lastDataTimestamp = Date()
        
        sessionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: sessionTimeoutInterval, repeats: true) { [weak self] _ in
            self?.checkSessionTimeout()
        }
    }
    
    private func stopSessionMonitoring() {
        sessionTimeoutTimer?.invalidate()
        sessionTimeoutTimer = nil
        print("🛑 Stopped session monitoring")
    }
    
    private func checkSessionTimeout() {
        let timeSinceLastData = Date().timeIntervalSince(lastDataTimestamp)
        
        if timeSinceLastData > sessionTimeoutInterval && sessionState != .inactive {
            print("⚠️ WARNING: No sensor data received for \(String(format: "%.1f", timeSinceLastData)) seconds!")
            print("   Session may have been suspended by watchOS")
            print("   Expected data every 0.01s, last data: \(lastDataTimestamp)")
            
            // Try to restart extended runtime session if it failed
            if extendedRuntimeSession == nil {
                print("🔄 Attempting to restart extended runtime session")
                startExtendedRuntimeSession()
            }
        }
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension DhikrDetectionEngine: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("✅ Extended runtime session successfully started")
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("⚠️ Extended runtime session will expire soon - watch may sleep")
        
        // Try to restart the session if we're still collecting data
        if sessionState != .inactive {
            print("🔄 Attempting to restart extended runtime session")
            stopExtendedRuntimeSession()
            startExtendedRuntimeSession()
        }
    }
    
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        print("🛑 Extended runtime session invalidated: \(reason)")
        
        if let error = error {
            print("   Error: \(error.localizedDescription)")
        }
        
        // Clear the reference since it's now invalid
        self.extendedRuntimeSession = nil
        
        // If we're still in an active session, warn the user
        if sessionState != .inactive {
            print("⚠️ Watch may go to sleep during sensor collection!")
            
            // Log the reason for debugging
            print("   Invalidation reason: \(reason)")
            
            // TODO: Add restart logic once we know the correct enum values
            // if reason == .someReasonValue {
            //     print("🔄 Attempting to restart extended runtime session")
            //     DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            //         self.startExtendedRuntimeSession()
            //     }
            // }
        }
    }
}

// MARK: - Helper Extensions

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}