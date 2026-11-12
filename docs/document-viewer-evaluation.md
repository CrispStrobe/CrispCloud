# Document viewer source evaluation

Reviewed on **12 November 2026**. This is a source and dependency review, not a
device rendering benchmark. No package was added, built, or executed for this
evaluation. Repository source, dependency manifests, tests, bundled engines and
license files were read through the GitHub connector at the commits below.

## Decision

**None of the three packages supplies a faithful binary `.doc` viewer or a
format-preserving `.doc` editor.** `docx_viewer` and `document_viewer` are DOCX
text wrappers. `offline_document_viewer` contains a real binary Word text
extractor, but no binary Word layout engine. Its richer renderers are for
ZIP/XML Office formats. The implementation evidence is described below.

Keep CrispCloud's bounded binary Word parser and patched Quds editing path.
Do not add either text-wrapper package. Treat selected parts of
`offline_document_viewer` as candidates for a separately tested preview
improvement: its basic RTF formatting, legacy PowerPoint text extraction, and
patched DOCX/PPTX visual rendering have identifiable value. Importing the whole
package would also introduce a WebView host, a second PDF stack, substantial
assets, and another document cache. [ODV-manifest] [ODV-workspace]

For richer binary DOC conversion, an installed office-suite adapter is a
different solution from these Flutter viewers. Apache POI HWPF is a permissive
parser worth knowing about, but brings a Java runtime and incomplete conversion
behavior; it is not a direct Flutter replacement. See the final section.

## Reviewed revisions and licenses

These are immutable source references, rather than claims about every future
release or the exact contents of a hosted package archive.

| Repository | Reviewed commit / declared version | License verified at that commit | Disposition |
| --- | --- | --- | --- |
| `santoshvandari/docx_viewer` | [`44bba352a271a22ca276b4738168b4b775d1d4fc`](https://github.com/santoshvandari/docx_viewer/commit/44bba352a271a22ca276b4738168b4b775d1d4fc), default branch `dev`, `1.0.1` | [MIT][SV-license] | No added format or fidelity capability worth importing |
| `komalsdagde/document_viewer` | [`3f4f638a9105980e11174526cb3dbfd4c3e584dc`](https://github.com/komalsdagde/document_viewer/commit/3f4f638a9105980e11174526cb3dbfd4c3e584dc), `main`, `0.0.2-4` | [MIT][DV-license] | No binary DOC parser; duplicates existing viewers and has an archive-version conflict |
| `huseyiniriss/offline_document_viewer` | [`8904c7bb93ebdc5265476febdd2344bb46a97326`](https://github.com/huseyiniriss/offline_document_viewer/commit/8904c7bb93ebdc5265476febdd2344bb46a97326), `main`, `0.1.0` | [MIT for its own code][ODV-license]; [separate engine/font notices][ODV-notices] | Evaluate selected functionality; not a complete editor or a binary DOC fidelity upgrade |

The manifests establish the declared versions and runtime dependencies.
[SV-manifest] [DV-manifest] [ODV-manifest]

## 1. `docx_viewer`: DOCX text extraction

### What actually runs

`extractTextFromDocxBytes` passes the input to `ZipDecoder`, selects exactly
`word/document.xml`, parses it as XML, and joins the `w:t` descendants of every
`w:p`. The result is displayed in one Flutter `Text` widget. There is no CFB/OLE
reader, Word FIB reader, CLX piece-table parser, or binary Word decoding path.
The local-file branch explicitly accepts only the `docx` extension. This
contradicts the broader “Docx/Doc” description in its manifest: passing binary
DOC bytes to the bytes constructor still reaches the ZIP decoder.
[SV-parser] [SV-widget] [SV-manifest]

This preserves paragraph text, with a simple incrementing counter when a
paragraph contains a numbering ID. It does not resolve `numbering.xml`, nested
numbering levels, or list styles. Table-cell text can appear because it contains
paragraphs, but the table itself is not reconstructed. Images, page layout,
headers/footers, comments, notes, and OLE objects are not rendered by this path.
Tracked-change markup is not interpreted as revision semantics; the code only
selects text elements. It provides no editing or Office save operation.
[SV-parser] [SV-widget]

### Platform and integration cost

The package declares Android, iOS, web, Windows, macOS and Linux. Its conditional
file imports and `bytes` input support an offline, in-memory use case; the web
path rejects direct local filenames. Network URLs are optional and are fetched
with `http.get`, rather than sent to an external conversion service. Runtime
dependencies are Flutter, `archive ^4.0.0`, `xml ^6.5.0`, and `http ^1.2.2`.
[SV-widget] [SV-manifest]

There is no input-byte or expanded-part budget in the reviewed wrapper/parser.
It decodes the ZIP before selecting the main part. CrispCloud would need to
retain its own loading and archive budgets even if it reused this code.
The MIT license permits reuse with its notice; the code adds no capability that
justifies another dependency here. [SV-parser] [SV-license]

## 2. `document_viewer`: a filename switch is not DOC support

Both `.doc` and `.docx` call the same `readFromDocxFile` method. That method
reads the whole file and calls `docxToText(bytes)` from `docx_to_text`; the output
again becomes a Flutter `Text` widget. The other branches dispatch PDF to
`PdfView`, TXT to `File.readAsString`, and PNG/JPEG to `PhotoView`.
[DV-widget]

The dependency is also a ZIP/XML text extractor. Its implementation at
`StarProxima/docx_to_text` commit
[`3c6b62ddaeeaf7c7f3d8143c86985ff1e275c880`][DTT-commit], whose manifest declares
`1.0.1`, uses `ZipDecoder`, selects `word/document.xml`, and walks paragraphs
and text nodes. The published `1.0.1` API implementation shows the same ZIP
entry point. Neither is a binary DOC parser. A ZIP-based DOCX renamed `.doc`
could traverse that branch; an actual Word 97–2003 compound file is a different
format. [DTT-parser] [DTT-manifest] [DTT-published]

The practical limits match the previous package: flattened text rather than
tables, pictures or page layout; no separate header/comment/revision/OLE
rendering; no editable document model or preserving save route.
[DV-widget] [DTT-parser]

The reviewed widget imports `dart:io` directly and works from a filesystem
path, with no bytes-source API. Its manifest describes Android and adds
`pdf_viewer_plugin ^2.0.1`, `photo_view ^0.14.0`, `path_provider ^2.0.15`,
`external_path ^1.0.3`, `permission_handler ^10.4.3`, and
`docx_to_text ^1.0.1`. The core viewer has no HTTP or cloud conversion call,
but it is not a web-compatible replacement for CrispCloud's captured bytes
loader. Other native platforms would need dependency-specific verification.
[DV-widget] [DV-manifest]

There is also a concrete dependency mismatch: `docx_to_text 1.0.1` requests
`archive ^3.3.6`, whereas the reviewed CrispCloud manifest requests
`archive ^4.6.0`. Those major-version constraints do not intersect. A fork or
override would be needed merely to resolve this redundant text viewer; no
override is recommended. Both repositories' own code is MIT licensed.
[DTT-manifest] [CC-manifest] [DTT-license] [DV-license]

## 3. `offline_document_viewer`: real parsers, with different fidelity tiers

### Binary DOC and PPT

This package does contain a CFB reader, including FAT and mini-FAT stream
reading. Its DOC extractor reads `WordDocument`, chooses `0Table` or `1Table`,
locates the CLX piece table, and decodes compressed or UTF-16 pieces. If that
fails, it attempts a contiguous text range with an encoding heuristic. The
workspace converts the extracted strings into escaped HTML paragraphs. This
is real binary DOC **text extraction**, not just an extension label.
[ODV-cfb] [ODV-legacy] [ODV-workspace]

It does not parse binary DOC paragraph/character formatting, table structures,
picture layout, header/footer stories as such, comments, revision state, or
embedded OLE objects into a visual document. Its public format enum accurately
marks DOC and PPT as `textOnly`. The PPT implementation walks text atoms and
skips master and notes containers; it is an additional legacy-format text
fallback, not slide-layout reconstruction. [ODV-legacy] [ODV-formats]

The existing CrispCloud DOC parser should remain the default. The reviewed
alternative uses fixed FIB offsets, reads all available pieces without a
`ccpText` main-story boundary, and falls back to a guessed contiguous range.
Its DOC path does not validate the Word signature/version and encrypted FIB
bits as CrispCloud does. CrispCloud walks the FIB arrays, bounds characters
and piece counts, restricts extraction to the main story, validates the
selected table and suppresses field instructions. That is a concrete reason
to retain the narrower parser, rather than replace it with a more permissive
recovery heuristic. This is a static comparison, not a claim that every
malformed input has been tested against the alternative. [ODV-legacy]
[CC-legacy]

The upstream test suite includes a DOC generated by `textutil`, verifies its
text, and has synthetic PPT/CFB fixtures. These are useful sample inputs and
assertions; they do not demonstrate DOC layout or a preserving round trip.
[ODV-tests] [ODV-fixtures]

### OOXML visual rendering and other useful formats

| Area | Actual implementation | Meaning for CrispCloud |
| --- | --- | --- |
| DOCX/DOCM | Bundled `docx-preview 0.3.5` plus JSZip, rendered to HTML/CSS. The shell enables page breaks, experimental layout, headers, footers and footnotes. The engine also defaults to endnote rendering. | A possible visual-preview comparison target, especially for images and page-like layout; not an editor. [ODV-docx-shell] [ODV-docx-engine] |
| DOCX tables/images | The engine parses table/row/cell structure and image relationships; local patches handle theme fill/tint/shade. | More than plain text, but no side-by-side evidence yet that it beats the patched Quds rendering on our corpus. [ODV-docx-engine] [ODV-docx-patches] |
| Comments/revisions | The engine has relevant code, but `renderComments` and `renderChanges` default to false and the shell does not override them. | Do not advertise review-markup viewing merely because parser symbols exist. There is no accept/reject or preserving edit workflow. [ODV-docx-shell] [ODV-docx-engine] |
| OLE in DOCX | No OLE execution/rendering route was found in the inspected parser/renderer. | Do not promise embedded-object fidelity. OOXML image previews are a separate capability. [ODV-docx-engine] |
| XLSX/XLSM and XLS | SheetJS reads values; the custom OOXML style layer adds fonts, borders, alignment, fills, merges and dimensions. XLS is explicitly partial/value-oriented. The style renderer defaults to 3,000 rows and 200 columns. | A richer spreadsheet preview candidate, not an Excel editor or calculation engine. [ODV-formats] [ODV-xlsx] |
| PPTX/PPTM | Bundled PPTXjs `1.21.1`, with patches for inherited bullets, Wingdings, numeric XML references, missing `docProps/app.xml`, and multi-column/vertical text. | Specific rendering fixes and fixtures are worth comparing with our approximate F3 slide preview. [ODV-pptx-patches] [ODV-pptx-shell] |
| RTF | Dart state machine emits HTML with basic emphasis, size, colors, paragraph alignment and Unicode handling; it skips pictures, embedded objects, headers, footers and other destinations. | A focused candidate for formatted RTF preview. It is not a complete RTF editor/importer. [ODV-rtf] |
| PDF, CSV/TSV | PDF delegates to `pdfrx`/PDFium; delimited text uses the spreadsheet viewer. | Already-covered categories; not a reason to install the full package. [ODV-view] [ODV-formats] |

The format enum's `high`/`full` labels are the package's declarations, not a
measurement against Word or CrispCloud. The bundled tests inspect converter
outputs and asset structure; this review did not run its claimed device
rendering checks. There is no editing/save model in the public view/controller
workflow. [ODV-formats] [ODV-view] [ODV-tests] [ODV-asset-tests]

### Offline behavior, platforms, archives and cache ownership

The package bundles the renderer scripts, CSS and fonts. Its workspace serves
Android from a virtual `appassets.androidplatform.net` origin and uses a
scoped file URL on the Apple path; when direct fetching cannot read the bytes,
the Dart bridge sends them in 256 KiB chunks. No external conversion server is
part of this implementation. The manifest depends on
`flutter_inappwebview ^6.1.5`, `pdfrx ^2.4.7`, `path_provider ^2.1.6`,
`crypto ^3.0.7`, Dart `^3.10.0` and Flutter `>=3.41.0`.
[ODV-bridge] [ODV-manifest]

Its source is native-filesystem based (`dart:io`, cache directories and file
URLs), so the package is not directly usable in CrispCloud web. Android/iOS
are the advertised targets; an Apple file-loading branch also mentions macOS.
Windows/macOS/Linux build and runtime coverage must not be inferred from the
cross-platform dependencies alone. No desktop or mobile build was attempted
in this review. [ODV-source] [ODV-bridge] [ODV-readme]

The offline controls deserve precise wording. Android CSP uses
`connect-src 'self'` for the local asset origin; the other branch uses
`connect-src 'none'`. The navigation policy checks the Android host or the
`file:` scheme, not the full workspace path. Therefore the source supports an
offline design, but the README's stronger description of every navigation
being restricted to a workspace root should not be copied as a verified
security guarantee. Any integration should retain CrispCloud's own URL/path
policy and verify actual requests on the target platforms.
[ODV-workspace] [ODV-bridge]

Preflight checks the input size, ZIP central-directory entry count, declared
expanded sizes, compression ratio and suspicious paths before JS rendering.
Its limits are 80 MiB input, 300 MiB declared expansion, 5,000 entries and a
200:1 per-entry ratio. This is not a measured bound on actual inflation or a
replacement for CrispCloud's archive reader. None of the three packages
provides general archive navigation or an archive `..` row.
[ODV-preflight] [SV-parser] [DV-widget]

Workspace creation writes OOXML bytes as `doc.bin`, or extracted DOC/PPT/RTF
content as HTML, into a content-hash-named application cache. It also copies
the required engine and all bundled fonts per workspace. `dispose` does not
delete the workspace. A separate prune method has defaults of 30 days and
400 MiB; it is not called by `DocumentView` itself. Adopting this host would
need an explicit cache lifecycle rather than silently creating another set
of retained document copies. [ODV-workspace] [ODV-view]

The pinned Git tree contains **12,836,078 raw asset bytes** (about 12.24 MiB),
including **9,996,609 font bytes** and **2,790,726 engine bytes**. These are sums
of Git blob sizes, not an installed-app or compressed-download measurement;
they exclude native PDFium/WebView dependency cost. This is materially more
than importing a small Dart extractor. [ODV-tree]

### License feasibility

The package's own code is MIT. Its notice inventory declares Apache-2.0 for
docx-preview, SheetJS CE and NVD3; MIT for PPTXjs, JSZip and jQuery; ISC for D3;
and separate permissive font terms, including SIL OFL and Bitstream/DejaVu
terms. The pinned PPTXjs license file and font license files substantiate those
specific bundled notices. Upstream docx-preview tag `0.3.5` resolves to
`f59e90decaf55d7ebb5f4205defaf3da63b403c4`; its actual LICENSE is Apache-2.0.
[ODV-license] [ODV-notices] [ODV-pptx-license] [ODV-font-license]
[DOCXJS-license]

These licenses are compatible with a permissive-library strategy in principle,
but the root MIT file does not relicense the bundled third-party code/fonts.
The repository's `assets/licenses` directory has four files, not a complete
separate license text for every listed engine/font. Before redistributing any
selected bundle, carry the applicable upstream license/NOTICE texts and
modification notices and verify the exact dependency versions. A complete
transitive license audit was not performed because no package is being added.
[ODV-license-tree] [ODV-notices] [DOCXJS-license]

## Comparison with the reviewed CrispCloud baseline

The baseline here is CrispCloud commit
[`77a63a08da6913b444a634b95fe79e62143776c5`][CC-commit]. Separate native
office-conversion work should be evaluated through its own adapter contract;
it is not a capability supplied by the three packages above.

| Existing capability | Source evidence | Effect on this decision |
| --- | --- | --- |
| Portable `.doc`/`.dot` main-story text | Bounded CFB and FIB/CLX parser, encrypted-file rejection, character/piece limits. [CC-legacy] | Already has the binary DOC capability the strongest candidate offers, with stricter selection and failure behavior. |
| Portable new DOCX copy from legacy Word | Writes a separate macro-free DOCX from the extracted body text; explicitly omits formatting, images, comments, notes and revision semantics. [CC-conversion] | None of these viewers upgrades this into preserving DOC conversion. |
| Structured F3 Office preview | Headings, emphasis, lists, tables and notes for Word; table data for spreadsheets; approximate positioned slide text/images; hardened package reads. [CC-preview] | The two plain-text wrappers would regress functionality. HTML-based visual preview is the candidate worth comparing. |
| Office editing | Patched Quds deserializer/serializer and editor host, with tables, sections, header/footer stories, notes, comments, revisions and opaque/embedded-part handling. Unsupported cases have explicit rejection paths. [CC-deserializer] [CC-serializer] [CC-editor] | A viewer-only WebView is not a replacement for this save/preservation model. Presence of models is not a claim of complete Word fidelity. |
| Preservation evidence | Independent fixture, package and host save checks are documented separately, including their limitations. [CC-fidelity] | Any candidate needs untouched and minimal-edit comparisons before changing the editor; a screenshot is insufficient. |

## Concrete follow-up options

1. **Keep the shipping paths.** Do not add `docx_viewer` or `document_viewer`.
   Their source does not solve an unmet format requirement.
2. **Use focused preview experiments.** Compare the patched docx-preview engine
   against the existing F3 and Quds rendering on the same DOCX corpus; inspect
   the PPTX bullet/theme and table-shading fixes as individual references.
   Keep source loading, origin identity, resource budgets and navigation in
   CrispCloud. Test embedded/remote relationships, images, headers, notes,
   comments, revisions, malformed ZIPs and offline loading before adoption.
3. **Consider small format-specific additions.** The MIT Dart PPT text walker
   and basic RTF converter offer more immediate new coverage than the complete
   mobile viewer package. Reuse ideas or selected code only with attribution,
   bounded input/output and independent fixtures. Do not replace the stricter
   DOC parser with its fallback heuristics.
4. **For richer binary DOC, consider a different backend category.** Apache POI
   HWPF at [`a4e8640da7c3bb906efc6fa11914d1b80f3cc9dc`][POI-commit] is actual
   binary Word parsing under [Apache-2.0][POI-license]. Its `WordToHtmlConverter`
   processes paragraph/character styles, tables and foot/endnotes, and has a
   picture-manager hook. This is concrete additional structure beyond text
   extraction. However, it is marked beta; image export needs host handling;
   its base OLE conversion hook returns false; and the converter has explicit
   unsupported areas. It emits HTML rather than a preserving DOCX edit
   round trip. [POI-html] [POI-base]

POI also brings a Java module/runtime plus its core, commons-codec and
commons-math dependencies, rather than a Dart package. That makes it a
potential isolated desktop converter or reference parser, not an immediate
solution for the same Android/iOS/web/desktop Flutter implementation. No
POI build, port, or rendering comparison was performed. Prefer the existing
native-office conversion direction for a higher-fidelity desktop path unless
a specific HWPF capability justifies that additional runtime. [POI-build]

[SV-license]: https://github.com/santoshvandari/docx_viewer/blob/44bba352a271a22ca276b4738168b4b775d1d4fc/LICENSE
[SV-manifest]: https://github.com/santoshvandari/docx_viewer/blob/44bba352a271a22ca276b4738168b4b775d1d4fc/pubspec.yaml
[SV-parser]: https://github.com/santoshvandari/docx_viewer/blob/44bba352a271a22ca276b4738168b4b775d1d4fc/lib/src/extract_text_from_docx.dart
[SV-widget]: https://github.com/santoshvandari/docx_viewer/blob/44bba352a271a22ca276b4738168b4b775d1d4fc/lib/src/docx_view.dart
[DV-license]: https://github.com/komalsdagde/document_viewer/blob/3f4f638a9105980e11174526cb3dbfd4c3e584dc/LICENSE
[DV-manifest]: https://github.com/komalsdagde/document_viewer/blob/3f4f638a9105980e11174526cb3dbfd4c3e584dc/pubspec.yaml
[DV-widget]: https://github.com/komalsdagde/document_viewer/blob/3f4f638a9105980e11174526cb3dbfd4c3e584dc/lib/src/document_viewer.dart
[DTT-commit]: https://github.com/StarProxima/docx_to_text/commit/3c6b62ddaeeaf7c7f3d8143c86985ff1e275c880
[DTT-parser]: https://github.com/StarProxima/docx_to_text/blob/3c6b62ddaeeaf7c7f3d8143c86985ff1e275c880/lib/src/docx_to_text_src.dart
[DTT-manifest]: https://github.com/StarProxima/docx_to_text/blob/3c6b62ddaeeaf7c7f3d8143c86985ff1e275c880/pubspec.yaml
[DTT-license]: https://github.com/StarProxima/docx_to_text/blob/3c6b62ddaeeaf7c7f3d8143c86985ff1e275c880/LICENSE
[DTT-published]: https://pub.dev/documentation/docx_to_text/1.0.1/docx_to_text/docxToText.html
[ODV-license]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/LICENSE
[ODV-notices]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/THIRD_PARTY_NOTICES.md
[ODV-manifest]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/pubspec.yaml
[ODV-formats]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/lib/src/document_format.dart
[ODV-cfb]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/lib/src/engine/compound_file.dart
[ODV-legacy]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/lib/src/engine/legacy_text.dart
[ODV-workspace]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/lib/src/workspace/workspace.dart
[ODV-view]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/lib/src/document_view.dart
[ODV-source]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/lib/src/document_source.dart
[ODV-bridge]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/lib/src/bridge/viewer_bridge.dart
[ODV-preflight]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/lib/src/preflight.dart
[ODV-docx-shell]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/assets/viewers/docx.js
[ODV-docx-engine]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/assets/engines/docx/docx-preview.js
[ODV-docx-patches]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/doc/engine-patches-docx-preview.md
[ODV-pptx-patches]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/doc/engine-patches-pptxjs.md
[ODV-pptx-shell]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/assets/viewers/pptx.js
[ODV-xlsx]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/assets/engines/xlsx/xlsx-render.js
[ODV-rtf]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/lib/src/engine/rtf_converter.dart
[ODV-tests]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/test/converters_test.dart
[ODV-fixtures]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/test/fixtures/README.md
[ODV-asset-tests]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/test/engine_assets_test.dart
[ODV-pptx-license]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/assets/licenses/LICENSE-pptxjs
[ODV-font-license]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/assets/licenses/LICENSE-liberation
[ODV-license-tree]: https://github.com/huseyiniriss/offline_document_viewer/tree/8904c7bb93ebdc5265476febdd2344bb46a97326/assets/licenses
[ODV-tree]: https://api.github.com/repos/huseyiniriss/offline_document_viewer/git/trees/13daf1f363068d9fb62d0f3cd213e9f55be796f4?recursive=1
[ODV-readme]: https://github.com/huseyiniriss/offline_document_viewer/blob/8904c7bb93ebdc5265476febdd2344bb46a97326/README.md
[DOCXJS-license]: https://github.com/VolodymyrBaydalka/docxjs/blob/f59e90decaf55d7ebb5f4205defaf3da63b403c4/LICENSE
[CC-commit]: https://github.com/CrispStrobe/CrispCloud/commit/77a63a08da6913b444a634b95fe79e62143776c5
[CC-manifest]: https://github.com/CrispStrobe/CrispCloud/blob/77a63a08da6913b444a634b95fe79e62143776c5/pubspec.yaml
[CC-legacy]: https://github.com/CrispStrobe/CrispCloud/blob/77a63a08da6913b444a634b95fe79e62143776c5/lib/services/legacy_word_document.dart
[CC-conversion]: https://github.com/CrispStrobe/CrispCloud/blob/77a63a08da6913b444a634b95fe79e62143776c5/lib/services/legacy_word_conversion.dart
[CC-preview]: https://github.com/CrispStrobe/CrispCloud/blob/77a63a08da6913b444a634b95fe79e62143776c5/lib/services/office_document_service.dart
[CC-deserializer]: https://github.com/CrispStrobe/CrispCloud/blob/77a63a08da6913b444a634b95fe79e62143776c5/packages/quds_office_engine/lib/src/word/serial/word_deserializer.dart
[CC-serializer]: https://github.com/CrispStrobe/CrispCloud/blob/77a63a08da6913b444a634b95fe79e62143776c5/packages/quds_office_engine/lib/src/word/serial/word_serializer.dart
[CC-editor]: https://github.com/CrispStrobe/CrispCloud/blob/77a63a08da6913b444a634b95fe79e62143776c5/lib/widgets/office_editor_dialog.dart
[CC-fidelity]: https://github.com/CrispStrobe/CrispCloud/blob/77a63a08da6913b444a634b95fe79e62143776c5/docs/office-fidelity.md
[POI-commit]: https://github.com/apache/poi/commit/a4e8640da7c3bb906efc6fa11914d1b80f3cc9dc
[POI-license]: https://github.com/apache/poi/blob/a4e8640da7c3bb906efc6fa11914d1b80f3cc9dc/legal/LICENSE
[POI-html]: https://github.com/apache/poi/blob/a4e8640da7c3bb906efc6fa11914d1b80f3cc9dc/poi-scratchpad/src/main/java/org/apache/poi/hwpf/converter/WordToHtmlConverter.java
[POI-base]: https://github.com/apache/poi/blob/a4e8640da7c3bb906efc6fa11914d1b80f3cc9dc/poi-scratchpad/src/main/java/org/apache/poi/hwpf/converter/AbstractWordConverter.java
[POI-build]: https://github.com/apache/poi/blob/a4e8640da7c3bb906efc6fa11914d1b80f3cc9dc/poi-scratchpad/build.gradle
