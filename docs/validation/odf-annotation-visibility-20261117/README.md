# ODF annotation visibility — source checkpoint

Recorded 17 November 2026. **Runtime qualification is pending.** This directory
records saved source, authored regression cases, exact remote read-back checks
and source review. It does not contain a passing Dart or Flutter test run.

## Why the change is needed

The recent ODT writer adds `office:annotation` with a reviewer's name, date and
comment body after an annotated run. CrispCloud's previous inline reader
recursed into that annotation and appended the metadata to the visible body.
Its table reader could include the comment twice: the outer paragraph's
`innerText` already contained the annotation and the nested comment paragraph
was also selected as another cell paragraph.

The canonical paragraph decoder already skipped inline annotations, but its
container enumeration and streaming extractor could treat independent
annotation paragraphs as ordinary content. ODS comment export places an
annotation beside the cell's visible paragraph, so generated ODS packages
exercised that path. An annotation-only document also needed to avoid the
namespace-less raw-text fallback.

These conclusions come from tracing the exact source below. They are not
claimed as executed failing controls.

## Saved checkpoints

Both dedicated branches are named
`codex/odf-annotation-visibility-20261117`.

| Repository | Baseline | Source checkpoint | Source plus tests |
| --- | --- | --- | --- |
| Quds Office | `3458c8977cef969a86a07b39734c761ba62e4b40` | `dd2e56e8cdc5cc7e8edc21513d7a12d7e6042f8b` | `cadb4ae30811739389f46d7b393c1136e0eb448c` |
| CrispCloud | `fad903782ee45031e26c57cc8a65ccf476b1724d` | `4dd520d93115be330dfb6cf47f1db983ec2dabea` | `3e3687856ffe9b96bd8dd70eacbc759daf425ab9` |

Every source/test checkpoint was saved remotely before this report. Branch
updates used the expected previous head and did not force an existing ref.
Both refs were read back after each checkpoint. The source and test commits
include `[skip ci]`. No GitHub Actions or CI-status endpoint was queried or
awaited.

## Implementation

Canonical Quds changes:

- `packages/quds_office_engine/lib/src/odf/odf_text.dart` recognizes annotations
  by the ODF office namespace URI and local name, and skips their paragraphs.
- `packages/quds_office_engine/lib/src/extract/office_text_extractor.dart`
  skips the complete annotation subtree in the streaming extractor.
- `packages/quds_office_engine/lib/src/extract/office_search_text.dart` also
  excludes annotations from the namespace-less fallback.

CrispCloud changes:

- `lib/services/office_document_service.dart` excludes ODF annotations and
  covered-cell stories from ODT inline, block, note, header and footer text.
- Cell extraction filters both hidden paragraph ancestors and hidden
  descendants inside a visible paragraph. Its recursive text reader retains
  XML text and CDATA, preserving the visible text types previously read by
  `innerText`.
- Prefix aliases are accepted as ODF annotations; foreign namespaces, including
  an `office` prefix rebound to a foreign URI, keep their existing visible
  content. The readers do not rewrite the package or remove comment XML.

The existing streaming skip loop is safe for self-closing annotations:
`XmlPullReader.next()` emits a synthetic end-element event at the reduced
depth. Empty-element regression cases nevertheless retain this boundary.

## Authored regression cases

There are **11 new canonical test cases** in
`packages/quds_office_engine/test/odf_annotation_extraction_test.dart` and
**8 new host test cases** in
`test/office_annotation_preview_test.dart`. These are counts of authored
cases, not passed tests.

Coverage includes ODT/ODS writer-to-reader and writer-to-search behavior,
inline and sibling cell annotations, hidden nested tables, surrounding
whitespace, CDATA, aliased and shadowed namespaces, annotation-only documents,
namespace-less fallback, and empty annotations followed by paragraphs/tables.
Canonical cases retain output-budget and package-byte-budget distinctions.
Host cases cover body paragraphs, lists, cells, notes, headers and footers.
Assertions retain raw XML and original model comments.

The cases are designed to expose the old source's behavior. The old-source
failure runs and corrected-source runs remain outstanding.

## Verification completed

The six changed source/test files were fetched again at the exact source-plus-
tests commits above and compared in full with the submitted text. All matched.
The returned blob identities are recorded in
[the machine-readable source review](source-review.json).

Base-to-checkpoint comparison shows exactly four changed Quds paths and two
changed CrispCloud paths. Modified source files were `100644` in the
baselines, and all written source/test entries use that mode.

Independent read-only reviews found no additional blocker in the annotation
reader changes or the authored host API/expectation usage. These reviews are
source inspection, not compilation or execution.

Integration review found a separate issue in the newer reconciled note writer:
a note reference inside an early comment could claim the emitted note body
before a later visible body reference. That correction and its footnote/endnote
regressions belong to the parent continuation branch; they are not included
in this dedicated annotation branch's source checkpoint.

## Execution blocker and required follow-up

The workspace execution launcher failed before a shell or SDK command could
start. The retained probe was `command -v dart flutter` and returned an
exec-server process-creation error: `No such file or directory (os error 2)`.
Earlier session launcher attempts also reported no free space.

**Not run:** Dart tests, Flutter tests, failing controls, formatter, analyzer,
the vendor fidelity guard, external Word/LibreOffice interoperability and
application UI acceptance. No earlier test receipts are reused to certify
these changes.

After execution is restored, qualify the reconciled source with the pinned
Flutter/Dart toolchain. Focused commands include:

```sh
# From quds_office_suite/packages/quds_office_engine
dart test test/odf_annotation_extraction_test.dart \
  test/odf_covered_cell_extraction_test.dart \
  test/odf_export_text_fidelity_test.dart \
  test/odt_document_writer_test.dart \
  test/ods_sheet_writer_test.dart \
  test/office_search_fidelity_test.dart

# From CrispCloud after synchronizing canonical source
flutter test test/office_annotation_preview_test.dart \
  test/office_document_service_test.dart
bash tool/check_office_fidelity.sh
```

Run formatting and selected-file analysis as well, retaining the actual
commands, source attribution and results. Run the newly authored failing
controls against the corresponding pre-fix source before reporting a
regression as empirically reproduced.

The dedicated host branch does not update the managed canonical source pin.
The parent continuation must carry the reconciled canonical files and update
the fidelity manifest before final qualification.
