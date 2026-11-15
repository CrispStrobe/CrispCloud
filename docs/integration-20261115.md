# Integration and PDF workspace — 15 November 2026

The integration includes the published legacy XLS and DOC recovery branches,
worksheet navigation recovery, Word selection, fields, header preservation,
revision performance, headings/theme colours and text-free shapes. Spreadsheet
imports include HTML captions/header emphasis and BIFF palettes. The Office
manifest records the exact canonical source and standalone DOC parser pins.

Three interaction defects were reproduced and fixed in the canonical engine:
opaque header fallback left revisions targeting discarded paragraphs; an
unfinished field in one story leaked into another; and a non-text inline before
a field was incorrectly included in its whole-paragraph result. Their tests
failed before the fixes. The app now suggests XLSX for every converted legacy
spreadsheet save route, retains original BIFF bytes for original export, and
only cleans the revision successfully written to a separate file.

The PDF editor keeps dart_pdf_editor 14.0.0 and the existing pdfx preview. Quds
provides annotations, notes, ink, forms, XFDF and incremental saves; it is not a
drop-in improvement over the current editor's richer annotation/page tools.
No comparative rendering or performance benchmark was conducted.

PDF changes:

- Text-selection notes use highlight QuadPoints and Contents, including multiple
  lines/pages in one undo transaction. Existing highlight notes can be edited.
- Pending ink is flushed before Save, Export or Close instead of waiting for the
  package's 800 ms batching delay. Cancel and later edits remain protected.
- macOS title-bar actions replace folder controls while editing a PDF. The
  duplicate PDF AppBar disappears only after native acknowledgement. A missing
  native host retains the Flutter controls. Other modal editors hide folder
  actions. Session-scoped IDs reject stale title-bar commands.
- Desktop primary/context toolbars use the same commands, can move independently,
  have reduced padding and optional snapping/orientation, and persist placement.
  Narrow screens retain the existing touch layout.
- The additive toolbar API is recorded in the maintained upstream patch;
  reconstructing the editor and document packages verifies all 343 files.

Observed checks:

- Standalone legacy DOC parser: 4,075 tests passed.
- Initial combined engine: 1,783 passed, three existing conditional skips.
- Full engine after the final heading, shape and palette merges: 1,787 passed,
  three existing conditional skips. The final source changes only export
  ordering and README prose; its analyzer has no issues.
- Subsequent worksheet navigation and Word selection editor cohort: 42 passed,
  including macOS/Windows selection goldens.
- Affected host regressions: 79 passed, including note save/reopen, native row
  acknowledgement/fallback, action isolation, independent toolbar dragging,
  legacy saves, worksheet navigation and Office lifecycle tests.
- PDF host static analysis: no issues; PDF formatting: 66 files unchanged.
- Office sync controls: eight passed; Apple export controls: 38 passed.

The export inventory fingerprints bind the reviewed sources without changing
classification or territory decisions. Native startup testing does not establish
full visual fidelity for arbitrary PDFs or Office files. Existing queued release
jobs and tags are retained.
