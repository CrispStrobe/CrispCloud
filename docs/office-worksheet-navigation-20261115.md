# Worksheet navigation acceptance — 15 November 2026

Review: [PR #110](https://github.com/CrispStrobe/CrispCloud/pull/110).
The behavior and saved-package acceptance are complete for the source below.
Readable UI captures are the remaining visual gate.

## Accepted source and results

Exact-source push run [43685477823](https://github.com/CrispStrobe/CrispCloud/actions/runs/43685477823)
passed at `7e5af83c4e6d26247ccf91d2b03c47a816f46231`. All three jobs checked
out that SHA. The PR run also passed, but executed a synthetic merge; the push
run supplies direct source binding.

| Gate | Result |
| --- | --- |
| Engine suite | 1,265 passed |
| Host cohort | 283 passed, including 12 worksheet-navigation cases |
| Inventory controls and required evidence | 32 controls; 182/182 files |
| OpenXML SDK | 540 packages; zero errors |
| SDK controls | Eight valid, four invalid-XML and twelve type-mismatch cases passed |
| Renderer | 80 controls; 149 files rendered; 36 save-cycle and three reference comparisons passed |
| Chromium recovery copy | Exact download bytes and URL cleanup passed |

The inventory retains all 149 render/reference files plus 33 schema-only
files. The six navigation workbooks are schema-scoped; they are not included
in the 149-file render claim. Independent Python OPC/XML reads verify the
valid draft value `250`, corrected rejected draft `300`, original data, and
the escaped formula/defined-name qualifier `'O''Brien 2026'` through rename,
undo and redo.

The guarded manifest verifies 2,197 Office files, with canonical source
`e6da5be3a7e085dc200e35d6300161658179463c` and standalone DOC parser
`f9d10b5a5e68b4216892d64622caa8b0a15c7afd`. Canonical accepted head
`f31cf308` and its two successful workflows are preserved; PR #18 is merged.

## Retention and independent verification

Evidence checkpoint `5fa20624cfdcea2cede84e22f2d5ce7faa7eb1f1` preserves the
original failed-run host ZIP and all four successful-run ZIPs, full job logs,
metadata, reports and hashes. See the
[retained evidence and replay instructions](evidence/office-worksheet-navigation-20261115/resume/hosted-7e5af83c/README.md).

A separate local verifier checks all five archive digests, 1,843 extracted
files, 540 SDK input hashes, the complete host inventory, six navigation
workbooks, and all 201 rendered PNG page fingerprints. All 36 save-cycle and
three independent-reference pixel comparisons pass. Reconstructing the
committed parts into a new directory and rerunning this verifier also passes.
This verifies hosted execution evidence; it is not a second SDK or renderer
execution. The browser's generated package configuration is absent; its
matching hosted digest is retained without claiming an independent
recomputation. Source, lockfile, compiled JavaScript and payload hashes agree.

## UI capture status

The first full-view PNGs have correct 1600 × 1000 rename-modal and 390 × 1000
Arabic-host framing, but widget-test fonts leave Arabic labels, icons and
grid headers as placeholder glyphs. They establish framing only.

Preview-only checkpoint `c3ac5b674c42b9a2d8f1b1631e394c6132cfbeba` loads
existing Roboto, Noto Naskh Arabic and Material Icons assets and records
source/font hashes, locale, DPR and visible icon code points in each sidecar.
Production source, assets, dependency declarations, validation tools and the
Office workflow match the accepted source exactly; the saved Git-object
comparison records that boundary. Normal test typography is unchanged.

At the user's direction, completion no longer waits on GitHub's free-tier
queue. Monitoring stopped after the browser job passed and before the host
job started; no later hosted result is claimed.

Local continuation at formatting checkpoint `52f2dec46cdd31c99b7dd0cae8294cbe450056c4`
resolved the locked dependencies without changing the lockfile, passed the
formatter, and passed strict analysis of the two changed files. The actual
test launch then exhausted workspace disk while compiling Kindling's real
native dependency, before any worksheet tests or captures ran. Subsequent
cleanup commands cannot start because sandbox setup also needs free space.

See the [local continuation checkpoint](evidence/office-worksheet-navigation-20261115/resume/local-preview-20261115/README.md).
Restore workspace capacity, retain the full local receipts, and retry the
same focused tests. Readable-glyph visual acceptance remains open.

## Integration limits

Other checks on this older PR branch have independent failures in 3D
extension/count expectations, the German panel-header finder, PDF formatting,
and crypto release-review freshness. Their run IDs and errors are retained in
the CI observation. Newer app/canonical main contain additional Office work
with separate qualification state; this result does not qualify those sources
or claim all repository checks pass. Add/remove/reorder/hide controls,
persisted native active-tab state, physical-device testing and signed release
remain outside this increment.

## Original implementation checkpoint (historical)

Working branch: `codex/office-recovery-20261115`.
Recovered app source: `8a24763fb4b2c720ff6b617cebbea8971191bdca`.
Recovered canonical source: `5133ce0343cb7c9456f852a4e760c771294ae6de`.

The interrupted conversation's implementation and test logs were not present
in the recovered remote trees. The saved
[navigation scope](office-worksheet-navigation-20261114.md) is being reconstructed
on current main, with separate new baseline and positive evidence. Historical
test counts and results are not relabeled as current acceptance.

## Scope

Expose a localized, keyboard-accessible worksheet selector and a guarded rename
dialog through the canonical navigation hook. Rejecting pending input must
leave the draft on its original worksheet; selecting the effective current
sheet changes no editor state. Rename uses the canonical reference-rewriting
and undo/redo operation, retains invalid input for correction, and stays bound
to the original worksheet while the dialog is open.

Six planned schema-scoped artifacts under
`build/office-sheet-navigation-acceptance/` are `source.xlsx`,
`switched-draft.xlsx`, `rejected-draft-corrected.xlsx`, `rename.xlsx`,
`rename-undo.xlsx`, and `rename-redo.xlsx`. Existing rendered, reference, and
schema artifact requirements remain intact. The authored input and five actual
host uploads will have independent validation receipts; this does not claim
external Office rendering or physical-device acceptance.

## Status

- Recovered current source and started the continuation branch.
- Reconstructing host controls, localizations, and regression tests.
- Canonical synchronization and local acceptance are pending.
- No new acceptance result is claimed at this checkpoint.
