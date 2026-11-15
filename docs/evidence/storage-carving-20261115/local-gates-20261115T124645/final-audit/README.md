# Independent final acceptance audit — corrected source4c2b6ddd

**Result: passed on the first audit attempt. No concrete acceptance gap was found within the declared selected qualification scope.**

The audit reviewed fixed clean app HEAD `f43eb7752f3c98505600a4b7d919537602dfb790`, with production source `4c2b6ddd87c854525b075dfda8783ad209565d5e`. All 13 accepted gates share source/resolution digest `3d7609bd6fdbc9beee4179e875c005ce6ccd9fcf9d6d70613706c362c574e9e0` across **8,621 inputs**. Current input bytes and all **49 unique recorded tool inputs** were rechecked at the end. Changes between production source and review HEAD are confined to evidence paths.

This audit performed only receipt, artifact, immutable Git and current-file reads. It wrote its reports to scratch, made no repository changes, ran no runtime tests, fetched no upstream objects, and did not poll or wait for CI. The fixed source and HEAD may be released after this completed audit.

## Accepted host results

| Gate | Visible passing tests | Requested suites |
|---|---:|---:|
| App | 903 | 65 |
| Engine | 275 | 23 |
| Editor | 105 | 11 |
| **Primary host total** | **1,283** | **99** |

Strict analysis passed with fatal infos and warnings over **102 selected files**: 76 app, 19 engine, six editor and one CLI. The machine streams have complete unique test IDs and successful terminal events, with no failed, error or skipped events. Navigation capture's **12 passing tests** remain separate from the primary host count.

The selected receipts are `analysis-app-final`, `analysis-engine-final`, `analysis-editor-final`, `analysis-cli-final`, `app-final`, `engine-final`, `editor-final`, `scripted-oracle-final`, `comments-oracle-final`, `source-integrity-final`, `png-portable-final-2`, `navigation-capture-final`, and `navigation-independent-review-final`. All exact artifact inventories and hashes passed. The first `png-portable-final` launch failure remains retained and excluded; its successful retry follows the evidence launcher's executable-mode correction without changing launcher bytes or production source.

## Source and generated-output verification

The source-integrity gate covered **11,899 tracked checkout files**, **2,336 managed canonical files** and **85 controls**. The independent final audit checked every managed file's SHA-256, canonical Git blob identity and file mode: **504 Quds files** at `47e44e0ae35adcc406eee2a2ae2118dd2a4a082a`, and **1,832 parser files** at `08296edbee08da013a8ff718798972552ccd03f7`. Required incoming ancestry and the exact three restored ODS regressions remain preserved.

The general Office oracle checked **12 fresh generated exports** and **17 reader controls**. Retained export bytes match the passed engine gate's immediately recorded generator inventory and the live generated files.

The comments oracle performed **1,154 independent checks** on **nine fresh XLSX files** and two authored manifests. Three packages cover repeated saves of six authored plain comments. Six packages cover valid and invalid-root orphan parts through empty, added and cleared phases. Both worksheets' notes, explicit owned comment relationships, original note preservation, exact unrelated XML and outgoing relationship bytes, content types, and valid empty authority passed. All **11 generated inputs** stayed unchanged and match the generator binding written before readback. Actual pinned Dart, the canonical generator, the tightened Python reader and five independent reader-module hashes were verified.

These comments checks cover the bounded plain-comment profile. They do not claim broad Open XML schema certification, rich comments, VML geometry or native Excel rendering.

## Portable PNG and navigation evidence

The accepted PNG retry executed both the Dart VM and actual compiled JavaScript through the recorded Node binary. Each runtime covered **eight cases and 248 assertions**. Independent Python checks verified each runtime's eight ZIP outputs containing ten recovered PNGs and the wrong-hash rejection control. VM and JavaScript candidate payloads are identical, and compiled JavaScript and Node identities are retained.

Navigation evidence contains **six real workbooks** and two fresh captures, bound to the passed capture receipt with exact font/source identities:

| Capture | Dimensions | SHA-256 |
|---|---|---|
| `rename-validation.png` | 1600×1000 | `081e408dc6062dc9c1bdcc7cf7e6b3ddea64e4d747d0ea1ca551a5107240b693` |
| `worksheet-arabic-narrow.png` | 390×1000 | `fd621aedbfd1cd3a4748d2d5fce7c6c637ba757e4cdfda57e0b5426fb5ac718d` |

The machine audit checks their identities, dimensions, six font files and two source files per capture. Root's actual visual inspection is a separate record; this script does not substitute pixel/hash checks for visual review.

## Exact Linux golden scope

All four visible cases in the two golden suites passed on Linux against five exact tracked 800×1120 references. The audit verified the normal comparator, absence of update/filter flags, bundled-font setup, viewport and DPR, all five PNG identities, and all 14 bundled font assets. The frozen source defines **18 exact comparisons**: two import/reopen comparisons and 16 structure/save-cycle comparisons. That loop count is identified as source-defined scope, not a separate runtime-test total.

This establishes the selected Linux comparisons. It does not claim new golden captures or external Word/macOS rendering fidelity.

## Complete standalone parser qualification

The primary parser result is **4,132 passing visible tests across all 144 requested suites**, plus strict analysis of **18 files**, from immutable evidence `09a4a531a4aa210a638a220de45c9d53d44c84e1` on exact source `08296edbee08da013a8ff718798972552ccd03f7`. The 144 hidden loader events are excluded. Raw IDs are unique and paired, per-suite counts match, and all requested suites are represented.

The audit independently verified **32 archive members**, **23 inner-index entries**, **937 non-evidence source files**, stable **949-entry snapshots**, six actual SDK binaries/snapshots, the retained recorder and immutable qualification helper. The original and current standalone locks are byte-identical; normalized dependency graphs match. Serialized config/graph bytes differ between workspaces and are not described as identical.

The foreign environment script has a stable recorded before/after hash but its bytes were not retained. The report explicitly marks that one tool as recorded-hash-only. No foreign workspace filesystem path was accessed. Standalone parser acceptance and host app dependency-graph acceptance retain their separate scopes.

The older 4,131-test full run and the 18-test changed-suite run remain preserved and were checked as historical evidence. Their overlapping counts are not added to the complete 4,132-test total.

## Audit files

`recorded-gates.json` contains exact selected receipts, source/tool checks, machine totals and artifact manifests. `cross-bindings.json` contains generator, reader, canonical source, parser, golden, navigation and PNG identity checks. `invocation.json`, the stdout/stderr logs, `completion.json`, the exact auditor and final configuration preserve this first successful audit attempt. `artifacts-sha256.json` indexes every other package file; each entry was read back and verified after packaging.
