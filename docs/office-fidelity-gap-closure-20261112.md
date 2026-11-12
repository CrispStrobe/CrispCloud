# Office integration gap closure — 12 November 2026

The working branch is `feature/office-fidelity-gap-closure-20261112`. Reusable
Office logic is maintained in the Quds fork. The source report and bounded gap
ledger are authoritative:

- [Quds implementation and acceptance](https://github.com/CrispStrobe/quds_office_suite/blob/feature/office-fidelity-gap-closure-20261112/docs/office-fidelity-gap-closure-20261112.md)
- [Quds gap ledger](https://github.com/CrispStrobe/quds_office_suite/blob/feature/office-fidelity-gap-closure-20261112/docs/office-fidelity-gaps.json)

The app pins exact source bytes with `tool/office_fidelity_manifest.json`.
`sync_office_fidelity.py` checks current hashes and source ancestry before any
write, rejects host drift, and updates the manifest last. `verify_office_fidelity.py`
checks the recorded snapshot. The implementation pin is
`a9bd470a4807c65f65271be896703e587c12de00`, covering **352 managed files**.
Final combined acceptance receipts are recorded below.

## Consolidated upstream work

Commit `ced4ad7c945cd16049fc3f5dc9c4fef691cb26e0` merges main through
`977b5037f133cb2d33c57db761864183455a705e`, including the merged Rust cloud-engine
and remote POSIX path changes. The merge was clean. A focused main regression
cohort passed 69 tests; four SFTP tests require a Python/paramiko fixture that is
not available in this environment. This is local integration coverage, not a
live-cloud or all-platform acceptance claim.

Office changes from the newer format-viewers branch are integrated by component
because their reusable helpers now live upstream. The CFB ownership/size and
relocated macro/template identity fixes belong to Quds. Its bounded DOC/DOT
body-text converter authors a new macro-free DOCX. CrispCloud retains the
localized conversion dialog, captured destination and F3/F4 file routing. The
separate KeePass feature is outside this Office integration.

## Host behavior

Compact previews follow declared Word relationships, and Pages/PDF view
recognizes relocated macro-enabled Word packages. The localized DOC/DOT copy
flow explicitly describes its text-only result. It authors a new DOCX beside
the captured source without overwriting the original, then edits and saves that
captured new document even if the user navigates to another pane or folder.
Detached attachments and cancelled conversions retain their existing boundaries.

The conversion action, captured-copy target and dialog are part of the explicit
mandatory Office coverage scope. The CI dependency-resolution fix from
`90e843b` writes the vendored editor's engine override before `pub get`.

## Ownership after consolidation

The app no longer maintains local implementations of `BoundedCfbReader`, legacy
Word text extraction, Word package preservation, Office package graph navigation
or bounded Office search. Their production callers import the public Quds engine
API, and pure format regressions run upstream. The new generic legacy Word
converter also lives in Quds; its host dialog and file operations stay here.

Host-specific work includes cloud traversal and I/O, preview presentation,
localization, platform menus, asset handling and save/upload coordination. Real
host tests continue to cover those consumers and their failure paths.

## Fidelity changes consumed from Quds

The pinned source adds reference-aware worksheet renaming with reversible editor
history, preservation of unsupported imported formula caches, native section-aware
slide reordering, placeholder inheritance, and native Word outline preview
geometry. Their independent fixtures, semantic/mutation controls and native
render comparisons are maintained in Quds and mirrored through the guarded pin.

Worksheet renaming remains a bounded partial capability. Unsupported opaque
reference owners and unsafe native projections fail before mutation. Broader
Excel evaluation and Microsoft Office layout equivalence are not implied.

## Final acceptance and provenance

The final source pin, managed-file count, host test/coverage and captured-output
inventory, independent schema/native results and remote comparison are recorded
under `docs/evidence/office-fidelity-gap-closure-20261112/` and summarized here
before the final remote checkpoint. Older consolidation receipts are historical.

Host coverage tracks the explicit host integration scope. Moving generic helpers
upstream changes that denominator, so the previous 12-file/9-file percentages
must not be compared as if the source population were unchanged. Source tests
and source-hashed coverage now account for those shared components.
