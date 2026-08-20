// NowPlayingBar.swift
// ytsplayer
//
// Glassmorphic transport bar pinned to the bottom of the window.
// Reads purely from PlaybackViewModel — zero audio thread interaction.

import SwiftUI

struct NowPlayingBar: View {
    @ObservedObject var vm: PlaybackViewModel
    var onArtworkTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            
            // ── LEFT: Artwork + Track Info ────────────────────────────────
            HStack(spacing: 12) {
                Button(action: { onArtworkTap?() }) {
                    ZStack(alignment: .bottomTrailing) {
                        artworkView
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                        
                        if (vm.currentTrack?.bitDepth ?? 0) >= 24 {
                            if let nsImage = NSImage(named: "hires.png") {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 16)
                                    .padding(4)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.currentTrack?.title ?? "Nothing Playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let artist = vm.currentTrack?.artistName, !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    if let artist = vm.currentTrack?.artistName, !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 160, alignment: .leading)
            }
            .frame(width: 280, alignment: .leading)
            .padding(.leading, 20)

            Spacer()

            // ── CENTER: Transport, Progress, Badges ─────────────────────────
            VStack(spacing: 8) {
                // 1. Controls
                HStack(spacing: 24) {
                    transportButton(systemImage: "shuffle", size: 14) {} // Mock
                    transportButton(systemImage: "backward.fill", size: 16) { vm.skipPrevious() }
                    playPauseButton
                    transportButton(systemImage: "forward.fill", size: 16) { vm.skipNext() }
                    transportButton(systemImage: "repeat", size: 14) {} // Mock
                }
                
                // 2. Progress Scrubber
                HStack(spacing: 8) {
                    Text(vm.currentTimeString)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 36, alignment: .trailing)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 4)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .indigo],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geo.size.width * vm.playbackProgress,
                                    height: 4
                                )
                                .shadow(color: .purple.opacity(0.5), radius: 3, y: 0)
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
                        .frame(height: 12)
                        .contentShape(Rectangle())
                    }
                    .frame(height: 12)
                    .frame(maxWidth: 320)

                    Text("-" + vm.totalTimeString) // Mockup has negative remaining time usually, but we use total
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 36, alignment: .leading)
                }
                
                // 3. Badges — only show audio info, never device-change noise
                HStack(spacing: 6) {
                    if vm.currentSampleRate > 0 {
                        if vm.currentBitDepth >= 24 {
                            badge(text: "Hi-Res", gradient: [.orange, .pink])
                        }
                        let ext = (vm.currentTrack?.filePath as NSString?)?.pathExtension.uppercased() ?? ""
                        if !ext.isEmpty {
                            badge(text: ext, gradient: [Color.white.opacity(0.4), Color.white.opacity(0.2)])
                        }
                        let kHz = vm.currentSampleRate / 1000
                        let remainder = vm.currentSampleRate % 1000
                        let rateStr = remainder == 0 ? "\(kHz)kHz" : "\(kHz).\(remainder / 100)kHz"
                        badge(text: rateStr, gradient: [.purple.opacity(0.8), .indigo.opacity(0.8)])
                        if vm.currentBitDepth > 0 {
                            badge(text: "\(vm.currentBitDepth)-bit", gradient: [.cyan.opacity(0.6), .blue.opacity(0.6)])
                        }
                    }
                }
            }

            Spacer()

            // ── RIGHT: Volume & Aux ───────────────────────────────────────
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 12) {
                    // Bit-Perfect Toggle
                    Toggle("Bit-Perfect", isOn: $vm.isBitPerfect)
                        .toggleStyle(.switch)
                        .scaleEffect(0.6)
                        .frame(width: 40)
                        .help("Bit-Perfect Mode: Bypasses software volume for pure, unaltered audio.")
                        .tint(.purple)

                    // Volume Slider
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(vm.isBitPerfect ? .white.opacity(0.2) : .white.opacity(0.5))
                        
                        Slider(value: $vm.volume, in: 0...1)
                            .frame(width: 70)
                            .tint(.purple)
                            .disabled(vm.isBitPerfect)
                        
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(vm.isBitPerfect ? .white.opacity(0.2) : .white.opacity(0.5))
                    }
                    
                    Button(action: {}) { Image(systemName: "music.note.list").foregroundStyle(.white.opacity(0.7)) }.buttonStyle(.plain)
                    Button(action: {}) { Image(systemName: "airplayaudio").foregroundStyle(.white.opacity(0.7)) }.buttonStyle(.plain)
                }
                
                if vm.isBitPerfect {
                    Text("Volume disabled (Bit-Perfect Mode)")
                        .font(.system(size: 9))
                        .foregroundStyle(.purple.opacity(0.8))
                        .padding(.trailing, 46) // Align under slider
                }
            }
            .frame(width: 280, alignment: .trailing)
            .padding(.trailing, 20)
        }
        .frame(height: 96) // Slightly taller
        .background(Material.ultraThinMaterial)
        // Removed Divider to reduce harsh lines
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
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hue: 0.7, saturation: 0.8, brightness: 0.4),
                             Color(hue: 0.6, saturation: 0.6, brightness: 0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
            )
    }

    private var playPauseButton: some View {
        Button(action: { vm.togglePlayPause() }) {
            Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(Color.white.opacity(0.12))
                )
                .scaleEffect(vm.isPlaying ? 0.95 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: vm.isPlaying)
        }
        .buttonStyle(.plain)
        .disabled(vm.currentTrack == nil)
    }

    private func transportButton(systemImage: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size + 2))
                .foregroundStyle(.white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .disabled(vm.currentTrack == nil)
    }

    private func badge(text: String, gradient: [Color]) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .stroke(
                        LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing),
                        lineWidth: 1
                    )
                    .background(Capsule().fill(Color.white.opacity(0.05)))
            )
            .foregroundStyle(.white.opacity(0.9))
    }
}
