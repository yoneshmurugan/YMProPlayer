// NowPlayingBar.swift
// ytsplayer
//
// Glassmorphic transport bar pinned to the bottom of the window.
// Reads purely from PlaybackViewModel — zero audio thread interaction.

import SwiftUI

struct NowPlayingBar: View {
    @ObservedObject var vm: PlaybackViewModel

    var body: some View {
        HStack(spacing: 0) {

            // ── Artwork + Track Info ───────────────────────────────────────
            HStack(spacing: 12) {
                artworkView
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.currentTrack?.title ?? "Nothing Playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(vm.currentTrack?.artistName ?? " ")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    // Audio format badges
                    HStack(spacing: 5) {
                        if vm.currentSampleRate > 0 {
                            if vm.currentBitDepth >= 24 {
                                badge(text: "Hi-Res", color: .orange)
                            }
                            let ext = (vm.currentTrack?.filePath as NSString?)?.pathExtension.uppercased() ?? ""
                            badge(text: ext.isEmpty ? "FLAC" : ext, color: .gray)
                            
                            badge(
                                text: "\(vm.currentSampleRate / 1000)kHz",
                                color: sampleRateColor(vm.currentSampleRate)
                            )
                            badge(
                                text: "\(vm.currentBitDepth)-bit",
                                color: bitDepthColor(vm.currentBitDepth)
                            )
                            badge(text: "BIT-PERFECT", color: .blue)
                        }
                        if vm.isBuffering {
                            badge(text: "BUFFERING…", color: .orange)
                        }
                    }
                }
                .frame(minWidth: 160, alignment: .leading)
            }
            .frame(width: 260, alignment: .leading)
            .padding(.leading, 16)

            Spacer()

            // ── Transport Controls ─────────────────────────────────────────
            VStack(spacing: 4) {
                HStack(spacing: 28) {
                    transportButton(systemImage: "backward.fill", size: 15) {
                        vm.skipPrevious()
                    }
                    playPauseButton
                    transportButton(systemImage: "forward.fill", size: 15) {
                        vm.skipNext()
                    }
                }

                // Progress scrubber + time
                HStack(spacing: 8) {
                    Text(vm.currentTimeString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 3)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geo.size.width * vm.playbackProgress,
                                    height: 3
                                )
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { val in
                                    vm.isScrubbing = true
                                    vm.playbackProgress = max(0, min(1, val.location.x / geo.size.width))
                                }
                                .onEnded { val in
                                    let finalScrub = max(0, min(1, val.location.x / geo.size.width))
                                    vm.playbackProgress = finalScrub
                                    vm.seek(to: finalScrub)
                                    vm.isScrubbing = false
                                }
                        )
                        .frame(height: 12) // larger hit area
                        .contentShape(Rectangle())
                    }
                    .frame(height: 12)
                    .frame(width: 200)

                    Text(vm.totalTimeString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                }
            }

            Spacer()

            // ── Right side: error / device info ───────────────────────────
            if let err = vm.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .padding(.trailing, 16)
                    .lineLimit(1)
            }
        }
        .frame(height: 72)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var artworkView: some View {
        if let path = vm.currentTrack?.albumArtworkPath,
           let cacheDir = ImageDownsampler.artworkCacheDirectory() {
            let url = cacheDir.appendingPathComponent(path)
            AsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                placeholderArt
            }
        } else {
            placeholderArt
        }
    }

    private var placeholderArt: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hue: 0.7, saturation: 0.6, brightness: 0.3),
                             Color(hue: 0.55, saturation: 0.5, brightness: 0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.5))
            )
    }

    private var playPauseButton: some View {
        Button(action: { vm.togglePlayPause() }) {
            Image(systemName: vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(vm.isPlaying ? 1.0 : 0.95)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: vm.isPlaying)
        }
        .buttonStyle(.plain)
        .disabled(vm.currentTrack == nil)
    }

    private func transportButton(systemImage: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(vm.currentTrack == nil)
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func sampleRateColor(_ rate: Int) -> Color {
        if rate >= 96000 {
            return Color(red: 0.8, green: 0.6, blue: 0.0) // Dark Yellow
        } else if rate > 48000 {
            return .orange
        }
        return .yellow
    }

    private func bitDepthColor(_ depth: Int) -> Color {
        if depth > 16 {
            return .yellow
        }
        return .blue
    }
}
