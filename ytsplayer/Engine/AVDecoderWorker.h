// AVDecoderWorker.h
// ytsplayer
// C-linkage API for the background ExtAudioFile decoder (supports MP3, M4A, ALAC, AAC, WAV).
// Safe to import from the Swift bridging header.

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include "AudioEngineContext.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AVDecoderWorker AVDecoderWorker;

AVDecoderWorker *AVDecoder_Create(const char *filePath, AudioEngineContext *ctx);
void AVDecoder_Start(AVDecoderWorker *worker);
void AVDecoder_Stop(AVDecoderWorker *worker);
void AVDecoder_Destroy(AVDecoderWorker *worker);
bool AVDecoder_Seek(AVDecoderWorker *worker, uint64_t targetFrame);

#ifdef __cplusplus
}
#endif
