# Offline audio engine provenance

## Imported dependency

- Repository: <https://github.com/mackron/miniaudio>.
- Tag: **0.11.26**, released 31 October 2026.
- Immutable commit: `877ea4a7c2601c7b0f2a44e83dfac42e6470fea6`.
- Imported files: `miniaudio.h` and the upstream `LICENSE`, unchanged, under
  `src/third_party/miniaudio/`.
- `miniaudio.h` SHA-256:
  `6b376c7fbb1352ba1e0e432ab66069b335ea9405e45cb6c30b97ef0f3c9c3e0e`.
- Upstream `LICENSE` SHA-256:
  `457f1b500e0adf6bc059edddfa78a2f62012e7c3bb43476c20e0bd23b25ba0eb`.
- Upstream offers public domain or MIT No Attribution. CrispCloud selects
  **MIT-0** and retains the complete original notice. No LGPL/GPL media runtime
  or AAC/MP3 encoder is added by this package.

The rest of this package is first-party CrispCloud integration and follows the
application's existing AGPL-3.0 license (`LICENSE`). This does not relicense the
upstream miniaudio files or change CrispCloud's license.

`NOTICES` uses Flutter's documented multi-license format (80-hyphen separator
and one component name per line). Flutter automatically collects this file in
preference to the package `LICENSE`: the first-party integration appears as
`crisp_audio`, and the MIT-0 text embedded in the actual vendored header appears
for `miniaudio`, `dr_wav`, `dr_flac` and `dr_mp3` in the app's license screen.
The original upstream license file and header are retained unchanged as well.

## Build configuration and local code

`src/crisp_audio.cpp` defines `MA_NO_DEVICE_IO`, `MA_NO_RESOURCE_MANAGER`,
`MA_NO_NODE_GRAPH`, `MA_NO_ENGINE`, `MA_NO_THREADING`, `MA_NO_GENERATION`,
`MA_NO_ENCODING`, and `MA_NO_RUNTIME_LINKING`. This builds offline WAV/MP3/FLAC
decoders only; there is no microphone capture, audio device, network service,
FFmpeg process or downloadable executable in the product. miniaudio itself is
not patched. WAV encoding is a small first-party PCM16 writer with checked
writes, explicit little-endian fields, and exclusive destination creation.

The native wrapper adds streaming file callbacks, peak bins, sample-accurate
selection, gain, linear fades, mute, progress, and atomic cancellation. Each
operation uses at most 4096 decoded frames at a time. Cancellation reaches the
file callbacks while miniaudio scans MP3 length, as well as the render loop.

On Apple, the pod uses a static framework and an explicit retained FFI symbol
to survive release dead stripping. The privacy manifest includes the file
timestamp category with C617.1 because miniaudio's compiled default VFS contains
`fstat`, even though the editor uses custom callbacks. The editor supplies only
private, staged working files in the app's own container to this backend.
Device I/O and runtime library loading are disabled in miniaudio.

## Reproducing the import

```sh
git clone --depth 1 --branch 0.11.26 https://github.com/mackron/miniaudio.git
git -C miniaudio rev-parse HEAD
sha256sum miniaudio/miniaudio.h miniaudio/LICENSE
```

Compare the revision and checksums above before replacing the two imported
files. Run the native fixtures and the Flutter FFI contract on every upgrade.
