// CoreAudioHALEngine.swift
// ytsplayer
//
// High-level Swift wrapper around the CoreAudio Hardware Abstraction Layer.

import CoreAudio
import AudioToolbox
import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let audioDeviceDidChange = Notification.Name("ytsplayer.audioDeviceDidChange")
}

// MARK: - Engine

@MainActor
final class CoreAudioHALEngine {

    // ── Volume & Bit-Perfect Mode ──────────────────────────────────────────

    var isBitPerfect: Bool {
        get { AEC_GetIsBitPerfect(context) }
        set { AEC_SetIsBitPerfect(context, newValue) }
    }

    var softwareVolume: Float {
        get { AEC_GetSoftwareVolume(context) }
        set { AEC_SetSoftwareVolume(context, max(0.0, min(1.0, newValue))) }
    }

    // ── Device Discovery ───────────────────────────────────────────────────────
    private(set) var currentDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private(set) var isHogMode: Bool = false
    private(set) var ioProcID: AudioDeviceIOProcID?

    /// Shared C engine context (ring buffer, atomics)
    let context: UnsafeMutablePointer<AudioEngineContext>

    private var decoderWorker: OpaquePointer?

    // Ring buffer: 131072 frames = power-of-two, ~3s at 44.1kHz
    private let ringBufferCapacity: Int = 131_072

    init() {
        context = AudioEngineContext_Create(ringBufferCapacity)
        currentDeviceID = discoverDefaultOutputDevice()
        registerDeviceChangeListener()
    }

    deinit {
        // Cannot call @MainActor methods from deinit — inline teardown directly
        AEC_SetIsPlaying(context, false)
        if let id = ioProcID {
            AudioDeviceStop(currentDeviceID, id)
            AudioEngine_DestroyIOProc(currentDeviceID, id)
        }
        // Release hog mode if held
        if isHogMode {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyHogMode,
                mScope:    kAudioObjectPropertyScopeGlobal,
                mElement:  kAudioObjectPropertyElementMain
            )
            var pid = pid_t(-1)
            let size = UInt32(MemoryLayout<pid_t>.size)
            AudioObjectSetPropertyData(currentDeviceID, &addr, 0, nil, size, &pid)
        }
        AudioEngineContext_Destroy(context)
    }

    // MARK: - Device Discovery

    private func discoverDefaultOutputDevice() -> AudioObjectID {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        
        if status != noErr || deviceID == kAudioObjectUnknown {
            NSLog("[ytsplayer] Failed to get default output device (status: \(status)). Attempting fallback...")
            // Fallback: get all devices and pick the first one with output streams
            var allDevicesAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope:    kAudioObjectPropertyScopeGlobal,
                mElement:  kAudioObjectPropertyElementMain
            )
            var allSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &allDevicesAddr, 0, nil, &allSize) == noErr {
                let count = Int(allSize) / MemoryLayout<AudioObjectID>.size
                var allDevices = [AudioObjectID](repeating: 0, count: count)
                if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &allDevicesAddr, 0, nil, &allSize, &allDevices) == noErr {
                    for dev in allDevices {
                        var streamAddr = AudioObjectPropertyAddress(
                            mSelector: kAudioDevicePropertyStreams,
                            mScope:    kAudioDevicePropertyScopeOutput,
                            mElement:  kAudioObjectPropertyElementMain
                        )
                        var streamSize: UInt32 = 0
                        if AudioObjectGetPropertyDataSize(dev, &streamAddr, 0, nil, &streamSize) == noErr && streamSize > 0 {
                            NSLog("[ytsplayer] Found fallback output device: \(dev)")
                            return dev
                        }
                    }
                }
            }
        }
        
        NSLog("[ytsplayer] Selected output device: \(deviceID)")
        return deviceID
    }

    // MARK: - Hog Mode

    @discardableResult
    func acquireHogMode() -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var pid = pid_t(ProcessInfo.processInfo.processIdentifier)
        let size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectSetPropertyData(currentDeviceID, &addr, 0, nil, size, &pid)
        isHogMode = (status == noErr)
        return isHogMode
    }

    @discardableResult
    func releaseHogMode() -> Bool {
        guard isHogMode else { return true }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var pid = pid_t(-1)
        let size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectSetPropertyData(currentDeviceID, &addr, 0, nil, size, &pid)
        if status == noErr { isHogMode = false }
        return !isHogMode
    }

    @discardableResult
    func setHogModeSafe(_ enable: Bool) -> Bool {
        let wasPlaying = isPlayingValue
        if wasPlaying { stopPlayback() }
        
        let result = enable ? acquireHogMode() : releaseHogMode()
        
        if wasPlaying { _ = startPlayback() }
        return result
    }

    // MARK: - Sample Rate

    func availableSampleRates() -> [Double] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(currentDeviceID, &addr, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: max(1, count))
        AudioObjectGetPropertyData(currentDeviceID, &addr, 0, nil, &size, &ranges)
        return ranges.map { $0.mMinimum }
    }

    @discardableResult
    func setHardwareSampleRate(_ rate: Double) async -> Bool {
        // Verify support
        var availAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var rangeSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(currentDeviceID, &availAddr, 0, nil, &rangeSize)
        let count = Int(rangeSize) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: max(1, count))
        AudioObjectGetPropertyData(currentDeviceID, &availAddr, 0, nil, &rangeSize, &ranges)
        guard ranges.contains(where: { rate >= $0.mMinimum && rate <= $0.mMaximum }) else {
            NSLog("[ytsplayer] Sample rate \(rate) Hz not supported")
            return false
        }

        // Ramp down → set rate → ramp up
        await rampGain(to: 0.0, steps: 50, durationMs: 50)

        var setAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var targetRate = Float64(rate)
        let dataSize = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectSetPropertyData(currentDeviceID, &setAddr, 0, nil, dataSize, &targetRate)

        await waitForSampleRate(expected: rate, timeoutMs: 200)
        await rampGain(to: 1.0, steps: 50, durationMs: 50)

        if status == noErr {
            context.pointee.sampleRate = UInt32(rate)
        }
        return status == noErr
    }

    private func rampGain(to target: Float, steps: Int, durationMs: Int) async {
        let nsPerStep = UInt64(durationMs) * 1_000_000 / UInt64(steps)
        let current   = AEC_GetOutputGain(context)
        let delta     = (target - current) / Float(steps)
        for i in 1...steps {
            AEC_SetOutputGain(context, current + delta * Float(i))
            try? await Task.sleep(nanoseconds: nsPerStep)
        }
        AEC_SetOutputGain(context, target)
    }

    private func waitForSampleRate(expected: Double, timeoutMs: Int) async {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope:    kAudioObjectPropertyScopeGlobal,
                mElement:  kAudioObjectPropertyElementMain
            )
            var current = Float64(0)
            var size = UInt32(MemoryLayout<Float64>.size)
            AudioObjectGetPropertyData(currentDeviceID, &addr, 0, nil, &size, &current)
            if abs(current - expected) < 1.0 { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - IOProc

    func registerIOProc() -> Bool {
        guard ioProcID == nil else { return true }
        var procID: AudioDeviceIOProcID?
        let status = AudioEngine_CreateIOProc(
            currentDeviceID,
            context,
            &procID
        )
        if status == noErr {
            ioProcID = procID
            return true
        }
        return false
    }

    func startPlayback() -> Bool {
        guard let id = ioProcID else { return false }
        return AudioDeviceStart(currentDeviceID, id) == noErr
    }

    func stopPlayback() {
        AEC_SetIsPlaying(context, false)
        if let id = ioProcID {
            AudioDeviceStop(currentDeviceID, id)
            AudioEngine_DestroyIOProc(currentDeviceID, id)
            ioProcID = nil
        }
    }

    // MARK: - Track Loading

    func loadTrack(filePath: String) async -> Bool {
        stopPlayback()

        if let w = decoderWorker {
            FLACDecoder_Stop(w)
            FLACDecoder_Destroy(w)
            decoderWorker = nil
        }

        RingBuffer_Reset(context.pointee.ringBuffer)
        AEC_ResetPlayback(context)

        guard let worker = FLACDecoder_Create(filePath, context) else {
            NSLog("[ytsplayer] FLACDecoder_Create failed for: \(filePath)")
            return false
        }
        decoderWorker = worker

        let rate = Double(context.pointee.sampleRate)
        if rate > 0 { 
            let ok = await setHardwareSampleRate(rate)
            if !ok {
                NSLog("[ytsplayer] Hardware rejected sample rate \(rate)")
                return false
            }
        }

        guard registerIOProc(), startPlayback() else { return false }

        FLACDecoder_Start(worker)
        return true
    }

    // MARK: - Seek

    func seek(to frame: UInt64) {
        guard let w = decoderWorker else { return }
        FLACDecoder_Seek(w, frame)
    }

    // MARK: - Convenience Reads for UI (safe on main thread)

    var isPlayingValue: Bool       { AEC_GetIsPlaying(context) }
    var currentFrameValue: UInt64  { AEC_GetCurrentFrame(context) }
    var totalFramesValue: UInt64   { AEC_GetTotalFrames(context) }

    // MARK: - Device Change Listener

    private func registerDeviceChangeListener() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            guard let self else { return }
            self.stopPlayback()
            self.isHogMode = false
            self.currentDeviceID = self.discoverDefaultOutputDevice()
            NotificationCenter.default.post(name: .audioDeviceDidChange, object: nil)
        }
    }
}
