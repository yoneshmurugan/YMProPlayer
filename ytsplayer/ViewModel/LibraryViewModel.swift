// LibraryViewModel.swift
// ytsplayer

import SwiftUI
import GRDB
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var albums: [AlbumViewModel] = []
    @Published var artists: [ArtistViewModel] = []
    @Published var quickPicks: [TrackViewModel] = []
    @Published var mostPlayedTracks: [TrackViewModel] = []
    @Published var mostPlayedAlbums: [AlbumViewModel] = []
    @Published var mostPlayedArtists: [ArtistViewModel] = []
    @Published var recentAlbums: [AlbumViewModel] = []
    @Published var recentArtists: [ArtistViewModel] = []
    @Published var isLoading: Bool          = true
    @Published var scanProgress: Double     = 0.0
    @Published var isScanning: Bool         = false
    @Published var libraryFolders: [URL]    = []

    let scanner: LibraryScanner
    private let db: DatabasePool
    private var scannerCancellables = Set<AnyCancellable>()

    init(db: DatabasePool) {
        self.db      = db
        self.scanner = LibraryScanner(db: db)
        loadFoldersFromUserDefaults()
        loadAlbums()
        observeScanner()
    }

    enum SortOrder: String, CaseIterable {
        case alphaAsc = "Alphabetical A-Z"
        case alphaDesc = "Alphabetical Z-A"
        case artistsAsc = "Artists A-Z"
        case artistsDesc = "Artists Z-A"
        case recentlyPlayed = "Recently played"
        case recentlyAdded = "Recently added"
        case mostPlayed = "Most played"
    }
    @Published var sortOrder: SortOrder = .alphaAsc {
        didSet { loadAlbums() }
    }

    func loadAlbums() {
        Task {
            isLoading = true
            var loaded: [AlbumViewModel] = []
            switch sortOrder {
            case .mostPlayed:
                loaded = (try? db.fetchTracksForAlbumSortMostPlayed()) ?? []
            default:
                loaded = (try? db.fetchAlbumViewModels()) ?? []
                switch sortOrder {
                case .alphaAsc:
                    loaded.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                case .alphaDesc:
                    loaded.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
                case .artistsAsc:
                    loaded.sort { ($0.artistName ?? "").localizedCaseInsensitiveCompare($1.artistName ?? "") == .orderedAscending }
                case .artistsDesc:
                    loaded.sort { ($0.artistName ?? "").localizedCaseInsensitiveCompare($1.artistName ?? "") == .orderedDescending }
                case .recentlyAdded:
                    loaded.sort { $0.id > $1.id }
                case .recentlyPlayed, .mostPlayed:
                    break
                }
            }
            
            albums = loaded
            artists = (try? db.fetchArtistsWithArtwork()) ?? []
            quickPicks = (try? db.fetchQuickPicks(limitPerFolder: 10, fromFolders: libraryFolders)) ?? []
            mostPlayedTracks = (try? db.fetchMostPlayedTracks(limit: 10)) ?? []
            mostPlayedAlbums = (try? db.fetchMostPlayedAlbums(limit: 15)) ?? []
            mostPlayedArtists = (try? db.fetchMostPlayedArtists(limit: 15)) ?? []
            recentAlbums = (try? db.fetchRecentAlbums(limit: 15)) ?? []
            recentArtists = (try? db.fetchRecentArtists(limit: 15)) ?? []
            isLoading = false
        }
    }
    
    func refreshMostPlayed() {
        Task {
            let tracks = (try? db.fetchMostPlayedTracks(limit: 10)) ?? []
            let albums = (try? db.fetchMostPlayedAlbums(limit: 15)) ?? []
            let artists = (try? db.fetchMostPlayedArtists(limit: 15)) ?? []
            
            
            await MainActor.run {
                self.mostPlayedTracks = tracks
                self.mostPlayedAlbums = albums
                self.mostPlayedArtists = artists
            }
        }
    }
    
    func refreshQuickPicks() {
        Task {
            let picks = (try? db.fetchQuickPicks(limitPerFolder: 10, fromFolders: libraryFolders)) ?? []
            await MainActor.run {
                self.quickPicks = picks
            }
        }
    }

    func addFolder(url: URL) {
        if !libraryFolders.contains(url) {
            libraryFolders.append(url)
            saveFoldersToUserDefaults()
        }
    }
    
    func removeFolder(url: URL) {
        libraryFolders.removeAll { $0 == url }
        saveFoldersToUserDefaults()
        
        Task {
            try? db.deleteTracks(inFolder: url.path)
            loadAlbums()
        }
    }
    
    func startScan() {
        guard !libraryFolders.isEmpty else { return }
        scanner.startScan(folders: libraryFolders)
    }
    
    func loadFoldersFromUserDefaults() {
        if let paths = UserDefaults.standard.stringArray(forKey: "libraryRootPaths") {
            libraryFolders = paths.map { URL(fileURLWithPath: $0) }
        } else if let legacyPath = UserDefaults.standard.string(forKey: "libraryRootPath") {
            let url = URL(fileURLWithPath: legacyPath)
            libraryFolders = [url]
            saveFoldersToUserDefaults()
            UserDefaults.standard.removeObject(forKey: "libraryRootPath")
        }
    }
    
    private func saveFoldersToUserDefaults() {
        let paths = libraryFolders.map { $0.path }
        UserDefaults.standard.set(paths, forKey: "libraryRootPaths")
    }

    func fetchTracks(for album: AlbumViewModel) -> [TrackViewModel] {
        (try? db.fetchTracks(forAlbumId: album.id)) ?? []
    }
    
    func fetchTracks(for artist: ArtistViewModel) -> [TrackViewModel] {
        (try? db.fetchTracks(forArtistId: artist.id)) ?? []
    }
    
    func fetchTrack(byPath path: String) -> TrackViewModel? {
        try? db.fetchTrack(byPath: path)
    }
    
    func fetchFirstTrackInFolder(path: String) -> TrackViewModel? {
        try? db.fetchFirstTrackInFolder(path: path)
    }

    func clearLibraryAndCache() {
        Task {
            await scanner.clearLibraryAndCache()
            
            await MainActor.run {
                libraryFolders.removeAll()
                UserDefaults.standard.removeObject(forKey: "libraryRootPaths")
                albums.removeAll()
                artists.removeAll()
                quickPicks.removeAll()
                mostPlayedTracks.removeAll()
                mostPlayedAlbums.removeAll()
                mostPlayedArtists.removeAll()
                recentAlbums.removeAll()
                recentArtists.removeAll()
            }
        }
    }

    private func observeScanner() {
        scanner.$isScanning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scanning in
                self?.isScanning = scanning
                if !scanning { self?.loadAlbums() }
            }
            .store(in: &scannerCancellables)

        scanner.$progress
            .receive(on: DispatchQueue.main)
            .assign(to: &$scanProgress)
    }
}

// MARK: -

enum SearchFilter: String, CaseIterable {
    case all = "All"
    case artist = "Artist"
    case album = "Album"
    case playlist = "Playlist"
    case songs = "Songs"
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String             = ""
    @Published var results: [TrackViewModel] = []
    @Published var isSearching: Bool         = false
    @Published var selectedFilter: SearchFilter = .all

    private let db: DatabasePool
    private var cancellables = Set<AnyCancellable>()

    init(db: DatabasePool) {
        self.db = db

        $query
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] q in
                self?.performSearch(q)
            }
            .store(in: &cancellables)
    }

    private func performSearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { results = []; return }
        isSearching = true
        Task {
            results = (try? db.searchTracks(query: trimmed)) ?? []
            isSearching = false
        }
    }
}
