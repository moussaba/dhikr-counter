import Foundation
import WatchConnectivity

@MainActor
class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()
    
    @Published var transferStatus: String = "Initializing..."
    @Published var isTransferring: Bool = false
    @Published var lastTransferError: Error?
    
    private var pendingUserInfos: [[String: Any]] = []
    
    private override init() {
        super.init()
        setupWatchConnectivity()
    }
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            transferStatus = "WatchConnectivity not supported"
            print("❌ WatchConnectivity not supported on this device")
            return
        }
        
        let session = WCSession.default
        session.delegate = self
        session.activate()
        
        transferStatus = "WCSession activation requested"
        print("⌚ WCSession activation requested - Delegate set and activate() called")
        print("⌚ Current activation state: \(session.activationState.rawValue)")
        
        // Additional logging for configuration verification
        DispatchQueue.main.async {
            print("⌚ CompanionInstalled: \(session.isCompanionAppInstalled)")
        }
    }
    
    func transferSensorData(sensorData: [SensorReading], detectionEvents: [DetectionEvent], sessionId: UUID) {
        print("⌚ Transfer requested for \(sensorData.count) readings")
        
        do {
            let sensorDataEncoded = try JSONEncoder().encode(sensorData)
            let detectionEventsEncoded = try JSONEncoder().encode(detectionEvents)
            
            let sessionData: [String: Any] = [
                "type": "sessionData",
                "sessionId": sessionId.uuidString,
                "sensorDataCount": sensorData.count,
                "detectionEventCount": detectionEvents.count,
                "timestamp": Date().timeIntervalSince1970,
                "sensorData": sensorDataEncoded,
                "detectionEvents": detectionEventsEncoded
            ]
            
            let session = WCSession.default
            guard session.activationState == .activated else {
                print("⌚ Session not activated - queuing transfer")
                pendingUserInfos.append(sessionData)
                transferStatus = "Queued - waiting for activation (\(pendingUserInfos.count) pending)"
                return
            }
            
            session.transferUserInfo(sessionData)
            transferStatus = "Data transferred (\(sensorData.count) readings)"
            print("⌚ transferUserInfo called successfully")
            
        } catch {
            transferStatus = "Encoding error: \(error.localizedDescription)"
            lastTransferError = error
            print("❌ Transfer encoding error: \(error)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("⌚ WCSession activation completed!")
        print("   State: \(activationState)")
        print("   Reachable: \(session.isReachable)")
        
        DispatchQueue.main.async {
            switch activationState {
            case .activated:
                self.transferStatus = "WCSession activated successfully"
                print("✅ WCSession activated - flushing \(self.pendingUserInfos.count) queued transfers")
                
                // Flush queued transfers
                if !self.pendingUserInfos.isEmpty {
                    for userInfo in self.pendingUserInfos {
                        WCSession.default.transferUserInfo(userInfo)
                        print("⌚ Flushed queued transfer")
                    }
                    self.pendingUserInfos.removeAll()
                }
                
            case .inactive:
                self.transferStatus = "WCSession inactive"
                print("❌ WCSession inactive")
                
            case .notActivated:
                self.transferStatus = "WCSession not activated"
                print("❌ WCSession not activated")
                
            @unknown default:
                self.transferStatus = "WCSession unknown state"
                print("❓ WCSession unknown state")
            }
            
            if let error = error {
                self.lastTransferError = error
                self.transferStatus = "Activation error: \(error.localizedDescription)"
                print("❌ WCSession activation error: \(error)")
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        // Handle messages from iPhone (acknowledgments, etc.)
        print("⌚ Received message from iPhone: \(message)")
        replyHandler(["status": "received"])
    }
}