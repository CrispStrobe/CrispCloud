# Audio and video editing

The first media editor is a single-file, nondestructive workflow opened through
the existing **Edit / F4** dispatcher. It stages the original, stores small edit
recipes, and exports a separate copy into the originating folder. Undo and redo
change recipes; they never repeatedly decode or rewrite the original.

## Shipped capability boundary

| Platform | Audio editing/export | Video editing/export | Inline playback |
| --- | --- | --- | --- |
| iOS, macOS, Android | WAV / MP3 / FLAC → PCM16 WAV | MP4 / MOV / M4V → MP4, subject to OS codecs | Existing `video_player` |
| Windows, Linux | WAV / MP3 / FLAC → PCM16 WAV | Unavailable | Waveform and export; no inline playback in this milestone |
| Web | Unavailable | Unavailable | Existing viewer unchanged |

Filename routing is a hint. Decoders inspect actual contents and reject invalid
or unsupported streams. A container extension does not guarantee that its codec
is available on every device. Unsupported formats never fall through to the
text editor. Audio supports mono/stereo at 8–384 kHz and retains the sample rate;
multichannel layouts are deliberately rejected until layout preservation exists.

Audio controls: waveform, selected start/end, gain from −60 to +12 dB, linear
fade in/out, undo/redo, rendered audition where playback exists, WAV export.
Positive gain can clip to the PCM16 range. Overlapping fades multiply their
amplitudes. Exported WAV does not retain tags, artwork, cue points or source bit
depth. MP3/AAC encoding and sample-rate conversion are outside this milestone.

Video controls: selected start/end, movable square/landscape/portrait crops,
clockwise quarter-turns, maximum output height, mute, undo/redo, rendered preview
and MP4 export. Crop coordinates are normalized in the source display orientation
(after its container orientation), followed by user rotation and downscaling.
Resize never upscales. Hardware-compatible even dimensions may round down by one
pixel; larger unexpected encoder dimension changes fail validation. The first
workflow does not include text layers, transitions, multiple tracks or effects.

The editor shows a **Source preview** until the user requests **Preview edit**.
That action runs the actual export backend into a private temporary file and
then plays that file as **Edited preview**. The exact verified render is reused
for export if the recipe has not changed. The waveform remains a view of the
source selection. Preview generation never marks the project as exported.

## Dependencies and licensing

* `packages/pro_video_editor`: pinned **2.51.0**, BSD-3-Clause, native
  AVFoundation/Media3 renderer. Only Android/iOS/macOS plugins are registered;
  the unused Linux GStreamer metadata dependency is excluded. Provenance,
  archive digest, native notices and local changes are in its `UPSTREAM.md`.
* `packages/crisp_audio`: first-party FFI wrapper around pinned
  **miniaudio 0.11.26**, using the **MIT-0** license choice. The wrapper follows
  this repository's AGPL license; it does not change the app's license.
  Its `UPSTREAM.md` records the revision, checksums and compile-time feature
  exclusions. Only offline decoders are enabled. The wrapper writes PCM16 WAV.
* `video_player`: existing application dependency, used only for playback.
  Flutter owns this editor's accessible controls and all nine translations.

No FFmpeg, GStreamer, mpv, GPL codec or network media service is added to the app.
FFmpeg/ffprobe are used only as independent test tools. Native Apache/BSD/MIT
notices remain bundled. Apple privacy manifests cover file timestamp APIs used
on the staged files in the application's container. The video backend does not
request access to Photos. Android's minimum SDK is at least 24 for Media3.

## Host and engine contracts

`MediaEditSession` owns immutable revisions, history and the exported revision
identity. Export locks history while rendering and persistence run. A successful
save marks exactly the captured revision clean. A cancellation, invalid output,
preview, account change or failed write leaves edits dirty. Undo branches cannot
reuse the saved revision's identity.

`MediaEditorBackend` exposes `probe`, `waveform` and file-to-file `render`. Heavy
audio work runs in an isolate over the C ABI. Progress/cancellation use a native
atomic job handle whose memory is kept until the worker completes. Fixed-size
PCM buffers avoid allocating the entire decoded track. Video uses native task
progress and cancellation. Both backends reject overwriting a render target and
remove their own incomplete outputs on failure.

The host reopens each successful output and checks its type and duration before
persistence. The video adapter additionally checks dimensions and mute state.
The native audio writer checks every write, flush and close; its tests inspect
sample counts and amplitudes using independent readers. Export is not reported
as successful merely because a plugin returned a path or emitted 100% progress.

`MediaFileStore` captures the actual panel origin. Each editor gets a unique
private working directory, a fresh source snapshot, and fresh output paths. It
bypasses the preview cache. Failed persistence keeps the verified render for
retry; closing the editor waits for active work and removes its workspace.

Local file operations hold independent security scopes on Apple platforms.
Copies use exclusive filename creation and reject existing files and symlinks.
As with the existing document writer, another process can still replace a
reserved path after creation. The original is never a permitted export target.

### Cloud behavior and practical limits

Local input and output are limited to **2 GiB each**. Cloud transfers are limited
to **64 MiB each** and require a fresh known source size. Several current cloud
adapters advertise streaming but still buffer, so `supportsStreaming` is not used
as proof of bounded memory. Byte counts are checked during staging, although an
adapter that buffers an unexpectedly growing file may allocate before handing
bytes to this layer. True large-cloud-media support requires stronger adapter
contracts or remote jobs and is deliberately not advertised here.

Cloud exports check the captured account before/after operations, verify the
parent listing and original identity, reject an existing destination, and use a
collision-resistant suggested filename. The common provider interface has no
conditional-create method, so the check and upload are not atomic. If the account
changes while an upload is already in flight, a copy may have reached the old
account; the editor reports failure instead of claiming it saved to the new one.
Only the new copy's cache entry is invalidated, and the host refreshes the panel.

FTP uploads and downloads pass absolute remote paths and use private temporary
files, so file routing does not depend on the server's current directory and
independent sessions cannot share temporary bytes. The current `ftpconnect`
transport still uses one control socket without a command queue. Overlapping
operations on the same FTP connection remain unsupported; directory operations
also retain their existing current-directory behavior. This adapter change does
not provide connection-wide serialization.

## Verification

The dedicated `Media editor` PR workflow runs:

1. C++ build of the shipped audio code, independent Python PCM assertions and
   FFmpeg/ffprobe inspection of WAV, MP3 and FLAC cases, write failure and active
   cancellation, source immutability and retry.
2. Actual Dart isolate/FFI tests with `CRISP_AUDIO_LIBRARY`, session/storage
   contracts, all locale coverage, F4 routing and host lifecycle tests.
3. Chrome capability/routing checks so unavailable native backends remain
   unreachable and conditional FFI imports do not break the web application.
4. Packaged macOS and Android native exports with real codecs. Video tests use
   a synthetic clip with changing colored quadrants and audio, then check trim
   timing, crop/rotation, resize, mute, re-editing, cancellation and retry.
5. Independent host FFmpeg inspection of the retained macOS outputs, plus an
   unsigned iOS build. The general application CI continues its platform builds.

Native audio can be checked without Flutter:

```sh
python3 packages/crisp_audio/native_test/test_audio.py
```

The audio package README documents the separate shared-library build for Dart
tests. Run native packaged-app integration tests on a supported device:

```sh
flutter test integration_test/media_export_test.dart -d macos \
  --dart-define=MEDIA_TEST_KEEP_OUTPUT=true
```

Actual signed iPhone/iPad testing, multiple Android hardware encoders, large
files, HDR/color-metadata retention and distribution review still need release
validation. CI fixtures cover the implemented ordinary SDR/single-clip workflow;
they do not imply every device codec or media profile is supported.

## Next extensions

Keep `MediaEdit` as the document model when adding a richer timeline. Extend
capability checks and backend/output tests before exposing multitrack mixing,
text/effects, waveform caches, more codecs, web rendering or Windows/Linux video.
The existing vendored image editor remains independent; this first media host
uses explicit controls rather than coupling its history to image-only rendering
callbacks. A future shared visual editor can translate its result into the same
validated recipes and persistence contract.
