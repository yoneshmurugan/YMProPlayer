// ytsplayerApp.swift
// ytsplayer
//
// Application entry point. Sets up the shared audio engine and database
// before any view is created, and tears them down on quit.

import SwiftUI
import GRDB

@MainActor
class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()
    
    let halEngine: CoreAudioHALEngine
    let db: DatabasePool
    let playlistManager: PlaylistManager
    let playbackVM: PlaybackViewModel
    
    private init() {
        let engine = CoreAudioHALEngine()
        halEngine = engine
        do {
            let pool = try AppDatabase.makeDatabasePool()
            db = pool
            playlistManager = PlaylistManager(db: pool)
            
            let pvm = PlaybackViewModel(halEngine: engine)
            pvm.onTrackPlayed = { id in
                try? pool.incrementPlayCount(forTrackId: id)
            }
            playbackVM = pvm
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
}

@main
struct ytsplayerApp: App {
    @StateObject private var env = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            ContentView(halEngine: env.halEngine, db: env.db, playbackVM: env.playbackVM)
                .environmentObject(env.playlistManager)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Remove default new-window command
            CommandGroup(replacing: .newItem) {}
        }
        
        WindowGroup("Playlist", id: "PlaylistEditor", for: Int64.self) { $playlistId in
            if let playlistId = playlistId {
                PlaylistEditorView(playlistId: playlistId, db: env.db)
                    .environmentObject(env.playlistManager)
                    .environmentObject(env.playbackVM)
            }
        }
        .windowStyle(.titleBar) // Let Playlist windows have a title bar!
        .commands {
            // Remove default new-window command
            CommandGroup(replacing: .newItem) {}
        }

        WindowGroup(id: "MiniPlayer") {
            MiniPlayerView()
                .environmentObject(env.playbackVM)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        MenuBarExtra("ytsplayer", systemImage: "waveform") {
            MenuBarAppView()
                .environmentObject(env.playbackVM)
        }
        .menuBarExtraStyle(.window)

        Settings {
            // macOS Settings window (Cmd+,)
            // Reuse the in-app settings view
            Text("Open Settings from the sidebar.")
                .frame(width: 300, height: 100)
        }
    }
}
