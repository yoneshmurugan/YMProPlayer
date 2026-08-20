// HomeView.swift
// ytsplayer

import SwiftUI

struct HomeView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playbackVM: PlaybackViewModel
    
    var onSearchTapped: () -> Void
    var onProfileTapped: () -> Void
    
    // For navigating directly to album/artist from home
    @State private var selectedAlbum: AlbumViewModel?
    @State private var selectedArtist: ArtistViewModel?
    
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
                    .padding(.trailing, 16)
                    
                    Button(action: onProfileTapped) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                
                if libraryVM.recentTracks.isEmpty && libraryVM.recentAlbums.isEmpty && libraryVM.recentArtists.isEmpty {
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
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 400)
                } else {
                    // 1. Recently added tracks (3-row horizontal grid)
                if !libraryVM.recentTracks.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader(title: "Recently added tracks")
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHGrid(rows: Array(repeating: GridItem(.fixed(60), spacing: 8), count: 3), spacing: 16) {
                                ForEach(0..<libraryVM.recentTracks.count, id: \.self) { index in
                                    let track = libraryVM.recentTracks[index]
                                    RecentTrackCell(track: track)
                                        .frame(width: 320)
                                        .onTapGesture {
                                            playbackVM.play(track: track, queue: libraryVM.recentTracks, startIndex: index)
                                        }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .frame(height: 200) // 3 rows of 60 + spacing
                    }
                }
                
                // 2. Recently added albums (horizontal squares)
                if !libraryVM.recentAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader(title: "Recently added albums")
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 20) {
                                ForEach(libraryVM.recentAlbums) { album in
                                    AlbumCard(album: album, isSelected: false)
                                        .frame(width: 180)
                                        .onTapGesture {
                                            selectedAlbum = album
                                        }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                
                // 3. Recently added artists (horizontal circles)
                if !libraryVM.recentArtists.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader(title: "Recently added artists")
                        
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
            if libraryVM.recentTracks.isEmpty {
                libraryVM.loadAlbums() // which also loads recent items now
            }
        }
    }
    
    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button("See all >") {}
                .font(.system(size: 14))
                .foregroundStyle(.purple)
        }
        .padding(.horizontal, 20)
    }
}

struct RecentTrackCell: View {
    let track: TrackViewModel
    @State private var isHovered = false
    
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
    }
}
