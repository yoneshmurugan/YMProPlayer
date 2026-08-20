// ContentView.swift
// ytsplayer

import SwiftUI
import GRDB

enum AppTab: Hashable {
    case home
    case albums
    case artists
    case hierarchy
    case search
    case mock(String)
}

struct ContentView: View {
    @StateObject private var playbackVM: PlaybackViewModel
    @StateObject private var libraryVM:  LibraryViewModel
    @StateObject private var searchVM:   SearchViewModel

    private let halEngine: CoreAudioHALEngine
    private let db: DatabasePool

    @State private var selectedTab: AppTab? = .home
    @State private var searchText = ""
    @State private var showFullScreenPlayer = false
    @State private var showSettings = false

    init(halEngine: CoreAudioHALEngine, db: DatabasePool) {
        self.halEngine = halEngine
        self.db = db
        _playbackVM = StateObject(wrappedValue: PlaybackViewModel(halEngine: halEngine))
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
                    // Search Bar Mock
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 8)
                    
                    Section("Listen Now") {
                        Label("Home", systemImage: "play.circle").tag(AppTab.home)
                    }
                    
                    Section("Library") {
                        Label("Albums", systemImage: "rectangle.stack").tag(AppTab.albums)
                        Label("Artists", systemImage: "music.mic").tag(AppTab.artists)
                        Label("Hierarchy", systemImage: "folder.tree").tag(AppTab.hierarchy)
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
                            HomeView(libraryVM: libraryVM, playbackVM: playbackVM)
                        case .albums:
                            LibraryView(libraryVM: libraryVM, playbackVM: playbackVM) {
                                showSettings = true
                            }
                        case .artists:
                            ArtistsView(libraryVM: libraryVM, playbackVM: playbackVM)
                        case .hierarchy:
                            HierarchyView(libraryVM: libraryVM, playbackVM: playbackVM)
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
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(libraryVM: libraryVM, halEngine: halEngine)
                .frame(width: 500, height: 400)
        }
        .navigationTitle("ytsplayer")
        .frame(minWidth: 1000, minHeight: 650)
        .preferredColorScheme(.dark)
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
