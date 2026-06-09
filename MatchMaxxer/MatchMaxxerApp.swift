//
//  MatchMaxxerApp.swift
//  MatchMaxxer
//
//  Created by Casey Millstein on 5/2/26.
//

import SwiftUI

@main
struct MatchMaxxerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Authenticate once the UI is live. Doing this in App.init()
                // runs before any UIWindowScene exists, so the Game Center
                // sign-in controller GameKit hands back has no window to be
                // presented from — it gets silently dropped and GameKit won't
                // offer it again this launch, leaving the sign-in button dead.
                .task { LeaderboardManager.shared.authenticate() }
        }
    }
}
