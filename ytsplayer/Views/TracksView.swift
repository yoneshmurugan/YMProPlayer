// TracksView.swift
// ytsplayer

import SwiftUI
import GRDB

struct TracksView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    let playbackVM: PlaybackViewModel
    
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var playlistManager: PlaylistManager

    @State private var allTracks: [TrackViewModel] = []
    @State private var isLoading = true
    @State private var selectedTracks: Set<Int64> = []
    
    @State private var currentTrackId: Int64?
    @State private var isPlaying: Bool = false
    
    // Sorting state
    @State private var sortOrder = [KeyPathComparator(\TrackViewModel.title)]
    
    // Filter state
    @State private var selectedRootFolder: URL? = nil
    
    // Column Customization
    @AppStorage("selectedTracksColumns") private var selectedColumnsData: Data = Data()
    @State private var selectedColumns: Set<String> = ["Artist", "Album", "Type", "Time"]
    
    let availableColumns = ["Artist", "Album", "Type", "Sample Rate", "Bit Depth", "Channels", "Bitrate", "Size", "Views", "Time"]

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
                let totalDuration = allTracks.reduce(0) { $0 + $1.duration }
                Text("\(allTracks.count) tracks • \(formatTotalDuration(totalDuration))")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.15))
            
            // Root Folder Filter
            if !libraryVM.libraryFolders.isEmpty {
                HStack {
                    Text("Location:")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    
                    Picker("", selection: $selectedRootFolder) {
                        Text("All Locations").tag(URL?(nil))
                        ForEach(libraryVM.libraryFolders, id: \.self) { folder in
                            Text(folder.lastPathComponent).tag(URL?(folder))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                    .tint(.purple)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.02))
            }
            
            // Selection Header
            if !selectedTracks.isEmpty {
                HStack {
                    Text("\(selectedTracks.count) selected")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.purple)
                    Spacer()
                    Button("Clear Selection") {
                        selectedTracks.removeAll()
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.1))
            }

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
                Table(of: TrackViewModel.self, selection: $selectedTracks, sortOrder: $sortOrder) {
                    TableColumn("Playing", value: \.id) { track in
                        playingCell(for: track)
                            .onTapGesture {
                                let idx = allTracks.firstIndex(where: { $0.id == track.id }) ?? 0
                                let queueEnd = min(idx + 10, allTracks.count - 1)
                                let queuedTracks = Array(allTracks[idx...queueEnd])
                                playbackVM.play(track: track, queue: queuedTracks, startIndex: 0, context: .allTracks)
                            }
                    }
                    .width(min: 20, ideal: 30, max: 40)
                    
                    TableColumn("Title", value: \.title) { track in
                        titleCell(for: track)
                            .onTapGesture {
                                let idx = allTracks.firstIndex(where: { $0.id == track.id }) ?? 0
                                let queueEnd = min(idx + 10, allTracks.count - 1)
                                let queuedTracks = Array(allTracks[idx...queueEnd])
                                playbackVM.play(track: track, queue: queuedTracks, startIndex: 0, context: .allTracks)
                            }
                    }
                    
                    Group {
                        if selectedColumns.contains("Artist") {
                            TableColumn("Artist", value: \.sortArtist) { artistCell(for: $0) }
                        }
                        if selectedColumns.contains("Album") {
                            TableColumn("Album", value: \.sortAlbum) { albumCell(for: $0) }
                        }
                        if selectedColumns.contains("Type") {
                            TableColumn("Type", value: \.filePath) { typeCell(for: $0) }.width(min: 40, ideal: 50, max: 80)
                        }
                        if selectedColumns.contains("Sample Rate") {
                            TableColumn("Sample Rate", value: \.sampleRate) { sampleRateCell(for: $0) }
                        }
                    }
                    Group {
                        if selectedColumns.contains("Bit Depth") {
                            TableColumn("Bit Depth", value: \.bitDepth) { bitDepthCell(for: $0) }
                        }
                        if selectedColumns.contains("Channels") {
                            TableColumn("Channels", value: \.channels) { channelsCell(for: $0) }
                        }
                        if selectedColumns.contains("Bitrate") {
                            TableColumn("Bitrate", value: \.sortBitrate) { bitrateCell(for: $0) }
                        }
                        if selectedColumns.contains("Size") {
                            TableColumn("Size", value: \.sortSize) { sizeCell(for: $0) }
                        }
                    }
                    Group {
                        if selectedColumns.contains("Views") {
                            TableColumn("Views", value: \.playCount) { viewsCell(for: $0) }
                        }
                        if selectedColumns.contains("Time") {
                            TableColumn("Time", value: \.duration) { timeCell(for: $0) }
                        }
                    }
                    
                    TableColumn("Fav") { favCell(for: $0) }
                        .width(min: 20, ideal: 30, max: 40)
                } rows: {
                    ForEach(allTracks) { track in
                        TableRow(track)
                            .itemProvider {
                                let payload = selectedTracks.contains(track.id) ? 
                                    TrackDropPayload(trackIds: Array(selectedTracks)) : 
                                    TrackDropPayload(trackIds: [track.id])
                                
                                let provider = NSItemProvider()
                                if let data = try? JSONEncoder().encode(payload) {
                                    provider.registerDataRepresentation(forTypeIdentifier: "com.ytsplayer.track.id", visibility: .all) { completion in
                                        completion(data, nil)
                                        return nil
                                    }
                                }
                                return provider
                            }
                    }
                }
                .tableStyle(.inset)
                .contextMenu(forSelectionType: TrackViewModel.ID.self) { items in
                    Button(selectedTracks.isEmpty ? "Select" : "Deselect All") {
                        if selectedTracks.isEmpty {
                            for item in items { selectedTracks.insert(item) }
                        } else {
                            selectedTracks.removeAll()
                        }
                    }
                    Divider()
                    Button("Play Next") {
                        for trackId in items {
                            if let track = allTracks.first(where: { $0.id == trackId }) {
                                playbackVM.playNext(track)
                            }
                        }
                    }
                    Button("Add to Queue") {
                        for trackId in items {
                            if let track = allTracks.first(where: { $0.id == trackId }) {
                                playbackVM.enqueue(track)
                            }
                        }
                    }
                    Divider()
                    Menu("Add to Playlist") {
                        Button("New Playlist...") {
                            if let id = playlistManager.createPlaylist(name: "New Playlist") {
                                playlistManager.addTracks(to: id, trackIds: Array(items))
                                openWindow(id: "PlaylistEditor", value: id)
                            }
                        }
                        if !playlistManager.playlists.isEmpty {
                            Divider()
                            ForEach(playlistManager.playlists) { playlist in
                                Button(playlist.name) {
                                    playlistManager.addTracks(to: playlist.id, trackIds: Array(items))
                                }
                            }
                        }
                    }
                } primaryAction: { items in
                    if let firstId = items.first, let idx = allTracks.firstIndex(where: { $0.id == firstId }) {
                        let queueEnd = min(idx + 10, allTracks.count - 1)
                        let queuedTracks = Array(allTracks[idx...queueEnd])
                        playbackVM.play(track: allTracks[idx], queue: queuedTracks, startIndex: 0, context: .allTracks)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(availableColumns, id: \.self) { col in
                        Button(action: {
                            if selectedColumns.contains(col) {
                                selectedColumns.remove(col)
                            } else {
                                selectedColumns.insert(col)
                            }
                            saveColumns()
                        }) {
                            if selectedColumns.contains(col) {
                                Label(col, systemImage: "checkmark")
                            } else {
                                Text(col)
                            }
                        }
                    }
                } label: {
                    Label("Columns", systemImage: "tablecells")
                }
                .help("Manage Columns")
            }
        }
        .onAppear {
            loadColumns()
            loadTracks()
        }
        .onChange(of: sortOrder) { _ in loadTracks() }
        .onChange(of: libraryVM.albums.count) { _ in loadTracks() }
        .onChange(of: selectedRootFolder) { _ in loadTracks() }
        .onReceive(playbackVM.$currentTrack) { track in
            currentTrackId = track?.id
        }
        .onReceive(playbackVM.$isPlaying) { playing in
            isPlaying = playing
        }
        .onAppear {
            currentTrackId = playbackVM.currentTrack?.id
            isPlaying = playbackVM.isPlaying
        }
    }
    
    // MARK: - Table Cell Helpers
    
    @ViewBuilder private func playingCell(for track: TrackViewModel) -> some View {
        let isCurrent = currentTrackId == track.id
        let isTrackPlaying = isCurrent && isPlaying
        if isTrackPlaying {
            Image(systemName: "waveform")
                .font(.system(size: 11))
                .foregroundStyle(.purple)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Text(track.trackNumber.map { String($0) } ?? "–")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    @ViewBuilder private func titleCell(for track: TrackViewModel) -> some View {
        let isCurrent = currentTrackId == track.id
        Text(track.title)
            .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
            .foregroundStyle(isCurrent ? Color.purple : Color.primary)
            .lineLimit(1)
    }
    
    @ViewBuilder private func artistCell(for track: TrackViewModel) -> some View {
        Text(track.artistName ?? "—").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
    }
    
    @ViewBuilder private func albumCell(for track: TrackViewModel) -> some View {
        Text(track.albumTitle ?? "—").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
    }
    
    @ViewBuilder private func typeCell(for track: TrackViewModel) -> some View {
        Text(URL(fileURLWithPath: track.filePath).pathExtension.uppercased())
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.orange.opacity(0.8))
    }
    
    @ViewBuilder private func sampleRateCell(for track: TrackViewModel) -> some View {
        Text(String(format: "%.1f kHz", Double(track.sampleRate) / 1000.0))
            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
    }
    
    @ViewBuilder private func bitDepthCell(for track: TrackViewModel) -> some View {
        Text("\(track.bitDepth)-bit")
            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
    }
    
    @ViewBuilder private func channelsCell(for track: TrackViewModel) -> some View {
        Text(track.channels == 1 ? "Mono" : (track.channels == 2 ? "Stereo" : "\(track.channels) ch"))
            .font(.system(size: 12)).foregroundStyle(.secondary)
    }
    
    @ViewBuilder private func bitrateCell(for track: TrackViewModel) -> some View {
        if let br = track.bitrate { Text("\(br / 1000) kbps").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }
        else { Text("—") }
    }
    
    @ViewBuilder private func sizeCell(for track: TrackViewModel) -> some View {
        if let size = track.fileSize { Text(String(format: "%.1f MB", Double(size) / 1_048_576.0)).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }
        else { Text("—") }
    }
    
    @ViewBuilder private func viewsCell(for track: TrackViewModel) -> some View {
        Text("\(track.playCount)").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
    }
    
    @ViewBuilder private func timeCell(for track: TrackViewModel) -> some View {
        Text(formatDuration(track.duration)).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
    }
    
    @ViewBuilder private func favCell(for track: TrackViewModel) -> some View {
        Button(action: {
            if let isFav = try? playlistManager.toggleFavorite(forTrackId: track.id) {
                if let idx = allTracks.firstIndex(where: { $0.id == track.id }) {
                    var updatedTrack = track
                    updatedTrack.isFavorite = isFav
                    allTracks[idx] = updatedTrack
                }
            }
        }) {
            Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                .foregroundColor(track.isFavorite ? .red : .gray.opacity(0.4))
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ s: Double) -> String {
        let s = Int(s)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func formatTotalDuration(_ duration: Double) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }

    private func saveColumns() {
        if let data = try? JSONEncoder().encode(Array(selectedColumns)) {
            selectedColumnsData = data
        }
    }

    private func loadColumns() {
        if let decoded = try? JSONDecoder().decode([String].self, from: selectedColumnsData) {
            selectedColumns = Set(decoded)
        }
    }
    
    private func loadTracks() {
        isLoading = true
        Task {
            var tracks: [TrackViewModel] = []
            for album in libraryVM.albums {
                tracks.append(contentsOf: libraryVM.fetchTracks(for: album))
            }
            
            if let root = selectedRootFolder {
                tracks = tracks.filter { $0.filePath.hasPrefix(root.path) }
            }

            tracks.sort(using: sortOrder)

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
    var isSelected: Bool = false
    var selectedTracks: Set<Int64> = []
    var isVisible: (String) -> Bool = { _ in false }
    var onPlayNext: (() -> Void)? = nil
    var onEnqueue: (() -> Void)? = nil
    var onToggleSelection: (() -> Void)? = nil
    var showDragHandle: Bool = false
    var enableExportDrag: Bool = true
    var onDragStarted: (() -> NSItemProvider)? = nil
    
    @State private var isHovered = false
    @State private var isFavoriteLocal = false
    
    @EnvironmentObject var playlistManager: PlaylistManager
    @Environment(\.openWindow) var openWindow

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
            
            if isVisible("Views") {
                Text("\(track.playCount)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 50, alignment: .trailing)
            }
            
            // Favorite Button
            Button(action: {
                if let next = try? playlistManager.toggleFavorite(forTrackId: track.id) {
                    // Ideally we'd have a local @State to update the UI instantly without reloading the entire DB view.
                    // For now, we rely on the DB refresh if any.
                    isFavoriteLocal.toggle()
                }
            }) {
                Image(systemName: isFavoriteLocal ? "heart.fill" : "heart")
                    .foregroundColor(isFavoriteLocal ? .red : .white.opacity(isHovered ? 0.4 : 0))
            }
            .buttonStyle(.plain)
            .frame(width: 30)

            if isVisible("Time") {
                Text(formatDuration(track.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 52, alignment: .trailing)
                    .padding(.trailing, 20)
            }
            
            // Drag Handle
            if showDragHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14))
                    .foregroundStyle(isHovered ? .white.opacity(0.6) : .white.opacity(0.2))
                    .padding(.leading, 8)
                    .contentShape(Rectangle())
                    .onDrag {
                        onDragStarted?() ?? NSItemProvider()
                    }
            }
        }
        .frame(height: 48)
        .background(isHovered || isSelected ? Color.white.opacity(isSelected ? 0.15 : 0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .onAppear {
            isFavoriteLocal = track.isFavorite
        }
        .modifier(DraggableModifier(
            isEnabled: enableExportDrag,
            payload: selectedTracks.contains(track.id) && selectedTracks.count > 1
                ? TrackDropPayload(trackIds: Array(selectedTracks))
                : TrackDropPayload(trackIds: [track.id])
        ))
        .contextMenu {
            Button(isSelected ? "Deselect" : "Select") {
                onToggleSelection?()
            }
            Divider()
            Button("Play Next") {
                onPlayNext?()
            }
            Button("Add to Queue") {
                onEnqueue?()
            }
            Divider()
            Menu("Add to Playlist") {
                Button("New Playlist...") {
                    let tracksToAdd = selectedTracks.contains(track.id) && selectedTracks.count > 1 ? Array(selectedTracks) : [track.id]
                    if let id = playlistManager.createPlaylist(name: "New Playlist") {
                        playlistManager.addTracks(to: id, trackIds: tracksToAdd)
                        openWindow(id: "PlaylistEditor", value: id)
                    }
                }
                
                if !playlistManager.playlists.isEmpty {
                    Divider()
                    ForEach(playlistManager.playlists) { playlist in
                        Button(playlist.name) {
                            let tracksToAdd = selectedTracks.contains(track.id) && selectedTracks.count > 1 ? Array(selectedTracks) : [track.id]
                            playlistManager.addTracks(to: playlist.id, trackIds: tracksToAdd)
                            openWindow(id: "PlaylistEditor", value: playlist.id)
                        }
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct DraggableModifier: ViewModifier {
    let isEnabled: Bool
    let payload: TrackDropPayload
    
    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(payload)
        } else {
            content
        }
    }
}
