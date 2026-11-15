# Comment ownership correction linkage

Canonical corrected source: `47e44e0ae35adcc406eee2a2ae2118dd2a4a082a`. Final saved evidence: `9f60ab2a47c2ebcef3d322a608d690178ff9b22f` on `integration/comments-ownership-20261115T132154`. The canonical checkout is clean and detached at the source pin for host integrity checks; the evidence branch and every predecessor ref remain intact.

The exact observed incoming pin `4e8c8f80f206e93be8530a94da478e06c0f87608` and restored ODS source `9bb71983` are ancestors. Only the sheet writer, additive namespace regression coverage and fixture generator differ outside evidence. The three restored ODS regressions remain byte-identical.

## Correction and proof

New worksheets previously adopted unrelated fixed-name comments parts after URI allocation: valid parts were deleted/overwritten; invalid-root orphans could cause refusal after package mutation. The writer now captures validated ownership from existing source worksheets before any part writes. A new sheet receives a distinct empty authoritative comments part when preserving an orphan would otherwise expose it as a legacy fallback. This authority survives empty→add→clear and reopen. Orphan XML, content type and outgoing relationship bytes stay intact. Existing namespace, shared ownership, authored relationship and malformed-owned-target behavior is retained.

The four failing baseline cases were saved before the production correction. All 28 focused comment tests then passed on the saved source; selected strict analysis passed with no issues. All 25 raw receipt files were independently hash-checked against the final immutable evidence commit, and source/resolution snapshots matched before and after every run. The failed baseline is diagnostic proof, never passing acceptance.

The canonical generator now emits 3 repeated-save packages and 6 valid/malformed orphan empty/add/clear lifecycle packages, plus authored JSON expectations. The parent workflow owns the independent Python/openpyxl gate; its acceptance is separate. These 28 tests add zero to primary host totals when the same suites run in the host cohort.

See `linkage.json` for exact trees, Git blobs, input hashes and gate results; `raw-gates-sha256.json` identifies every raw file; `source-correction.patch` preserves the scoped correction. No later upstream intake or GitHub Actions wait occurred.
