# Third parser-audit evidence — 13 November 2026

The complete [audit report](../../parser-audit-20261113-third-pass.md) describes
the corrections, compatibility decisions and remaining limits. The tested
implementation is
[`b1dff952a11e7de058a924cf7da8752574d0fbc5`](https://github.com/CrispStrobe/legacy-doc-parser/commit/b1dff952a11e7de058a924cf7da8752574d0fbc5).
This evidence was added after validation without changing tested code.

## Download and integrity

- [Complete evidence ZIP](parser-audit-20261113-third-pass.zip): **503,087 bytes**;
  **172 files plus the internal SHA-256 manifest**.
- [SHA256SUMS](SHA256SUMS) verifies the ZIP.
- [Expanded file manifest](manifest.json) gives every member's byte length and
  SHA-256 digest. All archive members and CRCs were verified after creation.

ZIP SHA-256:

```text
16055d5431b3f37a5b69d7f2302c7cdef218799f4591e3b173bfb00e2bc506fd
```

## Retained results

| Evidence | Result and scope |
| --- | --- |
| `acceptance/portable-final-receipt.json` | Six completed gates, each exit 0; 1,300 Dart tests, 162 Python controls, 24 corpus checks, analysis, formatting and actual compiled JavaScript |
| `schema/report.json` and `schema/schema-validation.json` | 273 DOC-derived outputs, zero SDK errors, exact output hashes, self-tests, positive/negative controls and 586-file determinism |
| `acceptance/public-media-receipt.json` | 24 caller-built model outputs, zero SDK errors and 49-file determinism |
| `acceptance/previous-output-comparison.json` | All 263 preceding DOCX outputs are byte-identical; ten added, none removed or changed |
| `acceptance/independent-review.json` | Separate-agent source, output, scope and implementation review, including the negative-size budget finding corrected before final acceptance |
| `acceptance/environment.json` and `dependencies/` | Recorded runtimes, resolved Dart lockfile and pinned validator package/provenance metadata |
| `regressions/` | Original failing and passing development logs, including directory names, overlapping allocations, negative-size accounting, fields, list metadata and forged metafile metadata |
| `new-cases/` | One nested-control DOC/DOCX pair and nine supported list metadata DOC/DOCX/HTML cases |
| `public-model-media/` | All 24 DOCX packages, raw EMF/WMF inputs and model descriptions: six active images and eighteen inert evidence cases |
| `checkpoints.json` | Ten incremental runtime/acceptance commits saved remotely before this report |

The complete passing scope is **297 schema-validated DOCX outputs**, comprising
273 binary-DOC-derived cases and 24 caller-built public models. The public
models are not mislabeled as binary DOC input fixtures.

## Receipt history and exclusions

The original `acceptance/schema-receipt.json` records a post-processing failure:
the extra public-model validator emitted relative paths, which the initial
checker resolved from the wrong directory. The SDK had completed with zero
errors. `schema-final-receipt.json` explains the corrected resolution against
the actual command working directory; raw validator reports and inspected
output bytes are unchanged. `verify_receipts.py` independently verifies the
final receipts against the clean checkout, and its result is retained.

The original `acceptance/portable-receipt.json` records the six completed
commands. Automatic approval review then blocked the optional publication
dry-run because it could contact pub.dev and disclose package contents or
metadata outside the requested audit and GitHub synchronization. The partial
log and explanation remain in `publish-dry-run.log` and
`approval-review-note.json`. This step was omitted, not retried or reported as
successful. `run.py` is the corrected future harness; `acceptance-initial.py`
retains the original harness exactly.

The before/after regression logs are development observations from evolving
working trees, not retroactive complete source snapshots. The final
clean-checkout receipts bind 619 source files, while the schema gate separately
binds 396 source files. Compiled JavaScript, SDK installations, restored package
caches and unchanged historical corpus copies are reproducible from the pinned
implementation and are not duplicated in this archive.

No new native Office or LibreOffice rendering was performed. All five field
DOCX inputs rendered during the first audit remain byte-identical, and the
first audit's two native importer differences remain open. The ZIP does not
establish complete CFB conformance, native visual fidelity, package publication,
or a successful hosted GitHub Actions run. Literal binary `%1`–`%9` list labels
remain explicitly unsupported rather than silently changed.
