# Changelog

All notable changes to `quds_office_editor` are documented here.

## Unreleased

- Paint explicit native Word frame outline widths, preset/custom dashes, caps,
  joins and inset alignment. Keep selection chrome separate from the document
  stroke. New frames preview their serialized one-point outline; imported
  omitted widths retain the existing approximation. Native pixel regressions
  and three reviewed outline-only golden corrections cover repeated saves.

- Commit active Word, Sheet and Slide drafts through `commitPendingEdits()`
  and both save APIs. Cell and slide text changes advance the content revision
  immediately, including edits during an asynchronous save; focus, caret and
  unchanged text stay clean. Cancel restores the draft without clearing other
  unsaved changes, and committed drafts remain undoable.

- Expose a content revision that advances immediately for pending note-pane
  edits as well as commands and history. Saves commit pending note edits before
  encoding so hosts can guard asynchronous completion against a later edit.

- Preserve native bookmark endpoints through run formatting, paragraph splits,
  inside-range edits, native clipboard insertion and undo/redo. Invalid partial
  range copies and duplicated native identities reject on export rather than
  losing markup; three actual editor exports are checked independently.

- Word, Sheet and Slide canvases dispose decoded images and suppress late
  callbacks after close. Two deterministic cache lifecycle regressions cover
  pending and ready image disposal.

- Native block content controls keep their metadata through inside edits,
  paragraph splitting, undo/redo and repeated saves. Splitting an inline-only
  control is rejected before changing the document or undo history.

- Toggling off an imported list suppresses style-based numbering through
  undo/redo and save/reopen; toggling it back on restores a list normally.

- Splitting a heading or a restarted list retains the first paragraph's anchor
  and restart without duplicating them on the new paragraph, including undo/redo.

- Relayout a replaced Word viewport so scrolling to later pages does not leave
  an empty canvas. Three reviewed page goldens cover first, even and default
  header/footer pictures before and after an asynchronous save.

- Fix the feature-showcase template detail band so its item table fits.
- Selection highlighting is visible on white pages.
- Header and footer edits force a full relayout so typed text lands in the
  correct band.

## 1.6.0

Built on `quds_office_engine` 1.5.0 and `quds_reports` 1.5.0.

- The report toolbox adds a section, a crosstab, and a subreport. The
  inspector edits their fields. Variables have "ask before preview" and
  "required".
- Ctrl+B toggles bold on the selected run of a rich paragraph.
- Bundled Liberation faces include italic and bold italic, and an embedded
  family stores those two slots beside regular and bold.
- The Excel formula bar shows the selection address or the matching defined
  name, and choosing that name selects its range.
- Word revisions draw a translucent mark in addition to the underline or
  strike.
- Ready-made templates add the sales order family, Arabic and English.

## 1.5.0

Built on `quds_office_engine` 1.4.0 and `quds_reports` 1.4.0.

- `package:quds_office_editor/quds_reports.dart` is the report designer and
  the report engine in one import: canvas, inspector, toolbox, preview, data
  explorer, bundled fonts, ready-made templates, and `QudsReportEngine`.

## 1.4.0

Built on `quds_office_engine` 1.4.0.

- Insert tools live in a side toolbox. Each tool shows a hover card with its
  name, a short description, and a small drawing. The map is its own tool.
- A shape map's choices are dropdowns. Region labels ask which field to draw,
  including calculated and constant columns from the shape table. A long menu
  scrolls, and typing filters it.
- Title, region labels, and the legend each have a format button. It opens a
  box for family, size, bold, italic, and color.
- The data explorer edits an imported shape layer as a table, so a calculated
  column can be the region's label. An imported shape file can be removed.

## 1.3.0

Built on `quds_office_engine` 1.3.0.

- The chart inspector lists the new types (including the scatter chart) and
  the plot controls that apply to the selected type: depth and skew for
  extruded charts, hole and start angle for pies and gauges, markers and
  curves for lines, axis bounds, a target and bands for gauges and bullets,
  and per-series style, secondary axis, X, and size.
- Bundled templates include a chart gallery (`chart_gallery_ar` and
  `chart_gallery_en`) with every chart type and a country shape map bound
  to its own `countries` table.
- A shape map chooses the world atlas or an imported shapefile, GeoJSON, or
  `.qmap`. **Import shapes…** embeds the file in the `.qrep` and points the
  region key at the table column that matches it (a district code, for
  example). The inspector also sets the low, high, and empty colors and
  whether wide regions are labeled.
- Calculated columns stay in their table. A formula in that table can name a
  sibling column directly (`price`) as well as `item.price`.

## 1.2.0

Built on `quds_office_engine` 1.2.0.

- Bundled templates include class certificates (`class_certificate_ar` and
  `class_certificate_en`). This is the report form of a mail merge: the
  Detail band is bound to the `students` table with **New page before**, so
  preview and export show one certificate page per student. The sample class
  has eight students.

## 1.1.0

Built on `quds_office_engine` 1.1.0.

- Two-finger zoom on the design canvas and the preview: a trackpad pinch or
  two fingers on a touch screen zoom around the point between the fingers.
- Problems panel. `ReportDesignerController.problemsOpen` shows it under
  the canvas (`QudsReportDesigner.problemsHeight`, drag to resize). It lists
  `controller.problems`: live parser and `validate()` findings, errors
  first, with each problem's kind, place, and a hint on how to fix it.
  Clicking a problem calls `revealDiagnostic`, which selects the element or
  band and scrolls the canvas to it, or opens the variable or data column,
  and marks the inspector property to fix (`highlightProperty`).
  `ReportProblemsPanel` is exported. `clearLoadDiagnostics` forgets what
  the parser corrected when the file was opened. Diagnostic messages are
  translated (`ReportDesignerStrings.diagnostic`).
- The 16 ready-made report templates ship as `.qrep` files in `templates/`
  (package assets). `ReportTemplateLibrary.bundled()` reads them in menu
  order. `QudsReportDesigner.templates` is now nullable, and null (the new
  default) offers the bundled files. `loadTemplate` loads a template's
  embedded fonts too.
- Embedded images can be replaced. Click a thumbnail on the inspector's
  Images tab, or use **Replace image…** on an image element. The image keeps
  its name, so every element showing it updates on the report at once
  (`ReportDesignerController.replaceImage`, `importReplacement`; undoable).
- `ReportDesignerController.fromXml`, `loadXml`, and `loadPackage` open a
  template that has expression errors instead of throwing, and list the
  errors in the new `loadDiagnostics`. A report saved with a typo, such as a
  variable `{{sum(item.qty}}`, can be reopened and fixed. They still throw
  `ReportTemplateException` when the XML can't be read.
- The report inspector has been redesigned:
  - Actions are icon buttons with tooltips instead of text rows.
  - The Variables tab is an explorer. Dotted names (`stats.sum`) appear as
    folders you can collapse, and the selected variable is edited below the
    tree (`selectedVariablePath`, `variableFolders`).
  - Images appear as cards with a thumbnail.
  - Embedded fonts appear as cards with a live preview, a default star, and a
    remove button.
  - Every font field opens a picker of installed fonts. It previews each font
    in its own script (Arabic, Thai, and so on), and choosing a font embeds
    it. Hosts report scripts through the new `ReportDeviceFontScripts`
    interface. `fontPreviewText` gives the sample text.
- The designer can be localized. `ReportDesignerStrings` ships English and
  Arabic. Pass it as `QudsReportDesigner.strings`, or let the designer follow
  the app's locale. In Arabic, the inspector, data explorer, menus, and status
  messages are mirrored right to left.
- `QudsReportDesigner.onPrint` adds a **Print** toolbar button and Ctrl+P.
  It hands the host the report as PDF, rendered with the preview data, so the
  host can show a print dialog. Adds `ReportToolbarIcon.print`.
- Dark `OfficeTheme`s are supported. The page stays white, while the
  inspector, data explorer, popups, and canvas grid use colors that suit the
  dark chrome.

## 1.0.0

First stable release, built on `quds_office_engine` 1.0.0. The public API
now follows semantic versioning: breaking changes wait for 2.0. This release
brings the report designer's data explorer, embedded images and fonts,
inspector tabs, and fidelity fixes for Word, Excel, and PowerPoint files.

- Depends on `quds_office_engine: ^1.0.0`.

**Calculated columns in report suggestions.**

- The report designer's `{{ }}` and expression suggestions (text, properties, variables) use the sample data as the report sees it: schema types applied and calculated columns filled in.
  - A new calculated column such as `calc1` is offered right away, with its computed value.

**Word, Excel and PowerPoint fidelity fixes ([#2](https://github.com/MohammedAsaadAsaad/quds_office_suite/issues/2), [#3](https://github.com/MohammedAsaadAsaad/quds_office_suite/issues/3), [#4](https://github.com/MohammedAsaadAsaad/quds_office_suite/issues/4)).**

- Word:
  - The Word controllers lay out with the same Flutter text metrics they paint with (`PaintRunText.advanceOf`), so lines no longer run past the column.
  - Layout runs again when system fonts change.
  - `WordEditorController.refreshMetrics()` re-measures on demand.
- Slides:
  - `QudsSlideEditor` now places `navigationBuilder` (a 220-pt pane shown when `showNavigationPane` allows it) and `notesPaneBuilder`; both were ignored.
  - An empty `PmlShape.fillColor` paints no fill instead of the `4472C4` fallback.
    - Text on unfilled shapes contrasts with the slide background.
    - Empty placeholders get a faint outline while editing.
  - The stage honors `PmlShape.textColor`.
  - Text boxes shorter than a line (`cy="0"`) grow with their text instead of being clipped away.

**Embedded report images in `.qrep` packages.**

- Packages:
  - `ReportDesignerController.fromPackage`, `loadPackage` and `toPackage` read and write the zipped `.qrep` (layout + images).
  - Legacy plain-XML files still open.
- Images:
  - `addImage`, `insertImage`, `renameImage` (repoints `<Image source>`), `removeImage` and `imageNames`.
  - Image edits are part of the undo history.
  - Loading or replacing a template now replaces `images` too.
- `QudsReportDesigner.onPickImage` (`ReportImagePicker`) turns on the import buttons:
  - The inspector's **Images** tab lists name, type, pixel size and file size, with Insert / Remove.
  - Image elements get an **Import image…** button, and their Source field suggests the embedded names.
  - Files that are not PNG / JPEG are reported in the status bar.

**Inspector tabs and resizing.**

- Tabs:
  - The inspector has **Properties**, **Variables** and **Images** tabs (`ReportInspectorPage`, `controller.inspectorPage`), with count badges.
  - Variables and images no longer crowd report settings.
  - Selecting an element or a band returns to Properties.
  - Variable edits apply even while an element is selected.
- Resizing:
  - A splitter between the canvas and the inspector resizes it; double-click restores `inspectorWidth`.
  - New parameters: `initialInspectorWidth`, `minInspectorWidth`, `maxInspectorWidth` and `onInspectorWidthChanged`.

**Embedded fonts.**

- Controller:
  - `embeddedFonts` are saved in the `.qrep` by `toPackage`; `fromPackage`, `loadPackage`, `loadXml(fonts:)` and `replaceTemplate(fonts:)` read them.
  - `effectiveFonts` (host `fonts` plus the embedded families) drives the preview, canvas charts and exports.
  - `addFont(bytes)` fills the regular or bold slot of the family the file declares; `embedFont(family, files)`, `removeFont`, `importFonts()`, `embedDeviceFont(family)` and `embeddedFamilies`.
  - Font edits are part of the undo history; italic, CFF, collection and no-embedding fonts are refused with `ReportFontException`.
  - `fontFamilies` presets include the host and embedded families.
- Inspector:
  - A **Fonts** tab (`ReportInspectorPage.fonts`) lists embedded families with faces, size, a **Report default** switch, usage count and Remove.
  - With `deviceFonts`, an **On this device** list with search and **Embed** buttons. Typing an installed family into a font field embeds it.
  - Tabs fall back to icons when the inspector is too narrow for their labels.
  - New read-only property kind `ReportPropertyKind.note`.
- `QudsReportDesigner`:
  - `onPickFont` (`ReportFontPicker`) and `deviceFonts` (`ReportDeviceFonts`) parameters.
  - Embedded families are loaded into Flutter (`FontLoader`) so the design canvas draws them; the canvas re-lays text when system fonts change.
  - Import results and errors (`controller.notice`) show in the status bar.

**Data explorer.**

- `ReportDataExplorer` / `RenderReportDataExplorer`: a painted data grid that F6 or the toolbar's **Data** button (`ReportDesignMode.data`, `toggleData`) shows in place of the canvas.
  - The sidebar lists Fields and tables with row counts, plus **+ New table**.
  - The grid has typed column headers, a row-number gutter, tinted calculated columns, formatted values, scrollbars, and a right-click menu (`ReportDataContextHit`).
  - Cells are edited in place: double-click, F2, Enter, or typing. Enter and Tab commit and move; values are checked against the column type. Ctrl+C / Ctrl+V and Delete work on cells and rows.
- Controller:
  - `sampleData` is saved in the `.qrep` (`data/sample.json`) and used by the preview after host `mockData`. Every edit is undoable.
  - Explorer views: `dataTables`, `dataTable`, `selectDataTable`, `selectDataCell`, `setDataCell`, `addDataRow`, `removeDataRows`.
  - Columns: `addDataColumn` (including calculated columns with `expression`), `renameDataColumn`, `removeDataColumn`, `setDataColumnType`, `setDataColumnExpression`, `setDataColumnFormat`.
  - Tables and fields: `addDataTable`, `removeDataTable`, `addDataField`, `renameDataField`, `setDataField`, `setDataFieldType`.
  - Imports: `importDataText(fileName, text)` takes CSV, TSV, or JSON; `importDataFile()` uses the host picker.
  - Renaming a column or field rewrites its bindings (`item.qty`, `SUM(items.qty)`, `Data.customer`) and the formulas that use it.
  - Types and formulas are written to the template's `<DataSchema>`. Host `mockData` is shown read-only.
  - Templates loaded from the menu bring their data as sample data.
- The inspector shows table, column (name, type, formula, format, description), field, and sample-data properties in data mode.
- `QudsReportDesigner.onPickData` (`ReportDataPicker`) turns on **Import CSV / JSON…**.

**Unique element names.**

- Elements get a unique name when they are added, pasted, or loaded (`text1`, `table2`, …), so code can reach them with `QudsReportEngine.setText`, `setTableRows`, `elementAs`, and the other named-element setters.
- Duplicate and invalid names typed in the inspector are rejected with a notice. An empty name generates a fresh one.
- `ReportExportFormat` now comes from `quds_office_engine`, and the editor re-exports it.

**Categorized, bilingual templates.**

- The designer's Templates menu groups families under category captions; picking a family asks for العربية or English.
- `loadTemplate` loads the template's pre-saved images with its sample data, so logos, stamps, signatures and product photos show in the canvas, preview and Images tab.

**Docs.**

- The README links to the Quds Report Studio installers for Windows and Linux, which are built on `QudsReportDesigner`. The pub.dev screenshots add the template catalog, the data explorer and the Fonts tab.

## 0.6.0

**Report designer (`QudsReportDesigner`).** Depends on `quds_office_engine` **0.6.0**.

- `ReportDesignerController`:
  - Select, move, resize, and nudge; snap to grid and guides.
  - Align, distribute, and same size; z-order; clipboard and duplicate.
  - Add and remove bands; undo and redo.
  - Typed property inspector rows; inline text editing.
  - Inferred mock data.
- RenderBox surfaces (no text fields, no scroll widgets):
  - `ReportDesignerCanvas`: bands, rulers, handles, marquee, tool creation, and cross-band drag.
  - `ReportInspector`.
  - `ReportToolbar` with vector icons.
  - `ReportPreviewSurface`: a paginated live preview painted from the engine's glyph outlines.
- Context menus; Design/Preview toggle (F5).
- Export to PDF, XLSX, or DOCX through `onExport`.
- Chart tool: creates a data-bound bar chart; the inspector edits type, data, aggregation, sort, top N, series, static points, and styling. The canvas draws the chart with the engine renderer and sample values.
- Templates button: loads one of `ReportTemplates.all` with its sample data, or a blank report (`ReportDesignerController.loadTemplate`).
- Autocomplete while editing text on the canvas or inspector values: a painted popup under the caret. ↑/↓ choose, Enter/Tab insert, Esc closes, Ctrl+Space opens it anywhere. Functions insert `NAME()` with the caret inside.
- Template variables: a Variables toolbar menu inserts `{{Variables.x}}` at the caret or as a new text box. With nothing selected, the inspector adds, renames, retypes, formats, and removes variables. Values are checked against the type, and renaming a variable rewrites its references.
- The on-canvas text editor paints on the element's fill and switches to black or white text when the element's color would be unreadable (WCAG 4.5:1).
- `ReportLayoutPainter.paintPrimitives` paints any primitive list, including chart paths.
- `ReportBundledFonts` loads the package's Liberation and Noto Naskh Arabic faces into a `ReportFontRegistry`.
- Inspector redesign (still one RenderBox):
  - Collapsible sections, a title badge with the element kind and band, and diagnostics with severity icons.
  - Controls picked from property metadata: switches for booleans, segmented icon or text choices, dropdowns, ±steppers (↑/↓ while editing, Shift for ×10), preset combos (font sizes, families, format samples), paired X/Y and Width/Height fields, and a B/I/U glyph row.
  - A painted color popover: no color, the template palette, Office theme tints and shades, and standard colors.
  - `ReportProperty` gains `hint`, `presets`, `step`, `min`, `pair`, and `glyph`. `ReportDesignerController.stepProperty` / `steppedValue` snap to the unit's step and clamp to the minimum.
- Standalone desktop app [`apps/quds_report_studio`](https://github.com/MohammedAsaadAsaad/quds_office_suite/tree/main/apps/quds_report_studio) replaces the old example entry point. It has frameless window chrome (move, resize, maximize), New/Open/Save/Save as, recent files, and an unsaved-changes guard.

**Fixes.**

- Chart visuals reserve a strip for the bottom legend, so it no longer overlaps the category labels.
- `PdfViewerController` zoom animation starts on its first frame. Calling `fitPage` / `setScale` from a tap no longer trips the scheduler assertion.
- `RenderWordCanvas.windowForPagePoint` maps a page point back to widget coordinates (the inverse of hit-testing), so hosts and tests can target page content past the rulers.
- Analyzer clean-up across the package and example (initializing formals, unnecessary casts, `onReorderItem`).
- The example studio theme uses Liberation Sans with Noto Naskh Arabic / Tajawal as fallbacks, so Latin chrome text no longer depends on host fonts.

## 0.5.1

**PDF viewer options and events.**

- `PdfViewerOptions` on `QudsPdfViewer` / `QudsPdfEditor`: fit policy, zoom
  clamps, swipe enable/axis, page fling/snap, night invert, background,
  scrollbar, password, `preventLinkNavigation`.
- Callbacks: `onViewCreated`, `onLoadComplete`, `onPageChanged`, `onRender`,
  `onError`, `onPageError`, `onLinkHandle`, `onDraw`.
- Horizontal page stack, night-mode raster invert (viewer), and snap/fling on
  the canvas.
- Depends on `quds_office_engine` **0.5.3** (Arabic tashkeel on the correct
  letter, BiDi format marks skipped, new `pdf_widgets`).

## 0.5.0

**Studio gallery ships the report template library.**

- Templates are the landing gallery rail. Category chips filter commerce,
  finance, people, operations, narrative, data, education, property,
  logistics, and programs.
- Every template sample is **two pages** in one PDF: English, then Arabic.
- Depends on `quds_office_engine` **0.5.0** (`pdf_templates`, `SheetSkin`,
  RTL table cell start alignment, Flutter twins).
- Gallery also covers Flutter-twins widgets and the existing showcase /
  Office → PDF samples.

## 0.4.0

PDF viewing matches the page that owns the text.

- Selection stays on its page. Opening another file or scrolling to another
  page does not repaint the old highlight at the same coordinates.
- `Ctrl+A` / `selectAll()` selects every text run in the file.
  `Ctrl+Shift+A` / `selectPage` selects every run on that page.
- Find walks display-list runs, including matches that span runs. Hits are
  page-tagged, the current hit scrolls into view, and next/previous wrap.
  Arabic queries fold presentation forms, alef variants, and diacritics.
- `/Rotate` is painted and hit-tested as a clockwise quarter-turn of the view.
- Depends on `quds_office_engine` 0.4.0 (`PdfToolbox` graft, shaped watermark).

## 0.3.0

**Four surfaces: Word · Excel · PowerPoint · PDF.** The editor now embeds a
full PDF viewer/editor beside the Office canvases — same RenderBox discipline,
same theme/chrome hooks.

### PDF surfaces
- `QudsPdfViewer` / `QudsPdfEditor` on `RenderPdfCanvas` (display list paint,
  find, copy, link follow, animated zoom with tile stretch).
- Viewer is display-only; editor adds markup, form fill, page ops, layer
  toggle, and incremental save.
- Host fonts: call `OfficeHostFonts.ensureRegistered()` so Standard-14 /
  common Office aliases paint without OS font folders; embedded PDF faces win.

### Office surfaces (continued)
- `QudsWordEditor`, `QudsSheetEditor`, `QudsSlideEditor` — IME, BiDi caret,
  formulas, Morph slideshow, isolate open.

### Studio example
- PDF gallery (Office→PDF, PdfDocument writer, `pdf_widgets` samples) and
  bilingual workspace.

## 0.2.0

Interactive Word ruler, notes pane, section-wide landscape, horizontal page
gutters, and English package documentation. Chrome strings stay localizable;
the canvas supports many languages and writing directions.

## 0.1.0

First public release.

### Surfaces
- `QudsWordEditor` — paginated Word canvas with IME, BiDi caret, tables, comments, headers/footers, equations, and visuals.
- `QudsSheetEditor` — virtualized spreadsheet grid with formula bar, freeze panes, fill handle, and charts.
- `QudsSlideEditor` — slide stage with transform handles, snap guides, animations, and a real slideshow (including reverse play).

### Host integration
- Controllers load and save OOXML bytes (`fromBytes` / `saveBytes`), including password-protected packages.
- `OfficeTheme` + `OfficeSurfaceConfig` for light/dark, viewing / selecting / editing modes, and localizable chrome strings.
- Page orientation applies to the whole continuous section; the Word canvas pans horizontally with side gutters.
- Undo/redo, clipboard, context menus, and keyboard intents without `TextField` / `ListView` / `InteractiveViewer`.
- Isolate open for large documents so the UI isolate stays live.

### Studio example
- Full bilingual Word / Excel / PowerPoint workspace under `example/`.
