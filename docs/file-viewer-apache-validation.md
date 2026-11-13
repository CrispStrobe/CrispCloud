# File Viewer Apache subset: implementation validation

Date: 2026-11-13. Branch: `feature/apache-file-viewer-20261113`.
Review: [PR #95](https://github.com/CrispStrobe/CrispCloud/pull/95).

The integration adds **F3 → Hex → Inspect structure**. It uses the current
viewer byte source, parses at most 64 KiB, and returns an exact field range to
the existing Hex view. The [assessment](file-viewer-apache-integration.md) defines
the functionality, exclusions and upstream Apache source boundary. This record
describes measured checks; it is not a claim of full application or device
qualification.

## Results

| Check | Result | Scope |
| --- | --- | --- |
| Production application focused native suite | **211 passed; zero failures/skips** | All 47 new tests plus existing Hex and internal-viewer unit/widget regressions; seven suites below |
| Focused Dart analyzer | **No issues found** | New parser/source/license/UI files, host viewer and new tests |
| Source provenance guard | **Passed** | Three approved upstream files, hashes, license/attribution and pure-Dart import boundary |
| Provenance adversarial tests | **21 passed** | Source/manifest tampering, unexpected files, symlinks/traversal, changed license/notices and hidden dependencies |
| Genuine Dart VM / Dart2js + Node portability check | **Passed** | Exact unsigned 64-bit values, both ELF byte orders, nonzero typed-data offsets, truncated prefixes and hostile PE offsets |
| Small-display / enlarged-text UI | **Passed** | 320 × 480 display, 2.5× text scaling and reachable Close action; included in the final 211-test run |
| GitHub workspace regression test step | **937 passed** | Existing workspace CI on checkpoint `de22048`; its final formatting check failed and was corrected subsequently |

The production test run uses the real application dependency graph and default
native build hooks. The original focused parser harness was useful before the
full graph resolved, but it is superseded for native coverage by the complete
211-test application run. The independent JavaScript check remains a parser
portability check, not a full browser application test.

Evidence is retained in
[native-tests.txt](evidence/file-viewer-apache-20261113/native-tests.txt) and
[analyzer.txt](evidence/file-viewer-apache-20261113/analyzer.txt).
The [receipt](evidence/file-viewer-apache-20261113/receipt.json) records their
checksums and the final source identities. The successful test run was followed
only by formatter changes to the host's two new highlight expressions; no
runtime logic changed after that run.

## Reproduce the focused application run

Use the Flutter SDK pinned in `.fvmrc`, and the native prerequisites already
required by the repository's ebook and terminal packages. Resolve the committed
dependencies without changing the lockfile:

```sh
flutter pub get --enforce-lockfile
flutter test --no-pub --concurrency=2 --reporter expanded \
  test/binary_structure_service_test.dart \
  test/binary_structure_source_test.dart \
  test/file_viewer_binary_license_test.dart \
  test/widget/binary_structure_viewer_test.dart \
  test/hex_viewer_test.dart \
  test/internal_viewer_test.dart \
  test/widget/internal_viewer_widget_test.dart
```

The new tests check supported headers and endianness; malformed/ambiguous input;
range bounds and uint64 precision; one bounded prefix read even for a multi-GB
source; changes before/during reads; short/closed sources; the real dialog-to-Hex
selection; preserved selection on cancel; unknown and truncated input;
localization of controls/issues; packaged Apache license presentation; and the
small-screen layout. Existing regression suites exercise search/reload, mode
routing, real archive fixtures and streamed text navigation.

Analyze the changed production surface and its tests with:

```sh
dart analyze \
  lib/services/binary_structure_service.dart \
  lib/services/binary_structure_source.dart \
  lib/services/file_viewer_binary_license.dart \
  lib/l10n/binary_structure_strings.dart \
  lib/widgets/binary_structure_dialog.dart \
  lib/widgets/internal_viewer_dialog.dart \
  test/binary_structure_service_test.dart \
  test/binary_structure_source_test.dart \
  test/file_viewer_binary_license_test.dart \
  test/widget/binary_structure_viewer_test.dart
```

The immutable source boundary checks need only Python's standard library:

```sh
python3 tool/verify_file_viewer_binary.py
python3 -m unittest discover -s tool -p test_verify_file_viewer_binary.py -v
```

The reproducible JavaScript check uses the actual production parser and explicit
failure checks, which remain active with optimized compilation:

```sh
dart compile js tool/binary_structure_portability_smoke.dart -O2 -o /tmp/binary-structure-smoke.js
node /tmp/binary-structure-smoke.js
```

Use any writable output directory if `/tmp` is unavailable. CI runs this check
using its own temporary directory. The original scratch runner also passed on
the Dart VM before compilation; the committed runner differs only in its
repository-relative import and formatting.

## Environment and dependency integrity

| Tool | Version / source |
| --- | --- |
| Flutter | 3.47.8; official tag commit `737ba8f885dc774b53b442759999a312c9461e4e` |
| Dart | 3.13.7; SDK from engine `cf636b1dfb818dd6a3ff16e390e93b1a036969c8` |
| Rust / Cargo | 1.100.0; official Rustup installation |
| C compiler | Debian Clang/LLVM 19.1.7; downloaded package checksums verified |
| Native test target | Linux, with actual application native-asset hooks |

The SDK, Rust and Clang were installed into the temporary workspace. No system
installation, application dependency, pin or native hook was changed to make
tests pass. An early browser-test attempt stopped at the missing Cargo hook
before running tests; the final successful application run is native Linux.

Both `flutter pub get --enforce-lockfile` and an offline repeat succeeded.
Resolution contained 272 dependencies plus the application. `pubspec.lock`
remains byte-identical to the baseline, SHA-256:

```text
135a9ccb44a38b2b9c7dcb541540b52bf151e8f5af14bf6e13b95d9240ae18a5
```

## GitHub CI status and existing blocker

The [workspace run at de22048](https://github.com/CrispStrobe/CrispCloud/actions/runs/43370427552)
passed analysis and all 937 regression tests, then failed `Require committed
formatting` because the formatter rewrote two new highlight expressions. The
repository's pinned formatter was applied to those expressions; the final
format check is clean. The latest commit triggers the normal CI rerun.

The [Text and hex editor run](https://github.com/CrispStrobe/CrispCloud/actions/runs/43370427703)
stopped on Linux, macOS and Windows at `Verify maintained fork source
fingerprints`, before its Dart tests. It reports:

```text
Changed since pinned fork: lib/hex_editor.dart
Changed since pinned fork: test/hex_ui_regression_test.dart
```

This is an existing vendored-fork provenance mismatch at the starting commit
`794bde82693e07a6e04ed1490bfa228f154e6e5c`:

| File under `packages/madedit2_hex/` | Recorded Git blob | Actual Git blob already at baseline |
| --- | --- | --- |
| `lib/hex_editor.dart` | `49af1fe0dd5e6961bf8f4d6f815d190c9256897d` | `9409dde9fa9799887355fdef59a411895c8c3349` |
| `test/hex_ui_regression_test.dart` | `fcedf34dd5eb0c527a04a28d164544ceb6f35b75` | `7e5991271dc4e1dead15b41ce4e376e86d535eae` |

Both files, `FORK.json` and `tool/verify_hex_vendor.py` are byte-identical on this
integration branch and at the baseline. The recorded fork pin is
`50d033cc70d9121819c890fe587f8b3dc4c82311`. Repair needs a separate review of the
existing vendored changes and a coordinated fork/provenance update; this branch
does not disable the gate or bless the mismatch by changing hashes alone.

PR #95 remains a draft. Full CI, release builds and physical-device acceptance
are not claimed complete. The current check list on the PR is authoritative for
later runs; the historical outcomes above retain their exact source/run scope.

## Remote checkpoints

| Commit | Saved result |
| --- | --- |
| `fd7a192` | Licensing assessment and immutable Apache source snapshot |
| `801eda2` | Bounded Dart header parser and focused parser tests |
| `9cda02f` | Hex integration, localized controls, license distribution, source guard and tests |
| `de22048` | Small-screen/enlarged-text correction and regression |

The following validation commit preserves this record, receipts, the portable
JavaScript check, explicit mounted guards and the required formatting correction.
All checkpoints are on the remote review branch; none merges or releases the
integration.
