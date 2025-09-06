import Foundation
import WatchConnectivity

@MainActor
class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()
    
    @Published var transferStatus: String = "Initializing..."
    @Published var isTransferring: Bool = false
    @Published var transferProgress: Double = 0.0
    @Published var lastTransferError: Error?
    
    private var pendingTransfers: [PendingTransfer] = []
    private var exportFormat: String = "JSON" // Default format
    private var currentTransfer: WCSessionFileTransfer?
    
    private struct PendingTransfer {
        let sensorData: [SensorReading]
        let detectionEvents: [DetectionEvent]
        let motionInterruptions: [MotionInterruption]
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
    
    func transferSensorData(sensorData: [SensorReading], detectionEvents: [DetectionEvent], motionInterruptions: [MotionInterruption], sessionId: UUID) {
        
        let session = WCSession.default
        guard session.activationState == .activated else {
            let pendingTransfer = PendingTransfer(sensorData: sensorData, detectionEvents: detectionEvents, motionInterruptions: motionInterruptions, sessionId: sessionId)
            pendingTransfers.append(pendingTransfer)
            transferStatus = "Queued - waiting for activation (\(pendingTransfers.count) pending)"
            return
        }
        
        Task {
            do {
                try await performFileTransfer(sensorData: sensorData, detectionEvents: detectionEvents, motionInterruptions: motionInterruptions, sessionId: sessionId)
            } catch {
                await MainActor.run {
                    self.transferStatus = "Transfer error: \(error.localizedDescription)"
                    self.lastTransferError = error
                }
            }
        }
    }
    
    private func performFileTransfer(sensorData: [SensorReading], detectionEvents: [DetectionEvent], motionInterruptions: [MotionInterruption], sessionId: UUID) async throws {
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
            fileData = try createCSVData(sensorData: sensorData, detectionEvents: detectionEvents, motionInterruptions: motionInterruptions, sessionId: sessionId)
            metadata = [
                "type": "sessionFile",
                "format": "CSV",
                "sessionId": sessionId.uuidString,
                "sensorDataCount": String(sensorData.count),
                "detectionEventCount": String(detectionEvents.count),
                "motionInterruptionCount": String(motionInterruptions.count),
                "timestamp": String(Date().timeIntervalSince1970),
                "fileSize": String(fileData.count)
            ]
        } else {
            // Create JSON format (default)
            let sessionData = SessionData(
                sessionId: sessionId,
                timestamp: Date().timeIntervalSince1970,
                sensorData: sensorData,
                detectionEvents: detectionEvents,
                motionInterruptions: motionInterruptions
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
        
        let transfer = WCSession.default.transferFile(fileURL, metadata: metadata)
        
        await MainActor.run {
            self.currentTransfer = transfer
            self.isTransferring = true
            self.transferProgress = 0.0
            self.transferStatus = "File transfer initiated (\(sensorData.count) readings, \(ByteCountFormatter.string(fromByteCount: Int64(fileData.count), countStyle: .file)))"
        }
        
        // Start monitoring transfer progress
        startProgressMonitoring()
    }
    
    private func startProgressMonitoring() {
        Task {
            while isTransferring, let transfer = currentTransfer {
                await MainActor.run {
                    // WCSessionFileTransfer doesn't provide built-in progress tracking
                    // We'll simulate progress based on transfer state and time elapsed
                    if transfer.isTransferring {
                        // Simulate progress based on time (watchOS transfers are usually quick)
                        self.transferProgress = min(0.9, self.transferProgress + 0.1)
                        self.transferStatus = "Transferring to iPhone... (\(Int(self.transferProgress * 100))%)"
                    }
                }
                
                // Check every 200ms for smooth progress updates
                try? await Task.sleep(for: .milliseconds(200))
            }
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
    
    private func createCSVData(sensorData: [SensorReading], detectionEvents: [DetectionEvent], motionInterruptions: [MotionInterruption], sessionId: UUID) throws -> Data {
        var csvContent = "time_s,epoch_s,userAccelerationX,userAccelerationY,userAccelerationZ,gravityX,gravityY,gravityZ,rotationRateX,rotationRateY,rotationRateZ,attitude_qW,attitude_qX,attitude_qY,attitude_qZ\n"
        
        let startTime = sensorData.first?.motionTimestamp ?? 0.0
        var invalidValueCount = 0
        
        // Merge sensor data and motion interruptions by timestamp for chronological order
        var allEvents: [(timestamp: Double, content: String)] = []
        
        // Add sensor readings
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
            
            let row = values.joined(separator: ",")
            allEvents.append((timestamp: reading.motionTimestamp, content: row))
        }
        
        // Add motion interruptions as CSV comments
        for interruption in motionInterruptions {
            allEvents.append((timestamp: interruption.motionTimestamp, content: interruption.csvRow()))
        }
        
        // Sort by timestamp and build final CSV
        allEvents.sort { $0.timestamp < $1.timestamp }
        for event in allEvents {
            csvContent += event.content + "\n"
        }
        
        // Log data quality information
        if invalidValueCount > 0 {
            print("⚠️ CSV export quality warning: \(invalidValueCount) invalid values (NaN/Inf) found and preserved")
        }
        if motionInterruptions.count > 0 {
            print("📝 CSV includes \(motionInterruptions.count) motion interruption events")
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
    let motionInterruptions: [MotionInterruption]
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
                                    motionInterruptions: pendingTransfer.motionInterruptions,
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
                self.transferProgress = 0.0
                self.currentTransfer = nil
            } else {
                self.transferStatus = "✅ File transfer completed successfully"
                self.transferProgress = 1.0
                self.isTransferring = false
                self.currentTransfer = nil
                
                // Clean up temporary file safely
                let tempFileURL = fileTransfer.file.fileURL
                DispatchQueue.global(qos: .background).async {
                    try? FileManager.default.removeItem(at: tempFileURL)
                }
            }
        }
    }
}