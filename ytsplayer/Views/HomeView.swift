// HomeView.swift
// ytsplayer

import SwiftUI

struct HomeView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playbackVM: PlaybackViewModel
    
    var onSearchTapped: () -> Void
    var onProfileTapped: () -> Void
    var onNavigateToTab: ((AppTab) -> Void)? = nil
    
    // For navigating directly to album/artist from home
    @State private var selectedAlbum: AlbumViewModel?
    @State private var selectedArtist: ArtistViewModel?
    
    @EnvironmentObject var playlistManager: PlaylistManager
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                HStack {
                    Text("Listen Now")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Button(action: onSearchTapped) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(.trailing, 16)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                
                if libraryVM.quickPicks.isEmpty && libraryVM.mostPlayedAlbums.isEmpty && libraryVM.mostPlayedArtists.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.house")
                            .font(.system(size: 64))
                            .foregroundStyle(.purple.opacity(0.8))
                        Text("No Music Library")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("Click the folder icon in the toolbar to select\nyour FLAC music directory.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.6))
                            .font(.system(size: 14))
                        
                        Button(action: onProfileTapped) {
                            Text("Select Music Folder")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Color.purple)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 400)
                } else {
                    // 1. Quick Picks (3-row horizontal grid)
                    if !libraryVM.quickPicks.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            sectionHeader(title: "Quick Picks") {
                                onNavigateToTab?(.tracks)
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHGrid(rows: Array(repeating: GridItem(.fixed(60), spacing: 8), count: 3), spacing: 16) {
                                    ForEach(0..<libraryVM.quickPicks.count, id: \.self) { index in
                                        let track = libraryVM.quickPicks[index]
                                        RecentTrackCell(track: track)
                                            .frame(width: 320)
                                            .onTapGesture {
                                                playbackVM.play(track: track, queue: libraryVM.quickPicks, startIndex: index, context: .quickPicks)
                                            }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            .frame(height: 200)
                        }
                    }
                    
                    // 2. Most Listened Albums
                    if !libraryVM.mostPlayedAlbums.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            sectionHeader(title: "Most Listened Albums") {
                                onNavigateToTab?(.albums)
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 20) {
                                    ForEach(libraryVM.mostPlayedAlbums) { album in
                                        AlbumCard(album: album, isSelected: false)
                                            .frame(width: 180)
                                            .onTapGesture {
                                                selectedAlbum = album
                                            }
                                            .contextMenu {
                                                AlbumContextMenuHome(
                                                    album: album,
                                                    libraryVM: libraryVM,
                                                    playbackVM: playbackVM
                                                )
                                            }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    // 3. Most Listened Artists
                    if !libraryVM.mostPlayedArtists.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            sectionHeader(title: "Most Listened Artists") {
                                onNavigateToTab?(.artists)
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 24) {
                                    ForEach(libraryVM.mostPlayedArtists) { artist in
                                        ArtistCard(artist: artist)
                                            .frame(width: 140)
                                            .onTapGesture {
                                                selectedArtist = artist
                                            }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    // 4. Heavy Rotation (Songs)
                    if !libraryVM.mostPlayedTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            sectionHeader(title: "Heavy Rotation") {
                                onNavigateToTab?(.tracks)
                            }
                            
                            VStack(spacing: 8) {
                                ForEach(0..<libraryVM.mostPlayedTracks.count, id: \.self) { index in
                                    let track = libraryVM.mostPlayedTracks[index]
                                    RecentTrackCell(
                                        track: track,
                                        onPlayNext: { playbackVM.playNext(track) },
                                        onEnqueue: { playbackVM.enqueue(track) }
                                    )
                                        .padding(.horizontal, 14)
                                        .onTapGesture {
                                            playbackVM.play(track: track, queue: libraryVM.mostPlayedTracks, startIndex: index)
                                        }
                                }
                            }
                        }
                    }
                    
                    // 5. Recently Added Albums
                    if !libraryVM.recentAlbums.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            sectionHeader(title: "Recently Added Albums") {
                                onNavigateToTab?(.albums)
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 20) {
                                    ForEach(libraryVM.recentAlbums) { album in
                                        AlbumCard(album: album, isSelected: false)
                                            .frame(width: 180)
                                            .onTapGesture {
                                                selectedAlbum = album
                                            }
                                            .contextMenu {
                                                AlbumContextMenuHome(
                                                    album: album,
                                                    libraryVM: libraryVM,
                                                    playbackVM: playbackVM
                                                )
                                            }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    // 6. Recently Added Artists
                    if !libraryVM.recentArtists.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            sectionHeader(title: "Recently Added Artists") {
                                onNavigateToTab?(.artists)
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 24) {
                                    ForEach(libraryVM.recentArtists) { artist in
                                        ArtistCard(artist: artist)
                                            .frame(width: 140)
                                            .onTapGesture {
                                                selectedArtist = artist
                                            }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                } // Close else block
                
                Spacer(minLength: 40)
            }
        }
        .sheet(item: $selectedAlbum) { album in
            AlbumDetailView(
                album: album,
                tracks: libraryVM.fetchTracks(for: album),
                playbackVM: playbackVM
            )
        }
        .sheet(item: $selectedArtist) { artist in
            ArtistDetailView(
                artist: artist,
                libraryVM: libraryVM,
                playbackVM: playbackVM
            )
        }
        .onAppear {
            libraryVM.refreshQuickPicks()
            if libraryVM.mostPlayedAlbums.isEmpty {
                libraryVM.loadAlbums() // Loads everything
            }
        }
    }
    
    private func sectionHeader(title: String, action: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            if let action = action {
                Button("See all") { action() }
                    .font(.system(size: 14))
                    .foregroundStyle(.purple)
            }
        }
        .padding(.horizontal, 20)
    }
    
}

// MARK: - Album Context Menu Home

struct AlbumContextMenuHome: View {
    let album: AlbumViewModel
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playbackVM: PlaybackViewModel
    
    @EnvironmentObject var playlistManager: PlaylistManager
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        Button("Play Next") {
            let tracks = libraryVM.fetchTracks(for: album)
            for track in tracks.reversed() {
                playbackVM.playNext(track)
            }
        }
        Button("Add to Queue") {
            let tracks = libraryVM.fetchTracks(for: album)
            for track in tracks {
                playbackVM.enqueue(track)
            }
        }
        Divider()
        Menu("Add to Playlist") {
            Button("New Playlist...") {
                if let id = playlistManager.createPlaylist(name: "New Playlist") {
                    let tracks = libraryVM.fetchTracks(for: album)
                    playlistManager.addTracks(to: id, trackIds: tracks.map { $0.id })
                    openWindow(id: "PlaylistEditor", value: id)
                }
            }
            if !playlistManager.playlists.isEmpty {
                Divider()
                ForEach(playlistManager.playlists) { playlist in
                    Button(playlist.name) {
                        let tracks = libraryVM.fetchTracks(for: album)
                        playlistManager.addTracks(to: playlist.id, trackIds: tracks.map { $0.id })
                        openWindow(id: "PlaylistEditor", value: playlist.id)
                    }
                }
            }
        }
    }
}

struct RecentTrackCell: View {
    let track: TrackViewModel
    @State private var isHovered = false
    var onPlayNext: (() -> Void)? = nil
    var onEnqueue: (() -> Void)? = nil
    
    @EnvironmentObject var playlistManager: PlaylistManager
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            Group {
                if let path = track.albumArtworkPath,
                   let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                    let url = cacheDir.appendingPathComponent(path)
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.white.opacity(0.1)
                    }
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artistName ?? "Unknown Artist")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.white.opacity(0.5))
                    .rotationEffect(.degrees(90))
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(6)
        .background(isHovered ? Color.white.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { h in isHovered = h }
        .draggable(TrackDropPayload(trackIds: [track.id]))
        .contextMenu {
            Button("Play Next") {
                onPlayNext?()
            }
            Button("Add to Queue") {
                onEnqueue?()
            }
            Divider()
            Menu("Add to Playlist") {
                Button("New Playlist...") {
                    if let id = playlistManager.createPlaylist(name: "New Playlist") {
                        playlistManager.addTracks(to: id, trackIds: [track.id])
                        openWindow(id: "PlaylistEditor", value: id)
                    }
                }
                
                if !playlistManager.playlists.isEmpty {
                    Divider()
                    ForEach(playlistManager.playlists) { playlist in
                        Button(playlist.name) {
                            playlistManager.addTracks(to: playlist.id, trackIds: [track.id])
                            openWindow(id: "PlaylistEditor", value: playlist.id)
                        }
                    }
                }
            }
        }
    }
}
