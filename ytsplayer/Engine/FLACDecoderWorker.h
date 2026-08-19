// FLACDecoderWorker.h
// ytsplayer
// C-linkage API for the background libFLAC decoder.
// Safe to import from the Swift bridging header.

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include "AudioEngineContext.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque decoder handle
typedef struct FLACDecoderWorker FLACDecoderWorker;

/// Create a decoder for the given file path.
/// Returns NULL on failure.
FLACDecoderWorker *FLACDecoder_Create(const char *filePath, AudioEngineContext *ctx);

/// Start decoding asynchronously on a background GCD queue.
/// Signals ctx->isPlaying = true once the ring buffer is at least half full.
void FLACDecoder_Start(FLACDecoderWorker *worker);

/// Signal the decoder to stop at the next safe point and release resources.
void FLACDecoder_Stop(FLACDecoderWorker *worker);

/// Free the decoder. Call only after FLACDecoder_Stop has returned.
void FLACDecoder_Destroy(FLACDecoderWorker *worker);

/// Seek to a specific frame position within the current file.
/// Safe to call from the main thread; decoder will drain and refill the ring buffer.
bool FLACDecoder_Seek(FLACDecoderWorker *worker, uint64_t targetFrame);

#ifdef __cplusplus
}
#endif
