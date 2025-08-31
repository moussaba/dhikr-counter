import Foundation

struct DetectionEvent: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let score: Double
    let accelerationPeak: Double
    let gyroscopePeak: Double
    let validated: Bool
    let manualCorrection: Bool
    
    init(timestamp: Date, score: Double, accelerationPeak: Double, gyroscopePeak: Double, validated: Bool, manualCorrection: Bool = false) {
        self.timestamp = timestamp
        self.score = score
        self.accelerationPeak = accelerationPeak
        self.gyroscopePeak = gyroscopePeak
        self.validated = validated
        self.manualCorrection = manualCorrection
    }
}

extension DetectionEvent {
    var detectionType: DetectionType {
        if manualCorrection {
            return .manual
        } else if validated {
            return .validated
        } else {
            return .candidate
        }
    }
    
    enum DetectionType: String {
        case validated = "Validated"
        case candidate = "Candidate"
        case manual = "Manual"
    }
}