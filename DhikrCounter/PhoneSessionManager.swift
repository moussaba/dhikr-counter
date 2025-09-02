import Foundation
import WatchConnectivity

@MainActor
class PhoneSessionManager: NSObject, ObservableObject {
    static let shared = PhoneSessionManager()
    
    @Published var isWatchConnected: Bool = false
    @Published var receivedSessions: [DhikrSession] = []
    @Published var lastReceiveStatus: String = "Initializing..."
    @Published var lastReceiveError: Error?
    @Published var debugMessages: [String] = []
    @Published var isReceivingFile: Bool = false
    @Published var fileTransferProgress: String = ""
    
    // Data storage
    private var storedSensorData: [String: [SensorReading]] = [:]
    private var storedDetectionEvents: [String: [DetectionEvent]] = [:]
    
    // Public accessors for UI
    func getSensorData(for sessionId: String) -> [SensorReading]? {
        return storedSensorData[sessionId]
    }
    
    func getDetectionEvents(for sessionId: String) -> [DetectionEvent]? {
        return storedDetectionEvents[sessionId]
    }
    
    func hasSensorData(for sessionId: String) -> Bool {
        return storedSensorData[sessionId] != nil
    }
    
    private override init() {
        super.init()
        setupWatchConnectivity()
        addDebugMessage("PhoneSessionManager singleton initialized")
    }
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            addDebugMessage("WatchConnectivity NOT supported on this device")
            return
        }
        
        let session = WCSession.default
        session.delegate = self
        session.activate()
        
        addDebugMessage("WCSession activation requested")
        lastReceiveStatus = "WCSession activation requested"
        
        // Check app installation status after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            let session = WCSession.default
            let installStatus = "Delayed check - Paired: \(session.isPaired), WatchInstalled: \(session.isWatchAppInstalled), Reachable: \(session.isReachable)"
            self.addDebugMessage(installStatus)
        }
    }
    
    private func addDebugMessage(_ message: String) {
        let timestamp = DateFormatter.debugTimeFormatter.string(from: Date())
        let debugMessage = "\(timestamp): \(message)"
        
        DispatchQueue.main.async {
            self.debugMessages.insert(debugMessage, at: 0) // Newest first
            if self.debugMessages.count > 3 {
                self.debugMessages.removeLast() // Keep only last 3
            }
        }
        print("📱 DEBUG: \(debugMessage)")
    }
    
    func forceConnectionCheck() {
        addDebugMessage("Force connection check requested")
        
        let session = WCSession.default
        if session.activationState != .activated {
            addDebugMessage("Reactivating WCSession...")
            session.activate()
        } else {
            checkConnectionStatus()
        }
    }
    
    private func checkConnectionStatus() {
        let session = WCSession.default
        let isConnected = session.isReachable && session.isPaired
        let statusMessage = "Connection check - Reachable: \(session.isReachable), Paired: \(session.isPaired), Connected: \(isConnected)"
        addDebugMessage(statusMessage)
        
        DispatchQueue.main.async {
            self.isWatchConnected = isConnected
            if isConnected {
                self.lastReceiveStatus = "Watch connected and ready"
            } else {
                self.lastReceiveStatus = "Watch not reachable (Paired: \(session.isPaired))"
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let statusMessage = "WCSession activation: \(activationState), Reachable: \(session.isReachable), Paired: \(session.isPaired), AppInstalled: \(session.isWatchAppInstalled)"
        addDebugMessage(statusMessage)
        
        DispatchQueue.main.async {
            switch activationState {
            case .activated:
                self.isWatchConnected = session.isReachable && session.isPaired
                self.lastReceiveStatus = "Watch connectivity activated - Reachable: \(session.isReachable), Paired: \(session.isPaired)"
                
                // Force check after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.checkConnectionStatus()
                }
                
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
                self.lastReceiveError = error
                self.lastReceiveStatus = "Activation error: \(error.localizedDescription)"
                self.addDebugMessage("Activation error: \(error.localizedDescription)")
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachabilityMessage = "Reachability changed - Reachable: \(session.isReachable), Paired: \(session.isPaired), AppInstalled: \(session.isWatchAppInstalled)"
        addDebugMessage(reachabilityMessage)
        checkConnectionStatus()
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        addDebugMessage("WCSession became inactive")
        DispatchQueue.main.async {
            self.isWatchConnected = false
            self.lastReceiveStatus = "Watch session inactive"
        }
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        addDebugMessage("WCSession deactivated - reactivating to handle pairing changes")
        
        // CRITICAL: Re-activate to handle pairing ID changes
        WCSession.default.activate()
        
        DispatchQueue.main.async {
            self.isWatchConnected = false
            self.lastReceiveStatus = "Watch session deactivated - reactivating"
        }
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        let userInfoMessage = "Received userInfo with keys: \(Array(userInfo.keys))"
        addDebugMessage(userInfoMessage)
        
        guard let type = userInfo["type"] as? String else {
            addDebugMessage("No 'type' field in userInfo - invalid data format")
            return
        }
        
        addDebugMessage("UserInfo type: '\(type)'")
        
        if type == "sessionData" {
            handleUserInfoSessionData(userInfo)
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // CRITICAL: Process file immediately while it still exists
        // WatchConnectivity may clean up the file very quickly
        let fileURL = file.fileURL
        let metadata = file.metadata ?? [:]
        
        // Read file data immediately before any async operations
        guard let fileData = try? Data(contentsOf: fileURL) else {
            Task { @MainActor in
                self.addDebugMessage("❌ Could not read file immediately: \(fileURL.lastPathComponent)")
                self.addDebugMessage("📁 File path: \(fileURL.path)")
                self.addDebugMessage("📁 File exists: \(FileManager.default.fileExists(atPath: fileURL.path))")
                self.lastReceiveStatus = "❌ File read failed"
            }
            return
        }
        
        Task { @MainActor in
            self.addDebugMessage("📁 Received file: \(fileURL.lastPathComponent)")
            self.addDebugMessage("📁 File metadata: \(metadata)")
            self.addDebugMessage("📁 File size read: \(ByteCountFormatter.string(fromByteCount: Int64(fileData.count), countStyle: .file))")
            
            self.isReceivingFile = true
            self.fileTransferProgress = "Processing received file..."
            
            guard let type = metadata["type"] as? String, type == "sessionFile" else {
                self.addDebugMessage("❌ Invalid file metadata - not a session file")
                self.isReceivingFile = false
                self.lastReceiveStatus = "❌ Invalid file metadata"
                return
            }
            
            self.handleSessionFile(fileData: fileData, metadata: metadata)
        }
    }
    
    private func handleUserInfoSessionData(_ userInfo: [String: Any]) {
        addDebugMessage("Processing sessionData userInfo...")
        
        guard 
            let sessionIdString = userInfo["sessionId"] as? String,
            let sessionId = UUID(uuidString: sessionIdString),
            let sensorDataData = userInfo["sensorData"] as? Data,
            let detectionEventsData = userInfo["detectionEvents"] as? Data
        else {
            addDebugMessage("Failed to decode userInfo - missing required fields")
            return
        }
        
        addDebugMessage("SessionId: \(sessionIdString), SensorData: \(sensorDataData.count) bytes, Events: \(detectionEventsData.count) bytes")
        
        do {
            let sensorData = try JSONDecoder().decode([SensorReading].self, from: sensorDataData)
            let detectionEvents = try JSONDecoder().decode([DetectionEvent].self, from: detectionEventsData)
            
            let successMessage = "✅ Successfully decoded: \(sensorData.count) sensor readings, \(detectionEvents.count) events"
            addDebugMessage(successMessage)
            
            // Store the data
            storedSensorData[sessionIdString] = sensorData
            storedDetectionEvents[sessionIdString] = detectionEvents
            
            // Create a session for display
            let startTime = sensorData.first?.timestamp ?? Date()
            let endTime = sensorData.last?.timestamp ?? Date()
            
            let tempSession = DhikrSession(startTime: startTime)
            let session = tempSession.completed(
                at: endTime,
                totalPinches: detectionEvents.count,
                detectedPinches: detectionEvents.count,
                manualCorrections: 0,
                notes: "Raw sensor data session - \(sensorData.count) readings"
            )
            
            DispatchQueue.main.async {
                self.receivedSessions.append(session)
                self.lastReceiveStatus = "✅ Received \(sensorData.count) sensor readings"
            }
            
        } catch {
            let errorMessage = "Error decoding session data: \(error.localizedDescription)"
            addDebugMessage(errorMessage)
            DispatchQueue.main.async {
                self.lastReceiveStatus = errorMessage
            }
        }
    }
    
    private func handleSessionFile(fileData: Data, metadata: [String: Any]) {
        addDebugMessage("📁 Processing session file...")
        
        guard let sessionIdString = metadata["sessionId"] as? String,
              let sessionId = UUID(uuidString: sessionIdString),
              let sensorCountString = metadata["sensorDataCount"] as? String,
              let sensorCount = Int(sensorCountString),
              let fileSizeString = metadata["fileSize"] as? String,
              let fileSize = Int(fileSizeString) else {
            addDebugMessage("❌ Invalid file metadata format")
            DispatchQueue.main.async {
                self.isReceivingFile = false
                self.lastReceiveStatus = "❌ Invalid file metadata"
            }
            return
        }
        
        addDebugMessage("📁 File details - SessionId: \(sessionIdString), Readings: \(sensorCount), Size: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))")
        
        // Process file data in background
        Task {
            do {
                let sessionData = try await processSessionFile(data: fileData)
                
                await MainActor.run {
                    // Store the data
                    self.storedSensorData[sessionIdString] = sessionData.sensorData
                    self.storedDetectionEvents[sessionIdString] = sessionData.detectionEvents
                    
                    self.addDebugMessage("📊 Stored sensor data for session ID: \(sessionIdString)")
                    
                    // Create session for display using the original session ID
                    let startTime = sessionData.sensorData.first?.timestamp ?? Date()
                    let endTime = sessionData.sensorData.last?.timestamp ?? Date()
                    
                    // Use the private initializer by creating via the extension static method pattern
                    let session = DhikrSession.createWithId(
                        id: sessionData.sessionId,
                        startTime: startTime,
                        endTime: endTime,
                        totalPinches: sessionData.detectionEvents.count,
                        detectedPinches: sessionData.detectionEvents.count,
                        manualCorrections: 0,
                        sessionDuration: endTime.timeIntervalSince(startTime),
                        notes: "File transfer session - \(sessionData.sensorData.count) readings"
                    )
                    
                    self.receivedSessions.append(session)
                    self.lastReceiveStatus = "✅ Received file: \(sessionData.sensorData.count) readings (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)))"
                    self.isReceivingFile = false
                    self.fileTransferProgress = ""
                    
                    let successMessage = "✅ Successfully processed file: \(sessionData.sensorData.count) sensor readings, \(sessionData.detectionEvents.count) events"
                    self.addDebugMessage(successMessage)
                }
                
            } catch {
                await MainActor.run {
                    let errorMessage = "Error processing session file: \(error.localizedDescription)"
                    self.addDebugMessage(errorMessage)
                    self.lastReceiveStatus = "❌ File processing error: \(error.localizedDescription)"
                    self.isReceivingFile = false
                    self.fileTransferProgress = ""
                }
            }
        }
    }
    
    private func processSessionFile(data: Data) async throws -> SessionData {
        await MainActor.run {
            self.addDebugMessage("📁 Processing \(data.count) bytes of JSON data")
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(SessionData.self, from: data)
    }
}

// MARK: - Data Structures

private struct SessionData: Codable {
    let sessionId: UUID
    let timestamp: TimeInterval
    let sensorData: [SensorReading]
    let detectionEvents: [DetectionEvent]
}

extension DateFormatter {
    static let debugTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}