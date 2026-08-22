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
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    Button(action: { showSettings = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.purple)
                            Text("Settings")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        if isHovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)

            } detail: {
                // ── Detail Pane ────────────────────────────────────────────────
                ZStack(alignment: .bottom) {
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
                            LibraryView(libraryVM: libraryVM, playbackVM: playbackVM, onSearchTapped: { selectedTab = .search }) {
                                showSettings = true
                            }
                        case .artists:
                            ArtistsView(libraryVM: libraryVM, playbackVM: playbackVM, onSearchTapped: { selectedTab = .search })
                        case .tracks:
                            TracksView(libraryVM: libraryVM, playbackVM: playbackVM, onSearchTapped: { selectedTab = .search })
                        case .hierarchy:
                            HierarchyView(libraryVM: libraryVM, playbackVM: playbackVM, onSearchTapped: { selectedTab = .search })
                        case .playlists:
                            PlaylistsView()
                        case .playlist(let id):
                            PlaylistEditorView(playlistId: id, db: db)
                                .environmentObject(playbackVM)
                                .id(id)
                        case .search:
                            SearchView(searchVM: searchVM, libraryVM: libraryVM, playbackVM: playbackVM)
                        case .mock(let title):
                            mockView(title)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.45))
                    // Safe area equivalent so scrollviews can scroll past the floating bar
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 120)
                    }

                    // ── Now Playing Bar (Floating in Detail Pane) ─────────────
                    NowPlayingBar(
                        vm: playbackVM,
                        onSearchTapped: { selectedTab = .search },
                        onArtworkTap: {
                            if playbackVM.currentTrack != nil {
                                showFullScreenPlayer = true
                            }
                        }
                    )
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
            // Premium Static Icon (Replaces buggy NSImage)
            Image(systemName: playbackVM.isPlaying ? "waveform" : "waveform.path")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundColor(.purple)
            
            // Static Track Info (Expanded width + Audiophile Stats)
            VStack(alignment: .leading, spacing: 2) {
                Text(playbackVM.currentTrack?.title ?? "ytsplayer")
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                
                let stats = "\(playbackVM.currentBitDepth)-bit / \(playbackVM.currentSampleRate / 1000)kHz"
                let artist = playbackVM.currentTrack?.artistName ?? "Bit-Perfect Audio"
                Text("\(artist) • \(stats)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 250, alignment: .leading)
            .clipped()
            
            // Format Badge, Hi-Res Logo
            if let track = playbackVM.currentTrack {
                if playbackVM.currentBitDepth >= 24, let nsImage = NSImage(named: "hires.png") {
                    let _ = { nsImage.isTemplate = false }()
                    Image(nsImage: nsImage)
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(height: 14)
                }
            }
            
            Spacer(minLength: 16)
            
            Text("\(playbackVM.currentTimeString) / \(playbackVM.totalTimeString)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 75)
                .layoutPriority(1)
            
            // Volume Slider (Disabled if Bit-Perfect)
            Slider(value: $playbackVM.volume, in: 0...1) {
                Image(systemName: "speaker.wave.2.fill")
            }
            .frame(width: 150)
            .tint(playbackVM.isBitPerfect ? .gray : .purple)
            .grayscale(playbackVM.isBitPerfect ? 1.0 : 0.0)
            .disabled(playbackVM.isBitPerfect)
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
