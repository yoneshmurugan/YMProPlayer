// ytsplayerApp.swift
// ytsplayer
//
// Application entry point. Sets up the shared audio engine and database
// before any view is created, and tears them down on quit.

import SwiftUI
import GRDB

@main
struct ytsplayerApp: App {
    private let halEngine: CoreAudioHALEngine
    private let db: DatabasePool

    init() {
        halEngine = CoreAudioHALEngine()
        do {
            db = try AppDatabase.makeDatabasePool()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(halEngine: halEngine, db: db)
                .preferredColorScheme(ColorScheme.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Remove default new-window command
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            // macOS Settings window (Cmd+,)
            // Reuse the in-app settings view
            Text("Open Settings from the sidebar.")
                .frame(width: 300, height: 100)
        }
    }
}
