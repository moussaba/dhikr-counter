import SwiftUI

@main
struct DhikrCounterApp: App {
    @StateObject private var detectionEngine = DhikrDetectionEngine()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(detectionEngine)
        }
    }
}