// PlaybackViewModel.swift
// ytsplayer

import SwiftUI
import Combine
import MediaPlayer

enum PlaybackContext: Equatable {
    case none
    case album(albumId: Int64)
    case hierarchy(folderUrl: URL)
    case quickPicks
    case allTracks
}

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
    
    @Published var currentContext: PlaybackContext = .none
    var onQueueEnded: (() -> Void)?
    var onTrackPlayed: ((Int64) -> Void)?

    @Published var isBitPerfect: Bool = true {
        didSet {
            halEngine.isBitPerfect = isBitPerfect
            _ = halEngine.setHogModeSafe(isBitPerfect)
        }
    }
    @Published var volume: Double = 1.0 {
        didSet { halEngine.softwareVolume = Float(volume) }
    }

    let halEngine: CoreAudioHALEngine
    private var pollerCancellable: AnyCancellable?
    private var deviceCancellable: AnyCancellable?

    init(halEngine: CoreAudioHALEngine) {
        self.halEngine = halEngine
        startPoller()
        observeDeviceChanges()
        
        // Sync initial Bit-Perfect state to hardware Hog Mode
        self.halEngine.isBitPerfect = self.isBitPerfect
        _ = self.halEngine.setHogModeSafe(self.isBitPerfect)
        
        setupRemoteCommandCenter()
    }

    // MARK: - Transport

    func play(track: TrackViewModel, queue: [TrackViewModel], startIndex: Int, context: PlaybackContext = .none) {
        self.queue      = queue
        self.queueIndex = startIndex
        self.currentContext = context
        Task { await loadAndPlay(track: track) }
    }
    
    // MARK: - Queue Management
    
    func playNext(_ track: TrackViewModel) {
        if queue.isEmpty {
            play(track: track, queue: [track], startIndex: 0)
        } else {
            queue.insert(track, at: queueIndex + 1)
        }
    }
    
    func enqueue(_ track: TrackViewModel) {
        if queue.isEmpty {
            play(track: track, queue: [track], startIndex: 0)
        } else {
            queue.append(track)
        }
    }
    
    func moveInQueue(from source: IndexSet, to destination: Int) {
        // Since we are modifying the queue, we need to adjust `queueIndex` if the current playing song moves.
        let currentTrackId = queue[queueIndex].id
        queue.move(fromOffsets: source, toOffset: destination)
        if let newIndex = queue.firstIndex(where: { $0.id == currentTrackId }) {
            queueIndex = newIndex
        }
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
        updateNowPlayingInfo()
    }
    
    func clearQueueAndStop() {
        let ctx = halEngine.context
        AEC_SetIsPlaying(ctx, false)
        isPlaying = false
        playbackProgress = 0.0
        currentTimeString = "0:00"
        totalTimeString = "0:00"
        currentTrack = nil
        queue = []
        queueIndex = 0
    }

    func skipNext() {
        guard !queue.isEmpty else { return }
        let nextIndex = queueIndex + 1
        if nextIndex < queue.count {
            play(track: queue[nextIndex], queue: queue, startIndex: nextIndex, context: currentContext)
        } else {
            onQueueEnded?()
        }
    }

    func skipPrevious() {
        guard !queue.isEmpty else { return }
        let elapsed = Double(halEngine.currentFrameValue) / Double(max(1, currentSampleRate))
        if elapsed > 3.0 || queueIndex == 0 {
            // Restart current track
            seek(to: 0)
        } else {
            let prevIndex = queueIndex - 1
            play(track: queue[prevIndex], queue: queue, startIndex: prevIndex, context: currentContext)
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

        // Let CoreAudioHALEngine re-assert Hog Mode internally after stream setup

        // Check if the file exists (e.g. drive disconnected)
        if !FileManager.default.fileExists(atPath: track.filePath) {
            isBuffering = false
            isPlaying = false
            errorMessage = "File not found or drive disconnected."
            return
        }

        let ok = await halEngine.loadTrack(filePath: track.filePath, expectedSampleRate: Double(track.sampleRate))
        isBuffering = false
        isPlaying   = ok
        updateNowPlayingInfo()
        if ok {
            AEC_SetIsPlaying(halEngine.context, true)
            // Track play count
            onTrackPlayed?(track.id)
        } else {
            errorMessage = "Audio format not supported or hardware rejected sample rate. Enable Downsampling in Settings."
        }
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
                // Engine handles device fallback automatically — no user-facing error needed
                self?.isPlaying = false
            }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let t = Int(seconds)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
    
    // MARK: - Media Keys & Control Center
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self, !self.isPlaying else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self, self.isPlaying else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipNext()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.skipPrevious()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let duration = self.currentTrack?.duration ?? 0
            if duration > 0 {
                let progress = event.positionTime / duration
                self.seek(to: progress)
            }
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.artistName ?? "Unknown Artist"
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = track.albumTitle ?? "Unknown Album"
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = track.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackProgress * track.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        if let cachePath = track.albumArtworkPath {
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ytsplayer/artwork")
            let url = cacheDir.appendingPathComponent(cachePath)
            if let image = NSImage(contentsOf: url) {
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}
