# Changelog

All notable changes to `quds_reports` are documented here.

The version matches `quds_office_engine`. A report API addition lands in both
packages together.

## 1.5.0

Same report surface as `quds_office_engine` 1.5.0.

- Prompted and required variables. Multiple detail sections. Crosstabs.
  Subreports stored inside the `.qrep`.
- Rich text runs, including a link that exports to PDF and Word.
- Italic and bold-italic font files. EAN-13 barcodes.
- Excel pictures and sheet headers. Word pictures for barcodes and shapes.
- Images continue on the next page. An oversized chart is scaled to the page.
- The sales order template, in Arabic and English, is the worked example.

## 1.4.0

First release of the report library.

- `.qrep` packages: `layout.xml`, embedded PNG/JPEG images, embedded TrueType
  fonts, shape layers, and design-time `data/sample.json`.
- Bands, groups, expressions (`SUM`, `TAFQEET`, `AMOUNTWORDS`), typed and
  calculated columns, tables, barcodes, QR codes, charts, and shape maps.
- Export to PDF, XLSX, and DOCX through `QudsReportEngine`.
- `PdfSaveOptions`, `SfntFont`, `BrokenLine`, and `ShapedGlyph` are part of
  this import, because export options, font faces, and laid-out lines use them.
- The visual designer is `package:quds_office_editor/quds_reports.dart`.
- `example/fill_qrep.dart` reads a `.qrep`, overrides its variables, feeds
  live data, and exports PDF, XLSX, and DOCX.
