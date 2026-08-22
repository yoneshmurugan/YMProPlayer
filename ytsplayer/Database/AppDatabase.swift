// AppDatabase.swift
// ytsplayer
//
// GRDB DatabasePool setup, schema migrations, and fetch request helpers.
// WAL mode ensures zero read-lock contention while the metadata scanner writes.

import GRDB
import Foundation

// MARK: - Record Models

struct ArtistRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "artists"
    var id: Int64?
    var name: String
}

struct AlbumRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "albums"
    var id: Int64?
    var title: String
    var artistId: Int64?
    var albumArtist: String?
    var year: Int?
    var artworkCachePath: String?   // Relative to ~/Library/Caches/ytsplayer/artwork/
}

struct TrackRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tracks"
    var id: Int64?
    var filePath: String            // Absolute path on disk / pCloud
    var title: String
    var albumId: Int64?
    var artistId: Int64?
    var trackNumber: Int?
    var discNumber: Int?
    var duration: Double
    var sampleRate: Int
    var bitDepth: Int
    var channels: Int
    var lyrics: String?
    var fileSize: Int64?
    var bitrate: Int?
    var playCount: Int = 0
    var lastPlayedAt: Double?
    var isFavorite: Bool = false
}

// MARK: - Rich DTO for UI display

struct TrackViewModel: Identifiable {
    let id: Int64
    let filePath: String
    let title: String
    let trackNumber: Int?
    let duration: Double
    let sampleRate: Int
    let bitDepth: Int
    let artistName: String?
    let albumTitle: String?
    let albumArtworkPath: String?
    var lyrics: String?
    let fileSize: Int64?
    let bitrate: Int?
    let channels: Int
    var playCount: Int
    var isFavorite: Bool
    
    // Computed properties for Table sorting (Optionals are not Comparable in Swift)
    var sortArtist: String { artistName ?? "" }
    var sortAlbum: String { albumTitle ?? "" }
    var sortBitrate: Int { bitrate ?? 0 }
    var sortSize: Int64 { fileSize ?? 0 }
}

struct AlbumViewModel: Identifiable {
    let id: Int64
    let title: String
    let artistName: String?
    let year: Int?
    let artworkCachePath: String?
    let trackCount: Int
    let isHiRes: Bool
}

struct ArtistViewModel: Identifiable {
    let id: Int64
    let name: String
    let artworkCachePath: String?
    let albumCount: Int
    let trackCount: Int
}

// MARK: - Playlist DTOs

struct PlaylistViewModel: Identifiable, Hashable {
    let id: Int64
    let name: String
    let createdAt: Date
    let trackCount: Int
    let totalDuration: Double
    let firstArtworkCachePath: String?
}

// MARK: - Database Setup

enum AppDatabase {

    static func makeDatabasePool() throws -> DatabasePool {
        let fm    = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("ytsplayer", isDirectory: true)

        try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)

        var config = Configuration()
        config.qos = .userInitiated
        config.prepareDatabase { db in
            // WAL mode: readers never block writers, writers never block readers
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous  = NORMAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let dbPath = appSupport.appendingPathComponent("library.db").path
        let pool   = try DatabasePool(path: dbPath, configuration: config)
        try migrator.migrate(pool)
        return pool
    }

    // MARK: - Schema Migrations

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1_schema") { db in
            try db.create(table: "artists") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique(onConflict: .ignore)
            }
            try db.create(table: "albums") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("artistId", .integer).references("artists", onDelete: .cascade)
                t.column("albumArtist", .text)
                t.column("year", .integer)
                t.column("artworkCachePath", .text)
                t.uniqueKey(["title", "artistId", "year"], onConflict: .ignore)
            }
            try db.create(table: "tracks") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("filePath", .text).notNull().unique(onConflict: .replace)
                t.column("title", .text).notNull()
                t.column("albumId", .integer).references("albums", onDelete: .cascade)
                t.column("artistId", .integer).references("artists", onDelete: .cascade)
                t.column("trackNumber", .integer)
                t.column("discNumber", .integer)
                t.column("duration", .double).notNull()
                t.column("sampleRate", .integer).notNull()
                t.column("bitDepth", .integer).notNull()
                t.column("channels", .integer).notNull()
            }
        }
        


        m.registerMigration("v1_fts_setup") { db in
            // FTS5 virtual table for sub-millisecond full-text search
            try db.execute(sql: """
                CREATE VIRTUAL TABLE tracks_fts USING fts5(
                    title,
                    content='tracks',
                    content_rowid='id',
                    tokenize='unicode61'
                );
                CREATE TRIGGER tracks_ai AFTER INSERT ON tracks BEGIN
                    INSERT INTO tracks_fts(rowid, title) VALUES (new.id, new.title);
                END;
                CREATE TRIGGER tracks_au AFTER UPDATE ON tracks BEGIN
                    INSERT INTO tracks_fts(tracks_fts, rowid, title) VALUES ('delete', old.id, old.title);
                    INSERT INTO tracks_fts(rowid, title) VALUES (new.id, new.title);
                END;
                CREATE TRIGGER tracks_ad AFTER DELETE ON tracks BEGIN
                    INSERT INTO tracks_fts(tracks_fts, rowid, title) VALUES ('delete', old.id, old.title);
                END;
            """)
        }

        m.registerMigration("v2") { db in
            try db.alter(table: "tracks") { t in
                t.add(column: "lyrics", .text)
            }
        }
        
        m.registerMigration("v3") { db in
            try db.alter(table: "tracks") { t in
                t.add(column: "fileSize", .integer)
                t.add(column: "bitrate", .integer)
            }
        }
        
        m.registerMigration("v4_play_metrics") { db in
            try db.alter(table: "tracks") { t in
                t.add(column: "playCount", .integer).notNull().defaults(to: 0)
                t.add(column: "lastPlayedAt", .double)
            }
        }

        m.registerMigration("v5_playlists") { db in
            try db.create(table: "playlists") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull().defaults(to: Date())
            }
            try db.create(table: "playlist_tracks") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("playlistId", .integer).notNull().references("playlists", onDelete: .cascade)
                t.column("trackId", .integer).notNull().references("tracks", onDelete: .cascade)
                t.column("orderIndex", .integer).notNull()
                t.column("addedAt", .datetime).notNull().defaults(to: Date())
            }
        }

        m.registerMigration("v6_favorites") { db in
            try db.alter(table: "tracks") { t in
                t.add(column: "isFavorite", .boolean).notNull().defaults(to: false)
            }
        }

        return m
    }
}

// MARK: - Query Helpers

extension DatabasePool {

    // Fetch all albums with their artist names and track counts
    func fetchAlbumViewModels() throws -> [AlbumViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT albums.id, albums.title, artists.name AS artistName,
                       albums.year, albums.artworkCachePath,
                       COUNT(tracks.id) AS trackCount,
                       MAX(tracks.bitDepth) AS maxBitDepth
                FROM albums
                LEFT JOIN artists ON artists.id = albums.artistId
                LEFT JOIN tracks  ON tracks.albumId = albums.id
                GROUP BY albums.id
                ORDER BY artistName COLLATE NOCASE, albums.year, albums.title COLLATE NOCASE
            """)
            return rows.map {
                let maxBitDepth: Int = $0["maxBitDepth"] ?? 0
                return AlbumViewModel(
                    id:              $0["id"],
                    title:           $0["title"],
                    artistName:      $0["artistName"],
                    year:            $0["year"],
                    artworkCachePath: $0["artworkCachePath"],
                    trackCount:      $0["trackCount"],
                    isHiRes:         maxBitDepth >= 24
                )
            }
        }
    }

    // Fetch all tracks for an album, sorted by disc + track number
    func fetchTracks(forAlbumId albumId: Int64) throws -> [TrackViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT tracks.*, artists.name AS artistName,
                       albums.title AS albumTitle, albums.artworkCachePath
                FROM tracks
                LEFT JOIN artists ON artists.id = tracks.artistId
                LEFT JOIN albums  ON albums.id  = tracks.albumId
                WHERE tracks.albumId = ?
                ORDER BY tracks.discNumber, tracks.trackNumber, tracks.title COLLATE NOCASE
            """, arguments: [albumId])
            return rows.map {
                TrackViewModel(
                    id:               $0["id"],
                    filePath:         $0["filePath"],
                    title:            $0["title"],
                    trackNumber:      $0["trackNumber"],
                    duration:         $0["duration"],
                    sampleRate:       $0["sampleRate"],
                    bitDepth:         $0["bitDepth"],
                    artistName:       $0["artistName"],
                    albumTitle:       $0["albumTitle"],
                    albumArtworkPath: $0["artworkCachePath"],
                    lyrics:           $0["lyrics"],
                    fileSize:         $0["fileSize"],
                    bitrate:          $0["bitrate"],
                    channels:         $0["channels"],
                    playCount:        $0["playCount"] ?? 0,
                    isFavorite:       $0["isFavorite"] ?? false
                )
            }
        }
    }

    // Fetch all tracks for an artist, sorted by album year, then album title, then track number
    func fetchTracks(forArtistId artistId: Int64) throws -> [TrackViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT tracks.*, artists.name AS artistName,
                       albums.title AS albumTitle, albums.artworkCachePath
                FROM tracks
                LEFT JOIN artists ON artists.id = tracks.artistId
                LEFT JOIN albums  ON albums.id  = tracks.albumId
                WHERE tracks.artistId = ?
                ORDER BY albums.year DESC, albums.title COLLATE NOCASE, tracks.discNumber, tracks.trackNumber
            """, arguments: [artistId])
            return rows.map {
                TrackViewModel(
                    id:               $0["id"],
                    filePath:         $0["filePath"],
                    title:            $0["title"],
                    trackNumber:      $0["trackNumber"],
                    duration:         $0["duration"],
                    sampleRate:       $0["sampleRate"],
                    bitDepth:         $0["bitDepth"],
                    artistName:       $0["artistName"],
                    albumTitle:       $0["albumTitle"],
                    albumArtworkPath: $0["artworkCachePath"],
                    lyrics:           $0["lyrics"],
                    fileSize:         $0["fileSize"],
                    bitrate:          $0["bitrate"],
                    channels:         $0["channels"],
                    playCount:        $0["playCount"] ?? 0,
                    isFavorite:       $0["isFavorite"] ?? false
                )
            }
        }
    }

    // Full-text search via FTS5 MATCH
    func searchTracks(query: String) throws -> [TrackViewModel] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        // Escape FTS5 special characters and append wildcard
        let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        let ftsQuery = "\"\(escaped)\"*"
        return try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT tracks.*, artists.name AS artistName,
                       albums.title AS albumTitle, albums.artworkCachePath
                FROM tracks
                JOIN tracks_fts ON tracks.id = tracks_fts.rowid
                LEFT JOIN artists ON artists.id = tracks.artistId
                LEFT JOIN albums  ON albums.id  = tracks.albumId
                WHERE tracks_fts MATCH ?
                ORDER BY rank
                LIMIT 100
            """, arguments: [ftsQuery])
            return rows.map {
                TrackViewModel(
                    id:               $0["id"],
                    filePath:         $0["filePath"],
                    title:            $0["title"],
                    trackNumber:      $0["trackNumber"],
                    duration:         $0["duration"],
                    sampleRate:       $0["sampleRate"],
                    bitDepth:         $0["bitDepth"],
                    artistName:       $0["artistName"],
                    albumTitle:       $0["albumTitle"],
                    albumArtworkPath: $0["artworkCachePath"],
                    lyrics:           $0["lyrics"],
                    fileSize:         $0["fileSize"],
                    bitrate:          $0["bitrate"],
                    channels:         $0["channels"],
                    playCount:        $0["playCount"] ?? 0,
                    isFavorite:       $0["isFavorite"] ?? false
                )
            }
        }
    }
    
    // MARK: - New Queries (Home & Artists)
    
    func fetchRecentTracks(limit: Int = 10) throws -> [TrackViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT tracks.*, artists.name AS artistName,
                       albums.title AS albumTitle, albums.artworkCachePath
                FROM tracks
                LEFT JOIN artists ON artists.id = tracks.artistId
                LEFT JOIN albums  ON albums.id  = tracks.albumId
                ORDER BY tracks.id DESC
                LIMIT ?
            """, arguments: [limit])
            
            return rows.map { r in
                TrackViewModel(
                    id:               r["id"],
                    filePath:         r["filePath"],
                    title:            r["title"],
                    trackNumber:      r["trackNumber"],
                    duration:         r["duration"],
                    sampleRate:       r["sampleRate"],
                    bitDepth:         r["bitDepth"],
                    artistName:       r["artistName"],
                    albumTitle:       r["albumTitle"],
                    albumArtworkPath: r["artworkCachePath"],
                    lyrics:           r["lyrics"],
                    fileSize:         r["fileSize"],
                    bitrate:          r["bitrate"],
                    channels:         r["channels"],
                    playCount:        r["playCount"]
                ,
                    isFavorite: r["isFavorite"] ?? false
                )
            }
        }
    }
    
    func fetchMostPlayedTracks(limit: Int = 10) throws -> [TrackViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT tracks.*, artists.name AS artistName,
                       albums.title AS albumTitle, albums.artworkCachePath
                FROM tracks
                LEFT JOIN artists ON artists.id = tracks.artistId
                LEFT JOIN albums  ON albums.id  = tracks.albumId
                WHERE tracks.playCount > 0
                ORDER BY tracks.playCount DESC, tracks.lastPlayedAt DESC
                LIMIT ?
            """, arguments: [limit])
            
            return rows.map { r in
                TrackViewModel(
                    id:               r["id"],
                    filePath:         r["filePath"],
                    title:            r["title"],
                    trackNumber:      r["trackNumber"],
                    duration:         r["duration"],
                    sampleRate:       r["sampleRate"],
                    bitDepth:         r["bitDepth"],
                    artistName:       r["artistName"],
                    albumTitle:       r["albumTitle"],
                    albumArtworkPath: r["artworkCachePath"],
                    lyrics:           r["lyrics"],
                    fileSize:         r["fileSize"],
                    bitrate:          r["bitrate"],
                    channels:         r["channels"],
                    playCount:        r["playCount"]
                ,
                    isFavorite: r["isFavorite"] ?? false
                )
            }
        }
    }

    func fetchMostPlayedAlbums(limit: Int = 10) throws -> [AlbumViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT albums.*, artists.name AS artistName, 
                       COUNT(tracks.id) AS trackCount,
                       SUM(tracks.playCount) AS totalPlays
                FROM albums
                LEFT JOIN artists ON artists.id = albums.artistId
                LEFT JOIN tracks  ON tracks.albumId = albums.id
                GROUP BY albums.id
                HAVING totalPlays > 0
                ORDER BY totalPlays DESC
                LIMIT ?
            """, arguments: [limit])
            return rows.map {
                AlbumViewModel(
                    id:               $0["id"],
                    title:            $0["title"],
                    artistName:       $0["artistName"],
                    year:             $0["year"],
                    artworkCachePath: $0["artworkCachePath"],
                    trackCount:       $0["trackCount"],
                    isHiRes:          false
                )
            }
        }
    }

    func fetchMostPlayedArtists(limit: Int = 10) throws -> [ArtistViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT artists.*, 
                       COUNT(DISTINCT albums.id) AS albumCount,
                       COUNT(DISTINCT tracks.id) AS trackCount,
                       (SELECT artworkCachePath FROM albums WHERE albums.artistId = artists.id AND artworkCachePath IS NOT NULL LIMIT 1) AS artworkCachePath,
                       SUM(tracks.playCount) AS totalPlays
                FROM artists
                LEFT JOIN albums ON albums.artistId = artists.id
                LEFT JOIN tracks ON tracks.artistId = artists.id
                GROUP BY artists.id
                HAVING totalPlays > 0
                ORDER BY totalPlays DESC
                LIMIT ?
            """, arguments: [limit])
            return rows.map {
                ArtistViewModel(
                    id:               $0["id"],
                    name:             $0["name"],
                    artworkCachePath: $0["artworkCachePath"],
                    albumCount:       $0["albumCount"],
                    trackCount:       $0["trackCount"]
                )
            }
        }
    }
    
    func fetchRecentAlbums(limit: Int = 15) throws -> [AlbumViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT albums.id, albums.title, artists.name AS artistName,
                       albums.year, albums.artworkCachePath,
                       COUNT(tracks.id) AS trackCount,
                       MAX(tracks.bitDepth) AS maxBitDepth
                FROM albums
                LEFT JOIN artists ON artists.id = albums.artistId
                LEFT JOIN tracks  ON tracks.albumId = albums.id
                GROUP BY albums.id
                ORDER BY albums.id DESC
                LIMIT ?
            """, arguments: [limit])
            return rows.map {
                let maxBitDepth: Int = $0["maxBitDepth"] ?? 0
                return AlbumViewModel(
                    id:              $0["id"],
                    title:           $0["title"],
                    artistName:      $0["artistName"],
                    year:            $0["year"],
                    artworkCachePath: $0["artworkCachePath"],
                    trackCount:      $0["trackCount"],
                    isHiRes:         maxBitDepth >= 24
                )
            }
        }
    }
    
    func fetchArtistsWithArtwork() throws -> [ArtistViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT artists.id, artists.name,
                       (SELECT artworkCachePath FROM albums WHERE albums.artistId = artists.id AND artworkCachePath IS NOT NULL ORDER BY year DESC LIMIT 1) AS artworkCachePath,
                       COUNT(DISTINCT albums.id) AS albumCount,
                       (SELECT COUNT(id) FROM tracks WHERE tracks.artistId = artists.id) AS trackCount
                FROM artists
                LEFT JOIN albums ON albums.artistId = artists.id
                GROUP BY artists.id
                ORDER BY artists.name COLLATE NOCASE
            """)
            return rows.map {
                ArtistViewModel(
                    id:               $0["id"],
                    name:             $0["name"],
                    artworkCachePath: $0["artworkCachePath"],
                    albumCount:       $0["albumCount"],
                    trackCount:       $0["trackCount"] ?? 0
                )
            }
        }
    }
    
    func fetchRecentArtists(limit: Int = 15) throws -> [ArtistViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT artists.id, artists.name,
                       (SELECT artworkCachePath FROM albums WHERE albums.artistId = artists.id AND artworkCachePath IS NOT NULL ORDER BY year DESC LIMIT 1) AS artworkCachePath,
                       COUNT(DISTINCT albums.id) AS albumCount,
                       (SELECT COUNT(id) FROM tracks WHERE tracks.artistId = artists.id) AS trackCount
                FROM artists
                LEFT JOIN albums ON albums.artistId = artists.id
                GROUP BY artists.id
                ORDER BY artists.id DESC
                LIMIT ?
            """, arguments: [limit])
            return rows.map {
                ArtistViewModel(
                    id:               $0["id"],
                    name:             $0["name"],
                    artworkCachePath: $0["artworkCachePath"],
                    albumCount:       $0["albumCount"],
                    trackCount:       $0["trackCount"] ?? 0
                )
            }
        }
    }
    
    func fetchTrack(byPath path: String) throws -> TrackViewModel? {
        try read { db -> TrackViewModel? in
            let row = try Row.fetchOne(db, sql: """
                SELECT tracks.*, artists.name AS artistName,
                       albums.title AS albumTitle, albums.artworkCachePath
                FROM tracks
                LEFT JOIN artists ON artists.id = tracks.artistId
                LEFT JOIN albums  ON albums.id  = tracks.albumId
                WHERE tracks.filePath = ?
            """, arguments: [path])
            
            guard let r = row else { return nil }
            return TrackViewModel(
                id:               r["id"],
                filePath:         r["filePath"],
                title:            r["title"],
                trackNumber:      r["trackNumber"],
                duration:         r["duration"],
                sampleRate:       r["sampleRate"],
                bitDepth:         r["bitDepth"],
                artistName:       r["artistName"],
                albumTitle:       r["albumTitle"],
                albumArtworkPath: r["artworkCachePath"],
                lyrics:           r["lyrics"],
                fileSize:         r["fileSize"],
                bitrate:          r["bitrate"],
                channels:         r["channels"],
                playCount:        r["playCount"]
            ,
                    isFavorite: r["isFavorite"] ?? false
                )
        }
    }
    
    func fetchTrack(byId id: Int64) throws -> TrackViewModel? {
        try read { db in
            guard let track = try TrackRecord.filter(Column("id") == id).fetchOne(db) else {
                return nil
            }
            
            let album = try AlbumRecord.filter(Column("id") == track.albumId).fetchOne(db)
            let artist = try ArtistRecord.filter(Column("id") == track.artistId).fetchOne(db)
            
            return TrackViewModel(
                id: track.id ?? 0,
                filePath: track.filePath,
                title: track.title,
                trackNumber: track.trackNumber,
                duration: track.duration,
                sampleRate: track.sampleRate,
                bitDepth: track.bitDepth,
                artistName: artist?.name ?? "Unknown Artist",
                albumTitle: album?.title ?? "Unknown Album",
                albumArtworkPath: album?.artworkCachePath,
                lyrics: track.lyrics,
                fileSize: track.fileSize,
                bitrate: track.bitrate,
                channels: track.channels,
                playCount: track.playCount,
                isFavorite: track.isFavorite
            )
        }
    }
    
    func fetchTracksForAlbumSortMostPlayed() throws -> [AlbumViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT albums.*, artists.name AS artistName, 
                       COUNT(tracks.id) AS trackCount,
                       SUM(tracks.playCount) AS totalPlays
                FROM albums
                LEFT JOIN artists ON artists.id = albums.artistId
                LEFT JOIN tracks  ON tracks.albumId = albums.id
                GROUP BY albums.id
                ORDER BY totalPlays DESC
            """)
            return rows.map {
                AlbumViewModel(
                    id:               $0["id"],
                    title:            $0["title"],
                    artistName:       $0["artistName"],
                    year:             $0["year"],
                    artworkCachePath: $0["artworkCachePath"],
                    trackCount:       $0["trackCount"],
                    isHiRes:          false
                )
            }
        }
    }
    
    func fetchQuickPicks(limitPerFolder: Int = 10, fromFolders folders: [URL]) throws -> [TrackViewModel] {
        guard !folders.isEmpty else { return [] }
        
        return try read { db in
            var allPicks: [TrackViewModel] = []
            for folder in folders {
                let folderPrefix = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
                let rows = try Row.fetchAll(db, sql: """
                    SELECT tracks.*, artists.name AS artistName,
                           albums.title AS albumTitle, albums.artworkCachePath
                    FROM tracks
                    LEFT JOIN artists ON artists.id = tracks.artistId
                    LEFT JOIN albums  ON albums.id  = tracks.albumId
                    WHERE tracks.filePath LIKE ?
                    ORDER BY RANDOM()
                    LIMIT ?
                """, arguments: ["\(folderPrefix)%", limitPerFolder])
                
                let tracks = rows.map { r in
                    TrackViewModel(
                        id:               r["id"],
                        filePath:         r["filePath"],
                        title:            r["title"],
                        trackNumber:      r["trackNumber"],
                        duration:         r["duration"],
                        sampleRate:       r["sampleRate"],
                        bitDepth:         r["bitDepth"],
                        artistName:       r["artistName"],
                        albumTitle:       r["albumTitle"],
                        albumArtworkPath: r["artworkCachePath"],
                        lyrics:           r["lyrics"],
                        fileSize:         r["fileSize"],
                        bitrate:          r["bitrate"],
                        channels:         r["channels"],
                        playCount:        r["playCount"]
                    ,
                    isFavorite: r["isFavorite"] ?? false
                )
                }
                allPicks.append(contentsOf: tracks)
            }
            
            allPicks.shuffle()
            return allPicks
        }
    }
    
    func fetchFirstTrackInFolder(path: String) throws -> TrackViewModel? {
        let folderPrefix = path.hasSuffix("/") ? path : path + "/"
        return try read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT tracks.*, artists.name AS artistName,
                       albums.title AS albumTitle, albums.artworkCachePath
                FROM tracks
                LEFT JOIN artists ON artists.id = tracks.artistId
                LEFT JOIN albums  ON albums.id  = tracks.albumId
                WHERE tracks.filePath LIKE ?
                LIMIT 1
            """, arguments: ["\(folderPrefix)%"])
            
            guard let r = row else { return nil }
            return TrackViewModel(
                id:               r["id"],
                filePath:         r["filePath"],
                title:            r["title"],
                trackNumber:      r["trackNumber"],
                duration:         r["duration"],
                sampleRate:       r["sampleRate"],
                bitDepth:         r["bitDepth"],
                artistName:       r["artistName"],
                albumTitle:       r["albumTitle"],
                albumArtworkPath: r["artworkCachePath"],
                lyrics:           r["lyrics"],
                fileSize:         r["fileSize"],
                bitrate:          r["bitrate"],
                channels:         r["channels"],
                playCount:        r["playCount"]
            ,
                    isFavorite: r["isFavorite"] ?? false
                )
        }
    }

    // MARK: - Play Metrics
    
    func incrementPlayCount(forTrackId trackId: Int64) throws {
        try write { db in
            try db.execute(sql: """
                UPDATE tracks 
                SET playCount = playCount + 1,
                    lastPlayedAt = ?
                WHERE id = ?
            """, arguments: [Date().timeIntervalSince1970, trackId])
        }
    }

    // MARK: - Maintenance
    
    func deleteTracks(inFolder path: String) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM tracks WHERE filePath LIKE ?", arguments: ["\(path)%"])
            // Clean up orphaned albums
            try db.execute(sql: """
                DELETE FROM albums 
                WHERE id NOT IN (SELECT DISTINCT albumId FROM tracks WHERE albumId IS NOT NULL)
            """)
            // Clean up orphaned artists
            try db.execute(sql: """
                DELETE FROM artists 
                WHERE id NOT IN (SELECT DISTINCT artistId FROM tracks WHERE artistId IS NOT NULL)
                  AND id NOT IN (SELECT DISTINCT artistId FROM albums WHERE artistId IS NOT NULL)
            """)
        }
    }
    
    func clearLibrary() throws {
        try write { db in
            try db.execute(sql: "DELETE FROM tracks")
            try db.execute(sql: "DELETE FROM albums")
            try db.execute(sql: "DELETE FROM artists")
        }
    }
}

// MARK: - Playlist Queries & Mutations

extension DatabasePool {
    func createPlaylist(name: String) throws -> Int64 {
        try write { db in
            try db.execute(sql: "INSERT INTO playlists (name, createdAt) VALUES (?, ?)", arguments: [name, Date()])
            return db.lastInsertedRowID
        }
    }
    
    func renamePlaylist(id: Int64, newName: String) throws {
        try write { db in
            try db.execute(sql: "UPDATE playlists SET name = ? WHERE id = ?", arguments: [newName, id])
        }
    }
    
    func deletePlaylist(id: Int64) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM playlists WHERE id = ?", arguments: [id])
        }
    }
    
    func fetchPlaylists() throws -> [PlaylistViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT p.id, p.name, p.createdAt,
                       COUNT(pt.id) AS trackCount,
                       COALESCE(SUM(t.duration), 0) AS totalDuration,
                       (SELECT a.artworkCachePath FROM playlist_tracks pt2
                        JOIN tracks t2 ON pt2.trackId = t2.id
                        JOIN albums a ON t2.albumId = a.id
                        WHERE pt2.playlistId = p.id AND a.artworkCachePath IS NOT NULL
                        ORDER BY pt2.orderIndex ASC LIMIT 1) AS firstArtworkCachePath
                FROM playlists p
                LEFT JOIN playlist_tracks pt ON p.id = pt.playlistId
                LEFT JOIN tracks t ON pt.trackId = t.id
                GROUP BY p.id
                ORDER BY p.createdAt DESC
            """)
            
            return rows.map { r in
                PlaylistViewModel(
                    id: r["id"],
                    name: r["name"],
                    createdAt: r["createdAt"],
                    trackCount: r["trackCount"],
                    totalDuration: r["totalDuration"],
                    firstArtworkCachePath: r["firstArtworkCachePath"]
                )
            }
        }
    }
    
    func fetchTracksForPlaylist(playlistId: Int64) throws -> [TrackViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT tracks.*, artists.name AS artistName,
                       albums.title AS albumTitle, albums.artworkCachePath,
                       playlist_tracks.id AS playlistTrackId
                FROM playlist_tracks
                JOIN tracks ON playlist_tracks.trackId = tracks.id
                LEFT JOIN artists ON artists.id = tracks.artistId
                LEFT JOIN albums  ON albums.id  = tracks.albumId
                WHERE playlist_tracks.playlistId = ?
                ORDER BY playlist_tracks.orderIndex ASC
            """, arguments: [playlistId])
            
            return rows.map { r in
                TrackViewModel(
                    id:               r["id"],
                    filePath:         r["filePath"],
                    title:            r["title"],
                    trackNumber:      r["trackNumber"],
                    duration:         r["duration"],
                    sampleRate:       r["sampleRate"],
                    bitDepth:         r["bitDepth"],
                    artistName:       r["artistName"],
                    albumTitle:       r["albumTitle"],
                    albumArtworkPath: r["artworkCachePath"],
                    lyrics:           r["lyrics"],
                    fileSize:         r["fileSize"],
                    bitrate:          r["bitrate"],
                    channels:         r["channels"],
                    playCount:        r["playCount"]
                ,
                    isFavorite: r["isFavorite"] ?? false
                )
            }
        }
    }
    
    func addTracksToPlaylist(playlistId: Int64, trackIds: [Int64]) throws {
        try write { db in
            // Get max order index
            let maxIndexRow = try Row.fetchOne(db, sql: "SELECT MAX(orderIndex) AS maxIdx FROM playlist_tracks WHERE playlistId = ?", arguments: [playlistId])
            var nextIndex = (maxIndexRow?["maxIdx"] as Int? ?? -1) + 1
            
            for trackId in trackIds {
                // Duplicate track protection
                let exists = try Int.fetchOne(db, sql: "SELECT 1 FROM playlist_tracks WHERE playlistId = ? AND trackId = ?", arguments: [playlistId, trackId]) != nil
                if !exists {
                    try db.execute(sql: """
                        INSERT INTO playlist_tracks (playlistId, trackId, orderIndex, addedAt)
                        VALUES (?, ?, ?, ?)
                    """, arguments: [playlistId, trackId, nextIndex, Date()])
                    nextIndex += 1
                }
            }
        }
    }
    
    func removeTrackFromPlaylist(playlistId: Int64, trackId: Int64) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM playlist_tracks WHERE playlistId = ? AND trackId = ?", arguments: [playlistId, trackId])
        }
    }
    
    // MARK: - Smart Playlists & Favorites
    
    func toggleFavorite(forTrackId id: Int64) throws -> Bool {
        try write { db in
            let row = try Row.fetchOne(db, sql: "SELECT isFavorite FROM tracks WHERE id = ?", arguments: [id])
            let current = row?["isFavorite"] as Bool? ?? false
            let next = !current
            try db.execute(sql: "UPDATE tracks SET isFavorite = ? WHERE id = ?", arguments: [next, id])
            return next
        }
    }
    
    func fetchFavorites() throws -> [TrackViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT tracks.*, artists.name AS artistName,
                       albums.title AS albumTitle, albums.artworkCachePath
                FROM tracks
                LEFT JOIN artists ON artists.id = tracks.artistId
                LEFT JOIN albums  ON albums.id  = tracks.albumId
                WHERE tracks.isFavorite = 1
                ORDER BY tracks.title COLLATE NOCASE
            """)
            return mapTrackRows(rows)
        }
    }
    
    func fetchTop50() throws -> [TrackViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT tracks.*, artists.name AS artistName,
                       albums.title AS albumTitle, albums.artworkCachePath
                FROM tracks
                LEFT JOIN artists ON artists.id = tracks.artistId
                LEFT JOIN albums  ON albums.id  = tracks.albumId
                WHERE tracks.playCount > 0
                ORDER BY tracks.playCount DESC, tracks.lastPlayedAt DESC
                LIMIT 50
            """)
            return mapTrackRows(rows)
        }
    }
    
    func fetchHiRes() throws -> [TrackViewModel] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT tracks.*, artists.name AS artistName,
                       albums.title AS albumTitle, albums.artworkCachePath
                FROM tracks
                LEFT JOIN artists ON artists.id = tracks.artistId
                LEFT JOIN albums  ON albums.id  = tracks.albumId
                WHERE tracks.bitDepth >= 24
                ORDER BY tracks.title COLLATE NOCASE
            """)
            return mapTrackRows(rows)
        }
    }
    
    private func mapTrackRows(_ rows: [Row]) -> [TrackViewModel] {
        return rows.map { r in
            TrackViewModel(
                id:               r["id"],
                filePath:         r["filePath"],
                title:            r["title"],
                trackNumber:      r["trackNumber"],
                duration:         r["duration"],
                sampleRate:       r["sampleRate"],
                bitDepth:         r["bitDepth"],
                artistName:       r["artistName"],
                albumTitle:       r["albumTitle"],
                albumArtworkPath: r["artworkCachePath"],
                lyrics:           r["lyrics"],
                fileSize:         r["fileSize"],
                bitrate:          r["bitrate"],
                channels:         r["channels"],
                playCount:        r["playCount"],
                isFavorite:       r["isFavorite"] ?? false
            )
        }
    }
}
