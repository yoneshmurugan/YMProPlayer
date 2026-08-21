// HierarchyView.swift
// ytsplayer

import SwiftUI

struct HierarchyItem: Identifiable {
    let id: String
    let url: URL
    let name: String
    let isDirectory: Bool
    let artworkPath: String?
    let trackId: Int64?
}

struct HierarchyView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playbackVM: PlaybackViewModel
    
    @State private var currentPath: URL?
    @State private var history: [URL?] = []
    @State private var items: [HierarchyItem] = []
    @State private var isScanning = false
    @State private var selectedItemIds: Set<String> = []
    
    @AppStorage("isHierarchyGridView") private var isGridView = true
    
    private let gridColumns = [GridItem(.adaptive(minimum: 140, maximum: 160), spacing: 20)]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                // Breadcrumbs / Back button
                HStack(spacing: 6) {
                    if !history.isEmpty {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(6)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 4)
                    }
                    
                    Button(action: {
                        history.removeAll()
                        currentPath = nil
                        scanCurrentFolder()
                    }) {
                        Text("Hierarchy")
                            .font(.system(size: 15, weight: currentPath == nil ? .bold : .regular))
                            .foregroundStyle(currentPath == nil ? .white : .white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    
                    if let current = currentPath {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                        Text(current.lastPathComponent)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // View Toggles (Grid / List)
                HStack(spacing: 0) {
                    Button(action: { withAnimation { isGridView = true } }) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 26)
                            .background(isGridView ? Color.white.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { withAnimation { isGridView = false } }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 26)
                            .background(!isGridView ? Color.white.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(4)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.15))
            
            Divider().background(Color.white.opacity(0.1))
            
            if isScanning {
                VStack {
                    Spacer()
                    ProgressView("Scanning Directory...")
                        .tint(.purple)
                    Spacer()
                }
            } else if items.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "folder.badge.minus")
                        .font(.system(size: 50))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("Folder is empty")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                if !selectedItemIds.isEmpty {
                    HStack {
                        Text("\(selectedItemIds.count) selected")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.purple)
                        Spacer()
                        Button("Clear Selection") {
                            selectedItemIds.removeAll()
                        }
                        .font(.system(size: 12))
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.1))
                }
                
                ScrollView {
                    if isGridView {
                        LazyVGrid(columns: gridColumns, spacing: 24) {
                            ForEach(items) { item in
                                HierarchyGridItem(
                                    item: item,
                                    isSelected: selectedItemIds.contains(item.id),
                                    selectedItemIds: selectedItemIds,
                                    allItems: items,
                                    onToggleSelection: {
                                        if selectedItemIds.contains(item.id) {
                                            selectedItemIds.remove(item.id)
                                        } else {
                                            selectedItemIds.insert(item.id)
                                        }
                                    }
                                )
                                .onTapGesture {
                                    handleTap(on: item)
                                }
                            }
                        }
                        .padding(24)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(items) { item in
                                HierarchyListItem(
                                    item: item,
                                    isSelected: selectedItemIds.contains(item.id),
                                    selectedItemIds: selectedItemIds,
                                    allItems: items,
                                    onToggleSelection: {
                                        if selectedItemIds.contains(item.id) {
                                            selectedItemIds.remove(item.id)
                                        } else {
                                            selectedItemIds.insert(item.id)
                                        }
                                    }
                                )
                                .onTapGesture {
                                    handleTap(on: item)
                                }
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if currentPath == nil {
                scanCurrentFolder()
            }
        }
        .onChange(of: libraryVM.libraryFolders) { _ in
            if currentPath == nil {
                scanCurrentFolder()
            }
        }
    }
    
    // MARK: - Navigation
    
    private func handleTap(on item: HierarchyItem) {
        if !selectedItemIds.isEmpty {
            if selectedItemIds.contains(item.id) {
                selectedItemIds.remove(item.id)
            } else {
                selectedItemIds.insert(item.id)
            }
            return
        }
        
        if item.isDirectory {
            history.append(currentPath)
            currentPath = item.url
            scanCurrentFolder()
        } else {
            playTrack(at: item.url)
        }
    }
    
    private func goBack() {
        guard !history.isEmpty else { return }
        currentPath = history.removeLast()
        scanCurrentFolder()
    }
    
    private func scanCurrentFolder() {
        guard let url = currentPath else {
            // Root level: show all configured library folders
            items = libraryVM.libraryFolders.map { folderURL in
                HierarchyItem(
                    id: folderURL.path,
                    url: folderURL,
                    name: folderURL.lastPathComponent,
                    isDirectory: true,
                    artworkPath: nil,
                    trackId: nil
                )
            }
            return
        }
        
        isScanning = true
        Task.detached(priority: .userInitiated) {
            var newItems: [HierarchyItem] = []
            
            let fm = FileManager.default
            
            // Try to access security scoped resource if this is a bookmark
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            if let urls = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for fileURL in urls {
                    let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    
                    if isDir || fileURL.pathExtension.lowercased() == "flac" {
                        var artworkPath: String? = nil
                        var trackId: Int64? = nil
                        
                        if isDir {
                            // Find first track in this directory to use its artwork
                            if let track = libraryVM.fetchFirstTrackInFolder(path: fileURL.path) {
                                artworkPath = track.albumArtworkPath
                            }
                        } else {
                            if let track = libraryVM.fetchTrack(byPath: fileURL.path) {
                                artworkPath = track.albumArtworkPath
                                trackId = track.id
                            }
                        }
                        
                        newItems.append(HierarchyItem(
                            id: fileURL.path,
                            url: fileURL,
                            name: fileURL.deletingPathExtension().lastPathComponent,
                            isDirectory: isDir,
                            artworkPath: artworkPath,
                            trackId: trackId
                        ))
                    }
                }
            }
            
            // Sort: Folders first, then alphabetically
            newItems.sort { a, b in
                if a.isDirectory == b.isDirectory {
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
                return a.isDirectory && !b.isDirectory
            }
            
            await MainActor.run {
                self.items = newItems
                self.isScanning = false
            }
        }
    }
    
    private func playTrack(at url: URL) {
        if let track = libraryVM.fetchTrack(byPath: url.path) {
            let trackItems = items.filter { !$0.isDirectory && $0.trackId != nil }
            let allFolderTracks = trackItems.compactMap { item -> TrackViewModel? in
                guard let tId = item.trackId else { return nil }
                return try? AppEnvironment.shared.db.fetchTrack(byId: tId)
            }
            
            if allFolderTracks.isEmpty {
                playbackVM.play(track: track, queue: [track], startIndex: 0, context: .hierarchy(folderUrl: url.deletingLastPathComponent()))
            } else {
                let startIndex = allFolderTracks.firstIndex(where: { $0.id == track.id }) ?? 0
                playbackVM.play(track: track, queue: allFolderTracks, startIndex: startIndex, context: .hierarchy(folderUrl: url.deletingLastPathComponent()))
            }
        } else {
            // Fallback for unscanned files
            let track = TrackViewModel(
                id: Int64(url.hashValue),
                filePath: url.path,
                title: url.deletingPathExtension().lastPathComponent,
                trackNumber: nil,
                duration: 0,
                sampleRate: 0,
                bitDepth: 0,
                artistName: "Unknown Artist",
                albumTitle: "Unknown Album",
                albumArtworkPath: nil,
                lyrics: nil,
                fileSize: nil,
                bitrate: nil,
                channels: 0,
                playCount: 0,
                isFavorite: false
            )
            playbackVM.play(track: track, queue: [track], startIndex: 0)
        }
    }
}

// MARK: - Grid Item
struct HierarchyGridItem: View {
    let item: HierarchyItem
    let isSelected: Bool
    let selectedItemIds: Set<String>
    let allItems: [HierarchyItem]
    let onToggleSelection: () -> Void
    
    @State private var isHovered = false
    @EnvironmentObject var playlistManager: PlaylistManager
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject var playbackVM: PlaybackViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let path = item.artworkPath,
                   let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                    let url = cacheDir.appendingPathComponent(path)
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        fallbackIcon
                    }
                } else {
                    fallbackIcon
                }
            }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            
            Text(item.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(isSelected ? "Deselect" : "Select") {
                onToggleSelection()
            }
            Divider()
            if !item.isDirectory {
                Button("Play Next") {
                    if let tId = item.trackId, let track = getTrack(by: tId) {
                        playbackVM.playNext(track)
                    }
                }
                Button("Add to Queue") {
                    if let tId = item.trackId, let track = getTrack(by: tId) {
                        playbackVM.enqueue(track)
                    }
                }
                Divider()
            }
            Menu("Add to Playlist") {
                Button("New Playlist...") {
                    if let id = playlistManager.createPlaylist(name: "New Playlist") {
                        if let tId = item.trackId { playlistManager.addTracks(to: id, trackIds: [tId]) }
                        openWindow(id: "PlaylistEditor", value: id)
                    }
                }
                if !playlistManager.playlists.isEmpty {
                    Divider()
                    ForEach(playlistManager.playlists) { playlist in
                        Button(playlist.name) {
                            if let tId = item.trackId { playlistManager.addTracks(to: playlist.id, trackIds: [tId]) }
                            openWindow(id: "PlaylistEditor", value: playlist.id)
                        }
                    }
                }
            }
        }
        .draggable(createDragPayload())
    }
    
    // Helper to fetch track details for playbackVM queues if needed
    private func getTrack(by id: Int64) -> TrackViewModel? {
        return try? AppEnvironment.shared.db.fetchTrack(byId: id)
    }

    private func createDragPayload() -> TrackDropPayload {
        var trackIds: [Int64] = []
        let activeItems = selectedItemIds.contains(item.id) && selectedItemIds.count > 1
            ? allItems.filter { selectedItemIds.contains($0.id) }
            : [item]
            
        for i in activeItems {
            if let tId = i.trackId {
                trackIds.append(tId)
            }
        }
        return TrackDropPayload(trackIds: trackIds)
    }
    
    private var fallbackIcon: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(item.isDirectory ? Color.blue.opacity(0.15) : Color.white.opacity(0.05))
            .overlay(
                Image(systemName: item.isDirectory ? "folder.fill" : "music.note")
                    .font(.system(size: 40))
                    .foregroundStyle(item.isDirectory ? Color.blue.opacity(0.8) : Color.white.opacity(0.3))
            )
    }
}

// MARK: - List Item
struct HierarchyListItem: View {
    let item: HierarchyItem
    let isSelected: Bool
    let selectedItemIds: Set<String>
    let allItems: [HierarchyItem]
    let onToggleSelection: () -> Void
    
    @State private var isHovered = false
    @EnvironmentObject var playlistManager: PlaylistManager
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject var playbackVM: PlaybackViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let path = item.artworkPath,
                   let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                    let url = cacheDir.appendingPathComponent(path)
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        fallbackIcon
                    }
                } else {
                    fallbackIcon
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Text(item.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            
            Spacer()
            
            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(isHovered || isSelected ? Color.white.opacity(isSelected ? 0.15 : 0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(isSelected ? "Deselect" : "Select") {
                onToggleSelection()
            }
            Divider()
            if !item.isDirectory {
                Button("Play Next") {
                    if let tId = item.trackId, let track = getTrack(by: tId) {
                        playbackVM.playNext(track)
                    }
                }
                Button("Add to Queue") {
                    if let tId = item.trackId, let track = getTrack(by: tId) {
                        playbackVM.enqueue(track)
                    }
                }
                Divider()
            }
            Menu("Add to Playlist") {
                Button("New Playlist...") {
                    if let id = playlistManager.createPlaylist(name: "New Playlist") {
                        if let tId = item.trackId { playlistManager.addTracks(to: id, trackIds: [tId]) }
                        openWindow(id: "PlaylistEditor", value: id)
                    }
                }
                if !playlistManager.playlists.isEmpty {
                    Divider()
                    ForEach(playlistManager.playlists) { playlist in
                        Button(playlist.name) {
                            if let tId = item.trackId { playlistManager.addTracks(to: playlist.id, trackIds: [tId]) }
                            openWindow(id: "PlaylistEditor", value: playlist.id)
                        }
                    }
                }
            }
        }
        .draggable(createDragPayload())
    }
    
    // Helper to fetch track details for playbackVM queues if needed
    private func getTrack(by id: Int64) -> TrackViewModel? {
        return try? AppEnvironment.shared.db.fetchTrack(byId: id)
    }
    
    private func createDragPayload() -> TrackDropPayload {
        var trackIds: [Int64] = []
        let activeItems = selectedItemIds.contains(item.id) && selectedItemIds.count > 1
            ? allItems.filter { selectedItemIds.contains($0.id) }
            : [item]
            
        for i in activeItems {
            if let tId = i.trackId {
                trackIds.append(tId)
            }
        }
        return TrackDropPayload(trackIds: trackIds)
    }
    
    private var fallbackIcon: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(item.isDirectory ? Color.blue.opacity(0.15) : Color.white.opacity(0.05))
            .overlay(
                Image(systemName: item.isDirectory ? "folder.fill" : "music.note")
                    .font(.system(size: 18))
                    .foregroundStyle(item.isDirectory ? Color.blue.opacity(0.8) : Color.white.opacity(0.3))
            )
    }
}
