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

struct QueueItem: Identifiable, Equatable {
    let id = UUID()
    let track: TrackViewModel
    
    static func == (lhs: QueueItem, rhs: QueueItem) -> Bool {
        return lhs.id == rhs.id
    }
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
    @Published var queue: [QueueItem]       = []
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
    
    // ── DSP Settings ────────────────────────────────────────────────────────
    
    @Published var eqEnabled: Bool = UserDefaults.standard.bool(forKey: "dspEqEnabled") {
        didSet {
            halEngine.eqEnabled = eqEnabled
            UserDefaults.standard.set(eqEnabled, forKey: "dspEqEnabled")
            if eqEnabled {
                self.isBitPerfect = false
                UserDefaults.standard.set(false, forKey: "isBitPerfect")
                _ = self.halEngine.setHogModeSafe(false)
                UserDefaults.standard.set(false, forKey: "hogModeEnabled")
            }
        }
    }
    
    @Published var crossfeedEnabled: Bool = UserDefaults.standard.bool(forKey: "dspCrossfeedEnabled") {
        didSet {
            halEngine.crossfeedEnabled = crossfeedEnabled
            UserDefaults.standard.set(crossfeedEnabled, forKey: "dspCrossfeedEnabled")
            if crossfeedEnabled {
                self.isBitPerfect = false
                UserDefaults.standard.set(false, forKey: "isBitPerfect")
                _ = self.halEngine.setHogModeSafe(false)
                UserDefaults.standard.set(false, forKey: "hogModeEnabled")
            }
        }
    }
    
    @Published var eqGains: [Float] = (UserDefaults.standard.array(forKey: "dspEqGains") as? [Float]) ?? Array(repeating: 0.0, count: 10) {
        didSet {
            for (index, gain) in eqGains.enumerated() {
                halEngine.setEQBandGain(index: index, gainDB: gain)
            }
            UserDefaults.standard.set(eqGains, forKey: "dspEqGains")
        }
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
        let defaultHog = UserDefaults.standard.object(forKey: "hogModeEnabled") as? Bool ?? false
        _ = self.halEngine.setHogModeSafe(defaultHog)
        
        self.halEngine.eqEnabled = self.eqEnabled
        self.halEngine.crossfeedEnabled = self.crossfeedEnabled
        for (index, gain) in self.eqGains.enumerated() {
            self.halEngine.setEQBandGain(index: index, gainDB: gain)
        }
        
        setupRemoteCommandCenter()
    }

    // MARK: - Transport

    func play(track: TrackViewModel, queue: [TrackViewModel], startIndex: Int, context: PlaybackContext = .none) {
        self.queue      = queue.map { QueueItem(track: $0) }
        self.queueIndex = startIndex
        self.currentContext = context
        Task { await loadAndPlay(track: track) }
    }
    
    // MARK: - Queue Management
    
    func playNext(_ track: TrackViewModel) {
        if queue.isEmpty {
            play(track: track, queue: [track], startIndex: 0)
        } else {
            queue.insert(QueueItem(track: track), at: queueIndex + 1)
        }
    }
    
    func enqueue(_ track: TrackViewModel) {
        if queue.isEmpty {
            play(track: track, queue: [track], startIndex: 0)
        } else {
            queue.append(QueueItem(track: track))
        }
    }
    
    func moveInQueue(from source: IndexSet, to destination: Int) {
        // Since we are modifying the queue, we need to adjust `queueIndex` if the current playing song moves.
        guard queue.indices.contains(queueIndex) else { return }
        let currentItemId = queue[queueIndex].id
        queue.move(fromOffsets: source, toOffset: destination)
        if let newIndex = queue.firstIndex(where: { $0.id == currentItemId }) {
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
                    play(track: queue[queueIndex].track, queue: queue.map { $0.track }, startIndex: queueIndex, context: currentContext)
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
            play(track: queue[nextIndex].track, queue: queue.map { $0.track }, startIndex: nextIndex, context: currentContext)
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
            play(track: queue[prevIndex].track, queue: queue.map { $0.track }, startIndex: prevIndex, context: currentContext)
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

        // CRITICAL: Perform synchronous file I/O and bookmark resolution on a background thread
        // to prevent locking up the main thread (beachballing) on slow network/cloud drives.
        let effectivePath = track.filePath
        let resolutionResult = await Task.detached { () -> (Bool, URL?) in
            let fm = FileManager.default
            if !fm.fileExists(atPath: effectivePath) {
                return (false, nil)
            }
            
            var resolvedURL: URL? = nil
            if let bookmarks = UserDefaults.standard.dictionary(forKey: "libraryBookmarks") as? [String: Data] {
                for (_, bookmarkData) in bookmarks {
                    var isStale = false
                    if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                        if effectivePath.hasPrefix(url.path) {
                            if url.startAccessingSecurityScopedResource() {
                                resolvedURL = url
                                NSLog("[ytsplayer] Security scope granted via library bookmark: \(url.path)")
                                break
                            }
                        }
                    }
                }
            }
            
            // Fallback: If not found in bookmarks, try accessing it directly
            if resolvedURL == nil {
                let fileURL = URL(fileURLWithPath: effectivePath)
                if fileURL.startAccessingSecurityScopedResource() {
                    resolvedURL = fileURL
                    NSLog("[ytsplayer] Security scope granted directly on file URL")
                }
            }
            return (true, resolvedURL)
        }.value
        
        if !resolutionResult.0 {
            isBuffering = false
            isPlaying = false
            errorMessage = "File not found or drive disconnected."
            return
        }
        
        var securityScopedURL = resolutionResult.1
        
        if securityScopedURL == nil {
            NSLog("[ytsplayer] WARNING: File is outside all library folders. Requesting user access via open panel.")
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                // NSOpenPanel must run on the main thread
                DispatchQueue.main.async {
                    let panel = NSOpenPanel()
                    panel.message = "YM Pro needs permission to access this file's folder.\nPlease click \"Grant Access\" to allow playback."
                    panel.prompt = "Grant Access"
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.canCreateDirectories = false
                    panel.directoryURL = URL(fileURLWithPath: effectivePath).deletingLastPathComponent()
                    panel.begin { response in
                        if response == .OK, let url = panel.url {
                            continuation.resume(returning: url)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
            
            if let grantedURL = granted {
                if let data = try? grantedURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    var bookmarks = (UserDefaults.standard.dictionary(forKey: "libraryBookmarks") as? [String: Data]) ?? [:]
                    bookmarks[grantedURL.path] = data
                    UserDefaults.standard.set(bookmarks, forKey: "libraryBookmarks")
                }
                if grantedURL.startAccessingSecurityScopedResource() {
                    securityScopedURL = grantedURL
                    NSLog("[ytsplayer] Security scope granted after user approval: \(grantedURL.path)")
                }
            } else {
                NSLog("[ytsplayer] User denied access — cannot play: \(effectivePath)")
                isBuffering = false
                isPlaying = false
                errorMessage = "Access denied. Please grant permission to the folder containing this file."
                return
            }
        }
        
        // Apply ReplayGain based on settings
        let rgMode = UserDefaults.standard.string(forKey: "replayGainMode") ?? "album"
        var gainScalar: Float = 1.0
        if rgMode != "off" {
            // Extract metadata on a background thread so disk I/O doesn't hang UI
            let metaResult = await Task.detached { () -> (Bool, Double, Double) in
                var meta = ExtractedTrackMetadata()
                let success = ExtractFLACMetadata((effectivePath as NSString).utf8String, &meta)
                defer { ExtractedMetadata_FreeArtwork(&meta) }
                return (success, meta.replayGainTrack, meta.replayGainAlbum)
            }.value
            
            if metaResult.0 {
                let trackGain = metaResult.1
                let albumGain = metaResult.2
                
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
            NSLog("[ytsplayer] PlaybackViewModel: loadTrack returned false! Setting errorMessage for UI.")
            errorMessage = "Audio format not supported or hardware rejected sample rate. Enable Downsampling in Settings."
        }
        
        // Release the security scope after the decoder has opened the file
        // (The C decoder keeps its own file handle open, so we can release the scope now)
        securityScopedURL?.stopAccessingSecurityScopedResource()
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

        if isPlaying != enginePlaying {
            isPlaying = enginePlaying
        }

        if totalFrames > 0 && !isScrubbing {
            let newProgress = min(1.0, Double(currentFrame) / Double(totalFrames))
            if playbackProgress != newProgress {
                playbackProgress = newProgress
            }
        }

        let newCurrent = formatTime(Double(currentFrame) / Double(sampleRate))
        if currentTimeString != newCurrent { currentTimeString = newCurrent }

        let newTotal = formatTime(Double(totalFrames)  / Double(sampleRate))
        if totalTimeString != newTotal { totalTimeString = newTotal }

        // Buffering indicator
        let available = RingBuffer_AvailableToRead(halEngine.context.pointee.ringBuffer)
        let capacity  = halEngine.context.pointee.ringBuffer?.pointee.capacityFrames ?? 1
        let newBuffering = enginePlaying && available < capacity / 10
        if isBuffering != newBuffering { isBuffering = newBuffering }
        
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
                    currentTrack = queue[nextIndex].track
                    // Trigger UI updates
                    updateNowPlayingInfo()
                    onTrackPlayed?(queue[nextIndex].track.id)
                }
            }
            
            // 2. Enqueue next track when approaching end
            if isGaplessEnabled && !gaplessTrackEnqueued && playbackProgress > 0.95 {
                let nextIndex = queueIndex + 1
                if nextIndex < queue.count {
                    let next = queue[nextIndex].track
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
    private func updateWidget() {
        let fileManager = FileManager.default
        
        // Check if the App Group is actually accessible before trying to write.
        // This prevents noisy sandbox violation logs if the developer profile
        // doesn't have the App Group entitlement fully configured.
        guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.yonesh.ympro.mac") else {
            return
        }
        
        if let defaults = UserDefaults(suiteName: "group.com.yonesh.ympro.mac") {
            defaults.set(currentTrack?.title ?? "Nothing Playing", forKey: "widget_title")
            defaults.set(currentTrack?.artistName ?? "", forKey: "widget_artist")
            defaults.set(currentTrack?.albumArtworkPath ?? "", forKey: "widget_artworkPath")
            defaults.set(isPlaying, forKey: "widget_isPlaying")
        }
        
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
        
        WidgetCenter.shared.reloadAllTimelines()
    }
}
