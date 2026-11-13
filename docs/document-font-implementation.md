# Shared document fonts and viewer alternatives

Implementation date: 13 November 2026. App branch:
`feature/apache-file-viewer-20261113`. This implements the accepted changes in
the [font and viewer assessment](document-fonts-and-viewer-policy.md).
The assessment's measurements remain a historical baseline.

The policy remains one primary implementation per format, with complementary
reading/source views and an explicit installed-application alternative. The
implementation reuses existing font files, corrects selection and measurement,
and reduces redundant packaging. It does not add a second bundled DOC engine,
an additional XML engine, a large Unicode font collection, or an optional-pack
distribution system.

## Font inventory used by the shared policy

The [app catalog](../lib/services/document_font_catalog.dart) describes 21
existing TrueType files. Its paths are also supplied to the isolated browser
host; the files are not copied into that package. Font aliases affect rendering
and do not rewrite document properties.

| Actual family | Existing faces | Rendering aliases | Font grant |
| --- | --- | --- | --- |
| Liberation Sans | Regular, bold, italic, bold italic | Arial, Helvetica, sans-serif/SansSerif | SIL OFL 1.1 |
| Liberation Serif | Regular, bold, italic, bold italic | Times New Roman, Times, Times-Roman, serif | SIL OFL 1.1 |
| Liberation Mono | Regular, bold, italic, bold italic | Courier New, Courier, monospace | SIL OFL 1.1 |
| Carlito | Regular, bold, italic, bold italic | Calibri | SIL OFL 1.1 |
| Noto Naskh Arabic | Regular, bold | NotoNaskhArabic; Arabic coverage fallback | SIL OFL 1.1 |
| Roboto | Regular, medium, bold | StoreRoboto | Apache 2.0 |

Liberation and Noto come from the existing Quds editor font assets. Carlito
comes from the already used `dart_pdf_editor_assets` 14.0.0 package. Roboto is
already in the app. Roboto Mono remains the separate `AppMono` source/text
font. Other PDF editor fonts, including TeX Gyre and DejaVu, retain their existing
PDF-specific behavior; this change does not remove or reinterpret them.

The inaccurate built-in Calibri/Carlito/Roboto-to-Liberation-Sans aliases and
Georgia-to-Liberation-Serif alias were removed in the canonical Quds repository.
Calibri now receives actual Carlito. Unknown names such as Georgia and Aptos
remain unknown names, with normal fallback behavior rather than a claimed
metric-compatible mapping. Real cuts are selected where available; an absent
italic/bold cut can still require synthesis.

Exact grants are retained in
[Liberation's notice](../packages/quds_office_editor/fonts/LICENSE-Liberation),
[Noto's notice](../packages/quds_office_editor/fonts/LICENSE-NotoNaskhArabic),
[PDF font notices](../assets/licenses/pdf_fonts/), and the existing app font
notices. The full Material Icons fixture carries the pinned **CC-BY-4.0**
notice; the earlier assessment incorrectly grouped it with Apache-licensed
Roboto. The attribution is retained even after the full icon file leaves the
production assets.

## Behavior by surface

| Surface | Implemented font behavior | Remaining boundary |
| --- | --- | --- |
| DOC/DOT formatted preview, F3 and side pane | Decode the parser's safe CSS hexadecimal font names at the Flutter `TextStyle` boundary; resolve known aliases through the catalog; initialize relevant fonts before paint. | This remains structured reading through the native legacy parser, not Word's pagination engine. Unknown/system fonts and unsupported layouts can differ. |
| RTF formatted preview | Uses the same safe HTML font boundary and available bundled fallbacks. | The current RTF projection does not reproduce every original font-table/layout feature. |
| DOCX/DOCM/DOTX/DOTM formatted reading | Existing Markdown/theme reading projection remains available. | It still does not reproduce original Word run typography or embedded Word font programs. |
| Supported OOXML Pages | Supply all 21 named faces to the native/Dart PDF exporter, selecting family, weight, italic and coverage before measurement and embedding. | Not a complete Office layout engine; CFF embedding and universal script coverage are outside this path. |
| Native Office editor | Existing Quds families plus host registration of actual Carlito and Roboto. | Unknown original family metadata remains intact; a supplied compatibility face does not imply exact Word layout. |
| XLS/XLT/XLSB browser grid | Load required real faces before measuring each active window; retain source family requests and append available shared fallbacks. | Workbook parsing, formula/cached-value, image and chart boundaries are unchanged. |
| Binary PPT/POT/PPS | Load faces for the requested slide and its master chain before Canvas measurement, then embed that selection into the transient standalone SVG used to produce slide pixels. | The bridge cannot restore unsupported PowerPoint layout or animations. Embedded CSS fonts in a page alone would not have reached the standalone SVG image. |
| WordPerfect | Use existing Liberation Serif styles for structured reading, with Arabic fallback when required. | The current libwpd-to-view-model bridge does not preserve original font family/size or full pagination. |
| PS/EPS | Keep Stet's own 35 embedded URW Type 1 faces, under its recorded OFL election. | These interpreter resources cannot simply be replaced by Flutter or CSS font registration. |
| CHM | Preserve bounded archive font resources and sanitized topic CSS. | Shared Office aliases do not override topic fonts. |
| XML/source and XSLT results | Native source uses AppMono/Roboto Mono; existing browser tooling and inert result rules remain. | XML data has no intrinsic page font. XSLT result styles and resource restrictions are unchanged. |
| MBOX/EML | Existing readable email typography and source views remain. | This is not a reproduction of arbitrary email CSS/fonts. |

Sources: [HTML font boundary](../lib/widgets/office_html_widget_factory.dart),
[lazy registration](../lib/services/document_fonts.dart),
[PDF export](../lib/services/office_pdf_service.dart),
[browser font loading](../packages/file_viewer_documents/engines/host/fonts.ts),
[native/web asset bridge](../packages/file_viewer_documents/lib/src/hosts/font_assets.dart),
and [selected-format implementations](file-viewer-selected-documents.md).

### Measurement and PDF output now agree

The canonical Quds change fixes more than a family-name lookup. Word previously
measured a paragraph with its first run and adjusted run scaling afterward.
Line breaking now receives source-offset-aware font and width callbacks, so a
run's family, size and real style are used before wrapping. PDF output selects
the same face and glyph subset. Actual bold/italic outlines do not receive an
additional synthetic bold stroke or italic shear.

Native spreadsheet PDF export also reads retained family/italic information.
The simplified native PPTX model still lacks complete rich-run font metadata;
it benefits from coverage but is not claimed to gain complete PowerPoint
typography from this change.

Export diagnostics describe glyphs actually painted, not speculative layout
probes. Unsupported printable characters retain their advance and receive a
visible box. Pages shows a compact, localized font notice, with selectable
details listing actual family substitutions and uncovered Unicode code points.
Diagnostics are bounded, and the UI retains only their small report after
opening the PDF, not an extra full PDF buffer.

Read-only HTML previews preserve readable content if font loading fails and
show a localized fallback note. Export and editor failures keep their existing
typed error/retry behavior. Completed byte caches are separate from in-flight
loads; completed futures are not kept in their original caller's zone.

### Browser loading and isolation

The app supplies trusted descriptors, not document-selected paths. Native
hosts expose only exact configured assets present in Flutter's manifest, using
session-scoped numbered font routes. The web host resolves the same assets
under the application's base path. Families, aliases, weights, paths, face
counts and messages are bounded.

The JS loader validates the corresponding local URL routes, limits each face
to 4 MiB and total fetched font data to 16 MiB, bounds parsing/loading time,
caches selected data per preview, and removes registered faces on disposal.
Only required faces load. Script fallback does not suppress a missing-family
warning or the Latin default for mixed text. PS, XML and CHM keep their own
font environments.

The PPT adjustment is a small exact-match patch to the pinned published runtime
that adds an optional SVG transform hook. Build-time drift rejection and
execution contracts cover that hook. Font bytes are embedded only in the
transient selected SVG, with cached data URLs; no additional font files enter
the app package.

## Complementary viewers

The Office toolbar now exposes **Preview with installed application** for
DOC/DOT/DOCX/DOCM on supported desktop platforms. It discovers the already
supported installed converters only when requested. The user selects an
application and explicitly chooses **Preview pages**. The existing converter
creates a bounded temporary PDF, which opens in the existing PDF viewer.

This adds no Office executable or download. Source files remain unchanged.
The selection and output envelope are checked; stale reads, exports and PDF
open results cannot replace a newer document after reload. Existing process
timeouts and temporary cleanup remain in the converter. There is no fake
Cancel control while a converter without a cancellation API is running.

The primary DOC/DOT route remains
[`legacy-doc-parser` at e442772](https://github.com/CrispStrobe/legacy-doc-parser/commit/e4427725cc720eaefad97c2cb921a6fe1e36749d).
The [previous comparison](file-viewer-doc-dot-comparison.md) and parser fixes
remain applicable. XML retains Tree, Source, XSD validation and XSLT tools.
Legacy PPT retains its native Text fallback. These are complementary uses of
the existing code, without another embedded general-purpose document engine.

## Package reduction

Measured against `db5b6126fdfb7f31598c80e5adc96ea548139505`, after the shared
browser-font code is included:

| Scope | Before | After | Raw saving | Gzip-9 saving |
| --- | ---: | ---: | ---: | ---: |
| Selected renderer, host, manifest and distributed notice assets | 24,914,367 B | 21,121,639 B | 3,792,728 B | 530,156 B |
| Standalone fonts | 14,213,736 B | 12,568,664 B | 1,645,072 B | 555,431 B |
| Combined asset reduction | 39,128,103 B | 33,690,303 B | **5,437,800 B (5.186 MiB)** | **1,085,587 B (1.035 MiB)** |

The final release measurement includes the normal production icon subset,
which grew by 112 bytes for the current icon set. Removing the extra full
Material Icons asset alone saves 1,645,184 bytes. All 21 shared catalog font
files appear once in the built assets, with no duplicate font hashes.

Production JavaScript is minified. Complete original notices remain as 63
distinct source texts representing all 86 origins; distribution contains one
complete aggregate with all source attributions plus the two authored host
notices. The retention guard checks hashes, coverage and attributions, including
mutations that recompute an aggregate hash after omitting a grant. All native
WASM and corresponding MPL source hashes remain unchanged. The full icon font
is preserved as a screenshot-test fixture.

These are asset bytes and the sum of per-file gzip-9 estimates, not
APK/IPA/installer savings or measured network transfer. Lazy loading reduces startup work and web requests but does not remove
installed asset bytes. The existing PS font set remains intact. Optional packs
remain a future decision if package budgets justify the distribution and
maintenance machinery.

Exact measurements and validation details are in
[the release measurement and method](evidence/document-font-implementation-20261113/release-web-validation.md)
and [machine-readable receipt](evidence/document-font-implementation-20261113/release-footprint.json).

## Source ownership and validation

Core changes were first saved in the canonical Quds repository, on
`feature/document-fonts-20261113`, at `afa8203`, `e241013`, then
[`e82c997`](https://github.com/CrispStrobe/quds_office_suite/commit/e82c997b6df8746fe86fb83b9f416a89bb3e3b80).
CrispCloud consumes that exact final commit through its guarded mirror sync.
The canonical changes are reviewable in
[Quds draft PR #7](https://github.com/CrispStrobe/quds_office_suite/pull/7).
The independent legacy parser source boundary is preserved.

Canonical verification covers 151 focused engine tests and 22 Flutter editor
tests, including actual font outlines, alias/style selection, mixed-run widths,
native sheet styles, Arabic/Hebrew, missing-character boxes, registration and
alias ownership. It used the genuine workspace SDK with temporary validation
dependency overrides for uncached standalone development packages; those
overrides were removed and did not change shipping dependencies.

The app passes 45 font/PDF/preservation checks, 37 viewer/diagnostic/entry
checks, and 17 installed-preview dialog checks. The Dart host has 23 distinct
passing font-route/lifecycle checks. These include real loopback font routes,
web asset URLs, real packaged font parsing, readable fallback when fonts fail,
and Unicode diagnostics. Focused static analysis reports no issues.

The selected browser engines pass 75 Node/native/WASM/font contracts. All 36
provenance controls pass, including nine runtime-retention mutation checks.
Tracked source verification covers 1,504 Office records and 158 selected
runtime/source/notice records. App checks use the normal dependency graph and
normal native hooks.

The release web build passed at implementation commit
[`ab3af2f`](https://github.com/CrispStrobe/CrispCloud/commit/ab3af2f813a97e57be351366ebe9573798177e4c),
using `flutter build web --no-pub --release --no-wasm-dry-run`. This skips only
Flutter's optional separate Dart-to-WASM dry-run probe; the selected document
engines' real WASM resources remain present. All 47 selected built assets match
their source hashes, source-only notice copies and MPL archives stay out of
the app assets, and the normal production icon font is 77,552 bytes. The
[app validation receipt](evidence/document-font-implementation-20261113/app-validation.json)
and [build receipt](evidence/document-font-implementation-20261113/release-web-build-receipt.json)
retain commands, source hashes, SDK versions and linked test logs.

Local Chromium cannot start in this execution sandbox because its process
singleton socket is denied. The updated CI smoke tests use real font bytes and
check WPD readiness, XLS measurement, PPT SVG embedding, unused-face loading
and disposal. A local browser pass is not claimed. Dialog tests inject the
installed converter and PDF callback; they do not claim an installed Microsoft
Word/LibreOffice run or interactive native PDF-device qualification.
