// TracksView.swift
// ytsplayer

import SwiftUI
import GRDB

struct TracksView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playbackVM: PlaybackViewModel

    @State private var allTracks: [TrackViewModel] = []
    @State private var isLoading = true
    @State private var sortOrder: TrackSortOrder = .titleAsc

    enum TrackSortOrder: String, CaseIterable {
        case titleAsc  = "Title (A–Z)"
        case titleDesc = "Title (Z–A)"
        case artist    = "Artist"
        case album     = "Album"
        case duration  = "Duration"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Text("Library")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Tracks")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text("\(allTracks.count) tracks")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.15))

            if isLoading {
                Spacer()
                ProgressView()
                    .tint(.purple)
                Spacer()
            } else if allTracks.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("No Tracks")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
            } else {
                // Column header
                HStack(spacing: 0) {
                    Text("#").frame(width: 36, alignment: .center)
                    Text("Title").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Artist").frame(width: 160, alignment: .leading)
                    Text("Album").frame(width: 160, alignment: .leading)
                    Text("Time").frame(width: 52, alignment: .trailing).padding(.trailing, 20)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.03))

                Divider().background(Color.white.opacity(0.1))

                List {
                    ForEach(Array(allTracks.enumerated()), id: \.element.id) { index, track in
                        rowView(index: index, track: track)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort By", selection: $sortOrder) {
                        ForEach(TrackSortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .onAppear { loadTracks() }
        .onChange(of: sortOrder) { _ in loadTracks() }
        .onChange(of: libraryVM.albums.count) { _ in loadTracks() }
    }

    @ViewBuilder
    private func rowView(index: Int, track: TrackViewModel) -> some View {
        let isPlaying = playbackVM.currentTrack?.id == track.id && playbackVM.isPlaying
        let isCurrentTrack = playbackVM.currentTrack?.id == track.id
        TrackRow(index: index + 1, track: track, isPlaying: isPlaying)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                playbackVM.play(track: track, queue: allTracks, startIndex: index)
            }
            .listRowBackground(isCurrentTrack ? Color.purple.opacity(0.15) : Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
    }

    private func loadTracks() {
        isLoading = true
        Task {
            // Collect all tracks from all albums
            var tracks: [TrackViewModel] = []
            for album in libraryVM.albums {
                let albumTracks = libraryVM.fetchTracks(for: album)
                tracks.append(contentsOf: albumTracks)
            }

            switch sortOrder {
            case .titleAsc:
                tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case .titleDesc:
                tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
            case .artist:
                tracks.sort { ($0.artistName ?? "").localizedCaseInsensitiveCompare($1.artistName ?? "") == .orderedAscending }
            case .album:
                tracks.sort { ($0.albumTitle ?? "").localizedCaseInsensitiveCompare($1.albumTitle ?? "") == .orderedAscending }
            case .duration:
                tracks.sort { $0.duration < $1.duration }
            }

            await MainActor.run {
                allTracks = tracks
                isLoading = false
            }
        }
    }
}

// MARK: - Track Row

struct TrackRow: View {
    let index: Int
    let track: TrackViewModel
    let isPlaying: Bool
    @State private var isHovered = false

    private var artworkURL: URL? {
        guard let path = track.albumArtworkPath,
              let cacheDir = ImageDownsampler.artworkCacheDirectory()
        else { return nil }
        return cacheDir.appendingPathComponent(path)
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                        .foregroundStyle(.purple)
                } else {
                    Text("\(index)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(isHovered ? 0.8 : 0.35))
                }
            }
            .frame(width: 36, alignment: .center)

            // Artwork thumbnail
            if let url = artworkURL {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.3))
                    )
            }

            // Title + badges
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .font(.system(size: 13, weight: isPlaying ? .semibold : .regular))
                        .foregroundStyle(isPlaying ? Color.purple : Color.white)
                        .lineLimit(1)
                    if track.bitDepth >= 24 {
                        Text("HI-RES")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Artist
            Text(track.artistName ?? "—")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            // Album
            Text(track.albumTitle ?? "—")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            // Duration
            Text(formatDuration(track.duration))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 52, alignment: .trailing)
                .padding(.trailing, 20)
        }
        .frame(height: 52)
        .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
