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
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ── DSP Helpers ────────────────────────────────────────────────────────────

static const float EQ_FREQS[10] = { 31.5f, 63.0f, 125.0f, 250.0f, 500.0f, 1000.0f, 2000.0f, 4000.0f, 8000.0f, 16000.0f };

static inline void CalculatePeakingEQ(float fs, float f0, float dBgain, float Q, float* b0, float* b1, float* b2, float* a1, float* a2) {
    float A = powf(10.0f, dBgain / 40.0f);
    float w0 = 2.0f * (float)M_PI * f0 / fs;
    float alpha = sinf(w0) / (2.0f * Q);

    float a0_inv = 1.0f / (1.0f + alpha / A);
    *b0 = (1.0f + alpha * A) * a0_inv;
    *b1 = (-2.0f * cosf(w0)) * a0_inv;
    *b2 = (1.0f - alpha * A) * a0_inv;
    *a1 = (-2.0f * cosf(w0)) * a0_inv;
    *a2 = (1.0f - alpha / A) * a0_inv;
}

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

    // ── Apply software volume if NOT in bit-perfect mode ────────────────────
    bool isBitPerfect = atomic_load_explicit(&ctx->isBitPerfect, memory_order_relaxed);
    float softwareVolume = isBitPerfect ? 1.0f : atomic_load_explicit(&ctx->softwareVolume, memory_order_relaxed);

    // ── Pull frames from the lock-free ring buffer ───────────────────────────
    UInt32 framesRead = (UInt32)RingBuffer_Read(ctx->ringBuffer, outputBuffer, (size_t)frameCount);

    // ── Underrun: fill remainder with silence (never drop out hard) ──────────
    if (framesRead < frameCount) {
        UInt32 silenceFrames = frameCount - framesRead;
        memset(outputBuffer + (framesRead * 2), 0, silenceFrames * 2 * sizeof(float));
    }

    // ── Apply gain in-place ─────────────────────────────────────────────────
    float replayGain = atomic_load_explicit(&ctx->trackReplayGain, memory_order_relaxed);
    float finalGain = gain * softwareVolume * replayGain;
    if (finalGain != 1.0f) {
        UInt32 samples = frameCount * 2; // stereo
        for (UInt32 i = 0; i < samples; i++) {
            outputBuffer[i] *= finalGain;
        }
    }
    // ── DSP: EQ & Crossfeed ─────────────────────────────────────────────────
    bool doEQ = atomic_load_explicit(&ctx->eqEnabled, memory_order_relaxed);
    bool doCrossfeed = atomic_load_explicit(&ctx->crossfeedEnabled, memory_order_relaxed);
    
    if (doEQ || doCrossfeed) {
        float fs = (float)ctx->sampleRate;
        if (fs <= 0) fs = 44100.0f; // fallback
        
        // 1. Update EQ Coefficients if gains changed
        if (doEQ) {
            for (int i = 0; i < 10; i++) {
                float targetGain = atomic_load_explicit(&ctx->eqGains[i], memory_order_relaxed);
                if (targetGain != ctx->eq_lastGains[i]) {
                    CalculatePeakingEQ(fs, EQ_FREQS[i], targetGain, 1.41f, 
                                       &ctx->eq_b0[i], &ctx->eq_b1[i], &ctx->eq_b2[i], 
                                       &ctx->eq_a1[i], &ctx->eq_a2[i]);
                    ctx->eq_lastGains[i] = targetGain;
                }
            }
        }
        
        // 2. Initialize Crossfeed if needed
        if (doCrossfeed && !ctx->cf_initialized) {
            memset(ctx->cf_delayL, 0, sizeof(ctx->cf_delayL));
            memset(ctx->cf_delayR, 0, sizeof(ctx->cf_delayR));
            ctx->cf_delayIdx = 0;
            ctx->cf_xl1 = ctx->cf_yl1 = 0;
            ctx->cf_xr1 = ctx->cf_yr1 = 0;
            ctx->cf_initialized = true;
        }

        // Crossfeed parameters: 400us delay, 1000Hz lowpass
        int delaySamples = (int)(fs * 0.0004f);
        if (delaySamples > 127) delaySamples = 127;
        if (delaySamples < 1) delaySamples = 1;
        float cf_bleed = 0.45f; // amount of bleed

        // Basic 1-pole lowpass for Crossfeed (1000Hz)
        float rc = 1.0f / (2.0f * (float)M_PI * 1000.0f);
        float dt = 1.0f / fs;
        float alpha = dt / (rc + dt);

        // Process frames
        for (UInt32 i = 0; i < frameCount; i++) {
            float L = outputBuffer[i * 2];
            float R = outputBuffer[i * 2 + 1];

            // --- CROSSFEED ---
            if (doCrossfeed) {
                // Read delayed samples
                int readIdx = (ctx->cf_delayIdx - delaySamples + 128) % 128;
                float dL = ctx->cf_delayL[readIdx];
                float dR = ctx->cf_delayR[readIdx];
                
                // Write current samples to delay line
                ctx->cf_delayL[ctx->cf_delayIdx] = L;
                ctx->cf_delayR[ctx->cf_delayIdx] = R;
                ctx->cf_delayIdx = (ctx->cf_delayIdx + 1) % 128;

                // Lowpass the delayed signal
                float lpL = ctx->cf_yl1 + alpha * (dL - ctx->cf_yl1);
                ctx->cf_yl1 = lpL;
                
                float lpR = ctx->cf_yr1 + alpha * (dR - ctx->cf_yr1);
                ctx->cf_yr1 = lpR;

                // Mix
                float newL = L + lpR * cf_bleed;
                float newR = R + lpL * cf_bleed;
                
                // Attenuate slightly to avoid clipping from added bleed
                L = newL * 0.7f;
                R = newR * 0.7f;
            }

            // --- EQ ---
            if (doEQ) {
                for (int b = 0; b < 10; b++) {
                    if (ctx->eq_lastGains[b] == 0.0f) continue; // Skip 0dB bands
                    
                    float b0 = ctx->eq_b0[b], b1 = ctx->eq_b1[b], b2 = ctx->eq_b2[b];
                    float a1 = ctx->eq_a1[b], a2 = ctx->eq_a2[b];
                    
                    // Left
                    float xL = L;
                    float yL = b0 * xL + b1 * ctx->eq_xl1[b] + b2 * ctx->eq_xl2[b] 
                                       - a1 * ctx->eq_yl1[b] - a2 * ctx->eq_yl2[b];
                    ctx->eq_xl2[b] = ctx->eq_xl1[b]; ctx->eq_xl1[b] = xL;
                    ctx->eq_yl2[b] = ctx->eq_yl1[b]; ctx->eq_yl1[b] = yL;
                    L = yL;
                    
                    // Right
                    float xR = R;
                    float yR = b0 * xR + b1 * ctx->eq_xr1[b] + b2 * ctx->eq_xr2[b] 
                                       - a1 * ctx->eq_yr1[b] - a2 * ctx->eq_yr2[b];
                    ctx->eq_xr2[b] = ctx->eq_xr1[b]; ctx->eq_xr1[b] = xR;
                    ctx->eq_yr2[b] = ctx->eq_yr1[b]; ctx->eq_yr1[b] = yR;
                    R = yR;
                }
            }

            outputBuffer[i * 2]     = L;
            outputBuffer[i * 2 + 1] = R;
        }
    }

    // ── Update elapsed frame counter for UI (lock-free, relaxed store) ───────
    uint64_t prev = atomic_fetch_add_explicit(
        &ctx->currentFramePosition,
        (uint64_t)framesRead,
        memory_order_relaxed
    );

    // (We no longer force isPlaying = false based on totalFrames to allow gapless transitions.
    // The swift layer or the decoder worker will manage EOF).

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
