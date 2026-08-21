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
    @ObservedObject var playbackVM: PlaybackViewModel
    @StateObject private var libraryVM:  LibraryViewModel
    @StateObject private var searchVM:   SearchViewModel
    @Environment(\.openWindow) var openWindow

    private let halEngine: CoreAudioHALEngine
    private let db: DatabasePool

    @State private var selectedTab: AppTab? = .home
    @State private var searchText = ""
    @State private var showFullScreenPlayer = false
    @State private var showSettings = false

    init(halEngine: CoreAudioHALEngine, db: DatabasePool, playbackVM: PlaybackViewModel) {
        self.halEngine = halEngine
        self.db = db
        self.playbackVM = playbackVM
        _libraryVM  = StateObject(wrappedValue: LibraryViewModel(db: db))
        _searchVM   = StateObject(wrappedValue: SearchViewModel(db: db))
    }

    var body: some View {
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
            .ignoresSafeArea()
            
            GeometryReader { geo in
                Circle()
                    .fill(Color.purple.opacity(0.3))
                    .blur(radius: 120)
                    .frame(width: 600, height: 600)
                    .position(x: -100, y: -100)
                
                Circle()
                    .fill(Color.cyan.opacity(0.15))
                    .blur(radius: 150)
                    .frame(width: 700, height: 700)
                    .position(x: geo.size.width, y: geo.size.height)
            }
            .ignoresSafeArea()

            NavigationSplitView {
                // ── Sidebar ────────────────────────────────────────────────────
                List(selection: $selectedTab) {

                    
                    Section("Listen Now") {
                        Label("Listen Now", systemImage: "play.circle").tag(AppTab.home)
                    }
                    
                    Section("Library") {
                        Label("Albums", systemImage: "rectangle.stack").tag(AppTab.albums)
                        Label("Artists", systemImage: "music.mic").tag(AppTab.artists)
                        Label("Tracks", systemImage: "music.note.list").tag(AppTab.tracks)
                        Label("Hierarchy", systemImage: "folder").tag(AppTab.hierarchy)
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
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .tint(.purple)

            } detail: {
                // ── Detail Pane ────────────────────────────────────────────────
                VStack(spacing: 0) {
                    Group {
                        switch selectedTab {
                        case .home, nil:
                            HomeView(
                                libraryVM: libraryVM,
                                playbackVM: playbackVM,
                                onSearchTapped: { selectedTab = .search },
                                onProfileTapped: { showSettings = true },
                                onNavigateToTab: { tab in selectedTab = tab }
                            )
                        case .albums:
                            LibraryView(libraryVM: libraryVM, playbackVM: playbackVM) {
                                showSettings = true
                            }
                        case .artists:
                            ArtistsView(libraryVM: libraryVM, playbackVM: playbackVM)
                        case .tracks:
                            TracksView(libraryVM: libraryVM, playbackVM: playbackVM)
                        case .hierarchy:
                            HierarchyView(libraryVM: libraryVM, playbackVM: playbackVM)
                        case .playlists:
                            PlaylistsView()
                        case .playlist(let id):
                            PlaylistEditorView(playlistId: id, db: db)
                                .environmentObject(playbackVM)
                                .id(id)
                        case .search:
                            SearchView(searchVM: searchVM, playbackVM: playbackVM)
                        case .mock(let title):
                            mockView(title)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.45)) // Translucent to let ambient glow through

                    // ── Now Playing Bar ────────────────────────────────────────
                    NowPlayingBar(vm: playbackVM) {
                        if playbackVM.currentTrack != nil {
                            showFullScreenPlayer = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showFullScreenPlayer) {
            FullScreenPlayerView(vm: playbackVM, database: db)
                .frame(minWidth: 800, idealWidth: 900, idealHeight: 650)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(libraryVM: libraryVM, playbackVM: playbackVM, halEngine: halEngine)
                .frame(width: 500, height: 400)
        }
        .navigationTitle("ytsplayer")
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
        .touchBar {
            PlayerTouchBar(playbackVM: playbackVM, showFullScreenPlayer: $showFullScreenPlayer) { id in
                openWindow(id: "PlaylistEditor", value: id)
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
                        .filter { $0.pathExtension.lowercased() == "flac" }
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
    
    private func mockView(_ title: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)
            Text("\(title) is coming soon")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PlayerTouchBar

struct PlayerTouchBar: View {
    @ObservedObject var playbackVM: PlaybackViewModel
    @EnvironmentObject var playlistManager: PlaylistManager
    @Binding var showFullScreenPlayer: Bool
    var openPlaylistEditor: (Int64) -> Void

    var body: some View {
        if let track = playbackVM.currentTrack {
            // Track Title (Fixed Width, Scrollable/Revealing)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(track.title)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 150)
            
            // Favorite Button
            Button(action: {
                if let next = try? playlistManager.toggleFavorite(forTrackId: track.id) {
                    playbackVM.currentTrack?.isFavorite = next
                }
            }) {
                Image(systemName: track.isFavorite ? "heart.fill" : "heart")
            }

            // Playlist Button
            Button(action: {
                if let id = playlistManager.createPlaylist(name: "New Playlist") {
                    playlistManager.addTracks(to: id, trackIds: [track.id])
                    openPlaylistEditor(id)
                }
            }) {
                Image(systemName: "text.badge.plus")
            }
            
            // Playback Controls
            Button(action: { playbackVM.skipPrevious() }) { 
                Image(systemName: "backward.fill") 
            }
            Button(action: { playbackVM.togglePlayPause() }) { 
                Image(systemName: playbackVM.isPlaying ? "pause.fill" : "play.fill") 
            }
            Button(action: { playbackVM.skipNext() }) { 
                Image(systemName: "forward.fill") 
            }
            
            // Scrubber
            Slider(value: $playbackVM.playbackProgress, in: 0...1) {
                Text("")
            }
            
            // Volume
            Slider(value: $playbackVM.volume, in: 0...1) {
                Image(systemName: "speaker.wave.2.fill")
            }
            .frame(width: 100)
            .tint(playbackVM.isBitPerfect ? .gray : .purple)
            .opacity(playbackVM.isBitPerfect ? 0.5 : 1.0)
            
            Spacer()
            
            // Cover Image -> Opens Lyrics
            Button(action: {
                showFullScreenPlayer = true
            }) {
                if let path = track.albumArtworkPath, let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "music.note")
                        .frame(width: 30, height: 30)
                }
            }
            .buttonStyle(.borderless)
        } else {
            Text("ytsplayer")
        }
    }
}
