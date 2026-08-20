// LyricsService.swift
// ytsplayer

import Foundation
import GRDB

actor LyricsService {
    
    struct LyricsResponse: Decodable {
        let lyrics: String
    }
    
    enum LyricsError: Error {
        case notFound
        case networkError
        case writeFailed
    }
    
    static let shared = LyricsService()
    private init() {}
    
    /// Fetches lyrics from api.lyrics.ovh, updates the DB, and embeds them into the FLAC file
    func fetchAndEmbedLyrics(for track: TrackViewModel, database: DatabasePool) async throws -> String {
        guard let artist = track.artistName?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let title = track.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.lyrics.ovh/v1/\(artist)/\(title)") else {
            throw LyricsError.notFound
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LyricsError.notFound
        }
        
        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode(LyricsResponse.self, from: data) else {
            throw LyricsError.notFound
        }
        
        let cleanLyrics = decoded.lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanLyrics.isEmpty {
            throw LyricsError.notFound
        }
        
        // 1. Embed into FLAC file via TagLib
        let success = track.filePath.withCString { pathC in
            cleanLyrics.withCString { lyricsC in
                EmbedLyricsToFLAC(pathC, lyricsC)
            }
        }
        
        guard success else {
            throw LyricsError.writeFailed
        }
        
        // 2. Update the SQLite Database
        try await database.write { db in
            try db.execute(sql: "UPDATE tracks SET lyrics = ? WHERE id = ?", arguments: [cleanLyrics, track.id])
        }
        
        return cleanLyrics
    }
}
