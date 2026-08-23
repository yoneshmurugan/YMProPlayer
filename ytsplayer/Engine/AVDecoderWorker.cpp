// AVDecoderWorker.cpp
// ytsplayer
//
// Background ExtAudioFile stream decoder worker for Apple-supported formats.
// Feeds decoded PCM into the SPSC ring buffer consumed by the CoreAudio IOProc.

#include "AVDecoderWorker.h"
#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <unistd.h>

#define PREBUFFER_RATIO 0.5

struct AVDecoderWorker {
    AudioEngineContext *ctx;
    ExtAudioFileRef audioFile = nullptr;
    dispatch_queue_t queue;
    _Atomic bool shouldStop = false;
    _Atomic bool isReady = false;
    uint64_t seekTarget = 0;
    _Atomic bool seekPending = false;
    
    uint32_t channels = 2;
    uint32_t sampleRate = 44100;
};

extern "C" AVDecoderWorker *AVDecoder_Create(const char *filePath, AudioEngineContext *ctx) {
    if (!filePath || !ctx) return nullptr;

    CFStringRef pathStr = CFStringCreateWithCString(kCFAllocatorDefault, filePath, kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, pathStr, kCFURLPOSIXPathStyle, false);
    CFRelease(pathStr);

    ExtAudioFileRef audioFile = nullptr;
    OSStatus status = ExtAudioFileOpenURL(url, &audioFile);
    CFRelease(url);
    if (status != noErr || !audioFile) {
        return nullptr;
    }

    AudioStreamBasicDescription inputFormat = {};
    UInt32 propSize = sizeof(inputFormat);
    ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileDataFormat, &propSize, &inputFormat);

    AudioStreamBasicDescription clientFormat = {};
    clientFormat.mSampleRate = inputFormat.mSampleRate;
    clientFormat.mFormatID = kAudioFormatLinearPCM;
    clientFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    clientFormat.mFramesPerPacket = 1;
    clientFormat.mChannelsPerFrame = inputFormat.mChannelsPerFrame;
    clientFormat.mBytesPerFrame = clientFormat.mChannelsPerFrame * sizeof(float);
    clientFormat.mBytesPerPacket = clientFormat.mBytesPerFrame;
    clientFormat.mBitsPerChannel = 32;

    status = ExtAudioFileSetProperty(audioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(clientFormat), &clientFormat);
    if (status != noErr) {
        ExtAudioFileDispose(audioFile);
        return nullptr;
    }

    AVDecoderWorker *worker = new AVDecoderWorker();
    worker->ctx = ctx;
    worker->audioFile = audioFile;
    worker->channels = inputFormat.mChannelsPerFrame;
    worker->sampleRate = inputFormat.mSampleRate;
    worker->queue = dispatch_queue_create("com.ytsplayer.AVDecoderWorker", DISPATCH_QUEUE_SERIAL);
    
    ctx->channels = worker->channels;
    ctx->sampleRate = worker->sampleRate;
    ctx->bitDepth = 32;

    SInt64 totalFrames = 0;
    propSize = sizeof(totalFrames);
    ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileLengthFrames, &propSize, &totalFrames);
    atomic_store_explicit(&ctx->totalFrames, (uint64_t)totalFrames, memory_order_relaxed);

    return worker;
}

extern "C" void AVDecoder_Start(AVDecoderWorker *worker) {
    if (!worker) return;
    
    dispatch_async(worker->queue, ^{
        const uint32_t bufferFrames = 4096;
        float *buffer = (float *)malloc(bufferFrames * worker->channels * sizeof(float));
        
        while (!atomic_load_explicit(&worker->shouldStop, memory_order_relaxed)) {
            if (atomic_load_explicit(&worker->seekPending, memory_order_relaxed)) {
                ExtAudioFileSeek(worker->audioFile, worker->seekTarget);
                atomic_store_explicit(&worker->seekPending, false, memory_order_relaxed);
            }
            
            AudioBufferList bufferList;
            bufferList.mNumberBuffers = 1;
            bufferList.mBuffers[0].mNumberChannels = worker->channels;
            bufferList.mBuffers[0].mDataByteSize = bufferFrames * worker->channels * sizeof(float);
            bufferList.mBuffers[0].mData = buffer;
            
            UInt32 framesToRead = bufferFrames;
            OSStatus status = ExtAudioFileRead(worker->audioFile, &framesToRead, &bufferList);
            
            if (status != noErr || framesToRead == 0) {
                break;
            }
            
            uint32_t ratio = worker->ctx->downsampleRatio;
            if (ratio < 1) ratio = 1;
            
            size_t outFrames = framesToRead / ratio;
            float *outBuffer = (float *)malloc(outFrames * 2 * sizeof(float));
            
            for (size_t i = 0; i < outFrames; i++) {
                size_t inIndex = i * ratio;
                if (worker->channels >= 2) {
                    outBuffer[i * 2] = buffer[inIndex * worker->channels];
                    outBuffer[i * 2 + 1] = buffer[inIndex * worker->channels + 1];
                } else {
                    float sample = buffer[inIndex];
                    outBuffer[i * 2] = sample;
                    outBuffer[i * 2 + 1] = sample;
                }
            }
            
            size_t written = 0;
            while (written < outFrames) {
                if (atomic_load_explicit(&worker->shouldStop, memory_order_relaxed)) break;
                size_t w = RingBuffer_Write(worker->ctx->ringBuffer, outBuffer + written * 2, outFrames - written);
                written += w;
                if (written < outFrames) {
                    usleep(1000);
                }
            }
            free(outBuffer);
            
            if (!atomic_load_explicit(&worker->isReady, memory_order_relaxed)) {
                size_t available = RingBuffer_AvailableToRead(worker->ctx->ringBuffer);
                size_t capacity = worker->ctx->ringBuffer->capacityFrames;
                if (available >= capacity * PREBUFFER_RATIO) {
                    atomic_store_explicit(&worker->isReady, true, memory_order_relaxed);
                    atomic_store_explicit(&worker->ctx->isPlaying, true, memory_order_relaxed);
                }
            }
        }
        free(buffer);
    });
}

extern "C" void AVDecoder_Stop(AVDecoderWorker *worker) {
    if (!worker) return;
    atomic_store_explicit(&worker->shouldStop, true, memory_order_relaxed);
}

extern "C" void AVDecoder_Destroy(AVDecoderWorker *worker) {
    if (!worker) return;
    dispatch_sync(worker->queue, ^{
        if (worker->audioFile) {
            ExtAudioFileDispose(worker->audioFile);
        }
    });
    delete worker;
}

extern "C" bool AVDecoder_Seek(AVDecoderWorker *worker, uint64_t targetFrame) {
    if (!worker) return false;
    worker->seekTarget = targetFrame;
    atomic_store_explicit(&worker->seekPending, true, memory_order_relaxed);
    return true;
}
