// LibraryViewModel.swift
// ytsplayer

import SwiftUI
import GRDB
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    // MARK: - Tracks Page Persistent State
    @AppStorage("TracksSortField") var tracksSortField: String = "title"
    @AppStorage("TracksSortAscending") var tracksSortAscending: Bool = true
    @AppStorage("isFSEventsEnabled") var isFSEventsEnabled: Bool = true {
        didSet { updateWatcherStatus() }
    }
    

    @Published var tracksSelectedRootFolder: URL? = nil
    @Published var tracksExpandedFolders: Set<URL> = []
    @Published var tracksFolderSearchQuery = ""
    @Published var cachedTracks: [TrackViewModel]? = nil
    @Published var cachedTrackOffset: Int = 0
    @Published var cachedHasMoreTracks: Bool = true
    @Published var cachedFolderPaths: [String]? = nil
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
    @Published var libraryFolders: [URL]    = [] {
        didSet { updateWatcherStatus() }
    }

    let scanner: LibraryScanner
    private let db: DatabasePool
    private var scannerCancellables = Set<AnyCancellable>()

    init(db: DatabasePool) {
        self.db      = db
        self.scanner = LibraryScanner(db: db)
        loadFoldersFromUserDefaults()
        loadAlbums()
        observeScanner()
        observeWatcher()
    }
    
    private func updateWatcherStatus() {
        if isFSEventsEnabled {
            LibraryWatcher.shared.startWatching(folders: libraryFolders)
        } else {
            LibraryWatcher.shared.stopWatching()
        }
    }
    
    private func observeWatcher() {
        LibraryWatcher.shared.folderDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if !self.isScanning {
                    self.startScan()
                }
            }
            .store(in: &scannerCancellables)
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
            let currentSort = sortOrder
            let result = await Task.detached(priority: .userInitiated) { [db] () -> (albums: [AlbumViewModel], artists: [ArtistViewModel], quickPicks: [TrackViewModel], mostPlayedTracks: [TrackViewModel], mostPlayedAlbums: [AlbumViewModel], mostPlayedArtists: [ArtistViewModel], recentAlbums: [AlbumViewModel], recentArtists: [ArtistViewModel]) in
                var loaded: [AlbumViewModel] = []
                switch currentSort {
                case .mostPlayed:
                    loaded = (try? db.fetchTracksForAlbumSortMostPlayed()) ?? []
                default:
                    loaded = (try? db.fetchAlbumViewModels()) ?? []
                    switch currentSort {
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
                
                let artists = (try? db.fetchArtistsWithArtwork()) ?? []
                let quickPicks = (try? db.fetchQuickPicks(limit: 15)) ?? []
                let mostPlayedTracks = (try? db.fetchMostPlayedTracks(limit: 10)) ?? []
                let mostPlayedAlbums = (try? db.fetchMostPlayedAlbums(limit: 15)) ?? []
                let mostPlayedArtists = (try? db.fetchMostPlayedArtists(limit: 15)) ?? []
                let recentAlbums = (try? db.fetchRecentAlbums(limit: 15)) ?? []
                let recentArtists = (try? db.fetchRecentArtists(limit: 15)) ?? []
                
                return (loaded, artists, quickPicks, mostPlayedTracks, mostPlayedAlbums, mostPlayedArtists, recentAlbums, recentArtists)
            }.value
            
            DispatchQueue.main.async {
                self.albums = result.albums
                self.artists = result.artists
                self.quickPicks = result.quickPicks
                self.mostPlayedTracks = result.mostPlayedTracks
                self.mostPlayedAlbums = result.mostPlayedAlbums
                self.mostPlayedArtists = result.mostPlayedArtists
                self.recentAlbums = result.recentAlbums
                self.recentArtists = result.recentArtists
                self.isLoading = false
            }
        }
    }
    
    func refreshMostPlayed() {
        Task {
            let result = await Task.detached(priority: .userInitiated) { [db] () -> (tracks: [TrackViewModel], albums: [AlbumViewModel], artists: [ArtistViewModel]) in
                let tracks = (try? db.fetchMostPlayedTracks(limit: 10)) ?? []
                let albums = (try? db.fetchMostPlayedAlbums(limit: 15)) ?? []
                let artists = (try? db.fetchMostPlayedArtists(limit: 15)) ?? []
                return (tracks, albums, artists)
            }.value
            
            DispatchQueue.main.async {
                self.mostPlayedTracks = result.tracks
                self.mostPlayedAlbums = result.albums
                self.mostPlayedArtists = result.artists
            }
        }
    }
    
    func refreshQuickPicks() {
        Task {
            let picks = await Task.detached(priority: .userInitiated) { [db] in
                (try? db.fetchQuickPicks(limit: 15)) ?? []
            }.value
            DispatchQueue.main.async {
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
        if let bookmarks = UserDefaults.standard.dictionary(forKey: "libraryBookmarks") as? [String: Data] {
            var loadedFolders: [URL] = []
            for (_, bookmarkData) in bookmarks {
                var isStale = false
                do {
                    let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                    if url.startAccessingSecurityScopedResource() {
                        loadedFolders.append(url)
                    } else {
                        // Fallback just in case
                        loadedFolders.append(url)
                    }
                } catch {
                    print("Failed to resolve bookmark: \(error)")
                }
            }
            libraryFolders = loadedFolders
        } else if let paths = UserDefaults.standard.stringArray(forKey: "libraryRootPaths") {
            // Legacy load
            libraryFolders = paths.map { URL(fileURLWithPath: $0) }
            saveFoldersToUserDefaults()
        }
    }
    
    private func saveFoldersToUserDefaults() {
        var bookmarks: [String: Data] = [:]
        for url in libraryFolders {
            do {
                let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                bookmarks[url.path] = data
            } catch {
                print("Failed to create bookmark for \(url.path): \(error)")
            }
        }
        UserDefaults.standard.set(bookmarks, forKey: "libraryBookmarks")
        
        // Also save simple paths for legacy/display purposes
        let paths = libraryFolders.map { $0.path }
        UserDefaults.standard.set(paths, forKey: "libraryRootPaths")
    }

    func fetchTracks(for album: AlbumViewModel) -> [TrackViewModel] {
        return (try? db.fetchTracks(forAlbumId: album.id)) ?? []
    }
    
    func fetchTracksPage(limit: Int, offset: Int, sortBy field: String? = nil, ascending: Bool = true, filterPath: String? = nil) -> [TrackViewModel] {
        return (try? db.fetchTrackViewModelsPage(limit: limit, offset: offset, sortBy: field, ascending: ascending, filterPath: filterPath)) ?? []
    }
    
    func fetchDistinctFilePaths() -> [String] {
        return (try? db.fetchDistinctFilePaths()) ?? []
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
    @Published var albumResults: [AlbumViewModel] = []
    @Published var artistResults: [ArtistViewModel] = []
    @Published var playlistResults: [PlaylistViewModel] = []
    
    @Published var isSearching: Bool         = false
    @Published var selectedFilter: SearchFilter = .all {
        didSet {
            performSearch(query)
        }
    }
    
    var hasNoResults: Bool {
        results.isEmpty && albumResults.isEmpty && artistResults.isEmpty && playlistResults.isEmpty && !query.isEmpty && !isSearching
    }

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
        guard !trimmed.isEmpty else {
            results = []
            albumResults = []
            artistResults = []
            playlistResults = []
            return
        }
        isSearching = true
        Task {
            let filter = selectedFilter
            let result = await Task.detached(priority: .userInitiated) { [db] () -> (tracks: [TrackViewModel], albums: [AlbumViewModel], artists: [ArtistViewModel], playlists: [PlaylistViewModel]) in
                var tResults: [TrackViewModel] = []
                var alResults: [AlbumViewModel] = []
                var arResults: [ArtistViewModel] = []
                var pResults: [PlaylistViewModel] = []
                
                if filter == .all || filter == .songs {
                    tResults = (try? db.searchTracks(query: trimmed)) ?? []
                }
                if filter == .all || filter == .album {
                    alResults = (try? db.searchAlbums(query: trimmed)) ?? []
                }
                if filter == .all || filter == .artist {
                    arResults = (try? db.searchArtists(query: trimmed)) ?? []
                }
                if filter == .all || filter == .playlist {
                    // Playlists are managed separately in PlaylistManager, so we leave it empty here 
                    // and let the main thread handle it or we fetch it if we passed a reference.
                    // For now, let's keep it simple.
                }
                return (tResults, alResults, arResults, pResults)
            }.value
            
            // Re-fetch playlists on main thread as they are stored in AppEnvironment
            var pResults: [PlaylistViewModel] = []
            if selectedFilter == .all || selectedFilter == .playlist {
                let allPlaylists = AppEnvironment.shared.playlistManager.playlists
                pResults = allPlaylists.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            }
            
            self.results = result.tracks
            self.albumResults = result.albums
            self.artistResults = result.artists
            self.playlistResults = pResults
            self.isSearching = false
        }
    }
}
import Foundation
import Combine

class LibraryWatcher {
    static let shared = LibraryWatcher()
    
    private var streamRef: FSEventStreamRef?
    private var isWatching: Bool = false
    
    /// Publisher that emits whenever a change is detected in watched folders.
    let folderDidChange = PassthroughSubject<Void, Never>()
    
    // Throttler for scan requests
    private var throttlerTask: Task<Void, Never>?
    
    private init() {}
    
    func startWatching(folders: [URL]) {
        stopWatching()
        
        let pathsToWatch = folders.compactMap { url -> CFString? in
            // Safety check for Network/NAS drives: FSEvents will crash if the path is entirely unreachable
            guard (try? url.checkResourceIsReachable()) == true else {
                print("[LibraryWatcher] Skipping unreachable folder: \(url.path)")
                return nil
            }
            return url.path as CFString
        }
        guard !pathsToWatch.isEmpty else { return }
        
        let pathsArray = pathsToWatch as CFArray
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        // FSEvents callback
        let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let clientInfo = clientCallBackInfo else { return }
            let watcher = Unmanaged<LibraryWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
            
            // We debounce the actual scan trigger to prevent spamming if many files change at once
            watcher.triggerScan()
        }
        
        // Create the stream
        streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1 second latency
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )
        
        if let streamRef = streamRef {
            FSEventStreamSetDispatchQueue(streamRef, DispatchQueue.global(qos: .background))
            FSEventStreamStart(streamRef)
            isWatching = true
            print("[LibraryWatcher] Started watching \(pathsToWatch.count) folders.")
        }
    }
    
    func stopWatching() {
        if let streamRef = streamRef {
            FSEventStreamStop(streamRef)
            FSEventStreamInvalidate(streamRef)
            FSEventStreamRelease(streamRef)
            self.streamRef = nil
            isWatching = false
            print("[LibraryWatcher] Stopped watching folders.")
        }
    }
    
    private func triggerScan() {
        throttlerTask?.cancel()
        throttlerTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s debounce
            guard !Task.isCancelled else { return }
            
            DispatchQueue.main.async {
                self.folderDidChange.send()
            }
        }
    }
}
