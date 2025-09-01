import Foundation
import WatchConnectivity

class WatchDataManager: NSObject, ObservableObject {
    private let session = WCSession.default
    
    @Published var transferProgress: Double = 0.0
    @Published var isTransferring: Bool = false
    @Published var transferStatus: String = ""
    @Published var lastTransferError: Error?
    
    // Transfer configuration
    private let chunkSize = 500 // SensorReading objects per chunk
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0
    
    // Transfer tracking
    private var currentTransfer: TransferTask?
    private var transferQueue: [TransferTask] = []
    
    override init() {
        super.init()
        setupWatchConnectivity()
    }
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            print("WatchConnectivity not supported")
            return
        }
        
        session.delegate = self
        session.activate()
    }
    
    // MARK: - Public Transfer Methods
    
    func transferSessionData(sensorData: [SensorReading], detectionEvents: [DetectionEvent], sessionId: UUID) {
        guard session.isReachable else {
            transferStatus = "iPhone not reachable"
            return
        }
        
        let task = TransferTask(
            sessionId: sessionId,
            sensorData: sensorData,
            detectionEvents: detectionEvents,
            type: .batch
        )
        
        queueTransfer(task)
    }
    
    func transferSessionMetadata(session: DhikrSession) {
        guard self.session.isReachable else {
            transferStatus = "iPhone not reachable"
            return
        }
        
        do {
            let data = try JSONEncoder().encode(session)
            let message: [String: Any] = [
                "type": "sessionMetadata",
                "sessionId": session.id.uuidString,
                "data": data
            ]
            
            self.session.sendMessage(message, replyHandler: { _ in
                DispatchQueue.main.async {
                    self.transferStatus = "Metadata transferred successfully"
                }
            }, errorHandler: { error in
                DispatchQueue.main.async {
                    self.handleTransferError(error, for: nil)
                }
            })
        } catch {
            handleTransferError(error, for: nil)
        }
    }
    
    // MARK: - Private Transfer Implementation
    
    private func queueTransfer(_ task: TransferTask) {
        transferQueue.append(task)
        processTransferQueue()
    }
    
    private func processTransferQueue() {
        guard currentTransfer == nil, !transferQueue.isEmpty else { return }
        
        currentTransfer = transferQueue.removeFirst()
        guard let task = currentTransfer else { return }
        
        DispatchQueue.main.async {
            self.isTransferring = true
            self.transferProgress = 0.0
            self.transferStatus = "Starting transfer..."
        }
        
        executeTransfer(task)
    }
    
    private func executeTransfer(_ task: TransferTask) {
        switch task.type {
        case .batch:
            executeBatchTransfer(task)
        case .realtime:
            executeRealtimeTransfer(task)
        }
    }
    
    private func executeBatchTransfer(_ task: TransferTask) {
        let chunks = createSensorDataChunks(task.sensorData)
        let totalChunks = chunks.count
        
        transferChunksSequentially(
            chunks: chunks,
            detectionEvents: task.detectionEvents,
            sessionId: task.sessionId,
            currentChunk: 0,
            totalChunks: totalChunks,
            task: task
        )
    }
    
    private func transferChunksSequentially(
        chunks: [[SensorReading]],
        detectionEvents: [DetectionEvent],
        sessionId: UUID,
        currentChunk: Int,
        totalChunks: Int,
        task: TransferTask
    ) {
        guard currentChunk < totalChunks else {
            // All sensor data chunks sent, now send detection events
            transferDetectionEvents(detectionEvents, sessionId: sessionId, task: task)
            return
        }
        
        let chunk = chunks[currentChunk]
        let progress = Double(currentChunk) / Double(totalChunks + 1) // +1 for detection events
        
        DispatchQueue.main.async {
            self.transferProgress = progress
            self.transferStatus = "Transferring chunk \(currentChunk + 1) of \(totalChunks)"
        }
        
        transferSensorDataChunk(chunk, sessionId: sessionId, chunkIndex: currentChunk) { [weak self] success in
            guard let self = self else { return }
            
            if success {
                self.transferChunksSequentially(
                    chunks: chunks,
                    detectionEvents: detectionEvents,
                    sessionId: sessionId,
                    currentChunk: currentChunk + 1,
                    totalChunks: totalChunks,
                    task: task
                )
            } else {
                self.handleTransferFailure(task)
            }
        }
    }
    
    private func transferSensorDataChunk(_ chunk: [SensorReading], sessionId: UUID, chunkIndex: Int, completion: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(chunk)
            let message: [String: Any] = [
                "type": "sensorDataChunk",
                "sessionId": sessionId.uuidString,
                "chunkIndex": chunkIndex,
                "data": data,
                "dataSize": chunk.count
            ]
            
            session.sendMessage(message, replyHandler: { _ in
                completion(true)
            }, errorHandler: { error in
                print("Chunk transfer error: \(error)")
                completion(false)
            })
        } catch {
            print("Encoding error: \(error)")
            completion(false)
        }
    }
    
    private func transferDetectionEvents(_ events: [DetectionEvent], sessionId: UUID, task: TransferTask) {
        DispatchQueue.main.async {
            self.transferProgress = 0.9
            self.transferStatus = "Transferring detection events"
        }
        
        do {
            let data = try JSONEncoder().encode(events)
            let message: [String: Any] = [
                "type": "detectionEvents",
                "sessionId": sessionId.uuidString,
                "data": data,
                "eventCount": events.count
            ]
            
            session.sendMessage(message, replyHandler: { _ in
                self.completeTransfer(task, success: true)
            }, errorHandler: { error in
                print("Detection events transfer error: \(error)")
                self.handleTransferFailure(task)
            })
        } catch {
            print("Detection events encoding error: \(error)")
            handleTransferFailure(task)
        }
    }
    
    private func executeRealtimeTransfer(_ task: TransferTask) {
        // Implementation for real-time streaming (future enhancement)
        transferStatus = "Real-time transfer not yet implemented"
        completeTransfer(task, success: false)
    }
    
    // MARK: - Helper Methods
    
    private func createSensorDataChunks(_ data: [SensorReading]) -> [[SensorReading]] {
        var chunks: [[SensorReading]] = []
        
        for i in stride(from: 0, to: data.count, by: chunkSize) {
            let end = min(i + chunkSize, data.count)
            chunks.append(Array(data[i..<end]))
        }
        
        return chunks
    }
    
    private func completeTransfer(_ task: TransferTask, success: Bool) {
        DispatchQueue.main.async {
            self.isTransferring = false
            self.transferProgress = success ? 1.0 : 0.0
            self.transferStatus = success ? "Transfer completed successfully" : "Transfer failed"
            self.currentTransfer = nil
            
            // Process next transfer in queue
            self.processTransferQueue()
        }
    }
    
    private func handleTransferFailure(_ task: TransferTask) {
        task.retryCount += 1
        
        if task.retryCount < maxRetries {
            let delay = baseRetryDelay * pow(2.0, Double(task.retryCount - 1)) // Exponential backoff
            
            DispatchQueue.main.async {
                self.transferStatus = "Retrying in \(Int(delay)) seconds... (attempt \(task.retryCount + 1))"
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.executeTransfer(task)
            }
        } else {
            DispatchQueue.main.async {
                self.transferStatus = "Transfer failed after \(self.maxRetries) attempts"
                self.completeTransfer(task, success: false)
            }
        }
    }
    
    private func handleTransferError(_ error: Error, for task: TransferTask?) {
        DispatchQueue.main.async {
            self.lastTransferError = error
            self.transferStatus = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchDataManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            switch activationState {
            case .activated:
                self.transferStatus = "Watch connectivity activated"
            case .inactive:
                self.transferStatus = "Watch connectivity inactive"
            case .notActivated:
                self.transferStatus = "Watch connectivity not activated"
            @unknown default:
                self.transferStatus = "Watch connectivity unknown state"
            }
            
            if let error = error {
                self.handleTransferError(error, for: nil)
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        // Handle messages from iPhone (acknowledgments, etc.)
        if let type = message["type"] as? String {
            switch type {
            case "transferAck":
                replyHandler(["status": "acknowledged"])
            default:
                replyHandler(["status": "unknown_message_type"])
            }
        }
    }
}

// MARK: - Supporting Types

private class TransferTask {
    let sessionId: UUID
    let sensorData: [SensorReading]
    let detectionEvents: [DetectionEvent]
    let type: TransferType
    var retryCount: Int = 0
    
    init(sessionId: UUID, sensorData: [SensorReading], detectionEvents: [DetectionEvent], type: TransferType) {
        self.sessionId = sessionId
        self.sensorData = sensorData
        self.detectionEvents = detectionEvents
        self.type = type
    }
}

private enum TransferType {
    case batch
    case realtime
}