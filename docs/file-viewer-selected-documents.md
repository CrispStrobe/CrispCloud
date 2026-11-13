# Prioritized File Viewer integrations

Implementation and validation checkpoint, 13 November 2026.

CrispCloud's F3 viewer now has the requested WordPerfect, CHM, legacy Excel,
visual legacy PowerPoint, PostScript/EPS, MBOX, and XML schema/transformation
routes. The selected upstream is File Viewer 3.3.3 at
`d264009ca6efb3daed79a39d1ae63133e0f25558`. The initial tested source checkpoint is
[`5404834`](https://github.com/CrispStrobe/CrispCloud/commit/540483491f4a02aad3672abe438ad4aad3696e21).
The later Linux XML chooser and browser/native build results are retained at
`ddfd695`; the DOC/DOT continuation below consumes standalone parser `e442772`.

## What opens, how it renders, and the effective licenses

These grants coexist; the Apache wrapper does not relicense its dependencies.
Original license texts and matching native source/build information are retained
with the selected package. See the [full audit](file-viewer-format-license-matrix.md)
for other candidates and excluded routes.

| Format | Implemented behavior | Effective selected grants |
| --- | --- | --- |
| **WordPerfect** — WPD, WP, WP5, WP6 | Real libwpd/librevenge WASM parses the legacy binary. Ordered paragraphs/tables, styles, supported links, headers/footers and notes become structured browser content. Genuine WP 4.2, 5.0, 5.1 and 6.x fixtures were exercised. A visible notice describes unavailable page layout, images/fonts, equations and drawings. | Apache-2.0 wrapper; **MPL-2.0 alternatives** for libwpd 0.10.3/librevenge 0.0.6; MIT shim, Boost and permissive native/toolchain grants. [Source/notice record](../packages/file_viewer_documents/engines/wordperfect/UPSTREAM.md). |
| **CHM** | Rust ITSF/LZX WASM decompresses a single help archive. Contents, keyword index, search, internal topics and resources remain available. Sanitized topic HTML is shown in a script-disabled blob iframe. Merged-archive references are disclosed, not fetched automatically. | Apache-2.0 renderer/native engine, MIT ancestry and permissive Rust dependencies. This path does not import CHMLib or libmspack. [Source/notice record](../packages/file_viewer_documents/engines/chm/UPSTREAM.md). |
| **XLS, XLT, XLSB** | Actual binary workbook parsing, worksheet tabs and a virtual grid with supported stored styles, formula/cached-value display and supported embedded images. Legacy/binary chart rendering is not supplied by these routes. Real BIFF8 and generated XLSB were independently exercised; the similarly named upstream demo files were not used as evidence of distinct formats. | Apache-2.0 styled-exceljs 0.21.6 and wrapper; MIT e-virt-table 1.4.17/Floating UI, MIT-selected JSZip, MIT xmldom, MIT/Zlib pako and other permissive helpers. [Source/notice record](../packages/file_viewer_documents/engines/spreadsheet/UPSTREAM.md). |
| **PPT, POT, PPS** | Real binary PowerPoint parsing in a worker, followed by virtualized positioned slide canvases. PPS is a CrispCloud alias for the same engine. F3 retains the existing native **Text fallback**. This is static preview, without PowerPoint animation or macro execution. | Apache-2.0 public PPT runtime 1.0.2 and wrapper. No PPT WASM/font bundle is imported. [Source/notice record](../packages/file_viewer_documents/engines/ppt/UPSTREAM.md). |
| **PS, EPS** | The Stet interpreter rasterizes real pages. Page navigation, fonts and color profile run locally. This is experimental PostScript support, with explicit bounds and parser failures; it is not a guarantee of Adobe/Ghostscript parity. | Apache-2.0 wrapper and elected Stet Apache option (Apache-2.0 OR MIT available); permissive native crates; **OFL-1.1** URW fonts and **CC0-1.0** ICC profile. [Source/notice record](../packages/file_viewer_documents/engines/postscript/UPSTREAM.md). |
| **MBOX** | Native indexing and message selection use the existing email parser/view. Bodies and attachments are decoded for the selected message. Previous/Next/chooser remain available during search; search and Copy All apply to that message. Original Source/Hex bytes and malformed-message recovery are preserved. | CrispCloud-authored integration using its existing Dart email stack. No File Viewer MBOX parser or new MIME dependency was imported. [Parser](../lib/services/mbox_message_service.dart). |
| **XML with XSD/XSLT** — XML, XSD, XSL, XSLT | Existing Tree/Source views gain **XSD / XSLT**. Users choose or paste self-contained resources. XML Schema 1.0 validation and XSLT 1.0 transformation run in workers. XML/text results remain source; HTML additionally gets a sanitized inert preview. Input is never overwritten. | Apache-2.0 integration; MIT xmllint-wasm 5.3.0/libxml2/libxslt; BSD-3-Clause xslt-polyfill 1.0.33; retained Zlib/native notices; Apache-selected DOMPurify 3.4.17. The published xmllint build does not identify the exact linked zlib version. [Source/notice record](../packages/file_viewer_documents/engines/xml/UPSTREAM.md). |

The exact JavaScript dependency inventory includes 24 installed production
packages, including dependencies prebundled inside selected npm distributions.
The package also retains separate native dependency/license books. Those books
may conservatively include build/host alternatives; they are not claims that
every listed package survived native linking.

## Limits and user-visible behavior

| Route | Principal source limit | Additional bounds |
| --- | ---: | --- |
| WordPerfect | 64 MiB | Native wire/events, decoded text, blocks and tables; worker deadline. |
| CHM | 64 MiB | 20,000 entries, 16 MiB per entry, 128 MiB declared/unique decoded content, 4 MiB topic/metadata and bounded search. |
| XLS/XLT/XLSB | 32 MiB | Actual ZIP inflation 64 MiB total/32 MiB per entry; 128 sheets, 100,000 rows, 512 columns, one million populated cells; 500-row display windows. |
| PPT/POT/PPS | 32 MiB | Record/depth/text/asset budgets, 200 slides and bounded shapes/canvas geometry. |
| PS/EPS | 32 MiB | 200 pages, 128 MiB PostScript VM, 16 million canvas pixels/8,192 per side, terminating worker deadlines. These are not whole-browser RSS limits. |
| MBOX | 64 MiB | 1,000 indexed messages and existing 32 MiB selected-message cap, plus MIME attachment limits. |
| XML tools | 4 MiB XML | Resource, transformed-output, WASM-memory and operation deadlines; local resource selection only. |

Limits produce explicit errors rather than a convincing partial result marked
complete. Existing streamed Source and Hex remain available. Spreadsheet formula
recovery is not an Excel calculation engine. CHM topic scripts, executable embeds,
remote document resources and external XML dependencies are disabled. Linux
systems without the required browser runtime receive an unavailable-host message;
PPT additionally retains its native text view.

XML tools accept a self-contained XSD or stylesheet. Schema imports/includes,
XInclude, DTDs/entities, XSLT imports/includes, `document()` and extension
instructions are disabled even for local resources. This is not XSD 1.1 or
XSLT 2.0/3.0 support. The boundary and actual worker options are recorded in the
[XML source notice](../packages/file_viewer_documents/engines/xml/UPSTREAM.md).

MBOX indexing accepts LF/CRLF mailboxes with traditional ctime `From ` envelope
lines. Without `Content-Length`, the preview uses mboxrd's convention of removing
one leading `>` from quoted body `From ` lines. A valid `Content-Length` instead
defines an exact body-byte boundary; quoted lines remain unchanged because
mboxcl and mboxcl2 cannot reliably be distinguished. Invalid or duplicate lengths
reject indexing. An unescaped body line that is itself a complete envelope is
intrinsically ambiguous in delimiter-based mailboxes. A malformed selected MIME
message leaves other indexed messages reachable; this does not guarantee recovery
from an invalid mailbox boundary. Source/Hex retain the exact stored bytes.

The genuine presentation fixtures cover PPT and POT. PPS routing uses the same
binary engine and is tested as an extension alias; no independent PPS document
corpus or slideshow behavior is claimed. The selected wrapper does not expose
the engine's password input, and visual preview does not execute slide shows.

The browser receives only the selected byte snapshot and display metadata, not
provider clients, credentials, native paths or source URLs. The host validates
its session and origin, limits transfers, restricts navigation and closes workers
on replacement, failure, timeout or disposal. The [package README](../packages/file_viewer_documents/README.md)
describes build/runtime architecture and complete limitations.

## DOC and DOT: native parser retained, specific gaps fixed

The [full comparison](file-viewer-doc-dot-comparison.md) examines actual source,
models, F3 output and a runnable 19-fixture differential probe.

- The original probe opened **19/19** selected fixtures upstream and **16/19**
  natively. The fresh compatibility follow-up now opens **19/19 in both engines**,
  with nine equal normalized main-preview text results. These counts measure
  selected compatibility/text projections, not visual fidelity.
- The three rejection cases now have narrow, regression-backed recovery rules:
  inert mode-94 linked-picture evidence, a corroborated WPS diagonal-border pair,
  and independently valid singleton textboxes without verified placement. Other
  malformed ranges, ambiguous chains and unsupported records still reject.
- Our parser reconstructs numbered list labels and preserves structured auxiliary
  stories, review/source provenance and editable DOCX conversion. The upstream
  browser DOC route does not replace that model/conversion work.
- CrispCloud's adapter now appends the already preserved visible headers,
  footers, notes, comments and textboxes with localized role labels. F3 search
  and copy use that extracted content. Hidden/private references remain hidden;
  Source/Hex retain the original bytes. Unresolved placement is explicitly
  identified, and the reading labels do not claim original pagination.
- Upstream has useful broader container detection and explicit final/original
  review projections. Those are candidates for targeted follow-up, not changes
  included in this priority-format implementation.

The native package-authored engine remains **MPL-2.0**, with its retained MIT/0BSD
source notices. File Viewer's binary DOC engine is **MIT**,
with an Apache Word wrapper and Apache-selectable sanitizer. It is not wholly
Apache merely because the enclosing repository is Apache.

The exact parser source is now
[`e442772`](https://github.com/CrispStrobe/legacy-doc-parser/commit/e4427725cc720eaefad97c2cb921a6fe1e36749d),
which preserves canonical parser `419864b` and its later Word/ink improvements.
Its **1,019-test suite** and full analyzer pass. The
[compatibility receipt](../packages/legacy_doc_parser/doc/evidence/file-viewer-compat-20261113/README.md)
retains the executed results and source identities; the
[continuation checkpoint](recovery/file-viewer-continuation-20261113.md) records
the app verification separately.

## Executed validation and its limits

The [retained receipts](evidence/file-viewer-selected-documents-20261113/README.md)
record commands, versions and evidence:

- **61/61** Node/native-WASM contracts pass, zero skips.
- [Real Chromium CI 43387993185](https://github.com/CrispStrobe/CrispCloud/actions/runs/43387993185)
  passes 6 PS/EPS and 10 XML browser cases, both XLS/PPT and WPD/CHM smoke suites,
  and the actual shipped host for all six engines. It checks real Canvas/Worker
  behavior, local assets/CSP, navigation, source transfer and cleanup.
- **69/69** focused app source/routing/widget cases pass in one fresh invocation.
  The separate earlier MBOX/email suite also passed 69 cases; these overlapping
  suites are not added together into a synthetic total.
- **15/15** host policy/server/Linux-widget tests pass. Server tests make real
  loopback HTTP requests; Linux widget tests use a controlled native channel.
- Focused final analyzer reports no issues. The production Flutter **3.47.8 /
  Dart 3.13.7 JavaScript web release** builds successfully. Its optional
  Flutter-WASM dry run reported exit 247; no Flutter-WASM build is claimed.

The subsequent DOC/DOT continuation has its own fresh receipt: **42 DOC/review/
metafile tests**, **36 MBOX/email/routing/source tests**, and **11 F3 email/search
tests**, all passing with normal native hooks. The focused analyzer is clean;
**23** provenance controls also pass. The production JavaScript release build
passed with `--no-wasm-dry-run`, retaining normal O4/minification and all document
engine WASM assets. **131** packaged runtime/notice/host files match the source
hashes. These results are separate from the original 69-test receipt and are
retained in the [continuation evidence](evidence/file-viewer-continuation-20261113/README.md).

The same run's Linux job compiled the real WebKitGTK-enabled plugin and release
consumer, verified 42 runtime assets and 27 XML chooser filesystem-policy cases,
and verified installation of its executable startup probe. It did not launch
the probe or an interactive GTK chooser. The exact job IDs and versions are in
the [retained receipt](evidence/file-viewer-selected-documents-20261113/ci-ddfd695.json).

Chromium success and a web compile do not establish desktop/mobile WebKit/WebView
rendering on every OS. Full device
qualification and release acceptance remain separate. No release gate was
weakened, and no merge into main, deployment or release is part of this work.
