# File Viewer integration assessment for CrispCloud

Date: 2026-11-13. Upstream: [flyfish-dev/file-viewer](https://github.com/flyfish-dev/file-viewer),
commit [`d264009ca6efb3daed79a39d1ae63133e0f25558`](https://github.com/flyfish-dev/file-viewer/commit/d264009ca6efb3daed79a39d1ae63133e0f25558),
version `3.3.3`. CrispCloud baseline inspected:
`794bde82693e07a6e04ed1490bfa228f154e6e5c`.

## Decision

Port a small, dependency-free Apache-2.0 binary-header parser into CrispCloud's
existing Dart viewer. Keep the exact selected upstream source, original license,
and a checksum allowlist in [packages/file_viewer_binary](../packages/file_viewer_binary/).
The first implementation adds structured information to the existing hex
preview, with bounded reads and navigation to the corresponding bytes.

The restriction applies to **code and assets introduced from File Viewer**, not a
new assertion that every pre-existing CrispCloud dependency is Apache licensed.
No non-Apache upstream dependency is approved by this assessment. Permissive MIT,
BSD, or OFL components still fall outside a literal Apache-only source import.
An Apache license on a renderer adapter or preset does not relicense its parser,
native runtime, font, fixture, or other dependency.

Do not install `*-full`, `preset-all`, `preset-engineering`, `preset-office`, or
copy the demo's public assets. A fork of the full repository would preserve the
same mixed-license contents; it would not by itself establish a clean boundary.
The selected files can be tracked directly in CrispCloud without a full fork.

There is also an independent **File Viewer Flutter** SDK, so a browser bridge is
not the only upstream integration path. Its reviewed
[development-preview README](https://github.com/flyfish-dev/file-viewer-flutter/blob/cdbe778cccbd9e1c6b3538624b46bde25f0bdaa8/README.md)
describes `0.1.0-dev.2`, system WebViews on Android/iOS/macOS, WebView2 on Windows,
and CEF on Linux. The adapter is Apache-2.0, but its base, CAD, drawing and Typst
asset packages are installed together, totaling about 225 MiB before application
compression, with separate asset/engine licenses. That bundled SDK is **not an
approved Apache-only import**. The selected Dart extraction avoids bringing its
CAD assets, native web engines and overlapping rendering stack into CrispCloud.

## Existing capabilities and useful additions

CrispCloud already has a native Dart/Flutter preview architecture. The inspected
[internal viewer service](../lib/services/internal_viewer_service.dart) routes
text, safe ASCII, binary, hex, images, Markdown, HTML, XML, PDF, media, fonts, CSV,
Office, saved email, and archives. Its
[hex viewer](../lib/widgets/hex_viewer.dart) already virtualizes rows and supports
byte selection, highlighting, and offset navigation over `ViewBytesSource`.
[ViewerTextDecoder](../lib/services/viewer_text_decoder.dart) incrementally
decodes text with byte-to-character mappings. The
[hex editing session](../lib/services/hex_file_session.dart) separately owns
editing and staged save behavior.

| Priority | Upstream capability | Fit and decision |
| --- | --- | --- |
| 1 — implement first | Binary format/header inspection | Adds structured explanations to the existing hex view without replacing its large-file reader or editor. The parser and local types can be ported without a runtime dependency. |
| 2 — focused follow-up | Bounded structural prechecks and format diagnostics | Could improve messages for truncated or mismatched containers. Adapt small Apache routines only after checking their imports and defining which existing viewer owns the decision. Do not import the entire upstream format registry as a claim of supported formats. |
| 2 — focused follow-up | SVG resource restrictions | Standalone Apache helper `packages/core/src/security/svgResources.ts` is a useful reference for stripping executable attributes and external resource URLs. Evaluate against current SVG handling; it is not by itself a complete sanitizer. |
| 3 — only for a measured gap | Text encoding detection/selection | `packages/core/src/source/textEncoding.ts` has no runtime imports, but CrispCloud already has incremental UTF and legacy decoding. Its offset mapping and streaming behavior should be retained. Upstream's GB18030 fallback is a product decision, not a default to copy blindly. |
| 3 — selective source study | Viewer lifecycle, lazy dispatch, resource cleanup, range reads and search | Reusable Apache patterns exist in `packages/core`, but much overlaps with existing viewer/source services. Port specific missing behavior, not the browser component architecture. |
| 4 — separate discovery | GDSII layout parser, then other EDA helpers | `packages/renderers/eda-layout/src/index.ts` is a concrete standalone candidate with no imports and an Apache package license. It parses GDSII geometry; real binary OASIS support is limited to inspection/indexing, not complete geometry rendering. GDSII product value, Dart adaptation, and complete per-file provenance still require a focused review. OrCAD helpers are a separate candidate. |
| Defer | Entire Office, email, archive, ebook, PDF, media or image renderer | CrispCloud already exposes these routes. Full imports introduce overlapping UI and mixed-license dependency/asset graphs; selectively port a proven missing Apache routine instead. |
| Exclude | CAD runtime and other non-Apache parts | Not within the user's Apache-only integration constraint. See the boundaries below. |

The ranking is an engineering judgment based on the inspected sources. It is not
an exhaustive runtime/fidelity test of every existing CrispCloud route or a
promise that every advertised upstream format has production parity.

## Initial binary subset

The selected upstream files are
[`parser.ts`](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/binary/src/parser.ts),
[`types.ts`](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/binary/src/types.ts),
and the binary package's
[`LICENSE`](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/binary/LICENSE).
`parser.ts` has only a local type import; `types.ts` has a type-only core import
which is replaced by local Dart definitions in the adaptation. The original
snapshots are preserved byte-for-byte and are not executed. No npm package,
Worker, WASM file, font, image, sample, or fixture is copied.

The upstream parser recognizes these signatures and explains selected fields:

| Format | Header information available from the selected source |
| --- | --- |
| PNG | Signature, initial chunk length/type, IHDR width, height, bit depth and color type |
| WebAssembly | Magic and version |
| ELF | Class, byte order, type, machine and entry point |
| PE/COFF | DOS magic, PE-header pointer/signature, machine, section count and optional-header metadata |
| Mach-O | Magic, 32/64-bit form, byte order, CPU type, file type and load-command count |
| ZIP | Signature and selected first local-file-header fields |
| Java class | Magic, minor/major version and constant-pool count |
| Unknown input | Raw-byte fallback |

These are **header descriptions, not complete validators**. The feature must not
claim that a signature proves a file is intact, safe to execute, or correctly
named. ZIP inspection does not enumerate or extract the archive; PNG inspection
does not verify all chunks or CRCs; the executable routes do not load or execute
the input. In particular, `CA FE BA BE` is ambiguous between a Java class and a
Mach-O universal/fat container, and a port should expose ambiguity instead of
mislabeling every matching input as Java.

The Dart implementation in
[`binary_structure_service.dart`](../lib/services/binary_structure_service.dart)
uses `inspectBinaryStructure(Uint8List prefix, {required int totalBytes})`, with a
64 KiB prefix limit and no imports beyond `dart:typed_data`. It reports total and
inspected byte lengths separately, bounds fields to bytes actually present, and
reports incomplete/invalid headers. Supported header schemas bound the work and
field count. PE pointers and optional-header sizes are validated; ELF class and
endianness are checked. `BigInt` preserves exact 64-bit hexadecimal values on
web, and byte-array subview offsets are retained. Fat Mach-O headers are
recognized, with conservative handling of the ambiguous Java signature.

In the F3 viewer, select **Hex → Inspect structure**. Selecting a field highlights
its range and navigates in the existing hex view. The inspector requests at most
64 KiB from the current byte source. A native source may fill its ordinary
256 KiB cache window; existing remote/web source materialization policy remains
owned by the viewer, so the 64 KiB parser limit is not a new guarantee about all
backend transfers. Source identity/snapshot checks surround the read and field
selection. Controls and explanations use the existing nine-language
localization approach; technical format/field identifiers remain English. The
Apache license is supplied as an explicit app asset to `LicenseRegistry`.

This assessment and source snapshot establish the first checkpoint. Verification
results are recorded in subsequent commits and the implementation report; this
document does not imply that unrecorded tests or builds passed.

## License boundaries

Upstream's [README license section](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/README.md)
says its own source is Apache-2.0 and separately identifies the CAD runtime as
AGPL-3.0-only. Inspection of package manifests and bundled notices confirms that
the distribution is not uniformly Apache licensed.

| Area | File Viewer's own code | Boundary for this task |
| --- | --- | --- |
| Binary parser/types | Apache-2.0; binary package LICENSE is identical to root LICENSE | Approved exact subset. The package's complete published dependency graph is not imported. |
| Core | Apache-2.0; runtime dependency `dompurify` 3.4.17 | DOMPurify's exact-tag manifest offers `(MPL-2.0 OR Apache-2.0)`, so the Apache arm is available. This does not approve arbitrary bundled assets or optional type packages. No core dependency is needed for the chosen port. |
| CAD adapter | Apache-2.0 wrapper | `@flyfish-dev/cad-viewer` 0.8.3 and `dwf-viewer` runtime are AGPL-3.0-only; distributed LibreDWG assets include GPL notices. Exclude CAD route and assets, including any proposed DXF shortcut until it has an independently reviewed Apache closure. |
| Legacy DOC | `packages/renderers/doc` / `@file-viewer/doc` explicitly MIT | Exclude this source. `renderer-word` depends on it, despite the wrapper's Apache metadata. |
| Geometry / 3D | Apache wrapper | `geometry-engine` depends on `occt-import-js` 0.0.23, whose distributed license is LGPL-2.1; other 3D dependencies have their own grants. Exclude full runtime. |
| WordPerfect | Apache TypeScript integration | Notices select MPL-2.0 for libwpd/librevenge WASM, with an MIT bridge and further native notices. Exclude full runtime. |
| Design / IDML / PostScript | Apache adapters | IDML selects MPL-2.0 for `introspect-wasm`; Illustrator/PSD helpers include MIT/ISC; fonts are OFL and a color profile is CC0. Stet offers Apache/MIT but its whole native/asset closure is not Apache-only. |
| CHM | Apache wrapper and File Viewer-specific changes | Notices retain MIT provenance from RustChm/FastChm for parser/decoder code. A blanket Apache import is not approved. |
| PDF | Apache viewer code | Font and codec assets have separate licenses; e.g. Noto/standard-font and CMap notices. Audit individual files before any reuse. |
| Images | Apache adapter | TIFF uses MIT UTIF.js; HEIC adds its own runtime chain. Full image package is not approved. |
| Text / email / archives / spreadsheets | Apache adapter portions | Manifests bring external packages such as highlight.js, marked, JSZip, mail parsers and spreadsheet engines. Their exact license closure must be reviewed; the adapter label is insufficient. |
| iWork / Hangul | Apache integration | Current notices describe MIT dependencies. Current iWork explicitly says no Xberg runtime is embedded; an MPL test fixture is not evidence that the runtime is MPL. Still outside an unchecked Apache-only full import. |
| BPMN | Apache adapter | bpmn-js has a separate license requiring a visible watermark. It is not Apache and is not plain MIT. Exclude. |
| Demo assets / fixtures | Mixed | Includes MIT, CC0, CC-BY, OFL, GPL and other materials. No sample/demo assets are approved. |

The complete recursive upstream tree had no submodule entries or `.gitmodules`.
There is no root or binary-package NOTICE file at this commit. Absence of a
root NOTICE does not override nested licenses elsewhere.

### Evidence for exclusions

- [CAD package manifest](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/cad/package.json) and [CAD README](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/cad/README.md).
- [preset-all manifest](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/presets/all/package.json) and [preset-office manifest](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/presets/office/package.json).
- [Legacy DOC manifest](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/doc/package.json).
- [Geometry engine manifest](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/geometry-engine/package.json) and [OCCT import license](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/apps/viewer-demo/public/wasm/model/LICENSE.occt-import-js.txt).
- [WordPerfect notices](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/wordperfect/THIRD_PARTY_NOTICES.md), [design notices](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/design/THIRD_PARTY_NOTICES.md), [CHM notices](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/chm/THIRD_PARTY_NOTICES.md), and [CHM source provenance](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/chm/rust/NOTICE.md).
- [Image notices](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/image/THIRD_PARTY_NOTICES.md), [iWork notices](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/iwork/THIRD_PARTY_NOTICES.md), [Hangul notices](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/hangul/THIRD_PARTY_NOTICES.md), and [BPMN notices](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/drawing/THIRD_PARTY_NOTICES.md).
- [Core manifest](https://github.com/flyfish-dev/file-viewer/blob/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/core/package.json) and [DOMPurify 3.4.17 manifest](https://github.com/cure53/DOMPurify/blob/3.4.17/package.json).

## Apache notices and distribution

The [Apache-2.0 license, section 4](https://www.apache.org/licenses/LICENSE-2.0)
requires a license copy for recipients, prominent notices on modified files,
retention of relevant source notices, and preservation of applicable upstream
NOTICE material if present. Keep the exact upstream license with the source
snapshot and make it available with distributions of the derivative. Mark the
Dart port's changes prominently and retain `Copyright 2026 Flyfish Viewer`.

No original NOTICE accompanies this selected subset. The checksum manifest,
source pin and SPDX annotation are maintenance controls used here; they are not
separate requirements invented by the Apache license. The license does not grant
trademark rights. This assessment records a narrow technical/provenance review
and does not guarantee licensing conclusions for the entire upstream project or
all existing CrispCloud dependencies.

## Staged delivery

1. **Audit checkpoint:** commit this assessment, exact Apache license, original
   source snapshots, and SHA-256 allowlist to the remote integration branch.
2. **Parser checkpoint:** port the bounded header logic into Dart, document
   changes and ambiguity handling, and verify representative valid/truncated
   inputs plus budget/offset limits. Use synthetic test bytes; no upstream
   fixture import is needed.
3. **Viewer checkpoint:** connect the parser to existing byte sources and hex
   navigation, expose the Apache notice in the application's existing license
   presentation, and verify the UI and relevant app behavior.
4. **Future integrations:** choose one measured feature gap at a time, pin exact
   files, review all code/assets needed by it, extend the allowlist, and test the
   behavior. Reject non-Apache upstream additions unless the user explicitly
   changes the constraint.

Save each completed stage remotely. A local commit alone does not meet the
requested persistence requirement. Verification outcomes and actual remote
commit identifiers belong in the final implementation report.
