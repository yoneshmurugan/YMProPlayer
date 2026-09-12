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
    
    var tracksSortComparator: [KeyPathComparator<TrackViewModel>] {
        let order: Foundation.SortOrder = tracksSortAscending ? .forward : .reverse
        switch tracksSortField {
        case "title": return [KeyPathComparator(\.title, order: order)]
        case "artistName": return [KeyPathComparator(\.artistName, order: order)]
        case "albumTitle": return [KeyPathComparator(\.albumTitle, order: order)]
        case "filePath": return [KeyPathComparator(\.filePath, order: order)]
        case "sampleRate": return [KeyPathComparator(\.sampleRate, order: order)]
        case "bitDepth": return [KeyPathComparator(\.bitDepth, order: order)]
        case "channels": return [KeyPathComparator(\.channels, order: order)]
        case "bitrate": return [KeyPathComparator(\.bitrate, order: order)]
        case "fileSize": return [KeyPathComparator(\.fileSize, order: order)]
        case "playCount": return [KeyPathComparator(\.playCount, order: order)]
        case "duration": return [KeyPathComparator(\.duration, order: order)]
        default: return [KeyPathComparator(\.title, order: order)]
        }
    }
    @Published var tracksSelectedRootFolder: URL? = nil
    @Published var tracksExpandedFolders: Set<URL> = []
    @Published var tracksFolderSearchQuery = ""

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
            quickPicks = (try? db.fetchQuickPicks(limit: 15)) ?? []
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
            let picks = (try? db.fetchQuickPicks(limit: 15)) ?? []
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
    
    func fetchAllTracks() -> [TrackViewModel] {
        return (try? db.fetchAllTrackViewModels()) ?? []
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
            var tResults: [TrackViewModel] = []
            var alResults: [AlbumViewModel] = []
            var arResults: [ArtistViewModel] = []
            var pResults: [PlaylistViewModel] = []
            
            if selectedFilter == .all || selectedFilter == .songs {
                tResults = (try? db.searchTracks(query: trimmed)) ?? []
            }
            if selectedFilter == .all || selectedFilter == .album {
                alResults = (try? db.searchAlbums(query: trimmed)) ?? []
            }
            if selectedFilter == .all || selectedFilter == .artist {
                arResults = (try? db.searchArtists(query: trimmed)) ?? []
            }
            if selectedFilter == .all || selectedFilter == .playlist {
                await MainActor.run {
                    let allPlaylists = AppEnvironment.shared.playlistManager.playlists
                    pResults = allPlaylists.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
                }
            }
            
            await MainActor.run {
                self.results = tResults
                self.albumResults = alResults
                self.artistResults = arResults
                self.playlistResults = pResults
                self.isSearching = false
            }
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
        
        let pathsToWatch = folders.map { $0.path as CFString }
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
