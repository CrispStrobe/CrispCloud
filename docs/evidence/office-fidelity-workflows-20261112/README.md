# Actual-host Office acceptance evidence

This evidence was collected at app commit
`afba7b6ac6e142294043c066f7ef2a926add6533`, with suite source
`8223a2297418ba6f478ed6ce80b9881d28680094` and all 378 selected vendor files
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
| LibreOffice/Poppler host rendering | 104 / 104 rendered, 113 pages, zero failures |
| Native save-cycle comparisons | 32 complete groups passed |
| Independently measured image-only pages | 18: twelve PPTX and six JPEG/GIF DOCX |
| Native Python controls | 69 passed |

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
- `host-native-report.json`, `host-native.log.gz`: the complete successful
  native run. All 104 files rendered and all 32 three-save groups passed;
  no retry or schema-only qualification was needed.
- `host-native-provenance.json`: exact app/pin identities and renderer/input/
  schema hashes, verified unchanged before and after native execution.
- `host-native-artifacts.tar.xz`, `host-native-artifact-hashes.json`: all 104
  PDFs and 113 page PNGs. Decoded PNG dimensions and RGB fingerprints match
  the renderer records. PDF hashes identify the retained archive bytes.
- `acceptance-summary.json`: machine-readable final results and limits.
- `host-integration.log.gz`: complete successful integration execution.
- `initial-host-failed.log.gz`: the earlier run that exposed obsolete note
  prefixes and unawaited picture decoding. It issued no successful receipt.
- `initial-schema-failed-report.json`: the earlier schema result identifying
  three small-slide fixtures below the native minimum height. The fixture was
  corrected to 100 by 72 points; the schema validator was not relaxed.
- `initial-host-native-failed-report.json` and its compressed log: the first
  complete native host run rendered 98 exports and rejected six image-only
  JPEG/GIF Word fixtures because its text requirement lacked a corresponding
  Word pixel oracle. Those six cases did not receive visual acceptance.
- Focused logs preserve the actual note/save and corrected picture regressions.

Full host native acceptance passed at the measured app revision. Eighteen
image-only exports require independent page, rectangle, color and pixel checks:
twelve slide cases and six JPEG/GIF Word cases. Word cases additionally require
the authored 12-point empty leading paragraph, exact inline geometry and owned
media. Their empty extracted text cannot pass by itself. Page-size tolerance
remains 0.03 point and raster edges one pixel. Arbitrary blank or image-only
files do not gain a general exception.

All schema records match the complete frozen 409-file receipt. Every native
record matches one of the exact 104 host input hashes, every cycle is complete,
and every retained PNG was decoded and checked before the archive was created.
The source suite has separate native evidence: 320 rendered packages plus
seven explicitly qualified schema-only cases, without visual certification for
those seven. Neither corpus certifies Microsoft Office pixel equivalence.

## Effective test configuration

Collection and strict reporting ran inside `with_ci_system_sqlite.py`, so the
temporary native-hook configuration is part of the input hashes. The wrapper
restored `pubspec.yaml` byte-for-byte afterward. Reverification requires the
same effective configuration; fresh work should run a new collection through
the normal wrapper. The receipt is an identity/provenance record, not a claim
of hermetic dependencies or complete Office support.
