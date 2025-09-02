//
//  DhikrCounter_Watch_App_Extension.swift
//  DhikrCounter Watch App Extension
//
//  Created by Moussa Ba on 9/2/25.
//

import AppIntents

struct DhikrCounter_Watch_App_Extension: AppIntent {
    static var title: LocalizedStringResource { "DhikrCounter Watch App Extension" }
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}
