import Foundation

struct DhikrSession: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    let endTime: Date?
    let totalPinches: Int
    let detectedPinches: Int
    let manualCorrections: Int
    let sessionDuration: TimeInterval
    let deviceInfo: DeviceInfo
    let sessionNotes: String?
    
    var isActive: Bool {
        return endTime == nil
    }
    
    var detectionAccuracy: Double {
        guard detectedPinches > 0 else { return 0.0 }
        return Double(detectedPinches) / Double(totalPinches)
    }
    
    var title: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Dhikr Session - \(formatter.string(from: startTime))"
    }
    
    init(startTime: Date = Date(), deviceInfo: DeviceInfo = .current) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = nil
        self.totalPinches = 0
        self.detectedPinches = 0
        self.manualCorrections = 0
        self.sessionDuration = 0
        self.deviceInfo = deviceInfo
        self.sessionNotes = nil
    }
    
    func completed(at endTime: Date, totalPinches: Int, detectedPinches: Int, manualCorrections: Int, notes: String? = nil) -> DhikrSession {
        return DhikrSession(
            id: self.id,
            startTime: self.startTime,
            endTime: endTime,
            totalPinches: totalPinches,
            detectedPinches: detectedPinches,
            manualCorrections: manualCorrections,
            sessionDuration: endTime.timeIntervalSince(self.startTime),
            deviceInfo: self.deviceInfo,
            sessionNotes: notes
        )
    }
    
    private init(id: UUID, startTime: Date, endTime: Date?, totalPinches: Int, detectedPinches: Int, manualCorrections: Int, sessionDuration: TimeInterval, deviceInfo: DeviceInfo, sessionNotes: String?) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.totalPinches = totalPinches
        self.detectedPinches = detectedPinches
        self.manualCorrections = manualCorrections
        self.sessionDuration = sessionDuration
        self.deviceInfo = deviceInfo
        self.sessionNotes = sessionNotes
    }
}

extension DhikrSession {
    static let sample = DhikrSession(
        id: UUID(),
        startTime: Date().addingTimeInterval(-1800), // 30 minutes ago
        endTime: Date().addingTimeInterval(-300),    // 5 minutes ago
        totalPinches: 100,
        detectedPinches: 87,
        manualCorrections: 4,
        sessionDuration: 1500, // 25 minutes
        deviceInfo: .current,
        sessionNotes: "Evening dhikr session - Astaghfirullah"
    )
}