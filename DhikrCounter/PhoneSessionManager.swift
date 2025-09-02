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
    
    // Data storage
    private var storedSensorData: [String: [SensorReading]] = [:]
    private var storedDetectionEvents: [String: [DetectionEvent]] = [:]
    
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
            if self.debugMessages.count > 10 {
                self.debugMessages.removeLast() // Keep only last 10
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
}

extension DateFormatter {
    static let debugTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}