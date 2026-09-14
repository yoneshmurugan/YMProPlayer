// ArtistsView.swift
// ytsplayer

import SwiftUI

struct ArtistsView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playbackVM: PlaybackViewModel
    var onSearchTapped: (() -> Void)? = nil
    
    @State private var selectedArtist: ArtistViewModel?
    
    @AppStorage("artistsIsGridView") private var isGridView = true
    
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20)]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Library")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.primary.opacity(0.5))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.3))
                Text("Artists")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                
                // View Toggles (Grid / List)
                HStack(spacing: 0) {
                    Button(action: { withAnimation { isGridView = true } }) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 26)
                            .background(isGridView ? Color.primary.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { withAnimation { isGridView = false } }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 26)
                            .background(!isGridView ? Color.primary.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 16)
                
                if let onSearchTapped = onSearchTapped {
                    Button(action: onSearchTapped) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(.trailing, 16)
                }
                
                Text("\(libraryVM.artists.count) artists")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            
            Divider().background(Color.primary.opacity(0.1))
            
            ScrollView {
                if isGridView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(libraryVM.artists) { artist in
                            ArtistCard(artist: artist)
                                .equatable()
                                .onTapGesture {
                                    selectedArtist = artist
                                }
                        }
                    }
                    .padding(20)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(libraryVM.artists) { artist in
                            ArtistListRow(artist: artist)
                                .onTapGesture {
                                    selectedArtist = artist
                                }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .sheet(item: $selectedArtist) { artist in
            ArtistDetailView(
                artist: artist,
                libraryVM: libraryVM,
                playbackVM: playbackVM
            )
        }
    }
}

struct ArtistListRow: View {
    let artist: ArtistViewModel
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Tiny Circular Thumbnail
            Group {
                if let path = artist.artworkCachePath,
                   let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                    let url = cacheDir.appendingPathComponent(path)
                    CachedAsyncImage(url: url) {
                        fallbackCircle
                    }
                    .scaledToFill()
                } else {
                    fallbackCircle
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                Text("\(artist.albumCount) Album\(artist.albumCount == 1 ? "" : "s") • \(artist.trackCount) Song\(artist.trackCount == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .contentShape(Rectangle())
    }
    
    private var fallbackCircle: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.purple.opacity(0.6), .indigo.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(String(artist.name.prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.8))
            )
    }
}

struct ArtistCard: View, Equatable {
    let artist: ArtistViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let path = artist.artworkCachePath,
                   let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                    let url = cacheDir.appendingPathComponent(path)
                    CachedAsyncImage(url: url) {
                        fallbackCircle
                    }
                    .scaledToFill()
                } else {
                    fallbackCircle
                }
            }
            .frame(width: 130, height: 130)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            
            Text(artist.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Text("\(artist.albumCount) Album\(artist.albumCount == 1 ? "" : "s") • \(artist.trackCount) Song\(artist.trackCount == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.primary.opacity(0.5))
        }
    }
    
    private var fallbackCircle: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.purple.opacity(0.6), .indigo.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(String(artist.name.prefix(1)).uppercased())
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.8))
            )
    }
}
