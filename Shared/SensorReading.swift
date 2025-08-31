import Foundation
import simd

struct SensorReading: Codable {
    let timestamp: Date
    let userAcceleration: SIMD3<Double>
    let rotationRate: SIMD3<Double>
    let activityIndex: Double
    let detectionScore: Double?
    let sessionState: SessionState
    
    enum SessionState: String, Codable {
        case inactive
        case setup
        case activeDhikr
        case paused
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