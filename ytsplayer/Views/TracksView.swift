// TracksView.swift
// ytsplayer

import SwiftUI
import GRDB
import AppKit

struct MenuFolderNode: Identifiable, Hashable {
    let id: URL
    let name: String
    var children: [MenuFolderNode] = []
}

func buildFolderTree(paths: [String], roots: [URL]) -> [MenuFolderNode] {
    var dirURLs = Set<URL>()
    for path in paths {
        dirURLs.insert(URL(fileURLWithPath: path).deletingLastPathComponent())
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
    let selectedFolder: Binding<URL?>
    let onSelect: (URL) -> Void
    
    var isExpanded: Bool { expandedFolders.contains(node.id) }
    var isSelected: Bool { selectedFolder.wrappedValue == node.id }
    
    var body: some View {
        let hasChildren = !node.children.isEmpty
        
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
    @State private var trackOffset: Int = 0
    @State private var hasMoreTracks: Bool = true
    let pageSize = 5000
    @State private var isLoading = true
    @State private var selectedTracks: Set<Int64> = []
    @State private var isSelectionMode = false
    @State private var lastSelectedIndex: Int? = nil
    
    @State private var currentTrackId: Int64?
    @State private var isPlaying: Bool = false
    
    // Sorting state
    // Filter state
    private var selectedRootFolder: Binding<URL?> {
        $libraryVM.tracksSelectedRootFolder
    }
    private var expandedFolders: Binding<Set<URL>> {
        $libraryVM.tracksExpandedFolders
    }
    private var folderSearchQuery: Binding<String> {
        $libraryVM.tracksFolderSearchQuery
    }
    
    @State private var folderTree: [MenuFolderNode] = []
    @State private var isShowingFolderPicker = false
    
    // Column Customization
    // Table State
    @State private var sortOrder: [KeyPathComparator<TrackViewModel>] = [KeyPathComparator(\.title)]
    @State private var columnCustomization = TableColumnCustomization<TrackViewModel>()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Text("Library")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.5))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.3))
                    Text("Tracks")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                
                if isSelectionMode {
                    Button(action: {
                        if selectedTracks.count == allTracks.count {
                            selectedTracks.removeAll()
                        } else {
                            selectedTracks = Set(allTracks.map { $0.id })
                        }
                    }) {
                        Text(selectedTracks.count == allTracks.count ? "Deselect All" : "Select All")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }
                
                Button(action: {
                    withAnimation { isSelectionMode.toggle() }
                    if !isSelectionMode { selectedTracks.removeAll() }
                }) {
                    Text(isSelectionMode ? "Done" : "Select")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelectionMode ? Color.purple : Color.primary.opacity(0.8))
                }
                .buttonStyle(.plain)
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
                    
                let totalDuration = allTracks.reduce(0) { $0 + $1.duration }
                let totalSize = allTracks.reduce(0) { $0 + ($1.fileSize ?? 0) }
                Text("\(allTracks.count) tracks • \(formatTotalDuration(totalDuration)) • \(formatSize(totalSize))")
                    .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.15))
            
            // Root Folder Filter
            if !libraryVM.libraryFolders.isEmpty {
                HStack {
                    Text("Location:")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.6))
                    
                    Button(action: {
                        isShowingFolderPicker.toggle()
                    }) {
                        HStack {
                            Text(selectedRootFolder.wrappedValue?.lastPathComponent ?? "All Locations")
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                                .foregroundStyle(.primary.opacity(0.5))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 250)
                    .popover(isPresented: $isShowingFolderPicker, arrowEdge: .bottom) {
                        VStack(spacing: 0) {
                            // Search bar
                            HStack {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                TextField("Search folders...", text: folderSearchQuery)
                                    .textFieldStyle(.plain)
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.2))
                            
                            Divider()
                            
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    Button(action: {
                                        selectedRootFolder.wrappedValue = nil
                                        isShowingFolderPicker = false
                                    }) {
                                        Text("All Locations")
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if folderSearchQuery.wrappedValue.isEmpty {
                                        ForEach(folderTree) { rootNode in
                                            ExpandableFolderRow(
                                                node: rootNode,
                                                depth: 0,
                                                expandedFolders: expandedFolders,
                                                selectedFolder: selectedRootFolder,
                                                onSelect: { url in
                                                    selectedRootFolder.wrappedValue = url
                                                    isShowingFolderPicker = false
                                                }
                                            )
                                        }
                                    } else {
                                        let allNodes = flatten(folderTree)
                                        let filtered = allNodes.filter { $0.name.localizedCaseInsensitiveContains(folderSearchQuery.wrappedValue) }
                                        ForEach(filtered) { node in
                                            Button(action: {
                                                selectedRootFolder.wrappedValue = node.id
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
                .background(Color.primary.opacity(0.02))
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
                    .foregroundStyle(.primary.opacity(0.6))
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
                        .foregroundStyle(.primary.opacity(0.2))
                    Text("No Tracks")
                        .font(.title2)
                        .foregroundStyle(.primary.opacity(0.4))
                }
                Spacer()
            } else {
                tracksTableView
            }
        }
        .onAppear {
            loadTracks(for: selectedRootFolder.wrappedValue, forceRefresh: false)
        }
        .onChange(of: sortOrder) { _ in
            loadTracks(for: selectedRootFolder.wrappedValue, forceRefresh: true)
        }
        .onChange(of: libraryVM.albums.count) { _ in loadTracks(for: selectedRootFolder.wrappedValue, forceRefresh: true) }
        .onChange(of: selectedRootFolder.wrappedValue) { newRoot in
            loadTracks(for: newRoot, forceRefresh: true)
        }
        .onChange(of: folderSearchQuery.wrappedValue) { _ in
            loadTracks(for: selectedRootFolder.wrappedValue, forceRefresh: true)
        }
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
    private var tracksTableView: some View {
        Table(allTracks, selection: $selectedTracks, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("#", value: \.sortTrackNumber) { track in
                if isSelectionMode {
                    Image(systemName: selectedTracks.contains(track.id) ? "checkmark.square.fill" : "square")
                        .foregroundColor(selectedTracks.contains(track.id) ? .purple : .secondary)
                        .font(.system(size: 14))
                        .onTapGesture {
                            let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
                            if let currentIndex = allTracks.firstIndex(where: { $0.id == track.id }) {
                                if isShiftPressed, let lastIdx = lastSelectedIndex {
                                    let range = min(currentIndex, lastIdx)...max(currentIndex, lastIdx)
                                    for i in range {
                                        selectedTracks.insert(allTracks[i].id)
                                    }
                                } else {
                                    if selectedTracks.contains(track.id) {
                                        selectedTracks.remove(track.id)
                                    } else {
                                        selectedTracks.insert(track.id)
                                    }
                                    lastSelectedIndex = currentIndex
                                }
                            }
                        }
                } else {
                    Text(track.trackNumber.map { String($0) } ?? "—").foregroundStyle(.secondary)
                }
            }
            .width(min: 30, ideal: 40)
            .customizationID("TrackNumber")
            
            TableColumn("Title", value: \.title) { track in
                trackTitleView(for: track)
                    .onAppear {
                        if track.id == allTracks.last?.id {
                            loadMoreTracks()
                        }
                    }
            }
            .width(min: 200, ideal: 300)
            .customizationID("Title")
            
            TableColumn("Artist", value: \.sortArtist) { track in
                Text(track.artistName ?? "—").foregroundStyle(.secondary)
            }
            .width(min: 150, ideal: 200)
            .customizationID("Artist")
            
            TableColumn("Album", value: \.sortAlbum) { track in
                Text(track.albumTitle ?? "—").foregroundStyle(.secondary)
            }
            .width(min: 150, ideal: 200)
            .customizationID("Album")
            
            TableColumn("Type", value: \.sortType) { track in
                trackTypeView(for: track)
            }
            .width(min: 60, ideal: 80)
            .customizationID("Type")
            
            TableColumn("Quality", value: \.sampleRate) { track in
                Text(String(format: "%.1f kHz / %d-bit", Double(track.sampleRate) / 1000.0, track.bitDepth))
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 120)
            .customizationID("Quality")
            
            TableColumn("Size", value: \.sortSize) { track in
                Text(track.fileSize.map { formatSize($0) } ?? "—").foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
            .customizationID("Size")
            
            TableColumn("Bitrate", value: \.sortBitrate) { track in
                Text(track.bitrate.map { "\($0 / 1000) kbps" } ?? "—").foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)
            .customizationID("Bitrate")
            
            TableColumn("Time", value: \.duration) { track in
                trackTimeView(for: track)
            }
            .width(min: 60, ideal: 80)
            .customizationID("Time")
            
            TableColumn("Plays", value: \.playCount) { track in
                Text("\(track.playCount)").foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60)
            .customizationID("Plays")
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: TrackViewModel.ID.self) { (items: Set<TrackViewModel.ID>) in
            tracksContextMenu(for: items)
        } primaryAction: { (items: Set<TrackViewModel.ID>) in
            handlePrimaryAction(for: items)
        }
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
    
    private func formatSize(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b > 1_073_741_824 { return String(format: "%.2f GB", b / 1_073_741_824) }
        if b > 1_048_576 { return String(format: "%.1f MB", b / 1_048_576) }
        return String(format: "%.0f KB", b / 1024)
    }
    
    @ViewBuilder
    private func trackTitleView(for track: TrackViewModel) -> some View {
        HStack(spacing: 8) {
            if let path = track.albumArtworkPath, let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                CachedAsyncImage(url: cacheDir.appendingPathComponent(path)) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1))
                }
                .frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08))
                    .frame(width: 24, height: 24)
                    .overlay(Image(systemName: "music.note").font(.system(size: 10)).foregroundStyle(.primary.opacity(0.3)))
            }
            Text(track.title)
                .font(.system(size: 13, weight: currentTrackId == track.id ? .semibold : .regular))
                .foregroundStyle(currentTrackId == track.id ? Color.purple : Color.primary)
            
            if track.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 11))
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    @ViewBuilder
    private func trackTypeView(for track: TrackViewModel) -> some View {
        Text(URL(fileURLWithPath: track.filePath).pathExtension.uppercased())
            .foregroundStyle(Color.orange.opacity(0.8))
    }
    
    @ViewBuilder
    private func trackTimeView(for track: TrackViewModel) -> some View {
        let s = Int(track.duration)
        Text(String(format: "%d:%02d", s / 60, s % 60)).foregroundStyle(.secondary)
    }
    
    @ViewBuilder
    private func trackFavView(for track: TrackViewModel) -> some View {
        Button(action: {
            if let isFav = try? playlistManager.toggleFavorite(forTrackId: track.id) {
                if let idx = allTracks.firstIndex(where: { $0.id == track.id }) {
                    allTracks[idx].isFavorite = isFav
                }
            }
        }) {
            Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                .foregroundColor(track.isFavorite ? .red : .gray.opacity(0.4))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func tracksContextMenu(for items: Set<TrackViewModel.ID>) -> some View {
        Button(selectedTracks.isEmpty ? "Select" : "Deselect All") {
            if selectedTracks.isEmpty {
                for item in items { selectedTracks.insert(item) }
            } else {
                selectedTracks.removeAll()
            }
        }
        Button("Toggle Favorite") {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                for trackId in items {
                    if let idx = allTracks.firstIndex(where: { $0.id == trackId }) {
                        allTracks[idx].isFavorite.toggle()
                        _ = try? playlistManager.toggleFavorite(forTrackId: trackId)
                    }
                }
                libraryVM.cachedTracks = allTracks // update cache
            }
        }
        Divider()
        Button("Show in Finder") {
            let urls = items.compactMap { id -> URL? in
                guard let track = allTracks.first(where: { $0.id == id }) else { return nil }
                return URL(fileURLWithPath: track.filePath)
            }
            if !urls.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
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
    }
    
    private func handlePrimaryAction(for items: Set<TrackViewModel.ID>) {
        if let firstId = items.first, let idx = allTracks.firstIndex(where: { $0.id == firstId }) {
            let queueEnd = min(idx + 10, allTracks.count - 1)
            let slice = allTracks[idx...queueEnd]
            let queuedTracks = Array(slice)
            playbackVM.play(track: allTracks[idx], queue: queuedTracks, startIndex: 0, context: .allTracks)
        }
    }

    
    
    private func sqlSortField() -> String {
        guard let sortDesc = sortOrder.first else { return "title" }
        switch sortDesc.keyPath {
        case \TrackViewModel.sortArtist: return "sortArtist"
        case \TrackViewModel.sortAlbum: return "sortAlbum"
        case \TrackViewModel.title: return "title"
        case \TrackViewModel.sortSize: return "sortSize"
        case \TrackViewModel.sortType: return "sortType"
        case \TrackViewModel.duration: return "duration"
        case \TrackViewModel.sampleRate: return "sampleRate"
        case \TrackViewModel.sortTrackNumber: return "sortTrackNumber"
        default: return "title"
        }
    }

    private func loadTracks(for root: URL?, forceRefresh: Bool = false) {
        if !forceRefresh, let cached = libraryVM.cachedTracks, root == selectedRootFolder.wrappedValue {
            self.allTracks = cached
            self.trackOffset = libraryVM.cachedTrackOffset
            self.hasMoreTracks = libraryVM.cachedHasMoreTracks
            if let cachedPaths = libraryVM.cachedFolderPaths {
                self.folderTree = buildFolderTree(paths: cachedPaths, roots: libraryVM.libraryFolders)
            }
            self.isLoading = false
            return
        }
        
        if forceRefresh || root != selectedRootFolder.wrappedValue {
            trackOffset = 0
            hasMoreTracks = true
            allTracks = []
        }
        
        guard hasMoreTracks else { return }
        if trackOffset == 0 { isLoading = true }
        
        Task {
            let field = sqlSortField()
            var ascending = true
            if let first = sortOrder.first {
                ascending = first.order == .forward
            }
            let filterPath = root?.path
            
            let fetched = libraryVM.fetchTracksPage(limit: pageSize, offset: trackOffset, sortBy: field, ascending: ascending, filterPath: filterPath)
            
            // Build folder tree efficiently using distinct paths if we are starting fresh
            let tree: [MenuFolderNode]?
            let fetchedPaths: [String]?
            if trackOffset == 0 {
                let allPaths = libraryVM.fetchDistinctFilePaths()
                fetchedPaths = allPaths
                tree = buildFolderTree(paths: allPaths, roots: libraryVM.libraryFolders)
            } else {
                fetchedPaths = nil
                tree = nil
            }
            
            await MainActor.run {
                self.selectedRootFolder.wrappedValue = root
                if let tree = tree {
                    self.folderTree = tree
                }
                
                if trackOffset == 0 {
                    self.allTracks = fetched
                } else {
                    self.allTracks.append(contentsOf: fetched)
                }
                
                self.trackOffset += fetched.count
                self.hasMoreTracks = fetched.count == self.pageSize
                
                // Update Cache
                self.libraryVM.cachedTracks = self.allTracks
                self.libraryVM.cachedTrackOffset = self.trackOffset
                self.libraryVM.cachedHasMoreTracks = self.hasMoreTracks
                if let fetchedPaths = fetchedPaths {
                    self.libraryVM.cachedFolderPaths = fetchedPaths
                }
                
                self.isLoading = false
            }
        }
    }
    
    private func loadMoreTracks() {
        guard hasMoreTracks, !isLoading else { return }
        loadTracks(for: selectedRootFolder.wrappedValue, forceRefresh: false)
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
                CachedAsyncImage(url: url) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1))
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(.primary.opacity(0.3)))
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
                    .foregroundStyle(.primary.opacity(0.55))
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
            }
            
            if isVisible("Album") {
                Text(track.albumTitle ?? "—")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.4))
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
                    .foregroundStyle(.primary.opacity(0.45))
                    .frame(width: 85, alignment: .trailing)
            }
            
            if isVisible("Bit Depth") {
                Text("\(track.bitDepth)-bit")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.45))
                    .frame(width: 70, alignment: .trailing)
            }
            
            if isVisible("Channels") {
                Text(track.channels == 1 ? "Mono" : (track.channels == 2 ? "Stereo" : "\(track.channels) ch"))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.45))
                    .frame(width: 70, alignment: .trailing)
            }
            
            if isVisible("Bitrate") {
                if let br = track.bitrate {
                    Text("\(br / 1000) kbps")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.45))
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
                        .foregroundStyle(.primary.opacity(0.45))
                        .frame(width: 70, alignment: .trailing)
                } else {
                    Text("—")
                        .frame(width: 70, alignment: .trailing)
                }
            }
            
            if isVisible("Views") {
                Text("\(track.playCount)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.45))
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
                    .foregroundColor(isFavoriteLocal ? .red : .primary.opacity(isHovered ? 0.4 : 0))
            }
            .buttonStyle(.plain)
            .frame(width: 30)

            if isVisible("Time") {
                Text(formatDuration(track.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.4))
                    .frame(width: 52, alignment: .trailing)
                    .padding(.trailing, 20)
            }
            
            // Drag Handle
            if showDragHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14))
                    .foregroundStyle(isHovered ? Color.primary.opacity(0.6) : Color.primary.opacity(0.2))
                    .padding(.leading, 8)
                    .contentShape(Rectangle())
                    .onDrag {
                        onDragStarted?() ?? NSItemProvider()
                    }
            }
        }
        .frame(height: 48)
        .background(isHovered || isSelected ? Color.primary.opacity(isSelected ? 0.15 : 0.05) : Color.clear)
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


