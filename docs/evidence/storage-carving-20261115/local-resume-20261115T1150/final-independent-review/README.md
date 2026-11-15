# Final independent acceptance audit

**Result: pass for the explicitly recorded qualification scopes. No concrete acceptance gap remains in the selected evidence.**

This audit read the fixed, clean CrispCloud checkout at `cc92423bb98789239380864d5e8343c19c25e815`. Its production source is identical, including Git blob identities and file modes, to the saved production checkpoint `20ee83ff965d5433aeb528ae84debdb304edcf4a`. The 194 changed paths between those commits are all under `docs/evidence/`.

The auditor wrote only this scratch directory. It did not rerun runtime tests, change either canonical checkout, modify the app, refresh remotes, poll CI, or wait for CI. Root may continue saving evidence after this completed audit.

## Accepted gates

Only these 12 labels were supplied to the saved `plans/audit_recorded_gates.py`. Rejected attempts and predecessor evidence were not selected.

| Gate | Verified result |
| --- | --- |
| `analysis-app-final` | 76 Dart files; fatal infos and warnings enabled; no issues |
| `analysis-engine-final` | 16 Dart files; fatal infos and warnings enabled; no issues |
| `analysis-editor-final` | 4 Dart files; fatal infos and warnings enabled; no issues |
| `analysis-cli-final` | 1 Dart file; fatal infos and warnings enabled; no issues |
| `app-retry-1` | 903 passing tests across 65 suites |
| `engine-final` | 249 passing tests across 22 suites |
| `editor-final` | 101 passing tests across 9 suites |
| `scripted-oracle-final` | 12 generated Office files and 17 oracle controls |
| `source-integrity-final` | 2,303 managed files, 11,366 tracked files at that gate, and 85 Python controls |
| `png-portable-final` | VM and actual compiled JavaScript each passed 8 cases / 248 assertions; independent Python verified 8 ZIPs / 10 PNGs per runtime |
| `navigation-capture-final` | 12 passing tests in 1 suite, recorded separately from the main cohort |
| `navigation-independent-review-final` | Six actual workbooks and two complete host PNGs with exact font/source receipts |

The primary host total is **1,253 passing tests across 96 suites**. The navigation capture is a repeated execution of a suite already included in the app cohort, so its 12 tests are not added to that total. The four strict analysis groups cover 97 file entries. Canonical parser acceptance below is a separate dependency graph and is also reported separately.

For every selected machine test gate, the auditor independently parsed raw JSON events, required unique matching start/end IDs, required every visible and hidden end event to succeed, rejected errors and skips, required one successful final `done` event, and checked the exact requested/observed suite inventory and saved counts.

## Source, resolution, tools, and artifact integrity

All 12 gates share the same **8,588-entry source and resolution snapshot**, including 8,577 tracked non-evidence source entries:

```text
8987e08d73b266e89dbf0e4f4615333155ee6754b9a38fd90380444d02d64c8b
```

The audit compared saved before/after snapshots, current source bytes, current ignored dependency graphs, original tested commit trees and modes, recorded commands, and all recorded tool hashes. It also rechecked current source and resolution at the audit's end. Each gate remained stable during its own recorded execution even though evidence-only saves advanced HEAD between gates.

The exact inventories and SHA-256/size entries passed for all 12 receipt directories plus these four ancillary directories:

- `scripted-oracle-final-artifacts`
- `source-integrity-final-details`
- `png-portable-final-artifacts`
- `navigation-independent-review-final-artifacts`

These 16 indexes cover 160 artifact files, excluding the indexes themselves. `recorded-gates.json` gives every selected tested head and index hash.

The additional audit independently compared all **2,303 managed files** with both canonical trees: **496 Quds files** at `c17098d65fe5f6e2bdf9999389deb2a6b508d928` and **1,807 parser files** at `9bdcc7eba3f1ce80b7d834d7740895774eeca615`. It compared canonical/app Git identities, current bytes, executable/symlink modes, manifest SHA-256 values, and the saved comparison receipt. There were no mismatches. The managed manifest SHA-256 is `f734610dc8d741b8180c33d7d5fdba9eff288cca4c6f2dad73faf1c4c9242f54`.

## Generated-file and independent-oracle bindings

The passed engine gate's `produced-files.json` is indexed in its receipt and identified by its postprocessing metadata. Its generation head and source/resolution digest agree with the independent Office oracle. All 12 retained DOCX/XLSX/PPTX files and the live generated files match that exact binding. The oracle reports 12 exports with no failures, and its raw control log records 17 successful controls. This closes the generated-output gate that the source-only helper correctly leaves to a separate command.

The passed navigation capture similarly binds ten files: six XLSX files, two PNGs, and two PNG metadata receipts. The retained and live outputs match the capture hashes, source digest, and generation head. The independent workbook reader verifies draft commit, rejected-draft correction, apostrophe-safe rename, undo and redo, plus formula/cache/defined-name and validation preservation. The image receipts bind the exact six font assets and two capture sources. The PNG headers and receipts agree on 1600×1000 English and 390×1000 Arabic captures at DPR 1.

Root separately inspected the actual images and reported readable complete duplicate-name error text and visible dialog controls in English, and joined Arabic glyphs with visible worksheet selector/rename controls in the narrow capture. The narrow viewport uses filename ellipsis and horizontal scrolling. Root will save that visual observation separately; this audit's numeric checks alone do not claim visual review.

The portable PNG audit verified both candidate receipt hashes against their Python reports, all eight decoded archive hashes/sizes and recovered-image counts per runtime, the fixture manifest hash, the compiled JavaScript hash, and the exact resolved Node executable hash. VM and JavaScript candidate payloads are identical. Both independent Python reports record rejection of the wrong expected hash. The compiled JavaScript SHA-256 is `b41eeb4323d6a3b971c831730da18ac6edd4126536e048d2c6c2d35572a5603e`.

## Final canonical parser linkage

The app's `canonical-parser-current-qualification.json` points to source pin `9bdcc7eba3f1ce80b7d834d7740895774eeca615` and final remote evidence head `57442c79239fb4d483e274e0ebb04f34686beb6c`.

The auditor read the final receipts directly from immutable canonical Git objects, without checking out that evidence head. It verified all 22 indexed artifact files across these three final parser gates:

| Canonical gate | Tested commit | Result |
| --- | --- | --- |
| `directory-focused-fixed` | `9bdcc7eba3f1ce80b7d834d7740895774eeca615` | 9 passing recovery controls |
| `directory-strict-analysis` | `fde5685965db83e9cfb6807ecba1205438d7e819` | 18 Dart files; fatal infos enabled, no issues or stderr |
| `directory-all-parser-final` | `337b2fad504ce68f9e5e5053ae859bb5905f3dd8` | 4,131 passing tests across 144 suites; no errors or skips |

The app's copied reports are exactly equal to the immutable canonical reports. Each parser gate's raw events, artifact inventory, before/after snapshots, commands, recorded tool hashes, and tested Git tree passed independent checks. All tested commits have the same 937 non-evidence Git entries as the app pin. Only evidence files changed after that pin.

The parser recorder includes its growing historical evidence directory in full input snapshots, so the three full snapshot digests differ. After excluding only `doc/evidence/`, all three have identical 949-entry source/declaration/resolution snapshots, including explicit absent-input entries, and those entries match the pinned current checkout. Their normalized digest is:

```text
6149dc897d58ac97384d135303acad721fbbfe24cf39dca2c92ef0cdcc577447
```

ParserCanonical HEAD was still `9bdcc7eba3f1ce80b7d834d7740895774eeca615` when the audit completed. The standalone parser development graph is not substituted for host qualification; the app, engine, and editor receipts independently qualify the committed host graph.

## Incoming closure and scope

The final incoming supplement covers the same finite **53 observed heads**: 49 ancestors and four separately reviewed superseded heads, with zero unaccounted heads. This audit independently rechecked all 49 ancestry relations and the final app/Quds/parser tree bindings. The four non-ancestor equivalence/semantic proofs remain in the incoming audit and its supplement; this audit does not claim a fresh upstream observation.

The two optional live-corpus scanners that search private Documents/Downloads directories were excluded from mandatory qualification and were not counted as passing acceptance. These receipts establish the named synthetic/local source and runtime scopes. They do not establish external Microsoft Office rendering, broad document-schema conformance, arbitrary private-corpus compatibility, release-binary qualification on every desktop OS, or a hermetic snapshot of all runtime caches.

## Files to save with the final evidence

- `recorded-gates.json`: saved 12-gate independent raw receipt/source/tool/inventory audit.
- `cross-bindings.json`: additional generated-output, parser, canonical source, and incoming-linkage audit.
- `audit_cross_bindings.py`: read-only reproducer for that additional audit using the recorded workspace and immutable heads.
- `README.md`: this scope and results explanation.
- `artifacts-sha256.json`: exact hashes and sizes for the four files above.

No runtime suite was rerun for this acceptance audit. Earlier failing receipts remain historical evidence and do not contribute to the accepted counts.
