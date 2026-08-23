import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var vm: PlaybackViewModel
    @State private var isHovered = false
    @State private var showQueue = false
    @Environment(\.dismiss) var dismiss
    
    private var artworkURL: URL? {
        guard let path = vm.currentTrack?.albumArtworkPath else { return nil }
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ytsplayer/artwork")
        return cacheDir.appendingPathComponent(path)
    }
    
    var body: some View {
        ZStack {
            // Background Artwork (Full Bleed)
            if let url = artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    LinearGradient(colors: [Color.purple.opacity(0.8), Color.blue.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            } else {
                LinearGradient(colors: [Color.black, Color.gray.opacity(0.2)], startPoint: .top, endPoint: .bottom)
            }
            
            // Interactive Glass Overlay
            if isHovered || !vm.isPlaying {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .transition(.opacity)
                
                VStack {
                    // Top Bar: Close & Queue
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(8)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button(action: { showQueue.toggle() }) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(showQueue ? .green : .white.opacity(0.8))
                                .padding(8)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showQueue, arrowEdge: .trailing) {
                            QueueView()
                                .frame(width: 300, height: 400)
                        }
                    }
                    .padding(12)
                    
                    Spacer()
                    
                    // Track Info
                    VStack(spacing: 4) {
                        Text(vm.currentTrack?.title ?? "YM Pro")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(vm.currentTrack?.artistName ?? "No Track Playing")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    
                    Spacer()
                    
                    // Transport Controls
                    HStack(spacing: 28) {
                        Button(action: { vm.skipPrevious() }) {
                            Image(systemName: "backward.end.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { vm.togglePlayPause() }) {
                            Image(systemName: vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { vm.skipNext() }) {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(width: 260, height: 260)
        .cornerRadius(16) // Smooth rounded corners for the entire window
        .onHover { h in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = h
            }
        }
    }
}
// MenuBarAppView.swift
// ytsplayer

import SwiftUI

struct MenuBarAppView: View {
    @EnvironmentObject var vm: PlaybackViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            // Artwork & Info
            HStack(spacing: 12) {
                if let path = vm.currentTrack?.albumArtworkPath,
                   let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                    let url = cacheDir.appendingPathComponent(path)
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ZStack {
                        Rectangle().fill(Color.gray.opacity(0.2))
                        Image(systemName: "music.note").foregroundColor(.gray)
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.currentTrack?.title ?? "Not Playing")
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Text(vm.currentTrack?.artistName ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            
            // Transport Controls
            HStack(spacing: 32) {
                Button(action: { vm.skipPrevious() }) {
                    Image(systemName: "backward.fill").font(.system(size: 16))
                }.buttonStyle(.plain)
                
                Button(action: { vm.togglePlayPause() }) {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                }.buttonStyle(.plain)
                
                Button(action: { vm.skipNext() }) {
                    Image(systemName: "forward.fill").font(.system(size: 16))
                }.buttonStyle(.plain)
            }
            
            // Volume
            HStack {
                Image(systemName: "speaker.fill").foregroundColor(.secondary).font(.caption)
                Slider(value: $vm.volume, in: 0...1).tint(.purple)
                Image(systemName: "speaker.wave.3.fill").foregroundColor(.secondary).font(.caption)
            }
        }
        .padding(16)
        .frame(width: 250)
    }
}
