# Changelog

All notable changes to `quds_office_engine` are documented here.

## Unreleased

- Preserve sparse paragraph/run formatting when importing a document with no
  style definitions; retain empty catalogs and avoid adding unreferenced Normal
  defaults, while exporting explicitly referenced built-in styles and edits.

- Preserve imported footnote/endnote separation exactly, including no space,
  multiple spaces and tabs; newly inserted notes still get one separator.
- Honor inherited `xml:space="preserve"` for whitespace-only text in the XML
  DOM so copied rich text and note spaces remain intact.

- Preserve imported `altChunk` blocks in body, table and note stories with
  immutable source XML and payload identity; rebind their relationships when
  moved or cloned between stories. Their external content remains unrendered.
- Allocate stable unique section-revision IDs when cloning imported sections,
  preserving their history and settings without duplicate schema identifiers.
- Add diagnostic probes that explicitly report remaining content-control
  wrapper loss and multiple/cross-paragraph bookmark-range loss.

- Join native comment replies and resolved state through the final paragraph's
  `w14:paraId`, retain anchors through comment copies/edits, allocate new anchors
  without collisions, and normalize MIME declarations when clearing comments.

- Add strict DOCX/XLSX/PPTX import, inspect, edit and repeated-save scripts with
  43 operations, authored semantic expectations and deliberate corruption checks.
  Explicit script formatting retains false/zero/default values as direct edits.

- Preserve imported list-level overrides and export explicit restart instances
  while keeping subsequent items attached to the restarted numbering sequence.
- Import only the first supported markup-compatibility Choice, or its Fallback,
  throughout Word body, table, header/footer and note stories.
- Retain imported section metadata, page numbering, grids, borders, custom
  columns and revision history through unrelated edits and section cloning;
  merge deliberate page and column edits without discarding other settings.
- Export referenced built-in styles missing from an imported style catalog,
  including known parent styles and references from notes and headers.
- Write line feeds as Word breaks, read run-contained line/page/column breaks,
  and use the standard extended-comments content type.

- Preserve one worksheet drawing relationship across absolute/relative target
  forms, emit SpreadsheetML chart transforms, and normalize pivot cache links.
- Keep imported font properties, number formats and borders during cell edits
  while serializing font properties in schema order.
- Convert stored column widths with the ISO maximum-digit-width formula;
  preserve untouched import precision and export edited pixel widths accurately.
- Preserve hidden/grouped columns, default column styles, best-fit/phonetic flags
  and width-less column definitions through edits and column insertion/deletion.

- Preserve imported PowerPoint rich text bodies and export scalar font/color
  edits; use proper paragraph boundaries for multiline shape text.
- Emit valid PowerPoint chart-frame transforms and transition durations, and
  allocate valid chart axis IDs for nonconforming imported identifiers.

- Preserve pictures and charts in default, first-page and even-page headers
  and footers; keep their relationships scoped to the owning story.
- Follow package relationships when saving nonstandard Word main, styles, notes
  and settings parts, so edits reach the part opened by external applications.
- Replacing or reordering Word media no longer overwrites payloads shared by
  other stories or retained package parts. Repeated saves reuse unchanged data.

- Fix the feature-showcase template detail band so its item table fits.
- Watermark text rotates as one marked line on every page.
- Imported DOCX footnote and endnote reference marks render as superscript.
  Notes attach to the page containing the reference glyph.

## 1.5.0

- A variable can ask for a value before preview, print, and export
  (`prompt`, `required`). The saved value stays the sample default.
- A report can hold more than one detail. Each `<Section>` has its own
  data set, group header, and group footer. A file with only section 0
  stays a single flat report.
- A crosstab pivots a data set by row field, column field, and value, using
  the existing aggregates. Empty cells show 0. More than 12 columns keeps
  the first 12 and warns.
- A subreport draws another template stored at `subreports/<name>.xml` in
  the same package, once, or once per row when it sits in a repeating
  detail. The child is shifted into the parent box. A child taller than
  the parent content area warns.
- A text element can hold `<Run>` children: bold, italic, size, color,
  underline, and a link. The link becomes a PDF URI annotation and a Word
  hyperlink.
- Fonts accept `italic.ttf` and `boldItalic.ttf` beside the regular and
  bold faces. Shear is used only when the real italic face is absent.
- Barcodes add EAN-13. Twelve digits gain a check digit; a wrong check
  digit warns.
- Excel export draws images and barcodes as pictures, and writes a text
  page header or footer into the sheet header. Word export draws a barcode
  as PNG, and a shape that is not a horizontal line as an image.
- An image taller than the page continues on the next page. A chart that
  does not fit moves to the next page; one taller than the content box is
  scaled to fit, with a warning.
- `PdfToOffice` reads a PDF file into DOCX, XLSX, or a freeform PPTX.
  DOCX keeps each line and each JPEG or PNG in a page-anchored box, turns
  a clearly ruled grid into a table, and turns vector bars, pie wedges, or
  a polyline into a native chart. A PDF outline or a dot-leader list becomes
  a table of contents, and link annotations become hyperlinks. XLSX keeps
  those tables and each chart's values, and writes other text as a single
  column.
  PPTX puts each page on a slide of positioned text boxes and PNG pictures.
  A page with no text layer is reported. Scanned pixels are not read.
- `CffRaster` fills a Type 2 charstring into a bitmap. It is not a general
  CFF text face for PDF.
- `GsubLigatures` applies OpenType GSUB lookup type 4 before line breaking,
  and the ligature glyph is subsetted into the PDF font.
- Redaction in remove-content mode clears `Tj` and hex strings whose text
  origin lies inside the rectangle, then paints black. Other operators stay.
- `PdfToolbox.stamp` and `numberPages` embed a supplied TrueType face and
  shape Arabic. Without those bytes they still use Helvetica and skip
  non-Latin text.
- `WordMailMerge.documentFor` repeats a table row that contains
  `MERGEFIELD` once per record, and otherwise repeats the body with a page
  break between records.
- Ready-made templates add a sales order (`feature_showcase_ar` and
  `feature_showcase_en`): prompted customer, purchase order, and delivery
  date, a rich confirmation, an italic note, an EAN-13 code, a nested
  delivery schedule, an item table, and a branch crosstab.
- JBIG2 arithmetic, symbol, and text regions are still not decoded.

## 1.4.0

- A shape map labels each region from an attribute, a calculated column on
  the shape table, or a formula in `labelField`. The formula may name shape
  attributes directly (`Name`, `Concat(Name, "\n", SHAPE_Area)`) as well as
  `Row.`.
- The map title, the region labels, and the legend each have their own font.
  `titleStyle`, `labelStyle`, and `legendStyle` set family, size, bold,
  italic, and color. An empty field inherits the chart font. An empty label
  color keeps the contrast color, white on a dark region. XML writes
  `titleFont`, `titleSize`, `titleBold`, `titleItalic`, and `titleColor`,
  and the same prefixes for `label` and `legend`.

## 1.3.0

- Report charts add percent-stacked columns, stacked area, column-and-line
  combo (with a secondary axis), waterfall, gauge, bullet, funnel, scatter,
  bubble, radar, heatmap, sparkline, and extruded (oblique 3D) columns, pie,
  and donut. Each has controllable depth, skew, hole, start angle, curve,
  markers, line width, axis bounds, target, bands, and waterfall colors.
  Scatter and bubble plot one point per row (`x`, `y`, and `size`). PDF and
  preview draw them as vectors. Word and Excel get a native chart where
  Office has one, and the nearest bar, line, or donut otherwise.
- Ready-made templates add a chart gallery (`chart_gallery_ar` and
  `chart_gallery_en`): every chart type, then a world shape map colored
  from a separate `countries` table (`Row.code` to `Row.revenue`).
- Shape maps color regions from the bundled country atlas or from a shapefile
  or GeoJSON stored in the report (`shapes/<name>.qmap`). The atlas matches
  an ISO alpha-2 or alpha-3 code and an English, Arabic, or French name.
  PDF and preview draw the polygons in Web Mercator, a min/max legend, and
  labels on the widest regions without overlap. A world-sized layer leaves
  Antarctica out of the frame. Word and Excel show a bar of the region values.
- A chart that crosses the bottom of a page moves to the next page together
  with the charts below it, so a row is not drawn on top of the one that moved.

## 1.2.0

Reports can do the same job as a mail merge, inside one file.

- A free-form Detail band (no table inside it) honors `newPageBefore` and
  `newPageAfter`. Each row of its data set starts on its own page. Preview,
  PDF export, and Word export all include those pages. Word writes a page
  break between the rows. A Detail band that contains a table still flows
  its rows down the page, so invoices are unchanged.
- Word's own mail merge is separate. `WordMailMerge` fills `«Field»` and
  `MERGEFIELD` tokens. `merge` fills one record, and `mergeAll` returns one
  document per record.
- New template family `class_certificate` (Arabic and English): one A4
  landscape certificate for every row of a `students` table. The sample is
  a class of eight students, so opening it and previewing shows eight pages.

## 1.1.0

- `ReportDiagnostic.target` says where a finding points
  (`ReportDiagnosticTarget`: band, element index, table column or cell,
  chart series or point, attribute, variable, data table and column,
  settings section), and parser and `validate()` paths for the same spot
  agree. `ReportDiagnostic.kind` (`ReportDiagnosticKind`) says what kind of
  problem it is, and `summary` drops the exception class name from parser
  messages.
- The parser warns "No Detail band" only when the template declares data
  tables, so certificates and vouchers no longer get it.
- Templates are files. A `.qrep` that holds a `template.json` manifest
  (`ReportTemplateManifest`: id, family, titles, descriptions, category,
  language, order) is a template. `ReportPackage.template` reads and writes
  the manifest. `ReportTemplateInfo.fromPackage` and
  `ReportTemplateInfo.decode` build a catalog entry from such a file, and
  `ReportTemplateInfo.manifest`, `order`, and `compare` describe and sort
  entries. `ReportTemplateInfo.package()` returns a file-based template's own
  package, fonts included.
- `ReportTemplates` is deprecated. The same 16 templates ship as `.qrep`
  files with `quds_office_editor` (`ReportTemplateLibrary`). The class keeps
  working until 2.0.
- `ReportParseResult.readable` is false only when the XML can't be read at
  all (malformed XML, an empty document, or a root that isn't
  `<QudsReport>`). A template with expression errors is still readable, so a
  designer can open it and show the errors.
- Aggregates over `item.` in template variables, such as
  `{{SUM(item.amount)}}` or `COUNT()`, now run over the detail band's data
  set. They returned 0 before, because variables had no rows in scope.
- Template variable names may contain dots, such as `stats.sum`. Expressions
  read them as `{{Variables.stats.sum}}`. Adds `ReportVariable.segments`,
  `folder`, and `leaf`, and `ReportGenerator.nestVariables`.
  `ReportVariable.isValidName` accepts dotted names. Validation, completion,
  and variable renames all handle dotted names.
- `ReportFontFileInfo.scripts` lists the writing systems a font covers,
  read from its `cmap`. The new `ReportScript` enum has a sample text for
  each script, plus `previewText` and `primary`, so a font picker can
  preview each font in its own script.

## 1.0.0

First stable release. The public API now follows semantic versioning:
breaking changes wait for 2.0. This release brings `.qrep` packages with
embedded images and fonts, report data schemas with calculated columns, 16
bilingual report templates, and a fidelity pass over Word, Excel, and
PowerPoint files saved by other office suites.

**Files saved by LibreOffice and other suites.**

- Word:
  - Numbering levels with `numFmt="none"` or an empty `lvlText` print no label. Writer ties every heading style to such an outline list, which used to show as an extra "1." before each heading.
  - Runs inherit bold, italic and color from their paragraph style chain. A run's own `w:b w:val="0"` still wins.
  - `w:b` / `w:i` with `false` or `off` turn the toggle off, in runs and in styles.
- Excel:
  - Header and footer sections keep their formatting codes (`&"Arial,Bold"`, `&12`). These codes used to swallow the section text.
  - PDF export expands `&D` and `&T`, drops font, size, color and toggle codes, and places the left, center and right sections on their own.
  - PDF export draws each cell at its font size, bold when the cell font is bold, and honors left / center / right alignment. Numbers under General alignment sit on the right, as in Excel.
- PDF: faux bold (used when no bold face is embedded) offsets its second pass by 5% of the em instead of 0.35 pt, so it reads as bold at every size.

**Calculated columns in suggestions.**

- `ReportCompleter` also suggests the columns `<DataSchema>` declares for a table (after `item.`, `items.`, `Data.items.`, `Group.rows.`), including calculated columns and tables with no sample rows yet.
  - Calculated columns show their expression as the detail.

**Word import and layout fixes ([#2](https://github.com/MohammedAsaadAsaad/quds_office_suite/issues/2)).**

- `WordLayoutEngine(measure:)` takes a `WordGlyphMeasure` that gives glyph widths when no font face is loaded, so line breaks match the host's text painting.
- Body text uses `fallbackWidthFactor`; the wider 0.72 em estimate is now limited to table cells and frames.
- Paragraph indents are subtracted once, not twice.
- Style numbering and indents (`w:numPr`, `w:ind` in `styles.xml`) now apply through `basedOn`, so heading and list styles get their markers.
  - `w:numId="0"` removes numbering.
  - `w:start` / `w:end` indents are read.
- Table styles from `styles.xml` apply `tblBorders` plus `firstRow` / `band1Horz` shading, following `w:tblLook`.
  - A table's own borders and cell fills win.

**Excel import fixes ([#3](https://github.com/MohammedAsaadAsaad/quds_office_suite/issues/3)).**

- `t="inlineStr"` cells keep their text: rich runs are joined, phonetic runs skipped.
- Shared formulas (`<f t="shared" si>`) expand from the master formula to every follower with `FormulaRefShift.shift`.
  - Relative references move, `$` parts stay fixed, and references pushed off the grid become `#REF!`.
- `FormulaDepGraph.recalculate` skips empty formulas.
  - It keeps a cell's cached value when the engine cannot compute the formula (`#NAME?` / `#ERROR!`), so recalc and save no longer overwrite Excel's result.
- `_xlfn.` / `_xlws.` function prefixes are ignored when evaluating; the formula text keeps them.
- Number formats support positive;negative;zero sections, thousands grouping, `,` scaling, `%`, quoted literals, `[Red]` and `[$€-407]` currency tokens.
  - `0%` no longer shows two decimals.
- Charts without a value cache are drawn from their `c:val` / `c:cat` ranges, on the same sheet or another one.
  - `SmlDrawing` gains `sourceSheetName`, `labelsFromA1` and `labelsToA1`; `SheetChartData.fromSeries` pairs values with category labels.

**PowerPoint import fixes ([#4](https://github.com/MohammedAsaadAsaad/quds_office_suite/issues/4)).**

- Only `p:pic` and shapes with a `blip` fill become pictures. Text boxes no longer turn into empty "Picture" boxes because of an `xfrm` or a shadow.
- `off` / `ext` are read only inside the shape's own `xfrm`, so `a:extLst/a:ext` no longer zeroes a shape's size.
- `p:ph` is read into `PmlShape.placeholder`, `placeholderType` and `placeholderIndex`.
- Slides follow their `slideLayout` → `slideMaster` → `theme` relationships:
  - Placeholders without their own `xfrm` inherit the layout's geometry (matched by `idx`, then by type), then the master's.
  - `PmlSlide.layoutName` is set.
  - `PmlPresentation.layouts` lists the deck's layouts, without their prompt text.
- `a:schemeClr` / `a:sysClr` colors resolve through the theme and the master's `p:clrMap`, with `lumMod`, `lumOff`, `shade` and `tint`.
  - `p:style` `fillRef` / `lnRef` / `fontRef` give default fill, outline and text colors, so PowerPoint autoshapes keep their fill.
  - `gradFill` / `pattFill` use their first color.
- Slide order follows `p:sldIdLst` through `presentation.xml.rels`, and slide parts no longer have to be named `slide1..n`.
  - `SlideSerializer` writes the real relationship ids into `p:sldIdLst`.
- Morph transitions keep an empty fill instead of blending through blue.

**`.qrep` packages.**

- A `.qrep` file is now a ZIP holding `layout.xml` (the `<QudsReport>` template) and pre-saved images under `images/<name>.png|jpg`.
  - A stored `mimetype` entry (`application/vnd.quds.qrep+zip`) comes first.
- `ReportPackage`:
  - `encode()` and `ReportPackage.decode(bytes)`; `decode` also opens legacy plain-XML `.qrep` files.
  - `keyFor(fileName)` derives unique image keys; `isValidKey` checks a name.
  - PNG / JPEG only (`ReportImageFormat.sniff`); each entry is capped at 64 MB.
  - Errors raise `ReportPackageException`.
- `QudsReportEngine.fromPackage(bytes, {images})` uses the embedded images; host `images:` win on name clashes. `engine.toPackage()` writes a package.

**Embedded fonts in `.qrep` packages.**

- Packages carry TrueType families under `fonts/<family>/regular.ttf|bold.ttf`, so a report exports with the faces it was designed with.
- `ReportPackage.fonts` (`Map<String, ReportFontFiles>`), `fontRegistry({base})`, `mergeFonts(base, embedded)` and `isValidFontFamily`.
  - Host families come first and win on name clashes; the host registry is not modified.
  - Every font is checked when it is written or read.
- `QudsReportEngine.fromPackage` registers the embedded fonts; `embeddedFonts` keeps them so `toPackage()` writes them back.
- `ReportFontFile.inspect(bytes)` / `inspectWith(read)` return `ReportFontFileInfo` (family, weight, italic) from the `name`, `OS/2` and `head` tables without parsing glyphs.
  - They throw `ReportFontException` for `.ttc` collections, CFF (`.otf`) outlines, missing tables, and fonts whose `fsType` forbids embedding.

**Report data schema and sample data.**

- `<DataSchema>` in the layout declares fields and tables with typed columns (`text`, `number`, `boolean`, `date`). This is `ReportTemplate.dataSchema` (`ReportDataSchema`, `ReportDataTable`, `ReportDataColumn`, `ReportDataField`).
  - Calculated columns (`expression="qty * price"`) are evaluated for every row at export; bare names refer to the row's columns.
  - Exports coerce values to the declared types. `engine.prepare(data)` returns the record the layout sees.
  - The parser warns about unknown types, duplicates, missing names, and broken formulas.
- Packages can carry design-time sample data as `data/sample.json` (`ReportPackage.sampleData`, `engine.sampleData`). Exports only use it when the host passes it.
- `ReportData`: dotted-path `get` / `set` / `remove` / `setTable` / `addRow` / `rows`, deep `merge`, and JSON round-trip with ISO dates. `ReportDataType` handles inference and coercion.
- `ReportCsv.parse` / `rows` / `write`: delimiter detection (`,` `;` tab), quotes, BOM, and typed columns.

**Named elements and runtime data.**

- Templates keep element names unique: `uniqueElementName`, `assignElementNames`, `elementNamed` (case-insensitive), `duplicateElementNames`, `isValidElementName`.
- `QudsReportEngine`:
  - Host data: the `data` constructor parameter (`ReportData`) is merged under the map passed to each export.
  - `export(format, {data})` / `exportSync`. `ReportExportFormat` moved here from the editor.
  - Element access by name: `elementNames`, `element`, `elementAs<T>`.
  - Setters by name: `setText` (with `literal`), `setImage`, `setBarcode`, `setTableRows`, `setChartRows`, `setChartPoints`, `setVisible`.
  - An unknown name or wrong type throws `ReportElementException`.

**Bilingual, categorized templates with saved images.**

- `ReportTemplates.all` now has 16 templates: eight families, each with an Arabic (RTL) and an English version.
  - New families: product catalog (a photo per row) and certificate of appreciation.
  - New English versions of the VAT invoice, account statement, receipt voucher and inventory report, and an Arabic version of the commercial invoice and the sales dashboard.
  - Existing ids are unchanged.
- `ReportTemplateInfo` gains `family`, `language` (`ReportTemplateLanguage`), `familyTitle` / `familyTitleAr`, `strings`, `images()` and `package()`.
  - Both versions share one layout with `[[key]]` tokens filled from per-language strings.
- `ReportTemplates.families`, `variants`, `find`, `counterpart` and `inCategory`.
- `ReportTemplateCategory` gains `hr` (Human resources) and bilingual `title` / `titleAr` / `titleFor`.
- Templates carry pre-saved PNG images (logo, stamp, signature, seal, product photos) in their package.
  - The images are drawn by the new `ReportTemplateArt` (`logo`, `stamp`, `signature`, `seal`, `product(ReportProductArt)`), an anti-aliased pure-Dart rasterizer.
- `AMOUNTWORDS(amount, 'USD', 'en'|'ar')` and the `words:USD` format spell amounts in English (`EnglishWords`, 21 currencies).
- The `dateAr:` format uses Arabic month and day names (`10 أكتوبر 2026`).

**Fixes.**

- Elements that share a top edge now paint in document order. Before, an unstable sort could draw a filled shape over the text placed on it (for example, the receipt voucher amount).
- Raw deflate now emits overlapping matches and caps hash-chain walks, so long runs (for example, transparent PNG rows) compress fast and much smaller.

**Docs.**

- The README links to the Quds Report Studio installers for Windows and Linux, which design `.qrep` reports for this engine. The pub.dev screenshots include the studio and the new templates.

## 0.6.0

**Band report engine (`quds_reports.dart`).**

- `.qrep` templates:
  - `QudsReportXmlParser` gives line:column diagnostics.
  - `QudsReportXmlWriter` round-trips templates.
  - The mutable `ReportTemplate` model is built for designers.
- `QudsExpressionEngine`:
  - `System.*`, `Variables.*`, and `Data.*` paths; arithmetic, comparisons, and aggregates.
  - Formats such as `currency:LYD` and dates.
  - Arabic `TAFQEET(amount, code)` (`ArabicTafqeet`).
- Generator:
  - Report, page, and group headers/footers, detail bands, and repeating tables.
  - `canGrow` text, page splitting, and `System.TotalPages`.
  - BiDi, Arabic shaping, and RTL x mirroring (`mirrorRtl`).
- `QudsReportEngine.fromXml(xml)` exports with `exportToPdf`, `exportToExcel`, and `exportToWord`.
- `ReportMockData.infer` builds preview data from a template's bindings.
- Charts (`<Chart>` / `ReportChartElement`):
  - Types: bar, horizontal bar, stacked bar, line, area, pie, donut.
  - Data: a dataset grouped by a category expression with `sum`/`avg`/`count`/`min`/`max`/`first`/`last`, sorting, and top N; or static `<Point>` values.
  - PDF and preview draw vectors (`ReportPathPrimitive`); RTL templates mirror the plot.
  - DOCX and XLSX embed native DrawingML charts; XLSX adds the data table.
- `ReportTemplates.all`: six ready-made templates with sample data (Arabic VAT invoice, English invoice, sales dashboard, account statement, inventory, receipt voucher).
- `ReportCompleter`: suggestions inside `{{ }}` and expressions: functions with signatures, `Data`/row fields from the preview data, `System`/`Group`/`Variables`, format specs after `|`, and currency codes in `TAFQEET`/`FORMAT`.
- Typed template variables (`<Var name type value format description/>`): `text` (may hold `{{ }}`), `number`, `boolean`, `date` (ISO, `today`, `now`), `list` (`;`-separated), and `expression`. Later variables can use earlier ones, host `variables:` still override, and the validator flags values that don't fit their type.
- `XlsxSheetBuilder.addChart` anchors a DrawingML chart part on a sheet.
- XLSX builder `style(rightToLeft:)` emits `readingOrder="2"`.
- `ReportCompleter.formats` exposes the format specs (with samples) that the designer offers as presets.
- XLSX and DOCX report exports: transparent text on a filled shape takes the shape's fill (white titles on a colored banner stay readable). XLSX chart placeholder rows get explicit heights, so the chart no longer overlaps its data table in LibreOffice.
- `tool/dump_report_shots.dart` renders every bundled template to PDF (and the sales dashboard to XLSX/DOCX through LibreOffice) for the README gallery.
- Limits are listed in `docs/STANDARDS.md`.

**PDF fidelity.** Five waves: OpenType marks, appearances, page graft, AcroForm write,
and a first slice of “files people send”.

- GPOS LookupType 4 (MarkToBase, including type-9 extensions). Combining
  marks use font anchors for `paintDx` / `paintDy`; the previous
  “center of advance” placement is the fallback.
- FreeText `/AP` (then Tx on fill) is a Form XObject through `LineBreaker`
  + Arabic shaping + a glyf Identity-H subset. Helvetica is not used for
  non-Latin text. `/NeedAppearances` stays if generation cannot embed a face.
- `PdfFile.appendPages` / `mergeFrom` rebuild via `PdfPageGraft`, so fonts
  and images survive. `PdfToolbox` remains the batch assembler.
- `pdf_widgets` `TextField` / `Checkbox` / `Radio` still draw marks. Pass
  `acroForm: true` (or use `ChoiceField`) to emit real `/Tx` `/Btn` `/Ch`
  fields on the writer `PdfDocument`.
- `/JBIG2Decode` decodes MMR generic regions (scanner dual-tone) with the
  same size cap as other filters. Arithmetic coding, symbol dictionaries,
  and JPX stay typed-unsupported placeholders.
- Signature fields: ByteRange coverage plus CMS `SignedData` `messageDigest`
  match (`valid` / `invalid`). Unknown digest algorithms are `unsupported`.
  Creating signatures and trusting a system root list are still out.

## 0.5.3

- High-value `pdf_widgets`: `PageNumber`, `HeaderFooter`, `SignatureLine`,
  `KeepTogether`, `Badge`, `Callout`, `Steps`, `DataGrid`, `Barcode` (Code128),
  `QrCode`, and `SvgImage` (path subset).
- Bilingual widget catalog via `pdf_widgets_samples.dart` /
  `example/pdf_widgets_catalog.dart`.
- Skip invisible BiDi marks (`LRE`/`PDF`/`LRM`/…) so `intl` dates do not
  paint as `.notdef` boxes.
- Reorder Arabic by grapheme cluster so tashkeel (ضمة on `أُنشئت`) stays
  on its letter after PDF export.

## 0.5.2

- Do not mid-cut Arabic chart axis labels (keeps joining forms intact).

## 0.5.1

- Soft-wrapped `Text` keeps the full max width so RTL `start` / `justify`
  paint on the start edge (headers, bullets, paragraphs).
- `TextAlign.justify` origins follow direction instead of always left.
- `Bullet` uses `TextAlign.start`. Chart titles follow direction; long axis
  labels are shortened to fit their slot.

## 0.5.0

**Report templates that look different, not only read different.**

- `pdf_templates.dart` ships **100+** classified report templates across
  commerce, finance, people, operations, narrative, data, education,
  property, logistics, and programs. Pick a named class
  (`InvoiceTemplate`, `PurchaseOrderTemplate`, …) and keep developing it.
- **`SheetSkin`** is the composition surface: invoice bar, receipt slip,
  letterhead, certificate frame, payslip split, checklist boxes, route
  endpoints, voucher, grades, identity panel, notice strip, journal,
  comparison columns, and more. Labels stay language. Direction stays
  layout. `TemplateTheme.copyWith` stays brand.
- `TemplateCatalog.all` / `inCategory` index every entry.
  `TemplateSuite.demo` writes a sample page. `joinTemplateFiles` joins
  English and Arabic into one PDF.
- `Table.fromTextArray` defaults to `AlignmentDirectional.topStart`, so
  Arabic table cells pin text to the start edge in RTL.
- `pdf_widgets` Flutter twins: `Transform`, clips, `FractionallySizedBox`,
  `IntrinsicHeight`, `CustomPaint`, `ListTile`, directional insets, and
  more. `TextOverflow.ellipsis` cuts a line.
- `OfficeColors.red` and other common names are `RRGGBB` strings for
  `OfficePalette` without touching Flutter `Colors`.

## 0.4.0

PDF is a file you can assemble, not only a file you can open or export.

- `PdfToolbox` grafts a new PDF 1.7 so fonts and images survive merge, extract,
  split, reorder, remove, reverse, insert, and mix. Range groups are
  1-based (`1-3`, `8-10`, `15`). One source may contribute several groups.
- `/Rotate` is a clockwise quarter-turn added to the existing value. It does
  not rewrite MediaBox. `PdfPageView` maps view space to unrotated crop space.
- Appearance overlays: Helvetica stamp, page numbers, Bates, and CropBox crop.
  Stamp is Latin only. A shaped watermark belongs on `pdf_widgets`.
- `pdf_widgets` watermark is one rotated string (ActualText + visual-order
  glyphs) so Arabic stays joined.
- Office slide export can stack two slides on one page (`slidesPerPage: 2`).
  The default remains one slide per page.
- `ArabicShaper.nominal` maps presentation forms back to isolated letters.
- Package documentation covers the full public surface, including honest
  limits (no OCR, no CMS verify, no certified PDF/A, no content-stream reflow).

## 0.3.1

- Keep `pdf_widgets` on its own library import
  (`package:quds_office_engine/pdf_widgets.dart`) so Flutter hosts do not see
  colliding `Text` / `TextStyle` / `Widget` names from the main barrel.

## 0.3.0

**Office + PDF in one pure-Dart engine.** This release makes PDF a first-class
citizen alongside DOCX / XLSX / PPTX — open, compose, and export without Flutter.

### PDF as a file (`PdfFile`)
- Open ISO 32000 packages: xref table/stream, object streams, incremental
  updates, filters (including CCITT G3/G4), encryption/password paths.
- Display list for page paint (`b`/`b*`, graphics state, Type 3, axial/radial
  shadings, OCG, SMask→RGBA, CMYK/ICCBased images).
- Text extract (WinAnsi / MacRoman / PDFDoc, Standard-14, `/ActualText`,
  `/StructTreeRoot` reading order).
- Typed honesty for signatures (`ByteRange` status), PDF/A detection (not
  certification), and unsupported codecs (JBIG2/JPX, in-engine CFF raster).

### PDF widgets (`pdf_widgets.dart`)
- Flutter-like constraint layout in pure Dart: `Document`, `Page` /
  `MultiPage`, `Table` / `TableBorder` / column widths, flex, text, media.
- Real bold faces via `Document.fontBold` (Type0 `/F3`), not faux stroke.
- Table cells expand to full width×row height (package:pdf-style fills).
- Synchronous `Document.save()` → native `PdfDocument` writer bytes.

### Office (unchanged strengths)
- Round-trip DOCX / XLSX / PPTX, formulas, BiDi/RTL, isolate open/save.
- `OfficePdfExport` still compiles Word / Excel / PowerPoint to PDF 1.7.

### Breaking
- Word widget DSL removed. Use `pdf_widgets` for PDF layout and
  `DocxDocumentBuilder` for DOCX.

## 0.2.0

- English package documentation, Word widget DSL (later removed), and
  PDF export polish.

## 0.1.0

- First public release: Office builders, models, formulas, BiDi, PDF export.
