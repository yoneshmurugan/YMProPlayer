// TracksView.swift
// ytsplayer

import SwiftUI
import GRDB

struct TracksView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playbackVM: PlaybackViewModel

    @State private var allTracks: [TrackViewModel] = []
    @State private var isLoading = true
    
    // Sorting state
    @State private var sortColumn: String = "Title"
    @State private var sortAscending: Bool = true

    // Column visibility (comma-separated string)
    @AppStorage("visibleTrackColumns") private var visibleColumnsString = "Artist,Album,Time"
    
    let availableColumns = ["Artist", "Album", "Type", "Sample Rate", "Bit Depth", "Channels", "Bitrate", "Size", "Time"]

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
                    
                    headerButton("Title", width: nil, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isVisible("Artist") { headerButton("Artist", width: 140, alignment: .leading) }
                    if isVisible("Album") { headerButton("Album", width: 140, alignment: .leading) }
                    if isVisible("Type") { headerButton("Type", width: 60, alignment: .leading) }
                    if isVisible("Sample Rate") { headerButton("Sample Rate", width: 85, alignment: .trailing) }
                    if isVisible("Bit Depth") { headerButton("Bit Depth", width: 70, alignment: .trailing) }
                    if isVisible("Channels") { headerButton("Channels", width: 70, alignment: .trailing) }
                    if isVisible("Bitrate") { headerButton("Bitrate", width: 70, alignment: .trailing) }
                    if isVisible("Size") { headerButton("Size", width: 70, alignment: .trailing) }
                    
                    if isVisible("Time") {
                        headerButton("Time", width: 52, alignment: .trailing)
                            .padding(.trailing, 20)
                    }
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
                    ForEach(availableColumns, id: \.self) { col in
                        Button(action: { toggleColumn(col) }) {
                            if isVisible(col) {
                                Label(col, systemImage: "checkmark")
                            } else {
                                Text(col)
                            }
                        }
                    }
                } label: {
                    Label("Columns", systemImage: "tablecells")
                }
                .help("Select Columns")
            }
        }
        .onAppear { loadTracks() }
        .onChange(of: sortColumn) { _ in loadTracks() }
        .onChange(of: sortAscending) { _ in loadTracks() }
        .onChange(of: libraryVM.albums.count) { _ in loadTracks() }
    }
    
    // MARK: - Helpers
    
    private func isVisible(_ col: String) -> Bool {
        visibleColumnsString.split(separator: ",").map(String.init).contains(col)
    }
    
    private func toggleColumn(_ col: String) {
        var cols = visibleColumnsString.split(separator: ",").map(String.init)
        if cols.contains(col) {
            cols.removeAll { $0 == col }
        } else {
            cols.append(col)
        }
        visibleColumnsString = cols.joined(separator: ",")
    }

    @ViewBuilder
    private func headerButton(_ title: String, width: CGFloat?, alignment: Alignment) -> some View {
        Button(action: {
            if sortColumn == title {
                sortAscending.toggle()
            } else {
                sortColumn = title
                sortAscending = true
            }
        }) {
            HStack(spacing: 4) {
                if alignment == .trailing && sortColumn == title {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(title)
                if alignment == .leading && sortColumn == title {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .frame(width: width, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(sortColumn == title ? .white : .white.opacity(0.4))
    }

    @ViewBuilder
    private func rowView(index: Int, track: TrackViewModel) -> some View {
        let isPlaying = playbackVM.currentTrack?.id == track.id && playbackVM.isPlaying
        let isCurrentTrack = playbackVM.currentTrack?.id == track.id
        TrackRow(
            index: index + 1,
            track: track,
            isPlaying: isPlaying,
            isVisible: isVisible
        )
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
            var tracks: [TrackViewModel] = []
            for album in libraryVM.albums {
                tracks.append(contentsOf: libraryVM.fetchTracks(for: album))
            }

            // Sorting
            tracks.sort { t1, t2 in
                let ascending = sortAscending
                switch sortColumn {
                case "Title":
                    return ascending ? (t1.title < t2.title) : (t1.title > t2.title)
                case "Artist":
                    let a1 = t1.artistName ?? ""
                    let a2 = t2.artistName ?? ""
                    return ascending ? (a1 < a2) : (a1 > a2)
                case "Album":
                    let a1 = t1.albumTitle ?? ""
                    let a2 = t2.albumTitle ?? ""
                    return ascending ? (a1 < a2) : (a1 > a2)
                case "Type":
                    // Derived from extension
                    let e1 = URL(fileURLWithPath: t1.filePath).pathExtension.uppercased()
                    let e2 = URL(fileURLWithPath: t2.filePath).pathExtension.uppercased()
                    return ascending ? (e1 < e2) : (e1 > e2)
                case "Sample Rate":
                    return ascending ? (t1.sampleRate < t2.sampleRate) : (t1.sampleRate > t2.sampleRate)
                case "Bit Depth":
                    return ascending ? (t1.bitDepth < t2.bitDepth) : (t1.bitDepth > t2.bitDepth)
                case "Channels":
                    return ascending ? (t1.channels < t2.channels) : (t1.channels > t2.channels)
                case "Bitrate":
                    let b1 = t1.bitrate ?? 0
                    let b2 = t2.bitrate ?? 0
                    return ascending ? (b1 < b2) : (b1 > b2)
                case "Size":
                    let s1 = t1.fileSize ?? 0
                    let s2 = t2.fileSize ?? 0
                    return ascending ? (s1 < s2) : (s1 > s2)
                case "Time":
                    return ascending ? (t1.duration < t2.duration) : (t1.duration > t2.duration)
                default:
                    return true
                }
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
    var isVisible: (String) -> Bool = { _ in false }
    
    @State private var isHovered = false

    private var artworkURL: URL? {
        guard let path = track.albumArtworkPath,
              let cacheDir = ImageDownsampler.artworkCacheDirectory()
        else { return nil }
        return cacheDir.appendingPathComponent(path)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Index / Play Icon
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

            // Artwork
            if let url = artworkURL {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1))
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(.white.opacity(0.3)))
            }

            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13, weight: isPlaying ? .semibold : .regular))
                    .foregroundStyle(isPlaying ? Color.purple : Color.white)
                    .lineLimit(1)
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Dynamic Columns
            if isVisible("Artist") {
                Text(track.artistName ?? "—")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
            }
            
            if isVisible("Album") {
                Text(track.albumTitle ?? "—")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
            }
            
            if isVisible("Type") {
                Text(URL(fileURLWithPath: track.filePath).pathExtension.uppercased())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.8))
                    .frame(width: 60, alignment: .leading)
            }
            
            if isVisible("Sample Rate") {
                Text(String(format: "%.1f kHz", Double(track.sampleRate) / 1000.0))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 85, alignment: .trailing)
            }
            
            if isVisible("Bit Depth") {
                Text("\(track.bitDepth)-bit")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 70, alignment: .trailing)
            }
            
            if isVisible("Channels") {
                Text(track.channels == 1 ? "Mono" : (track.channels == 2 ? "Stereo" : "\(track.channels) ch"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 70, alignment: .trailing)
            }
            
            if isVisible("Bitrate") {
                if let br = track.bitrate {
                    Text("\(br / 1000) kbps")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 70, alignment: .trailing)
                } else {
                    Text("—")
                        .frame(width: 70, alignment: .trailing)
                }
            }
            
            if isVisible("Size") {
                if let size = track.fileSize {
                    Text(String(format: "%.1f MB", Double(size) / 1_048_576.0))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 70, alignment: .trailing)
                } else {
                    Text("—")
                        .frame(width: 70, alignment: .trailing)
                }
            }

            if isVisible("Time") {
                Text(formatDuration(track.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 52, alignment: .trailing)
                    .padding(.trailing, 20)
            }
        }
        .frame(height: 48)
        .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
