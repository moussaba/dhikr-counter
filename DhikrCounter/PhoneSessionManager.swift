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
    private var storedMetadata: [String: SessionMetadata] = [:]
    
    // File storage - use Documents directory (required for iOS file sharing)
    private var sessionsDirectory: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL
    }
    
    // Public accessors for UI
    func getSensorData(for sessionId: String) -> [SensorReading]? {
        // If already in memory, return it
        if let sensorData = storedSensorData[sessionId] {
            return sensorData
        }
        
        // Otherwise, load from file on-demand
        addDebugMessage("📀 Loading sensor data on-demand for session: \(sessionId.prefix(8))")
        
        let fileName = "session_\(sessionId).json"
        let fileURL = sessionsDirectory.appendingPathComponent(fileName)
        
        if loadSession(from: fileURL) != nil {
            return storedSensorData[sessionId]
        }
        
        return nil
    }
    
    func getDetectionEvents(for sessionId: String) -> [DetectionEvent]? {
        // If already in memory, return it
        if let detectionEvents = storedDetectionEvents[sessionId] {
            return detectionEvents
        }
        
        // Otherwise, load from file on-demand
        addDebugMessage("📀 Loading detection events on-demand for session: \(sessionId.prefix(8))")
        
        let fileName = "session_\(sessionId).json"
        let fileURL = sessionsDirectory.appendingPathComponent(fileName)
        
        if loadSession(from: fileURL) != nil {
            return storedDetectionEvents[sessionId]
        }
        
        return nil
    }
    
    func hasSensorData(for sessionId: String) -> Bool {
        // Check if already in memory
        if storedSensorData[sessionId] != nil {
            return true
        }
        
        // Check if file exists for this session
        let fileName = "session_\(sessionId).json"
        let fileURL = sessionsDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    // Metadata-based computed properties (fast, no data loading)
    var totalSensorReadings: Int {
        return storedMetadata.values.reduce(0) { $0 + $1.sensorDataCount }
    }
    
    var totalDetectionEvents: Int {
        return storedMetadata.values.reduce(0) { $0 + $1.detectionEventCount }
    }
    
    var estimatedTotalDataSize: Int {
        // Rough estimate: ~48 bytes per sensor reading
        return totalSensorReadings * 48
    }
    
    func getSensorDataCount(for sessionId: String) -> Int {
        return storedMetadata[sessionId]?.sensorDataCount ?? 0
    }
    
    func getDetectionEventCount(for sessionId: String) -> Int {
        return storedMetadata[sessionId]?.detectionEventCount ?? 0
    }
    
    private override init() {
        super.init()
        setupFileStorage()
        loadPersistedSessions()
        setupWatchConnectivity()
        syncExportFormatToWatch()
    }
    
    private func syncExportFormatToWatch() {
        let exportFormat = UserDefaults.standard.string(forKey: "exportFormat") ?? "JSON"
        let session = WCSession.default
        
        guard session.activationState == .activated && session.isPaired else {
            return
        }
        
        do {
            try session.updateApplicationContext(["exportFormat": exportFormat])
        } catch {
            addDebugMessage("Failed to sync export format: \(error.localizedDescription)")
        }
    }
    
    func updateExportFormat() {
        syncExportFormatToWatch()
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
    
    private func setupFileStorage() {
        // Create sessions directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
            
            // Create a readme file to make the app visible in Files app
            let readmeURL = sessionsDirectory.appendingPathComponent("DhikrSessions_README.txt")
            if !FileManager.default.fileExists(atPath: readmeURL.path) {
                let readmeContent = """
                Dhikr Counter Session Files
                
                This app directory contains session files with research-grade sensor data.
                
                Each session file includes:
                • High-resolution sensor data (100Hz accelerometer and gyroscope)  
                • Detection events and timestamps
                • Research-grade CSV/JSON format for analysis
                
                Files are named: session_[UUID].json
                
                Access: Files app → "On My iPhone" → "Dhikr Counter"
                
                Generated automatically by Dhikr Counter app.
                """
                try readmeContent.write(to: readmeURL, atomically: true, encoding: .utf8)
            }
        } catch {
            // Silent failure for directory setup
        }
    }
    
    private func loadPersistedSessions() {
        do {
            let allFiles = try FileManager.default.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)
            
            // First try to load from .meta.json files (fast)
            let metadataFiles = allFiles
                .filter { $0.pathExtension == "json" && $0.lastPathComponent.contains(".meta.") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            // Fallback to regular .json files if no metadata files exist  
            let sessionFiles = allFiles
                .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains(".meta.") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            addDebugMessage("🎯 Found \(metadataFiles.count) metadata files, \(sessionFiles.count) full session files")
            
            var loadedCount = 0
            
            // Process metadata files first (fast)
            for metadataFile in metadataFiles {
                addDebugMessage("⚡ Loading from metadata file: \(metadataFile.lastPathComponent)")
                
                if let metadata = loadSessionMetadata(from: metadataFile) {
                    let session = metadata.toDhikrSession()
                    receivedSessions.append(session)
                    storedMetadata[session.id.uuidString] = metadata
                    loadedCount += 1
                    addDebugMessage("✅ Loaded metadata: \(session.id.uuidString.prefix(8)) - \(session.totalPinches) pinches")
                }
            }
            
            // Process remaining session files without metadata files (slower fallback)
            for sessionFile in sessionFiles {
                let sessionId = sessionFile.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "session_", with: "")
                
                // Skip if we already loaded metadata for this session
                if storedMetadata.keys.contains(sessionId) {
                    continue
                }
                
                addDebugMessage("🐌 Loading from full session file (no metadata): \(sessionFile.lastPathComponent)")
                
                if let metadata = loadSessionMetadata(from: sessionFile) {
                    let session = metadata.toDhikrSession()
                    receivedSessions.append(session)
                    storedMetadata[session.id.uuidString] = metadata
                    loadedCount += 1
                    addDebugMessage("✅ Loaded metadata: \(session.id.uuidString.prefix(8)) - \(session.totalPinches) pinches")
                }
            }
            
            addDebugMessage("📊 SESSION LOADING SUMMARY:")
            addDebugMessage("   • Total files found: \(allFiles.count)")
            addDebugMessage("   • JSON files found: \(sessionFiles.count)")
            addDebugMessage("   • Sessions loaded: \(loadedCount)")
            addDebugMessage("   • Final receivedSessions count: \(receivedSessions.count)")
            
        } catch {
            addDebugMessage("💥 Failed to load persisted sessions: \(error.localizedDescription)")
        }
    }
    
    // Load only session metadata (fast startup) - tries metadata file first, fallback to full file
    private func loadSessionMetadata(from fileURL: URL) -> SessionMetadata? {
        let metadataURL = fileURL.deletingPathExtension().appendingPathExtension("meta.json")
        
        // Try to load from separate metadata file first (fast)
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            do {
                let data = try Data(contentsOf: metadataURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let metadata = try decoder.decode(SessionMetadata.self, from: data)
                addDebugMessage("⚡ Loaded metadata from separate file: \(metadataURL.lastPathComponent)")
                return metadata
            } catch {
                addDebugMessage("❌ Error loading metadata from \(metadataURL.lastPathComponent): \(error)")
                // Delete corrupted metadata file and fall back to full file
                do {
                    try FileManager.default.removeItem(at: metadataURL)
                    addDebugMessage("🗑️ Successfully deleted corrupted metadata file: \(metadataURL.lastPathComponent)")
                } catch let deleteError {
                    addDebugMessage("⚠️ Failed to delete corrupted metadata file \(metadataURL.lastPathComponent): \(deleteError)")
                }
            }
        }
        
        // Fallback: extract metadata from full session file (slow)
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            // Decode full session data but only extract metadata
            let sessionData = try decoder.decode(PersistedSessionData.self, from: data)
            let metadata = SessionMetadata(
                sessionId: sessionData.sessionId,
                startTime: sessionData.startTime,
                endTime: sessionData.endTime,
                sessionDuration: sessionData.sessionDuration,
                totalPinches: sessionData.totalPinches,
                detectedPinches: sessionData.detectedPinches,
                manualCorrections: sessionData.manualCorrections,
                notes: sessionData.notes,
                sensorDataCount: sessionData.sensorData.count,
                detectionEventCount: sessionData.detectionEvents.count
            )
            
            // Save extracted metadata to separate file for next time
            saveMetadata(metadata, to: metadataURL)
            addDebugMessage("🐌 Extracted and saved metadata from full file: \(fileURL.lastPathComponent)")
            
            return metadata
        } catch {
            addDebugMessage("❌ Error loading metadata from \(fileURL.lastPathComponent): \(error)")
            return nil
        }
    }
    
    // Save metadata to separate file for fast loading
    private func saveMetadata(_ metadata: SessionMetadata, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(metadata)
            try data.write(to: url)
        } catch {
            addDebugMessage("⚠️ Failed to save metadata file: \(error)")
        }
    }
    
    // Load full session data on-demand
    private func loadSession(from fileURL: URL) -> DhikrSession? {
        do {
            let data = try Data(contentsOf: fileURL)
            addDebugMessage("📄 File size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let sessionData = try decoder.decode(PersistedSessionData.self, from: data)
            
            addDebugMessage("🎯 Decoded session data:")
            addDebugMessage("   • ID: \(sessionData.sessionId.uuidString.prefix(8))")
            addDebugMessage("   • Sensor readings: \(sessionData.sensorData.count)")
            addDebugMessage("   • Detection events: \(sessionData.detectionEvents.count)")
            addDebugMessage("   • Duration: \(String(format: "%.1fs", sessionData.sessionDuration))")
            
            // Store sensor data and detection events in memory
            let sessionIdString = sessionData.sessionId.uuidString
            storedSensorData[sessionIdString] = sessionData.sensorData
            storedDetectionEvents[sessionIdString] = sessionData.detectionEvents
            
            addDebugMessage("💾 Stored sensor data for session \(sessionIdString.prefix(8)) in memory")
            
            // Create session object
            let session = sessionData.toDhikrSession()
            return session
            
        } catch {
            addDebugMessage("💥 Failed to load session from \(fileURL.lastPathComponent): \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                addDebugMessage("🔍 Decoding error details: \(decodingError)")
            }
            return nil
        }
    }
    
    private func saveSession(_ session: DhikrSession, sensorData: [SensorReading], detectionEvents: [DetectionEvent]) {
        addDebugMessage("💾 SAVING SESSION:")
        addDebugMessage("   • ID: \(session.id.uuidString.prefix(8))")
        addDebugMessage("   • Sensor readings: \(sensorData.count)")
        addDebugMessage("   • Detection events: \(detectionEvents.count)")
        addDebugMessage("   • Duration: \(String(format: "%.1fs", session.sessionDuration))")
        
        let sessionData = PersistedSessionData(
            sessionId: session.id,
            startTime: session.startTime,
            endTime: session.endTime ?? session.startTime,
            sessionDuration: session.sessionDuration,
            totalPinches: session.totalPinches,
            detectedPinches: session.detectedPinches,
            manualCorrections: session.manualCorrections,
            notes: nil,
            sensorData: sensorData,
            detectionEvents: detectionEvents
        )
        
        let fileName = "session_\(session.id.uuidString).json"
        let fileURL = sessionsDirectory.appendingPathComponent(fileName)
        
        addDebugMessage("📁 Saving to: \(fileURL.path)")
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sessionData)
            
            addDebugMessage("📦 Encoded data size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
            
            try data.write(to: fileURL)
            
            // Verify the file was written
            let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
            addDebugMessage("✅ Session saved successfully: \(fileName) (exists: \(fileExists))")
            
            // Store metadata for quick access
            let metadata = SessionMetadata(
                sessionId: session.id,
                startTime: session.startTime,
                endTime: session.endTime ?? session.startTime,
                sessionDuration: session.sessionDuration,
                totalPinches: session.totalPinches,
                detectedPinches: session.detectedPinches,
                manualCorrections: session.manualCorrections,
                notes: session.sessionNotes,
                sensorDataCount: sensorData.count,
                detectionEventCount: detectionEvents.count
            )
            storedMetadata[session.id.uuidString] = metadata
            
            // Save separate metadata file for fast startup
            let metadataURL = fileURL.deletingPathExtension().appendingPathExtension("meta.json")
            saveMetadata(metadata, to: metadataURL)
            addDebugMessage("📊 Metadata stored for quick access and saved to separate file")
            
        } catch {
            addDebugMessage("💥 Failed to save session: \(error.localizedDescription)")
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

extension PhoneSessionManager: @preconcurrency WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let statusMessage = "WCSession activation: \(activationState), Reachable: \(session.isReachable), Paired: \(session.isPaired), AppInstalled: \(session.isWatchAppInstalled)"
        addDebugMessage(statusMessage)
        
        DispatchQueue.main.async {
            switch activationState {
            case .activated:
                self.isWatchConnected = session.isReachable && session.isPaired
                self.lastReceiveStatus = "Watch connectivity activated - Reachable: \(session.isReachable), Paired: \(session.isPaired)"
                
                // Sync export format after activation
                self.syncExportFormatToWatch()
                
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
            self.isReceivingFile = true
            self.fileTransferProgress = "Processing received file..."
            
            guard let type = metadata["type"] as? String, type == "sessionFile" else {
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
                
                // Save session to disk
                self.saveSession(session, sensorData: sensorData, detectionEvents: detectionEvents)
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
        guard let sessionIdString = metadata["sessionId"] as? String,
              let sensorCountString = metadata["sensorDataCount"] as? String,
              let sensorCount = Int(sensorCountString),
              let fileSizeString = metadata["fileSize"] as? String,
              let fileSize = Int(fileSizeString) else {
            DispatchQueue.main.async {
                self.isReceivingFile = false
                self.lastReceiveStatus = "❌ Invalid file metadata"
            }
            return
        }
        
        let format = metadata["format"] as? String ?? "JSON"
        
        // Process file data in background
        Task {
            do {
                let sessionData = try await processSessionFile(data: fileData, format: format, sessionIdString: sessionIdString)
                
                await MainActor.run {
                    // Store the data
                    self.storedSensorData[sessionIdString] = sessionData.sensorData
                    self.storedDetectionEvents[sessionIdString] = sessionData.detectionEvents
                    
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
                    self.lastReceiveStatus = "✅ Received \(sessionData.sensorData.count) readings"
                    self.isReceivingFile = false
                    self.fileTransferProgress = ""
                    
                    // Save session to disk
                    self.saveSession(session, sensorData: sessionData.sensorData, detectionEvents: sessionData.detectionEvents)
                    
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
    
    private func processSessionFile(data: Data, format: String, sessionIdString: String) async throws -> SessionData {
        
        if format == "CSV" {
            return try parseCSVSessionData(data: data, sessionIdString: sessionIdString)
        } else {
            // Default to JSON
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SessionData.self, from: data)
        }
    }
    
    private func parseCSVSessionData(data: Data, sessionIdString: String) throws -> SessionData {
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "CSVParseError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not decode CSV data as UTF-8"])
        }
        
        let lines = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else {
            throw NSError(domain: "CSVParseError", code: 2, userInfo: [NSLocalizedDescriptionKey: "CSV file is empty or has no data rows"])
        }
        
        // Skip header line
        let dataLines = Array(lines.dropFirst())
        var sensorReadings: [SensorReading] = []
        
        for line in dataLines {
            let components = line.components(separatedBy: ",")
            guard components.count >= 15 else { continue }
            
            // Parse CSV format: time_s,epoch_s,userAccelerationX,userAccelerationY,userAccelerationZ,gravityX,gravityY,gravityZ,rotationRateX,rotationRateY,rotationRateZ,attitude_qW,attitude_qX,attitude_qY,attitude_qZ
            guard let relativeTime = Double(components[0]),
                  let epochTime = Double(components[1]),
                  let userAccelX = Double(components[2]),
                  let userAccelY = Double(components[3]),
                  let userAccelZ = Double(components[4]),
                  let gravityX = Double(components[5]),
                  let gravityY = Double(components[6]),
                  let gravityZ = Double(components[7]),
                  let rotationX = Double(components[8]),
                  let rotationY = Double(components[9]),
                  let rotationZ = Double(components[10]),
                  let attitudeW = Double(components[11]),
                  let attitudeX = Double(components[12]),
                  let attitudeY = Double(components[13]),
                  let attitudeZ = Double(components[14]) else {
                continue
            }
            
            let timestamp = Date(timeIntervalSince1970: epochTime)
            let reading = SensorReading(
                timestamp: timestamp,
                motionTimestamp: relativeTime,
                epochTimestamp: epochTime,
                userAcceleration: SIMD3<Double>(userAccelX, userAccelY, userAccelZ),
                gravity: SIMD3<Double>(gravityX, gravityY, gravityZ),
                rotationRate: SIMD3<Double>(rotationX, rotationY, rotationZ),
                attitude: SIMD4<Double>(attitudeW, attitudeX, attitudeY, attitudeZ),
                activityIndex: 0.0, // CSV doesn't include activity index
                detectionScore: nil, // CSV doesn't include detection score
                sessionState: .activeDhikr // Assume active state for CSV data
            )
            
            sensorReadings.append(reading)
        }
        
        guard let sessionId = UUID(uuidString: sessionIdString) else {
            throw NSError(domain: "CSVParseError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid session UUID"])
        }
        
        return SessionData(
            sessionId: sessionId,
            timestamp: Date().timeIntervalSince1970,
            sensorData: sensorReadings,
            detectionEvents: [] // CSV format doesn't include detection events separately
        )
    }
}

// MARK: - Data Structures

private struct SessionData: Codable {
    let sessionId: UUID
    let timestamp: TimeInterval
    let sensorData: [SensorReading]
    let detectionEvents: [DetectionEvent]
}

// Lightweight metadata for fast startup loading
private struct SessionMetadata: Codable {
    let sessionId: UUID
    let startTime: Date
    let endTime: Date
    let sessionDuration: TimeInterval
    let totalPinches: Int
    let detectedPinches: Int
    let manualCorrections: Int
    let notes: String?
    let sensorDataCount: Int
    let detectionEventCount: Int
    
    func toDhikrSession() -> DhikrSession {
        return DhikrSession.createWithId(
            id: sessionId,
            startTime: startTime,
            endTime: endTime,
            totalPinches: totalPinches,
            detectedPinches: detectedPinches,
            manualCorrections: manualCorrections,
            sessionDuration: sessionDuration,
            notes: notes
        )
    }
}

// Full session data structure (loaded on-demand)
private struct PersistedSessionData: Codable {
    let sessionId: UUID
    let startTime: Date
    let endTime: Date
    let sessionDuration: TimeInterval
    let totalPinches: Int
    let detectedPinches: Int
    let manualCorrections: Int
    let notes: String?
    let sensorData: [SensorReading]
    let detectionEvents: [DetectionEvent]
    
    func toDhikrSession() -> DhikrSession {
        return DhikrSession.createWithId(
            id: sessionId,
            startTime: startTime,
            endTime: endTime,
            totalPinches: totalPinches,
            detectedPinches: detectedPinches,
            manualCorrections: manualCorrections,
            sessionDuration: sessionDuration,
            notes: notes
        )
    }
}

extension DateFormatter {
    static let debugTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}