import Foundation
import WatchConnectivity

@MainActor
class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()
    
    @Published var transferStatus: String = "Initializing..."
    @Published var isTransferring: Bool = false
    @Published var lastTransferError: Error?
    
    private var pendingTransfers: [PendingTransfer] = []
    
    private struct PendingTransfer {
        let sensorData: [SensorReading]
        let detectionEvents: [DetectionEvent]
        let sessionId: UUID
    }
    
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
        print("⌚ Transfer requested for \(sensorData.count) readings via transferFile")
        
        let session = WCSession.default
        guard session.activationState == .activated else {
            print("⌚ Session not activated - queuing transfer")
            let pendingTransfer = PendingTransfer(sensorData: sensorData, detectionEvents: detectionEvents, sessionId: sessionId)
            pendingTransfers.append(pendingTransfer)
            transferStatus = "Queued - waiting for activation (\(pendingTransfers.count) pending)"
            return
        }
        
        Task {
            do {
                try await performFileTransfer(sensorData: sensorData, detectionEvents: detectionEvents, sessionId: sessionId)
            } catch {
                await MainActor.run {
                    self.transferStatus = "Transfer error: \(error.localizedDescription)"
                    self.lastTransferError = error
                }
                print("❌ Transfer error: \(error)")
            }
        }
    }
    
    private func performFileTransfer(sensorData: [SensorReading], detectionEvents: [DetectionEvent], sessionId: UUID) async throws {
        // Create session data structure
        let sessionData = SessionData(
            sessionId: sessionId,
            timestamp: Date().timeIntervalSince1970,
            sensorData: sensorData,
            detectionEvents: detectionEvents
        )
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(sessionData)
        
        // Create temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "session_\(sessionId.uuidString)_\(Int(Date().timeIntervalSince1970)).json"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try jsonData.write(to: fileURL)
        print("⌚ Created temp file: \(fileURL.path)")
        print("⌚ File size: \(ByteCountFormatter.string(fromByteCount: Int64(jsonData.count), countStyle: .file))")
        
        // Transfer file
        let metadata = [
            "type": "sessionFile",
            "sessionId": sessionId.uuidString,
            "sensorDataCount": String(sensorData.count),
            "detectionEventCount": String(detectionEvents.count),
            "timestamp": String(sessionData.timestamp),
            "fileSize": String(jsonData.count)
        ]
        
        WCSession.default.transferFile(fileURL, metadata: metadata)
        
        await MainActor.run {
            self.isTransferring = true
            self.transferStatus = "File transfer initiated (\(sensorData.count) readings, \(ByteCountFormatter.string(fromByteCount: Int64(jsonData.count), countStyle: .file)))"
        }
        
        print("⌚ transferFile called successfully with metadata: \(metadata)")
    }
}

// MARK: - WCSessionDelegate

// MARK: - Data Structures

private struct SessionData: Codable {
    let sessionId: UUID
    let timestamp: TimeInterval
    let sensorData: [SensorReading]
    let detectionEvents: [DetectionEvent]
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: @preconcurrency WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("⌚ WCSession activation completed!")
        print("   State: \(activationState)")
        print("   Reachable: \(session.isReachable)")
        
        DispatchQueue.main.async {
            switch activationState {
            case .activated:
                self.transferStatus = "WCSession activated successfully"
                print("✅ WCSession activated - flushing \(self.pendingTransfers.count) queued transfers")
                
                // Flush queued transfers
                if !self.pendingTransfers.isEmpty {
                    print("⌚ Flushing \(self.pendingTransfers.count) queued file transfers")
                    for pendingTransfer in self.pendingTransfers {
                        Task {
                            do {
                                try await self.performFileTransfer(
                                    sensorData: pendingTransfer.sensorData,
                                    detectionEvents: pendingTransfer.detectionEvents,
                                    sessionId: pendingTransfer.sessionId
                                )
                                print("⌚ Flushed queued file transfer for session \(pendingTransfer.sessionId)")
                            } catch {
                                print("❌ Error flushing queued transfer: \(error)")
                            }
                        }
                    }
                    self.pendingTransfers.removeAll()
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
    
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                self.transferStatus = "File transfer failed: \(error.localizedDescription)"
                self.lastTransferError = error
                self.isTransferring = false
                print("❌ File transfer failed: \(error)")
            } else {
                self.transferStatus = "✅ File transfer completed successfully"
                self.isTransferring = false
                print("✅ File transfer completed successfully")
                
                // Clean up temporary file
                if FileManager.default.fileExists(atPath: fileTransfer.file.fileURL.path) {
                    do {
                        try FileManager.default.removeItem(at: fileTransfer.file.fileURL)
                        print("⌚ Cleaned up temporary file: \(fileTransfer.file.fileURL.path)")
                    } catch {
                        print("⚠️ Failed to clean up temporary file: \(error)")
                    }
                }
            }
        }
    }
}