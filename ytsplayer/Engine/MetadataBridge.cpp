// MetadataBridge.cpp
// ytsplayer
//
// TagLib-based FLAC metadata extractor.
// Extracts: title, artist, album, albumArtist, trackNumber, discNumber,
//           year, sampleRate, bitDepth, channels, duration, embedded artwork.

#include "MetadataBridge.h"

#include <taglib/fileref.h>
#include <taglib/flacfile.h>
#include <taglib/xiphcomment.h>
#include <taglib/flacpicture.h>
#include <taglib/tstring.h>
#include <taglib/tpropertymap.h>

#include <cstring>
#include <cstdlib>

static void copyTag(const TagLib::String &src, char *dst, size_t maxLen) {
    if (src.isEmpty()) { dst[0] = '\0'; return; }
    std::string utf8 = src.to8Bit(true);
    size_t len = utf8.size() < maxLen - 1 ? utf8.size() : maxLen - 1;
    memcpy(dst, utf8.data(), len);
    dst[len] = '\0';
}

static uint32_t tagUInt(const TagLib::PropertyMap &props, const char *key) {
    if (!props.contains(key)) return 0;
    auto &vals = props[key];
    if (vals.isEmpty()) return 0;
    return static_cast<uint32_t>(vals.front().toInt());
}

extern "C" bool ExtractFLACMetadata(const char *filePath, ExtractedTrackMetadata *out) {
    if (!filePath || !out) return false;
    memset(out, 0, sizeof(*out));

    TagLib::FLAC::File file(filePath);
    if (!file.isValid()) return false;

    // ── Audio properties ───────────────────────────────────────────────────
    auto *props = file.audioProperties();
    if (props) {
        out->sampleRate = static_cast<uint32_t>(props->sampleRate());
        out->bitDepth   = static_cast<uint32_t>(props->bitsPerSample());
        out->channels   = static_cast<uint32_t>(props->channels());
        out->duration   = static_cast<double>(props->lengthInSeconds());
    }

    // ── Tags — prefer PropertyMap for universal, case-insensitive extraction ──
    TagLib::PropertyMap pm = file.properties();
    if (pm.contains("TITLE"))       copyTag(pm["TITLE"].front(),       out->title,  sizeof(out->title));
    if (pm.contains("ARTIST"))      copyTag(pm["ARTIST"].front(),      out->artist, sizeof(out->artist));
    if (pm.contains("ALBUM"))       copyTag(pm["ALBUM"].front(),       out->album,  sizeof(out->album));
    if (pm.contains("ALBUMARTIST")) copyTag(pm["ALBUMARTIST"].front(), out->albumArtist, sizeof(out->albumArtist));
    
    out->trackNumber = tagUInt(pm, "TRACKNUMBER");
    out->discNumber  = tagUInt(pm, "DISCNUMBER");
    out->year        = tagUInt(pm, "DATE"); // TagLib exposes Year as DATE in PropertyMap
    if (out->year == 0) out->year = tagUInt(pm, "YEAR");

    // ── Fallback to basic tag() if properties failed ───────────────────────
    auto *tag = file.tag();
    if (tag) {
        if (out->title[0] == '\0')  copyTag(tag->title(),  out->title,  sizeof(out->title));
        if (out->artist[0] == '\0') copyTag(tag->artist(), out->artist, sizeof(out->artist));
        if (out->album[0] == '\0')  copyTag(tag->album(),  out->album,  sizeof(out->album));
        if (out->trackNumber == 0)  out->trackNumber = static_cast<uint32_t>(tag->track());
        if (out->year == 0)         out->year = static_cast<uint32_t>(tag->year());
    }

    // ── Embedded artwork ───────────────────────────────────────────────────
    const TagLib::List<TagLib::FLAC::Picture *> &pics = file.pictureList();
    for (auto *pic : pics) {
        // Prefer front-cover; fall back to the first picture found
        if (pic->type() == TagLib::FLAC::Picture::FrontCover || out->artworkData == nullptr) {
            free(out->artworkData); // free a non-FrontCover we may have already stored
            const TagLib::ByteVector &data = pic->data();
            out->artworkData = static_cast<uint8_t *>(malloc(data.size()));
            if (out->artworkData) {
                memcpy(out->artworkData, data.data(), data.size());
                out->artworkSize = data.size();
                copyTag(pic->mimeType(), out->artworkMimeType, sizeof(out->artworkMimeType));
            }
            if (pic->type() == TagLib::FLAC::Picture::FrontCover) break;
        }
    }

    return true;
}

extern "C" void ExtractedMetadata_FreeArtwork(ExtractedTrackMetadata *metadata) {
    if (!metadata) return;
    free(metadata->artworkData);
    metadata->artworkData = nullptr;
    metadata->artworkSize = 0;
}
