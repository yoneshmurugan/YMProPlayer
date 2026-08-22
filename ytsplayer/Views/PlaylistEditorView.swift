import SwiftUI
import GRDB

struct PlaylistEditorView: View {
    let playlistId: Int64
    let db: DatabasePool
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var playbackVM: PlaybackViewModel
    
    @Environment(\.dismiss) var dismiss
    
    @State private var playlistName: String = ""
    @State private var originalPlaylistName: String = ""
    @State private var tracks: [TrackViewModel] = []
    @State private var isHoveringDropZone = false
    @State private var showSavedCheckmark = false
    @State private var showDeleteConfirmation = false
    @State private var draggedItem: TrackViewModel?
    @State private var searchQuery: String = ""
    @State private var displayedTracks: [TrackViewModel] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 20) {
                Group {
                    if let firstTrack = tracks.first,
                       let path = firstTrack.albumArtworkPath,
                       let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                        let url = cacheDir.appendingPathComponent(path)
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            fallbackIcon()
                        }
                    } else {
                        fallbackIcon()
                    }
                }
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("PLAYLIST")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.purple)
                        .kerning(1.2)
                    
                    HStack {
                        TextField("Playlist Name", text: $playlistName, onCommit: savePlaylistName)
                        .font(.system(size: 28, weight: .bold))
                        .padding(.vertical, 4)
                        .textFieldStyle(.plain)
                        .disabled(playlistId < 0)
                        
                        if playlistId >= 0 {
                            Button(action: savePlaylistName) {
                                HStack {
                                    if showSavedCheckmark {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(showSavedCheckmark ? "Saved" : "Save")
                                }
                                .animation(.default, value: showSavedCheckmark)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(showSavedCheckmark ? .green : .accentColor)
                            .disabled(playlistName == originalPlaylistName || playlistName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .grayscale(playlistName == originalPlaylistName || playlistName.trimmingCharacters(in: .whitespaces).isEmpty ? 1.0 : 0.0)
                            .padding(.leading, 8)
                            
                            Button(action: { showDeleteConfirmation = true }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red.opacity(0.8))
                            .padding(.leading, 4)
                        }
                    }
                    
                    HStack(spacing: 16) {
                        Button(action: {
                            if let first = tracks.first {
                                playbackVM.play(track: first, queue: tracks, startIndex: 0, context: .allTracks)
                            }
                        }) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.purple))
                                .shadow(color: .purple.opacity(0.5), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(tracks.isEmpty)
                        .opacity(tracks.isEmpty ? 0.5 : 1.0)
                        
                        let totalDuration = tracks.reduce(0) { $0 + $1.duration }
                        Text("\(tracks.count) tracks • \(formatTotalDuration(totalDuration))")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            
                        Spacer()
                        
                        // Internal Search
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search playlist...", text: $searchQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .frame(width: 150)
                            
                            if !searchQuery.isEmpty {
                                Button(action: { searchQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                Spacer()
            }
            .padding(32)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Tracks List with Drop Destination
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(displayedTracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(
                            index: index + 1, 
                            track: track, 
                            isPlaying: playbackVM.currentTrack?.id == track.id,
                            onPlayNext: { playbackVM.playNext(track) },
                            onEnqueue: { playbackVM.enqueue(track) },
                            showDragHandle: searchQuery.isEmpty,
                            enableExportDrag: false,
                            onDragStarted: {
                                self.draggedItem = track
                                return NSItemProvider(object: track.id.description as NSString)
                            }
                        )
                        .equatable()
                        .onTapGesture {
                                playbackVM.play(track: track, queue: displayedTracks, startIndex: index)
                            }
                            .onDrop(of: [.plainText], delegate: PlaylistDropDelegate(item: track, items: $tracks, playlistId: playlistId, draggedItem: $draggedItem, isSearchActive: !searchQuery.isEmpty))
                            .contextMenu {
                                if playlistId >= 0 {
                                    Button("Remove from Playlist", role: .destructive) {
                                        removeTrack(track)
                                    }
                                }
                            }
                    }
                }
                .padding(.vertical, 8)
            }
            .overlay(
                Group {
                    if tracks.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 40))
                            Text("Drag and drop songs here")
                                .font(.title3)
                        }
                        .foregroundColor(isHoveringDropZone ? .accentColor : .secondary)
                    }
                }
            )
            .dropDestination(for: TrackDropPayload.self) { items, location in
                if playlistId < 0 { return false }
                return handleDrop(items: items)
            } isTargeted: { targeted in
                if playlistId >= 0 { isHoveringDropZone = targeted }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .onAppear {
            loadPlaylist()
        }
        .onChange(of: playlistManager.playlists) {
            // Refresh if playlist was deleted or changed externally
            loadPlaylist()
        }
        .onChange(of: tracks) { _ in
            updateDisplayedTracks()
        }
        .onChange(of: searchQuery) { _ in
            updateDisplayedTracks()
        }
        .confirmationDialog("Delete Playlist", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                playlistManager.deletePlaylist(id: playlistId)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete '\(originalPlaylistName)'? This cannot be undone.")
        }
    }
    
    private func loadPlaylist() {
        if playlistId == -1 {
            playlistName = "Favorites"
            tracks = (try? db.fetchFavorites()) ?? []
            return
        } else if playlistId == -2 {
            playlistName = "Top 50 Heavy Rotation"
            tracks = (try? db.fetchTop50()) ?? []
            return
        } else if playlistId == -3 {
            playlistName = "Hi-Res Audio"
            tracks = (try? db.fetchHiRes()) ?? []
            return
        }
        
        guard let pl = playlistManager.playlists.first(where: { $0.id == playlistId }) else { return }
        
        // Only update if it's different to prevent resetting while typing (if an external refresh happens)
        if originalPlaylistName != pl.name || playlistName.isEmpty {
            playlistName = pl.name
            originalPlaylistName = pl.name
        }
        
        tracks = (try? db.fetchTracksForPlaylist(playlistId: playlistId)) ?? []
    }
    
    private func updateDisplayedTracks() {
        let query = searchQuery
        let all = tracks
        Task.detached {
            let result: [TrackViewModel]
            if query.isEmpty {
                result = all
            } else {
                result = all.filter { track in
                    track.title.localizedCaseInsensitiveContains(query) ||
                    (track.artistName?.localizedCaseInsensitiveContains(query) ?? false) ||
                    (track.albumTitle?.localizedCaseInsensitiveContains(query) ?? false)
                }
            }
            await MainActor.run {
                if self.searchQuery == query {
                    self.displayedTracks = result
                }
            }
        }
    }
    
    private func handleDrop(items: [TrackDropPayload]) -> Bool {
        let allTrackIds = items.flatMap { $0.trackIds }
        guard !allTrackIds.isEmpty else { return false }
        
        do {
            try db.addTracksToPlaylist(playlistId: playlistId, trackIds: allTrackIds)
            playlistManager.refreshPlaylists()
            loadPlaylist()
            return true
        } catch {
            print("Failed to add tracks to playlist: \(error)")
            return false
        }
    }
    
    private func removeTrack(_ track: TrackViewModel) {
        do {
            try db.removeTrackFromPlaylist(playlistId: playlistId, trackId: track.id)
            playlistManager.refreshPlaylists()
            loadPlaylist()
        } catch {
            print("Failed to remove track: \(error)")
        }
    }
    

    
    private func savePlaylistName() {
        guard playlistId >= 0, playlistName != originalPlaylistName, !playlistName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        playlistManager.renamePlaylist(id: playlistId, newName: playlistName)
        originalPlaylistName = playlistName
        
        withAnimation {
            showSavedCheckmark = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSavedCheckmark = false
            }
        }
    }
    
    private func fallbackIcon(for name: String = "music.note.list") -> some View {
        ZStack {
            LinearGradient(colors: [.purple.opacity(0.6), .purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: name)
                .font(.system(size: 48))
                .foregroundColor(.purple)
                .shadow(color: .purple.opacity(0.5), radius: 10, y: 5)
        }
    }
    
    private func formatTotalDuration(_ duration: Double) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

struct PlaylistDropDelegate: DropDelegate {
    let item: TrackViewModel
    @Binding var items: [TrackViewModel]
    let playlistId: Int64
    @Binding var draggedItem: TrackViewModel?
    let isSearchActive: Bool

    func dropEntered(info: DropInfo) {
        guard !isSearchActive,
              playlistId >= 0,
              let draggedItem,
              draggedItem.id != item.id,
              let from = items.firstIndex(where: { $0.id == draggedItem.id }),
              let to = items.firstIndex(where: { $0.id == item.id }) else { return }

        if from != to {
            withAnimation(.default) {
                let toOffset = to > from ? to + 1 : to
                items.move(fromOffsets: IndexSet(integer: from), toOffset: toOffset)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        self.draggedItem = nil
        return true
    }
}
