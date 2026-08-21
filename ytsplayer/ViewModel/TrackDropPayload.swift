import SwiftUI
import UniformTypeIdentifiers

// Define a custom UTType for ytsplayer tracks
extension UTType {
    static let ytsplayerTrack = UTType(exportedAs: "com.ytsplayer.track.id")
}

/// Payload for dragging and dropping tracks between windows or views
struct TrackDropPayload: Transferable, Codable {
    let trackIds: [Int64]
    
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: TrackDropPayload.self, contentType: .ytsplayerTrack)
    }
}
