// ArtistsView.swift
// ytsplayer

import SwiftUI

struct ArtistsView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playbackVM: PlaybackViewModel
    
    @State private var selectedArtist: ArtistViewModel?
    
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20)]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Library")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                Text("Artists")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(libraryVM.artists.count) artists")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            
            Divider().background(Color.white.opacity(0.1))
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(libraryVM.artists) { artist in
                        ArtistCard(artist: artist)
                            .onTapGesture {
                                selectedArtist = artist
                            }
                    }
                }
                .padding(20)
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

struct ArtistCard: View {
    let artist: ArtistViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let path = artist.artworkCachePath,
                   let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                    let url = cacheDir.appendingPathComponent(path)
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        fallbackCircle
                    }
                } else {
                    fallbackCircle
                }
            }
            .frame(width: 130, height: 130)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            
            Text(artist.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            
            Text("\(artist.albumCount) Album\(artist.albumCount == 1 ? "" : "s") • \(artist.trackCount) Song\(artist.trackCount == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
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
                    .foregroundStyle(.white.opacity(0.8))
            )
    }
}
