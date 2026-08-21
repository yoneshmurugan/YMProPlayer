import Foundation
import Combine
import GRDB

@MainActor
class PlaylistManager: ObservableObject {
    @Published var playlists: [PlaylistViewModel] = []
    
    private let db: DatabasePool
    
    init(db: DatabasePool) {
        self.db = db
        refreshPlaylists()
    }
    
    func refreshPlaylists() {
        Task {
            let fetched = (try? db.fetchPlaylists()) ?? []
            await MainActor.run {
                self.playlists = fetched
            }
        }
    }
    
    func createPlaylist(name: String) -> Int64? {
        if let id = try? db.createPlaylist(name: name) {
            refreshPlaylists()
            return id
        }
        return nil
    }
    
    func deletePlaylist(id: Int64) {
        try? db.deletePlaylist(id: id)
        refreshPlaylists()
    }
    
    func renamePlaylist(id: Int64, newName: String) {
        try? db.renamePlaylist(id: id, newName: newName)
        refreshPlaylists()
    }
    
    func addTracks(to playlistId: Int64, trackIds: [Int64]) {
        do {
            try db.addTracksToPlaylist(playlistId: playlistId, trackIds: trackIds)
            loadPlaylists() // refresh
        } catch {
            print("Failed to add tracks to playlist: \(error)")
        }
    }
    
    func toggleFavorite(forTrackId trackId: Int64) throws -> Bool {
        return try db.toggleFavorite(forTrackId: trackId)
    }
    
    func loadPlaylists() {
        refreshPlaylists()
    }
}
