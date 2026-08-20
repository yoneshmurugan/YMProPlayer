// LibraryScanner.swift
// ytsplayer
//
// Recursively scans a music folder for FLAC files,
// extracts metadata via the TagLib C++ bridge, downsamples artwork,
// and batch-inserts into the GRDB database.

import Foundation
import GRDB

@MainActor
final class LibraryScanner: ObservableObject {
    @Published var isScanning: Bool = false
    @Published var progress: Double = 0.0          // 0.0 – 1.0
    @Published var scannedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var lastError: String?

    private let db: DatabasePool
    private let cacheDir: URL?
    private var scanTask: Task<Void, Never>?

    init(db: DatabasePool) {
        self.db = db
        self.cacheDir = ImageDownsampler.artworkCacheDirectory()
    }

    // MARK: - Public API

    func startScan(rootURL: URL) {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.scan(rootURL: rootURL)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
    }

    // MARK: - Core Scan Logic

    private func scan(rootURL: URL) async {
        isScanning    = true
        scannedCount  = 0
        progress      = 0.0
        lastError     = nil

        let files = await discoverFLACFiles(in: rootURL)
        totalCount = files.count
        guard totalCount > 0 else {
            isScanning = false
            return
        }

        let batchSize = 50
        let cacheDir  = self.cacheDir

        // Process in chunks on a background actor so the main thread stays free
        await withTaskGroup(of: Void.self) { _ in
            for chunkStart in stride(from: 0, to: files.count, by: batchSize) {
                if Task.isCancelled { break }
                let chunk = Array(files[chunkStart..<min(chunkStart + batchSize, files.count)])

                // Run extraction on a background thread
                let records = await Task.detached(priority: .utility) {
                    chunk.compactMap { url -> (ArtistRecord, AlbumRecord, TrackRecord, String?)? in
                        var meta = ExtractedTrackMetadata()
                        guard ExtractFLACMetadata(url.path, &meta) else { return nil }

                        let title = withUnsafePointer(to: meta.title) {
                            $0.withMemoryRebound(to: CChar.self, capacity: 512) { String(cString: $0) }
                        }.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        let artist = withUnsafePointer(to: meta.artist) {
                            $0.withMemoryRebound(to: CChar.self, capacity: 512) { String(cString: $0) }
                        }.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        let album = withUnsafePointer(to: meta.album) {
                            $0.withMemoryRebound(to: CChar.self, capacity: 512) { String(cString: $0) }
                        }.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        let albumArtist = withUnsafePointer(to: meta.albumArtist) {
                            $0.withMemoryRebound(to: CChar.self, capacity: 512) { String(cString: $0) }
                        }.trimmingCharacters(in: .whitespacesAndNewlines)

                        var finalLyrics: String? = nil
                        if let lyricsC = meta.lyricsData {
                            let lyricsStr = String(cString: lyricsC).trimmingCharacters(in: .whitespacesAndNewlines)
                            finalLyrics = lyricsStr.isEmpty ? nil : lyricsStr
                        }

                        // Downsample artwork
                        var artworkFilename: String? = nil
                        if let cacheDir, meta.artworkData != nil, meta.artworkSize > 0 {
                            let artworkData = Data(bytes: meta.artworkData!, count: meta.artworkSize)
                            artworkFilename = ImageDownsampler.downsampleAndCache(
                                artworkData: artworkData,
                                cacheDirectory: cacheDir
                            )
                        }
                        ExtractedMetadata_FreeArtwork(&meta)

                        let fallbackAlbum = url.deletingLastPathComponent().lastPathComponent
                        let finalAlbum = album.isEmpty ? (fallbackAlbum.isEmpty ? "Unknown Album" : fallbackAlbum) : album

                        let artistRecord = ArtistRecord(name: artist.isEmpty ? "Unknown Artist" : artist)
                        let albumRecord  = AlbumRecord(
                            title:           finalAlbum,
                            albumArtist:     albumArtist.isEmpty ? nil : albumArtist,
                            year:            meta.year > 0 ? Int(meta.year) : nil,
                            artworkCachePath: artworkFilename
                        )
                        let trackRecord  = TrackRecord(
                            filePath:    url.path,
                            title:       title.isEmpty ? url.deletingPathExtension().lastPathComponent : title,
                            trackNumber: meta.trackNumber > 0 ? Int(meta.trackNumber) : nil,
                            discNumber:  meta.discNumber  > 0 ? Int(meta.discNumber)  : nil,
                            duration:    meta.duration,
                            sampleRate:  Int(meta.sampleRate),
                            bitDepth:    Int(meta.bitDepth),
                            channels:    Int(meta.channels),
                            lyrics:      finalLyrics
                        )
                        return (artistRecord, albumRecord, trackRecord, artworkFilename)
                    }
                }.value

                // Batch-insert into GRDB
                try? await Task.detached(priority: .utility) { [db = self.db] in
                    try db.write { dbConn in
                        for (artistRec, albumRec, trackRec, _) in records {
                            // Upsert artist
                            var artist = artistRec
                            try artist.insert(dbConn)
                            let artistId = try ArtistRecord.filter(Column("name") == artist.name).fetchOne(dbConn)?.id

                            // Upsert album
                            var album = albumRec
                            album.artistId = artistId
                            try album.insert(dbConn)
                            let albumId = try AlbumRecord
                                .filter(Column("title") == album.title && Column("artistId") == artistId)
                                .fetchOne(dbConn)?.id

                            // Upsert track
                            var track = trackRec
                            track.albumId  = albumId
                            track.artistId = artistId
                            try track.insert(dbConn)
                        }
                    }
                }.value

                await MainActor.run {
                    self.scannedCount += chunk.count
                    self.progress = Double(self.scannedCount) / Double(self.totalCount)
                }
            }
        }

        isScanning = false
        progress   = 1.0
    }

    // MARK: - File Discovery

    private func discoverFLACFiles(in rootURL: URL) async -> [URL] {
        await Task.detached(priority: .utility) {
            var results: [URL] = []
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }

            while let next = enumerator.nextObject() as? URL {
                if next.pathExtension.lowercased() == "flac" {
                    results.append(next)
                }
            }
            return results
        }.value
    }

    func clearLibraryAndCache() async {
        cancelScan()
        
        // Clear DB
        try? await Task.detached(priority: .utility) { [db = self.db] in
            try? db.clearLibrary()
        }.value
        
        // Clear artwork cache
        if let cacheDir = self.cacheDir {
            let fm = FileManager.default
            if let urls = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
                for url in urls {
                    try? fm.removeItem(at: url)
                }
            }
        }
        
        scannedCount = 0
        totalCount = 0
        progress = 0
    }
}
