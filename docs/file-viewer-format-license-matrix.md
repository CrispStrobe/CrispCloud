# File Viewer formats and effective licenses

Review date: 2026-11-13. Repository: [flyfish-dev/file-viewer](https://github.com/flyfish-dev/file-viewer).
The reviewed upstream version is 3.3.3 at
[`d264009ca6efb3daed79a39d1ae63133e0f25558`](https://github.com/flyfish-dev/file-viewer/commit/d264009ca6efb3daed79a39d1ae63133e0f25558),
also confirmed as upstream main during this review. CrispCloud's implemented
binary and LRC extraction checkpoint is
[`98b39f2`](https://github.com/CrispStrobe/CrispCloud/commit/98b39f21a528375165822e38c4ff4fcfa75575e2).
The priority document/mailbox integration is saved at source checkpoint
[`5404834`](https://github.com/CrispStrobe/CrispCloud/commit/540483491f4a02aad3672abe438ad4aad3696e21).
Its exact selected build and retained grants are documented in the
[document package README](../packages/file_viewer_documents/README.md).

## User-approved policy

The user's updated instruction is: “mit or bsd or similar are ok for crispcloud.
mpl too.” Future candidates may therefore include Apache-2.0, MIT/MIT-0,
BSD-family and comparable permissive code licenses, and MPL. The existing
Apache-only extracted files and their provenance guards stay unchanged.

An effective-license entry describes the components distributed for a route:
File Viewer's wrapper, parser, runtime, and relevant bundled assets. It is not
a new license applied to the entire combination. A dual license offering a
permissive or MPL option can use that option; an Apache wrapper does not change
the license of its engine or assets. LGPL, GPL/AGPL, EPL, custom restrictions and
unresolved binary provenance require separate treatment.

MPL is accepted with its source and notice obligations: preserve the applicable
license and provide the corresponding covered source and modifications when
distributing compiled code. The [Mozilla FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/)
explains the file-level boundary and executable-distribution requirements.
Fonts and data have their own grants, such as OFL, GUST/LPPL or CC0, and are
listed separately from software licenses.

## What this adds to CrispCloud

CrispCloud now implements F3 routes for **WordPerfect, CHM, legacy Excel/XLSB,
positioned binary PowerPoint slides, PostScript/EPS and optional XML XSD/XSLT
tools**, plus a native **MBOX** viewer. The table below identifies that selected
subset. The remaining genuinely new candidates include **Hancom Hangul, Apple
iWork, DBF/FODS, OFD, XMind, Parquet/Avro, geospatial overlays, IDML and optional
IFC geometry**. Photoshop/Illustrator and selected 3D formats offer additional
previews, with format-specific limits. Binary DOC is already substantially
supported by CrispCloud's native MPL parser; replacing it wholesale is not
justified. The [DOC/DOT comparison](file-viewer-doc-dot-comparison.md) records
the exact source boundaries, differential fixtures and concrete gaps on each side.

The comparison uses CrispCloud's actual [viewer routes](../lib/services/internal_viewer_service.dart),
[Office dispatch](../lib/services/office_document_service.dart), and
[existing format documentation](file-format-viewers.md), rather than assuming
that every upstream extension is a new feature. SQLite currently opens as binary
in the main viewer, so a table preview would add capability. Existing PDF,
EPUB, email, image, font, media, archive and source-code viewers overlap heavily.
The separately integrated CrisperBooks subsystem must also be considered before
calling an ebook format new.

### Implemented priority subset

| F3 inputs | CrispCloud implementation | Remaining limits |
|---|---|---|
| `.wpd/.wp/.wp5/.wp6` | libwpd/librevenge worker/WASM; ordered structured text, tables, running sections and notes | Persistent layout warning; no original pagination, embedded images/fonts, drawings or equations. No implicit approximate-text fallback. |
| `.chm` | ITSF/LZX worker/WASM; contents/index/search and archive-local topic resources | Sanitized script-disabled topic frames; no merged-collection constituent discovery. |
| `.xls/.xlt/.xlsb` | Bounded spreadsheet worker and virtual worksheet grid | Saved formula values dominate; no full Excel recalculation, macro execution or legacy/binary chart extraction. Other spreadsheet candidates below are not automatically enabled. |
| `.ppt/.pot/.pps` | Local pure-JavaScript worker and virtual slide canvases | Supported geometry/pictures; Office-identical layout and animation are not promised. Existing native **Text fallback** is an explicit choice. |
| `.ps/.eps` | Stet worker/WASM rasterized pages and local font/color assets | Experimental PostScript, without complete Level 3 conformance. |
| `.xml/.xsd/.xsl/.xslt` | Existing tree/source view plus explicit **XSD / XSLT** tools | Schemas/stylesheets must be supplied; external resource resolution is disabled. Output does not overwrite source. |
| `.mbox` | CrispCloud-authored Dart indexing and existing email renderer; message chooser, navigation and selected-message search/copy | Bounded complete-mailbox indexing and lazy selected-message decoding. No upstream email runtime imported. |

The [package README](../packages/file_viewer_documents/README.md) records local
runtime assets, exact notices and matching source; the
[viewer guide](file-format-viewers.md) records app behavior and bounds. Its six
browser engines and the shipped host passed genuine Chromium smoke tests in
[CI run 43383695021](https://github.com/CrispStrobe/CrispCloud/actions/runs/43383695021)
against source `5404834`, alongside 61 engine Node tests. The Flutter JavaScript
web release build also passed, focused analysis was clean across 12 paths, and
the combined six-suite app integration run passed all 69 tests.
These are selected fixture/build checks, not complete format fidelity or
cross-platform acceptance. Native WebKit/WebView and individual OS/device
acceptance remain pending. The rest of this document retains the broader pinned
upstream survey; a candidate row does not mean its runtime ships in CrispCloud.

## Reading the effective licenses

- Every table includes the Apache-2.0 File Viewer adapter unless stated otherwise.
  `+` means several applicable licenses coexist; it does not relicense the
  combined product. Shared DOMPurify 3.4.17 permits an Apache-2.0 election.
- JSZip 3.10.2 offers `MIT OR GPL-3.0-or-later`; these candidates select **MIT**.
  Its bundled compression/helpers still retain their own MIT/Zlib/other permissive
  notices. A dual license is different from an `AND` combination.
- **Candidate** means the identified code path fits the expanded software policy.
  Actual imported files, codecs, fonts and generated bundles still need an exact
  distribution inventory. An Apache package name is not that inventory.
- **Separate decision** marks LGPL/GPL/AGPL/EPL or custom terms outside the named
  policy. It is not a claim that these licenses are inherently incompatible with
  CrispCloud. **Unresolved** means exact linked-material evidence is incomplete.
- Asset terms are stated separately: OFL, GUST/LPPL, Bitstream/Arev, CC0, Adobe
  CMap/Foxit grants, etc. A user's opened document/font does not become an app
  asset merely because it can be previewed.

## Office and legacy documents

Detailed execution paths, component grants and immutable links are preserved in
the [office audit](evidence/file-viewer-expanded-license-20261113/office-audit.md).

| Formats | Engine / real output | Effective software licenses | Value and limits |
|---|---|---|---|
| **WordPerfect `.wpd/.wp/.wp5/.wp6`** | libwpd 0.10.3 + librevenge 0.0.6 in a Worker/WASM; structured text and tables | **Apache-2.0 + MPL-2.0** elected for both native libraries + MIT bridge + Boost BSL-1.0 + permissive LLVM/Emscripten/musl/Zlib/CC0 materials | **Implemented F3 route.** CrispCloud fixes paragraph/table order and exposes layout limits; graphics and original pagination remain incomplete. `.wpt` is not routed. Details below. |
| **Word `.doc/.dot`** | `@file-viewer/doc` 3.3.3, public msdoc-viewer 0.2.0 lineage; OLE/CFB → Word model → HTML/CSS | **Apache-2.0 + MIT**, with DOMPurify Apache election | Existing native DOC is already substantial. Compare isolated missing behaviors; do not replace on format-count grounds. Word 97–2003 binary, not a universal historical Word reader. |
| **DOCX/DOCM/DOTX/DOTM; Word 2003 XML** | `@file-viewer/docx` 0.3.39; ZIP/XML → browser pages. WordML first converts to OOXML | **Apache-2.0 + MIT + Zlib/helper notices** | DOCX family already supported; **Word 2003 XML detection/adaptation is new** for Word-suffixed files, not a general XML association. No VBA execution or wrapper password path. Exact DOCX tarball license verified against lock integrity. |
| **RTF** | Optional `rtf.js` 3.0.9 loader → DOM, including supported WMF/EMF pictures | **Apache-2.0 + MIT**; codepage 1.15.0 Apache | Existing basic native RTF could gain pictures/formatting. Loader must be registered explicitly. |
| **Legacy PPT/POT** | `@file-viewer/ppt` 1.0.2 compiled JS; CFB → slide model → SVG → Canvas | **Apache-2.0** runtime and adapter, no production dependencies | **Implemented F3 visual route for PPT/POT/PPS**, with explicit native Text fallback. Already eligible under Apache-only. Public compiled JS exists; upstream TS development source is private. Current wrapper does not expose engine password support. `.pps` is a CrispCloud alias, absent from upstream's pinned catalog. |
| **PPTX/PPTM/POTX/POTM/PPSX/PPSM** | Workspace PPTX 3.3.3; ZIP/XML → HTML/SVG slides | **Apache-2.0 + MIT + Zlib/helper notices** | Existing PPTX family, extra suffixes and fidelity candidates. Static preview; host fonts affect appearance. |
| **XLS/XLSB, XLT/XLA/XLAM/XLTM; XLSX/XLSM/XLTX/CSV/TSV/ODS/FODS** | styled-exceljs 0.21.6 + e-virt-table 1.4.17; workbook → virtual grid | **Apache-2.0 + MIT + Zlib/helper notices** | **XLS/XLT/XLSB are implemented F3 routes.** FODS and other extra template/add-in suffixes remain candidates; existing modern spreadsheet routes are retained. Saved formula caches dominate; not full Excel recalculation. No macro/add-in execution. Exact e-virt-table 1.4.17 MIT payload verified. |
| **DBF** | Same spreadsheet path; dBASE III/IV and Visual FoxPro tables | **Apache-2.0 + MIT + Zlib/helper notices** | **New candidate.** Missing DBT/FPT memo sidecars yield incomplete cells. |
| **Pages/Numbers/Keynote `.pages/.numbers/.key`** | Own XML/IWA parsers, keynote-archives 2.0.1; static scenes/workbooks | **Apache-2.0 + MIT + BSD-3-Clause + 0BSD + Zlib** | **New candidates.** iWork '09 and modern IWA containers; Quick Look images are fallback only. No encrypted iwpv2, transitions, media playback or full recalculation. |
| **Hangul `.hwp/.hwpx`** | HWPv5 binary/CFB and HWPX XML; own parsers + hwpxjs 0.4.0 | **Apache-2.0 + MIT + Zlib** | **New candidates.** Static structured pages; no HWP3 promise. Encryption/distribution protection rejected. Charts/OLE/difficult drawing and pagination limited. |
| **ODT/ODP** | Own `content.xml` text extraction through JSZip | **Apache-2.0 + MIT + permissive compression helpers** | Existing formats; little upgrade. ODT groups headings before paragraphs; no faithful original table/image/layout model. ODS/FODS use the spreadsheet path above. |

### How legacy DOC actually renders

The signature dispatcher separates binary Word from OOXML, Word 2003 XML,
HTML and other content with a Word suffix. Genuine OLE/CFB is opened locally;
the engine reads `WordDocument`, `0Table`/`1Table` and `Data`, parses the FIB and
CLX piece tables, resolves styles, fonts and paragraph/character formatting, and
builds paragraphs, tables and assets. It then generates HTML/CSS and sanitizes it
before mounting it in the browser. The wrapper does not pass the optional Worker
client, so this default path parses on the main thread.

This uses neither Microsoft Office nor LibreOffice nor a conversion service.
It reconstructs a readable document using browser layout and fonts. Supported
images include raster pictures and partial WMF/EMF conversion; OLE attachments
are represented, not launched. Encryption is rejected. Textboxes can be
linearized after the main body, and recognizing Word story lengths does not
establish full header/footer/footnote layout support.

The parser itself is **MIT**, including the retained 2026 msdoc-viewer contributor
notice. The wrapper's Apache license does not replace that grant. CrispCloud's
existing `legacy_doc_parser` already models multiple stories, notes/comments,
nested tables, supported OfficeArt, revisions, images and conversion semantics.
Its MPL-2.0 package-authored code and retained MIT/0BSD sources are allowed under
the updated policy. Borrowing a proven improvement is more compelling than
replacing the native pipeline with another partial Word layout engine.
The [detailed DOC/DOT comparison](file-viewer-doc-dot-comparison.md) separates
parser-model capability from the current F3 adapters and reports the 19-fixture
differential probe. The selected browser package does not import the DOC engine.

### How WordPerfect actually renders

The default path sends bytes to a module Worker, loads `libwpd.mjs` and
`libwpd.wasm`, and calls libwpd through librevenge. An MIT-licensed C++ callback
bridge emits a versioned binary event stream; TypeScript decodes it into a
document model and creates DOM text, spans and tables. There is **no DOCX/PDF
intermediate**. Selecting the MPL-2.0 option for libwpd/librevenge fits the user's
expanded policy without electing their LGPL alternative.

The model carries paragraphs, styles, lists, links, tables, headers/footers and
notes. The **pinned upstream implementation** has concrete losses:

- The bridge discards page spans, embedded fonts, frames, binary objects,
  equations and vector drawing callbacks.
- The renderer emits body paragraphs first and all tables afterward; original
  paragraph/table interleaving is lost. Table cells are mostly plain text.
- Structured libwpd failures inside a running Worker switch to approximate text
  extraction. Worker startup errors, timeouts and aborts still fail. Model
  warnings exist, but the current DOM view does not show them. Disabling Workers
  also goes directly to text fallback.
- The fallback has a 128 MiB limit, but the normal WASM allocation happens
  before that fallback check. CrispCloud must apply its own bounded read and
  resource ceilings before invoking the engine.

The [CrispCloud overlay](../packages/file_viewer_documents/engines/wordperfect/UPSTREAM.md)
implements **structured WordPerfect reading** with those integration repairs:
it preserves paragraph/table callback order, displays a persistent fidelity
notice, rejects input above 64 MiB before WASM allocation, adds decoded-output
bounds and requires the real structured engine. Worker/parser failure is
reported instead of silently returning approximate text. Graphics, embedded
fonts, equations, drawings and original pagination remain outside this preview.
The exact WASM has been exercised against WP4.2, 5.0, 5.1 and 6.x fixtures, with
ordered DOM and warning behavior checked in Chromium; this is not a version-wide
fidelity guarantee. `.wp5` and `.wp6` are routing aliases for matching content;
`.wpt` is absent from the catalog.

The retained native provenance is relatively strong: pinned corresponding
libwpd/librevenge sources, shim source, toolchain grants and linked library list.
The vendored loader and WASM SHA-256 values were independently checked against
their manifest and matched. This audit did not rebuild them.

## Books, help, email, images, media and archives

See the [remaining-format audit](evidence/file-viewer-expanded-license-20261113/other-audit.md)
for exact versions, retained notices and source links.

| Formats | Real output | Effective software / asset licenses | Assessment |
|---|---|---|---|
| **CHM** | Local Rust/WASM ITSF v2/v3 and LZX; topic HTML, contents/index/search and archive-local resources | **Apache-2.0 + MIT**, with permissive BSD/Unicode/Rust runtime notices | **Implemented F3 route.** Not a CHMLib/libmspack runtime. Scripts/ActiveX/network blocked; merged help collections require separate constituent files. |
| **UMD** | Structured book metadata and chapters | **Apache-2.0 + MIT + Zlib** (pako 2.2.0) | **Small new reading candidate.** Preserve encoding/inflation bounds. |
| **EPUB/FB2** | EPUB.js chapters/navigation/search; own FB2 semantic book parser | EPUB: **Apache-2.0 + BSD-2-Clause + MIT + Zlib**; FB2: **Apache-2.0** and shared sanitizer | Already covered through CrispCloud/CrisperBooks. EPUB.js 0.3.93 is BSD-2, not Apache. No upstream Kindle renderer. |
| **CBZ/CBR** | Sequential images, natural ordering, page count, keyboard/swipe | **Apache-2.0 controller**, plus the selected archive/image engines | Prefer porting controller behavior onto existing CrispCloud archive/image services. Upstream libarchive WASM has unresolved provenance below. |
| **EML/MSG/MBOX** | Upstream: decoded mail and attachments; **MBOX only its first message plus count** | Upstream: **Apache-2.0 + MIT-0** postal-mime 4.1.4; MSG adds Apache msgreader 1.29.0, **BSD-2-Clause** decompressrtf 0.1.4 and MIT helpers | Existing EML/MSG retained. **MBOX now implemented independently in CrispCloud Dart**, with indexed message navigation and selected-message search/copy; the upstream dependencies in this row are not imported. No PST/OST. |
| **PDF** | PDF.js 5.4.624 pages, outline/search/print; optional font repair | **Apache-2.0 + MIT + BSD-2/BSD-3**, plus **OFL-1.1** fonts | Existing viewer; targeted improvements. Adobe CMaps/Foxit fonts, OpenJPEG/JBIG2 and qcms have distinct notices. Noto patch-version attribution needs correction. |
| **TIFF/TIF** | UTIF 3.1.0; bounded multipage pixel decode, page navigation/rotation | **Apache-2.0 + MIT + Zlib** | Candidate enhancement over current image path; compare actual existing TIFF behavior. |
| **PNG/JPEG/GIF/BMP/WebP/ICO/SVG; AVIF/JXL** | Browser image decoding with viewer controls | **Apache-2.0 adapter**, shared sanitizer where applicable | Existing common images. **AVIF/JXL decoding depends on the browser**; no standalone bundled decoder in this path. HEIC is separate below. |
| **DICOM `.dcm/.dicom`** | Cornerstone 5.13.2 local Part 10/multiframe pixels, window/level and frame controls | **Apache-2.0 + MIT + BSD-2/BSD-3 + ISC + IJG + Zlib**, selected codec notices; conservative source inventory also includes **Python-2.0** and **CC-BY-4.0 data** | New larger optional feature. Exact delivered manifest determines which source-inventory entries ship. No series/PACS/MPR/segmentation/measurement workstation. |
| **ZIP/7Z/RAR/TAR and archive families** | libarchive.js 2.0.2 listing/extraction/nested previews; narrower ZIP/TAR/GZIP fallback | MIT wrapper; **BSD-2-Clause libarchive + Zlib + bzip2 + public-domain liblzma + old OpenSSL/SSLeay**, exact binary closure **unresolved** | Existing archive stack is preferable. Source recipe and actual WASM disagree on bzip2 version. Do not approve the whole binary from wrapper metadata. |
| **MP4/WebM and common audio** | Browser playback; narrow MPEG-4 Part 2 `mp4v` fallback | **Apache-2.0 adapter/AOSP decoder**, linked **MIT/NCSA, Apache with LLVM exception, musl MIT, public-domain/CC0** runtime materials | Existing broader media stack. This is not a general software codec engine. |
| **HLS `.m3u8`** | Optional hls.js 1.7.3 streaming | **Apache-2.0** | Optional web playback enhancement. |
| **MIDI `.mid/.midi`** | Track/note/tempo inspection through tonejs/midi 2.0.28 | **Apache-2.0 + MIT** | Useful inspector; no synthesized audio output. |
| **Text/code/Markdown; patch/Git bundle tools** | Highlighting, formatting, sanitized Markdown; optional diff/bundle inspection | **Apache-2.0 + MIT + BSD-3-Clause + Zlib**, with selected transitive notices | Existing viewing overlap. IPYNB/TeX are source display, not notebook execution/typesetting. |
| **XML with optional XSD/XSLT tools** | xmllint-wasm 5.3.0 and xslt-polyfill 1.0.33; real bounded validation/transformation | **Apache-2.0 + BSD-3-Clause + MIT-style libxml2/libxslt + Zlib** | **Implemented optional F3 tools for XML/XSD/XSL/XSLT**, alongside native tree/source. External resources disabled. Exact linked zlib version is not identified in upstream metadata. |

Archive catalog extensions include `.zip/.zipx/.7z/.rar/.tar`, gzip/bzip2/xz/
lzma/zstd aliases, `.cab/.ar/.cpio/.iso/.xar/.lha/.lzh`, Java/Android ZIP packages,
and `.cbz/.cbr`. This is a dispatch inventory; not every codec was exercised or
proven present in the prebuilt WASM. In particular, Zstandard support in that
binary was not established by this review.

## Data, geography, mind maps and signed containers

| Formats | Real output | Effective software licenses | Assessment |
|---|---|---|---|
| **SQLite `.sqlite`** | sql.js 1.15.2 WASM; table/view inventory and first table/view sample, at most 30 rows | **Apache-2.0 + MIT + SQLite public-domain material** | New structured preview over current binary view; not a DB editor. `.db` is not a promised upstream extension alias. |
| **Parquet `.parquet`** | hyparquet 1.31.5; schema/column metadata and first 30 rows | **Apache-2.0 + MIT** | New useful data inspection, not a complete analytic grid. |
| **Avro `.avro`** | avsc 5.7.9; object-container schema and first 30 records | **Apache-2.0 + MIT**, browser shims retain permissive notices | New candidate. Limited displayed rows do not prove bounded whole-input decoding. |
| **GeoJSON/KML/GPX/SHP** | MapLibre 6.16.0 overlays; togeojson 7.1.3, shpjs 6.2.0 and proj4 2.22.0 | **Apache-2.0 + BSD-3-Clause + BSD-2-Clause + MIT**, transitive ISC/Zlib/CC0 notices | New geometry/map previews. Offline empty basemap, pan/zoom; SVG fallback. Basemap data and tile-provider terms are separate. Do not infer GeoTIFF preview from a transitive dependency. |
| **XMind `.xmind`** | xmind-parser 1.1.3 + Panzoom 4.6.2; classic XML/modern JSON, sheets and hierarchical canvas | **Apache-2.0 + MIT + permissive JSZip helpers** | New mind-map preview. Not a general FreeMind/other mind-map format reader. |
| **OFD `.ofd`** | Vendored DLTech21/ofd.js; fixed pages, zoom/print and visible electronic seals | **Apache-2.0 + MIT + ISC**, retained PDF.js/JBIG2 and Glyph & Cog permissive notices | New candidate. Seal appearance is not cryptographic signature verification. |
| **Typst `.typ/.typst`** | typst.ts, renderer/compiler 0.7.0; WASM compilation to paged SVG | **Apache-2.0 + MIT/BSD/Zlib/Unicode/CC0 + MPL-2.0** (`option-ext`), plus separate font grants | New actual typesetting. Libertinus OFL-1.1; New Computer Modern GUST/LPPL-1.3c-or-later; DejaVu Bitstream/Arev. Native inventory's final review is pending. |
| **CMS/PKCS7, timestamp, ASiC, ERS, JWS, OpenPGP** | Optional signature renderer; bounded container/metadata inspection, extraction and selected cryptographic verification; rPGP 0.20.0 WASM | **Apache-2.0 + MIT + BSD/ISC/Zlib/Unicode and other retained permissive grants**; rPGP MIT/Apache selection | New optional inspector, not a general certificate-trust/qualified-signature validator. No private-key operations or automatic decryption. Not in the frozen preset-all runtime. |
| **TTF/OTF/WOFF/WOFF2** | Browser FontFace specimen | **Apache-2.0** adapter | Existing font preview. Font files distributed with the app need their own rights. |
| **WASM; binary headers; LRC** | WASM imports/exports inspection; selected binary structure; static lyrics | **Apache-2.0** selected code paths | Binary and LRC extracts already integrated. WASM compile/introspection does not instantiate a document's module. |
| **WebArchive** | Generic safe summary/readable snippets | **Apache-2.0** selected data path | Metadata/text fallback, not a reconstructed offline webpage. |

Primary sources: [data scope][data], [data implementation][data-src], [geo][geo],
[XMind][mindmap], [OFD][ofd], [Typst][typst], [Typst native ledger][typst-book],
[Typst fonts][typst-fonts], [signature][signature] and [signature licenses][signature-licenses].
Exact registry declarations for 63 locked data/geo/mindmap dependencies were
queried, with no failed lookups. All offer permissive choices; details are in
[metadata evidence](evidence/file-viewer-expanded-license-20261113/data-geo-mindmap-license-evidence.json).
That checks package declarations, not the contents of every generated bundle.

Signature extensions are `.p7m/.p7s/.p7b/.p7c/.pkcs7/.cms/.cmsc`,
`.tsq/.tsr/.tst/.tsd`, `.asics/.scs/.asice/.sce`, `.ers`, `.jws`, and
`.asc/.sig/.pgp/.gpg`. Detached verification requires the appropriate original
content and host-supplied public keys. Parsing, mathematical verification and
trust are separate outcomes in the upstream UI.

## Design, 3D, CAD and engineering

Full source links, asset terms and exact route boundaries are in the
[engineering audit](evidence/file-viewer-expanded-license-20261113/engineering-audit.md).

| Formats | Real output | Effective software / asset licenses | Assessment |
|---|---|---|---|
| **PSD/PDD/PSDT; PSB** | Saved composites, layer inventory, limited PSD recomposition | **Apache-2.0 + MIT**: ag-psd 31.0.3, webtoon/psd 0.4.0 and helpers | Candidate enhancement. 8-bit RGB/grayscale saved composites can retain effects; masks/effects/complex layers limit interactive recomposition. Unsupported color/depth variants and ZIP-compressed PSB channels are rejected. ag-psd notice label is stale. |
| **AI/AIT** | Prefer verified saved PDF surface; native PGF artboards/paths/layers with limited fidelity | **Apache-2.0 + MIT** illustrator-pgf 0.1.0/fzstd, plus PDF asset stack when used | New candidate, experimental. Complex text, gradients, embedded images, effects and print color fidelity incomplete. |
| **EPS/PS** | Stet 0.8.7 / stet-wasm 0.2.0 local Worker/WASM page rasterization | **Apache-2.0 or MIT** engine + permissive dependencies; **OFL-1.1 URW fonts + CC0 ICC profile** | **Implemented F3 route with retained asset notices.** Experimental PostScript engine, not Ghostscript; not complete Level 3 conformance. |
| **IDML** | Introspect WASM 0.73.4 page rendering | **Apache-2.0 + MPL-2.0** elected for Introspect, plus MIT/BSD/Zlib/Unicode; Adobe CMap and Foxit-named asset grants are **BSD-3-Clause** | New candidate with covered-source obligations. Bounded ZIP/Worker path; not native INDD parsing. Native-material review and source retained; no final release approval or bit-for-bit WASM rebuild asserted. |
| **ICML/IDMS/INX** | Styled story, bounded layout fragment or partial legacy layout/structure | **Apache-2.0 + ISC + MIT** (`saxes`, `xmlchars`) | Candidates with explicitly limited layout. Linked assets are not fetched. |
| **INDD/INDT; XD** | Embedded verified thumbnail/rendition plus structure inventory | **Apache-2.0 + permissive support bundle** | Candidate **preview/metadata only**. No native InDesign layout database or XD vector reconstruction. |
| **Modern FLA/XFL** | CS5+ ZIP/XFL; bounded first-frame shapes/text/images | **Apache-2.0 + MIT** | Static candidate; legacy binary FLA rejected. No ActionScript, full animation or media execution. Standalone XFL markers need sibling files. |
| **ASE/ACO; ABR/CSH/PAT/GRD/ASL** | Color swatches, brush tips, paths, tiles, gradients and effect descriptors | **Apache-2.0**, with **MIT** ag-psd/helpers where used | Useful resource inspection. No Photoshop brush/effect engine or print-reference color fidelity. Version restrictions apply. |
| **GLB/glTF, OBJ, STL, PLY, FBX, DAE, 3DS, 3MF, AMF, USD variants, KMZ, PCD, WRL/VRML, XYZ, VTK/VTP** | Three.js 0.186.1 loaders → interactive meshes/scenes | **Apache-2.0 + MIT** selected mesh path; preserve exact addon/codec notices | Candidate **only after excluding the LGPL OCCT engine/assets from the build**. Basic glTF lacks Draco/KTX2/Meshopt setup; OBJ does not load MTL. Sibling assets may be unavailable. |
| **IFC via optional `/ifc` entry** | Geometry, element selection and basic properties | **Apache-2.0 + MIT** That Open components/fragments 3.6.0/Three + **MPL-2.0 web-ifc 0.0.77**, permissive helpers | New candidate with source/notices. Ordinary model route is diagnostic; explicitly use optional IFC entry. No full BIM authoring/clash checking. |
| **GDSII `.gds`** | Stream structures/boundaries/paths/references → SVG/WebGL | **Apache-2.0** standalone parser | Candidate for semiconductor layout inspection, not DRC/LVS or complete hierarchy tooling. |
| **OAS/OASIS** | Binary recognition/indexing/diagnostics | **Apache-2.0** | Limited inspector. Actual industrial binary geometry/repetition expansion is absent; rendered examples use readable text fixtures. |
| **OrCAD OLB / Allegro DRA** | Compound tree, strings and object candidates | **Apache-2.0**, including CFB/checksum helpers | Limited inspector, not complete symbols/footprints. PSM/PAD are not registered full viewers. |

### Routes requiring a separate license decision or build exclusion

| Route | Effective license issue | Consequence |
|---|---|---|
| **DXF** | cad-viewer 0.8.3 **AGPL-3.0** | Bundled route is outside the stated policy. Its Apache adapter is insufficient by itself. |
| **DWG** | Same **AGPL-3.0**, plus LibreDWG/libredwg-web 0.7.9 **GPL-3.0** | Separate policy decision; Worker/WASM packaging does not remove these grants. |
| **DWF/DWFX/XPS** | dwf-viewer 0.6.7 + CAD **AGPL-3.0** | Outside named policy for this implementation. |
| **STEP/STP/IGES/IGS/BREP** | occt-import-js 0.0.23 **LGPL-2.1-only**, OCCT 7.6.1 **LGPL-2.1 with exception** | Real geometry support, but LGPL has not been selected. Ordinary 3D package also depends on this engine. |
| **Mermaid/MMD** | Mermaid 12.2.0 MIT plus **elkjs 0.9.3 EPL-2.0**, retained underlying Java notices | Additional license decision or a verified distribution excluding EPL material. Lazy loading alone is not exclusion. |
| **BPMN** | bpmn-js 18.31.1 **custom bpmn.io license**, diagram-js 15.28.1 MIT | Visible unmodified/uncovered watermark condition. Separate decision; requires BPMN DI layout for diagrams. |
| **Official draw.io offline assets** | Apache viewer plus **custom Atlassian-related restriction** on icons/shapes/stencils, plus font grants | Do not classify the whole asset pack Apache/MIT. Avoid or separately evaluate these assets. |
| **HEIC/HEIF JS conversion** | heic2any MIT wrapper around a **libheif copyleft binary** | Not MIT-only. Exact binary/codec grant evidence unresolved; native browser decoding is a different path. |
| **Full libarchive WASM / CBR route** | Permissive wrapper/core, but exact prebuilt linked compression/crypto materials not reconciled, including old OpenSSL/SSLeay | Potentially reusable after actual binary/source/notices are resolved; not approved by a BSD package label alone. |

The built-in **draw.io/DIO SVG subset** can use Apache-only parsing, but it reads
embedded XML `mxGraphModel` and does not inflate compressed diagram payloads in
that fallback. **Excalidraw** has a read-only rough.js 4.6.6 **MIT** SVG fallback
under the Apache adapter; the optional host-provided official Excalidraw runtime
is not version-pinned here. The drawing package also depends on Mermaid, so
the selected fallback build must omit unwanted dependency/assets.

**PlantUML/PUML** is Apache source display offline, with optional MIT
plantuml-encoder 1.4.0 for a configured rendering service. There is no bundled
local PlantUML layout engine. **Rhino 3DM** has diagnostics rather than actual
geometry. **Gerber, Excellon, KiCad, Visio, OFF, WordPerfect WPT, PST/OST, DjVu and
Kindle MOBI/AZW** should not be claimed as working viewers supplied by this pin;
an application's separate implementation is a different matter.

## Evidence quality and implementation choices

The upstream catalog is a routing inventory, not proof of fidelity or a license
clearance of every distributed asset. This review followed source dispatch,
parser calls, package locks, retained license texts and native/asset provenance.
Where useful, exact published archives were fetched without running scripts.

Verified details include the WordPerfect loader/WASM hashes; the exact MIT
e-virt-table 1.4.17 and Apache DOCX 0.3.39 tarballs matching both registry and
upstream lock integrity; 63 data/geo/mindmap dependency declarations; and direct
inspection of source limits that broad catalog labels omit. Those checks do not
substitute for representative document rendering tests.

The following issues remain at the integration checkpoint:

- **Version attribution:** ag-psd is locked at 31.0.3 but design notices/catalog
  still name 31.0.2. bpmn-js/diagram-js are 18.31.1/15.28.1 but one notice says
  18.28.0/15.26.0. PDF's Noto asset ledger and manifest also differ by patch
  version. Reconcile actual files and notices.
- **Native ledgers:** Typst lists 352 conservative normal dependencies before
  stripping, pending final review and `releaseApproval: false`. Introspect's
  native-material review is complete with no missing materials, but separately
  disclaims final release approval and a bit-for-bit rebuild. These are source
  inventories, not a statement that every package ships or every binary was
  reproduced.
- **Distribution boundaries:** selected 3D and drawing entries must prove
  exclusion of unwanted OCCT, ELK and custom asset bundles. Inspect generated
  chunks and copied assets, not just package import syntax.
- **Fidelity and resource bounds:** the selected WordPerfect overlay repairs
  block order and failure reporting, and the six selected adapters carry bounded
  file/ZIP/XML/image/worker checks. Continue platform acceptance and benchmark
  any DOC changes against the native corpus; test real documents for newer
  iWork/Hangul/design candidates before importing them.

Most upstream renderers produce browser DOM/Canvas/SVG from TypeScript and some
use WASM. CrispCloud is Flutter. The six selected engines now use the isolated
local browser surface in `file_viewer_documents`; MBOX uses a native Dart
indexer. Remaining license-compatible formats still need an implementation
decision: a small parser port and native widget, a narrow native FFI/WASM
boundary, or an isolated web rendering surface. Reusing complete Vue/browser UI
packages is more invasive than extracting a parser/model.

Priority status and remaining increments, based on new coverage and identified gaps:

1. **WordPerfect:** implemented with the integration repairs and matching MPL
   source/notices. Broader document fidelity and native platform acceptance remain.
2. **CHM and older spreadsheets:** CHM and XLS/XLT/XLSB are implemented;
   **DBF/FODS** remain useful candidates with precise unsupported/encrypted/memo
   behavior to validate.
3. **Hangul and iWork:** meaningful new document families; validate a producer and
   version corpus before broad fidelity claims.
4. **PPT visual rendering:** implemented beside the explicit native text fallback;
   the maintainability cost of compiled-only upstream source remains.
5. **Data/GIS/XMind/OFD**, then **IDML/IFC** according to actual user demand and
   the larger runtime/asset costs. **PostScript/EPS** is already in the selected
   implementation, with experimental-engine and asset limits retained.

MPL redistribution needs access to the corresponding covered source and changes,
license notices and a clear way for recipients to obtain that source. Newly
written separate files without MPL material need not become MPL merely by
combination; copied or modified covered files remain within its boundary. See
the [Mozilla FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/). Apache redistribution
also retains licenses, applicable notices and change markings under
[section 4](https://www.apache.org/licenses/LICENSE-2.0). Fonts and other assets
need their own retained grants even when all code has a permissive selection.

## Primary source index

The detailed evidence reports link each engineering/office/remaining-format row
to immutable source. These additional links cover the root data/geo/typography
review. All File Viewer references are pinned to the reviewed commit.

[data]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/data/README.en.md
[data-src]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/data/src/data.ts
[geo]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/geo/README.en.md
[mindmap]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/mindmap/README.en.md
[ofd]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/ofd/README.en.md
[typst]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/typst/README.en.md
[typst-book]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/typst/assets/NATIVE_THIRD_PARTY_LICENSES.json
[typst-fonts]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/typst/assets/fonts/README.md
[signature]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/signature/README.en.md
[signature-licenses]: https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/signature/THIRD_PARTY_LICENSES.json
