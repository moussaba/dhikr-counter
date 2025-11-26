import Foundation
import WatchConnectivity

/// Represents a setting that was changed in the last sync
struct ChangedSetting: Identifiable {
    let id = UUID()
    let key: String
    let displayName: String
    let oldValue: String
    let newValue: String
    let changedAt: Date
}

/// Represents a current setting value for display
struct SettingValue: Identifiable {
    let id: String
    let displayName: String
    let value: String
    let category: SettingCategory
    var wasRecentlyChanged: Bool = false

    enum SettingCategory: String, CaseIterable {
        case threshold = "Thresholds"
        case timing = "Timing"
        case validation = "Validation"
        case other = "Other"
    }
}

@MainActor
class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var transferStatus: String = "Initializing..."
    @Published var isTransferring: Bool = false
    @Published var transferProgress: Double = 0.0
    @Published var lastTransferError: Error?

    // TKEO Detection Settings (synced from iPhone)
    @Published var tkeoSettingsReceived: Bool = false
    @Published var recentlyChangedSettings: [ChangedSetting] = []
    @Published var syncFlashActive: Bool = false
    @Published var lastSyncTime: Date? = nil
    private(set) var tkeoSettings: [String: Any] = [:]
    private var previousSettings: [String: Any] = [:]

    // Thread-safe cached copies for access from non-MainActor contexts
    // These are nonisolated(unsafe) because they are protected by settingsLock
    nonisolated(unsafe) private let settingsLock = NSLock()
    nonisolated(unsafe) private var _cachedSettings: [String: Any] = [:]
    nonisolated(unsafe) private var _cachedSettingsReceived: Bool = false

    private var pendingTransfers: [PendingTransfer] = []
    private var exportFormat: String = "JSON" // Default format
    private var currentTransfer: WCSessionFileTransfer?
    
    private struct PendingTransfer {
        let sensorData: [SensorReading]
        let detectionEvents: [DetectionEvent]
        let motionInterruptions: [MotionInterruption]
        let detectorMetadata: WatchDetectorMetadata?
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
    
    func transferSensorData(sensorData: [SensorReading], detectionEvents: [DetectionEvent], motionInterruptions: [MotionInterruption], detectorMetadata: WatchDetectorMetadata?, sessionId: UUID) {

        let session = WCSession.default
        guard session.activationState == .activated else {
            let pendingTransfer = PendingTransfer(sensorData: sensorData, detectionEvents: detectionEvents, motionInterruptions: motionInterruptions, detectorMetadata: detectorMetadata, sessionId: sessionId)
            pendingTransfers.append(pendingTransfer)
            transferStatus = "Queued - waiting for activation (\(pendingTransfers.count) pending)"
            return
        }

        Task {
            do {
                try await performFileTransfer(sensorData: sensorData, detectionEvents: detectionEvents, motionInterruptions: motionInterruptions, detectorMetadata: detectorMetadata, sessionId: sessionId)
            } catch {
                await MainActor.run {
                    self.transferStatus = "Transfer error: \(error.localizedDescription)"
                    self.lastTransferError = error
                }
            }
        }
    }
    
    private func performFileTransfer(sensorData: [SensorReading], detectionEvents: [DetectionEvent], motionInterruptions: [MotionInterruption], detectorMetadata: WatchDetectorMetadata?, sessionId: UUID) async throws {
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

            // Encode detector metadata as JSON string to include in transfer metadata
            var detectorMetadataJSON: String = ""
            if let meta = detectorMetadata {
                let encoder = JSONEncoder()
                if let metaData = try? encoder.encode(meta),
                   let metaString = String(data: metaData, encoding: .utf8) {
                    detectorMetadataJSON = metaString
                    print("📦 CSV transfer: Including detector metadata JSON (\(metaString.count) chars)")
                }
            }

            metadata = [
                "type": "sessionFile",
                "format": "CSV",
                "sessionId": sessionId.uuidString,
                "sensorDataCount": String(sensorData.count),
                "detectionEventCount": String(detectionEvents.count),
                "motionInterruptionCount": String(motionInterruptions.count),
                "timestamp": String(Date().timeIntervalSince1970),
                "fileSize": String(fileData.count),
                "watchDetectorMetadataJSON": detectorMetadataJSON
            ]
        } else {
            // Create JSON format (default)
            print("📦 Creating SessionData with detectorMetadata: \(detectorMetadata != nil)")
            if let meta = detectorMetadata {
                print("   - gateK: \(meta.gateK), nccThresh: \(meta.nccThresh)")
                print("   - configSource: \(meta.configSource)")
            }

            let sessionData = SessionData(
                sessionId: sessionId,
                timestamp: Date().timeIntervalSince1970,
                sensorData: sensorData,
                detectionEvents: detectionEvents,
                motionInterruptions: motionInterruptions,
                watchDetectorMetadata: detectorMetadata
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            fileData = try encoder.encode(sessionData)
            print("📦 Encoded SessionData size: \(fileData.count) bytes")

            // Debug: Check if watchDetectorMetadata is in the JSON
            if let jsonString = String(data: fileData, encoding: .utf8) {
                let hasMetadataKey = jsonString.contains("watchDetectorMetadata")
                let metadataIsNull = jsonString.contains("\"watchDetectorMetadata\":null")
                print("📤 JSON contains watchDetectorMetadata key: \(hasMetadataKey), isNull: \(metadataIsNull)")
            }
            metadata = [
                "type": "sessionFile",
                "format": "JSON",
                "sessionId": sessionId.uuidString,
                "sensorDataCount": String(sensorData.count),
                "detectionEventCount": String(detectionEvents.count),
                "hasDetectorMetadata": String(detectorMetadata != nil),
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
    let watchDetectorMetadata: WatchDetectorMetadata?
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: @preconcurrency WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        
        DispatchQueue.main.async {
            switch activationState {
            case .activated:
                self.transferStatus = "WCSession activated successfully"
                print("✅ WCSession activated on Watch")

                // Check for existing application context from iPhone
                // This is important because didReceiveApplicationContext is NOT called
                // if the context was sent before the Watch app launched
                let existingContext = session.receivedApplicationContext
                if !existingContext.isEmpty {
                    print("📱 Found existing application context with \(existingContext.count) keys")
                    self.processApplicationContext(existingContext)
                } else {
                    print("📱 No existing application context found")
                }

                // Flush queued transfers
                if !self.pendingTransfers.isEmpty {
                    for pendingTransfer in self.pendingTransfers {
                        Task {
                            do {
                                try await self.performFileTransfer(
                                    sensorData: pendingTransfer.sensorData,
                                    detectionEvents: pendingTransfer.detectionEvents,
                                    motionInterruptions: pendingTransfer.motionInterruptions,
                                    detectorMetadata: pendingTransfer.detectorMetadata,
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
        print("📱 didReceiveApplicationContext called with \(applicationContext.count) keys")
        DispatchQueue.main.async {
            self.processApplicationContext(applicationContext)
        }
    }

    /// Process application context from iPhone (shared by delegate and activation check)
    private func processApplicationContext(_ applicationContext: [String: Any]) {
        // Process export format
        if let formatString = applicationContext["exportFormat"] as? String {
            let validFormats = ["JSON", "CSV"]
            if validFormats.contains(formatString) {
                self.exportFormat = formatString
                print("📱 Export format updated from Phone: \(formatString)")
            }
        }

        // Process TKEO settings and detect changes
        var tkeoCount = 0
        var changedSettings: [ChangedSetting] = []
        let now = Date()

        for (key, value) in applicationContext {
            if key.hasPrefix("tkeo_") {
                // Check if this setting changed
                let oldValue = self.tkeoSettings[key]
                let valueChanged = !valuesAreEqual(oldValue, value)

                if valueChanged {
                    let displayName = settingDisplayName(for: key)
                    let oldStr = formatSettingValue(oldValue)
                    let newStr = formatSettingValue(value)

                    changedSettings.append(ChangedSetting(
                        key: key,
                        displayName: displayName,
                        oldValue: oldStr,
                        newValue: newStr,
                        changedAt: now
                    ))
                    print("📱 Setting changed: \(displayName): \(oldStr) → \(newStr)")
                }

                self.tkeoSettings[key] = value
                tkeoCount += 1
            }
        }

        if tkeoCount > 0 {
            self.tkeoSettingsReceived = true
            self.lastSyncTime = now

            // Update changed settings list (most recent first)
            if !changedSettings.isEmpty {
                self.recentlyChangedSettings = changedSettings + self.recentlyChangedSettings
                // Keep only the last 20 changes
                if self.recentlyChangedSettings.count > 20 {
                    self.recentlyChangedSettings = Array(self.recentlyChangedSettings.prefix(20))
                }

                // Trigger sync flash animation
                self.triggerSyncFlash()

                self.transferStatus = "Synced: \(changedSettings.count) settings changed"
            } else {
                self.transferStatus = "Settings synced: \(tkeoCount) parameters (no changes)"
            }

            print("📱 TKEO settings received from Phone: \(tkeoCount) parameters, \(changedSettings.count) changed")

            // Log some key values for debugging
            if let gateK = tkeoSettings["tkeo_gateThreshold"] as? Double {
                print("   - gateThreshold: \(gateK)")
            }
            if let nccThresh = tkeoSettings["tkeo_templateConfidence"] as? Double {
                print("   - templateConfidence: \(nccThresh)")
            }

            // Store current settings as previous for next comparison
            self.previousSettings = self.tkeoSettings

            // Update thread-safe cached copies
            self.settingsLock.lock()
            self._cachedSettings = self.tkeoSettings
            self._cachedSettingsReceived = true
            self.settingsLock.unlock()

            // Notify detection engine of settings update
            NotificationCenter.default.post(name: .tkeoSettingsUpdated, object: nil, userInfo: self.tkeoSettings)
        } else {
            print("⚠️ No TKEO settings found in application context")
        }
    }

    /// Trigger a brief flash animation for the sync indicator
    private func triggerSyncFlash() {
        syncFlashActive = true
        // Flash for 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.syncFlashActive = false
        }
    }

    /// Compare two Any values for equality
    private func valuesAreEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        if lhs == nil && rhs == nil { return true }
        guard let l = lhs, let r = rhs else { return false }

        switch (l, r) {
        case let (ld, rd) as (Double, Double): return abs(ld - rd) < 0.0001
        case let (li, ri) as (Int, Int): return li == ri
        case let (ls, rs) as (String, String): return ls == rs
        case let (lb, rb) as (Bool, Bool): return lb == rb
        default: return false
        }
    }

    /// Format a setting value for display
    private func formatSettingValue(_ value: Any?) -> String {
        guard let v = value else { return "—" }
        switch v {
        case let d as Double: return String(format: "%.2f", d)
        case let i as Int: return "\(i)"
        case let s as String: return s
        case let b as Bool: return b ? "On" : "Off"
        default: return "\(v)"
        }
    }

    /// Get display name for a setting key
    private func settingDisplayName(for key: String) -> String {
        let names: [String: String] = [
            "tkeo_sampleRate": "Sample Rate",
            "tkeo_gateThreshold": "Gate K (σ)",
            "tkeo_gyroVetoThresh": "Gyro Veto",
            "tkeo_gyroVetoHoldMs": "Gyro Hold",
            "tkeo_amplitudeSurplus": "Amplitude Surplus",
            "tkeo_isiThreshold": "ISI Threshold",
            "tkeo_refractoryMs": "Refractory",
            "tkeo_minWidthMs": "Min Width",
            "tkeo_maxWidthMs": "Max Width",
            "tkeo_templateConfidence": "NCC Thresh",
            "tkeo_windowPreMs": "Window Pre",
            "tkeo_windowPostMs": "Window Post",
            "tkeo_bandpassLow": "Bandpass Low",
            "tkeo_bandpassHigh": "Bandpass High",
            "tkeo_accelWeight": "Accel Weight",
            "tkeo_gyroWeight": "Gyro Weight",
            "tkeo_madWinSec": "MAD Window",
            "tkeo_ignoreStartMs": "Ignore Start",
            "tkeo_ignoreEndMs": "Ignore End",
            "tkeo_gateRampMs": "Gate Ramp",
            "tkeo_preQuietMs": "Pre-Quiet",
            "tkeo_useTemplateValidation": "Template Valid."
        ]
        return names[key] ?? key.replacingOccurrences(of: "tkeo_", with: "")
    }

    /// Get all current settings formatted for display, with recently changed ones first
    func getAllSettingsForDisplay() -> [SettingValue] {
        let recentKeys = Set(recentlyChangedSettings.prefix(5).map { $0.key })

        var settings: [SettingValue] = []

        // Define settings with categories
        let settingDefs: [(key: String, category: SettingValue.SettingCategory)] = [
            ("tkeo_gateThreshold", .threshold),
            ("tkeo_templateConfidence", .threshold),
            ("tkeo_gyroVetoThresh", .threshold),
            ("tkeo_amplitudeSurplus", .threshold),
            ("tkeo_isiThreshold", .timing),
            ("tkeo_refractoryMs", .timing),
            ("tkeo_minWidthMs", .timing),
            ("tkeo_maxWidthMs", .timing),
            ("tkeo_gyroVetoHoldMs", .timing),
            ("tkeo_windowPreMs", .timing),
            ("tkeo_windowPostMs", .timing),
            ("tkeo_preQuietMs", .timing),
            ("tkeo_ignoreStartMs", .timing),
            ("tkeo_ignoreEndMs", .timing),
            ("tkeo_gateRampMs", .timing),
            ("tkeo_useTemplateValidation", .validation),
            ("tkeo_sampleRate", .other),
            ("tkeo_bandpassLow", .other),
            ("tkeo_bandpassHigh", .other),
            ("tkeo_accelWeight", .other),
            ("tkeo_gyroWeight", .other),
            ("tkeo_madWinSec", .other)
        ]

        for def in settingDefs {
            if let value = tkeoSettings[def.key] {
                settings.append(SettingValue(
                    id: def.key,
                    displayName: settingDisplayName(for: def.key),
                    value: formatSettingValue(value),
                    category: def.category,
                    wasRecentlyChanged: recentKeys.contains(def.key)
                ))
            }
        }

        // Sort: recently changed first, then by category
        settings.sort { a, b in
            if a.wasRecentlyChanged != b.wasRecentlyChanged {
                return a.wasRecentlyChanged
            }
            return a.category.rawValue < b.category.rawValue
        }

        return settings
    }

    /// Build a PinchConfig from synced settings, falling back to watchDefaults
    /// This is nonisolated to allow calling from non-MainActor contexts
    nonisolated func buildPinchConfig() -> PinchConfig {
        // Helper to get Double from settings
        func getDouble(_ settings: [String: Any], _ key: String, default defaultValue: Float) -> Float {
            if let value = settings[key] as? Double {
                return Float(value)
            }
            return defaultValue
        }

        // Thread-safe read of cached settings
        settingsLock.lock()
        let settings = _cachedSettings
        settingsLock.unlock()

        let defaults = PinchConfig.watchDefaults()

        return PinchConfig(
            fs: getDouble(settings, "tkeo_sampleRate", default: defaults.fs),
            bandpassLow: getDouble(settings, "tkeo_bandpassLow", default: defaults.bandpassLow),
            bandpassHigh: getDouble(settings, "tkeo_bandpassHigh", default: defaults.bandpassHigh),
            accelWeight: getDouble(settings, "tkeo_accelWeight", default: defaults.accelWeight),
            gyroWeight: getDouble(settings, "tkeo_gyroWeight", default: defaults.gyroWeight),
            madWinSec: getDouble(settings, "tkeo_madWinSec", default: defaults.madWinSec),
            gateK: getDouble(settings, "tkeo_gateThreshold", default: defaults.gateK),
            refractoryMs: getDouble(settings, "tkeo_refractoryPeriod", default: defaults.refractoryMs / 1000.0) * 1000.0,
            minWidthMs: getDouble(settings, "tkeo_minWidthMs", default: defaults.minWidthMs),
            maxWidthMs: getDouble(settings, "tkeo_maxWidthMs", default: defaults.maxWidthMs),
            nccThresh: getDouble(settings, "tkeo_templateConfidence", default: defaults.nccThresh),
            windowPreMs: getDouble(settings, "tkeo_windowPreMs", default: defaults.windowPreMs),
            windowPostMs: getDouble(settings, "tkeo_windowPostMs", default: defaults.windowPostMs),
            ignoreStartMs: getDouble(settings, "tkeo_ignoreStartMs", default: defaults.ignoreStartMs),
            ignoreEndMs: getDouble(settings, "tkeo_ignoreEndMs", default: defaults.ignoreEndMs),
            gateRampMs: getDouble(settings, "tkeo_gateRampMs", default: defaults.gateRampMs),
            gyroVetoThresh: getDouble(settings, "tkeo_gyroVetoThresh", default: defaults.gyroVetoThresh),
            gyroVetoHoldMs: getDouble(settings, "tkeo_gyroVetoHoldMs", default: defaults.gyroVetoHoldMs),
            amplitudeSurplusThresh: getDouble(settings, "tkeo_amplitudeSurplusThresh", default: defaults.amplitudeSurplusThresh),
            preQuietMs: getDouble(settings, "tkeo_preQuietMs", default: defaults.preQuietMs),
            isiThresholdMs: getDouble(settings, "tkeo_isiThresholdMs", default: defaults.isiThresholdMs)
        )
    }

    /// Check if template validation should be used
    /// This is nonisolated to allow calling from non-MainActor contexts
    nonisolated func useTemplateValidation() -> Bool {
        // Thread-safe read of cached settings
        settingsLock.lock()
        let settings = _cachedSettings
        settingsLock.unlock()

        if let value = settings["tkeo_useTemplateValidation"] as? Bool {
            return value
        }
        return true // Default
    }

    /// Check if settings have been received from iPhone
    /// This is nonisolated to allow calling from non-MainActor contexts
    nonisolated func hasReceivedSettings() -> Bool {
        // Thread-safe read of cached flag
        settingsLock.lock()
        let received = _cachedSettingsReceived
        settingsLock.unlock()
        return received
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

// MARK: - Notification Names
extension Notification.Name {
    static let tkeoSettingsUpdated = Notification.Name("tkeoSettingsUpdated")
}