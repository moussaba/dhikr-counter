import Foundation
import WatchConnectivity

@MainActor
class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()
    
    @Published var transferStatus: String = "Initializing..."
    @Published var isTransferring: Bool = false
    @Published var lastTransferError: Error?
    
    private var pendingTransfers: [PendingTransfer] = []
    private var exportFormat: String = "JSON" // Default format
    
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
    }
    
    func transferSensorData(sensorData: [SensorReading], detectionEvents: [DetectionEvent], sessionId: UUID) {
        
        let session = WCSession.default
        guard session.activationState == .activated else {
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
            }
        }
    }
    
    private func performFileTransfer(sensorData: [SensorReading], detectionEvents: [DetectionEvent], sessionId: UUID) async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileExtension = exportFormat.lowercased()
        let fileName = "session_\(sessionId.uuidString)_\(timestamp).\(fileExtension)"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        // Ensure temp directory exists
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        
        let fileData: Data
        let metadata: [String: String]
        
        if exportFormat == "CSV" {
            // Create CSV format
            fileData = try createCSVData(sensorData: sensorData, detectionEvents: detectionEvents, sessionId: sessionId)
            metadata = [
                "type": "sessionFile",
                "format": "CSV",
                "sessionId": sessionId.uuidString,
                "sensorDataCount": String(sensorData.count),
                "detectionEventCount": String(detectionEvents.count),
                "timestamp": String(Date().timeIntervalSince1970),
                "fileSize": String(fileData.count)
            ]
        } else {
            // Create JSON format (default)
            let sessionData = SessionData(
                sessionId: sessionId,
                timestamp: Date().timeIntervalSince1970,
                sensorData: sensorData,
                detectionEvents: detectionEvents
            )
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            fileData = try encoder.encode(sessionData)
            metadata = [
                "type": "sessionFile",
                "format": "JSON",
                "sessionId": sessionId.uuidString,
                "sensorDataCount": String(sensorData.count),
                "detectionEventCount": String(detectionEvents.count),
                "timestamp": String(Date().timeIntervalSince1970),
                "fileSize": String(fileData.count)
            ]
        }
        
        try fileData.write(to: fileURL, options: .atomic)
        
        WCSession.default.transferFile(fileURL, metadata: metadata)
        
        await MainActor.run {
            self.isTransferring = true
            self.transferStatus = "File transfer initiated (\(sensorData.count) readings, \(ByteCountFormatter.string(fromByteCount: Int64(fileData.count), countStyle: .file)))"
        }
    }
    
    // Helper function to safely format CSV values, handling special cases
    private func formatCSVValue(_ value: Double) -> String {
        if value.isNaN {
            return "NaN"
        } else if value.isInfinite {
            return value > 0 ? "Inf" : "-Inf"
        } else {
            return String(format: "%.6f", value)
        }
    }
    
    private func createCSVData(sensorData: [SensorReading], detectionEvents: [DetectionEvent], sessionId: UUID) throws -> Data {
        var csvContent = "time_s,epoch_s,userAccelerationX,userAccelerationY,userAccelerationZ,gravityX,gravityY,gravityZ,rotationRateX,rotationRateY,rotationRateZ,attitude_qW,attitude_qX,attitude_qY,attitude_qZ\n"
        
        let startTime = sensorData.first?.motionTimestamp ?? 0.0
        var invalidValueCount = 0
        
        for reading in sensorData {
            let relativeTime = reading.motionTimestamp - startTime
            let epochTime = reading.epochTimestamp
            
            // Validate and format all values
            let values = [
                formatCSVValue(relativeTime),
                formatCSVValue(epochTime),
                formatCSVValue(reading.userAcceleration.x),
                formatCSVValue(reading.userAcceleration.y), 
                formatCSVValue(reading.userAcceleration.z),
                formatCSVValue(reading.gravity.x),
                formatCSVValue(reading.gravity.y),
                formatCSVValue(reading.gravity.z),
                formatCSVValue(reading.rotationRate.x),
                formatCSVValue(reading.rotationRate.y),
                formatCSVValue(reading.rotationRate.z),
                formatCSVValue(reading.attitude.w),
                formatCSVValue(reading.attitude.x),
                formatCSVValue(reading.attitude.y),
                formatCSVValue(reading.attitude.z)
            ]
            
            // Count invalid values for logging
            let invalidInThisRow = values.filter { $0.contains("NaN") || $0.contains("Inf") }.count
            if invalidInThisRow > 0 {
                invalidValueCount += invalidInThisRow
            }
            
            let row = values.joined(separator: ",") + "\n"
            csvContent += row
        }
        
        // Log data quality information
        if invalidValueCount > 0 {
            print("⚠️ CSV export quality warning: \(invalidValueCount) invalid values (NaN/Inf) found and preserved")
        }
        
        guard let data = csvContent.data(using: .utf8) else {
            throw NSError(domain: "CSVExportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode CSV data"])
        }
        
        return data
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
        
        DispatchQueue.main.async {
            switch activationState {
            case .activated:
                self.transferStatus = "WCSession activated successfully"
                
                // Flush queued transfers
                if !self.pendingTransfers.isEmpty {
                    for pendingTransfer in self.pendingTransfers {
                        Task {
                            do {
                                try await self.performFileTransfer(
                                    sensorData: pendingTransfer.sensorData,
                                    detectionEvents: pendingTransfer.detectionEvents,
                                    sessionId: pendingTransfer.sessionId
                                )
                            } catch {
                                // Silent failure for queued transfers
                            }
                        }
                    }
                    self.pendingTransfers.removeAll()
                }
                
            case .inactive:
                self.transferStatus = "WCSession inactive"
                
            case .notActivated:
                self.transferStatus = "WCSession not activated"
                
            @unknown default:
                self.transferStatus = "WCSession unknown state"
            }
            
            if let error = error {
                self.lastTransferError = error
                self.transferStatus = "Activation error: \(error.localizedDescription)"
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        replyHandler(["status": "received"])
    }
    
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            if let formatString = applicationContext["exportFormat"] as? String {
                // Validate format string and fallback to default if invalid
                let validFormats = ["JSON", "CSV"]
                if validFormats.contains(formatString) {
                    self.exportFormat = formatString
                    self.transferStatus = "Export format synced: \(formatString)"
                    print("📱 Export format updated from Phone: \(formatString)")
                } else {
                    print("⚠️ Invalid export format received: '\(formatString)', keeping current: \(self.exportFormat)")
                    self.transferStatus = "Invalid format received, keeping \(self.exportFormat)"
                }
            } else {
                print("⚠️ No valid exportFormat in application context, keeping current: \(self.exportFormat)")
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                self.transferStatus = "File transfer failed: \(error.localizedDescription)"
                self.lastTransferError = error
                self.isTransferring = false
            } else {
                self.transferStatus = "✅ File transfer completed successfully"
                self.isTransferring = false
                
                // Clean up temporary file safely
                let tempFileURL = fileTransfer.file.fileURL
                DispatchQueue.global(qos: .background).async {
                    try? FileManager.default.removeItem(at: tempFileURL)
                }
            }
        }
    }
}