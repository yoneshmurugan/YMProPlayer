// AlbumDetailView.swift
// ytsplayer

import SwiftUI

struct AlbumDetailView: View {
    let album: AlbumViewModel
    let tracks: [TrackViewModel]
    @ObservedObject var playbackVM: PlaybackViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ─────────────────────────────────────────────────────
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottomLeading) {
                    // Blurred artwork background
                    if let path = album.artworkCachePath,
                       let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                        CachedAsyncImage(url: cacheDir.appendingPathComponent(path)) { Color.clear }
                        .frame(height: 220)
                        .clipped()
                        .blur(radius: 40)
                        .overlay(Color.black.opacity(0.55))
                    } else {
                        LinearGradient(
                            colors: [.purple.opacity(0.4), .black],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 220)
                    }

                    HStack(alignment: .bottom, spacing: 20) {
                        // Album art
                        ZStack(alignment: .bottomTrailing) {
                            artworkView
                                .frame(width: 130, height: 130)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: .black.opacity(0.5), radius: 16)
                                .contextMenu {
                                    AlbumDetailContextMenu(
                                        album: album,
                                        tracks: tracks,
                                        playbackVM: playbackVM
                                    )
                                }
                            
                            if album.isHiRes {
                                if let nsImage = NSImage(named: "hires.png") {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 26)
                                        .padding(8)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(album.title)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        if let artist = album.artistName {
                            Text(artist)
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        HStack(spacing: 10) {
                            if let year = album.year {
                                Text(String(year))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            Text("\(album.trackCount) tracks")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.55))
                        }

                        // Play all button
                        Button(action: playAll) {
                            Label("Play All", systemImage: "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(20)
                }
                
                // Close button
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.6))
                        .background(Circle().fill(Color.black.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .padding(20)
            }
            .frame(height: 220)

            // ── Track List ─────────────────────────────────────────────────
            List(Array(tracks.enumerated()), id: \.element.id) { index, track in
                AlbumTrackRow(
                    track: track,
                    isPlaying: playbackVM.currentTrack?.id == track.id && playbackVM.isPlaying,
                    onPlayNext: { playbackVM.playNext(track) },
                    onEnqueue: { playbackVM.enqueue(track) },
                    allTracks: tracks,
                    index: index
                )
                .listRowBackground(
                    playbackVM.currentTrack?.id == track.id
                        ? Color.purple.opacity(0.12)
                        : Color.clear
                )
                .onTapGesture {
                    playbackVM.play(track: track, queue: tracks, startIndex: index, context: .album(albumId: album.id))
                    dismiss()
                }
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 520, minHeight: 600)
        .background(.background)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let path = album.artworkCachePath,
           let cacheDir = ImageDownsampler.artworkCacheDirectory() {
            CachedAsyncImage(url: cacheDir.appendingPathComponent(path)) { placeholderArt }
            .scaledToFill()
        } else {
            placeholderArt
        }
    }

    private var placeholderArt: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.purple.opacity(0.5), .blue.opacity(0.3)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.3))
            )
    }

    private func playAll() {
        guard !tracks.isEmpty else { return }
        playbackVM.play(track: tracks[0], queue: tracks, startIndex: 0)
        dismiss()
    }
}

// MARK: - Album Detail Context Menu

struct AlbumDetailContextMenu: View {
    let album: AlbumViewModel
    let tracks: [TrackViewModel]
    @ObservedObject var playbackVM: PlaybackViewModel
    
    @EnvironmentObject var playlistManager: PlaylistManager
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        Button("Play Next") {
            for track in tracks.reversed() {
                playbackVM.playNext(track)
            }
        }
        Button("Add to Queue") {
            for track in tracks {
                playbackVM.enqueue(track)
            }
        }
        Divider()
        Menu("Add to Playlist") {
            Button("New Playlist...") {
                if let id = playlistManager.createPlaylist(name: "New Playlist") {
                    playlistManager.addTracks(to: id, trackIds: tracks.map { $0.id })
                    openWindow(id: "PlaylistEditor", value: id)
                }
            }
            if !playlistManager.playlists.isEmpty {
                Divider()
                ForEach(playlistManager.playlists) { playlist in
                    Button(playlist.name) {
                        playlistManager.addTracks(to: playlist.id, trackIds: tracks.map { $0.id })
                        openWindow(id: "PlaylistEditor", value: playlist.id)
                    }
                }
            }
        }
    }
}

// MARK: - Track Row

struct AlbumTrackRow: View {
    let track: TrackViewModel
    let isPlaying: Bool
    
    var onPlayNext: (() -> Void)? = nil
    var onEnqueue: (() -> Void)? = nil
    let allTracks: [TrackViewModel]
    let index: Int
    
    @State private var isFavoriteLocal = false
    @State private var isHovered = false
    @EnvironmentObject var playlistManager: PlaylistManager
    @Environment(\.openWindow) var openWindow

    var body: some View {
        HStack(spacing: 12) {
            // Track number / playing indicator
            ZStack {
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                        .foregroundStyle(.purple)
                } else {
                    Text(track.trackNumber.map { String($0) } ?? "–")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 24, alignment: .center)

            Text(track.title)
                .font(.system(size: 13))
                .foregroundStyle(isPlaying ? .purple : .primary)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 6) {
                // Hi-Res Badge
                if track.bitDepth >= 24 {
                    Text("Hi-Res")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // File Type Badge
                let ext = (track.filePath as NSString).pathExtension.uppercased()
                Text(ext.isEmpty ? "AUDIO" : ext)
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // Sample rate badge
                Text("\(track.sampleRate / 1000)kHz·\(track.bitDepth)bit")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(badgeColor(for: track).opacity(0.15))
                    .foregroundStyle(badgeColor(for: track))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // Favorite Button
                Button(action: {
                    if let _ = try? playlistManager.toggleFavorite(forTrackId: track.id) {
                        isFavoriteLocal.toggle()
                    }
                }) {
                    Image(systemName: isFavoriteLocal ? "heart.fill" : "heart")
                        .foregroundColor(isFavoriteLocal ? .red : .white.opacity(isHovered ? 0.4 : 0))
                }
                .buttonStyle(.plain)
                .frame(width: 24)

                Text(formatDuration(track.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onAppear {
            isFavoriteLocal = track.isFavorite
        }
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

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func badgeColor(for track: TrackViewModel) -> Color {
        if track.sampleRate >= 96000 {
            return Color(red: 0.8, green: 0.6, blue: 0.0)
        } else if track.sampleRate > 48000 || track.bitDepth > 16 {
            return .yellow
        }
        return .blue
    }
}
