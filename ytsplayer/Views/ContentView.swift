// ContentView.swift
// ytsplayer

import SwiftUI
import GRDB

enum SidebarItem: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case library  = "Library"
    case search   = "Search"
    case settings = "Settings"

    var systemImage: String {
        switch self {
        case .library:  return "music.note.house"
        case .search:   return "magnifyingglass"
        case .settings: return "gear"
        }
    }
}

struct ContentView: View {
    @StateObject private var playbackVM: PlaybackViewModel
    @StateObject private var libraryVM:  LibraryViewModel
    @StateObject private var searchVM:   SearchViewModel

    private let halEngine: CoreAudioHALEngine
    private let db: DatabasePool

    @State private var selectedItem: SidebarItem? = .library

    init(halEngine: CoreAudioHALEngine, db: DatabasePool) {
        self.halEngine = halEngine
        self.db = db
        _playbackVM = StateObject(wrappedValue: PlaybackViewModel(halEngine: halEngine))
        _libraryVM  = StateObject(wrappedValue: LibraryViewModel(db: db))
        _searchVM   = StateObject(wrappedValue: SearchViewModel(db: db))
    }

    var body: some View {
        NavigationSplitView {
            // ── Sidebar ────────────────────────────────────────────────────
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                Label(item.rawValue, systemImage: item.systemImage)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)

        } detail: {
            // ── Detail Pane ────────────────────────────────────────────────
            VStack(spacing: 0) {
                Group {
                    switch selectedItem {
                    case .library, nil:
                        LibraryView(libraryVM: libraryVM, playbackVM: playbackVM)
                    case .search:
                        SearchView(searchVM: searchVM, playbackVM: playbackVM)
                    case .settings:
                        SettingsView(libraryVM: libraryVM, halEngine: halEngine)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // ── Now Playing Bar ────────────────────────────────────────
                NowPlayingBar(vm: playbackVM)
            }
        }
        .navigationTitle("ytsplayer")
        .frame(minWidth: 900, minHeight: 580)
    }
}
