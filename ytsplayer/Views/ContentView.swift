// ContentView.swift
// ytsplayer

import SwiftUI
import GRDB

enum AppTab: Hashable {
    case home
    case albums
    case artists
    case tracks
    case hierarchy
    case playlists
    case playlist(Int64)
    case search
    case mock(String)
}

struct ContentView: View {
    @EnvironmentObject var playlistManager: PlaylistManager
    let playbackVM: PlaybackViewModel
    @StateObject private var libraryVM:  LibraryViewModel
    @StateObject private var searchVM:   SearchViewModel
    @Environment(\.openWindow) var openWindow

    private let halEngine: CoreAudioHALEngine
    private let db: DatabasePool

    @State private var selectedTab: AppTab? = .home
    @State private var showFullScreenPlayer = false
    @State private var showSettings = false
    @State private var showFolderPicker = false
    @AppStorage("showNowPlayingInspector") private var showInspector = false
    @State private var isFullScreen: Bool = false
    @EnvironmentObject var themeManager: ThemeManager

    @AppStorage("introFinished") private var introFinished = false
    init(halEngine: CoreAudioHALEngine, db: DatabasePool, playbackVM: PlaybackViewModel) {
        self.halEngine = halEngine
        self.db = db
        self.playbackVM = playbackVM
        _libraryVM  = StateObject(wrappedValue: LibraryViewModel(db: db))
        _searchVM   = StateObject(wrappedValue: SearchViewModel(db: db))
    }

    var body: some View {
        NavigationSplitView {
            // ── Sidebar ────────────────────────────────────────────────────
            VStack(spacing: 0) {
                List(selection: $selectedTab) {

                    
                    Section("Listen Now") {
                        Label("Listen Now", systemImage: "play.circle").tag(AppTab.home)
                        Label("Search", systemImage: "magnifyingglass").tag(AppTab.search)
                    }
                    
                    Section("Library") {
                        Label("Albums", systemImage: "rectangle.stack").tag(AppTab.albums)
                        Label("Artists", systemImage: "music.mic").tag(AppTab.artists)
                        Label("Tracks", systemImage: "music.note.list").tag(AppTab.tracks)
                        Label("Hierarchy", systemImage: "folder").tag(AppTab.hierarchy)
                        Button(action: { showSettings = true }) {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Section("Playlists") {
                        Label("All Playlists", systemImage: "square.grid.2x2").tag(AppTab.playlists)
                        
                        ForEach(playlistManager.playlists) { pl in
                            Label(pl.name, systemImage: "music.note.list")
                                .dropDestination(for: TrackDropPayload.self) { payloads, _ in
                                    let trackIds = payloads.flatMap { $0.trackIds }
                                    if !trackIds.isEmpty {
                                        playlistManager.addTracks(to: pl.id, trackIds: trackIds)
                                        return true
                                    }
                                    return false
                                }
                                .contextMenu {
                                    Button("Open in New Window") {
                                        openWindow(id: "PlaylistEditor", value: pl.id)
                                    }
                                    Button("Delete Playlist", role: .destructive) {
                                        playlistManager.deletePlaylist(id: pl.id)
                                        if selectedTab == .playlist(pl.id) {
                                            selectedTab = .playlists
                                        }
                                    }
                                }
                                .tag(AppTab.playlist(pl.id))
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .tint(.purple)
                .symbolEffect(.bounce, value: selectedTab)
                
                Divider()
                    .background(Color.primary.opacity(0.1))
                
                VStack(spacing: 12) {
                    Button(action: {
                        showFolderPicker = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 20))
                                .foregroundStyle(.primary)
                            
                            Text("Add Folders")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    
                    Text("YM Pro v2.1")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 20)
                .background(Color.clear)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)

        } detail: {
            // ── Detail Pane ────────────────────────────────────────────────
            // IMPORTANT: NowPlayingBar is broken out into its own view (DetailContentView)
            // so that its @ObservedObject (playbackProgress ticking every second) does NOT
            // cause ContentView to re-evaluate, which would thrash the inspector's
            // _NSConstraintBasedLayoutHostingView and crash with constraint loop on macOS 27.
            DetailContentView(
                selectedTab: $selectedTab,
                showFullScreenPlayer: $showFullScreenPlayer,
                showSettings: $showSettings,
                showInspector: $showInspector,
                playbackVM: playbackVM,
                libraryVM: libraryVM,
                searchVM: searchVM,
                db: db
            )
        }
        .navigationSplitViewStyle(.balanced)

        .background(
            ZStack {
                // ── Ambient Vibrant Background ──
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.05, blue: 0.2),
                        Color(red: 0.05, green: 0.08, blue: 0.2),
                        Color(red: 0.02, green: 0.02, blue: 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Static positioned circles without GeometryReader to avoid layout loops
                Circle()
                    .fill(Color.purple.opacity(0.3))
                    .blur(radius: 120)
                    .frame(width: 600, height: 600)
                    .offset(x: -100, y: -100)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                
                Circle()
                    .fill(Color.cyan.opacity(0.15))
                    .blur(radius: 150)
                    .frame(width: 700, height: 700)
                    .offset(x: 100, y: 100)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                
                Color.clear
                    .onAppear {
                        DispatchQueue.main.async {
                            isFullScreen = NSApplication.shared.windows.first(where: { $0.isKeyWindow })?.styleMask.contains(.fullScreen) ?? false
                        }
                    }
            }
        )
        .overlay(
            Group {
                // ── Intro Video Loader (plays once on launch) ──
                if !introFinished {
                    IntroVideoView(isFinished: $introFinished)
                        .transition(.opacity)
                        .zIndex(200)
                }
                
                // ── Full-Screen Player Overlay (Liquid Glass) ──
                if showFullScreenPlayer {
                    FullScreenPlayerView(vm: playbackVM, database: db, isPresented: $showFullScreenPlayer)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(100)
                }
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }

        .sheet(isPresented: $showSettings) {
            SettingsView(libraryVM: libraryVM, playbackVM: playbackVM, halEngine: halEngine)
                .frame(width: 500, height: 400)
        }
        .background(
            Button("") { showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        )
        .navigationTitle("YM Pro")
        .frame(minWidth: 1000, minHeight: 650)
        .preferredColorScheme(.dark)
        .onAppear {
            playbackVM.onTrackPlayed = { id in
                try? db.incrementPlayCount(forTrackId: id)
                libraryVM.refreshMostPlayed()
            }
            playbackVM.onQueueEnded = {
                handleQueueEnded()
            }
        }

        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    _ = url.startAccessingSecurityScopedResource()
                    libraryVM.addFolder(url: url)
                }
                libraryVM.startScan()
            }
        }
    }
    
    private func handleQueueEnded() {
        switch playbackVM.currentContext {
        case .album(let albumId):
            if let idx = libraryVM.albums.firstIndex(where: { $0.id == albumId }), idx + 1 < libraryVM.albums.count {
                let nextAlbum = libraryVM.albums[idx + 1]
                let tracks = libraryVM.fetchTracks(for: nextAlbum)
                if let first = tracks.first {
                    playbackVM.play(track: first, queue: tracks, startIndex: 0, context: .album(albumId: nextAlbum.id))
                }
            }
        case .hierarchy(let folderUrl):
            let fm = FileManager.default
            let parent = folderUrl.deletingLastPathComponent()
            if let urls = try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                let dirs = urls
                    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                if let idx = dirs.firstIndex(of: folderUrl), idx + 1 < dirs.count {
                    let nextDir = dirs[idx + 1]
                    let files = (try? fm.contentsOfDirectory(at: nextDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                    let trackPaths = files
                        .filter { supportedAudioExtensions.contains($0.pathExtension.lowercased()) }
                        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                        .map { $0.path }
                    let tracks = trackPaths.compactMap { libraryVM.fetchTrack(byPath: $0) }
                    if let first = tracks.first {
                        playbackVM.play(track: first, queue: tracks, startIndex: 0, context: .hierarchy(folderUrl: nextDir))
                    }
                }
            }
        default:
            break
        }
    }
}
