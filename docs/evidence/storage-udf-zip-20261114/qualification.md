# UDF and ZIP recovery qualification

The final qualified runtime is `20798b39a0c792e533a5c785294417f26db03272`.
The broad regression gate qualified `b07b7b738a261cc79bffe5f47c3881e2412da2cd`;
a targeted follow-up qualified the two subsequent implementation changes:
aggregate retained-path accounting in the UDF reader and display of a queued
ZIP publication warning after a successful save. The production JavaScript
release below is stamped with the final runtime revision.

## Results and source identity

| Gate | Result | Evidence |
| --- | --- | --- |
| Broad native service, queue and widget regression gate | 526 passed, zero failed or skipped, across 20 files | [Summary](udf-zip-final-gate-summary.json), [receipt](udf-zip-final-gate-receipt.json), [source binding](native-gate-source-binding.json) |
| Final UDF and ZIP warning follow-up | 96 passed, zero failed or skipped, across four files | [Summary](udf-zip-hardening-gate-summary.json), [receipt](udf-zip-hardening-gate-receipt.json), [source binding](hardening-gate-source-binding.json) |
| Final strict scoped analysis | All 38 changed Dart files passed with no errors, warnings or infos | [Receipt](udf-zip-hardening-analysis-receipt.json), [log](udf-zip-hardening-analysis.log) |
| Final UDF portable acceptance, Dart VM and actual compiled JavaScript | 26 groups and 500 checks on each runtime; JSON results identical | [Receipt](udf-path-budget-portable-receipt.json) |
| ZIP portable acceptance, Dart VM and actual compiled JavaScript | 15 groups and 131 checks on each runtime; JSON results identical | [Receipt](portable-validation-receipt.json) |
| Independent UDF extraction | Three images extracted by 7-Zip 26.06 with exit code zero; all 12 file payload hashes matched | [Oracle report](udf-sevenzip-oracle.json) |
| Independent UDF fixture integrity | 93 descriptor checksum, CRC and location checks across three images | [Oracle report](udf-python-fixture-oracle.json) |
| Independent recovered ZIP readback | Python `zipfile` accepted eight actual recovery outputs; all 14 member payload hashes and CRCs matched | [Oracle report](zip-python-candidate-oracle.json) |
| Fixture regeneration | Both generators reproduced their committed fixture data and manifests byte-for-byte | [Receipt](fixture-reproduction-receipt.json) |
| Production JavaScript release | Passed with original production manifest, version 1.2.9+22 and exact `20798b39` stamp | [Receipt](udf-zip-web-release-receipt.json), [log](udf-zip-web-release.log) |

The counts overlap and must not be added. In particular, the native review tests
invoke the portable acceptance programs. The 96-test follow-up includes 62 UDF
core tests, eight UDF review tests, 15 dispatch/integration tests and all 11 ZIP
recovery dialog tests. The earlier 526-test gate includes the complete existing
archive-container viewer file, both new native F3 UDF cases, queue and restart
recovery tests, ISO and DMG readers, DMG writer guards, format routing and menu
layout tests.

The [transition receipt](runtime-qualification-transition.json) verifies that
only two implementation files and three test/driver files changed between the
broad gate and the final runtime. Dependency manifests and all other Dart files
were unchanged. The earlier receipts retain their original source hashes;
the final UDF portable run has its own receipt instead of replacing that history.
The unchanged ZIP service, driver and fixture hashes continue to bind its earlier
portable and independent readback results to the final runtime. The final
[source verification](final-source-verification.json) compares the scoped
implementation, test and manifest files against the qualified commit and both
checkouts after the release build.

## Native profile and toolchain

Qualification used Flutter 3.47.8 with Dart 3.13.7, Node v24.22.1 and the locked
application dependency graph. Python fixture generation and independent checks
used Python 3.12.14 and zlib 1.3.2. The existing
[runtime environment record](../storage-runtime-20261114/native-runtime-environment.json)
and the individual portable receipts identify the tools and paths.

Native Flutter tests ran in a separate validation checkout. This host does not
have Cargo, so the
[native profile helper](../storage-runtime-20261114/native-validation-profile.py)
temporarily appended only the following optional ebook conversion build setting:

```yaml
hooks:
  user_defines:
    crisp_ebook_conversion:
      enabled: false
```

The app implementation and dependency versions were not substituted. The
production `pubspec.yaml` and `pubspec.lock` were restored byte-for-byte after
each native run; each receipt records the original, test-profile and restored
hashes. The lockfile did not change during the tests. This native test profile
does not qualify the optional native ebook conversion engine or a native device
release. The production web build used the original production manifest.

The exact commands and full file lists are preserved in the native receipts.
The final targeted Flutter command was:

```sh
flutter test --no-pub --reporter json \
  test/archive_udf_reader_test.dart \
  test/archive_udf_reader_review_test.dart \
  test/archive_udf_integration_test.dart \
  test/widget/archive_zip_recovery_dialog_test.dart
```

Both strict analysis runs used `flutter analyze --no-pub` with the
[38-file scope](udf-zip-analysis-files.json), without suppressing infos or
warnings. They passed before and after the final implementation follow-up.

## Independent fixtures and portable checks

The [fixture provenance document](independent-fixtures.md) records exact tool
versions, binary and image hashes, commands and derivations. The externally
mastered reference is an ISO/Joliet/UDF 1.02 bridge containing original test
payloads. The UDF-only image removes the ISO recognition descriptors from that
reference; the fragmented image additionally redistributes one file into three
nonascending extents. These two are explicitly derived fixtures, not claims of
two separately mastered images. 7-Zip independently extracted the three images
as UDF and matched every payload.

The Python UDF oracle verifies the fixed fixtures' descriptor integrity. It is
not a second general-purpose UDF implementation. The external `genisoimage` and
7-Zip executables are test-only tools; neither their binaries nor source code
are bundled with CrispCloud. The fixtures contain original test content. The
UDF reader and ZIP recovery core are original MIT code using the existing
locked dependencies; existing project licensing remains unchanged.

The portable UDF driver exercises external/derived images, malformed metadata,
ownership, offset views, bounded streaming and cancellation. Synthetic cases
cover the four supported revisions and three allocation layouts, an exact
physical position of 6,144,000,040,960 bytes, and an 8 GiB sparse logical file
with a 17-byte streamed zero prefix. The final group accepts the exact 396-byte
full-path budget and rejects 395 bytes for distinct hard links under a shared
Unicode directory prefix. These large-offset cases use synthetic positional
sources; they are not full physical multi-terabyte image extraction tests.

The ZIP fixtures come from Python's standard `zipfile` writer and controlled
damage to its output. They cover complete and missing-directory inputs,
signed and unsigned DEFLATE descriptors, unsupported stored descriptors,
truncation, bad CRC, duplicate/unsafe names, ZIP64 rejection, mismatched
descriptor sizes and incompressible input that crosses multiple 8 KiB codec
input chunks. Python independently reopened the actual emitted recovery
candidates and compared against the committed expected payload manifest.

Portable acceptance executes the same Dart sources on the VM and as actual
`dart compile js -O2` output under Node. The `self` alias below supplies the
browser global expected by that output; it does not replace the reader or codec.
For a checkout with the locked package graph resolved, first set
`CRISP_EVIDENCE_OUT` to an absolute scratch output directory:

```sh
mkdir -p "$CRISP_EVIDENCE_OUT"
dart test/support/archive_udf_web_acceptance.dart
dart compile js -O2 test/support/archive_udf_web_acceptance.dart \
  -o "$CRISP_EVIDENCE_OUT/udf.js"
node -e 'globalThis.self = globalThis; require(process.argv[1]);' \
  "$CRISP_EVIDENCE_OUT/udf.js"

dart test/support/archive_zip_recovery_web_acceptance.dart
dart compile js -O2 test/support/archive_zip_recovery_web_acceptance.dart \
  -o "$CRISP_EVIDENCE_OUT/zip.js"
node -e 'globalThis.self = globalThis; require(process.argv[1]);' \
  "$CRISP_EVIDENCE_OUT/zip.js"
dart test/support/archive_zip_recovery_web_acceptance.dart --emit-candidates \
  > "$CRISP_EVIDENCE_OUT/zip-candidates.json"
python3 test/support/check_archive_zip_recovery.py \
  --candidates "$CRISP_EVIDENCE_OUT/zip-candidates.json" \
  --report "$CRISP_EVIDENCE_OUT/zip-oracle.json"
```

The committed Python fixture validators and generator reproduction commands are
listed in the provenance document and receipts. An additional
[60-case UDF SDK/Node run](udf-core-sdk-node-receipt.json) preserves the earlier
core coverage using byte-identical reader/fixture sources and an import-only
`flutter_test` to `package:test` adaptation. Its test bodies were unchanged;
it is supplemental earlier evidence, not a claim that all final 62 core tests
were rerun through that separate harness.

## Release and remaining qualification boundaries

The production release completed successfully in 164.8 seconds using the
[release helper](../storage-runtime-20261114/web-release-build-helper.py) and
this command, with the original manifest and lockfile:

```sh
flutter build web --release --no-pub --no-wasm-dry-run \
  --dart-define=APP_VERSION=1.2.9+22 \
  --dart-define=GIT_HASH=20798b39a0c792e533a5c785294417f26db03272
```

The resulting `main.dart.js` is 27,607,886 bytes and has SHA256
`a308d6341dd73477addda31aec855df7fc39116f78cebcdc6853e337787c309b`.
The complete commit stamp and application version were verified inside the
compiled JavaScript. The existing Apple LZFSE license asset is present in the
release. The receipt records hashes of `main.dart.js`, `flutter_bootstrap.js`,
`index.html` and that license asset, and confirms that both production manifests
remained unchanged.

WebAssembly compilation, new native/device release builds, physical image
extraction above the normal fixture sizes and browser-engine execution of the
portable drivers were not qualified by this pass. Actual JavaScript acceptance
used Node; the full Flutter web application was compiled as a production release.
Hosted CI state is recorded separately by the integration owner and is not
inferred from these local results.

The supported read and recovery profiles remain those documented in
[the UDF profile](../../archive-udf-profile.md) and
[the ZIP recovery profile](../../archive-zip-recovery.md).
The UDF 64 KiB request ceiling is at the reader's `ByteSource` boundary; an
existing F3 cache or DMG decompressor can perform a larger bounded underlying
read. The current nested DMG wrapper does not forward a child's open-volume
notice. These documented limits do not prevent the qualified UDF-in-DMG reads.

## Resolved development findings

The first combined 20-file attempt had 524 passes and one failure because the
existing registry test still listed `.udf` as unsupported. That assertion was
updated to the new read-only capability and the complete gate was repeated;
the 526-pass receipt above is the clean result.

ZIP dialog tests exposed a test-scheduler interaction in which a timed stream's
completion crossed the fake-async zone. An isolated real-async pipeline
completed normally. The test helper now permits a real event-loop turn before
the controlled pump, retaining its bounded polling and all assertions. A narrow
layout test also needed to select the outer report scrollable instead of a text
field's internal horizontal scrollable. No production stream binder change
was made for either test adjustment.

Final review then identified the two small implementation gaps qualified by the
96-test follow-up: repeated ancestor prefixes needed their own aggregate path
budget, and queue-level publication warnings needed to remain visible beside a
successful saved result. The portable path-budget group and dialog warning
regression exercise those behaviors directly.
