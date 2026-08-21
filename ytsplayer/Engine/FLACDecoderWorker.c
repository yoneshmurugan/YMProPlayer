// FLACDecoderWorker.c
// ytsplayer
//
// Background libFLAC stream decoder worker.
// Runs on a GCD serial queue at QOS_CLASS_BACKGROUND.
// Feeds decoded PCM into the SPSC ring buffer consumed by the CoreAudio IOProc.

#include "FLACDecoderWorker.h"
#include "LockFreeRingBuffer.h"
#include "AudioEngineContext.h"

#include <FLAC/stream_decoder.h>
#include <dispatch/dispatch.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>   // usleep
#include <stdatomic.h>
#include <stdio.h>

// ── Pre-buffer target: fill ring buffer to 50% before unblocking playback ─
#define PREBUFFER_RATIO 0.5

// ── Internal decoder state ─────────────────────────────────────────────────
struct FLACDecoderWorker {
    FLAC__StreamDecoder   *decoder;
    AudioEngineContext    *ctx;
    char                   filePath[4096];
    dispatch_queue_t       queue;
    _Atomic bool           shouldStop;
    _Atomic bool           isReady;     ///< true once pre-buffer is full
    uint64_t               seekTarget;  ///< 0 = no seek pending
    _Atomic bool           seekPending;
};

// ── libFLAC Callbacks ──────────────────────────────────────────────────────

static FLAC__StreamDecoderWriteStatus flac_write_callback(
    const FLAC__StreamDecoder *decoder,
    const FLAC__Frame         *frame,
    const FLAC__int32 *const   buffer[],
    void                      *client_data
) {
    struct FLACDecoderWorker *worker = (struct FLACDecoderWorker *)client_data;
    AudioEngineContext       *ctx    = worker->ctx;

    if (atomic_load_explicit(&worker->shouldStop, memory_order_relaxed)) {
        return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    }

    size_t blocksize      = frame->header.blocksize;
    uint32_t bitsPerSample = frame->header.bits_per_sample;
    uint32_t channels     = frame->header.channels;

    // Convert integer samples → float32
    float scale = 1.0f / (float)(1 << (bitsPerSample - 1));

    uint32_t ratio = ctx->downsampleRatio;
    if (ratio < 1) ratio = 1;

    size_t outFrames = blocksize / ratio;

    // Stack-allocate the interleaved float buffer
    float interleavedBuffer[outFrames * 2];

    for (size_t i = 0; i < outFrames; i++) {
        size_t inIndex = i * ratio;
        if (channels >= 2) {
            interleavedBuffer[i * 2]     = (float)buffer[0][inIndex] * scale;
            interleavedBuffer[i * 2 + 1] = (float)buffer[1][inIndex] * scale;
        } else {
            // Mono → duplicate to both channels
            float sample = (float)buffer[0][inIndex] * scale;
            interleavedBuffer[i * 2]     = sample;
            interleavedBuffer[i * 2 + 1] = sample;
        }
    }

    // Write to ring buffer, spin-wait if full (1ms sleep, background thread only)
    size_t written = 0;
    while (written < outFrames) {
        if (atomic_load_explicit(&worker->shouldStop, memory_order_relaxed)) {
            return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
        }
        size_t w = RingBuffer_Write(ctx->ringBuffer,
                                    interleavedBuffer + written * 2,
                                    outFrames - written);
        written += w;
        if (written < outFrames) {
            usleep(1000); // 1ms yield — background thread only, never in IOProc
        }
    }

    // Once ring buffer is half full, signal that playback may begin
    if (!atomic_load_explicit(&worker->isReady, memory_order_relaxed)) {
        size_t available = RingBuffer_AvailableToRead(ctx->ringBuffer);
        size_t half      = ctx->ringBuffer->capacityFrames / 2;
        if (available >= half) {
            atomic_store_explicit(&worker->isReady, true, memory_order_release);
            atomic_store_explicit(&ctx->isPlaying,  true, memory_order_release);
        }
    }

    return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

static void flac_metadata_callback(
    const FLAC__StreamDecoder        *decoder,
    const FLAC__StreamMetadata       *metadata,
    void                             *client_data
) {
    struct FLACDecoderWorker *worker = (struct FLACDecoderWorker *)client_data;
    AudioEngineContext       *ctx    = worker->ctx;

    if (metadata->type == FLAC__METADATA_TYPE_STREAMINFO) {
        ctx->sampleRate = metadata->data.stream_info.sample_rate;
        ctx->bitDepth   = metadata->data.stream_info.bits_per_sample;
        ctx->channels   = metadata->data.stream_info.channels;
        atomic_store_explicit(
            &ctx->totalFrames,
            (uint64_t)metadata->data.stream_info.total_samples,
            memory_order_release
        );
    }
}

static void flac_error_callback(
    const FLAC__StreamDecoder      *decoder,
    FLAC__StreamDecoderErrorStatus  status,
    void                           *client_data
) {
    // Background thread — printf is safe here
    fprintf(stderr, "[ytsplayer] FLAC decode error: %s\n",
            FLAC__StreamDecoderErrorStatusString[status]);
}

// ── Public API ─────────────────────────────────────────────────────────────

FLACDecoderWorker *FLACDecoder_Create(const char *filePath, AudioEngineContext *ctx) {
    struct FLACDecoderWorker *worker = calloc(1, sizeof(struct FLACDecoderWorker));
    if (!worker) return NULL;

    strncpy(worker->filePath, filePath, sizeof(worker->filePath) - 1);
    worker->ctx = ctx;

    worker->decoder = FLAC__stream_decoder_new();
    if (!worker->decoder) { free(worker); return NULL; }

    FLAC__stream_decoder_set_md5_checking(worker->decoder, false);

    FLAC__StreamDecoderInitStatus initStatus =
        FLAC__stream_decoder_init_file(
            worker->decoder,
            filePath,
            flac_write_callback,
            flac_metadata_callback,
            flac_error_callback,
            worker
        );

    if (initStatus != FLAC__STREAM_DECODER_INIT_STATUS_OK) {
        fprintf(stderr, "[ytsplayer] FLAC init failed: %s\n",
                FLAC__StreamDecoderInitStatusString[initStatus]);
        FLAC__stream_decoder_delete(worker->decoder);
        free(worker);
        return NULL;
    }

    worker->queue = dispatch_queue_create("com.ytsplayer.decoder", DISPATCH_QUEUE_SERIAL);
    atomic_store_explicit(&worker->shouldStop, false, memory_order_relaxed);
    atomic_store_explicit(&worker->isReady,    false, memory_order_relaxed);
    atomic_store_explicit(&worker->seekPending, false, memory_order_relaxed);

    // Decode STREAMINFO metadata block immediately (synchronous, cheap)
    FLAC__stream_decoder_process_until_end_of_metadata(worker->decoder);

    return worker;
}

void FLACDecoder_Start(FLACDecoderWorker *worker) {
    struct FLACDecoderWorker *w = (struct FLACDecoderWorker *)worker;

    // Reset ring buffer and frame counter before starting a new track
    RingBuffer_Reset(w->ctx->ringBuffer);
    atomic_store_explicit(&w->ctx->currentFramePosition, 0, memory_order_seq_cst);
    atomic_store_explicit(&w->ctx->isPlaying,  false,   memory_order_seq_cst);
    atomic_store_explicit(&w->isReady,         false,   memory_order_relaxed);
    atomic_store_explicit(&w->shouldStop,      false,   memory_order_relaxed);
    atomic_store_explicit(&w->seekPending,     false,   memory_order_relaxed);

    dispatch_async(w->queue, ^{
        while (!atomic_load_explicit(&w->shouldStop, memory_order_relaxed)) {
            if (atomic_exchange_explicit(&w->seekPending, false, memory_order_acquire)) {
                uint64_t target = w->seekTarget;
                FLAC__stream_decoder_seek_absolute(w->decoder, target);
                // Clear the EOF flag from the decoder if we seeked after EOF
                if (FLAC__stream_decoder_get_state(w->decoder) == FLAC__STREAM_DECODER_END_OF_STREAM) {
                    FLAC__stream_decoder_flush(w->decoder);
                    FLAC__stream_decoder_seek_absolute(w->decoder, target);
                }
            }
            
            if (!FLAC__stream_decoder_process_single(w->decoder)) {
                break; // Error
            }
            
            if (FLAC__stream_decoder_get_state(w->decoder) == FLAC__STREAM_DECODER_END_OF_STREAM) {
                // Track ended naturally — ensure isPlaying is false
                atomic_store_explicit(&w->ctx->isPlaying, false, memory_order_release);
                break;
            }
        }
    });
}

void FLACDecoder_Stop(FLACDecoderWorker *worker) {
    struct FLACDecoderWorker *w = (struct FLACDecoderWorker *)worker;
    atomic_store_explicit(&w->shouldStop, true, memory_order_release);
    // Wait for the async decode block to finish
    dispatch_sync(w->queue, ^{ /* drain */ });
    atomic_store_explicit(&w->ctx->isPlaying, false, memory_order_release);
}

void FLACDecoder_Destroy(FLACDecoderWorker *worker) {
    struct FLACDecoderWorker *w = (struct FLACDecoderWorker *)worker;
    if (!w) return;
    FLAC__stream_decoder_finish(w->decoder);
    FLAC__stream_decoder_delete(w->decoder);
    // ARC does not manage dispatch_queue_t in C — release explicitly
    dispatch_release(w->queue);
    free(w);
}

bool FLACDecoder_Seek(FLACDecoderWorker *worker, uint64_t targetFrame) {
    struct FLACDecoderWorker *w = (struct FLACDecoderWorker *)worker;
    atomic_store_explicit(&w->ctx->isPlaying, false, memory_order_release);

    // Drain and reset the ring buffer
    RingBuffer_Reset(w->ctx->ringBuffer);
    atomic_store_explicit(&w->ctx->currentFramePosition, targetFrame, memory_order_release);
    atomic_store_explicit(&w->isReady, false, memory_order_relaxed);

    w->seekTarget = targetFrame;
    atomic_store_explicit(&w->seekPending, true, memory_order_release);
    
    return true;
}
