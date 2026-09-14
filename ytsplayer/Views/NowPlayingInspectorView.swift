// NowPlayingInspectorView.swift
// ytsplayer

import SwiftUI

struct NowPlayingInspectorView: View {
    @ObservedObject var vm: PlaybackViewModel
    var onArtworkTap: (() -> Void)? = nil
    @State private var draggedItem: QueueItem?
    
    private var artworkURL: URL? {
        guard let path = vm.currentTrack?.albumArtworkPath else { return nil }
        let cacheDir = ImageDownsampler.artworkCacheDirectory()
        return cacheDir?.appendingPathComponent(path)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            if let track = vm.currentTrack {
                // Large Artwork
                Button(action: { onArtworkTap?() }) {
                    ZStack {
                        if let url = artworkURL {
                            CachedAsyncImage(url: url) {
                                fallbackArtwork
                            }
                            .scaledToFit()
                        } else {
                            fallbackArtwork
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 15, y: 10)
                }
                .buttonStyle(.plain)
                .focusable(false)
                
                // Track Info
                VStack(spacing: 8) {
                    Text(track.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text(track.artistName ?? "Unknown Artist")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    if let album = track.albumTitle {
                        Text(album)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal)
                
                // Audio Specs Badge
                HStack(spacing: 6) {
                    if vm.currentBitDepth >= 24 {
                        Image(systemName: "hifispeaker.fill")
                            .foregroundStyle(.purple)
                        Text("Hi-Res Lossless")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.purple)
                    } else {
                        Image(systemName: "hifispeaker")
                            .foregroundStyle(.secondary)
                        Text("Lossless")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        
                    Text("\(vm.currentBitDepth)-bit / \(vm.currentSampleRate / 1000)kHz")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                
                Divider().background(Color.primary.opacity(0.1)).padding(.vertical, 8)
                
                // Up Next Queue
                VStack(alignment: .leading, spacing: 12) {
                    Text("Up Next")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 4)
                    
                    if vm.queue.isEmpty {
                        Text("Queue is empty")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 8) {
                                let startIndex = vm.queueIndex + 1
                                if startIndex < vm.queue.count {
                                    ForEach(Array(vm.queue[startIndex...].enumerated()), id: \.element.id) { index, queueItem in
                                        let upcomingTrack = queueItem.track
                                        InspectorQueueRow(track: upcomingTrack, index: index + 1)
                                            .onTapGesture {
                                                vm.play(track: upcomingTrack, queue: vm.queue.map { $0.track }, startIndex: startIndex + index, context: vm.currentContext)
                                            }
                                            .onDrag {
                                                self.draggedItem = queueItem
                                                return NSItemProvider(object: queueItem.id.uuidString as NSString)
                                            }
                                            .onDrop(of: [.plainText], delegate: QueueDropDelegate(item: queueItem, items: vm.queue, playbackVM: vm, draggedItem: $draggedItem))
                                    }
                                } else {
                                    Text("End of Queue")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 16)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer(minLength: 0)
                
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Not Playing")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                if let url = artworkURL, vm.currentTrack != nil {
                    CachedAsyncImage(url: url) {
                        Color.clear
                    }
                    .scaledToFill()
                    .blur(radius: 80, opaque: true)
                    .saturation(1.5)
                    .opacity(0.8)
                    .ignoresSafeArea()
                } else {
                    fallbackArtwork
                        .blur(radius: 80, opaque: true)
                        .ignoresSafeArea()
                }
                
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
        )
    }
    
    private var fallbackArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [Color.purple.opacity(0.4), Color.blue.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.quarternote.3")
                .font(.system(size: 64))
                .foregroundStyle(.primary.opacity(0.5))
        }
    }
}

struct InspectorQueueRow: View {
    let track: TrackViewModel
    let index: Int
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.5))
                .frame(width: 20, alignment: .trailing)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if let artist = track.artistName {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Text(formatTime(track.duration))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.7))
                
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.leading, 4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .contentShape(Rectangle())
    }
    
    private func formatTime(_ time: Double) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%d:%02d", m, s)
    }
}
