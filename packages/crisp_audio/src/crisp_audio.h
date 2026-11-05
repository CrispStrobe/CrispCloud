#ifndef CRISP_AUDIO_H
#define CRISP_AUDIO_H

#include <stdint.h>

#if defined(_WIN32)
#define CRISP_AUDIO_EXPORT __declspec(dllexport)
#else
#define CRISP_AUDIO_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

enum crisp_audio_result {
  CRISP_AUDIO_OK = 0,
  CRISP_AUDIO_INVALID_ARGUMENT = 1,
  CRISP_AUDIO_INVALID_INPUT = 2,
  CRISP_AUDIO_UNSUPPORTED = 3,
  CRISP_AUDIO_IO_ERROR = 4,
  CRISP_AUDIO_CANCELLED = 5,
  CRISP_AUDIO_OUT_OF_MEMORY = 6,
  CRISP_AUDIO_OUTPUT_EXISTS = 7
};

typedef struct crisp_audio_info {
  uint64_t frames;
  uint32_t sample_rate;
  uint32_t channels;
} crisp_audio_info;

/* A job is owned by the caller. cancel/progress may run on another thread;
   destroy must run only after the operation and all polls have completed. */
typedef struct crisp_audio_job crisp_audio_job;

CRISP_AUDIO_EXPORT int32_t crisp_audio_abi_version(void);
CRISP_AUDIO_EXPORT crisp_audio_job* crisp_audio_job_create(void);
CRISP_AUDIO_EXPORT void crisp_audio_job_cancel(crisp_audio_job* job);
CRISP_AUDIO_EXPORT uint32_t crisp_audio_job_progress(crisp_audio_job* job);
CRISP_AUDIO_EXPORT void crisp_audio_job_destroy(crisp_audio_job* job);

/* All paths are UTF-8, including on Windows. These functions perform blocking
   bounded-memory work and must be called from a Dart worker isolate. */
CRISP_AUDIO_EXPORT int32_t crisp_audio_probe(
    crisp_audio_job* job, const char* input_path, crisp_audio_info* result);

/* Peak absolute amplitude per equally sized bin, across all channels. */
CRISP_AUDIO_EXPORT int32_t crisp_audio_waveform(
    crisp_audio_job* job, const char* input_path, float* peaks, uint32_t count);

/* Exports PCM16 little-endian WAV, retaining sample rate and channel count.
   Times are rounded to the nearest sample. end_us is exclusive. Gain is in
   dB, fades are linear amplitude ramps at the selected region's boundaries.
   Existing outputs are never overwritten. Failure/cancellation removes only
   a file created by this call. Successful export closes and flushes the file. */
CRISP_AUDIO_EXPORT int32_t crisp_audio_render(
    crisp_audio_job* job, const char* input_path, const char* output_path,
    int64_t start_us, int64_t end_us, double gain_db,
    int64_t fade_in_us, int64_t fade_out_us, int32_t muted);

#ifdef __cplusplus
}
#endif
#endif
