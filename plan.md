Markdown
# Native macOS Hi-Res Bit-Perfect Audio Player
## Complete Architecture, Low-Level CoreAudio HAL, and Implementation Specification

---

## 1. System Architecture & Concurrency Model

Audiophile-grade playback on macOS requires a strictly decoupled, multi-tier threading model. The real-time audio thread must be protected from high-level OS interference, memory allocations, and network latency.

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        MAIN UI THREAD (SwiftUI)                        │
│   • 60fps / 120fps ProMotion UI                                        │
│   • LazyVGrid Album Virtualization & NavigationSplitView               │
│   • Reads Atomic State at 30Hz via CADisplayLink / Combine             │
└───────────────────────────────────▲────────────────────────────────────┘
                                    │ Atomic Reads / Lock-Free Ring
┌───────────────────────────────────▼────────────────────────────────────┐
│                    DATABASE & METADATA THREAD (GCD)                    │
│   • GRDB (SQLite FTS5) Indexing                                        │
│   • TagLib C-Bridge Metadata & Vorbis Comment Extraction               │
│   • CoreGraphics 200x200 Image Downsampling Cache                      │
└───────────────────────────────────▲────────────────────────────────────┘
                                    │ Decoupled Pipeline
┌───────────────────────────────────▼────────────────────────────────────┐
│               BACKGROUND DECODER WORKER (libFLAC / GCD)                │
│   • Network I/O from /Volumes/pCloudDrive                              │
│   • libFLAC Stream Decoding to 32-bit Floating-Point PCM               │
│   • Writes PCM frames into Lock-Free SPSC Ring Buffer                  │
└───────────────────────────────────▲────────────────────────────────────┘
                                    │ Lock-Free Atomic Read (Zero Heap Alloc)
┌───────────────────────────────────▼────────────────────────────────────┐
│                 REAL-TIME AUDIO THREAD (CoreAudio HAL)                 │
│   • High-Priority IOProc Callback (`AudioDeviceIOProc`)                │
│   • Direct Hardware Access via Hog Mode (`kAudioDevicePropertyHogMode`)│
│   • Dynamic Clock Switching (`kAudioDevicePropertyNominalSampleRate`)  │
│   • Feeds MacBook 3.5mm Internal DAC with 0% System Resampling         │
└────────────────────────────────────────────────────────────────────────┘
2. Phase 1: Low-Level CoreAudio HAL (Hardware Control Engine)
Apple’s AVFoundation and AudioQueue APIs pass audio through the macOS AudioToolbox mixer, which automatically resamples all audio streams to the sample rate selected in Audio MIDI Setup. To bypass the mixer entirely, the engine interfaces directly with the CoreAudio Hardware Abstraction Layer (HAL).

2.1 CoreAudio HAL Property Architecture
The engine interacts with the hardware via AudioObjectGetPropertyData and AudioObjectSetPropertyData.

Swift
import CoreAudio
import AudioToolbox

public final class CoreAudioHALEngine {
    private var defaultOutputDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var isHogged: Bool = false
    
    public init() {
        self.defaultOutputDeviceID = getDefaultOutputDevice()
    }
    
    // MARK: - 1. Discover Default 3.5mm / Built-In Hardware Device
    private func getDefaultOutputDevice() -> AudioObjectID {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        
        guard status == noErr else {
            fatalError("Failed to discover default CoreAudio output device: \\(status)")
        }
        return deviceID
    }
    
    // MARK: - 2. Seize Exclusive Access (Hog Mode)
    public func setHogMode(enable: Bool) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var pid: pid_t = enable ? getpid() : -1
        let dataSize = UInt32(MemoryLayout<pid_t>.size)
        
        let status = AudioObjectSetPropertyData(
            defaultOutputDeviceID,
            &propertyAddress,
            0,
            nil,
            dataSize,
            &pid
        )
        
        if status == noErr {
            self.isHogged = enable
            return true
        } else {
            print("Hog mode acquisition failed with OSStatus code: \\(status)")
            return false
        }
    }
    
    // MARK: - 3. Dynamic Sample Rate Switching (Bypassing Resampler)
    public func setHardwareSampleRate(_ sampleRate: Double) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var targetRate = Float64(sampleRate)
        let dataSize = UInt32(MemoryLayout<Float64>.size)
        
        // Query hardware to verify if sample rate is natively supported
        var availableAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rangeSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(defaultOutputDeviceID, &availableAddress, 0, nil, &rangeSize)
        
        let count = Int(rangeSize) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        AudioObjectGetPropertyData(defaultOutputDeviceID, &availableAddress, 0, nil, &rangeSize, &ranges)
        
        let isSupported = ranges.contains { targetRate >= $0.mMinimum && targetRate <= $0.mMaximum }
        guard isSupported else {
            print("Sample rate \\(sampleRate) Hz is not supported by built-in DAC.")
            return false
        }
        
        let status = AudioObjectSetPropertyData(
            defaultOutputDeviceID,
            &propertyAddress,
            0,
            nil,
            dataSize,
            &targetRate
        )
        
        return status == noErr
    }
}
2.2 Pop/Click Suppression During Clock Frequency Shifts
When switching between different clock domains (e.g., 44.1kHz to 96kHz), the internal DAC hardware locks its phase-locked loop (PLL), causing an audible transient pop.
Engine Rule: Mute the CoreAudio IO callback buffer with a 50ms smooth linear volume ramp-down before invoking AudioObjectSetPropertyData.
Maintain a 50ms silence buffer while listening for the kAudioDevicePropertyNominalSampleRate notification via AudioObjectAddPropertyListener.
Ramp volume linearly back from 0.0 to 1.0 over 50ms once the new sample rate is acknowledged by the driver.
2.3 The Real-Time IO Callback (IOProc)
The audio thread runs at real-time kernel priority (THREAD_TIME_CONSTRAINT_POLICY).

C
// Real-time C render callback for CoreAudio HAL
OSStatus AudioDeviceRenderCallback(
    AudioObjectID inDevice,
    const AudioTimeStamp* inNow,
    const AudioBufferList* inInputData,
    const AudioTimeStamp* inInputTime,
    AudioBufferList* outOutputData,
    const AudioTimeStamp* inOutputTime,
    void* inClientData
) {
    AudioEngineContext* context = (AudioEngineContext*)inClientData;
    float* outputBuffer = (float*)outOutputData->mBuffers[0].mData;
    UInt32 frameCount = outOutputData->mBuffers[0].mDataByteSize / (sizeof(float) * 2); // Stereo 32-bit Float
    
    // Read directly from Lock-Free SPSC Circular Ring Buffer
    UInt32 framesRead = RingBuffer_Read(context->ringBuffer, outputBuffer, frameCount);
    
    // If underrun occurs (e.g., pCloud network lag), fill remainder with silence
    if (framesRead < frameCount) {
        memset(outputBuffer + (framesRead * 2), 0, (frameCount - framesRead) * sizeof(float) * 2);
    }
    
    // Update atomic frame counter for UI sync (lock-free)
    atomic_fetch_add_explicit(&context->currentFramePosition, framesRead, memory_order_relaxed);
    
    return noErr;
}
Strict Constraints Inside AudioDeviceRenderCallback:
NO Heap Allocations: malloc(), calloc(), free(), or Swift object instantiations are strictly forbidden.
NO Locks/Mutexes: pthread_mutex_lock, os_unfair_lock, or Swift actor isolation will cause unbounded priority inversions and audible dropouts.
NO System Calls: File I/O, network sockets, NSLog, or print() must never be called.
NO Objective-C/Swift Runtime Dispatches: All interaction occurs using statically typed C structures.
3. Phase 2: Asynchronous FLAC Decoding & Lock-Free Buffering
Because the library resides on a mounted cloud filesystem (/Volumes/pCloudDrive), synchronous disk reads on the playback thread will cause audio stuttering. The engine implements a decoupled producer-consumer architecture.

Plaintext
┌─────────────────────────────────┐           ┌─────────────────────────────────┐
│     pCloud Mounted Drive        │           │    CoreAudio HAL Audio Device   │
└────────────────┬────────────────┘           └─────────────────▲───────────────┘
                 │ (Network/Disk Read)                          │
                 ▼                                              │ (Real-Time Pull)
┌─────────────────────────────────┐           ┌─────────────────┴───────────────┐
│    libFLAC Decoding Worker      │           │    Real-Time Render Callback    │
│  (Background GCD Serial Queue)  │           │   (C-Based, Real-Time Priority) │
└────────────────┬────────────────┘           └─────────────────▲───────────────┘
                 │                                              │
                 │ (Push Float32 PCM)                           │ (Read Float32 PCM)
                 ▼                                              │
       ┌────────────────────────────────────────────────────────┴────────┐
       │         Lock-Free Single-Producer Single-Consumer (SPSC)        │
       │                   Circular Ring Buffer (10MB)                   │
       └─────────────────────────────────────────────────────────────────┘
3.1 Lock-Free Single-Producer Single-Consumer (SPSC) Ring Buffer
Memory ordering fences (atomic_thread_fence) ensure lock-free synchronization between the background decoder and the audio hardware.

C
// LockFreeRingBuffer.h
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    float* buffer;
    size_t capacityFrames;
    atomic_size_t writeIndex;
    atomic_size_t readIndex;
} SPSCRingBuffer;

static inline SPSCRingBuffer* RingBuffer_Create(size_t capacityFrames) {
    SPSCRingBuffer* rb = (SPSCRingBuffer*)malloc(sizeof(SPSCRingBuffer));
    rb->buffer = (float*)malloc(capacityFrames * 2 * sizeof(float)); // Stereo interleaved
    rb->capacityFrames = capacityFrames;
    atomic_init(&rb->writeIndex, 0);
    atomic_init(&rb->readIndex, 0);
    return rb;
}

static inline size_t RingBuffer_Write(SPSCRingBuffer* rb, const float* data, size_t frames) {
    size_t write = atomic_load_explicit(&rb->writeIndex, memory_order_relaxed);
    size_t read = atomic_load_explicit(&rb->readIndex, memory_order_acquire);
    
    size_t available = rb->capacityFrames - (write - read);
    size_t toWrite = frames < available ? frames : available;
    
    size_t mask = rb->capacityFrames - 1; // Requires power-of-two capacity
    for (size_t i = 0; i < toWrite; i++) {
        size_t idx = ((write + i) & mask) * 2;
        rb->buffer[idx] = data[i * 2];
        rb->buffer[idx + 1] = data[i * 2 + 1];
    }
    
    atomic_store_explicit(&rb->writeIndex, write + toWrite, memory_order_release);
    return toWrite;
}

static inline size_t RingBuffer_Read(SPSCRingBuffer* rb, float* data, size_t frames) {
    size_t read = atomic_load_explicit(&rb->readIndex, memory_order_relaxed);
    size_t write = atomic_load_explicit(&rb->writeIndex, memory_order_acquire);
    
    size_t available = write - read;
    size_t toRead = frames < available ? frames : available;
    
    size_t mask = rb->capacityFrames - 1;
    for (size_t i = 0; i < toRead; i++) {
        size_t idx = ((read + i) & mask) * 2;
        data[i * 2] = rb->buffer[idx];
        data[i * 2 + 1] = rb->buffer[idx + 1];
    }
    
    atomic_store_explicit(&rb->readIndex, read + toRead, memory_order_release);
    return toRead;
}
3.2 Bridging libFLAC Stream Decoder
The decoder decompresses Vorbis-framed linear PCM and converts raw 16-bit or 24-bit integer samples to 32-bit floating-point format:

sample 
float32
​	
 = 
2 
bit_depth−1
 
sample 
int32
​	
 
​	
 
C
#include <FLAC/stream_decoder.h>

typedef struct {
    SPSCRingBuffer* ringBuffer;
    unsigned int bitsPerSample;
    unsigned int sampleRate;
    unsigned int channels;
} FLACDecoderContext;

// libFLAC write callback
FLAC__StreamDecoderWriteStatus flac_write_callback(
    const FLAC__StreamDecoder *decoder,
    const FLAC__Frame *frame,
    const FLAC__int32 *const buffer[],
    void *client_data
) {
    FLACDecoderContext *ctx = (FLACDecoderContext*)client_data;
    size_t blocksize = frame->header.blocksize;
    float interleavedBuffer[blocksize * 2];
    
    float scale = 1.0f / (float)(1 << (frame->header.bits_per_sample - 1));
    
    for (size_t i = 0; i < blocksize; i++) {
        if (frame->header.channels == 2) {
            interleavedBuffer[i * 2]     = (float)buffer[0][i] * scale;
            interleavedBuffer[i * 2 + 1] = (float)buffer[1][i] * scale;
        } else if (frame->header.channels == 1) {
            interleavedBuffer[i * 2]     = (float)buffer[0][i] * scale;
            interleavedBuffer[i * 2 + 1] = (float)buffer[0][i] * scale;
        }
    }
    
    // Spin/Wait non-blocking on ring buffer write until space is free
    while (RingBuffer_Write(ctx->ringBuffer, interleavedBuffer, blocksize) < blocksize) {
        usleep(1000); // 1ms sleep on background thread if buffer full
    }
    
    return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}
4. Phase 3: Metadata Pipeline & SQLite Storage (GRDB)
To support instant search across thousands of tracks with zero dropped frames in SwiftUI, metadata parsing and UI reads are decoupled using an optimized SQLite database with Full-Text Search (FTS5).

Plaintext
┌────────────────────────────────────────────────────────┐
│               Background TagLib Parser                 │
│   • Scans /Volumes/pCloudDrive asynchronously          │
│   • Extracts Vorbis Tags (FLAC) & Embedded Pictures    │
└───────────────────────────┬────────────────────────────┘
                            │ Batch Transactions
┌───────────────────────────▼────────────────────────────┐
│                    GRDB Database Pool                  │
│   • WAL Mode Enabled (Concurrent Read/Write)           │
│   • Normalized Tables: artists, albums, tracks         │
│   • FTS5 Full-Text Virtual Search Index                │
└───────────────────────────┬────────────────────────────┘
                            │ Reactive Fetch Requests
┌───────────────────────────▼────────────────────────────┐
│               SwiftUI Main Thread Views                │
│   • Reads Downsampled 200x200 JPEGs from Disk Cache    │
│   • Virtualized Navigation & Sub-Millisecond Search    │
└────────────────────────────────────────────────────────┘
4.1 Normalized SQLite Schema & GRDB Setup
Swift
import GRDB
import Foundation

struct AppDatabase {
    static func makeDatabasePool(at path: String) throws -> DatabasePool {
        var config = Configuration()
        config.qos = .userInitiated
        // Enable WAL mode for zero UI-lock contention during writes
        let dbPool = try DatabasePool(path: path, configuration: config)
        
        try migrator.migrate(dbPool)
        return dbPool
    }
    
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1_schema") { db in
            try db.create(table: "artists") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique(onConflict: .ignore)
            }
            
            try db.create(table: "albums") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("artistId", .integer).references("artists", onDelete: .cascade)
                t.column("artworkPath", .text)
                t.uniqueKey(["title", "artistId"], onConflict: .ignore)
            }
            
            try db.create(table: "tracks") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("filePath", .text).notNull().unique(onConflict: .replace)
                t.column("title", .text).notNull()
                t.column("albumId", .integer).references("albums", onDelete: .cascade)
                t.column("duration", .double).notNull()
                t.column("sampleRate", .integer).notNull()
                t.column("bitDepth", .integer).notNull()
                t.column("channels", .integer).notNull()
                t.column("trackNumber", .integer)
            }
            
            // FTS5 Full-Text Search Table
            try db.execute(sql: """
                CREATE VIRTUAL TABLE tracks_fts USING fts5(
                    title,
                    content='tracks',
                    content_rowid='id'
                );
                CREATE TRIGGER tracks_ai AFTER INSERT ON tracks BEGIN
                    INSERT INTO tracks_fts(rowid, title) VALUES (new.id, new.title);
                END;
            """)
        }
        return migrator
    }
}
4.2 C++ TagLib Extraction & Downsampling Pipeline
High-resolution embedded album art must never be loaded directly into memory or saved uncompressed to the database. Downsample to a max resolution of 400x400 JPEG on disk.

C++
// MetadataBridge.cpp
#include <taglib/fileref.h>
#include <taglib/flacfile.h>
#include <taglib/attachedpictureframe.h>

struct ExtractedTrackMetadata {
    char title[256];
    char artist[256];
    char album[256];
    uint32_t sampleRate;
    uint32_t bitDepth;
    uint32_t channels;
    double duration;
    const char* artworkData;
    size_t artworkSize;
};

extern "C" bool ExtractFLACMetadata(const char* filePath, ExtractedTrackMetadata* outMetadata) {
    TagLib::FLAC::File file(filePath);
    if (!file.isValid()) return false;
    
    TagLib::Tag *tag = file.tag();
    if (tag) {
        strncpy(outMetadata->title, tag->title().toCString(true), 255);
        strncpy(outMetadata->artist, tag->artist().toCString(true), 255);
        strncpy(outMetadata->album, tag->album().toCString(true), 255);
    }
    
    TagLib::FLAC::Properties *props = file.audioProperties();
    if (props) {
        outMetadata->sampleRate = props->sampleRate();
        outMetadata->bitDepth = props->bitsPerSample();
        outMetadata->channels = props->channels();
        outMetadata->duration = props->lengthInSeconds();
    }
    
    auto pictures = file.pictureList();
    if (!pictures.isEmpty()) {
        TagLib::FLAC::Picture* pic = pictures.front();
        outMetadata->artworkData = pic->data().data();
        outMetadata->artworkSize = pic->data().size();
    } else {
        outMetadata->artworkData = nullptr;
        outMetadata->artworkSize = 0;
    }
    
    return true;
}
5. Phase 4: Thread Decoupling & SwiftUI Frontend
The UI communicates with the low-level playback engine through atomic memory locations and periodic polling, avoiding state locking on the audio callback.

Plaintext
┌────────────────────────────────────────────────────────┐
│               AudioEngineContext (C Engine)            │
│   • atomic_uint_least64_t currentFramePosition         │
│   • atomic_bool isPlaying                              │
└───────────────────────────┬────────────────────────────┘
                            │ Non-blocking Atomic Read
┌───────────────────────────▼────────────────────────────┐
│         PlaybackViewModel (Swift MainActor)            │
│   • Timer / CADisplayLink updates progress at 30Hz     │
│   • @Published var currentProgress: Double             │
│   • @Published var activeSampleRate: Int               │
└───────────────────────────┬────────────────────────────┘
                            │ Reactive SwiftUI Bindings
┌───────────────────────────▼────────────────────────────┐
│                    NowPlayingBar View                  │
│   • Render progress sliders & sample rate badges       │
│   • Zero audio-thread lock contention                  │
└────────────────────────────────────────────────────────┘
5.1 Player ViewModel (Lock-Free UI Poller)
Swift
import SwiftUI
import Combine

@MainActor
public final class PlaybackViewModel: ObservableObject {
    @Published public var playbackProgress: Double = 0.0
    @Published public var currentTimeString: String = "0:00"
    @Published public var isPlaying: Bool = false
    @Published public var currentSampleRate: Int = 0
    @Published public var currentBitDepth: Int = 0
    
    private var cancellableTimer: AnyCancellable?
    private let halEngine: CoreAudioHALEngine
    private var totalFrames: UInt64 = 0
    
    public init(engine: CoreAudioHALEngine) {
        self.halEngine = engine
        
        // Poll audio progress at 30Hz without touching the CoreAudio execution thread
        self.cancellableTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.syncProgressFromEngine()
            }
    }
    
    private func syncProgressFromEngine() {
        // Read atomic frame counter from C audio engine
        let currentFrame = AtomicBridgeGetElapsedFrames()
        guard totalFrames > 0 else { return }
        
        self.playbackProgress = Double(currentFrame) / Double(totalFrames)
        let seconds = Double(currentFrame) / Double(currentSampleRate)
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        self.currentTimeString = String(format: "%d:%02d", mins, secs)
    }
}
5.2 SwiftUI Native Glassmorphic Interface
Swift
import SwiftUI

struct NowPlayingBar: View {
    @ObservedObject var viewModel: PlaybackViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            // Album Artwork Thumbnail
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundColor(.white)
                )
            
            // Track Info & Audio Format Badges
            VStack(alignment: .leading, spacing: 4) {
                Text("Lossless Stream")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 6) {
                    Text("\\(viewModel.currentSampleRate / 1000) kHz")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundColor(.yellow)
                        .cornerRadius(3)
                    
                    Text("\\(viewModel.currentBitDepth)-bit")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(3)
                    
                    Text("BIT-PERFECT")
                        .font(.system(size: 9, weight: .heavy))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(3)
                }
            }
            
            Spacer()
            
            // Transport Controls
            HStack(spacing: 20) {
                Button(action: {}) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                
                Button(action: { viewModel.isPlaying.toggle() }) {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                }
                .buttonStyle(.plain)
                
                Button(action: {}) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Progress Scrubber
            HStack(spacing: 8) {
                Text(viewModel.currentTimeString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Slider(value: $viewModel.playbackProgress, in: 0...1)
                    .frame(width: 150)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(.ultraThinMaterial)
        .overlay(
            Divider(), alignment: .top
        )
    }
}
6. Phase 5: Error Handling, Sandboxing & Edge Cases
6.1 Hardware Disconnection Listener
If headphones are disconnected from the 3.5mm jack during playback, macOS shifts the default output device to the internal speakers. The engine must safely release Hog Mode and halt the render callback without crashing.

Swift
extension CoreAudioHALEngine {
    public func registerDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            guard let self = self else { return }
            print("Audio route changed: Releasing Hog Mode and stopping render thread.")
            _ = self.setHogMode(enable: false)
            self.reinitializeAudioPipeline()
        }
    }
    
    private func reinitializeAudioPipeline() {
        self.defaultOutputDeviceID = getDefaultOutputDevice()
        // Reset buffers and await new user play dispatch
    }
}
6.2 App Sandbox & Security-Scoped Bookmarks
To read directly from external mounts (/Volumes/pCloudDrive) in an App Store sandboxed application, configure .entitlements with user-selected file read rights and persist access via Security-Scoped Bookmarks.

XML
<!-- PetrichorPlayer.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "[http://www.apple.com/DTDs/PropertyList-1.0.dtd](http://www.apple.com/DTDs/PropertyList-1.0.dtd)">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <false/>
</dict>
</plist>
Swift
// Bookmark persistence for mounted folder
func saveSecurityScopedBookmark(for url: URL) throws -> Data {
    return try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
    )
}

func resolveSecurityScopedBookmark(data: Data) throws -> URL {
    var isStale = false
    let url = try URL(
        resolvingBookmarkData: data,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
    )
    _ = url.startAccessingSecurityScopedResource()
    return url
}
7. Build Checklist & Verification Protocol
Verification Stage	Testing Method	Expected Pass Criteria
Bit-Perfect Output	Open Audio MIDI Setup.app while switching between 44.1kHz, 96kHz, and 192kHz FLACs.	Format dropdown automatically jumps to exact file sample rate.
Mixer Isolation	Play music through the app, then trigger a macOS system alert (e.g., volume change beep or terminal bell).	System sound is completely silenced or routed to internal speakers without mixing into IEMs.
Underrun Immunity	Simulate high CPU load and heavy network latency on the pCloud mount.	Lock-free ring buffer absorbs up to 5 seconds of I/O stall with zero audio dropouts.
Memory Ceiling	Rapidly scroll through a library containing 1,000+ indexed FLAC albums in SwiftUI.	Memory usage stays strictly bounded under 100MB due to downsampled image caching.