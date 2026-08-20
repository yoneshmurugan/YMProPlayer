// MetadataBridge.h
// ytsplayer
// C-linkage declarations for the TagLib-based metadata extractor.
// Safe to include from the Swift bridging header.

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Extracted metadata for a single FLAC file.
/// All strings are null-terminated UTF-8.
typedef struct {
    char     title[512];
    char     artist[512];
    char     album[512];
    char     albumArtist[512];
    uint32_t trackNumber;
    uint32_t discNumber;
    uint32_t year;
    uint32_t sampleRate;
    uint32_t bitDepth;
    uint32_t channels;
    double   duration;          ///< Seconds

    /// Raw embedded artwork bytes (owned by the caller — must free with ExtractedMetadata_FreeArtwork)
    uint8_t *artworkData;
    size_t   artworkSize;
    char     artworkMimeType[64]; ///< e.g. "image/jpeg"

    /// Extracted lyrics, if available (owned by caller — must free with ExtractedMetadata_FreeArtwork)
    char    *lyricsData;
} ExtractedTrackMetadata;

/// Extract all metadata from a FLAC file at filePath.
/// Returns true on success. On success, caller MUST call ExtractedMetadata_FreeArtwork.
bool ExtractFLACMetadata(const char *filePath, ExtractedTrackMetadata *outMetadata);

/// Free the artwork buffer allocated by ExtractFLACMetadata.
void ExtractedMetadata_FreeArtwork(ExtractedTrackMetadata *metadata);

/// Embeds lyrics directly into the FLAC file's Vorbis Comment block.
/// Returns true if successful.
bool EmbedLyricsToFLAC(const char *filePath, const char *lyricsText);

#ifdef __cplusplus
}
#endif
