// AudioEngineContext.h
// ytsplayer
// Shared C context struct passed to the CoreAudio IOProc.
// Must contain NO Swift/ObjC types — only C primitives and atomics.
//
// Swift cannot directly call _Atomic field operations, so we expose
// C accessor functions for every atomic field.

#pragma once

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include "LockFreeRingBuffer.h"

/// All state the real-time IOProc needs. Allocated once on startup.
typedef struct {
    /// Pointer to the lock-free SPSC ring buffer
    SPSCRingBuffer *ringBuffer;

    /// Atomic elapsed frame counter — written by IOProc, read by UI
    _Atomic uint64_t currentFramePosition;

    /// Total frames in the current track
    _Atomic uint64_t totalFrames;

    /// True when the engine should be rendering audio
    _Atomic bool isPlaying;

    /// Linear gain scalar [0.0–1.0] applied per-frame (click suppression)
    _Atomic float outputGain;

    /// Current nominal sample rate
    uint32_t sampleRate;

    /// Bit depth (informational)
    uint32_t bitDepth;

    /// Channel count
    uint32_t channels;
} AudioEngineContext;

// ── Lifecycle ──────────────────────────────────────────────────────────────

static inline AudioEngineContext *AudioEngineContext_Create(size_t ringBufferCapacityFrames) {
    AudioEngineContext *ctx = (AudioEngineContext *)calloc(1, sizeof(AudioEngineContext));
    ctx->ringBuffer = RingBuffer_Create(ringBufferCapacityFrames);
    atomic_store_explicit(&ctx->currentFramePosition, 0,     memory_order_relaxed);
    atomic_store_explicit(&ctx->totalFrames,          0,     memory_order_relaxed);
    atomic_store_explicit(&ctx->isPlaying,            false, memory_order_relaxed);
    atomic_store_explicit(&ctx->outputGain,           1.0f,  memory_order_relaxed);
    return ctx;
}

static inline void AudioEngineContext_Destroy(AudioEngineContext *ctx) {
    if (!ctx) return;
    RingBuffer_Destroy(ctx->ringBuffer);
    free(ctx);
}

// ── Swift-callable atomic accessors ───────────────────────────────────────
// These are non-inline extern functions so Swift can call them across the C bridge.

static inline bool   AEC_GetIsPlaying(AudioEngineContext *ctx) {
    return atomic_load_explicit(&ctx->isPlaying, memory_order_acquire);
}
static inline void   AEC_SetIsPlaying(AudioEngineContext *ctx, bool v) {
    atomic_store_explicit(&ctx->isPlaying, v, memory_order_release);
}

static inline uint64_t AEC_GetCurrentFrame(AudioEngineContext *ctx) {
    return atomic_load_explicit(&ctx->currentFramePosition, memory_order_relaxed);
}
static inline void     AEC_SetCurrentFrame(AudioEngineContext *ctx, uint64_t v) {
    atomic_store_explicit(&ctx->currentFramePosition, v, memory_order_release);
}

static inline uint64_t AEC_GetTotalFrames(AudioEngineContext *ctx) {
    return atomic_load_explicit(&ctx->totalFrames, memory_order_relaxed);
}
static inline void     AEC_SetTotalFrames(AudioEngineContext *ctx, uint64_t v) {
    atomic_store_explicit(&ctx->totalFrames, v, memory_order_release);
}

static inline float AEC_GetOutputGain(AudioEngineContext *ctx) {
    return atomic_load_explicit(&ctx->outputGain, memory_order_relaxed);
}
static inline void  AEC_SetOutputGain(AudioEngineContext *ctx, float v) {
    atomic_store_explicit(&ctx->outputGain, v, memory_order_relaxed);
}

static inline void AEC_ResetPlayback(AudioEngineContext *ctx) {
    atomic_store_explicit(&ctx->isPlaying,            false, memory_order_seq_cst);
    atomic_store_explicit(&ctx->currentFramePosition, 0,     memory_order_seq_cst);
    atomic_store_explicit(&ctx->totalFrames,          0,     memory_order_seq_cst);
    atomic_store_explicit(&ctx->outputGain,           1.0f,  memory_order_seq_cst);
}
