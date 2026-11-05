#include "crisp_audio.h"

#if defined(_WIN32) && !defined(NOMINMAX)
#define NOMINMAX
#endif

// This is an offline decoder, not an audio-device or recording engine. Custom
// file callbacks also let cancellation interrupt MP3 length scans.
#define MA_NO_DEVICE_IO
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_NO_ENGINE
#define MA_NO_THREADING
#define MA_NO_GENERATION
#define MA_NO_ENCODING
#define MA_NO_RUNTIME_LINKING
#define MINIAUDIO_IMPLEMENTATION
#include "third_party/miniaudio/miniaudio.h"

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>
#include <new>
#include <string>
#include <vector>
#include <fcntl.h>

#if defined(_WIN32)
#include <io.h>
#include <sys/stat.h>
#include <windows.h>
#else
#include <unistd.h>
#endif

struct crisp_audio_job {
  std::atomic<bool> cancelled{false};
  // Parts per million. Integers avoid non-lock-free floating point atomics.
  std::atomic<uint32_t> progress{0};
};

namespace {
constexpr uint64_t kChunkFrames = 4096;
// The first editor retains mono/stereo exactly. Multichannel exports need
// explicit speaker-layout metadata and are rejected rather than losing it.
constexpr uint32_t kMaximumChannels = 2;
constexpr uint32_t kMaximumSampleRate = 384000;
constexpr uint64_t kMaximumSeconds = 24 * 60 * 60;

bool cancelled(const crisp_audio_job* job) {
  return job != nullptr && job->cancelled.load(std::memory_order_relaxed);
}

void progress(crisp_audio_job* job, uint64_t completed, uint64_t total) {
  job->progress.store(static_cast<uint32_t>(completed * 1000000 / total),
                      std::memory_order_relaxed);
}

#if defined(_WIN32)
std::wstring wide_path(const char* path) {
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1,
                                      nullptr, 0);
  if (count == 0) return {};
  std::wstring wide(static_cast<size_t>(count), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide.data(),
                          count) == 0) return {};
  return wide;
}
#endif

FILE* open_input(const char* path) {
#if defined(_WIN32)
  const auto wide = wide_path(path);
  return wide.empty() ? nullptr : _wfopen(wide.c_str(), L"rb");
#else
  return fopen(path, "rb");
#endif
}

struct Input {
  FILE* file = nullptr;
  crisp_audio_job* job;
  explicit Input(crisp_audio_job* value) : job(value) {}
  ~Input() { if (file != nullptr) fclose(file); }

  static ma_result read(ma_decoder* decoder, void* buffer, size_t size,
                        size_t* bytes_read) {
    auto* input = static_cast<Input*>(decoder->pUserData);
    *bytes_read = 0;
    if (cancelled(input->job)) return MA_CANCELLED;
    *bytes_read = fread(buffer, 1, size, input->file);
    if (ferror(input->file)) return MA_IO_ERROR;
    return *bytes_read == 0 ? MA_AT_END : MA_SUCCESS;
  }

  static ma_result seek(ma_decoder* decoder, ma_int64 offset,
                        ma_seek_origin origin) {
    auto* input = static_cast<Input*>(decoder->pUserData);
    if (cancelled(input->job)) return MA_CANCELLED;
    const int whence = origin == ma_seek_origin_start ? SEEK_SET
                     : origin == ma_seek_origin_current ? SEEK_CUR : SEEK_END;
#if defined(_WIN32)
    const int result = _fseeki64(input->file, offset, whence);
#else
    const int result = fseeko(input->file, static_cast<off_t>(offset), whence);
#endif
    return result == 0 ? MA_SUCCESS : MA_BAD_SEEK;
  }
};

struct Decoder {
  Input input;
  ma_decoder decoder{};
  bool initialized = false;
  ma_uint64 frames = 0;
  explicit Decoder(crisp_audio_job* job) : input(job) {}
  ~Decoder() { if (initialized) ma_decoder_uninit(&decoder); }

  int open(const char* path) {
    if (cancelled(input.job)) return CRISP_AUDIO_CANCELLED;
    input.file = open_input(path);
    if (input.file == nullptr) return CRISP_AUDIO_IO_ERROR;
    const auto config = ma_decoder_config_init(ma_format_f32, 0, 0);
    const auto result = ma_decoder_init(Input::read, Input::seek, &input,
                                        &config, &decoder);
    initialized = result == MA_SUCCESS;
    if (cancelled(input.job)) return CRISP_AUDIO_CANCELLED;
    if (result != MA_SUCCESS) {
      return result == MA_OUT_OF_MEMORY ? CRISP_AUDIO_OUT_OF_MEMORY
                                        : CRISP_AUDIO_INVALID_INPUT;
    }
    if (decoder.outputChannels < 1 || decoder.outputChannels > kMaximumChannels ||
        decoder.outputSampleRate < 8000 ||
        decoder.outputSampleRate > kMaximumSampleRate) {
      return CRISP_AUDIO_UNSUPPORTED;
    }
    const auto length_result = ma_decoder_get_length_in_pcm_frames(&decoder,
                                                                  &frames);
    if (cancelled(input.job)) return CRISP_AUDIO_CANCELLED;
    if (length_result != MA_SUCCESS || frames == 0) {
      return CRISP_AUDIO_INVALID_INPUT;
    }
    if (frames > kMaximumSeconds * decoder.outputSampleRate) {
      return CRISP_AUDIO_UNSUPPORTED;
    }
    return CRISP_AUDIO_OK;
  }
};

struct Output {
  std::string path;
#if defined(_WIN32)
  std::wstring wide;
#endif
  FILE* file = nullptr;
  bool created = false;
  bool committed = false;
  explicit Output(const char* value) : path(value)
#if defined(_WIN32)
      , wide(wide_path(value))
#endif
      {}
  ~Output() {
    if (file != nullptr) fclose(file);
    if (created && !committed) {
#if defined(_WIN32)
      _wremove(wide.c_str());
#else
      std::remove(path.c_str());
#endif
    }
  }
  int open() {
#if defined(_WIN32)
    if (wide.empty()) return CRISP_AUDIO_INVALID_ARGUMENT;
    const int fd = _wopen(wide.c_str(), _O_CREAT | _O_EXCL | _O_WRONLY | _O_BINARY,
                         _S_IREAD | _S_IWRITE);
#else
    const int fd = ::open(path.c_str(), O_CREAT | O_EXCL | O_WRONLY, 0600);
#endif
    if (fd < 0) {
      return errno == EEXIST ? CRISP_AUDIO_OUTPUT_EXISTS : CRISP_AUDIO_IO_ERROR;
    }
    created = true;
#if defined(_WIN32)
    file = _fdopen(fd, "wb");
    if (file == nullptr) _close(fd);
#else
    file = fdopen(fd, "wb");
    if (file == nullptr) close(fd);
#endif
    return file != nullptr ? CRISP_AUDIO_OK : CRISP_AUDIO_IO_ERROR;
  }
  bool write(const void* data, size_t size) {
    return fwrite(data, 1, size, file) == size;
  }
  bool finish() {
    const bool flushed = fflush(file) == 0;
    const bool closed = fclose(file) == 0;
    file = nullptr;
    committed = flushed && closed;
    return committed;
  }
};

void little_u16(unsigned char* target, uint16_t value) {
  target[0] = static_cast<unsigned char>(value);
  target[1] = static_cast<unsigned char>(value >> 8);
}
void little_u32(unsigned char* target, uint32_t value) {
  for (int i = 0; i < 4; ++i) target[i] = static_cast<unsigned char>(value >> (8 * i));
}

bool write_header(Output& output, uint32_t channels, uint32_t sample_rate,
                  uint32_t data_size) {
  unsigned char header[44]{};
  memcpy(header, "RIFF", 4);
  little_u32(header + 4, data_size + 36);
  memcpy(header + 8, "WAVEfmt ", 8);
  little_u32(header + 16, 16);
  little_u16(header + 20, 1);  // WAVE_FORMAT_PCM
  little_u16(header + 22, static_cast<uint16_t>(channels));
  little_u32(header + 24, sample_rate);
  little_u32(header + 28, sample_rate * channels * 2);
  little_u16(header + 32, static_cast<uint16_t>(channels * 2));
  little_u16(header + 34, 16);
  memcpy(header + 36, "data", 4);
  little_u32(header + 40, data_size);
  return output.write(header, sizeof(header));
}

uint64_t nearest_frame(int64_t micros, uint32_t sample_rate) {
  const auto value = static_cast<uint64_t>(micros);
  return (value / 1000000) * sample_rate +
         ((value % 1000000) * sample_rate + 500000) / 1000000;
}

double fade_gain(uint64_t frame, uint64_t total, uint64_t fade_in,
                 uint64_t fade_out) {
  double gain = 1;
  if (frame < fade_in) {
    gain *= fade_in <= 1 ? 0 : static_cast<double>(frame) / (fade_in - 1);
  }
  if (fade_out != 0 && total - frame <= fade_out) {
    gain *= fade_out <= 1 ? 0
                        : static_cast<double>(total - frame - 1) / (fade_out - 1);
  }
  return gain;
}

int waveform_impl(crisp_audio_job* job, const char* path, float* peaks,
                  uint32_t count) {
  if (job == nullptr || path == nullptr || peaks == nullptr || count == 0 ||
      count > 32768) return CRISP_AUDIO_INVALID_ARGUMENT;
  std::fill(peaks, peaks + count, 0.0f);
  Decoder input(job);
  const int opened = input.open(path);
  if (opened != CRISP_AUDIO_OK) return opened;
  const uint32_t channels = input.decoder.outputChannels;
  if (ma_decoder_seek_to_pcm_frame(&input.decoder, 0) != MA_SUCCESS) {
    return cancelled(job) ? CRISP_AUDIO_CANCELLED : CRISP_AUDIO_INVALID_INPUT;
  }
  std::vector<float> buffer(kChunkFrames * channels);
  uint64_t position = 0;
  while (position < input.frames) {
    if (cancelled(job)) return CRISP_AUDIO_CANCELLED;
    const auto wanted = std::min<uint64_t>(kChunkFrames, input.frames - position);
    ma_uint64 read = 0;
    const auto result = ma_decoder_read_pcm_frames(&input.decoder, buffer.data(),
                                                   wanted, &read);
    if (cancelled(job)) return CRISP_AUDIO_CANCELLED;
    if ((result != MA_SUCCESS && result != MA_AT_END) || read == 0) {
      return CRISP_AUDIO_INVALID_INPUT;
    }
    for (uint64_t frame = 0; frame < read; ++frame) {
      const auto bin = static_cast<uint32_t>((position + frame) * count /
                                             input.frames);
      for (uint32_t channel = 0; channel < channels; ++channel) {
        const float sample = buffer[frame * channels + channel];
        if (std::isfinite(sample)) {
          peaks[bin] = std::max(peaks[bin], std::min(1.0f, std::fabs(sample)));
        }
      }
    }
    position += read;
    progress(job, position, input.frames);
  }
  return CRISP_AUDIO_OK;
}

int render_impl(crisp_audio_job* job, const char* input_path,
                const char* output_path, int64_t start_us, int64_t end_us,
                double gain_db, int64_t fade_in_us, int64_t fade_out_us,
                int32_t muted) {
  if (job == nullptr || input_path == nullptr || output_path == nullptr ||
      start_us < 0 || end_us <= start_us ||
      end_us > static_cast<int64_t>(kMaximumSeconds * 1000000) ||
      !std::isfinite(gain_db) || gain_db < -60 || gain_db > 24 ||
      fade_in_us < 0 || fade_out_us < 0 ||
      fade_in_us > end_us - start_us || fade_out_us > end_us - start_us ||
      (muted != 0 && muted != 1)) return CRISP_AUDIO_INVALID_ARGUMENT;

  Decoder input(job);
  const int opened = input.open(input_path);
  if (opened != CRISP_AUDIO_OK) return opened;
  const uint32_t channels = input.decoder.outputChannels;
  const uint32_t sample_rate = input.decoder.outputSampleRate;
  const uint64_t start = nearest_frame(start_us, sample_rate);
  const uint64_t end = nearest_frame(end_us, sample_rate);
  if (end > input.frames || start >= end) return CRISP_AUDIO_INVALID_ARGUMENT;
  const uint64_t frames = end - start;
  const uint64_t byte_count = frames * channels * 2;
  // The output is ordinary RIFF/WAV, not RF64. Reject instead of wrapping a
  // 32-bit chunk size and producing an apparently successful corrupt file.
  if (byte_count > UINT32_MAX - 36) return CRISP_AUDIO_UNSUPPORTED;
  if (ma_decoder_seek_to_pcm_frame(&input.decoder, start) != MA_SUCCESS) {
    return cancelled(job) ? CRISP_AUDIO_CANCELLED : CRISP_AUDIO_INVALID_INPUT;
  }
  if (cancelled(job)) return CRISP_AUDIO_CANCELLED;
  Output output(output_path);
  const int output_opened = output.open();
  if (output_opened != CRISP_AUDIO_OK) return output_opened;
  if (!write_header(output, channels, sample_rate,
                    static_cast<uint32_t>(byte_count))) return CRISP_AUDIO_IO_ERROR;

  std::vector<float> buffer(kChunkFrames * channels);
  std::vector<unsigned char> encoded(kChunkFrames * channels * 2);
  const double gain = muted ? 0 : std::pow(10.0, gain_db / 20.0);
  const uint64_t fade_in = nearest_frame(fade_in_us, sample_rate);
  const uint64_t fade_out = nearest_frame(fade_out_us, sample_rate);
  uint64_t position = 0;
  while (position < frames) {
    if (cancelled(job)) return CRISP_AUDIO_CANCELLED;
    const auto wanted = std::min(kChunkFrames, frames - position);
    ma_uint64 read = 0;
    const auto result = ma_decoder_read_pcm_frames(&input.decoder, buffer.data(),
                                                   wanted, &read);
    if (cancelled(job)) return CRISP_AUDIO_CANCELLED;
    if ((result != MA_SUCCESS && result != MA_AT_END) || read == 0) {
      return CRISP_AUDIO_INVALID_INPUT;
    }
    for (uint64_t frame = 0; frame < read; ++frame) {
      const double amplitude = gain * fade_gain(position + frame, frames,
                                                 fade_in, fade_out);
      for (uint32_t channel = 0; channel < channels; ++channel) {
        const auto index = frame * channels + channel;
        const double sample = std::isfinite(buffer[index])
                                ? buffer[index] * amplitude : 0;
        const double bounded = std::max(-1.0, std::min(1.0, sample));
        const auto integer = static_cast<int32_t>(std::llround(bounded * 32768));
        const auto clipped = static_cast<int16_t>(std::max(-32768,
                                                          std::min(32767, integer)));
        little_u16(encoded.data() + index * 2, static_cast<uint16_t>(clipped));
      }
    }
    if (!output.write(encoded.data(), static_cast<size_t>(read * channels * 2))) {
      return CRISP_AUDIO_IO_ERROR;
    }
    position += read;
    progress(job, position, frames);
  }
  if (cancelled(job)) return CRISP_AUDIO_CANCELLED;
  if (!output.finish()) return CRISP_AUDIO_IO_ERROR;
  return CRISP_AUDIO_OK;
}
}  // namespace

int32_t crisp_audio_abi_version(void) { return 1; }

crisp_audio_job* crisp_audio_job_create(void) {
  return new (std::nothrow) crisp_audio_job;
}

void crisp_audio_job_cancel(crisp_audio_job* job) {
  if (job != nullptr) job->cancelled.store(true, std::memory_order_relaxed);
}

uint32_t crisp_audio_job_progress(crisp_audio_job* job) {
  return job == nullptr ? 0 : job->progress.load(std::memory_order_relaxed);
}

void crisp_audio_job_destroy(crisp_audio_job* job) { delete job; }

int32_t crisp_audio_probe(crisp_audio_job* job, const char* input_path,
                          crisp_audio_info* result) {
  if (job == nullptr || input_path == nullptr || result == nullptr) {
    return CRISP_AUDIO_INVALID_ARGUMENT;
  }
  *result = {};
  try {
    Decoder input(job);
    const int opened = input.open(input_path);
    if (opened != CRISP_AUDIO_OK) return opened;
    result->frames = input.frames;
    result->sample_rate = input.decoder.outputSampleRate;
    result->channels = input.decoder.outputChannels;
    job->progress.store(1000000, std::memory_order_relaxed);
    return CRISP_AUDIO_OK;
  } catch (const std::bad_alloc&) { return CRISP_AUDIO_OUT_OF_MEMORY; }
  catch (...) { return CRISP_AUDIO_INVALID_INPUT; }
}

int32_t crisp_audio_waveform(crisp_audio_job* job, const char* input_path,
                             float* peaks, uint32_t count) {
  try { return waveform_impl(job, input_path, peaks, count); }
  catch (const std::bad_alloc&) { return CRISP_AUDIO_OUT_OF_MEMORY; }
  catch (...) { return CRISP_AUDIO_INVALID_INPUT; }
}

int32_t crisp_audio_render(crisp_audio_job* job, const char* input_path,
                           const char* output_path, int64_t start_us,
                           int64_t end_us, double gain_db, int64_t fade_in_us,
                           int64_t fade_out_us, int32_t muted) {
  try {
    return render_impl(job, input_path, output_path, start_us, end_us, gain_db,
                        fade_in_us, fade_out_us, muted);
  } catch (const std::bad_alloc&) { return CRISP_AUDIO_OUT_OF_MEMORY; }
  catch (...) { return CRISP_AUDIO_INVALID_INPUT; }
}
