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

Final acceptance ran against clean app implementation
`5202d362a929c30266519dee178a441884056ca0`. Its **352 managed files** match Quds
implementation `a9bd470a4807c65f65271be896703e587c12de00` exactly. Subsequent
report/evidence commits preserve those production and test bytes.

| Gate | Result |
| --- | --- |
| Mandatory vendored engine Dart cases | 873 passed |
| Mandatory host Flutter cases | 140 passed across 26 test files |
| Engine independent Python controls | 344 passed |
| Sync / host-inventory / coverage controls | 7 / 10 / 9 passed |
| Scripted engine operations | 67/67 |
| Engine export inventory | 277/277 |
| Actual host capture inventory | 59/59 |
| Open XML SDK | 336/336 exact inputs pass; no errors |
| Supplementary native host probe | 11 actual XLSX/PPTX/DOCM/DOTX/DOTM uploads; 23 pages; no failures |
| Host line coverage | 2,223/3,558 (62.5%); all ten declared sources present |
| Working-tree and capture integrity | Clean tested tree, restored pubspec/lock and all 336 original/snapshot hashes unchanged |

No test was skipped in the complete mandatory app gate. It used Flutter 3.47.8 /
Dart 3.13.7 and the documented SQLite runtime wrapper. The native probe reused
the unchanged renderer and exact input/schema hash checks; it does not imply a
repeated-save comparison for every host capture. Quds separately passed its
complete 1,336-test engine and 448-test editor suites, all 299 source schema
inputs, and 292 native packages/592 pages with the seven documented importer
limitations explicitly retained.

[The evidence index](evidence/office-fidelity-gap-closure-20261112/README.md)
contains producer, inventory, coverage, exact SDK/native and runtime receipts.
The archived files are byte-identical copies; their archive manifest records
original paths, sizes and SHA-256 values. The complete generated native artifacts
remain at the recorded validation paths. Older consolidation receipts retain
their original historical scope.

Host coverage now includes the copy target, conversion action and conversion
dialog. Six reusable format modules are maintained and measured in Quds. Earlier
12-file/9-file percentages use a different source population and cannot be
compared directly with the current ten-file measurement.

The final remote audit at 11:18:56 UTC verified current main as an ancestor and
found no missing Office implementation in PR55's new `36f6d8c3` commit. Its
KeePass/export-review changes and documentation remain separate. The relevant
PR62 dependency fix is incorporated. Source/app Actions runs were queued at
that observation; these local acceptance results do not claim remote CI success.
