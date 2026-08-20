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
}

struct AlbumViewModel: Identifiable {
    let id: Int64
    let title: String
    let artistName: String?
    let year: Int?
    let artworkCachePath: String?
    let trackCount: Int
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
                       COUNT(tracks.id) AS trackCount
                FROM albums
                LEFT JOIN artists ON artists.id = albums.artistId
                LEFT JOIN tracks  ON tracks.albumId = albums.id
                GROUP BY albums.id
                ORDER BY artistName COLLATE NOCASE, albums.year, albums.title COLLATE NOCASE
            """)
            return rows.map {
                AlbumViewModel(
                    id:              $0["id"],
                    title:           $0["title"],
                    artistName:      $0["artistName"],
                    year:            $0["year"],
                    artworkCachePath: $0["artworkCachePath"],
                    trackCount:      $0["trackCount"]
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
                    lyrics:           $0["lyrics"]
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
                    albumArtworkPath: $0["albumArtworkPath"],
                    lyrics:           $0["lyrics"]
                )
            }
        }
    }

    // MARK: - Maintenance
    
    func clearLibrary() throws {
        try write { db in
            try db.execute(sql: "DELETE FROM tracks")
            try db.execute(sql: "DELETE FROM albums")
            try db.execute(sql: "DELETE FROM artists")
        }
    }
}
