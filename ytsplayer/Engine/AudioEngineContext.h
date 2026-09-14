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
    
    /// ReplayGain scalar applied per-frame
    _Atomic float trackReplayGain;

    /// True if bit-perfect mode is enabled (ignores software volume)
    _Atomic bool isBitPerfect;

    /// Software volume scalar [0.0–1.0], only applied if !isBitPerfect
    _Atomic float softwareVolume;

    /// Current nominal sample rate
    uint32_t sampleRate;

    /// Bit depth (informational)
    uint32_t bitDepth;

    /// Channel count
    uint32_t channels;

    /// Ratio for integer downsampling (e.g. 2 for 192kHz -> 96kHz, 1 for no downsampling)
    uint32_t downsampleRatio;

    // ── DSP: EQ ─────────────────────────────────────────────────────────────
    _Atomic bool eqEnabled;
    _Atomic float eqGains[10]; // Gains for 10 bands (-12dB to +12dB)
    
    // Internal state for 10 Stereo Biquad filters
    float eq_b0[10], eq_b1[10], eq_b2[10], eq_a1[10], eq_a2[10];
    float eq_xl1[10], eq_xl2[10], eq_yl1[10], eq_yl2[10];
    float eq_xr1[10], eq_xr2[10], eq_yr1[10], eq_yr2[10];
    float eq_lastGains[10]; // To detect changes and recalculate coefficients

    // ── DSP: Crossfeed ──────────────────────────────────────────────────────
    _Atomic bool crossfeedEnabled;
    float cf_delayL[128]; // Circular buffer for crossfeed delay
    float cf_delayR[128];
    int cf_delayIdx;
    float cf_xl1, cf_yl1; // Lowpass for L->R bleed
    float cf_xr1, cf_yr1; // Lowpass for R->L bleed
    bool cf_initialized;
} AudioEngineContext;

// ── Lifecycle ──────────────────────────────────────────────────────────────

static inline AudioEngineContext *AudioEngineContext_Create(size_t ringBufferCapacityFrames) {
    AudioEngineContext *ctx = (AudioEngineContext *)calloc(1, sizeof(AudioEngineContext));
    ctx->ringBuffer = RingBuffer_Create(ringBufferCapacityFrames);
    atomic_store_explicit(&ctx->currentFramePosition, 0,     memory_order_relaxed);
    atomic_store_explicit(&ctx->totalFrames,          0,     memory_order_relaxed);
    atomic_store_explicit(&ctx->isPlaying,            false, memory_order_relaxed);
    atomic_store_explicit(&ctx->outputGain,           1.0f,  memory_order_relaxed);
    atomic_store_explicit(&ctx->trackReplayGain,      1.0f,  memory_order_relaxed);
    atomic_store_explicit(&ctx->isBitPerfect,         true,  memory_order_relaxed);
    atomic_store_explicit(&ctx->softwareVolume,       1.0f,  memory_order_relaxed);
    ctx->downsampleRatio = 1;
    
    atomic_store_explicit(&ctx->eqEnabled, false, memory_order_relaxed);
    atomic_store_explicit(&ctx->crossfeedEnabled, false, memory_order_relaxed);
    for (int i = 0; i < 10; i++) {
        atomic_store_explicit(&ctx->eqGains[i], 0.0f, memory_order_relaxed);
        ctx->eq_lastGains[i] = -999.0f; // Force initial calc
    }
    
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

static inline uint32_t AEC_GetDownsampleRatio(AudioEngineContext *ctx) {
    return ctx->downsampleRatio;
}

// ── DSP Accessors ──────────────────────────────────────────────────────────

static inline bool AEC_GetEQEnabled(AudioEngineContext *ctx) {
    return atomic_load_explicit(&ctx->eqEnabled, memory_order_relaxed);
}
static inline void AEC_SetEQEnabled(AudioEngineContext *ctx, bool v) {
    atomic_store_explicit(&ctx->eqEnabled, v, memory_order_relaxed);
}

static inline float AEC_GetEQBandGain(AudioEngineContext *ctx, int bandIndex) {
    if (bandIndex < 0 || bandIndex >= 10) return 0.0f;
    return atomic_load_explicit(&ctx->eqGains[bandIndex], memory_order_relaxed);
}
static inline void AEC_SetEQBandGain(AudioEngineContext *ctx, int bandIndex, float gainDB) {
    if (bandIndex < 0 || bandIndex >= 10) return;
    atomic_store_explicit(&ctx->eqGains[bandIndex], gainDB, memory_order_relaxed);
}

static inline bool AEC_GetCrossfeedEnabled(AudioEngineContext *ctx) {
    return atomic_load_explicit(&ctx->crossfeedEnabled, memory_order_relaxed);
}
static inline void AEC_SetCrossfeedEnabled(AudioEngineContext *ctx, bool v) {
    atomic_store_explicit(&ctx->crossfeedEnabled, v, memory_order_relaxed);
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

static inline float AEC_GetTrackReplayGain(AudioEngineContext *ctx) {
    return atomic_load_explicit(&ctx->trackReplayGain, memory_order_relaxed);
}
static inline void  AEC_SetTrackReplayGain(AudioEngineContext *ctx, float v) {
    atomic_store_explicit(&ctx->trackReplayGain, v, memory_order_relaxed);
}

static inline bool AEC_GetIsBitPerfect(AudioEngineContext *ctx) {
    return atomic_load_explicit(&ctx->isBitPerfect, memory_order_relaxed);
}
static inline void AEC_SetIsBitPerfect(AudioEngineContext *ctx, bool v) {
    atomic_store_explicit(&ctx->isBitPerfect, v, memory_order_relaxed);
}

static inline float AEC_GetSoftwareVolume(AudioEngineContext *ctx) {
    return atomic_load_explicit(&ctx->softwareVolume, memory_order_relaxed);
}
static inline void AEC_SetSoftwareVolume(AudioEngineContext *ctx, float v) {
    atomic_store_explicit(&ctx->softwareVolume, v, memory_order_relaxed);
}

static inline void AEC_ResetPlayback(AudioEngineContext *ctx) {
    atomic_store_explicit(&ctx->isPlaying,            false, memory_order_seq_cst);
    atomic_store_explicit(&ctx->currentFramePosition, 0,     memory_order_seq_cst);
    atomic_store_explicit(&ctx->totalFrames,          0,     memory_order_seq_cst);
    atomic_store_explicit(&ctx->outputGain,           1.0f,  memory_order_seq_cst);
    atomic_store_explicit(&ctx->trackReplayGain,      1.0f,  memory_order_seq_cst);
}
