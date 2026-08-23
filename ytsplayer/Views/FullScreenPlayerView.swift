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
        FullScreenPlayerContent(
            track: vm.currentTrack,
            sampleRate: vm.currentSampleRate,
            bitDepth: vm.currentBitDepth,
            errorMessage: vm.errorMessage,
            database: database,
            dismiss: dismiss,
            onLyricsFetched: { newLyrics in
                if var updated = vm.currentTrack {
                    updated.lyrics = newLyrics
                    vm.currentTrack = updated
                }
            }
        )
        .environmentObject(vm)
    }
}

struct FullScreenPlayerContent: View {
    let track: TrackViewModel?
    let sampleRate: Int
    let bitDepth: Int
    let errorMessage: String?
    let database: DatabasePool
    let dismiss: DismissAction
    let onLyricsFetched: (String) -> Void
    
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
                    Text(track?.title ?? "Nothing Playing")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    Text(track?.artistName ?? "Unknown Artist")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))

                    Text(track?.albumTitle ?? "Unknown Album")
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
        if let path = track?.albumArtworkPath,
           let cacheDir = ImageDownsampler.artworkCacheDirectory() {
            CachedAsyncImage(url: cacheDir.appendingPathComponent(path)) {
                Color(red: 0.08, green: 0.05, blue: 0.18)
            }
            .scaledToFill()
            .blur(radius: 80)
            .overlay(Color.black.opacity(0.55))
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
        Button(action: {
            if let path = track?.albumArtworkPath,
               let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                let url = cacheDir.appendingPathComponent(path)
                NSWorkspace.shared.open(url)
            }
        }) {
            ZStack(alignment: .bottomTrailing) {
                if let path = track?.albumArtworkPath,
                   let cacheDir = ImageDownsampler.artworkCacheDirectory() {
                    CachedAsyncImage(url: cacheDir.appendingPathComponent(path)) {
                        RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.1))
                            .overlay(Image(systemName: "music.note").font(.system(size: 60)).foregroundColor(.white.opacity(0.25)))
                    }
                    .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .overlay(Image(systemName: "music.note").font(.system(size: 60)).foregroundColor(.white.opacity(0.25)))
                }

                if (track?.bitDepth ?? 0) >= 24,
                   let nsImage = NSImage(named: "hires.png") {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 32)
                        .padding(12)
                }
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    @ViewBuilder
    private var audioSpecBadges: some View {
        if let err = errorMessage {
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
        } else if sampleRate > 0 {
            HStack(spacing: 8) {
                let ext = (track?.filePath as NSString?)?.pathExtension.uppercased() ?? ""
                if !ext.isEmpty {
                    specBadge(ext)
                }
                
                specBadge("\(bitDepth)-bit")
                
                let kHz = sampleRate / 1000
                let rem = sampleRate % 1000
                let rateStr = rem == 0 ? "\(kHz)kHz" : "\(kHz).\(rem / 100)kHz"
                specBadge(rateStr)
                
                if bitDepth >= 24 {
                    specBadge("Hi-Res", accent: Color(red: 0.9, green: 0.75, blue: 0.2))
                }
            }
        }
    }

    private func specBadge(_ text: String, accent: Color = .white) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(accent.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .stroke(accent.opacity(0.3), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var lyricsPanel: some View {
        LyricsOverlayView(database: database)
            // It uses @EnvironmentObject var playbackVM internally
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var metadataGrid: some View {
        if let t = track {
            Divider().background(Color.white.opacity(0.15)).padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("TRACK INFO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.bottom, 4)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    metaItem("File", value: URL(fileURLWithPath: t.filePath).lastPathComponent)
                    metaItem("Format", value: URL(fileURLWithPath: t.filePath).pathExtension.uppercased())
                    metaItem("Sample Rate", value: {
                        let kHz = t.sampleRate / 1000
                        let rem = t.sampleRate % 1000
                        return rem == 0 ? "\(kHz) kHz" : "\(kHz).\(rem / 100) kHz"
                    }())
                    metaItem("Bit Depth", value: "\(t.bitDepth)-bit")
                    if let num = t.trackNumber { metaItem("Track #", value: "\(num)") }
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
        guard let t = track else { return }
        isFetchingLyrics = true
        lyricsError = nil

        Task {
            do {
                let fetchedLyrics = try await LyricsService.shared.fetchAndEmbedLyrics(for: t, database: database)
                await MainActor.run {
                    onLyricsFetched(fetchedLyrics)
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
