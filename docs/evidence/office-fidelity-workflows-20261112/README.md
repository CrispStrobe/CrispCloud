# Actual-host Office acceptance evidence

This evidence was collected at app commit
`0bbb7f1fc5ed2a1be8ef7a94acf23ce7c4f7d715`, with suite source
`c8d5ba3cfddf8c6fd3fa736deab992be1e0cc3aa` and all 378 selected vendor files
verified. The source and dependency declarations were unchanged throughout the
actual collection.

## Completed checks

| Check | Measured result |
| --- | --- |
| Actual host Flutter cohort | 154 passed across 21 files |
| Coverage-provenance controls | 31 passed |
| Host artifact controls | 12 passed |
| Synchronization controls | Seven passed |
| Host output inventory | 104 / 104: 92 DOCX and 12 PPTX |
| Vendored portable engine | 963 Dart tests, 389 Python controls, 305 exports |
| Host line execution | 2,540 / 3,782 instrumented lines, 67.2% |
| Host instrumentation | All ten scoped Office sources; 1,242 unhit lines |
| Collection provenance | Successful LCOV sealed against 2,133 inputs |
| Open XML SDK | 409 actual app/engine packages; zero errors |

The scope of the line report is `office_*.dart` under `lib/services` and
`lib/widgets`. Line hits do not establish branch correctness. The original
LCOV, source hashes, detailed gaps and test execution remain available here.

## Retained files

- `host-summary.json`: exact commit/pin identities, runtime, counts and hashes.
- `host-collection-receipt.json`: successful execution, all measured inputs and
  the exact raw LCOV hash.
- `host-lcov.info.xz`: losslessly compressed original LCOV; the decompressed
  bytes were verified against the collection receipt.
- `host-coverage-gaps.json`: every uncovered scoped line and source identity.
- `host-inventory.json`, `engine-inventory.json`, `app-input-receipt.json`:
  exact required packages and the byte identities staged for validation.
- `app-schema-report.json`: complete SDK results for the frozen 409 inputs.
- `app-inputs.tar.xz`: all 409 exact validated packages, losslessly compressed
  and checked against the staged input receipt after archiving.
- `host-integration.log.gz`: complete successful integration execution.
- `initial-host-failed.log.gz`: the earlier run that exposed obsolete note
  prefixes and unawaited picture decoding. It issued no successful receipt.
- `initial-schema-failed-report.json`: the earlier schema result identifying
  three small-slide fixtures below the native minimum height. The fixture was
  corrected to 100 by 72 points; the schema validator was not relaxed.
- Focused logs preserve the actual note/save and corrected picture regressions.

The final host native-render report is added after the serial render completes.
The twelve picture-only slides require independent page/rectangle/color/pixel
checks; their empty extracted text cannot pass by itself.

## Effective test configuration

Collection and strict reporting ran inside `with_ci_system_sqlite.py`, so the
temporary native-hook configuration is part of the input hashes. The wrapper
restored `pubspec.yaml` byte-for-byte afterward. Reverification requires the
same effective configuration; fresh work should run a new collection through
the normal wrapper. The receipt is an identity/provenance record, not a claim
of hermetic dependencies or complete Office support.
