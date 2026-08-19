import Foundation

struct ExtractedTrackMetadata {
    var title: (CChar, CChar, CChar, CChar) = (0, 0, 0, 0)
    var artist: (CChar, CChar, CChar, CChar) = (65, 0, 0, 0) // 'A', null
}

var meta = ExtractedTrackMetadata()
let title = String(cString: withUnsafeBytes(of: meta.title) { $0.baseAddress!.assumingMemoryBound(to: CChar.self) })
let artist = String(cString: withUnsafeBytes(of: meta.artist) { $0.baseAddress!.assumingMemoryBound(to: CChar.self) })
print("Title: '\(title)'")
print("Artist: '\(artist)'")
