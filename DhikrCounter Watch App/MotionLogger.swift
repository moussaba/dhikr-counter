import CoreMotion
import WatchKit
import HealthKit
import Foundation

final class MotionLogger {
    private let mm = CMMotionManager()
    private let queue = OperationQueue()
    private var fileHandle: FileHandle?
    private var buffer = String()
    private var startEpoch: TimeInterval = 0
    
    // MARK: - Keep the app alive while logging (watchOS)
    private var healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    
    func startLogging(to url: URL) throws {
        // Open file & write header
        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: url)
        write(SensorReading.csvHeader + "\n")
        
        // Keep session alive in background (strongly recommended)
        startWorkoutSession()
        
        // Configure Core Motion
        mm.deviceMotionUpdateInterval = 1.0 / 100.0 // ~100 Hz
        // Optional: helps stabilize reference frame
        mm.showsDeviceMovementDisplay = true
        
        // Align epoch with Core Motion timestamp (seconds since boot)
        startEpoch = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        
        // Start device motion with stable reference frame
        mm.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { [weak self] dm, err in
            guard let self = self, let dm = dm else { return }
            
            // High-res relative time (s since boot)
            let t = dm.timestamp                       // Double, sub-ms precision
            // Absolute epoch time in seconds (Double)
            let tEpoch = self.startEpoch + t
            
            // Signals (in g and rad/s)
            let ua = dm.userAcceleration   // (x,y,z) in g
            let gr = dm.gravity            // (x,y,z) unitless (g projection)
            let rr = dm.rotationRate       // (x,y,z) rad/s
            let q  = dm.attitude.quaternion
            
            // Never round: keep 6 decimals
            let line = String(
                format:"%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
                t, tEpoch,
                ua.x, ua.y, ua.z,
                gr.x, gr.y, gr.z,
                rr.x, rr.y, rr.z,
                q.w, q.x, q.y, q.z
            )
            self.buffer.append(line)
            
            // Flush periodically to avoid blocking
            if self.buffer.count > 64_000 { self.flush() }
        }
    }
    
    func stopLogging() {
        mm.stopDeviceMotionUpdates()
        flush()
        try? fileHandle?.close()
        fileHandle = nil
        stopWorkoutSession()
    }
    
    private func write(_ s: String) {
        if let data = s.data(using: .utf8) { fileHandle?.write(data) }
    }
    
    private func flush() {
        write(buffer); buffer.removeAll(keepingCapacity: true)
    }
    
    private func startWorkoutSession() {
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = .other
        cfg.locationType = .indoor
        
        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: cfg)
            workoutSession?.startActivity(with: Date())
            print("✅ Started background workout session for motion logging")
        } catch {
            print("⚠️ Failed to start workout session: \(error.localizedDescription)")
            // Continue without background session
        }
    }
    
    private func stopWorkoutSession() {
        workoutSession?.stopActivity(with: Date())
        workoutSession = nil
        print("🛑 Stopped background workout session")
    }
}