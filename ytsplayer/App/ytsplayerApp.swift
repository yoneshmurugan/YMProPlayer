// ytsplayerApp.swift
// ytsplayer
//
// Application entry point. Sets up the shared audio engine and database
// before any view is created, and tears them down on quit.

import SwiftUI
import GRDB
import AppKit

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
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // KeyCode 49 is Spacebar
            if event.keyCode == 49 {
                // Do not intercept if user is typing in a search bar or text field
                if let responder = NSApp.keyWindow?.firstResponder {
                    let className = String(describing: type(of: responder))
                    if className.contains("NSTextView") || className.contains("TextField") || className.contains("SearchField") {
                        return event
                    }
                }
                
                self?.playbackVM.togglePlayPause()
                return nil // swallow event
            }
            return event
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
            
            CommandMenu("Playback") {
                Button("Play/Pause") {
                    AppEnvironment.shared.playbackVM.togglePlayPause()
                }
                
                Button("Next Track") {
                    AppEnvironment.shared.playbackVM.skipNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                
                Button("Previous Track") {
                    AppEnvironment.shared.playbackVM.skipPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                
                Divider()
                
                Button("Volume Up") {
                    let current = AppEnvironment.shared.playbackVM.volume
                    AppEnvironment.shared.playbackVM.volume = min(1.0, current + 0.05)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command])
                
                Button("Volume Down") {
                    let current = AppEnvironment.shared.playbackVM.volume
                    AppEnvironment.shared.playbackVM.volume = max(0.0, current - 0.05)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command])
                
                Button("Mute") {
                    if AppEnvironment.shared.playbackVM.volume > 0 {
                        AppEnvironment.shared.playbackVM.volume = 0
                    } else {
                        AppEnvironment.shared.playbackVM.volume = 1.0
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                
                Divider()
                
                Button(AppEnvironment.shared.playbackVM.isBitPerfect ? "Disable Bit-Perfect" : "Enable Bit-Perfect") {
                    AppEnvironment.shared.playbackVM.isBitPerfect.toggle()
                }
            }
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
                .environmentObject(env.playlistManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        MenuBarExtra("YM Pro", systemImage: "waveform") {
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
