// LockFreeRingBuffer.h
// ytsplayer
// Lock-Free Single-Producer Single-Consumer (SPSC) ring buffer.
//
// Constraints:
//   - Capacity MUST be a power of two (enforced by assertion)
//   - Only ONE thread calls RingBuffer_Write (decoder worker)
//   - Only ONE thread calls RingBuffer_Read  (CoreAudio IOProc)
//   - No locks, no OS calls, no heap allocation in the hot path
//   - Correct memory ordering via acquire/release atomics

#pragma once

#include <stdatomic.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

/// Stereo interleaved float32 SPSC ring buffer.
typedef struct {
    float          *buffer;           ///< Stereo interleaved samples [L, R, L, R, ...]
    size_t          capacityFrames;   ///< Number of stereo frames (must be power of two)
    _Atomic size_t  writeIndex;       ///< Monotonically increasing write position (frames)
    _Atomic size_t  readIndex;        ///< Monotonically increasing read position (frames)
} SPSCRingBuffer;

/// Create a new ring buffer. Called once on startup — NOT real-time safe.
static inline SPSCRingBuffer *RingBuffer_Create(size_t capacityFrames) {
    // Capacity must be a power of two for the bitmask trick
    assert((capacityFrames & (capacityFrames - 1)) == 0 && "Ring buffer capacity must be power of two");

    SPSCRingBuffer *rb = (SPSCRingBuffer *)malloc(sizeof(SPSCRingBuffer));
    if (!rb) return NULL;

    rb->buffer = (float *)malloc(capacityFrames * 2 * sizeof(float)); // stereo
    if (!rb->buffer) { free(rb); return NULL; }

    rb->capacityFrames = capacityFrames;
    atomic_init(&rb->writeIndex, 0);
    atomic_init(&rb->readIndex, 0);
    return rb;
}

/// Destroy a ring buffer. Called on shutdown — NOT real-time safe.
static inline void RingBuffer_Destroy(SPSCRingBuffer *rb) {
    if (!rb) return;
    free(rb->buffer);
    free(rb);
}

/// Returns the number of frames currently available for reading.
static inline size_t RingBuffer_AvailableToRead(const SPSCRingBuffer *rb) {
    size_t w = atomic_load_explicit(&rb->writeIndex, memory_order_acquire);
    size_t r = atomic_load_explicit(&rb->readIndex, memory_order_relaxed);
    return w - r;
}

/// Returns the number of frames available for writing.
static inline size_t RingBuffer_AvailableToWrite(const SPSCRingBuffer *rb) {
    size_t w = atomic_load_explicit(&rb->writeIndex, memory_order_relaxed);
    size_t r = atomic_load_explicit(&rb->readIndex, memory_order_acquire);
    return rb->capacityFrames - (w - r);
}

/// Write up to `frames` stereo interleaved float32 frames.
/// Returns the number of frames actually written (may be < frames if buffer full).
/// PRODUCER ONLY — called from the decoder background thread.
static inline size_t RingBuffer_Write(SPSCRingBuffer *rb, const float *data, size_t frames) {
    size_t write    = atomic_load_explicit(&rb->writeIndex, memory_order_relaxed);
    size_t read     = atomic_load_explicit(&rb->readIndex,  memory_order_acquire);
    size_t available = rb->capacityFrames - (write - read);
    size_t toWrite  = frames < available ? frames : available;

    if (toWrite == 0) return 0;

    size_t mask = rb->capacityFrames - 1;

    // Handle wrap-around: write in up to two contiguous segments
    size_t writePos = write & mask;
    size_t firstChunk = rb->capacityFrames - writePos;
    if (firstChunk > toWrite) firstChunk = toWrite;

    memcpy(&rb->buffer[writePos * 2], &data[0],              firstChunk * 2 * sizeof(float));
    if (toWrite > firstChunk) {
        memcpy(&rb->buffer[0],        &data[firstChunk * 2], (toWrite - firstChunk) * 2 * sizeof(float));
    }

    atomic_store_explicit(&rb->writeIndex, write + toWrite, memory_order_release);
    return toWrite;
}

/// Read up to `frames` stereo interleaved float32 frames.
/// Returns the number of frames actually read (may be < frames on underrun).
/// CONSUMER ONLY — called from the CoreAudio real-time IOProc.
/// REAL-TIME SAFE: no heap alloc, no locks, no OS calls.
static inline size_t RingBuffer_Read(SPSCRingBuffer *rb, float *data, size_t frames) {
    size_t read     = atomic_load_explicit(&rb->readIndex,   memory_order_relaxed);
    size_t write    = atomic_load_explicit(&rb->writeIndex,  memory_order_acquire);
    size_t available = write - read;
    size_t toRead   = frames < available ? frames : available;

    if (toRead == 0) return 0;

    size_t mask    = rb->capacityFrames - 1;
    size_t readPos = read & mask;
    size_t firstChunk = rb->capacityFrames - readPos;
    if (firstChunk > toRead) firstChunk = toRead;

    memcpy(&data[0],             &rb->buffer[readPos * 2], firstChunk * 2 * sizeof(float));
    if (toRead > firstChunk) {
        memcpy(&data[firstChunk * 2], &rb->buffer[0],       (toRead - firstChunk) * 2 * sizeof(float));
    }

    atomic_store_explicit(&rb->readIndex, read + toRead, memory_order_release);
    return toRead;
}

/// Reset both indices to zero. Call only when engine is fully stopped.
/// NOT real-time safe.
static inline void RingBuffer_Reset(SPSCRingBuffer *rb) {
    atomic_store_explicit(&rb->writeIndex, 0, memory_order_seq_cst);
    atomic_store_explicit(&rb->readIndex,  0, memory_order_seq_cst);
}
