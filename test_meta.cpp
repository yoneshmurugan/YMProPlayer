#include <iostream>
#include "ytsplayer/Engine/MetadataBridge.h"
int main() {
    ExtractedTrackMetadata meta;
    if (ExtractFLACMetadata("/Users/yonesh/pCloud Drive/Tamil/0Anirudh Ravichander/1 Singles/05 - Yaanji.flac", &meta)) {
        std::cout << "Title: " << meta.title << "\n";
        std::cout << "Artist: " << meta.artist << "\n";
        std::cout << "Album: " << meta.album << "\n";
    } else {
        std::cout << "Failed to extract\n";
    }
    return 0;
}
