# New documents, conversion and recent files

**File → New…** chooses an editor and creates a document in the active pane's
verified local or connected cloud folder. Text/code keeps a chosen extension;
Markdown and CSV use the text editor. DOCX, XLSX and PPTX open the Quds editors;
PDF opens the PDF editor; PNG opens the image editor; EPUB opens the book editor.
Images start as an opaque white 1024 × 768 canvas. Presentations start with one
blank slide; spreadsheets with one sheet; PDFs with one page; EPUBs with one
chapter. Cancel creates nothing. Existing destinations are refused, and creation
uses the existing staged, verified write boundary. Provider publication guarantees
remain those of the selected storage adapter.

New and conversion are also in the command palette. On macOS they remain in
File while editing. Starting another editor uses the current editor's actual
asynchronous close flow, including its Save/Discard/Cancel prompt. A cancelled
prompt or failed save aborts the handoff. Saved custom File menus gain the new
commands once; later user customizations remain respected.

## Converter

**File → Convert existing file…** and the equivalent button in New open the same
conversion dialog. Start from the selected file or choose a source through the
system file picker. Inspect the prepared output and any warnings, then choose
**Save copy and edit**. Output goes to the captured destination folder under a
new filename. The original and existing files are protected from replacement.

| Input | Offered output |
| --- | --- |
| PDF, including a recognized PDF with an unknown suffix | DOCX, XLSX, PPTX, UTF-8 text |
| DOCX/DOCM, XLSX/XLSM/XLTX, PPTX/PPTM | PDF |
| Supported legacy XLS/XLT | XLSX, PDF |
| Supported legacy DOC/DOT | DOCX, PDF |
| CSV/TSV | XLSX, DOCX, PDF, UTF-8 text |
| Supported text/code | DOCX, PDF |
| PNG, JPEG, WebP, BMP, TIFF, GIF | PNG, JPEG |

PDF reconstruction uses the fork's existing `PdfToOffice` API, corresponding to
[upstream issue #8](https://github.com/MohammedAsaadAsaad/quds_office_suite/issues/8).
It reconstructs positioned text and supported images, detects ruled tables, and
retains supported RTL metadata. Reconstruction is approximate. Ruled tables go
to table worksheets; prose goes to the Text worksheet when no table is found.
A page without extractable text is reported as requiring OCR. **This converter
does not implement OCR.** PPTX currently omits non-PNG recovered images; the
warning is shown before saving. DOCX supports recovered JPEG and PNG images.
Warnings require explicit review before saving. Encrypted input can be opened
with a password, but converted copies are unencrypted and do not retain digital
signatures. The existing legacy Word converter remains available for its more
specialized inspection, installed-Office and DOCM workflows.

CSV expressions are imported as literal values, rather than executable formulas.
Text decoding reuses the editor's encoding detection. JPEG flattens transparency
onto white at quality 95; animated/multipage images convert their first frame.
Input is capped at 64 MiB, text at 8 MiB/100,000 lines, recovered PDFs at 300
pages and images at 40 million pixels; output is capped at 128 MiB. These byte
limits do not establish constant memory use or full visual fidelity.

## Recent files

**File → Recent files…** has Edited, Opened and All filters, path search, reopening
in a viewer/editor, and removal of individual entries.

- Successful saves and created documents enter Edited. A failed save or merely
  opening an editor does not count as a successful edit.
- Opened-file logging is optional and off by default. It records explicit viewer
  and editor opens, rather than every selection in a preview pane.
- Tracking can be disabled. Preferences and metadata persist together locally.
- Up to 1,000 files are retained. Entries identify the original storage account
  and path; a different account is never substituted when reopening. Reconnect
  unavailable storage first. Transient attachments/unverified origins are omitted.
- **Save list…** exports versioned JSON. **Load list…** validates a complete list
  before merging it, or replacing the current list when explicitly selected.
  Importing a list never turns on recording. Imports are limited to 8 MiB.
- **Purge list…** confirms before clearing memory and persisted history. It does
  not delete documents, editor recovery copies or previously exported lists.

History contains file/location metadata, not document contents or passwords.
On small screens, list save/load/purge actions are in the title bar's overflow
menu. A history storage error is reported in this dialog without turning a
successful document save into a failed save.

## Active folder pane

The file-operation pane has a persistent theme-coloured outline and an accented
path header with a filled selection marker. The other pane has a neutral border
and unfilled marker. The indicator follows the active pane independently of
keyboard focus; fixed border padding prevents column/row movement when switching.

## Integration checks (15 November 2026)

The focused native regression run passed 93 tests. Three additional portability
and end-to-end New → Word editor tests passed, as did the isolated existing
spreadsheet save/close regression. The source fork’s seven wrap-text fidelity
tests passed before synchronizing its 2,217 managed files into this app.
