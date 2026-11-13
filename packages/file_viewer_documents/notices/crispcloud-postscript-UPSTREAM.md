# Selected PostScript and EPS preview

The selected File Viewer adapter and worker are Apache-2.0 at
[`d264009ca6efb3daed79a39d1ae63133e0f25558`](https://github.com/flyfish-dev/file-viewer/tree/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/design).
Only its PostScript path is selected. Photoshop/Illustrator/Introspect and other
engines from the design package are not imported by this entry.

## Native artifact, sources and grants

The unchanged native engine is **Stet 0.8.7 / stet-wasm 0.2.0**, from
[`AndyCappDev/stet@58c7066817f7939789c6f030515c02e94fb0353b`](https://github.com/AndyCappDev/stet/tree/58c7066817f7939789c6f030515c02e94fb0353b).
Stet offers Apache-2.0 OR MIT; this selection elects Apache-2.0 and retains both
complete original texts. It is not a Ghostscript/libgs engine.

The 14,706,940-byte WASM has SHA-256
`b8d72531ec41ca497d67a79589a1dbb44748a4fefd088aa122007fbb28e06b20`.
The worker verifies that hash before compilation. The generated JavaScript
binding, WASM, embedded fonts/profile and native source are unmodified.
The original locked native provenance, toolchain versions, asset hashes and
source links are retained in `provenance/`; `UPSTREAM.json` ties those originals
to this selection. No independent native rebuild is claimed.

Retain the full `licenses/` directory:

- Stet Apache-2.0/MIT code licenses.
- **URW Base35 font assets under OFL-1.1**, including their reserved-name and
  modification conditions. These are separately licensed assets embedded in
  the WASM, not Apache fonts and not the user's opened fonts.
- **CGATS001Compat-v2-micro ICC profile under CC0-1.0**, with the original
  profile notice and complete CC0 legal text. Its source bytes are not the
  similarly named Ghostscript profile.
- The upstream native license book contains 91 conservative locked source
  packages and full original Rust/crate license materials. It includes
  host/build alternatives and is not a post-link claim that all listed
  packages are present. The underlying grant families are permissive (including
  MIT, Apache, BSD, Zlib and retained data/toolchain notices).

## Host and build contract

Stage upstream `packages/renderers/design/src`, then overlay this directory's
`src`. Bundle `entry.ts` and `postscript.worker.ts` as separate ES modules in the
flat runtime directory; copy unchanged `runtime/postscript/stet_wasm_bg.wasm`
there. The entry exports a default `(buffer, target, context)` renderer. The
worker bundles the original `src/postscriptRuntime/stet_wasm.js` binding.

Runtime URLs are fixed to that same HTTP(S) origin. The host needs module
workers, WebAssembly, `crypto.subtle`, Canvas 2D and an abort signal on close or
source replacement. The options under `context.options.design` may lower the
hard limits; they cannot raise them or replace the worker/native asset URL.
The worker deadline minimum is one second and the PS VM limit minimum is 16 MiB.

## Local modifications, 2026-11-13

- Cap the input at 32 MiB, published output at 200 pages, source dimensions at
  100,000 units, individual canvases at 8,192 pixels per side and 16 million
  pixels, and the interpreter's PostScript VM at 128 MiB. Every worker request
  has a terminating deadline of at most 30 seconds. These are specific input,
  interpreter and output limits, not a whole-browser RSS guarantee.
- Preserve lower host-supplied limits. The LRU cache targets 32 MiB while keeping
  the current raster; one 64 MiB RGBA page may therefore exceed that cache
  target. Print preparation checks a 128 MiB combined decoded working set.
- Fetch the native binary with a 16 MiB streamed asset cap, no redirects,
  omitted credentials, same-origin enforcement and the reviewed SHA-256.
  Other worker network APIs are disabled. Native PS cannot request additional
  files from the host through this adapter.
- Validate returned raster dimensions and RGBA length before transfer to the
  viewer. Return native failure/limit errors rather than text or metadata as a
  purported rendered result.
- Correct the page-cap boundary: Stet needs an additional EOF step after its
  final `showpage`. Accept a document exactly at the cap, rejecting immediately
  after the first extra completed page. At most one extra native page can
  complete before rejection, still inside the PS VM and worker-time bounds;
  no partial over-limit preview is returned.
- Clean up the worker, raster/print caches, observer, zoom provider, listeners
  and DOM both on normal destruction and on initial rendering failure or abort.
  Retain upstream latest-request-wins page rendering and bounded print logic.

The output is real CPU rasterization with Stet's embedded fonts and color
profile. The engine remains experimental and is not claimed to implement every
Adobe PostScript Level 3 extension or match reference print output.

## Validation

```sh
FILE_VIEWER_UPSTREAM_DIR=/path/to/file-viewer node --test packages/file_viewer_documents/engines/postscript/test/postscript.test.mjs
FILE_VIEWER_UPSTREAM_DIR=/path/to/file-viewer node packages/file_viewer_documents/engines/postscript/test/browser-smoke.mjs
```

The Node suite runs the genuine pinned WASM and production worker/client through
an explicit Node worker-thread transport fixture. Only local asset transport
and the Worker event interface are adapted; the interpreter/compiler is not
replaced. It checks real PS/EPS raster pixels, the exact page-cap boundary,
malformed inputs, native artifact verification, cancellation and timeout.
It does not qualify browser Worker/CSP/Canvas integration.

The separate Playwright script exercises those browser boundaries and the
rendered canvas/page controls on an enabled CI runner. Local Chromium could not
start because process socket creation was denied, so no local browser pass is
claimed. Install the pinned tooling and Chromium, or set
`CHROMIUM_EXECUTABLE`. Authored PS/EPS test fixtures are Apache-2.0 and are not
runtime assets.
