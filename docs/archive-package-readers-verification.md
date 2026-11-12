# Package-reader continuation: verification

Date: 2026-11-12. Implementation checkpoint:
[`5b0ea09c`](https://github.com/CrispStrobe/CrispCloud/commit/5b0ea09c30d27de93dfc155c8b52e51a67a439ca),
extending writer baseline `84c3a117`. The work is preserved on
`feature/archive-package-readers-20261112` in
[draft PR #90](https://github.com/CrispStrobe/CrispCloud/pull/90), stacked on #89.

## Observed results

| Check | Result |
| --- | --- |
| Combined archive/viewer regression run | **1,257 tests passed across 50 files**, exit 0 |
| Static analysis | **All 19 changed Dart files clean**, `--fatal-infos`, exit 0 |
| Container-viewer widget suite | **13 passed**, including four new CAB/RPM/nested Apple-package cases; included in the combined run |
| Sparse large PBZX source | **2 passed**; later small-file read skips a 65 MiB + 333 byte member; >2 GiB decoded framing rejected before payload reads; included in the combined run |
| CAB native/reference readback | **Passed** for independent MakeCAB stored/MSZIP and a dictionary-dependent zlib fixture, using libarchive 3.7.4 |
| PBZX independent decoder | **Passed** for mixed XZ/stored chunks and XZ `CHECK_NONE`, with exact original CPIO bytes |
| RPM independent fixtures | **Passed** for unchanged native rpmbuild gzip/bzip2 fixtures, including MD5, metadata and file content |
| Portable CPIO reference | **Passed** for an original native libarchive odc fixture with unaligned record boundaries |
| Standard release web build | **Passed**, exit 0, `Built build/web` |

Focused results overlap the combined run and must not be added to its total.
The CAB-focused 63-test suite also passed under `TZ=America/New_York`, including
a valid CAB wall-clock timestamp in the host's daylight-saving gap. Independent
review covered MSZIP history and termination, metadata and allocation bounds,
source ownership, concurrent caches, close races and read-only endpoint policy.

## Reproducing the regression scope

Use the repository pin, Flutter **3.47.8** / Dart **3.13.7**, and the locked
dependencies. From the repository root:

```sh
flutter pub get --enforce-lockfile
flutter test --no-pub --concurrency=4 --reporter expanded \
  test/archive_*_test.dart \
  test/widget/archive_*_test.dart \
  test/internal_viewer_test.dart \
  test/panel_source_test.dart \
  test/viewer_search_service_test.dart \
  test/viewer_streaming_service_test.dart \
  test/viewer_spool_lifecycle_test.dart \
  test/widget/internal_viewer_widget_test.dart \
  test/widget/internal_viewer_localization_test.dart
```

This covers reader/writer compatibility, compression integrity, creation,
workspaces, reviewed publication and recovery, import guards, disk-image paths,
extraction, shared recognition, source lifetimes and viewer/localization behavior.
The new integration tests check actual-signature dispatch under misleading
filenames, wrappers with opaque inner names, safe-subset extraction, immutable
package workspaces and extensionless payload preview routing.

The large PBZX fixture retains less than 1 KiB of headers and text while exposing
a valid sparse source larger than 65 MiB. It fails on any underlying request
larger than 16 MiB and asserts that none of the three intervening payload chunks
is touched. This demonstrates bounded positional browsing; it is not a claim
that a >64 MiB member can be previewed or extracted.

The new widget checks use actual taps for CAB member previews, RPM payload
preview, container details, and
`installer.pkg` → `Payload` → PBZX/odc tree → `docs/hello.txt` → text.

Static analysis uses the 19 `.dart` paths changed from `84c3a117` through the
implementation checkpoint, including production code, fixture helpers and
tests. `git diff --check` also passes.

## Reference tools and provenance

```sh
python3 test/support/check_archive_cab.py
python3 test/support/generate_pbzx_reference.py PATH_TO_PINNED_BIOSUTILITIES --check-only
```

The PBZX checkout is pinned to
`f799425af93264b62a2f3c3cc5bbabf8a2226114`. The checker runs the unchanged
BSD-2-Clause-Patent decoder and captures its CPIO before the optional 7-Zip
handoff. Both fixtures match the independently generated 381-byte CPIO exactly.
The original fixture contains only repository test text, not Apple software.

See the complete reproduction commands, hashes, source revisions and licenses:

- [CAB reference fixtures](../test/fixtures/archives/CAB_READERS.md).
- [RPM reference fixtures](../test/fixtures/archives/RPM_REFERENCE.md).
- [Portable CPIO fixture](../test/fixtures/archives/CPIO_ODC.md).
- [PBZX reference fixtures](../test/fixtures/archives/PBZX_REFERENCE.md).

Native tools and external reference sources are test tooling only. No app
runtime dependency, subprocess packer, installer or package execution path was
added. The original writer creation choices retain their existing tests.

## Validation environment and remaining acceptance

Local dependency resolution used the available offline cache and
`--enforce-lockfile`. The local validation wrapper temporarily disabled only
the optional native ebook conversion engine through its documented hook and
selected the system SQLite 3.46.1 library. It serialized validation commands and
restored `pubspec.yaml` byte-for-byte after each run. Neither configuration nor
dependency changes are part of this continuation.

The standard web command is:

```sh
flutter build web --release --no-pub --no-wasm-dry-run
```

The initial build reached asset bundling but ran out of local disk space.
Removing reproducible test caches freed 224 MiB; the same command then
completed successfully using its compiled output cache. This required no
source or dependency change. The optional WebAssembly dry run was disabled;
this result establishes the standard JavaScript release build only.

Native Windows/macOS/mobile release acceptance, package signature trust and
installer acceptance are separate from these Linux reference and Flutter
checks. CAB Quantum/LZX/spanning, RPM v6/stripped CPIO, Apple Archive/YAA and
new package writers remain outside this increment. The
[format matrix](archive-format-coverage.md) records exact reader, memory,
checksum and nested-preview boundaries. GitHub Actions status is tracked on the
PR and is separate from the local results above.
