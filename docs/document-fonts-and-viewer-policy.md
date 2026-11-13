# Document fonts, size, and alternative viewers

Audit date: 2026-11-13. Runtime/code baseline:
`087b73a14b64c445c5eb717f187925b5472ed9b3`, on
`feature/apache-file-viewer-20261113`. The first audit checkpoint is
`b3b03807bcbde5f77fd842e8eb9918807be64376`. Measurements and probes use the
unchanged implementation and existing release JavaScript web build. This
assessment changes documentation and evidence, not production rendering or
packaging. Recommendations are not implemented fixes.

## Recommended decision

Keep one maintained primary engine per format, the existing complementary
reading/source modes, and explicit system/installed-application alternatives.
Improve font integration and redundant packaging before adding a second embedded
DOC or XML engine. The current set has useful coverage, but font handling is
inconsistent and has demonstrated gaps. It does not establish universally best
rendering.

The next implementation should fix the DOC HTML font-name boundary, supply
existing script-covering fonts to Office PDF export, make font selection
consistent before the first preview, correct broad substitution aliases, and
perform the small packaging changes below. Keep the PS Base35 set intact.

## 1. What is actually used today

### Office, mail, and structured text

| Format / surface | Actual font behavior | Qualification |
| --- | --- | --- |
| DOC/DOT Formatted, F3 and side pane | Native parser emits document font names in safe HTML; Flutter `HtmlWidget` paints it. | Hex-escaped CSS font strings are not decoded by the pinned Flutter HTML package. The requested font becomes a literal escaped name and ordinary named fonts fall through. Bold and size remain intact. |
| DOC/DOT Text and F3 source | `AppMono`, bundled Roboto Mono Regular, with platform monospace fallbacks. | The side pane's general text fallback still uses generic `monospace`; unify it with F3. |
| DOCX/DOCM/DOTX/DOTM Formatted | OOXML-to-Markdown projection, then Flutter theme/default typeface. | Original run families and embedded Word font programs are not reproduced in this reading view. |
| DOCX and other supported OOXML Pages | Quds PDF export with **only bundled Roboto Regular** supplied by the app. | Requested document families are not resolved; bold/italic are synthesized. Missing non-WinAnsi characters can be omitted if no covering face is supplied. |
| Native Office editor | Liberation Sans/Serif/Mono in regular/bold/italic/bold-italic; Noto Naskh Arabic regular/bold. | ASCII/non-RTL versus complex-script/RTL selection exists, but broad aliases substitute several unlike families. Registration happens when opening the editor, not consistently before F3. |
| RTF preview | Flutter/default font through safe HTML. | The parsed font table helps decode text; it is not a font-face reproduction path. |
| PPTX simplified Slides | Flutter/default font; the simplified shape model has size/bold/color but no family. | Pages has the same single-Roboto export issue. |
| Binary PPT/POT/PPS | Parsed run font names go into SVG/HTML/Canvas; default Arial and sans-serif fallback. | Browser/WebView font availability and metrics govern layout. The selected adapter disables the optional PPT font/WASM bundle. |
| XLS/XLT/XLSB | Cell families and sizes flow into Canvas/DOM; default stack `Aptos, Calibri, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif`. | These are font requests, not bundled Aptos/Calibri/etc. There is no shared metric-substitution policy. |
| WordPerfect | `Georgia, 'Times New Roman', serif`, 16px base; supported emphasis survives. | Current run model does not carry source font family/size. More installed fonts alone cannot restore those properties. |
| CHM | System UI default; sanitized topic CSS may request local faces. | Bounded archive-contained WOFF/WOFF2/TTF/OTF resources can load through rewritten blob URLs. External resources remain disabled. |
| XML Tree/Source | Native `AppMono`/Roboto Mono, with Menlo/Consolas/monospace fallback. | XML data has no intrinsic page font. Tools UI uses system-ui; tool text/output uses browser monospace. |
| XSLT HTML result | Sanitized authored inline CSS or browser default in an inert iframe. | CSP disallows fetched/font-URL resources. Source output remains separately available. |
| MBOX/EML | Existing Flutter email body typography, 14px times zoom. | Sanitization removes source style/font attributes. Text/Formatted modes favor reading over original email typography. |
| EPUB/CrisperBooks | Foliate defaults to serif, supports generic-family choice and publication styles/local fonts. | Foliate handles local EPUB font deobfuscation/resources. The portable Flutter reader does not provide the same embedded-font registration. |

Sources: [Office extraction](../lib/services/office_document_service.dart),
[Office PDF service](../lib/services/office_pdf_service.dart),
[F3 modes](../lib/widgets/internal_viewer_dialog.dart),
[native font registry](../packages/quds_office_editor/lib/src/embed/office_host_fonts.dart),
[native Word paint](../packages/quds_office_editor/lib/src/editor_word/paint_run_text.dart),
[WordPerfect](../packages/file_viewer_documents/engines/wordperfect/src/wordperfect.ts),
[PPT options](../packages/file_viewer_documents/engines/ppt/src/entry.ts),
[CHM resources](../packages/file_viewer_documents/engines/chm/src/chm.ts),
[XML result](../packages/file_viewer_documents/engines/xml/src/entry.ts),
[mail](../lib/widgets/email_message_view.dart).
EPUB source is pinned in the app pubspec to CrisperBooks
`32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52`.

### PDF fonts already present

PDF editor assets include Carlito in four styles; TeX Gyre Heros, Termes, and
Cursor in four styles; Adventor regular/bold; DejaVu Sans/Serif/Sans Mono; and
editor choices Fira Sans, Spectral, and Lobster. The editor substitutes Calibri
with actual Carlito, Helvetica/Arial with Heros, Times with Termes, Courier with
Cursor, and Century Gothic/Avant Garde with Adventor. Supported embedded PDF
font programs have a separate path. F3's `pdfx` page renderer has its own
platform behavior: this inventory does not imply every PDF surface uses the
editor's resolver.

[PDF policy](../packages/dart_pdf_editor/lib/src/font_substitution.dart) and
[font attribution](../assets/licenses/pdf_fonts/FONT-COPYRIGHTS.txt).

### PS and EPS have a separate font environment

Both use one Stet interpreter, with 35 URW Type 1 font programs embedded in its
WASM. These page pixels do not depend on Flutter font registration or browser
CSS. Styles map separately:

| PostScript family | Embedded URW family | Faces |
| --- | --- | ---: |
| Times | Nimbus Roman | 4 |
| Helvetica | Nimbus Sans | 4 |
| Helvetica Narrow | Nimbus Sans Narrow | 4 |
| Courier | Nimbus Mono PS | 4 |
| Palatino | P052 | 4 |
| New Century Schoolbook | C059 | 4 |
| Bookman | URW Bookman | 4 |
| Avant Garde | URW Gothic | 4 |
| Symbol | Standard Symbols PS | 1 |
| Zapf Dingbats | D050000L | 1 |
| Zapf Chancery | Z003 Medium Italic | 1 |

Missing PS fonts default to Helvetica/Nimbus Sans in the inspected interpreter
path. Source accepts supported document font definitions and contains Type 1,
TrueType/Type 42, and CFF machinery, but this audit does not qualify every
embedded-document font or CJK program. The existing test named "embedded-font
text" selects `/Helvetica`: it demonstrates engine-bundled fonts, not arbitrary
document embedding. The adapter has no system/external-font bridge.

The current `fontSubstitutes` output is a generic capability label, not a
per-document report of actual substitutions. Keep this distinction in future
diagnostics.

Exact Stet source: `58c7066817f7939789c6f030515c02e94fb0353b`, version 0.8.7,
`stet-wasm` 0.2.0. The [retained inventory](evidence/document-fonts-20261113/postscript-font-inventory.json)
verifies 37 manifest resources, all 35 font hashes and the alias table against
[app provenance](../packages/file_viewer_documents/engines/postscript/provenance/upstream.json).

### Effective font grants

| Shipped font group | Retained font license |
| --- | --- |
| App Roboto / Roboto Mono / Material Icons | Apache-2.0 for the pinned files |
| Liberation and Noto Naskh Arabic | SIL OFL-1.1 |
| Carlito, Fira Sans, Spectral, Lobster | SIL OFL-1.1 |
| TeX Gyre families | GUST Font License / retained LPPL terms |
| DejaVu families | Bitstream/Arev grants and public-domain DejaVu changes, as applicable to the face |
| Stet URW Base35 | Upstream's recorded OFL-1.1 election; retain its exact provenance and notices |

These asset grants are distinct from rendering software licenses. Loading a
user's document font also differs from redistributing it as an app asset. Keep
versions, hashes, original copyright and applicable reserved font names when
changing fonts. The historical URW election is recorded in
[the retained notice](../packages/file_viewer_documents/engines/postscript/licenses/Stet-URW-Fonts-OFL-1.1.txt).

## 2. Font changes with the best value

### Fix the DOC font-name boundary

`legacy_word_structured_render.dart` safely serializes Arial as
`font-family:'\41 \72 \69 \61 \6c '`. This is valid browser CSS. The pinned
`csslib` 1.0.2 / `flutter_widget_from_html_core` 0.17.4 path leaves the escapes
in the actual Flutter family. A real widget probe reproduced the literal name,
while preserving bold=700 and 17pt=22.6667px. This is a narrow interoperability
defect, not loss of all formatting or failure of the DOC parser.

Normalize/decode fonts at the bounded rendering boundary or introduce a safe
compatible serialization in the canonical parser. Preserve escaping, length
limits, and protection from injected CSS/URLs. No new font or parser payload is
needed. See [the probe and output](evidence/document-fonts-20261113/README.md).

### Reuse fonts for coverage, then improve family/style selection

The actual Roboto passed to Pages has no glyph for the inspected Hebrew,
Arabic, CJK, Japanese or Korean samples. Existing Liberation covers the Hebrew
sample; existing Noto Naskh covers Arabic. The exporter ultimately draws only
WinAnsi when there is no embedded covering face. Supplying already-bundled
covering faces can prevent a class of missing text without adding assets.
One sample does not prove complete script support or correct shaping.

`OfficeFontSet.faceFor(codePoint)` selects by glyph coverage, not requested
family, weight or slant. Passing every font is insufficient for Times-versus-Arial
fidelity. A later family/style resolver should use the same chosen face for
layout measurement and PDF emission, with real regular/bold/italic/bold-italic
faces. CFF TeX Gyre files are not drop-in export candidates: the exporter
currently requires TrueType `glyf`. Existing Liberation, Carlito and Noto TTFs
are suitable initial inputs.

Sources: [font set](../packages/quds_office_engine/lib/src/fonts/office_font_set.dart),
[PDF emission](../packages/quds_office_engine/lib/src/pdf/office_pdf_export.dart),
[coverage probe](evidence/document-fonts-20261113/font_coverage_probe.log).

### Share policy and bytes across compatible consumers

Use one small inventory and substitution policy with adapters for Flutter,
browser CSS/Canvas, and PDF export. Load needed faces and cache them; initialize
before the first applicable preview instead of waiting for the editor to open.
Keep document font metadata unchanged when only its on-screen substitute changes.

Useful mappings are Arial/Times New Roman/Courier New to Liberation
Sans/Serif/Mono, and Calibri to actual Carlito. Liberation names those three
metric targets; Carlito names Calibri. Broad aliases such as Georgia to
Liberation Serif or Calibri to Liberation Sans should be explicit approximations,
not registered as if they were original faces. Metric compatibility is a design
target: pin and validate actual versions and shaping/layout cases.

Primary references: [Liberation](https://github.com/liberationfonts/liberation-fonts),
[Carlito](https://github.com/googlefonts/carlito),
[a reported Carlito metrics issue](https://github.com/google/fonts/issues/9720),
[Flutter fallback semantics](https://api.flutter.dev/flutter/painting/TextStyle/fontFamilyFallback.html).

These environments do not share registration automatically. The document asset
server exposes its own package prefix and lacks a font MIME/path bridge to Quds
or PDF assets. Reuse needs a narrow allowlisted path and explicit browser
`FontFace`/CSS registration. Stet retains its native resources; generic Flutter
font names cannot replace its Base35 programs.

Add a new family/script pack only for a demonstrated coverage/layout requirement.
The inspected Office defaults do not supply CJK. Platform fallback where
available, accurate missing-glyph reporting, and optional regional assets are
preferable to an unmeasured universal collection. Embedded DOCX font extraction
and deobfuscation is a distinct later feature, absent from these preview/editor
paths.

## 3. Measured payload and practical optimizations

The selected document package occupies **24,914,367 raw bytes (23.76 MiB)** in
the existing release web output; built assets match source hashes. Static
dependency grouping counts shared files once:

| Component | Raw bytes | MiB |
| --- | ---: | ---: |
| PS/EPS exclusive runtime | 14,760,408 | 14.08 |
| XML/XSD/XSLT exclusive runtime | 2,221,990 | 2.12 |
| XLS/XLT/XLSB exclusive runtime | 2,085,971 | 1.99 |
| PPT/POT/PPS exclusive runtime | 967,200 | 0.92 |
| WordPerfect exclusive runtime | 571,412 | 0.54 |
| CHM exclusive runtime | 444,203 | 0.42 |
| Shared runtime | 360,700 | 0.34 |
| Host, manifest, other runtime | 121,096 | 0.12 |
| Notices: originals plus aggregate | 3,379,595 | 3.22 |
| Index HTML | 1,792 | 0.002 |

This conservative static partition includes optional feature imports; it is not
a first-open download trace. MBOX reuses Dart mail code and has no separate asset
engine here. DOC/DOCX and the rest of the app are outside this package total.

Separately, the full web build contains **46 standalone font files, 14,213,736
raw bytes (13.56 MiB)**: Quds 4,717,424 bytes; PDF assets 7,147,412; app fonts/full
icons 2,268,896; smaller generated icons 80,004. There are **no byte-identical
standalone font duplicates**. Similar-purpose fonts cannot be removed as ordinary
duplicate files.

Stet's WASM is 14,706,940 bytes, about 59% of the selected package total. Its 35
source font programs total 4,480,458 bytes (4.27 MiB), already inside WASM; do not
add them again. That source sum is not a measured saving from stripping fonts
and rebuilding.

Raw bytes describe assets, not APK/IPA download or installed app size. Per-file
gzip estimates total 13,905,996 bytes for this package; real transfer depends on
compression and cache. Store sizes need release-package/store reports.
[Flutter measurement guidance](https://docs.flutter.dev/perf/app-size) also
distinguishes upload packages from user downloads.

### Small changes before optional delivery infrastructure

| Candidate | Measured opportunity | Work and limits |
| --- | --- | --- |
| Minify generated JS | In-memory transform of 32 files: 3,705,821 to 2,066,621 bytes; **1,639,200 bytes (1.56 MiB) raw** saved, 191,664 bytes in the same Node gzip series. | Current build uses `minify:false`. Rebuild, regenerate provenance/manifests/notices, and rerun browser/worker controls. |
| Move full Material Icons to test-only use | Explicit full font **1,645,184 bytes (1.57 MiB)** accompanies a 77,440-byte tree-shaken face. | Production FontManifest uses the subset; store screenshot tests load the full asset. Preserve it as test fixture/retrieval, then verify icons and rebuild. |
| Deduplicate packaged notices | **492,125 bytes** of exact extra individual-file duplicates; original/aggregate overlap is larger. | Retain every applicable license/copyright/notice and source provenance. Choose a distribution representation and update references/guards. Do not double-count aggregate overlap and duplicate-file savings. |
| Whole PS/EPS optional delivery | Moves the largest engine out of a genuinely lean initial package. | Native dynamic imports do not remove bundled bytes. Versioned packs/build flavors add installation, offline/cache, update and platform-delivery work. Use only if size targets justify it. |

The first three narrow opportunities sum to about **3.60 MiB raw**, before any
larger notice redesign. This estimates candidate changes, not a tested optimized
release.

Avoid a Stet fork solely to delete standard fonts. Its native build already uses
release optimization, LTO and `wasm-opt -Oz`. It also exports PDF reading/rendering
and depends on the PDF reader/JPX path although CrispCloud uses PS APIs. An
upstream PS-only feature may save more, but savings are unmeasured and a native
fork adds rebuild/provenance/testing cost.

Evidence: [footprint](evidence/document-fonts-20261113/footprint.json),
[minification](evidence/document-fonts-20261113/minify-estimate.json),
[methodology](evidence/document-fonts-20261113/footprint-methodology.md).

### Loading and offline behavior

The host dynamically imports the chosen renderer when its view opens. The custom
service worker precaches only the app shell and bypasses WASM; the generated
Flutter worker is an unregistering shim. There is no blanket renderer precache.
Web startup benefits from lazy loading, but guaranteed offline availability of
these WASM engines is not established by that behavior.

Native asset declarations still package every engine. If optional assets become
necessary, use one versioned mechanism with explicit offline state rather than
a downloader per format. Prefer normal bundled/offline native delivery until
actual size targets justify the maintenance of optional delivery.

## 4. Alternatives: keep the useful ones

| Family | Existing alternatives | Recommended decision |
| --- | --- | --- |
| DOC/DOT | Native Formatted/Text, original-byte modes; conversion workflow; Quick Look on supported Apple platforms; local Open with System App. | Keep native primary, improve fonts, and make installed-engine PDF preview more discoverable. Keep upstream DOC as reference until a corpus shows important unique gains. |
| DOCX/OOXML | Pages, Formatted, Text, XML source; native editor; system preview. | Keep complementary modes and fix font coverage/layout integration. Another parser is not the first fix. |
| XML | Tree, Source, XSD 1.0 validation, XSLT 1.0 tools, output source and inert HTML. | Keep these. Add an engine only for a defined gap such as XSLT 3.0 or XSD 1.1. |
| PPT | Browser visual preview and independent native Text fallback. | Keep both; text remains useful when layout fails. |
| PS/EPS | One bounded Stet renderer; original source/bytes available. | Keep one renderer and Base35. Source display does not turn a rendering failure into a successful page preview. Consider an explicit installed-tool route if needed. |
| WPD/CHM/XLS/MBOX | Purpose-specific reader with applicable text/source or message modes. | Improve targeted gaps; no second complete engine by default. |

The installed Office converter discovers separately installed LibreOffice on
desktop and Word on Windows. Its model states these engines are never bundled
or downloaded. DOC/DOT conversion can request PDF as well as DOCX/DOCM;
DOCX/DOCM input is accepted by the installed PDF conversion service. This is
existing capability, although direct DOC Pages navigation does not expose it as
a first-class preview. Quick Look is present, but its historical "exact-rendering"
comment overstates a guarantee.

Sources: [converter models](../lib/services/installed_office_converter_models.dart),
[implementation](../lib/services/installed_office_converter_io.dart),
[conversion UI](../lib/widgets/legacy_word_conversion_dialog.dart),
[system preview](../lib/services/system_preview_service.dart),
[local open-with](../lib/widgets/file_context_menu.dart).

The native DOC parser now accepts the same 19 diagnostic inputs as upstream,
including three repaired cases; nine normalized main-preview texts match. This
is neither a representative compatibility rate nor a layout comparison. A second
engine should earn its cost by recovering important documents, not by repeating
that count. [Prior comparison](file-viewer-doc-dot-comparison.md).

For XML, avoid browser-native `XSLTProcessor` as the fallback. Chrome's current
plan removes it in Chrome 158 on November 17, 2026, with transitional exceptions.
Our local worker path does not depend on it. XSLT 3.0 is a separate capability
and license decision: SaxonJS is not open source, whereas the separate Saxon-HE
product has an MPL option. [Chrome plan](https://developer.chrome.com/docs/web-platform/deprecating-xslt)
and [Saxonica licenses](https://www.saxonica.com/html/license/terms.html).

## 5. Maintenance and implementation order

1. **Correct existing behavior:** bounded DOC font-name decoding, consistent
   lazy font registration, coverage fallback for Pages, and accurate missing-glyph
   or substitution reporting where measurable.
2. **Reuse font assets:** correct Calibri/Carlito mapping, implement family/style
   resolution in the canonical Office engine, and make browser measurement/paint
   wait for the same chosen fonts.
3. **Shrink packaging:** minify generated JS, move the full icon test fixture,
   and package nonduplicated complete notices. Preserve reproducible manifests
   and browser controls.
4. **Improve discovery of existing alternatives:** retain readable text/source,
   make installed Office/Quick Look explicit for page-sensitive documents.
   Do not reclassify invalid XML as valid, or a partial rendering as complete,
   merely because another view succeeds.
5. **Then consider packs or another engine:** require demonstrated compatibility
   gains and measured release download/installation savings. Use one pack
   mechanism with clear update/source/license ownership if needed.

Preserve canonical ownership: parser changes belong in standalone
legacy-doc-parser and its guarded synchronization; Quds changes belong in its
maintained canonical source. A shared inventory should not become another
rendering framework or a second layer of vendored parsers.

Useful focused validation includes mixed serif/sans text, real bold/italic,
Latin/Greek/Cyrillic/Hebrew/Arabic and selected CJK samples, missing fonts, DOC
before/after opening the editor, and measurement-versus-paint consistency.
Keep pagination/native Office acceptance distinct from readable preview tests.
