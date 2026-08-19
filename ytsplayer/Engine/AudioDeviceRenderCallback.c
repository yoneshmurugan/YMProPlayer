// AudioDeviceRenderCallback.c
// ytsplayer
//
// Real-time CoreAudio IOProc.
//
// HARD CONSTRAINTS — violations cause audio dropouts or crashes:
//   ✗  NO malloc / calloc / free / realloc
//   ✗  NO pthread_mutex_lock / os_unfair_lock / dispatch_sync
//   ✗  NO system calls (open, read, write, socket)
//   ✗  NO NSLog / printf / os_log
//   ✗  NO Objective-C message sends
//   ✗  NO Swift runtime calls
//   ✓  Atomic loads/stores (relaxed / acquire / release only)
//   ✓  memset / memcpy on stack-allocated or pre-allocated buffers

#include "AudioDeviceRenderCallback.h"
#include "AudioEngineContext.h"
#include "LockFreeRingBuffer.h"

#include <string.h>
#include <stdatomic.h>

OSStatus AudioDevice_RenderCallback(
    AudioObjectID           inDevice,
    const AudioTimeStamp   *inNow,
    const AudioBufferList  *inInputData,
    const AudioTimeStamp   *inInputTime,
    AudioBufferList        *outOutputData,
    const AudioTimeStamp   *inOutputTime,
    void                   *inClientData
) {
    AudioEngineContext *ctx = (AudioEngineContext *)inClientData;

    // ── Grab the output buffer pointer and frame count ──────────────────────
    float   *outputBuffer = (float *)outOutputData->mBuffers[0].mData;
    UInt32   byteSize     = outOutputData->mBuffers[0].mDataByteSize;
    // Stereo interleaved float32: 2 channels × 4 bytes per sample
    UInt32   frameCount   = byteSize / (sizeof(float) * 2);

    // ── Guard: if not playing, fill with silence and return ─────────────────
    if (!atomic_load_explicit(&ctx->isPlaying, memory_order_relaxed)) {
        memset(outputBuffer, 0, byteSize);
        return noErr;
    }

    // ── Apply gain scalar (used for 50ms ramp suppression during SR switch) ─
    float gain = atomic_load_explicit(&ctx->outputGain, memory_order_relaxed);

    // ── Pull frames from the lock-free ring buffer ───────────────────────────
    UInt32 framesRead = (UInt32)RingBuffer_Read(ctx->ringBuffer, outputBuffer, (size_t)frameCount);

    // ── Underrun: fill remainder with silence (never drop out hard) ──────────
    if (framesRead < frameCount) {
        UInt32 silenceFrames = frameCount - framesRead;
        memset(outputBuffer + (framesRead * 2), 0, silenceFrames * 2 * sizeof(float));
    }

    // ── Apply gain in-place (used during ramp suppression) ──────────────────
    if (gain < 1.0f) {
        UInt32 samples = frameCount * 2; // stereo
        for (UInt32 i = 0; i < samples; i++) {
            outputBuffer[i] *= gain;
        }
    }

    // ── Update elapsed frame counter for UI (lock-free, relaxed store) ───────
    uint64_t prev = atomic_fetch_add_explicit(
        &ctx->currentFramePosition,
        (uint64_t)framesRead,
        memory_order_relaxed
    );

    // ── Detect end of track: signal isPlaying = false ────────────────────────
    uint64_t total = atomic_load_explicit(&ctx->totalFrames, memory_order_relaxed);
    if (total > 0 && (prev + framesRead) >= total) {
        atomic_store_explicit(&ctx->isPlaying, false, memory_order_relaxed);
    }

    return noErr;
}

// ── Registration Helpers ───────────────────────────────────────────────────

OSStatus AudioEngine_CreateIOProc(
    AudioObjectID          deviceID,
    AudioEngineContext    *ctx,
    AudioDeviceIOProcID   *outProcID
) {
    return AudioDeviceCreateIOProcID(deviceID, AudioDevice_RenderCallback, ctx, outProcID);
}

void AudioEngine_DestroyIOProc(
    AudioObjectID         deviceID,
    AudioDeviceIOProcID   procID
) {
    AudioDeviceDestroyIOProcID(deviceID, procID);
}
