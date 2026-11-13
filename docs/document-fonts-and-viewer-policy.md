# Document fonts and viewer policy

Audit date: 2026-11-13. Source baseline:
`087b73a14b64c445c5eb717f187925b5472ed9b3`, branch
`feature/apache-file-viewer-20261113`.

This first checkpoint records verified findings while the font-path and asset
measurements are completed. It changes documentation only. The recommendations
below are not claims that new font loading or packaging changes have shipped.

## Direction

Keep one maintained primary parser for each format family, retain inexpensive
reading/source modes, and use existing system preview as an explicit alternative
where available. Improve shared font resolution before bundling a second DOC
engine. XML already has complementary Tree, Source, and XSD/XSLT views; those are
useful modes with different purposes rather than competing full-document engines.

## Verified initial findings

- DOC/DOT uses the native parser's HTML with Flutter's `HtmlWidget`. Parsed font
  metadata, actual registered font bytes, and CSS interpretation are separate
  stages; the audit is tracing all three.
- DOCX Pages calls `convertOfficeToPdf`, which loads only
  `assets/fonts/Roboto-Regular.ttf` and supplies one `SfntFont` to
  `OfficePdfExport.fromBytes`. It does not pass a family/style resolver.
- DOCX Formatted is a readable Markdown projection, with Text and raw XML also
  available. Pages is a separate approximate layout path through the existing
  Quds engine and PDF viewer.
- `OfficeHostFonts` ships Liberation Sans, Serif, and Mono in four styles each,
  plus Noto Naskh Arabic regular/bold. Registration is currently triggered by
  the Office editor. It also aliases Calibri, Carlito, and Roboto to Liberation
  Sans, and Georgia to Liberation Serif. These broad aliases must not be
  described as exact metric matches.
- The app already includes the PDF editor assets companion, whose substitutions
  include actual Carlito and TeX Gyre Heros, Termes, Cursor, and Adventor. Reusing
  existing bytes can improve Office behavior without adding a font collection.
- PS/EPS shares one Stet WASM interpreter. The shipped WASM is 14,706,940 bytes;
  its font resources are inside the binary. It does not use Flutter's loaded
  font families or the browser's CSS font cascade.
- F3 exposes Quick Look for Office documents on macOS/iOS. The platform's own
  preview availability and rendering fidelity are format/version dependent;
  the service's historical "exact-rendering" comment is not a guarantee.

## Initial source pointers

- [Office PDF service](../lib/services/office_pdf_service.dart)
- [F3 mode selection and system-preview action](../lib/widgets/internal_viewer_dialog.dart)
- [System preview](../lib/services/system_preview_service.dart)
- [Host font registration](../packages/quds_office_editor/lib/src/embed/office_host_fonts.dart)
- [Existing PDF substitutions](../packages/dart_pdf_editor/lib/src/font_substitution.dart)
- [PostScript provenance and font election](../packages/file_viewer_documents/engines/postscript/UPSTREAM.md)
- [Existing DOC/DOT comparison](file-viewer-doc-dot-comparison.md)

## Measurements in progress

Measure the existing release web output, distinguish declared package assets
from initially requested assets, and separate font files from fonts embedded
inside WASM. Compressed per-file estimates are useful for comparisons but do not
establish APK, IPA, installer, or actual network transfer size. Source archives,
fixture repositories, and audit evidence are not distributable Flutter assets.

A final update will retain the measurements and recommend changes in benefit,
size, and maintenance order.
