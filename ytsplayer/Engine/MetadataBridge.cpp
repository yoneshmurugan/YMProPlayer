// MetadataBridge.cpp
// ytsplayer
//
// TagLib-based FLAC metadata extractor.
// Extracts: title, artist, album, albumArtist, trackNumber, discNumber,
//           year, sampleRate, bitDepth, channels, duration, embedded artwork.

#include "MetadataBridge.h"

#include <taglib/fileref.h>
#include <taglib/flacfile.h>
#include <taglib/mpegfile.h>
#include <taglib/id3v2tag.h>
#include <taglib/attachedpictureframe.h>
#include <taglib/mp4file.h>
#include <taglib/mp4tag.h>
#include <taglib/xiphcomment.h>
#include <taglib/flacpicture.h>
#include <taglib/tstring.h>
#include <taglib/tpropertymap.h>
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

    TagLib::FileRef fileRef(filePath);
    if (fileRef.isNull() || !fileRef.file()) return false;
    
    TagLib::File *file = fileRef.file();

    // ── Audio properties ───────────────────────────────────────────────────
    if (auto *props = file->audioProperties()) {
        out->sampleRate = static_cast<uint32_t>(props->sampleRate());
        out->channels   = static_cast<uint32_t>(props->channels());
        out->duration   = static_cast<double>(props->lengthInSeconds());
        out->bitDepth   = 16; // default fallback
        
        if (auto *flacFile = dynamic_cast<TagLib::FLAC::File*>(file)) {
            if (auto *flacProps = flacFile->audioProperties()) {
                out->bitDepth = static_cast<uint32_t>(flacProps->bitsPerSample());
            }
        }
    }

    // ── Tags — prefer PropertyMap for universal, case-insensitive extraction ──
    TagLib::PropertyMap pm = file->properties();
    if (pm.contains("TITLE") && !pm["TITLE"].isEmpty())             copyTag(pm["TITLE"].front(),       out->title,  sizeof(out->title));
    if (pm.contains("ARTIST") && !pm["ARTIST"].isEmpty())           copyTag(pm["ARTIST"].front(),      out->artist, sizeof(out->artist));
    if (pm.contains("ALBUM") && !pm["ALBUM"].isEmpty())             copyTag(pm["ALBUM"].front(),       out->album,  sizeof(out->album));
    if (pm.contains("ALBUMARTIST") && !pm["ALBUMARTIST"].isEmpty()) copyTag(pm["ALBUMARTIST"].front(), out->albumArtist, sizeof(out->albumArtist));
    
    out->trackNumber = tagUInt(pm, "TRACKNUMBER");
    out->discNumber  = tagUInt(pm, "DISCNUMBER");
    out->year        = tagUInt(pm, "DATE"); // TagLib exposes Year as DATE in PropertyMap
    if (out->year == 0) out->year = tagUInt(pm, "YEAR");

    if (pm.contains("LYRICS") && !pm["LYRICS"].isEmpty()) {
        std::string lyricsStr = pm["LYRICS"].front().to8Bit(true);
        if (!lyricsStr.empty()) {
            out->lyricsData = strdup(lyricsStr.c_str());
        }
    } else if (pm.contains("UNSYNCEDLYRICS") && !pm["UNSYNCEDLYRICS"].isEmpty()) {
        std::string lyricsStr = pm["UNSYNCEDLYRICS"].front().to8Bit(true);
        if (!lyricsStr.empty()) {
            out->lyricsData = strdup(lyricsStr.c_str());
        }
    }

    // ── Fallback to basic tag() if properties failed ───────────────────────
    auto *tag = file->tag();
    if (tag) {
        if (out->title[0] == '\0')  copyTag(tag->title(),  out->title,  sizeof(out->title));
        if (out->artist[0] == '\0') copyTag(tag->artist(), out->artist, sizeof(out->artist));
        if (out->album[0] == '\0')  copyTag(tag->album(),  out->album,  sizeof(out->album));
        if (out->trackNumber == 0)  out->trackNumber = static_cast<uint32_t>(tag->track());
        if (out->year == 0)         out->year = static_cast<uint32_t>(tag->year());
    }

    // ── Embedded Artwork Extraction ────────────────────────────────────────

    // 1. Try FLAC
    if (auto *flacFile = dynamic_cast<TagLib::FLAC::File*>(file)) {
        if (flacFile->hasXiphComment()) {
            auto pictures = flacFile->pictureList();
            if (!pictures.isEmpty()) {
                auto *pic = pictures.front();
                out->artworkSize = pic->data().size();
                out->artworkData = (uint8_t *)malloc(out->artworkSize);
                memcpy(out->artworkData, pic->data().data(), out->artworkSize);
                copyTag(pic->mimeType(), out->artworkMimeType, sizeof(out->artworkMimeType));
                return true;
            }
        }
    }
    
    // 2. Try ID3v2 (MP3/WAV)
    if (auto *mpegFile = dynamic_cast<TagLib::MPEG::File*>(file)) {
        if (auto *id3v2Tag = mpegFile->ID3v2Tag()) {
            auto frames = id3v2Tag->frameListMap()["APIC"];
            if (!frames.isEmpty()) {
                if (auto *pic = dynamic_cast<TagLib::ID3v2::AttachedPictureFrame*>(frames.front())) {
                    out->artworkSize = pic->picture().size();
                    out->artworkData = (uint8_t *)malloc(out->artworkSize);
                    memcpy(out->artworkData, pic->picture().data(), out->artworkSize);
                    copyTag(pic->mimeType(), out->artworkMimeType, sizeof(out->artworkMimeType));
                    return true;
                }
            }
        }
    }

    // 3. Try MP4/M4A/ALAC/AAC
    if (auto *mp4File = dynamic_cast<TagLib::MP4::File*>(file)) {
        if (auto *mp4Tag = mp4File->tag()) {
            if (mp4Tag->itemMap().contains("covr")) {
                auto covrList = mp4Tag->itemMap()["covr"].toCoverArtList();
                if (!covrList.isEmpty()) {
                    auto covr = covrList.front();
                    out->artworkSize = covr.data().size();
                    out->artworkData = (uint8_t *)malloc(out->artworkSize);
                    memcpy(out->artworkData, covr.data().data(), out->artworkSize);
                    
                    if (covr.format() == TagLib::MP4::CoverArt::JPEG) {
                        strcpy(out->artworkMimeType, "image/jpeg");
                    } else if (covr.format() == TagLib::MP4::CoverArt::PNG) {
                        strcpy(out->artworkMimeType, "image/png");
                    }
                    return true;
                }
            }
        }
    }

    return true;
}

extern "C" void ExtractedMetadata_FreeArtwork(ExtractedTrackMetadata *metadata) {
    if (!metadata) return;
    free(metadata->artworkData);
    metadata->artworkData = nullptr;
    metadata->artworkSize = 0;
    
    if (metadata->lyricsData) {
        free(metadata->lyricsData);
        metadata->lyricsData = nullptr;
    }
}

extern "C" bool EmbedLyricsToFLAC(const char *filePath, const char *lyricsText) {
    if (!filePath || !lyricsText) return false;
    
    TagLib::FLAC::File file(filePath, false, TagLib::AudioProperties::Average);
    if (!file.isValid()) return false;
    
    // Use XiphComment for FLAC
    TagLib::Ogg::XiphComment *comment = file.xiphComment(true);
    if (!comment) return false;
    
    TagLib::String lyricsString(lyricsText, TagLib::String::UTF8);
    
    // First remove any old lyrics
    comment->removeFields("LYRICS");
    comment->removeFields("UNSYNCEDLYRICS");
    
    // Add new lyrics
    comment->addField("LYRICS", lyricsString);
    
    return file.save();
}
