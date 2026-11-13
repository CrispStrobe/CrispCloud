# Selected WordPerfect engine

This directory contains explicit source overlays for the Apache-2.0 WordPerfect
wrapper in [File Viewer at d264009ca6efb3daed79a39d1ae63133e0f25558](https://github.com/flyfish-dev/file-viewer/tree/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/wordperfect).
`UPSTREAM.json` records the original source, runtime, fixture and notice bytes;
the entries marked as test material are only for validation. The runtime closure
uses libwpd 0.10.3 and librevenge 0.0.6 under the **MPL-2.0 election**, the MIT
callback shim, Boost under BSL-1.0, and the permissive native toolchain grants
listed in the upstream notice book. The root Apache license is not substituted
for those component licenses.

## Build and host contract

Copy the pinned `packages/renderers/wordperfect` package to staging and overlay
this directory's `src/*.ts` at its `src/` paths. Bundle `src/entry.ts` as the
browser renderer and `src/wordperfect.worker.ts` as a separate module worker.
The entry exports `renderWordPerfect(buffer, target, context)` and a default
alias. Context uses the existing File Viewer type-only contract; no core
runtime, npm parser, external service or approximate text fallback is imported.

The renderer needs the following same-origin runtime siblings, normally under
the host's flat `assets/runtime/` directory:

| Asset | Source |
| --- | --- |
| `wordperfect.worker.js` | Bundled selected `src/wordperfect.worker.ts` |
| `libwpd.mjs` | Unchanged upstream `vendor/libwpd.mjs` |
| `libwpd.wasm` | Unchanged upstream `vendor/libwpd.wasm` |

Context can provide local `wordPerfect.workerUrl` and `wordPerfect.wasmUrl`;
the loader is resolved beside the worker. The host must serve them using its
HTTP(S) origin, permit module workers and WebAssembly, and abort the context
when a file is closed or replaced. Both `destroy()` and `unmount()` dispose the
rendered instance. Native platforms use the host's local browser surface; this
slice does not add a native libwpd FFI build or claim native platform validation.

## Intentional modifications

- Require the actual structured libwpd engine. A missing worker, unsupported or
  corrupt file, encryption, timeout, or WASM failure rejects the preview.
- Preserve paragraph/table callback order, including tables in running
  sections. Keep a partially open body paragraph and its styles/links across a
  note. Header, footer and note content remain separately displayed.
- Display a persistent fidelity notice: page layout, embedded images/fonts,
  equations and drawings are not reproduced; table cells use plain text.
- When the app supplies its shared font catalog, await only the bundled
  Liberation Serif emphasis faces used by the parsed content before layout;
  Arabic text also requests existing Noto Naskh Arabic. The native bridge does
  not expose original font names. This makes structured reading consistent and
  does not claim restoration of original document typography or embedded fonts.
- Reject source above 64 MiB before copying, importing or allocating in WASM.
  Limit the decoded wire to 32 MiB, 200,000 events, 1,000 metadata pairs,
  8 MiB aggregate string bytes, 20,000 rendered blocks, 50,000 table cells,
  1,000-row/column spans and 16 nested document sections. Reject malformed or
  unfinished structures instead of rendering a misleading partial document.
- Keep parsing in a module worker with a maximum 60-second deadline. Abort,
  message/transfer errors and parser failures terminate that worker. Runtime
  URLs must use the local viewer origin. Links are rendered as text-safe DOM
  content; the shared host controls any external navigation.

These are input, output and time bounds. The unchanged native parser can
allocate internal working memory before it returns; these checks do not claim
to replace its compiled WASM memory ceiling or prove arbitrary-file safety.

## Distribution and source obligations

Preserve this Apache license and modification notices. Stage upstream
`THIRD_PARTY_NOTICES.md`, all `vendor/libwpd-src/LICENSE*` documents,
`NATIVE_PROVENANCE.json`, `PROVENANCE.md`, `shim.cpp`, the three checksum-pinned
source archives, and `scripts/build-libwpd-wasm.mjs` as the corresponding source
and notice materials. The MPL-covered libraries and MIT shim are unchanged.
Their exact source is retained, including the fixed Xberg source URLs documented
by upstream. An application distributor must keep the MPL source availability
and notice requirements when distributing the runtime. The source and license
materials must remain reachable from the delivered app/source distribution;
this README alone is not a replacement for them.

The native runtime is copied after hash verification, **not rebuilt** by this
integration. WPD loader SHA-256 is
`ccd3267ce9cac2961bb6a500761753efa05c93563e7a5e46a31594cceb5e3096`;
WASM SHA-256 is
`bbfe0c7f712a357e3f9d11f9cf96d931e7cf4b9165d4379af78bf1bcb69333f0`.
No fonts, sample documents or complete File Viewer bundles are runtime assets.

## Focused validation

After installing the pinned dependencies in `../../tooling`, run from the app
root, supplying the exact upstream checkout if it is not a sibling directory:

```sh
FILE_VIEWER_UPSTREAM_DIR=/path/to/file-viewer node --test packages/file_viewer_documents/engines/wordperfect/test/wordperfect.test.mjs
```

The suite stages original files plus overlays into a temporary directory and
uses the package's esbuild. It checks malformed streams, ordering/sections,
limits, allocation-before-validation regressions, local assets and worker
lifecycle. It also runs the exact WASM against hash-verified, redistributable
WP 4.2, 5.0, 5.1 and 6.x fixtures. Fixture licenses and provenance remain in the
pinned upstream test directory; fixtures are not added to the app runtime.

`test/browser-smoke.mjs` separately checks both engine renderers in Chromium,
including visible warning text, ordered DOM tables, CHM sandbox/topic links,
sanitization and disposal. It requires a Playwright browser installation or an
explicit `CHROME_EXECUTABLE`. Local execution was blocked before browser startup
by the workspace socket policy; this is not recorded as a browser pass.
