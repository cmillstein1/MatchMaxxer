//
//  MatchMaxxerApp.swift
//  MatchMaxxer
//
//  Created by Casey Millstein on 5/2/26.
//

import SwiftUI

@main
struct MatchMaxxerApp: App {
    init() {
        LeaderboardManager.shared.authenticate()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
