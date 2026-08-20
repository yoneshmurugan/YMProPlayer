// ArtistDetailView.swift
// ytsplayer

import SwiftUI

struct ArtistDetailView: View {
    let artist: ArtistViewModel
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playbackVM: PlaybackViewModel
    
    @State private var tracks: [TrackViewModel] = []
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    HStack(spacing: 24) {
                        Group {
                            if let path = artist.artworkCachePath,
                               let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                                let url = cacheDir.appendingPathComponent(path)
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    fallbackCircle
                                }
                            } else {
                                fallbackCircle
                            }
                        }
                        .frame(width: 180, height: 180)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(artist.name)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(.white)
                            
                            Text("\(artist.albumCount) Album\(artist.albumCount == 1 ? "" : "s") • \(tracks.count) Track\(tracks.count == 1 ? "" : "s")")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                            
                            Button(action: {
                                if let first = tracks.first {
                                    playbackVM.play(track: first, queue: tracks, startIndex: 0)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Play All")
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.purple)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                        Spacer()
                    }
                    .padding(32)
                    
                    // Track List (grouped by album visually)
                    LazyVStack(spacing: 0) {
                        ForEach(0..<tracks.count, id: \.self) { index in
                            ArtistTrackRowWrapper(tracks: tracks, index: index, playbackVM: playbackVM)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .background(Color.black.opacity(0.9))
        }
        .onAppear {
            self.tracks = libraryVM.fetchTracks(for: artist)
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
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            )
    }
}

struct ArtistTrackRowWrapper: View {
    let tracks: [TrackViewModel]
    let index: Int
    @ObservedObject var playbackVM: PlaybackViewModel
    
    var isNewAlbum: Bool {
        if index == 0 { return true }
        return tracks[index - 1].albumTitle != tracks[index].albumTitle
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isNewAlbum {
                HStack {
                    Text(tracks[index].albumTitle ?? "Unknown Album")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)
                
                Divider().background(Color.white.opacity(0.1))
                    .padding(.horizontal, 24)
            }
            
            TrackRow(track: tracks[index], isPlaying: playbackVM.currentTrack?.id == tracks[index].id)
                .onTapGesture {
                    playbackVM.play(track: tracks[index], queue: tracks, startIndex: index)
                }
                .padding(.horizontal, 24)
        }
    }
}
