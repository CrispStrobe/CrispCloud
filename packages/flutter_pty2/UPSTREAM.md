# flutter_pty2: desktop integration

CrispCloud reuses the native PTY implementation from `flutter_pty2` **3.0.0**.
This directory contains the published package's runtime Dart, C and build-hook
sources, with a desktop platform allowlist and a Windows standard-handle fix
described below. CrispCloud supplies the terminal emulator, session ownership,
UI, and SSH transport separately.

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

## Local patches

### Desktop-only native assets

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

There is no substitute C stub and no new local-shell functionality on mobile.
The web path continues to use CrispCloud's conditional Dart stub.

This patch intentionally omits functionality CrispCloud does not use on mobile.
It does **not** claim that the upstream package necessarily fails to compile for
physical iOS devices. Upstream documents simulator verification separately from
physical-device runtime verification.

### Windows standard-handle isolation

`patches/0002-conpty-standard-handles.patch` sets `STARTF_USESTDHANDLES` in
`src/windows/pty_windows_spawn.c`. The zero-initialized standard handles remain
null so Windows assigns the child's input, output and error streams to ConPTY.
Without this flag, Windows can duplicate a parent's redirected standard handles
into a console child even when `bInheritHandles` is false. That sends shell output
to the parent runner's pipes instead of the PTY and leaves the terminal unable to
interact with the child. Microsoft's console maintainer describes this exact
case and correction in
<https://github.com/microsoft/terminal/discussions/15814>.

The failure was exposed by the Windows Flutter test runner, whose standard
streams are redirected. The terminal smoke test now uses the application's
actual emulator/session to answer terminal queries, captures raw PTY diagnostics,
and requires a rendered command-output line plus the expected exit code.
The native correction is separate from the emulator's normal DA1/CPR replies.

Only `hook/build.dart`, `lib/src/pty.dart`, and
`src/windows/pty_windows_spawn.c` differ from the reviewed runtime archive.
Every other C source remains byte-for-byte identical to that release.

## Reproduction and updates

To reconstruct this directory, download the archive, verify the SHA-256 above,
and copy its `lib/`, `hook/`, `src/`, `pubspec.yaml` and `LICENSE`. Apply both patches
from the resulting package directory:

```sh
patch -p1 < patches/0001-desktop-only.patch
patch -p1 < patches/0002-conpty-standard-handles.patch
```

Keep this provenance file, the supplementary Dart license, both patches, and the
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
- ConPTY with redirected parent standard streams:
  <https://github.com/microsoft/terminal/discussions/15814>
