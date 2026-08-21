import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var vm: PlaybackViewModel
    @State private var isHovered = false
    @Environment(\.dismiss) var dismiss
    
    private var artworkURL: URL? {
        guard let path = vm.currentTrack?.albumArtworkPath else { return nil }
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ytsplayer/artwork")
        return cacheDir.appendingPathComponent(path)
    }
    
    var body: some View {
        ZStack {
            // Background Artwork
            if let url = artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.black
                }
            } else {
                Color.black
            }
            
            // Hover Overlay
            if isHovered || !vm.isPlaying {
                Color.black.opacity(0.6)
                
                VStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(8)
                    
                    Spacer()
                    
                    Text(vm.currentTrack?.title ?? "Nothing Playing")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal)
                    
                    Text(vm.currentTrack?.artistName ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .padding(.horizontal)
                    
                    HStack(spacing: 24) {
                        Button(action: { vm.skipPrevious() }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { vm.togglePlayPause() }) {
                            Image(systemName: vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { vm.skipNext() }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                    
                    Spacer()
                }
            }
        }
        .frame(width: 200, height: 200)
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = h
            }
        }
    }
}
