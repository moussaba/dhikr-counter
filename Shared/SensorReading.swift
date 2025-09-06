import Foundation
import simd

struct SensorReading: Codable {
    let timestamp: Date
    let motionTimestamp: Double // CMDeviceMotion.timestamp (seconds since boot)
    let epochTimestamp: Double  // Absolute epoch time in seconds
    let userAcceleration: SIMD3<Double>
    let gravity: SIMD3<Double>  // Added gravity data
    let rotationRate: SIMD3<Double>
    let attitude: SIMD4<Double> // Quaternion (w, x, y, z)
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

// Motion interruption event for tracking sensor stream breaks
struct MotionInterruption: Codable {
    let timestamp: Date
    let motionTimestamp: Double
    let epochTimestamp: Double
    let interruptionType: InterruptionType
    let duration: Double // Duration of interruption in seconds
    let reason: String
    
    enum InterruptionType: String, Codable {
        case streamPaused = "STREAM_PAUSED"
        case sensorTimeout = "SENSOR_TIMEOUT"  
        case motionError = "MOTION_ERROR"
        case streamResumed = "STREAM_RESUMED"
    }
    
    // CSV format for interruption events
    func csvRow() -> String {
        return "# MOTION_INTERRUPTION,\(String(format: "%.6f", motionTimestamp)),\(String(format: "%.6f", epochTimestamp)),\(interruptionType.rawValue),\(String(format: "%.3f", duration)),\(reason)"
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
    
    var gravityMagnitude: Double {
        return sqrt(gravity.x * gravity.x + 
                   gravity.y * gravity.y + 
                   gravity.z * gravity.z)
    }
    
    // CSV format compatible with the guide
    func csvRow() -> String {
        return String(format: "%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f",
                     motionTimestamp, epochTimestamp,
                     userAcceleration.x, userAcceleration.y, userAcceleration.z,
                     gravity.x, gravity.y, gravity.z,
                     rotationRate.x, rotationRate.y, rotationRate.z,
                     attitude.w, attitude.x, attitude.y, attitude.z)
    }
    
    static var csvHeader: String {
        return "time_s,epoch_s,userAccelerationX,userAccelerationY,userAccelerationZ,gravityX,gravityY,gravityZ,rotationRateX,rotationRateY,rotationRateZ,attitude_qW,attitude_qX,attitude_qY,attitude_qZ"
    }
}