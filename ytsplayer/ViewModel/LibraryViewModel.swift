// LibraryViewModel.swift
// ytsplayer

import SwiftUI
import GRDB
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var albums: [AlbumViewModel] = []
    @Published var isLoading: Bool          = true
    @Published var scanProgress: Double     = 0.0
    @Published var isScanning: Bool         = false
    @Published var libraryRootURL: URL?

    let scanner: LibraryScanner
    private let db: DatabasePool
    private var scannerCancellables = Set<AnyCancellable>()

    init(db: DatabasePool) {
        self.db      = db
        self.scanner = LibraryScanner(db: db)
        loadAlbums()
        observeScanner()
    }

    enum SortOrder: String, CaseIterable {
        case titleAsc = "Title (A-Z)"
        case titleDesc = "Title (Z-A)"
        case yearDesc = "Year (Newest)"
        case yearAsc = "Year (Oldest)"
    }
    @Published var sortOrder: SortOrder = .titleAsc {
        didSet { loadAlbums() }
    }

    func loadAlbums() {
        Task {
            isLoading = true
            var loaded = (try? db.fetchAlbumViewModels()) ?? []
            
            switch sortOrder {
            case .titleAsc:
                loaded.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case .titleDesc:
                loaded.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
            case .yearDesc:
                loaded.sort { ($0.year ?? 0) > ($1.year ?? 0) }
            case .yearAsc:
                loaded.sort { ($0.year ?? Int.max) < ($1.year ?? Int.max) }
            }
            
            albums = loaded
            isLoading = false
        }
    }

    func startScan(rootURL: URL) {
        libraryRootURL = rootURL
        UserDefaults.standard.set(rootURL.path, forKey: "libraryRootPath")
        scanner.startScan(rootURL: rootURL)
    }

    func fetchTracks(for album: AlbumViewModel) -> [TrackViewModel] {
        (try? db.fetchTracks(forAlbumId: album.id)) ?? []
    }

    func clearLibraryAndCache() {
        Task {
            await scanner.clearLibraryAndCache()
            libraryRootURL = nil
            UserDefaults.standard.removeObject(forKey: "libraryRootPath")
            loadAlbums()
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

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String             = ""
    @Published var results: [TrackViewModel] = []
    @Published var isSearching: Bool         = false

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
