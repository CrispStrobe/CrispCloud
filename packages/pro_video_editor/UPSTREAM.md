# CrispCloud's pro_video_editor copy

## Provenance

- Upstream: <https://github.com/hm21/pro_video_editor>.
- Published package: **pro_video_editor 2.51.0**.
- Archive: <https://pub.dev/api/archives/pro_video_editor-2.51.0.tar.gz>.
- Archive SHA-256:
  `0fae0ac54fa279b3c3669affc2702b402238dc175c3dfd23be94afe99ee2e641`.
- Upstream tag: `v2.51.0`, commit
  `93fe48baaf67ef5ba74130bb3c1c63adc4d7f3e1`.
- License: BSD-3-Clause. The original `LICENSE` is retained verbatim.

The root application's exact dependency version and local path override resolve
this checked-in source. No build fetches a moving upstream branch or downloads
an opaque video-engine binary.

## Imported files

The verified pub archive supplies `lib/`, `shaders/`, `android/`, `darwin/`,
`test/`, `LICENSE`, `README.md`, `CHANGELOG.md`, `SECURITY.md`, `pubspec.yaml`,
and `analysis_options.yaml`. Runtime Dart code, native renderers, Android R8
consumer rules and upstream Dart/native tests are retained.

Examples and their media assets, showcase images, and the Windows/Linux native
metadata-only plugins are omitted. In particular, upstream's Linux metadata
implementation links GStreamer but cannot export edited video. CrispCloud
does not add that dependency merely to register an unsupported editor. The
web metadata-only registration is omitted too. Portable Dart library code is
retained so imports and capability checks compile across all app targets.

## Local changes

| File | Change |
| --- | --- |
| `pubspec.yaml` | Set `publish_to: none`; remove omitted screenshots; register only Android/iOS/macOS; bundle native dependency notices. |
| `assets/licenses/native.txt` | Preserve Apache-2.0 license text and attribution for the native Android dependencies. |
| `darwin/pro_video_editor/Resources/PrivacyInfo.xcprivacy` | Declare file timestamp/size metadata access inside the app container (`C617.1`). |
| `darwin/pro_video_editor.podspec`, `darwin/pro_video_editor/Package.swift` | Include the privacy manifest in CocoaPods and Swift Package builds. |
| `README.md`, `CHANGELOG.md` | Identify the maintained copy and its supported application scope. |

`UPSTREAM.patch` records modifications to imported files. New provenance and
license notice files are maintained separately. There are no local renderer
changes in this initial integration.

## Native dependencies and Apple packaging

Android uses AndroidX Media3 **1.11.1**, AndroidX ExifInterface **1.4.2**, and
Kotlin coroutines **1.7.3**, all Apache-2.0 licensed. Media3's common,
transformer, inspector-frame, effect and muxer artifacts are declared in
`android/build.gradle`. Android requires API 24 or newer and compile SDK 36.
CrispCloud retains the plugin's R8 rules for exports on older Android versions.
The application's startup registers `assets/licenses/native.txt` with Flutter's
license registry; Flutter collects the package's BSD license itself.

Apple builds use the operating system's AVFoundation/CoreImage/VideoToolbox
facilities. No FFmpeg, GStreamer, x264 or separately distributed codec binary is
included. The CocoaPods deployment targets are iOS 13 and macOS 10.15; the Swift
package declares iOS 13 and macOS 12. CrispCloud already targets iOS 15/macOS 12.

The native metadata reader obtains file size and falls back to a file creation
date when the media contains no creation date. CrispCloud passes **only its own
staged input snapshots and temporary output files** to this backend. The
manifest declares that actual use with Apple's container-metadata reason
`C617.1`. The manifest is included in both Apple package mechanisms rather than
relying on the host's declarations. If the integration later passes external
user-selected paths directly, revisit the reason against that new behavior.
See Apple's [required-reason API documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

The upstream Photos resolver remains in the package but this integration does
not call it: file snapshots, not `ph://` URLs, are passed to the editor. The iOS
application already declares its photo-library purpose for its existing import
workflow. This metadata/packaging review is not an App Store submission test.

## Application adapter and limits

`lib/services/media_video_backend.dart` in the application maps a single immutable
edit recipe to the native renderer. It uses file paths end to end. Crop
coordinates are fractions of the **display-oriented source**, before the
user's clockwise rotation. The transform order is crop, rotation, resize. On
Android the engine rotates first and maps the crop into that rotated space;
the resulting crop is equivalent. No source-container rotation is added twice.

Resize never enlarges the selected image. The adapter rounds output dimensions
down to even numbers for hardware codecs. Its output check tolerates two pixels
of native alignment, but rejects larger unexpected dimensions rather than
silently accepting an encoder fallback that changes the requested result.
Media3 can choose device-specific aligned/fallback dimensions; a device that
cannot encode this requested size can therefore report a recoverable export
failure. Test representative physical Android encoders in addition to CI.

Trim is applied to `VideoSegment` once. Apple exports request preservation of
the source frame timestamps for this one forward clip, including fractional
and variable frame rates. Video gain/fades are rejected by the shared edit
model until preview/export parity is implemented. Mute removes the audio track.
Exports are MP4, and supported input codecs remain those available on the
device. A filename alone does not prove codec support.

The adapter refuses an existing output path, subscribes to the render's unique
progress ID, propagates cancellation, waits for native completion before
cleaning a partial output, and reopens a completed output to check dimensions,
duration and mute before allowing persistence. Progress-stream failure alone
does not turn a successful render into an error; the render future and reopen
checks are authoritative.

## Reproduce and validate

Download and hash the published archive, copy the imported paths above, then
apply `UPSTREAM.patch` relative to this package. Preserve the BSD license, both
shaders, native sources, R8 rules, privacy manifest and native license asset.
The root lockfile records shipped dependency resolution.

With the application's pinned Flutter toolchain:

```sh
flutter pub get
flutter test test/media_video_backend_test.dart
flutter test integration_test/media_video_export_test.dart -d macos \
  --dart-define=MEDIA_TEST_KEEP_OUTPUT=true
```

The contract test checks native request semantics, unsupported targets, output
reopening, partial/missing/corrupt outputs, cancellation races, retry and source
protection. Its method-channel substitute is intentionally separate from the
native integration test.

The native integration test embeds a small synthetic H.264/AAC clip only in its
test executable. It changes the upper-left quadrant's color every second. The
test renders actual trim/crop/rotation/resize/mute edits, decodes exported frame
thumbnails to inspect their pixels, checks audio retention/removal, reopens and
edits an output, cancels and retries, and confirms the source bytes are unchanged.
Retained outputs are printed as `MEDIA_VIDEO_EXPORT` JSON path lines. The CI
host additionally runs `tool/check_media_video_exports.py` against that log to
inspect all streams and decode video/audio with an independent FFmpeg build.
FFmpeg is used for fixtures and validation only, never by the app.

The fixture's SHA-256 is
`47ee6f0553c7eb7dcdaf884066c139df702b0c8d91cff2a2f8b5f02392feed87`.
`test/support/media_video_fixture.dart` documents its dimensions, timing and
colors. The encoded clip was generated with FFmpeg 6.1.1: a 320×180, 20 fps,
four-second color source; four filled quadrant boxes; a green upper-left box
enabled from 1–2 seconds, yellow from 2–3, cyan from 3–4; and a 48 kHz, 440 Hz
sine track. Encoding used libx264 (`yuv420p`, CRF 18, `veryfast`, GOP 20), AAC
32 kbit/s, and MP4 `+faststart`. Test pixels allow codec/color-conversion error
while distinguishing the source positions and trim times.
