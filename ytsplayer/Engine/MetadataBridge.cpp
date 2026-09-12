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
    
    if (pm.contains("GENRE") && !pm["GENRE"].isEmpty())             copyTag(pm["GENRE"].front(),       out->genre, sizeof(out->genre));
    if (pm.contains("COMPOSER") && !pm["COMPOSER"].isEmpty())       copyTag(pm["COMPOSER"].front(),    out->composer, sizeof(out->composer));
    if (pm.contains("COMMENT") && !pm["COMMENT"].isEmpty())         copyTag(pm["COMMENT"].front(),     out->comment, sizeof(out->comment));
    if (pm.contains("PUBLISHER") && !pm["PUBLISHER"].isEmpty())     copyTag(pm["PUBLISHER"].front(),   out->publisher, sizeof(out->publisher));
    if (pm.contains("ISRC") && !pm["ISRC"].isEmpty())               copyTag(pm["ISRC"].front(),        out->isrc, sizeof(out->isrc));
    out->bpm = tagUInt(pm, "BPM");

    auto extractGain = [](const TagLib::String &str) -> double {
        std::string s = str.to8Bit(true);
        try {
            size_t idx = 0;
            double val = std::stod(s, &idx);
            return val;
        } catch(...) { return 0.0; }
    };

    if (pm.contains("REPLAYGAIN_TRACK_GAIN") && !pm["REPLAYGAIN_TRACK_GAIN"].isEmpty()) {
        out->replayGainTrack = extractGain(pm["REPLAYGAIN_TRACK_GAIN"].front());
    }
    if (pm.contains("REPLAYGAIN_ALBUM_GAIN") && !pm["REPLAYGAIN_ALBUM_GAIN"].isEmpty()) {
        out->replayGainAlbum = extractGain(pm["REPLAYGAIN_ALBUM_GAIN"].front());
    }
    
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
        if (out->comment[0] == '\0') copyTag(tag->comment(), out->comment, sizeof(out->comment));
        if (out->genre[0] == '\0')   copyTag(tag->genre(), out->genre, sizeof(out->genre));
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

extern "C" bool UpdateFLACMetadata(const char *filePath, const char *title, const char *artist, const char *album, const char *albumArtist, uint32_t year, uint32_t trackNumber, uint32_t discNumber, const char *genre, const char *composer, const char *comment, const char *publisher, const char *isrc, uint32_t bpm) {
    if (!filePath) return false;
    
    TagLib::FileRef fileRef(filePath, false, TagLib::AudioProperties::Average);
    if (fileRef.isNull() || !fileRef.file() || !fileRef.file()->isValid()) return false;
    
    TagLib::Tag *tag = fileRef.tag();
    if (!tag) return false;
    
    if (title) tag->setTitle(TagLib::String(title, TagLib::String::UTF8));
    if (artist) tag->setArtist(TagLib::String(artist, TagLib::String::UTF8));
    if (album) tag->setAlbum(TagLib::String(album, TagLib::String::UTF8));
    if (genre) tag->setGenre(TagLib::String(genre, TagLib::String::UTF8));
    if (comment) tag->setComment(TagLib::String(comment, TagLib::String::UTF8));
    tag->setYear(year);
    tag->setTrack(trackNumber);
    
    // For AlbumArtist and DiscNumber, we need format-specific tags.
    // Assuming FLAC for now since YM Pro is FLAC-focused.
    if (auto *flacFile = dynamic_cast<TagLib::FLAC::File*>(fileRef.file())) {
        TagLib::Ogg::XiphComment *xiph = flacFile->xiphComment(true);
        if (xiph) {
            if (albumArtist) {
                xiph->removeFields("ALBUMARTIST");
                xiph->addField("ALBUMARTIST", TagLib::String(albumArtist, TagLib::String::UTF8));
            }
            if (discNumber > 0) {
                xiph->removeFields("DISCNUMBER");
                xiph->addField("DISCNUMBER", TagLib::String(std::to_string(discNumber), TagLib::String::UTF8));
            }
            if (composer) {
                xiph->removeFields("COMPOSER");
                xiph->addField("COMPOSER", TagLib::String(composer, TagLib::String::UTF8));
            }
            if (publisher) {
                xiph->removeFields("PUBLISHER");
                xiph->addField("PUBLISHER", TagLib::String(publisher, TagLib::String::UTF8));
            }
            if (isrc) {
                xiph->removeFields("ISRC");
                xiph->addField("ISRC", TagLib::String(isrc, TagLib::String::UTF8));
            }
            if (bpm > 0) {
                xiph->removeFields("BPM");
                xiph->addField("BPM", TagLib::String(std::to_string(bpm), TagLib::String::UTF8));
            }
        }
    }
    
    return fileRef.save();
}

extern "C" bool UpdateFLACArtwork(const char *filePath, const uint8_t *imageData, size_t imageSize, const char *mimeType) {
    if (!filePath || !imageData || imageSize == 0 || !mimeType) return false;
    
    TagLib::FLAC::File file(filePath);
    if (!file.isValid()) return false;
    
    // Remove existing pictures to avoid duplicates
    file.removePictures();
    
    // Create new picture
    TagLib::FLAC::Picture *picture = new TagLib::FLAC::Picture();
    picture->setData(TagLib::ByteVector((const char *)imageData, (unsigned int)imageSize));
    picture->setType(TagLib::FLAC::Picture::FrontCover);
    picture->setMimeType(TagLib::String(mimeType, TagLib::String::UTF8));
    
    file.addPicture(picture);
    
    return file.save();
}
