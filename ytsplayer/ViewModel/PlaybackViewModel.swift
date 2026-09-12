// PlaybackViewModel.swift
// ytsplayer

import SwiftUI
import Combine
import AVFoundation
import MediaPlayer
import WidgetKit

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

    @Published var isBitPerfect: Bool = UserDefaults.standard.object(forKey: "isBitPerfect") as? Bool ?? true {
        didSet {
            halEngine.isBitPerfect = isBitPerfect
        }
    }
    @Published var volume: Double = 1.0 {
        didSet { halEngine.softwareVolume = Float(volume) }
    }
    
    let halEngine: CoreAudioHALEngine
    private var gaplessTrackEnqueued: Bool = false
    private var pollerCancellable: AnyCancellable?
    private var deviceCancellable: AnyCancellable?

    init(halEngine: CoreAudioHALEngine) {
        self.halEngine = halEngine
        startPoller()
        observeDeviceChanges()
        
        // Sync initial states
        self.halEngine.isBitPerfect = self.isBitPerfect
        let defaultHog = UserDefaults.standard.object(forKey: "hogModeEnabled") as? Bool ?? true
        _ = self.halEngine.setHogModeSafe(defaultHog)
        
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
            if currentTrack == nil {
                if !queue.isEmpty {
                    play(track: queue[queueIndex], queue: queue, startIndex: queueIndex, context: currentContext)
                }
            } else {
                halEngine.resumePlayback()
                isPlaying = true
            }
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
        gaplessTrackEnqueued = false

        // Let CoreAudioHALEngine re-assert Hog Mode internally after stream setup

        // Check if the file exists (e.g. drive disconnected)
        if !FileManager.default.fileExists(atPath: track.filePath) {
            isBuffering = false
            isPlaying = false
            errorMessage = "File not found or drive disconnected."
            return
        }
        
        var effectivePath = track.filePath
        
        // Smart Cloud Pre-buffering
        if effectivePath.contains("pCloud Drive") && track.sortSize > 50_000_000 { // > 50MB
            if let cached = await bufferTrackToLocalCache(path: effectivePath) {
                effectivePath = cached
            }
        }
        
        // Apply ReplayGain based on settings
        let rgMode = UserDefaults.standard.string(forKey: "replayGainMode") ?? "album"
        var gainScalar: Float = 1.0
        if rgMode != "off" {
            var meta = ExtractedTrackMetadata()
            if ExtractFLACMetadata((effectivePath as NSString).utf8String, &meta) {
                let trackGain = meta.replayGainTrack
                let albumGain = meta.replayGainAlbum
                
                var targetGain = 0.0
                if rgMode == "album" && albumGain != 0.0 {
                    targetGain = albumGain
                } else if trackGain != 0.0 {
                    targetGain = trackGain
                }
                
                // Convert dB to linear scalar (10^(dB/20))
                if targetGain != 0.0 {
                    gainScalar = Float(pow(10.0, targetGain / 20.0))
                }
                ExtractedMetadata_FreeArtwork(&meta)
            }
        }
        AEC_SetTrackReplayGain(halEngine.context, gainScalar)
        
        // Auto-Sample Rate is fundamentally required by the HAL engine architecture (no software resampler)
        let targetSR = Double(track.sampleRate)

        let ok = await halEngine.loadTrack(filePath: effectivePath, expectedSampleRate: targetSR)
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
        if isPlaying && totalFrames > 0 && currentFrame >= totalFrames {
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
        
        // Gapless Playback Logic
        if enginePlaying && !isScrubbing && totalFrames > 0 {
            let isGaplessEnabled = UserDefaults.standard.bool(forKey: "isGaplessEnabled")
            
            // 1. Detect if we just crossed the gapless boundary
            if gaplessTrackEnqueued && playbackProgress < 0.1 {
                // The C engine seamlessly looped back to 0 frame count for the new track
                gaplessTrackEnqueued = false
                let nextIndex = queueIndex + 1
                if nextIndex < queue.count {
                    queueIndex = nextIndex
                    currentTrack = queue[nextIndex]
                    // Trigger UI updates
                    updateNowPlayingInfo()
                    onTrackPlayed?(queue[nextIndex].id)
                }
            }
            
            // 2. Enqueue next track when approaching end
            if isGaplessEnabled && !gaplessTrackEnqueued && playbackProgress > 0.95 {
                let nextIndex = queueIndex + 1
                if nextIndex < queue.count {
                    let next = queue[nextIndex]
                    // Gapless requires same sample rate for true seamlessness
                    if next.sampleRate == currentSampleRate {
                        halEngine.enqueueNextTrack(filePath: next.filePath)
                        gaplessTrackEnqueued = true
                    }
                }
            }
        }
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
            if self.currentTrack != nil {
                self.halEngine.resumePlayback()
                self.isPlaying = true
                return .success
            }
            return .commandFailed
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
        guard currentTrack != nil else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            if let defaults = UserDefaults(suiteName: "group.com.yonesh.ympro.mac") {
                defaults.set(false, forKey: "isPlaying")
                WidgetCenter.shared.reloadAllTimelines()
            }
            return
        }
        
        var info = [String: Any]()
        if let t = currentTrack {
            info[MPMediaItemPropertyTitle] = t.title
            info[MPMediaItemPropertyArtist] = t.artistName ?? "Unknown Artist"
            if let album = t.albumTitle {
                info[MPMediaItemPropertyAlbumTitle] = album
            }
            info[MPMediaItemPropertyPlaybackDuration] = t.duration
            if let artworkPath = t.albumArtworkPath {
                let fullPath = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0])
                    .appendingPathComponent("ytsplayer/artwork")
                    .appendingPathComponent(artworkPath).path
                if let nsImage = NSImage(contentsOfFile: fullPath) {
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: nsImage.size) { _ in nsImage }
                }
            }
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = halEngine.currentFrameValue > 0 ? (Double(halEngine.currentFrameValue) / Double(max(1, currentSampleRate))) : 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateWidget()
    }
    
    // MARK: - Smart Cloud Buffering
    
    private func bufferTrackToLocalCache(path: String) async -> String? {
        let fm = FileManager.default
        let cacheDir = fm.temporaryDirectory.appendingPathComponent("ytsplayer_cloud_cache")
        
        do {
            if !fm.fileExists(atPath: cacheDir.path) {
                try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            }
            
            // Cleanup old cache files to prevent disk bloat
            cleanupOldCache(in: cacheDir)
            
            let originalURL = URL(fileURLWithPath: path)
            let cachedURL = cacheDir.appendingPathComponent(originalURL.lastPathComponent)
            
            if fm.fileExists(atPath: cachedURL.path) {
                // Already cached
                return cachedURL.path
            }
            
            // Asynchronously copy file
            try await Task.detached(priority: .userInitiated) {
                try fm.copyItem(at: originalURL, to: cachedURL)
            }.value
            
            return cachedURL.path
            
        } catch {
            print("Failed to buffer cloud track: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func cleanupOldCache(in cacheDir: URL) {
        Task.detached(priority: .background) {
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.creationDateKey]) else { return }
            
            // Keep only the most recent 5 tracks
            let sortedFiles = files.sorted {
                let date1 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }
            
            if sortedFiles.count > 5 {
                let toDelete = sortedFiles.dropFirst(5)
                for file in toDelete {
                    try? fm.removeItem(at: file)
                }
            }
        }
    }

    private func updateWidget() {
        if let defaults = UserDefaults(suiteName: "group.com.yonesh.ympro.mac") {
            defaults.set(currentTrack?.title ?? "Nothing Playing", forKey: "widget_title")
            defaults.set(currentTrack?.artistName ?? "", forKey: "widget_artist")
            defaults.set(currentTrack?.albumArtworkPath ?? "", forKey: "widget_artworkPath")
            defaults.set(isPlaying, forKey: "widget_isPlaying")
        }
        
        let fileManager = FileManager.default
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.yonesh.ympro.mac") {
            let widgetImageURL = groupURL.appendingPathComponent("widget_artwork.jpg")
            
            if let cachePath = currentTrack?.albumArtworkPath {
                let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ytsplayer/artwork")
                let sourceURL = cacheDir.appendingPathComponent(cachePath)
                if fileManager.fileExists(atPath: sourceURL.path) {
                    if fileManager.fileExists(atPath: widgetImageURL.path) {
                        try? fileManager.removeItem(at: widgetImageURL)
                    }
                    try? fileManager.copyItem(at: sourceURL, to: widgetImageURL)
                }
            } else {
                if fileManager.fileExists(atPath: widgetImageURL.path) {
                    try? fileManager.removeItem(at: widgetImageURL)
                }
            }
        }
        
        WidgetCenter.shared.reloadAllTimelines()
    }
}
