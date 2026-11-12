# Office fidelity consolidation — 12 November 2026

This continuation is on `feature/office-fidelity-consolidation-20261112`.
It combines app `main` at `f8dd29db4a00607513b7f687b21e4dc16e075735` with
the newer Office coverage branch at
`86338bdab58f46eeb68bb24d0916690874dfdca5`.

The corresponding source history combines current suite `main` and the newer
native fidelity work. The app now pins **309 shared source files** to
`3ff2e15823c86cda88d3369dc4bbabf42f45290a`. The guarded synchronization verified
the previous vendor baseline, copied committed source bytes, and checked every
pinned hash against the consolidated suite.

## User-visible behavior retained and repaired

The app retains the newer paragraph/margin precision controls, styles, native
note marker preservation, note pane, localized Footnote/Endnote ribbon commands,
and actual heading/paragraph/note/image upload workflows from both branches.

The save guard uses the controller's monotonic content revision. Typing in the
Word notes pane or a Sheet/Slide inline editor can precede an undo command; a
counter based only on command notifications missed that interval. Save commits
all active drafts before capturing the revision. An older upload can clear dirty
state or close the editor only if that revision still matches.

The Close prompt reads current controller dirty state without committing a
draft, so invalid cell input can still be cancelled or discarded. Save reports
validation errors while preserving the input. No-op edits and caret/focus
changes stay clean; cancelling a draft preserves unrelated committed edits.

Six actual widget regressions cover Save and Save and Close for Word notes,
spreadsheet cells, and slide text. They pause an upload, type a newer value,
verify that no new command notification has yet occurred, then release the older
upload. The newer edit must remain dirty and open. The next successful upload
must contain the new text before clearing state or closing. The Sheet/Slide
cases also exercise real F2/IME input, cancellation, unchanged edits, failed
uploads, and retries. Expected DOCX/XLSX/PPTX contents are inspected directly
from their ZIP/XML parts without using the engine deserializer as the oracle.

The shared source also retains both branches' bookmark/content-control/note
regressions, image-cache disposal, richer native editing/history, native note
separator definitions and their absence, and strict per-part bookmark identity
checks. See the
[source consolidation report](https://github.com/CrispStrobe/quds_office_suite/blob/feature/office-fidelity-consolidation-20261112/docs/office-fidelity-consolidation-20261112.md)
for the merge decisions and bounded support claims.

## Extended Word formats and incoming feature integration

The feature branch at `9068e31d8a11c61d4f40cc09badb4c176500f7b9` is also merged.
It adds bounded legacy DOC/DOT text preview, guarded DOCM/DOTX/DOTM editing,
saved email viewers, archive parent navigation, and path favorites. Legacy binary
Word files remain preview-only; that preview does not claim to reproduce
formatting, images, headers, notes, or tracked changes.

Macro/template saves keep their original main package type, opaque binary/VBA
parts, and protected relationships. The host validates the produced package
before upload and retains dirty state on failure. Macros are preserved as opaque
bytes and are never executed. The generic pending-edit precommit and revision
comparison remain intact around the new asynchronous preservation check.

Three actual host uploads independently check the MIME type, edited document
text, opaque VBA bytes, and relationships for DOCM/DOTX/DOTM. A fourth case corrupts
a protected VBA part and proves that upload is blocked while the editor stays
dirty. The new captures pass the independent SDK's matching Word-type checks.

The merged feature's focused gate passes 299 tests across its nine incoming test
files and affected archive/viewer/editability/Office entrypoints. Two concrete
incoming integration defects were fixed: headerless MIME bodies and the default
message type of multipart/digest are preserved, and archive tests select named
members while retaining the new parent row and source-identity assertions.
The incoming parser regression assertions are unchanged.

Fresh host coverage now explicitly includes `word_package_preservation.dart`,
`legacy_word_document.dart`, and `bounded_cfb_reader.dart` in addition to the
existing Office-prefixed services/widgets. Their Word tests are part of the
mandatory host gate, and a negative control rejects an uninstrumented new helper.

## Acceptance requirements

The merged engine inventory requires **241 Office packages**. The app's own
inventory requires **59 captured Office packages**, including old/new uploads from
both pending-note scenarios and eight XLSX/PPTX files from pending-cell and
pending-slide scenarios, plus one actual DOCM, DOTX, and DOTM upload each. The gate verifies the vendor pin, runs the shared
scripted corpus and independent controls, executes the full declared Office
host test set with fresh coverage, and rejects missing or unexpected artifacts.

```sh
python3 tool/verify_office_fidelity.py
python3 tool/with_ci_system_sqlite.py bash tool/check_office_fidelity.sh
dotnet run --project tool/office-validation -- --self-test
```

The Office integration workflow additionally validates the exact engine and host
export bytes with Open XML SDK. The suite workflow covers reviewed Flutter page
goldens and independent source/repeated-save rendering. Those are separate
claims: an unsupported external renderer does not turn schema success into a
visual pass.

Fresh complete acceptance is in progress for this checkpoint. Older coverage,
schema, and render reports remain historical; the source run at `adcccb4` had
14 schema failures and 15 rendering-gate failures. This continuation regenerates
those outputs and receipts after the fixes instead of reusing the old evidence.

## Additional remote consolidation

The refreshed source pin includes coverage head
`31add77938bb1242d510ab544dbe886d87ebdf75`: native note IDs now reserve retained
separator/continuation definitions through their actual owning relationships,
and Quds preview suppresses a separator when none was imported. The reviewed
story is now exported and reopened through three cycles. The final source
external inventory is 241 engine packages plus 22 editor packages.

This app branch also merges main at
`d32191c3af8d74c9ec59be20d3183e323dea532f`, carrying the Rust-SMB starting-offset
and progress-frame fixes, and coverage at
`389a2fd2b9acb6d6213b9bbf2b5b6808534195f0`, carrying the corresponding source
syncs and historical evidence. Every managed file is then synchronized from the
combined source checkpoint, retaining both corpora and the host save fixes.

The earlier Office completion/oracle work is represented in the combined
histories. Two independent draft PRs are open: [#53 for ebooks](https://github.com/CrispStrobe/CrispCloud/pull/53)
and [#54 for file-manager capabilities](https://github.com/CrispStrobe/CrispCloud/pull/54).
They and the unfinished Rust cloud-engine branch remain outside this Office
consolidation. The format-viewers/path-favorites work is incorporated at the exact
`9068e31d` snapshot described above.
