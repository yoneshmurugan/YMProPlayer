// ytsplayer-Bridging-Header.h
// ytsplayer
//
// Exposes C/C++ engine APIs to Swift.
// C++ headers must use extern "C" linkage (MetadataBridge.h already does this).

#ifndef ytsplayer_Bridging_Header_h
#define ytsplayer_Bridging_Header_h

// ── Lock-Free Ring Buffer (pure C) ────────────────────────────────────────
#include "LockFreeRingBuffer.h"

// ── Audio Engine Context (pure C) ─────────────────────────────────────────
#include "AudioEngineContext.h"

// ── Real-time IOProc (C linkage) ──────────────────────────────────────────
#include "AudioDeviceRenderCallback.h"

// ── FLAC Decoder Worker (C linkage) ───────────────────────────────────────
#include "FLACDecoderWorker.h"

// ── AV Decoder Worker (C linkage) ─────────────────────────────────────────
#include "AVDecoderWorker.h"

// ── TagLib Metadata Bridge (C linkage from C++ impl) ──────────────────────
#include "MetadataBridge.h"

#endif /* ytsplayer_Bridging_Header_h */
