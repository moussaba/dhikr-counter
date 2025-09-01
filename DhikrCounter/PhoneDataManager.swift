import Foundation
import WatchConnectivity

class PhoneDataManager: NSObject, ObservableObject {
    static let shared = PhoneDataManager()
    private let session = WCSession.default
    
    @Published var isWatchConnected: Bool = false
    @Published var receivedSessions: [DhikrSession] = []
    @Published var lastReceiveStatus: String = "Ready to receive data"
    @Published var lastReceiveError: Error?
    
    // Data reception tracking
    private var activeReceptions: [UUID: SessionReception] = [:]
    private var receivedChunks: [UUID: [Int: [SensorReading]]] = [:]
    
    // Data persistence
    private let userDefaults = UserDefaults(suiteName: "group.com.moussaba.dhikrcounter") ?? UserDefaults.standard
    private let sessionsKey = "stored_sessions"
    private let sensorDataKeyPrefix = "sensor_data_"
    private let detectionEventsKeyPrefix = "detection_events_"
    
    override init() {
        super.init()
        setupWatchConnectivity()
        loadStoredSessions()
    }
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            print("WatchConnectivity not supported on this device")
            return
        }
        
        session.delegate = self
        session.activate()
    }
    
    // MARK: - Data Reception
    
    private func handleSessionMetadata(_ data: Data, sessionId: UUID) {
        do {
            let session = try JSONDecoder().decode(DhikrSession.self, from: data)
            
            DispatchQueue.main.async {
                self.lastReceiveStatus = "Received session metadata: \(session.title)"
                
                // Update or add session
                if let index = self.receivedSessions.firstIndex(where: { $0.id == sessionId }) {
                    self.receivedSessions[index] = session
                } else {
                    self.receivedSessions.append(session)
                }
                
                self.persistSession(session)
            }
        } catch {
            handleReceiveError(error, context: "session metadata")
        }
    }
    
    private func handleSensorDataChunk(_ data: Data, sessionId: UUID, chunkIndex: Int, dataSize: Int) {
        do {
            let sensorData = try JSONDecoder().decode([SensorReading].self, from: data)
            
            // Initialize reception tracking if needed
            if activeReceptions[sessionId] == nil {
                activeReceptions[sessionId] = SessionReception(sessionId: sessionId, startTime: Date())
                receivedChunks[sessionId] = [:]
            }
            
            // Store chunk
            receivedChunks[sessionId]?[chunkIndex] = sensorData
            activeReceptions[sessionId]?.receivedChunks += 1
            activeReceptions[sessionId]?.totalSensorReadings += dataSize
            
            DispatchQueue.main.async {
                let reception = self.activeReceptions[sessionId]!
                self.lastReceiveStatus = "Received chunk \(chunkIndex + 1) (\(dataSize) readings)"
                
                // Update progress for the session
                self.updateSessionProgress(sessionId: sessionId, reception: reception)
            }
            
        } catch {
            handleReceiveError(error, context: "sensor data chunk \(chunkIndex)")
        }
    }
    
    private func handleDetectionEvents(_ data: Data, sessionId: UUID, eventCount: Int) {
        do {
            let events = try JSONDecoder().decode([DetectionEvent].self, from: data)
            
            // Store detection events
            persistDetectionEvents(events, for: sessionId)
            
            // Complete the reception
            if let reception = activeReceptions[sessionId] {
                reception.detectionEvents = events
                completeSessionReception(sessionId: sessionId, reception: reception)
            }
            
            DispatchQueue.main.async {
                self.lastReceiveStatus = "Received \(eventCount) detection events - Transfer complete!"
            }
            
        } catch {
            handleReceiveError(error, context: "detection events")
        }
    }
    
    private func completeSessionReception(sessionId: UUID, reception: SessionReception) {
        // Combine all sensor data chunks in order
        guard let chunks = receivedChunks[sessionId] else { return }
        
        let sortedChunks = chunks.sorted(by: { $0.key < $1.key })
        let allSensorData = sortedChunks.flatMap { $0.value }
        
        // Persist complete sensor data
        persistSensorData(allSensorData, for: sessionId)
        
        // Validate data integrity
        let validation = validateReceivedData(
            sensorData: allSensorData,
            detectionEvents: reception.detectionEvents,
            sessionId: sessionId
        )
        
        DispatchQueue.main.async {
            self.lastReceiveStatus = validation.isValid ? 
                "Transfer completed successfully (\(allSensorData.count) readings, \(reception.detectionEvents.count) events)" :
                "Transfer completed with validation warnings: \(validation.issues.joined(separator: ", "))"
        }
        
        // Clean up
        activeReceptions.removeValue(forKey: sessionId)
        receivedChunks.removeValue(forKey: sessionId)
    }
    
    // MARK: - Data Validation
    
    private func validateReceivedData(sensorData: [SensorReading], detectionEvents: [DetectionEvent], sessionId: UUID) -> ValidationResult {
        var issues: [String] = []
        
        // Check for data completeness
        if sensorData.isEmpty {
            issues.append("No sensor data received")
        }
        
        if detectionEvents.isEmpty {
            issues.append("No detection events received")
        }
        
        // Check temporal consistency
        let sensorTimes = sensorData.compactMap { $0.timestamp }
        let eventTimes = detectionEvents.compactMap { $0.timestamp }
        
        if !sensorTimes.isEmpty && !eventTimes.isEmpty {
            let sensorTimeRange = sensorTimes.min()!...sensorTimes.max()!
            let eventsInRange = eventTimes.filter { sensorTimeRange.contains($0) }
            
            if eventsInRange.count < eventTimes.count {
                issues.append("Some detection events outside sensor data time range")
            }
        }
        
        // Check for data gaps (basic check)
        let sortedSensorData = sensorData.sorted(by: { $0.timestamp < $1.timestamp })
        var largeGaps = 0
        
        for i in 1..<sortedSensorData.count {
            let gap = sortedSensorData[i].timestamp.timeIntervalSince(sortedSensorData[i-1].timestamp)
            if gap > 0.5 { // 500ms gap
                largeGaps += 1
            }
        }
        
        if largeGaps > 5 {
            issues.append("\(largeGaps) large data gaps detected")
        }
        
        return ValidationResult(isValid: issues.isEmpty, issues: issues)
    }
    
    // MARK: - Data Persistence
    
    private func persistSession(_ session: DhikrSession) {
        var sessions = loadStoredSessionMetadata()
        
        // Update or add
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        
        // Store
        do {
            let data = try JSONEncoder().encode(sessions)
            userDefaults.set(data, forKey: sessionsKey)
        } catch {
            print("Error persisting session: \(error)")
        }
    }
    
    private func persistSensorData(_ data: [SensorReading], for sessionId: UUID) {
        do {
            let encodedData = try JSONEncoder().encode(data)
            userDefaults.set(encodedData, forKey: sensorDataKeyPrefix + sessionId.uuidString)
        } catch {
            print("Error persisting sensor data: \(error)")
        }
    }
    
    private func persistDetectionEvents(_ events: [DetectionEvent], for sessionId: UUID) {
        do {
            let encodedData = try JSONEncoder().encode(events)
            userDefaults.set(encodedData, forKey: detectionEventsKeyPrefix + sessionId.uuidString)
        } catch {
            print("Error persisting detection events: \(error)")
        }
    }
    
    // MARK: - Data Retrieval
    
    private func loadStoredSessions() {
        let sessions = loadStoredSessionMetadata()
        DispatchQueue.main.async {
            self.receivedSessions = sessions
        }
    }
    
    private func loadStoredSessionMetadata() -> [DhikrSession] {
        guard let data = userDefaults.data(forKey: sessionsKey) else { return [] }
        
        do {
            return try JSONDecoder().decode([DhikrSession].self, from: data)
        } catch {
            print("Error loading sessions: \(error)")
            return []
        }
    }
    
    func loadSensorData(for sessionId: UUID) -> [SensorReading] {
        guard let data = userDefaults.data(forKey: sensorDataKeyPrefix + sessionId.uuidString) else { return [] }
        
        do {
            return try JSONDecoder().decode([SensorReading].self, from: data)
        } catch {
            print("Error loading sensor data: \(error)")
            return []
        }
    }
    
    func loadDetectionEvents(for sessionId: UUID) -> [DetectionEvent] {
        guard let data = userDefaults.data(forKey: detectionEventsKeyPrefix + sessionId.uuidString) else { return [] }
        
        do {
            return try JSONDecoder().decode([DetectionEvent].self, from: data)
        } catch {
            print("Error loading detection events: \(error)")
            return []
        }
    }
    
    // MARK: - Export Functionality
    
    func exportSessionDataAsCSV(sessionId: UUID) -> URL? {
        let sensorData = loadSensorData(for: sessionId)
        let detectionEvents = loadDetectionEvents(for: sessionId)
        
        guard !sensorData.isEmpty else { return nil }
        
        // Create CSV content
        var csvContent = "timestamp,userAccelX,userAccelY,userAccelZ,rotationX,rotationY,rotationZ,activityIndex,detectionScore,sessionState,detectedPinch\n"
        
        for reading in sensorData {
            let line = "\(reading.timestamp.timeIntervalSince1970)," +
                      "\(reading.userAcceleration.x)," +
                      "\(reading.userAcceleration.y)," +
                      "\(reading.userAcceleration.z)," +
                      "\(reading.rotationRate.x)," +
                      "\(reading.rotationRate.y)," +
                      "\(reading.rotationRate.z)," +
                      "\(reading.activityIndex)," +
                      "\(reading.detectionScore ?? 0.0)," +
                      "\(reading.sessionState.rawValue)," +
                      "false\n" // Will be updated with detection events
            csvContent += line
        }
        
        // Write to temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("session_\(sessionId.uuidString).csv")
        
        do {
            try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Error writing CSV: \(error)")
            return nil
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateSessionProgress(sessionId: UUID, reception: SessionReception) {
        // This would be connected to UI progress indicators
        let progressInfo = "Session \(sessionId): \(reception.receivedChunks) chunks, \(reception.totalSensorReadings) readings"
        print(progressInfo)
    }
    
    private func handleReceiveError(_ error: Error, context: String) {
        DispatchQueue.main.async {
            self.lastReceiveError = error
            self.lastReceiveStatus = "Error receiving \(context): \(error.localizedDescription)"
        }
        print("Reception error (\(context)): \(error)")
    }
}

// MARK: - WCSessionDelegate

extension PhoneDataManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            switch activationState {
            case .activated:
                self.isWatchConnected = session.isReachable
                self.lastReceiveStatus = "Watch connectivity activated"
            case .inactive:
                self.isWatchConnected = false
                self.lastReceiveStatus = "Watch connectivity inactive"
            case .notActivated:
                self.isWatchConnected = false
                self.lastReceiveStatus = "Watch connectivity not activated"
            @unknown default:
                self.isWatchConnected = false
                self.lastReceiveStatus = "Watch connectivity unknown state"
            }
            
            if let error = error {
                self.handleReceiveError(error, context: "activation")
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = session.isReachable
            self.lastReceiveStatus = session.isReachable ? "Watch connected" : "Watch disconnected"
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        guard let type = message["type"] as? String else {
            replyHandler(["error": "Missing message type"])
            return
        }
        
        switch type {
        case "sessionMetadata":
            if let dataObj = message["data"] as? Data,
               let sessionIdString = message["sessionId"] as? String,
               let sessionId = UUID(uuidString: sessionIdString) {
                handleSessionMetadata(dataObj, sessionId: sessionId)
                replyHandler(["status": "metadata_received"])
            } else {
                replyHandler(["error": "Invalid session metadata format"])
            }
            
        case "sensorDataChunk":
            if let dataObj = message["data"] as? Data,
               let sessionIdString = message["sessionId"] as? String,
               let sessionId = UUID(uuidString: sessionIdString),
               let chunkIndex = message["chunkIndex"] as? Int,
               let dataSize = message["dataSize"] as? Int {
                handleSensorDataChunk(dataObj, sessionId: sessionId, chunkIndex: chunkIndex, dataSize: dataSize)
                replyHandler(["status": "chunk_received", "chunkIndex": chunkIndex])
            } else {
                replyHandler(["error": "Invalid sensor data chunk format"])
            }
            
        case "detectionEvents":
            if let dataObj = message["data"] as? Data,
               let sessionIdString = message["sessionId"] as? String,
               let sessionId = UUID(uuidString: sessionIdString),
               let eventCount = message["eventCount"] as? Int {
                handleDetectionEvents(dataObj, sessionId: sessionId, eventCount: eventCount)
                replyHandler(["status": "events_received"])
            } else {
                replyHandler(["error": "Invalid detection events format"])
            }
            
        default:
            replyHandler(["error": "Unknown message type"])
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = false
            self.lastReceiveStatus = "Watch session inactive"
        }
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = false
            self.lastReceiveStatus = "Watch session deactivated"
        }
    }
}

// MARK: - Supporting Types

private class SessionReception {
    let sessionId: UUID
    let startTime: Date
    var receivedChunks: Int = 0
    var totalSensorReadings: Int = 0
    var detectionEvents: [DetectionEvent] = []
    
    init(sessionId: UUID, startTime: Date) {
        self.sessionId = sessionId
        self.startTime = startTime
    }
}

private struct ValidationResult {
    let isValid: Bool
    let issues: [String]
}