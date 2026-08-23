// NowPlayingBar.swift
// ytsplayer
//
// Glassmorphic transport bar pinned to the bottom of the window.
// Reads purely from PlaybackViewModel — zero audio thread interaction.

import SwiftUI
import AVFoundation

struct NowPlayingBar: View {
    @ObservedObject var vm: PlaybackViewModel
    @EnvironmentObject var playlistManager: PlaylistManager
    @Environment(\.openWindow) var openWindow
    
    @State private var isFavoriteLocal = false
    @State private var isQueuePresented = false
    @StateObject private var waveform = WaveformGenerator()
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
                .focusable(false)

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
                
                // Favorite Button
                if let track = vm.currentTrack {
                    Button(action: {
                        if let _ = try? playlistManager.toggleFavorite(forTrackId: track.id) {
                            isFavoriteLocal.toggle()
                            // Update the in-memory track so it persists if we pause/play
                            // But vm.currentTrack is a struct, we can just let UI refresh
                        }
                    }) {
                        Image(systemName: isFavoriteLocal ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .foregroundColor(isFavoriteLocal ? .red : .white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                }
            }
            .frame(minWidth: 150, idealWidth: 240, maxWidth: 280, alignment: .leading)
            .padding(.leading, 20)
            .onChange(of: vm.currentTrack?.id) { _ in
                isFavoriteLocal = vm.currentTrack?.isFavorite ?? false
                if let path = vm.currentTrack?.filePath {
                    waveform.generatePeaks(for: path)
                } else {
                    waveform.peaks = []
                }
            }
            .onAppear {
                if let path = vm.currentTrack?.filePath {
                    waveform.generatePeaks(for: path)
                }
            }

            Spacer()

            // ── CENTER: Transport, Progress, Badges ─────────────────────────
            VStack(spacing: 8) {
                // 1. Controls
                HStack(spacing: 32) {
                    transportButton(systemImage: "backward.fill", size: 20) { vm.skipPrevious() }
                    playPauseButton
                    transportButton(systemImage: "forward.fill", size: 20) { vm.skipNext() }
                }
                
                // 2. Progress Scrubber
                HStack(spacing: 8) {
                    Text(vm.currentTimeString)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 36, alignment: .trailing)

                    GeometryReader { geo in
                        Group {
                            if waveform.peaks.isEmpty {
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
                            } else {
                                WaveformView(peaks: waveform.peaks, progress: vm.playbackProgress)
                            }
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
                        .contentShape(Rectangle())
                        .frame(maxHeight: waveform.peaks.isEmpty ? 12 : 24)
                    }
                    .frame(height: 24)
                    .frame(maxWidth: 320)

                    Text("-" + vm.totalTimeString) // Mockup has negative remaining time usually, but we use total
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 36, alignment: .leading)
                }
                
                // 3. Badges — only show audio info, never device-change noise
                if let err = vm.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                        Text(err)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.85))
                    .clipShape(Capsule())
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 6) {
                        if vm.currentSampleRate > 0 {
                            if vm.currentBitDepth >= 24 {
                                badge(text: "Hi-Res", accent: Color(red: 0.9, green: 0.75, blue: 0.2))
                            }
                            let ext = (vm.currentTrack?.filePath as NSString?)?.pathExtension.uppercased() ?? ""
                            if !ext.isEmpty {
                                badge(text: ext)
                            }
                            let kHz = vm.currentSampleRate / 1000
                            let remainder = vm.currentSampleRate % 1000
                            let rateStr = remainder == 0 ? "\(kHz)kHz" : "\(kHz).\(remainder / 100)kHz"
                            badge(text: rateStr)
                            if vm.currentBitDepth > 0 {
                                badge(text: "\(vm.currentBitDepth)-bit")
                            }
                        }
                    }
                }
            }

            Spacer()

            // ── RIGHT: Volume & Aux ───────────────────────────────────────
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 16) {
                    // Bit-Perfect Toggle
                    Toggle("Bit-Perfect", isOn: $vm.isBitPerfect)
                        .toggleStyle(.switch)
                        .scaleEffect(0.6)
                        .frame(width: 40)
                        .focusable(false)
                        .help("Bit-Perfect Mode: Bypasses software volume for pure, unaltered audio.")
                        .tint(.purple)
                        
                    // Mini-Player Toggle
                    Button(action: { openWindow(id: "MiniPlayer") }) {
                        Image(systemName: "pip.enter")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Open Mini-Player")
                    
                    // Queue Button
                    Button(action: { isQueuePresented.toggle() }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isQueuePresented ? Color.accentColor : Color.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .popover(isPresented: $isQueuePresented, arrowEdge: .top) {
                        QueueView()
                            .environmentObject(vm)
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                        
                        Slider(value: $vm.volume, in: 0...1)
                            .tint(Color.white)
                            .frame(width: 80)
                        
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(width: 130)
                    .disabled(vm.isBitPerfect)
                    .opacity(vm.isBitPerfect ? 0.3 : 1.0)
                    .grayscale(vm.isBitPerfect ? 1.0 : 0.0)
                }
                
                if vm.isBitPerfect {
                    Text("Volume disabled (Bit-Perfect)")
                        .font(.system(size: 9))
                        .foregroundStyle(.purple.opacity(0.8))
                        .padding(.trailing, 16)
                }
            }
            .frame(width: 280, alignment: .trailing)
            .padding(.trailing, 20)
        }
        .frame(height: 120)
        .background(
            ZStack {
                Rectangle()
                    .fill(Material.ultraThin)
                
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.clear,
                        Color.black.opacity(0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.2)),
            alignment: .top
        )
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var artworkView: some View {
        if let path = vm.currentTrack?.albumArtworkPath,
           let cacheDir = ImageDownsampler.artworkCacheDirectory() {
            let url = cacheDir.appendingPathComponent(path)
            CachedAsyncImage(url: url) {
                placeholderArt
            }
            .scaledToFill()
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
        .focusable(false)
        .disabled(vm.currentTrack == nil)
    }

    private func transportButton(systemImage: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size + 2))
                .foregroundStyle(.white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(vm.currentTrack == nil)
    }

    private func badge(text: String, accent: Color = .white) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(accent.opacity(0.9))
            .background(
                Capsule()
                    .stroke(accent.opacity(0.3), lineWidth: 1)
            )
    }
}

struct WaveformView: View {
    let peaks: [Float]
    let progress: Double
    
    var body: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width / CGFloat(peaks.count)
            let playedWidth = geo.size.width * progress
            
            HStack(alignment: .center, spacing: 0) {
                ForEach(0..<peaks.count, id: \.self) { i in
                    let height = max(3.0, CGFloat(peaks[i]) * geo.size.height)
                    let isPlayed = (CGFloat(i) * barWidth) < playedWidth
                    
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(isPlayed ? AnyShapeStyle(LinearGradient(colors: [.purple, .indigo], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.15)))
                        .frame(width: max(1.0, barWidth - 1), height: height)
                        .padding(.horizontal, 0.5)
                        .shadow(color: isPlayed ? .purple.opacity(0.4) : .clear, radius: 2, y: 0)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

final class WaveformGenerator: ObservableObject {
    @Published var peaks: [Float] = []
    
    func generatePeaks(for filePath: String) {
        self.peaks = []
        let url = URL(fileURLWithPath: filePath)
        DispatchQueue.global(qos: .userInitiated).async {
            guard let file = try? AVAudioFile(forReading: url) else { return }
            
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            // Instead of fully decoding the file, read small sparse chunks for the waveform
            let targetPeakCount = 100
            let stride = Int(frameCount) / targetPeakCount
            let framesToReadPerPeak = AVAudioFrameCount(min(stride, 1024))
            
            guard stride > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToReadPerPeak) else { return }
            
            var newPeaks: [Float] = []
            for i in 0..<targetPeakCount {
                do {
                    file.framePosition = AVAudioFramePosition(i * stride)
                    try file.read(into: buffer, frameCount: framesToReadPerPeak)
                    guard let channelData = buffer.floatChannelData else { continue }
                    
                    let length = Int(buffer.frameLength)
                    if length == 0 {
                        newPeaks.append(0)
                        continue
                    }
                    var sumSquare: Float = 0.0
                    for j in 0..<length {
                        let sample = channelData[0][j]
                        sumSquare += sample * sample
                    }
                    let rms = sqrt(sumSquare / Float(length))
                    newPeaks.append(pow(rms, 0.45)) // Enhance lower amplitudes
                } catch {
                    newPeaks.append(0)
                }
            }
            
            let maxPeak = newPeaks.max() ?? 1.0
            let safeMax = maxPeak > 0 ? maxPeak : 1.0
            let normalized = newPeaks.map { $0 / safeMax }
            
            DispatchQueue.main.async {
                self.peaks = normalized
            }
        }
    }
}
