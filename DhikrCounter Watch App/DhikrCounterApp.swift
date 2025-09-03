import SwiftUI
import WatchKit

@main
struct DhikrCounterApp: App {
    @StateObject private var detectionEngine = DhikrDetectionEngine()
    
    init() {
        // Initialize WCSession singleton immediately at app launch
        _ = WatchSessionManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(detectionEngine)
        }
    }
}