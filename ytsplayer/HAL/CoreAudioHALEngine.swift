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
    private var avDecoderWorker: OpaquePointer?

    // Ring buffer: 131072 frames = power-of-two, ~3s at 44.1kHz
    private let ringBufferCapacity: Int = 131_072

    init() {
        context = AudioEngineContext_Create(ringBufferCapacity)
        
        if let storedDeviceID = UserDefaults.standard.string(forKey: "outputDeviceID"),
           let devId = UInt32(storedDeviceID),
           isValidOutputDevice(AudioDeviceID(devId)) {
            currentDeviceID = AudioDeviceID(devId)
        } else {
            currentDeviceID = discoverDefaultOutputDevice()
        }
        
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
    
    private func isValidOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var streamAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain
        )
        var streamSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &streamAddr, 0, nil, &streamSize)
        return status == noErr && streamSize > 0
    }
    
    func setOutputDevice(to deviceID: AudioDeviceID) {
        if currentDeviceID == deviceID { return }
        stopPlayback()
        isHogMode = false
        currentDeviceID = deviceID
        UserDefaults.standard.set(String(deviceID), forKey: "outputDeviceID")
        
        // Let the ViewModel restart playback if needed
        NotificationCenter.default.post(name: .audioDeviceDidChange, object: nil)
    }

    // MARK: - Hog Mode

    func checkHogMode() -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var hogPID = pid_t(-1)
        var size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(currentDeviceID, &addr, 0, nil, &size, &hogPID)
        return status == noErr && hogPID == pid_t(ProcessInfo.processInfo.processIdentifier)
    }

    @discardableResult
    func acquireHogMode() -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        
        if checkHogMode() {
            isHogMode = true
            return true
        }

        var pid = pid_t(ProcessInfo.processInfo.processIdentifier)
        let size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectSetPropertyData(currentDeviceID, &addr, 0, nil, size, &pid)
        isHogMode = (status == noErr)
        return isHogMode
    }

    @discardableResult
    func releaseHogMode() -> Bool {
        if !checkHogMode() {
            isHogMode = false
            return true
        }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var pid = pid_t(-1)
        let size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectSetPropertyData(currentDeviceID, &addr, 0, nil, size, &pid)
        if status == noErr { isHogMode = false }
        return status == noErr
    }

    @discardableResult
    func setHogModeSafe(_ enable: Bool) -> Bool {
        if isPlayingValue { stopPlayback() }
        
        // We MUST destroy the IOProc before changing Hog Mode. 
        // Core Audio caches device exclusivity on the IOProc itself.
        if let id = ioProcID {
            AudioEngine_DestroyIOProc(currentDeviceID, id)
            ioProcID = nil
        }
        
        let result = enable ? acquireHogMode() : releaseHogMode()
        
        // Let the ViewModel reflect the pause state so the user can manually resume
        NotificationCenter.default.post(name: .audioDeviceDidChange, object: nil)
        
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
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var current = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(currentDeviceID, &addr, 0, nil, &size, &current)
        if abs(current - rate) < 1.0 { return true }
        
        // Release Hog Mode safely before changing the sample rate route
        let hadHogMode = isHogMode
        if hadHogMode { _ = releaseHogMode() }

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

    @discardableResult
    func resumePlayback() -> Bool {
        if ioProcID == nil {
            guard registerIOProc() else { return false }
            usleep(50_000)
            guard startPlayback() else { return false }
        }
        AEC_SetIsPlaying(context, true)
        return true
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

    func loadTrack(filePath: String, expectedSampleRate: Double) async -> Bool {
        stopPlayback()

        if let w = decoderWorker {
            FLACDecoder_Stop(w)
            FLACDecoder_Destroy(w)
            decoderWorker = nil
        }
        if let w = avDecoderWorker {
            AVDecoder_Stop(w)
            AVDecoder_Destroy(w)
            avDecoderWorker = nil
        }

        RingBuffer_Reset(context.pointee.ringBuffer)
        AEC_ResetPlayback(context)

        let ext = (filePath as NSString).pathExtension.lowercased()
        let isFLAC = (ext == "flac")

        if isFLAC {
            guard let worker = FLACDecoder_Create(filePath, context) else {
                NSLog("[ytsplayer] FLACDecoder_Create failed for: \(filePath)")
                return false
            }
            decoderWorker = worker
        } else {
            guard let worker = AVDecoder_Create(filePath, context) else {
                NSLog("[ytsplayer] AVDecoder_Create failed for: \(filePath)")
                return false
            }
            avDecoderWorker = worker
        }

        let originalRate = expectedSampleRate > 0 ? expectedSampleRate : Double(context.pointee.sampleRate)
        var hardwareRate = originalRate
        var ratio: UInt32 = 1

        if originalRate > 0 { 
            let ok = await setHardwareSampleRate(originalRate)
            if !ok {
                let allowDownsampling = UserDefaults.standard.bool(forKey: "allowDownsampling")
                
                if !allowDownsampling {
                    NSLog("[ytsplayer] Hardware rejected sample rate \(originalRate) and downsampling is disabled.")
                    return false
                }
                
                // Integer downsampling fallback
                if originalRate >= 176400 {
                    let ok2x = await setHardwareSampleRate(originalRate / 2.0)
                    if ok2x {
                        ratio = 2
                        hardwareRate = originalRate / 2.0
                        NSLog("[ytsplayer] Hardware rejected \(originalRate)Hz, downsampling to \(hardwareRate)Hz (2x)")
                    }
                }
                
                if ratio == 1 && originalRate >= 352800 {
                    let ok4x = await setHardwareSampleRate(originalRate / 4.0)
                    if ok4x {
                        ratio = 4
                        hardwareRate = originalRate / 4.0
                        NSLog("[ytsplayer] Hardware rejected \(originalRate)Hz, downsampling to \(hardwareRate)Hz (4x)")
                    }
                }
                
                if ratio == 1 {
                    NSLog("[ytsplayer] Hardware rejected sample rate \(originalRate)")
                    return false
                }
            }
        }

        context.pointee.downsampleRatio = ratio
        context.pointee.sampleRate = UInt32(hardwareRate)
        let total = AEC_GetTotalFrames(context)
        AEC_SetTotalFrames(context, total / UInt64(ratio))

        // Wait for Core Audio hardware route changes to fully settle
        // before attempting to acquire Hog Mode, otherwise it drops it silently.
        try? await Task.sleep(nanoseconds: 200_000_000)

        let bp = AEC_GetIsBitPerfect(context)
        if bp {
            if !checkHogMode() {
                _ = acquireHogMode()
                try? await Task.sleep(nanoseconds: 200_000_000) // generous sleep
            }
        } else {
            _ = releaseHogMode()
        }

        guard registerIOProc() else { return false }
        try? await Task.sleep(nanoseconds: 50_000_000)
        guard startPlayback() else { return false }

        // Start whichever worker was created
        if let w = decoderWorker {
            FLACDecoder_Start(w)
        } else if let w = avDecoderWorker {
            AVDecoder_Start(w)
        }
        return true
    }

    // MARK: - Gapless Playback

    func enqueueNextTrack(filePath: String) {
        let ext = (filePath as NSString).pathExtension.lowercased()
        if ext == "flac" {
            if let w = decoderWorker {
                FLACDecoder_EnqueueNext(w, filePath)
                NSLog("[ytsplayer] Enqueued next track for gapless playback: \(filePath)")
            }
        } else {
            NSLog("[ytsplayer] Gapless playback not supported for AVDecoder yet.")
        }
    }

    // MARK: - Seek

    func seek(to frame: UInt64) {
        if let w = decoderWorker {
            _ = FLACDecoder_Seek(w, frame)
        } else if let w = avDecoderWorker {
            _ = AVDecoder_Seek(w, frame)
        }
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
import Foundation
import CoreAudio
import AudioToolbox

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let manufacturer: String
    let uid: String
}

class CoreAudioController {
    static let shared = CoreAudioController()
    
    private init() {}
    
    /// Retrieves a list of all available audio output devices (excluding purely input devices).
    func getAvailableOutputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return [] }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        let status2 = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        guard status2 == noErr else { return [] }
        
        var outputDevices: [AudioDevice] = []
        
        for id in deviceIDs {
            // Check if device has output channels
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamDataSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamDataSize)
            if streamDataSize == 0 { continue } // Input only device
            
            // Get name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameCF: CFString? = nil
            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &nameCF)
            let name = (nameCF as String?) ?? "Unknown Device"
            
            // Get UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidCF: CFString? = nil
            var uidSize = UInt32(MemoryLayout<CFString?>.size)
            AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &uidCF)
            let uid = (uidCF as String?) ?? ""
            
            // Get manufacturer
            var mfgAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceManufacturerCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var mfgCF: CFString? = nil
            var mfgSize = UInt32(MemoryLayout<CFString?>.size)
            AudioObjectGetPropertyData(id, &mfgAddress, 0, nil, &mfgSize, &mfgCF)
            let mfg = (mfgCF as String?) ?? "Unknown"
            
            outputDevices.append(AudioDevice(id: id, name: name, manufacturer: mfg, uid: uid))
        }
        
        return outputDevices
    }
    
    /// Gets the default system output device ID
    func getDefaultOutputDevice() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceID)
        if status == noErr && deviceID != kAudioObjectUnknown {
            return deviceID
        }
        return nil
    }
    
    /// Switches the hardware nominal sample rate for the given device
    func setSampleRate(for deviceID: AudioDeviceID, to rate: Double) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // First check if it's already at this rate
        var currentRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &currentRate)
        
        if abs(currentRate - rate) < 1.0 {
            return // Already at requested rate
        }
        
        // Attempt to set
        var newRate: Float64 = rate
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &newRate)
        
        if status != noErr {
            print("[CoreAudioController] Failed to set sample rate \(rate)Hz on device \(deviceID)")
        } else {
            print("[CoreAudioController] Successfully switched device \(deviceID) to \(rate)Hz")
        }
    }
}
