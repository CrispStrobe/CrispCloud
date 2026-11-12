# Office fidelity consolidation — 12 November 2026

This continuation is on `feature/office-fidelity-consolidation-20261112`.
It combines app `main` at `d32191c3af8d74c9ec59be20d3183e323dea532f`,
Office coverage at `389a2fd2b9acb6d6213b9bbf2b5b6808534195f0`, and the
format-viewers/path-favorites feature at
`9068e31d8a11c61d4f40cc09badb4c176500f7b9`. The recovery started from the
earlier `f8dd29db` main and `86338bda` coverage snapshots.

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

## Fresh acceptance

The merged engine inventory requires **241 Office packages**. The app's own
inventory requires **59 captured Office packages**, including old/new uploads from
both pending-note scenarios and eight XLSX/PPTX files from pending-cell and
pending-slide scenarios, plus one actual DOCM, DOTX, and DOTM upload each.
The gate verifies the vendor pin, runs the shared scripted corpus and independent controls, executes the full declared Office
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

The expanded gate ran against clean app implementation commit
`e226859cbde21af0b3d70b755c350978161a73c9` and the exact source pin above.
The temporary system-SQLite test override was restored after the run; neither
`pubspec.yaml` nor its lockfile changed. Later commits archive documentation and
receipts without changing the tested implementation.

| Check | Result |
| --- | --- |
| Exact vendor verification | 309/309 shared files; seven sync controls pass |
| Mandatory Office host suite | 146 Flutter tests pass |
| Incoming feature and affected integration suite | 299 focused tests pass |
| Shared scripted engine gate | 598 Dart tests and 308 Python controls pass |
| Public operation scenarios | 67/67 exercised |
| Host inventory/coverage controls | 17 pass |
| Engine export inventory | 241/241, zero errors |
| Actual host save inventory | 59/59, zero errors |
| Independent Open XML SDK validation | 300/300 exact packages; zero errors |
| New-format/native host conversion proof | 11/11 captures, 23 pages; zero failures |

The 59 host captures are 48 DOCX, four XLSX, four PPTX, and one DOCM/DOTX/DOTM
each. The final SDK aggregate combines those files with 241 freshly generated
engine packages. Every receipt matches its exact input SHA-256, and all 300
hashes remain unchanged after validation and rendering.

Fresh host coverage is **2,605 of 3,948 instrumented lines (66.0%) across all 12
declared Office source files**, with zero files absent from instrumentation.
The source fingerprint is
`a7cf5bf291d9d385ed0cf3f8b18401e9b8df4a4939eb0b49fa9f23fc93d35ce4`.
This is executed-line coverage within the documented Office scope, not branch
coverage or whole-application coverage. It includes the three newly integrated
Word/CFB helpers; no narrower file subset is used to make the percentage larger.

The supplementary native check uses official LibreOffice 24.2.7.2 through its
LibreOfficeKit API for four actual XLSX saves, four PPTX saves, and the three
macro/template saves. All eleven convert to 23 PDF pages. This confirms native
conversion of those captures; it does not imply repeated-cycle certification
for them. The separate source report records the full 263-package validation
and 78 repeated native visual series.

Complete input hashes, schema/native receipts, scoped coverage, test summary,
runtime provenance and branch ancestry are preserved in
[the acceptance evidence](evidence/office-fidelity-consolidation-20261112/README.md).
The test-stage receipt records external validation as pending at its own capture
time; the separate final external receipt records the completed 300-file pass.
Older top-level coverage/schema evidence remains explicitly historical. The
source `adcccb4` run had 14 schema failures and 15 rendering-gate failures;
those old failures are not reused as current acceptance.

This validates the declared Office and focused incoming-feature scopes. It does
not claim a complete application test run, native Rust-SMB runtime execution,
Microsoft Office visual equivalence, or arbitrary binary DOC/DOT fidelity.

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
