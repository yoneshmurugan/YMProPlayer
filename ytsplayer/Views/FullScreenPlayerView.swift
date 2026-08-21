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
        HStack(alignment: .top, spacing: 50) {
            
            // LEFT: Artwork + Info
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 20)
                
                // Artwork
                artworkView
                    .frame(maxWidth: 220, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 40, y: 20)

                Spacer().frame(height: 24)

                // Track info
                VStack(alignment: .leading, spacing: 6) {
                    Text(vm.currentTrack?.title ?? "Nothing Playing")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    Text(vm.currentTrack?.artistName ?? "Unknown Artist")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))

                    Text(vm.currentTrack?.albumTitle ?? "Unknown Album")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.45))
                }

                Spacer().frame(height: 20)

                // Audio format badges
                audioSpecBadges
                
                Spacer().frame(height: 32)
                
                // Metadata grid
                metadataGrid
                    .padding(.bottom, 20)
            }
            .frame(width: 320)

            // RIGHT: Lyrics & Close Button
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Lyrics")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.8))
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                .padding(.bottom, 16)
                .padding(.top, 20)

                lyricsPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
        .frame(width: 850, height: 550)
        .background(backgroundLayer)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Subviews

    @ViewBuilder
    private var backgroundLayer: some View {
        if let path = vm.currentTrack?.albumArtworkPath,
           let cacheDir = ImageDownsampler.artworkCacheDirectory() {
            AsyncImage(url: cacheDir.appendingPathComponent(path)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 80)
                    .overlay(Color.black.opacity(0.55))
            } placeholder: {
                Color(red: 0.08, green: 0.05, blue: 0.18)
            }
            .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.05, blue: 0.25), Color(red: 0.04, green: 0.04, blue: 0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        ZStack(alignment: .bottomTrailing) {
            if let path = vm.currentTrack?.albumArtworkPath,
               let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                AsyncImage(url: cacheDir.appendingPathComponent(path)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.1))
                        .overlay(Image(systemName: "music.note").font(.system(size: 60)).foregroundColor(.white.opacity(0.25)))
                }
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .overlay(Image(systemName: "music.note").font(.system(size: 60)).foregroundColor(.white.opacity(0.25)))
            }

            if (vm.currentTrack?.bitDepth ?? 0) >= 24,
               let nsImage = NSImage(named: "hires.png") {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 32)
                    .padding(12)
            }
        }
    }

    @ViewBuilder
    private var audioSpecBadges: some View {
        if let err = vm.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                Text(err)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.85))
            .clipShape(Capsule())
        } else if vm.currentSampleRate > 0 {
            HStack(spacing: 8) {
                let kHz = vm.currentSampleRate / 1000
                let rem = vm.currentSampleRate % 1000
                let rateStr = rem == 0 ? "\(kHz)kHz" : "\(kHz).\(rem / 100)kHz"

                specBadge("FLAC", color: .white.opacity(0.25))
                specBadge("\(vm.currentBitDepth)-bit", color: .cyan.opacity(0.3))
                specBadge(rateStr, color: .purple.opacity(0.5))
                if vm.currentBitDepth >= 24 {
                    specBadge("Hi-Res", color: .orange.opacity(0.5))
                }
            }
        }
    }

    private func specBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var lyricsPanel: some View {
        if let lyrics = vm.currentTrack?.lyrics {
            ScrollView(showsIndicators: false) {
                Text(lyrics)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineSpacing(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 20)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 44))
                    .foregroundColor(.white.opacity(0.25))

                Text("No Lyrics Found")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.5))

                if isFetchingLyrics {
                    ProgressView().tint(.white)
                } else {
                    Button(action: fetchLyrics) {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                            Text("Search Online")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Color.purple.opacity(0.8))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if let err = lyricsError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    @ViewBuilder
    private var metadataGrid: some View {
        if let track = vm.currentTrack {
            Divider().background(Color.white.opacity(0.15)).padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("TRACK INFO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.bottom, 4)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    metaItem("File", value: URL(fileURLWithPath: track.filePath).lastPathComponent)
                    metaItem("Format", value: URL(fileURLWithPath: track.filePath).pathExtension.uppercased())
                    metaItem("Sample Rate", value: {
                        let kHz = track.sampleRate / 1000
                        let rem = track.sampleRate % 1000
                        return rem == 0 ? "\(kHz) kHz" : "\(kHz).\(rem / 100) kHz"
                    }())
                    metaItem("Bit Depth", value: "\(track.bitDepth)-bit")
                    if let num = track.trackNumber { metaItem("Track #", value: "\(num)") }
                }
            }
        }
    }

    private func metaItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
        }
    }

    // MARK: - Lyrics Fetch

    private func fetchLyrics() {
        guard let track = vm.currentTrack else { return }
        isFetchingLyrics = true
        lyricsError = nil

        Task {
            do {
                let fetchedLyrics = try await LyricsService.shared.fetchAndEmbedLyrics(for: track, database: database)
                await MainActor.run {
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
