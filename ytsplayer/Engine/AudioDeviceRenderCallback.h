// AudioDeviceRenderCallback.h
// ytsplayer

#pragma once

#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include "AudioEngineContext.h"

#ifdef __cplusplus
extern "C" {
#endif

/// The real-time IOProc — called by CoreAudio HAL at hardware clock rate.
/// REAL-TIME CONSTRAINTS: NO malloc, NO locks, NO Swift/ObjC runtime.
OSStatus AudioDevice_RenderCallback(
    AudioObjectID           inDevice,
    const AudioTimeStamp   *inNow,
    const AudioBufferList  *inInputData,
    const AudioTimeStamp   *inInputTime,
    AudioBufferList        *outOutputData,
    const AudioTimeStamp   *inOutputTime,
    void                   *inClientData
);

/// Swift-callable C helper: creates and registers the IOProc, returning a proc ID.
/// Avoids passing the C function pointer from Swift (incompatible bridging in Swift 5+).
OSStatus AudioEngine_CreateIOProc(
    AudioObjectID         deviceID,
    AudioEngineContext   *ctx,
    AudioDeviceIOProcID  *outProcID
);

/// Swift-callable C helper: removes the IOProc registration.
void AudioEngine_DestroyIOProc(
    AudioObjectID        deviceID,
    AudioDeviceIOProcID  procID
);

#ifdef __cplusplus
}
#endif
