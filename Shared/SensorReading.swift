import Foundation
import simd

struct SensorReading: Codable {
    // Core sensor data (existing)
    let timestamp: Date
    let userAcceleration: SIMD3<Double>
    let rotationRate: SIMD3<Double>
    let activityIndex: Double
    let detectionScore: Double?
    let sessionState: SessionState
    
    // Enhanced metadata for comprehensive analysis
    let sessionId: UUID
    let gravity: SIMD3<Double>
    let attitudeX: Double?
    let attitudeY: Double?
    let attitudeZ: Double?
    let attitudeW: Double?
    let detectedPinch: Bool
    let manualCorrection: Bool
    let deviceInfo: DeviceInfo?
    
    enum SessionState: String, Codable {
        case inactive
        case setup
        case activeDhikr
        case paused
    }
}

struct DeviceInfo: Codable {
    let deviceModel: String
    let systemVersion: String
    let appVersion: String
    let samplingRate: Double
    
    static var current: DeviceInfo {
        return DeviceInfo(
            deviceModel: "Apple Watch", // Will be populated with actual device info
            systemVersion: "watchOS", // Will be populated with actual version
            appVersion: "1.0", // From bundle info
            samplingRate: 100.0
        )
    }
}

extension SensorReading {
    var accelerationMagnitude: Double {
        return sqrt(userAcceleration.x * userAcceleration.x + 
                   userAcceleration.y * userAcceleration.y + 
                   userAcceleration.z * userAcceleration.z)
    }
    
    var rotationMagnitude: Double {
        return sqrt(rotationRate.x * rotationRate.x + 
                   rotationRate.y * rotationRate.y + 
                   rotationRate.z * rotationRate.z)
    }
}