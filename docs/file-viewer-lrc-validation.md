# File Viewer continuation validation

Date: 2026-11-13. Scope: the selected Apache LRC addition, existing binary
inspector regressions, and repair of the inherited maintained-hex provenance.
This supplements the [initial binary validation](file-viewer-apache-validation.md).

## Results

The final native command below completed with **268 tests passed, zero failures
and zero skips**: 47 binary inspector tests, **57 LRC tests**, and 164 existing
viewer regressions. The [complete transcript](evidence/file-viewer-lrc-20261113/native-tests.txt)
and [receipt](evidence/file-viewer-lrc-20261113/receipt.json) are retained with
the source. Runtime, test and dependency input hashes were unchanged throughout
the final run.

Focused analysis across 14 changed runtime/test paths completed with
**No issues found**; see the [analyzer output](evidence/file-viewer-lrc-20261113/analyzer.txt).
The pinned formatter checked all 26 added/modified Dart files across the entire
integration: **zero changes**. An earlier broader analyzer run including
`main.dart` reported only the existing deprecated `FlutterCryptography.enable()`
call. This integration adds license registration there and leaves that call
unchanged.

## Runtime and dependencies

Validation uses genuine Flutter 3.47.8 / Dart 3.13.7 on Linux, the full production
Pub graph and the normal native build hooks. The installed scratch toolchain
includes Rust/Cargo 1.100.0 and Clang 19.1.7 for the existing ebook/terminal hooks.
No hook or native implementation was replaced, disabled or stubbed for these
tests. No dependency was added.

`pubspec.lock` remains byte-identical, SHA-256:
`135a9ccb44a38b2b9c7dcb541540b52bf151e8f5af14bf6e13b95d9240ae18a5`.
The pubspec change adds only the explicitly bundled LRC Apache license asset.

## Native regression command

The focused CI gate uses the following command on Linux, Windows and macOS:

```sh
flutter test --no-pub --reporter expanded --concurrency=2 \
  test/binary_structure_service_test.dart \
  test/binary_structure_source_test.dart \
  test/file_viewer_binary_license_test.dart \
  test/widget/binary_structure_viewer_test.dart \
  test/lrc_parser_test.dart \
  test/lrc_source_test.dart \
  test/file_viewer_lrc_license_test.dart \
  test/lrc_viewer_routing_test.dart \
  test/widget/lrc_viewer_test.dart \
  test/internal_viewer_test.dart \
  test/hex_viewer_test.dart \
  test/widget/internal_viewer_widget_test.dart
```

The LRC suites cover repeated timestamps, offsets placed after earlier cues,
word-time shifts, stable equal-time sorting, malformed marker preservation,
literal markup, immutable models and bounded expansion. Source tests cover the
exact 4 MiB boundary, a late offset beyond the first 256 KiB read window,
UTF-16 LE/BE and legacy encoding overrides, short reads, source resizing, stale
ownership and real file changes before or after a read.

Widget coverage exercises automatic F3 routing, archive display names, BOM
handling, metadata and word timing, source-order/chronological views, search
handoff, exact decoded CRLF clipboard output, original Hex bytes, limit fallback,
bounded individual text layouts and all nine supported locales. At 320 × 480
with 2.5× text scaling, Source remains reachable. Timestamps explicitly retain
left-to-right direction under Arabic localization.

One initial test incorrectly expected carriage returns in displayed text rows.
The existing viewer intentionally hides those trailing display characters. The
test was corrected to check the display contract, with a separate clipboard
assertion proving that the original decoded CRLF text remains intact. No runtime
behavior was changed to satisfy that test.

## Source provenance and portability

```sh
python3 tool/verify_file_viewer_binary.py
python3 tool/verify_file_viewer_lrc.py
python3 -m unittest discover -s tool -p 'test_verify_file_viewer*.py'
python3 tool/verify_hex_vendor.py

dart run tool/binary_structure_portability_smoke.dart
dart run tool/lrc_portability_smoke.dart
dart compile js tool/binary_structure_portability_smoke.dart -O2 -o /tmp/binary-smoke.js
node /tmp/binary-smoke.js
dart compile js tool/lrc_portability_smoke.dart -O2 -o /tmp/lrc-smoke.js
node /tmp/lrc-smoke.js
```

Both selected-source guards and all **41 provenance/tamper tests** pass: 21
binary and 20 LRC tests. The hex-fork verifier now passes with the exact existing
source pinned to a real maintained-fork commit. All **25 standalone hex package
tests** passed before the maintained source was saved remotely.

Both parser smoke scripts pass under the Dart VM and genuine optimized Dart2js
compilation followed by Node. The LRC check includes the exact large clock
`18999999999997`, signed offsets, repeated word shifts, stable ties, malformed
text and explicit limit fallback. JavaScript parser portability does not imply
completed browser UI or mobile/device qualification.

## CI status and practical limits

The earlier
[File workspace run 43371831609](https://github.com/CrispStrobe/CrispCloud/actions/runs/43371831609)
passed after the binary inspector formatting correction. Image, PDF, ebook and
provider checks also passed at that earlier checkpoint.

After the hex provenance repair, the fingerprint step passed on Linux, Windows
and macOS in
[Text/Hex run 43374770853](https://github.com/CrispStrobe/CrispCloud/actions/runs/43374770853).
The standalone package tests passed on all three platforms and Linux's existing
native application editor regressions passed. That run was cancelled by the
next incremental push before the remaining work completed; it is not claimed as
a fully successful workflow.

Two inherited failures were investigated at the earlier `aef2afa` checkpoint:

- [Office run 43371831432](https://github.com/CrispStrobe/CrispCloud/actions/runs/43371831432),
  job `131709229926`, failed source verification before Office tests. Six
  canonical parser evidence `.log` files were missing from the merged app tree,
  although the then-pinned upstream parser `cd9ab85` contains them. They were
  also absent from the main commit used by that run (`0893bb9`), and the PR
  comparison introduced no parser, manifest or Office-verifier changes. The
  root `*.log` ignore is a plausible cause; restoring the exact pinned logs
  belongs to that Office roll.
- [Main CI run 43371831415](https://github.com/CrispStrobe/CrispCloud/actions/runs/43371831415)
  reported the same missing parser evidence in Linux job `131710229126` and a
  stale Apple export review declaration in job `131710229142`. The declaration
  must reflect the actual reviewed crypto source; this integration does not
  change crypto policy or refresh that declaration to bypass the gate.

The Text/Hex workflow now independently runs the selected-source guards,
portability checks and the 12-suite native viewer command above. Existing
workflow steps, including its browser editor tests, remain in place. This makes
the feature's remote gate independent of the unrelated Office verification
failure. Full repository CI and device/release acceptance remain separate from
the focused results recorded here. The PR remains in draft.
