import SwiftUI
import Foundation

@main
struct DhikrCounterCompanionApp: App {
    init() {
        // Initialize WCSession singleton immediately at app launch
        _ = PhoneSessionManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            CompanionContentView()
        }
    }
}