// TracksView.swift
// ytsplayer

import SwiftUI
import GRDB

struct MenuFolderNode: Identifiable, Hashable {
    let id: URL
    let name: String
    var children: [MenuFolderNode] = []
}

func buildFolderTree(tracks: [TrackViewModel], roots: [URL]) -> [MenuFolderNode] {
    var dirURLs = Set<URL>()
    for track in tracks {
        dirURLs.insert(URL(fileURLWithPath: track.filePath).deletingLastPathComponent())
    }
    
    var allDirs = Set<URL>()
    for var dir in dirURLs {
        while dir.path.count > 1 {
            allDirs.insert(dir)
            if roots.contains(dir) { break }
            dir = dir.deletingLastPathComponent()
        }
    }
    
    let validDirs = allDirs.filter { dir in roots.contains(where: { dir.path.hasPrefix($0.path) }) }
    
    var childrenByParent = [URL: [URL]]()
    for dir in validDirs {
        let parent = dir.deletingLastPathComponent()
        childrenByParent[parent, default: []].append(dir)
    }
    
    func assembleNode(for url: URL) -> MenuFolderNode {
        let kids = childrenByParent[url] ?? []
        let sortedKids = kids.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        return MenuFolderNode(
            id: url,
            name: url.lastPathComponent,
            children: sortedKids.map { assembleNode(for: $0) }
        )
    }
    
    return roots.map { assembleNode(for: $0) }
}

func flatten(_ nodes: [MenuFolderNode]) -> [MenuFolderNode] {
    var result = [MenuFolderNode]()
    for node in nodes {
        result.append(node)
        result.append(contentsOf: flatten(node.children))
    }
    return result
}

struct ExpandableFolderRow: View {
    let node: MenuFolderNode
    let depth: Int
    @Binding var expandedFolders: Set<URL>
    let selectedFolder: URL?
    let onSelect: (URL) -> Void
    
    var body: some View {
        let isExpanded = expandedFolders.contains(node.id)
        let hasChildren = !node.children.isEmpty
        let isSelected = node.id == selectedFolder
        
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                // Indent
                Spacer().frame(width: CGFloat(depth * 16))
                
                // Chevron
                if hasChildren {
                    Button(action: {
                        if isExpanded {
                            expandedFolders.remove(node.id)
                        } else {
                            expandedFolders.insert(node.id)
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 16)
                }
                
                // Folder Name (Click to select)
                Button(action: {
                    onSelect(node.id)
                }) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.purple.opacity(0.8))
                        Text(node.name)
                            .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? .purple : .primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.purple.opacity(0.15) : Color.clear)
            
            if isExpanded {
                ForEach(node.children) { child in
                    ExpandableFolderRow(
                        node: child,
                        depth: depth + 1,
                        expandedFolders: $expandedFolders,
                        selectedFolder: selectedFolder,
                        onSelect: onSelect
                    )
                }
            }
        }
    }
}



struct TracksView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    let playbackVM: PlaybackViewModel
    var onSearchTapped: (() -> Void)? = nil
    
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
    // Filter state
    @State private var selectedRootFolder: URL? = nil
    @State private var folderTree: [MenuFolderNode] = []
    @State private var expandedFolders: Set<URL> = []
    @State private var isShowingFolderPicker = false
    @State private var folderSearchQuery = ""
    
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                
                if let onSearchTapped = onSearchTapped {
                        Button(action: onSearchTapped) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .padding(.trailing, 16)
                    }
                    
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
                    
                    Button(action: {
                        isShowingFolderPicker.toggle()
                    }) {
                        HStack {
                            Text(selectedRootFolder?.lastPathComponent ?? "All Locations")
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 250)
                    .popover(isPresented: $isShowingFolderPicker, arrowEdge: .bottom) {
                        VStack(spacing: 0) {
                            // Search bar
                            HStack {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                TextField("Search folders...", text: $folderSearchQuery)
                                    .textFieldStyle(.plain)
                            }
                            .padding(10)
                            .background(Color.black.opacity(0.2))
                            
                            Divider()
                            
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    Button(action: {
                                        selectedRootFolder = nil
                                        isShowingFolderPicker = false
                                    }) {
                                        Text("All Locations")
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if folderSearchQuery.isEmpty {
                                        ForEach(folderTree) { rootNode in
                                            ExpandableFolderRow(
                                                node: rootNode,
                                                depth: 0,
                                                expandedFolders: $expandedFolders,
                                                selectedFolder: selectedRootFolder,
                                                onSelect: { url in
                                                    selectedRootFolder = url
                                                    isShowingFolderPicker = false
                                                }
                                            )
                                        }
                                    } else {
                                        let allNodes = flatten(folderTree)
                                        let filtered = allNodes.filter { $0.name.localizedCaseInsensitiveContains(folderSearchQuery) }
                                        ForEach(filtered) { node in
                                            Button(action: {
                                                selectedRootFolder = node.id
                                                isShowingFolderPicker = false
                                            }) {
                                                HStack {
                                                    Image(systemName: "folder.fill")
                                                        .foregroundStyle(.purple.opacity(0.8))
                                                    Text(node.name)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: 300, height: 400)
                    }
                    
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
                headerRow
                Divider().background(Color.white.opacity(0.1))
                
                List(selection: $selectedTracks) {
                    ForEach(allTracks, id: \.id) { track in
                        TracksTableRow(
                            track: track,
                            selectedColumns: selectedColumns,
                            isCurrentTrack: currentTrackId == track.id,
                            isPlaying: currentTrackId == track.id && isPlaying,
                            onToggleFavorite: {
                                if let isFav = try? playlistManager.toggleFavorite(forTrackId: track.id) {
                                    if let idx = allTracks.firstIndex(where: { $0.id == track.id }) {
                                        var updatedTrack = track
                                        updatedTrack.isFavorite = isFav
                                        allTracks[idx] = updatedTrack
                                    }
                                }
                            }
                        )
                        .equatable()
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .tag(track.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
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
                        let slice = allTracks[idx...queueEnd]
                        let queuedTracks = Array(slice)
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
            loadTracks(for: selectedRootFolder)
        }
        .onChange(of: sortOrder) { _ in
            loadTracks(for: selectedRootFolder)
        }
        .onChange(of: libraryVM.albums.count) { _ in loadTracks(for: selectedRootFolder) }
        .onChange(of: selectedRootFolder) { newValue in loadTracks(for: newValue) }
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
    
    @ViewBuilder
    private func sortButton(title: String, keyPath: AnyKeyPath, comparator: KeyPathComparator<TrackViewModel>, width: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
        Button(action: {
            if let current = sortOrder.first, current.keyPath == keyPath {
                let order: SortOrder = current.order == .forward ? .reverse : .forward
                var newComparator = comparator
                newComparator.order = order
                sortOrder = [newComparator]
            } else {
                sortOrder = [comparator]
            }
        }) {
            HStack(spacing: 4) {
                if alignment == .trailing { Spacer() }
                Text(title)
                if let current = sortOrder.first, current.keyPath == keyPath {
                    Image(systemName: current.order == .forward ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                if alignment == .leading { Spacer() }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
        .frame(width: width)
    }
    
    private var headerRow: some View {
        HStack(spacing: 16) {
            sortButton(title: "Title", keyPath: \TrackViewModel.title, comparator: KeyPathComparator(\.title))
            if selectedColumns.contains("Artist") { sortButton(title: "Artist", keyPath: \TrackViewModel.artistName, comparator: KeyPathComparator(\.artistName), width: 140) }
            if selectedColumns.contains("Album") { sortButton(title: "Album", keyPath: \TrackViewModel.albumTitle, comparator: KeyPathComparator(\.albumTitle), width: 140) }
            if selectedColumns.contains("Type") { sortButton(title: "Type", keyPath: \TrackViewModel.filePath, comparator: KeyPathComparator(\.filePath), width: 60) }
            if selectedColumns.contains("Sample Rate") { sortButton(title: "Sample Rate", keyPath: \TrackViewModel.sampleRate, comparator: KeyPathComparator(\.sampleRate), width: 85, alignment: .trailing) }
            if selectedColumns.contains("Bit Depth") { sortButton(title: "Bit Depth", keyPath: \TrackViewModel.bitDepth, comparator: KeyPathComparator(\.bitDepth), width: 70, alignment: .trailing) }
            if selectedColumns.contains("Channels") { sortButton(title: "Channels", keyPath: \TrackViewModel.channels, comparator: KeyPathComparator(\.channels), width: 70, alignment: .trailing) }
            if selectedColumns.contains("Bitrate") { sortButton(title: "Bitrate", keyPath: \TrackViewModel.bitrate, comparator: KeyPathComparator(\.bitrate), width: 70, alignment: .trailing) }
            if selectedColumns.contains("Size") { sortButton(title: "Size", keyPath: \TrackViewModel.fileSize, comparator: KeyPathComparator(\.fileSize), width: 70, alignment: .trailing) }
            if selectedColumns.contains("Views") { sortButton(title: "Views", keyPath: \TrackViewModel.playCount, comparator: KeyPathComparator(\.playCount), width: 50, alignment: .trailing) }
            if selectedColumns.contains("Time") { sortButton(title: "Time", keyPath: \TrackViewModel.duration, comparator: KeyPathComparator(\.duration), width: 52, alignment: .trailing) }
            Text("Fav").frame(width: 30)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.5))
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.15))
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

    @ViewBuilder private func trackContextMenu(for track: TrackViewModel) -> some View {
        Button(selectedTracks.isEmpty ? "Select" : "Deselect All") {
            if selectedTracks.isEmpty {
                selectedTracks.insert(track.id)
            } else {
                selectedTracks.removeAll()
            }
        }
        Divider()
        Button("Play Next") {
            let targets = selectedTracks.contains(track.id) ? Array(selectedTracks) : [track.id]
            for trackId in targets {
                if let t = allTracks.first(where: { $0.id == trackId }) {
                    playbackVM.playNext(t)
                }
            }
        }
        Button("Add to Queue") {
            let targets = selectedTracks.contains(track.id) ? Array(selectedTracks) : [track.id]
            for trackId in targets {
                if let t = allTracks.first(where: { $0.id == trackId }) {
                    playbackVM.enqueue(t)
                }
            }
        }
        Divider()
        Menu("Add to Playlist") {
            Button("New Playlist...") {
                if let id = playlistManager.createPlaylist(name: "New Playlist") {
                    let targets = selectedTracks.contains(track.id) ? Array(selectedTracks) : [track.id]
                    playlistManager.addTracks(to: id, trackIds: targets)
                    openWindow(id: "PlaylistEditor", value: id)
                }
            }
            if !playlistManager.playlists.isEmpty {
                Divider()
                ForEach(playlistManager.playlists) { playlist in
                    Button(playlist.name) {
                        let targets = selectedTracks.contains(track.id) ? Array(selectedTracks) : [track.id]
                        playlistManager.addTracks(to: playlist.id, trackIds: targets)
                    }
                }
            }
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
    
    private func loadTracks(for root: URL?) {
        isLoading = true
        Task {
            let allLibraryTracks = libraryVM.fetchAllTracks()
            let tree = buildFolderTree(tracks: allLibraryTracks, roots: libraryVM.libraryFolders)
            
            var tracks = allLibraryTracks
            if let r = root {
                tracks = tracks.filter { $0.filePath.hasPrefix(r.path) }
            }

            tracks.sort(using: sortOrder)

            await MainActor.run {
                self.selectedRootFolder = root
                self.folderTree = tree
                self.allTracks = tracks
                self.isLoading = false
            }
        }
    }
}

// MARK: - Track Row

struct TrackRow: View, Equatable {
    static func == (lhs: TrackRow, rhs: TrackRow) -> Bool {
        lhs.track.id == rhs.track.id &&
        lhs.isPlaying == rhs.isPlaying &&
        lhs.isSelected == rhs.isSelected &&
        lhs.selectedTracks == rhs.selectedTracks
    }
    
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

// MARK: - TracksTableRow (Equatable)

struct TracksTableRow: View, Equatable {
    let track: TrackViewModel
    let selectedColumns: Set<String>
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let onToggleFavorite: () -> Void
    
    static func == (lhs: TracksTableRow, rhs: TracksTableRow) -> Bool {
        lhs.track == rhs.track &&
        lhs.selectedColumns == rhs.selectedColumns &&
        lhs.isCurrentTrack == rhs.isCurrentTrack &&
        lhs.isPlaying == rhs.isPlaying
    }
    
    var body: some View {
        HStack(spacing: 16) {
            playingCell.frame(width: 30)
            titleCell.frame(maxWidth: .infinity, alignment: .leading)
            if selectedColumns.contains("Artist") { artistCell.frame(width: 140, alignment: .leading) }
            if selectedColumns.contains("Album") { albumCell.frame(width: 140, alignment: .leading) }
            if selectedColumns.contains("Type") { typeCell.frame(width: 60, alignment: .leading) }
            if selectedColumns.contains("Sample Rate") { sampleRateCell.frame(width: 85, alignment: .trailing) }
            if selectedColumns.contains("Bit Depth") { bitDepthCell.frame(width: 70, alignment: .trailing) }
            if selectedColumns.contains("Channels") { channelsCell.frame(width: 70, alignment: .trailing) }
            if selectedColumns.contains("Bitrate") { bitrateCell.frame(width: 70, alignment: .trailing) }
            if selectedColumns.contains("Size") { sizeCell.frame(width: 70, alignment: .trailing) }
            if selectedColumns.contains("Views") { viewsCell.frame(width: 50, alignment: .trailing) }
            if selectedColumns.contains("Time") { timeCell.frame(width: 52, alignment: .trailing) }
            favCell.frame(width: 30)
        }
    }
    
    @ViewBuilder private var playingCell: some View {
        if isPlaying {
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
    
    @ViewBuilder private var titleCell: some View {
        Text(track.title)
            .font(.system(size: 13, weight: isCurrentTrack ? .semibold : .regular))
            .foregroundStyle(isCurrentTrack ? Color.purple : Color.primary)
            .lineLimit(1)
    }
    
    @ViewBuilder private var artistCell: some View {
        Text(track.artistName ?? "—").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
    }
    
    @ViewBuilder private var albumCell: some View {
        Text(track.albumTitle ?? "—").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
    }
    
    @ViewBuilder private var typeCell: some View {
        Text(URL(fileURLWithPath: track.filePath).pathExtension.uppercased())
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.orange.opacity(0.8))
    }
    
    @ViewBuilder private var sampleRateCell: some View {
        Text(String(format: "%.1f kHz", Double(track.sampleRate) / 1000.0))
            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
    }
    
    @ViewBuilder private var bitDepthCell: some View {
        Text("\(track.bitDepth)-bit")
            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
    }
    
    @ViewBuilder private var channelsCell: some View {
        Text(track.channels == 1 ? "Mono" : (track.channels == 2 ? "Stereo" : "\(track.channels) ch"))
            .font(.system(size: 12)).foregroundStyle(.secondary)
    }
    
    @ViewBuilder private var bitrateCell: some View {
        if let br = track.bitrate { Text("\(br / 1000) kbps").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }
        else { Text("—") }
    }
    
    @ViewBuilder private var sizeCell: some View {
        if let size = track.fileSize { Text(String(format: "%.1f MB", Double(size) / 1_048_576.0)).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }
        else { Text("—") }
    }
    
    @ViewBuilder private var viewsCell: some View {
        Text("\(track.playCount)").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
    }
    
    @ViewBuilder private var timeCell: some View {
        let s = Int(track.duration)
        Text(String(format: "%d:%02d", s / 60, s % 60)).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
    }
    
    @ViewBuilder private var favCell: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                .foregroundColor(track.isFavorite ? .red : .gray.opacity(0.4))
        }
        .buttonStyle(.plain)
    }
}
