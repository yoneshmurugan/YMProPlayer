// ImageDownsampler.swift
// ytsplayer
//
// Downsample raw embedded JPEG/PNG artwork to a 400×400 JPEG and cache it to disk.
// Cache key: MD5 of the source bytes (stable across re-scans of the same file).

import CoreGraphics
import ImageIO
import Foundation
import CryptoKit

enum ImageDownsampler {

    static let maxPixelSize: Int = 400
    static let jpegQuality: Float = 0.82

    // Returns the relative cache path ("artwork/<hash>.jpg") on success.
    static func downsampleAndCache(
        artworkData: Data,
        cacheDirectory: URL
    ) -> String? {
        let hash = Insecure.MD5.hash(data: artworkData).map { String(format: "%02x", $0) }.joined()
        let filename   = "\(hash).jpg"
        let outputURL  = cacheDirectory.appendingPathComponent(filename)

        // Return existing cached path without re-decoding
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return filename
        }

        guard let source = CGImageSourceCreateWithData(artworkData as CFData, nil) else {
            return nil
        }

        // Decode at 1:1 and downsample using ImageIO thumbnail pipeline
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways:  true,
            kCGImageSourceCreateThumbnailWithTransform:    true,
            kCGImageSourceShouldCacheImmediately:          false,
            kCGImageSourceThumbnailMaxPixelSize:           maxPixelSize
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        // Encode as JPEG
        guard let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, thumbnail, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }

        return filename
    }

    static func artworkCacheDirectory() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = caches.appendingPathComponent("ytsplayer/artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
