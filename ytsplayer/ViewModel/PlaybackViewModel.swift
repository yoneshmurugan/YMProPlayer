// PlaybackViewModel.swift
// ytsplayer

import SwiftUI
import Combine

@MainActor
final class PlaybackViewModel: ObservableObject {

    @Published var isPlaying: Bool          = false
    @Published var playbackProgress: Double = 0.0
    @Published var currentTimeString: String = "0:00"
    @Published var totalTimeString: String   = "0:00"
    @Published var currentSampleRate: Int   = 0
    @Published var currentBitDepth: Int     = 0
    @Published var currentTrack: TrackViewModel?
    @Published var queue: [TrackViewModel]  = []
    @Published var queueIndex: Int          = 0
    @Published var isBuffering: Bool        = false
    @Published var isScrubbing: Bool        = false
    @Published var errorMessage: String?

    let halEngine: CoreAudioHALEngine
    private var pollerCancellable: AnyCancellable?
    private var deviceCancellable: AnyCancellable?

    init(halEngine: CoreAudioHALEngine) {
        self.halEngine = halEngine
        startPoller()
        observeDeviceChanges()
    }

    // MARK: - Transport

    func play(track: TrackViewModel, queue: [TrackViewModel], startIndex: Int) {
        self.queue      = queue
        self.queueIndex = startIndex
        Task { await loadAndPlay(track: track) }
    }

    func togglePlayPause() {
        let ctx = halEngine.context
        if isPlaying {
            AEC_SetIsPlaying(ctx, false)
            isPlaying = false
        } else {
            AEC_SetIsPlaying(ctx, true)
            isPlaying = true
        }
    }

    func skipNext() {
        guard queueIndex + 1 < queue.count else { return }
        queueIndex += 1
        Task { await loadAndPlay(track: queue[queueIndex]) }
    }

    func skipPrevious() {
        let elapsed = Double(halEngine.currentFrameValue) / Double(max(1, currentSampleRate))
        if elapsed > 3.0 || queueIndex == 0 {
            Task { await loadAndPlay(track: queue[queueIndex]) }
        } else {
            queueIndex -= 1
            Task { await loadAndPlay(track: queue[queueIndex]) }
        }
    }

    func seek(to fraction: Double) {
        let total  = halEngine.totalFramesValue
        let target = UInt64(fraction * Double(total))
        halEngine.seek(to: target)
        AEC_SetCurrentFrame(halEngine.context, target)
    }

    // MARK: - Private

    private func loadAndPlay(track: TrackViewModel) async {
        errorMessage      = nil
        isBuffering       = true
        currentTrack      = track
        currentSampleRate = track.sampleRate
        currentBitDepth   = track.bitDepth

        if !halEngine.isHogMode { halEngine.acquireHogMode() }

        let ok = await halEngine.loadTrack(filePath: track.filePath)
        isBuffering = false
        isPlaying   = ok
        if !ok { errorMessage = "Failed to load: \(track.title)" }
    }

    // MARK: - 30Hz Poller

    private func startPoller() {
        pollerCancellable = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.syncFromEngine() }
    }

    private func syncFromEngine() {
        let enginePlaying = halEngine.isPlayingValue
        let currentFrame  = halEngine.currentFrameValue
        let totalFrames   = halEngine.totalFramesValue
        let sampleRate    = max(1, halEngine.context.pointee.sampleRate)

        // Auto-advance queue on track end
        if isPlaying && !enginePlaying && totalFrames > 0 && currentFrame >= totalFrames {
            isPlaying = false
            skipNext()
            return
        }

        isPlaying = enginePlaying

        if totalFrames > 0 && !isScrubbing {
            playbackProgress = min(1.0, Double(currentFrame) / Double(totalFrames))
        }

        currentTimeString = formatTime(Double(currentFrame) / Double(sampleRate))
        totalTimeString   = formatTime(Double(totalFrames)  / Double(sampleRate))

        // Buffering indicator
        let available = RingBuffer_AvailableToRead(halEngine.context.pointee.ringBuffer)
        let capacity  = halEngine.context.pointee.ringBuffer?.pointee.capacityFrames ?? 1
        isBuffering   = enginePlaying && available < capacity / 10
    }

    private func observeDeviceChanges() {
        deviceCancellable = NotificationCenter.default
            .publisher(for: .audioDeviceDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isPlaying    = false
                self?.errorMessage = "Audio device changed — press play to continue."
            }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let t = Int(seconds)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
