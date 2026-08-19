#include <iostream>
#include <taglib/flacfile.h>
#include <taglib/tpropertymap.h>

int main() {
    TagLib::FLAC::File file("/Users/yonesh/pCloud Drive/Tamil/0A.R. Rahman/Padayappa/Padayappa Theme Music.flac");
    TagLib::PropertyMap pm = file.properties();
    std::cout << "TITLE: " << (pm.contains("TITLE") ? pm["TITLE"].front().to8Bit(true) : "none") << "\n";
    std::cout << "ARTIST: " << (pm.contains("ARTIST") ? pm["ARTIST"].front().to8Bit(true) : "none") << "\n";
    std::cout << "ALBUM: " << (pm.contains("ALBUM") ? pm["ALBUM"].front().to8Bit(true) : "none") << "\n";
    return 0;
}
