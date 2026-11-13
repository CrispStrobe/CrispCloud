# File Viewer continuation checkpoint

13 November 2026. Work resumes from remote branch
`feature/apache-file-viewer-20261113` at
[`ddfd695`](https://github.com/CrispStrobe/CrispCloud/commit/ddfd6951997b16b3e7b1b72ec43a9f2e0077e9c8).
This is newer than the original format/license audit at `9b9af85`.

## Recovered state

- WordPerfect, CHM, XLS/XLT/XLSB, PPT/POT/PPS, PS/EPS, MBOX, and XML with
  XSD/XSLT are already integrated. The selected engines and corresponding
  notices/source archives are saved on this same feature branch.
- [The latest selected-engine workflow](https://github.com/CrispStrobe/CrispCloud/actions/runs/43387993185)
  completed successfully, including the real WebKitGTK-enabled Linux consumer
  compiler check. It does not establish native interactive/device rendering.
- [The DOC/DOT comparison](../file-viewer-doc-dot-comparison.md) retains a
  reproducible 19-fixture probe. It identifies an app preview omission and
  three specific native parser compatibility failures.
- [PR #95](https://github.com/CrispStrobe/CrispCloud/pull/95) remains draft.
  The continuation is on the existing feature branch; it does not merge or
  release the work.

## Completed continuation

1. Retained the completed Linux/browser result in the validation receipts.
2. Exposed the native DOC/DOT model's already parsed auxiliary stories in the
   app preview, with consistent search/copy behavior and clear story labels.
3. Fixed the linked-picture mapping, WPS table-border range, and unresolved
   textbox-shape cases independently. The parser changes were saved in the
   standalone `CrispStrobe/legacy-doc-parser` source before the verified mirror
   sync updated CrispCloud.
4. Ran focused regression and provenance checks, recorded their actual scope,
   and saved incremental remote commits. The historical comparison results
   remain identified as measurements of their original source checkpoint.

Existing input/allocation guards and source fingerprints remain part of the
acceptance criteria. The implementation and executed checks are recorded below.

## Saved implementation checkpoints

| Repository | Remote commit | Result |
| --- | --- | --- |
| CrispCloud | [`33cd37e`](https://github.com/CrispStrobe/CrispCloud/commit/33cd37eb015edc896d56136ba4fdbdf16d03d07c) | Completed Linux/Chromium evidence retained, replacing stale pending status. |
| CrispCloud | [`ee7531c`](https://github.com/CrispStrobe/CrispCloud/commit/ee7531cd2404cb1243c3198ebcac9e5620df87c2) | Reproducible npm contract entry and common build-checkout selection; 61 contracts pass. |
| CrispCloud | [`e5d3324`](https://github.com/CrispStrobe/CrispCloud/commit/e5d332463bd773e812da277ab3c4d74d0f183f38) | Labeled DOC/DOT auxiliary-story projection, nine-language labels, extracted-content search/copy, and focused regressions. |
| CrispCloud | [`60794aa`](https://github.com/CrispStrobe/CrispCloud/commit/60794aa1c8982eef2dd74d3c9e4c5280f19601a0) | Canonical main snapshot `be103b4c` brought into the feature branch, preserving newer Word, archive, source-retention and runtime verification work. |
| legacy-doc-parser | [`22f2daf`](https://github.com/CrispStrobe/legacy-doc-parser/commit/22f2dafeeb28a5a469cf436d26dca0e0da7a7730) | First bounded compatibility fixes and 27 authored positive/negative controls. |
| legacy-doc-parser | [`e442772`](https://github.com/CrispStrobe/legacy-doc-parser/commit/e4427725cc720eaefad97c2cb921a6fe1e36749d) | Canonical parser `419864b` preserved, with 1,019 passing tests, clean full analysis and a fresh 19/19 differential probe. |
| CrispCloud | [`e8e46b5`](https://github.com/CrispStrobe/CrispCloud/commit/e8e46b5ef04dcea3b4a65f5b4f1c797559528f5b) | Exact standalone parser mirror, source pin and evidence synced with the repository's guarded tool. |
| CrispCloud | [`66843aa`](https://github.com/CrispStrobe/CrispCloud/commit/66843aa48cc23a647cfdd4bde85554a4574d527e) | Final recovered-placement labels, updated comparison and passing app/provenance receipts retained. |

The source guard verified all **1,500 Office-managed files** against the updated
inventory and exact standalone Git commit, including tracked file modes and
retained evidence. The independent document-runtime guard verified **174**
runtime, notice, overlay and matching-source records. No dependency version,
native hook or source-verification rule was changed to make these checks pass.

The [updated comparison](../file-viewer-doc-dot-comparison.md) separates the
original 16/19 native result from the new 19/19 result. It also distinguishes
appended reading content from original pagination and preserves the exact
limitations of linked-image and unpositioned-textbox recovery.

## Final app regression checks

The final projection adds an explicit localized **Placement unavailable**
qualifier for recovered textboxes. All nine supported languages preserve
document text while translating the generated headings. The app tests passed
in three nonoverlapping invocations: **42 DOC/review/metafile cases**, **36
MBOX/email/routing/source cases**, and **11 F3 email/search/format cases**.
All **89** tests passed; the focused analyzer over nine paths reports no issues.
The parser-sync and document-runtime verifier controls also pass **23/23**.

The [app validation receipt](../evidence/file-viewer-continuation-20261113/README.md)
retains the real logs, exact source/lockfile hashes and commands. These commands
used Flutter 3.47.8 / Dart 3.13.7, the actual production graph, enforced lockfile
resolution and normal native hooks. The initial filtered-environment Rustup
failure is retained separately; genuine workspace compiler launchers resolved
that environment issue without replacing a dependency or disabling a hook.

The production JavaScript web release build also **passed**, with unchanged
release/O4 settings and the optional separate Flutter-WASM dry run disabled.
The initial default invocation's terminated compiler output is retained along
with the successful invocation. All **131** selected runtime/notice/host files
in the actual web bundle match their source hashes; the format engines' WASM
files remain included. Flutter-WASM application output and interactive device
qualification remain outside this result. The [build receipt](../evidence/file-viewer-continuation-20261113/web-release.json)
retains the output size, digest and packaging checks.

## Reproducible local engine checks

The normal `npm test` entry now selects the six actual engine test directories.
WordPerfect/CHM and XML/PostScript test staging also reuse the build's default
`tooling/.source` checkout, matching the existing spreadsheet/PPT behavior.
Previously the npm script pointed to a nonexistent directory and those helpers
required an undocumented sibling checkout unless an environment override was set.

On the unmodified Node 24.22.1 runtime, `npm run build` reproduced all committed
generated assets/notices/source materials without a Git diff. Then `npm test`
passed all **61** native/WASM contracts, with zero failures and zero skips, using
the default source location. The [executed log](../evidence/file-viewer-continuation-20261113/selected-engine-tests.log)
is retained. This check changes test entry points, not production engine code.
