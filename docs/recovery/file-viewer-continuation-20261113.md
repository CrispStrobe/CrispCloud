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

## Current continuation

1. Retain the completed Linux/browser result in the validation receipts.
2. Expose the native DOC/DOT model's already parsed auxiliary stories in the
   app preview, with consistent search/copy behavior and clear story labels.
3. Investigate the linked-picture mapping, WPS table-border range, and unresolved
   textbox-shape cases independently. Any parser changes belong in the
   standalone `CrispStrobe/legacy-doc-parser` source and must be committed there
   before the verified mirror sync updates CrispCloud.
4. Run focused regression and provenance checks, record their actual scope,
   and save incremental remote commits. The historical comparison results
   remain identified as measurements of their original source checkpoint.

Implementation and final validation results will be appended as each portion
finishes. Existing input/allocation guards and source fingerprints remain part
of the acceptance criteria.

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
