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
            ZStack(alignment: .bottomLeading) {
                // Blurred artwork background
                if let path = album.artworkCachePath,
                   let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                    AsyncImage(url: cacheDir.appendingPathComponent(path)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: { Color.clear }
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
                    artworkView
                        .frame(width: 130, height: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 16)

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
            .frame(height: 220)

            // ── Track List ─────────────────────────────────────────────────
            List(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(
                    track: track,
                    isPlaying: playbackVM.currentTrack?.id == track.id && playbackVM.isPlaying
                )
                .listRowBackground(
                    playbackVM.currentTrack?.id == track.id
                        ? Color.purple.opacity(0.12)
                        : Color.clear
                )
                .onTapGesture {
                    playbackVM.play(track: track, queue: tracks, startIndex: index)
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
            AsyncImage(url: cacheDir.appendingPathComponent(path)) { img in
                img.resizable().scaledToFill()
            } placeholder: { placeholderArt }
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

// MARK: - Track Row

struct TrackRow: View {
    let track: TrackViewModel
    let isPlaying: Bool

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
                Text(ext.isEmpty ? "FLAC" : ext)
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

                Text(formatDuration(track.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
