// FullScreenPlayerView.swift
// ytsplayer

import SwiftUI
import GRDB

struct FullScreenPlayerView: View {
    @ObservedObject var vm: PlaybackViewModel
    let database: DatabasePool
    @Environment(\.dismiss) var dismiss
    
    @State private var isFetchingLyrics = false
    @State private var lyricsError: String?
    
    var body: some View {
        ZStack {
            // Background Blur based on current artwork
            if let path = vm.currentTrack?.albumArtworkPath,
               let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                let url = cacheDir.appendingPathComponent(path)
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 60)
                        .overlay(Color.black.opacity(0.4))
                } placeholder: {
                    Color.black
                }
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
            
            // Content
            HStack(spacing: 40) {
                
                // Left: Artwork and Track Info
                VStack(alignment: .leading, spacing: 20) {
                    if let path = vm.currentTrack?.albumArtworkPath,
                       let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                        let url = cacheDir.appendingPathComponent(path)
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.1))
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                            .overlay(Image(systemName: "music.note").font(.system(size: 60)).foregroundColor(.white.opacity(0.3)))
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.currentTrack?.title ?? "Nothing Playing")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        Text(vm.currentTrack?.artistName ?? "Unknown Artist")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text(vm.currentTrack?.albumTitle ?? "Unknown Album")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.5))
                        
                        // Audio Specs
                        if vm.currentSampleRate > 0 {
                            HStack(spacing: 8) {
                                let kHz = vm.currentSampleRate / 1000
                                let rem = vm.currentSampleRate % 1000
                                let rateStr = rem == 0 ? "\(kHz)kHz" : "\(kHz).\(rem/100)kHz"
                                
                                Text("\(vm.currentBitDepth)-bit / \(rateStr)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.white.opacity(0.2)))
                                    .foregroundColor(.white)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
                // Right: Lyrics
                VStack(alignment: .leading) {
                    Text("Lyrics")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .padding(.bottom, 10)
                    
                    if let lyrics = vm.currentTrack?.lyrics {
                        ScrollView(showsIndicators: false) {
                            Text(lyrics)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                                .lineSpacing(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 60)
                        }
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 50))
                                .foregroundColor(.white.opacity(0.3))
                            
                            Text("No Lyrics Found")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.6))
                            
                            if isFetchingLyrics {
                                ProgressView()
                                    .controlSize(.regular)
                                    .tint(.white)
                            } else {
                                Button(action: fetchLyrics) {
                                    HStack {
                                        Image(systemName: "globe")
                                        Text("Search Online")
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.purple)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                
                                if let err = lyricsError {
                                    Text(err)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(60)
            
            // Close Button
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                Spacer()
            }
            .padding(30)
        }
    }
    
    private func fetchLyrics() {
        guard let track = vm.currentTrack else { return }
        isFetchingLyrics = true
        lyricsError = nil
        
        Task {
            do {
                let fetchedLyrics = try await LyricsService.shared.fetchAndEmbedLyrics(for: track, database: database)
                
                await MainActor.run {
                    // Update the view model's current track to trigger UI refresh
                    var updatedTrack = track
                    updatedTrack.lyrics = fetchedLyrics
                    vm.currentTrack = updatedTrack
                    isFetchingLyrics = false
                }
            } catch {
                await MainActor.run {
                    lyricsError = "Could not find lyrics online."
                    isFetchingLyrics = false
                }
            }
        }
    }
}
