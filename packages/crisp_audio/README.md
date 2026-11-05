# CrispCloud offline audio editing

This local Flutter FFI plugin provides a small offline editing backend. The
application owns the editing UI, immutable history, input staging, account
identity, export validation and persistence. The backend never saves over the
source and never chooses an external destination.

## Supported first workflow

| Operation | Behavior |
| --- | --- |
| Import | WAV, FLAC and MP3 decoded by pinned miniaudio 0.11.26 |
| Channels/rate | Mono or stereo, original sample rate retained, 8–384 kHz |
| Waveform | Maximum absolute amplitude across channels in each requested bin |
| Selection | Start/end rounded to the nearest source sample; end is exclusive |
| Gain | Constant gain in dB; clipped to PCM16 range at export |
| Fades | Linear amplitude ramps at selected-region boundaries; overlapping ramps multiply |
| Mute | Exported samples are zero |
| Export | New PCM16 little-endian WAV; existing paths are rejected |
| Platforms | iOS, macOS, Android API 24+, Windows, Linux; web has an explicit unsupported stub |

The backend caps inspected inputs at 24 hours and exports at the ordinary
RIFF/WAV 32-bit chunk size. The host can impose smaller practical file limits.
Multichannel inputs are rejected until speaker-layout preservation is part of
the contract. WAV metadata, tags, cue points and cover art are not copied.
There is no resampling, recording, realtime playback, MP3/AAC encoding,
multitrack mixing, or time stretching in this milestone. Playback remains the
host's responsibility; successful export does not require an audio device.

The public API is `CrispAudio.probe`, `waveform`, and `render`. The application
adapter is `lib/services/media_audio_backend.dart`. Decoder/render work runs in
Dart isolates; a thread-safe native job handle exposes progress and cancellation.
The handle is destroyed only after the worker, poll timer and listener finish.
Rendering uses fixed-size buffers, checks every output write/flush/close, and
removes its own partial file on cancellation, truncated input or write error.

## Verification

From the repository root, with a C++17 compiler and Python 3:

```sh
python3 packages/crisp_audio/native_test/test_audio.py
```

Install FFmpeg/ffprobe to enable the independent MP3/FLAC generation and output
inspection case. Python's `wave` and `struct` readers verify actual sample
counts, selected samples, channel preservation, gain and fade amplitudes.
Fixtures also check Unicode paths, existing-output protection, malformed input,
short reads, write failure, active cancellation, cleanup, and retry.

For the Dart FFI/isolate contract on Linux:

```sh
mkdir -p build/media-tests
g++ -std=c++17 -O2 -fPIC -fvisibility=hidden -D_FILE_OFFSET_BITS=64 \
  -shared packages/crisp_audio/src/crisp_audio.cpp \
  -o build/media-tests/libcrisp_audio.so -lm
CRISP_AUDIO_LIBRARY="$PWD/build/media-tests/libcrisp_audio.so" \
  flutter test test/media_audio_backend_test.dart
```

On macOS use `clang++ -dynamiclib` instead of `g++ -shared` and a `.dylib`
filename. `src/CMakeLists.txt` builds the same implementation for platform
plugins, including an explicit 16 KiB page alignment for Android. The Apple
podspec retains its FFI symbols in static release links; packaged-app CI must
also test loading the plugin through `DynamicLibrary.process()`.

See [UPSTREAM.md](UPSTREAM.md) for source pin, license choice, checksums and
Apple privacy manifest rationale. FFmpeg is used only by tests.
