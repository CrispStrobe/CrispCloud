# Selected document previews for CrispCloud

This local Flutter package hosts six explicitly selected File Viewer engines.
The upstream commit is `d264009ca6efb3daed79a39d1ae63133e0f25558` (3.3.3).
It does not load the upstream preset or download a renderer at runtime.

## Formats and selected grants

| Engine | F3 input extensions | Implementation and effective grants |
| --- | --- | --- |
| WordPerfect | WPD, WP, WP5, WP6 | Apache-2.0 renderer; libwpd 0.10.3 and librevenge 0.0.6 under their MPL-2.0 alternatives; permissive shim/native dependencies. |
| Compiled HTML Help | CHM | Apache-2.0 renderer and Rust ITSF/LZX WASM engine; MIT ancestry and permissive Rust dependencies. No CHMLib/libmspack import. |
| Legacy Excel | XLS, XLT, XLSB | Apache-2.0 styled-exceljs 0.21.6 and wrapper; MIT e-virt-table 1.4.17; selected MIT JSZip, MIT xmldom and MIT/Zlib pako. |
| Legacy PowerPoint | PPT, POT, PPS | Apache-2.0 public PPT runtime 1.0.2 and renderer. Pure JavaScript parsing in a worker and virtual slide canvases. |
| PostScript | PS, EPS | Apache-2.0 wrapper; Stet 0.8.7 / stet-wasm 0.2.0 under Apache-2.0 OR MIT; permissive crate dependencies, OFL-1.1 fonts and CC0-1.0 ICC profile. |
| XML tools | XML, XSD, XSL, XSLT | Apache-2.0 integration; MIT xmllint-wasm/libxml2/libxslt, BSD-3-Clause xslt-polyfill, Zlib terms, Apache-2.0 DOMPurify selection. |

The complete shipped grants are in `assets/licenses/THIRD_PARTY.txt`, including
the original native notices and matching-source/build references. The generated
`RUNTIME_MANIFEST.json` records input, overlay, dependency and asset hashes.
The exact WordPerfect source archives, shim and original build materials are
also retained under `corresponding-source/wordperfect` in this source repository.
They are not added to the application's rendering payload.
Keep these notices and the MPL matching-source availability information with
redistributed binaries. See each `engines/*/UPSTREAM.md` for the exact boundaries.
The full repository audit is in `../../docs/file-viewer-format-license-matrix.md`.

MBOX is implemented by CrispCloud's Dart `mbox_message_service.dart` and existing
email viewer; no upstream MBOX code or dependency is imported by this package.
DOC/DOT continue using `legacy_doc_parser`; see the separate comparison report.

## App behavior

F3 selects these engines for the extensions above. PPT also offers the existing
native text reader through **Text fallback**. XML initially opens its existing
tree/source view; **XSD / XSLT** opens local schema validation and transformation.
Schemas and stylesheets are explicitly supplied files or pasted text. Their
external imports, includes, DTD/entity resources and document loads are disabled.
Transformation output stays in the preview; it does not overwrite the input.

The host receives only a bounded byte snapshot, filename, language and appearance
settings. It receives no provider client, credentials, native path or remote file
URL. It transfers bytes in 192 KiB chunks with a per-view random session identifier.
Changing source or closing the view revokes the renderer's lifetime and workers.

The general source cap is 64 MiB; XLS/PPT/PS are limited to 32 MiB and XML to 4 MiB.
Each parser adds bounds for decoded resources, records, cells, pages and output.
Oversized input stays available in the existing streamed Source/Hex modes.
The host has startup/render deadlines; individual workers have shorter operation
limits. Limits are part of preview behavior, not format guarantees.

Document content cannot run scripts. CHM pages use a sanitized blob iframe with
`sandbox="allow-same-origin"`, which grants no script permission. XSLT HTML output
uses an inert sandbox. The host CSP admits only its own scripts/WASM/workers and
local blob/data resources. Ordinary remote requests, executable embeds and
document-driven navigation are blocked. This is a rendering boundary, not a claim
that every malformed format has been exhaustively tested.

## Platform hosts

The MIT CrisperBooks host at commit
`32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52` was adapted into a separate document
plugin/channel. Its copyright and change provenance are retained.

- Web uses a local Flutter asset iframe and validates message origin, frame and
  session. The containing renderer code is trusted; document HTML is sanitized
  and isolated within that renderer.
- Android, iOS, macOS and Windows use the existing `flutter_inappwebview` platform
  dependency and a per-session loopback asset server.
- Linux uses a separate WebKitGTK texture plugin. Builds require WebKitGTK 4.1
  development headers at least 2.48.4 and CMake at least 3.19 to enable that host.
  The complete system WebKit runtime must be installed; it is not copied into this
  package. When unavailable, the view explains the failure and Source/Hex remain
  accessible. PPT also retains its native text fallback.

Native browser engines/platform libraries are existing platform dependencies,
separate from the selected upstream renderer grants. Platform compilation and
browser-engine tests are distinct; a Chromium test is not a claim of tested
WebKit/WebView behavior on every OS.

## Reproducible build and validation

Use Node 24 and the checked-in exact npm lockfile:

```sh
cd packages/file_viewer_documents/tooling
npm ci --ignore-scripts --no-audit --no-fund
npm run build
npm test
```

By default, the build fetches the pinned upstream into ignored `tooling/.source`.
Set `FILE_VIEWER_UPSTREAM_DIR` to reuse a clean checkout at that exact commit.
The build rejects a different commit or tracked source changes. It stages only
the relevant source directories and overlays, then verifies the selected module
graph excludes the CAD/OCCT, Mermaid/ELK, HEIC, archive and Draw.io bundles.
Generated `assets/runtime` and license records are included in the app bundle.
The contract tests reuse the same `tooling/.source` checkout by default; an
explicit `FILE_VIEWER_UPSTREAM_DIR` also applies to them.

```sh
# From the repository root:
cd packages/file_viewer_documents/tooling
npx --no-install playwright install --with-deps chromium
cd ../../..
for smoke in packages/file_viewer_documents/engines/*/test/browser-smoke.mjs; do
  node "$smoke"
done
node packages/file_viewer_documents/tooling/host-browser-smoke.mjs
```

The dedicated GitHub workflow runs the genuine engine fixtures and browser
checks. On the explicitly authorized feature branch, a passing push run commits
the generated runtime and notices back to that same branch using a normal
fast-forward push. It refuses to overwrite a concurrent update. Pull-request
runs publish only their test artifact. There is no deployment or release step.
