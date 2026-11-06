# flutter_pty2: desktop-only integration

CrispCloud reuses the native PTY implementation from `flutter_pty2` **3.0.0**.
This directory contains the published package's runtime Dart, C and build-hook
sources. Desktop transport behavior is unchanged. CrispCloud supplies the
terminal emulator, session ownership, UI, and SSH transport separately.

## Provenance and license

- Package: <https://pub.dev/packages/flutter_pty2/versions/3.0.0>
- Source: <https://github.com/SoFluffyOS/flutter_pty2>
- Release archive: <https://pub.dev/api/archives/flutter_pty2-3.0.0.tar.gz>
- Published: 2026-10-21; reviewed for this integration: 2026-11-06.
- Archive SHA-256:
  `9802f793109fe7241cc172780571d501e50db6b247624a6b7c4df889bb9cbfe6`
- Runtime retained from the archive: `lib/`, `hook/`, `src/`, `pubspec.yaml`,
  and `LICENSE`. Upstream examples, benchmarks, tests and CI are not vendored.
- Main license: MIT, copyright 2022 xuty; see `LICENSE`.
- Bundled Dart SDK API headers and C shim in `src/include/`: BSD 3-Clause;
  see `DART_SDK_LICENSE.txt`. Their upstream copyright headers are preserved.

## Why this local patch exists

CrispCloud exposes local shells on Linux, macOS and Windows, and uses SSH on
Android and iOS. Upstream's build hook also compiles a local subprocess library
for mobile platforms. A Dart UI guard alone does not prevent that native asset
from being built and bundled.

The small patch in `patches/0001-desktop-only.patch` applies the same desktop
allowlist at two boundaries:

1. `hook/build.dart` emits no native asset for mobile targets and invokes no
   native compiler for those targets.
2. `Pty.spawn` returns `PtyUnsupportedException` on other platforms before
   initializing any FFI bindings.

All C sources and desktop PTY behavior remain identical to the published
archive. There is no substitute C stub and no new local-shell functionality on
mobile. The web path continues to use CrispCloud's conditional Dart stub.

This patch intentionally omits functionality CrispCloud does not use on mobile.
It does **not** claim that the upstream package necessarily fails to compile for
physical iOS devices. Upstream documents simulator verification separately from
physical-device runtime verification.

## Reproduction and updates

To reconstruct this directory, download the archive, verify the SHA-256 above,
and copy its `lib/`, `hook/`, `src/`, `pubspec.yaml` and `LICENSE`. Apply the patch
from the resulting package directory:

```sh
patch -p1 < patches/0001-desktop-only.patch
```

Keep this provenance file, the supplementary Dart license, patch, and the
local `tool/verify_mobile_assets.dart` regression when updating the archive.
Keep the application's dependency and override pinned to the reviewed release;
review source and licensing again before changing that version.

Run the focused checks from the application root after `flutter pub get`:

```sh
flutter test test/terminal_process_test.dart \
  test/terminal_native_assets_test.dart
```

Linux native-asset auto-discovery currently requires clang. Desktop builds also
need their normal C toolchain (Xcode on macOS; Visual Studio C++ on Windows).
The mobile hook regression runs the actual hook with validated iOS device and
Android arm64 configurations and asserts that no assets are emitted. It needs
neither Xcode nor an NDK.

For this integration, the desktop wrapper's Linux tests passed using the actual
native build hook: TTY allocation, ANSI output, initial/dynamic size, output
drain, UTF-8, Ctrl+C, and early/idempotent cleanup. A separate host simulation
omitted the asset and applied the matching platform guard: both Dart JIT and
AOT compiled and ran successfully, and the AOT bundle contained no PTY library.
That simulation validates the absent-asset path; it is not a physical-device
build or a macOS/Windows runtime test.

## Reference documentation

- Dart hooks and native asset bundling: <https://dart.dev/tools/hooks>
- Dart 3.13 native library tree shaking:
  <https://dart.dev/blog/announcing-dart-3-13>
