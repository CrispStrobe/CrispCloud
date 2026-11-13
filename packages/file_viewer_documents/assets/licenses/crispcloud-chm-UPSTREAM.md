# Selected CHM engine

This directory contains source overlays for the Apache-2.0 CHM wrapper in
[File Viewer at d264009ca6efb3daed79a39d1ae63133e0f25558](https://github.com/flyfish-dev/file-viewer/tree/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/chm).
`UPSTREAM.json` records original source, runtime, fixture and notice bytes.
The real Rust ITSF/LZX parser includes MIT adaptations from RustChm/FastChm;
its lockfile and complete packaged license book identify the Apache, MIT, BSD
and Unicode grants for Rust/WASM dependencies. This route does not use chmlib,
libmspack or a remote conversion service.

## Build and host contract

Copy the pinned `packages/renderers/chm` package to staging, then overlay this
directory's `src/*.ts` onto its `src/` paths. Bundle `src/entry.ts` as the browser
renderer and `src/chm.worker.ts` as a separate module worker. The entry exports
`renderChm(buffer, target, context)` and a default alias. Core imports in this
selected path are type-only; no full File Viewer core bundle is necessary.

The host's flat local runtime directory must include:

| Asset | Source |
| --- | --- |
| `chm.worker.js` | Bundled upstream worker with selected model overlay |
| `chm_wasm.js` | Unchanged upstream `src/wasm/chm_wasm.js` |
| `chm_wasm_bg.wasm` | Unchanged upstream `src/wasm/chm_wasm_bg.wasm` |

The context may override local `chm.workerUrl`, `chm.wasmModuleUrl` and
`chm.wasmUrl`. All must use the viewer's HTTP(S) origin. The host must support
module workers, WebAssembly, blob/data archive resources and a nested topic
iframe. Keep that topic iframe sandbox at `allow-same-origin` **without
`allow-scripts`**. The upstream HTML/CSS/SVG sanitizers and topic CSP remove
active content and block remote requests. Abort the context and destroy the
rendered instance on file replacement or close.

## Intentional modifications

- Enforce a hard 64 MiB input maximum before DOM construction or worker transfer.
  Bound the selected route to 20,000 archive entries, 16 MiB per decoded entry,
  128 MiB declared/unique decoded content, 4 MiB HTML/metadata, 2,000 search
  topics and 200 results. Lower host-supplied limits are preserved. Every worker
  request has a maximum 60-second deadline.
- Preserve and display parser warnings and references to additional merged
  archives. Only the selected archive is opened; related CHM files are not
  fetched automatically or represented as available topics.
- Restrict worker/loader/WASM URLs to the local origin. Abort closes the archive
  worker; failed transfers, initialization and malformed inputs reject cleanly.
  A failed initial render is propagated to the host instead of reporting ready.
- Retain the real archive table of contents, keyword index, search, local topics,
  resource resolution, sanitizers and object-URL cleanup.
- Resolve topic link targets using DOM capabilities rather than a parent-realm
  `instanceof Element` check, so links inside the topic iframe can navigate to
  another internal topic.
- Display sanitized topic HTML through one same-origin blob URL instead of
  `srcdoc`, matching the native host's restricted child-frame navigation policy.
  Revoke the previous topic URL on navigation and the final URL on disposal.
  The topic still has no script permission and retains its restrictive CSP.

Input/output limits are not claims that arbitrary native parsing is infallible.
The unchanged Rust/WASM runtime retains its own allocation, metadata, depth,
directory and decompression bounds. Initial topic readiness and cross-platform
host behavior need the shared browser/native host checks in addition to parser
tests.

## Distribution materials

Preserve the Apache license and modification notices, upstream
`THIRD_PARTY_NOTICES.md`, `rust/LICENSE`, `rust/NOTICE.md`,
`rust/THIRD_PARTY_LICENSES.md`, `rust/Cargo.toml`, `rust/Cargo.lock`,
`rust/rust-toolchain.toml`, the full `rust/src/` source and the upstream build
scripts. The source test fixture is used only by tests and is not a runtime
asset. Native parser sources and committed native outputs are unchanged.

The JavaScript loader SHA-256 is
`e7f1a6e0de035e7178c04a0307f52806997c9971a948e333e66a49fbe73a3d5c`;
WASM SHA-256 is
`02904a83ae8be928d5c90b9fd61faf28d8ba7e67ee96e3aeeb5d5b5102691538`.
This integration copies those hash-verified artifacts; it does not claim to
have rebuilt the native binary or to approve unrelated File Viewer bundles.

## Focused validation

After installing pinned `../../tooling` dependencies, run from the app root:

```sh
FILE_VIEWER_UPSTREAM_DIR=/path/to/file-viewer node --test packages/file_viewer_documents/engines/chm/test/chm.test.mjs
```

The suite stages exact source plus overlays in a temporary directory and uses
the shared test helper under `../wordperfect/test/`. It verifies limits, warning
retention, path/CSS/SVG protections, local runtime URLs, transfer and cancellation
lifecycle, then runs the pinned WASM against the real LZX-compressed fixture to
check contents, index, search metadata, HTML and local CSS resources. Malformed
archives and native parser limits must reject, with no text fallback.

The separate `../wordperfect/test/browser-smoke.mjs` covers both engines in a
real Chromium browser. Local execution was attempted but blocked before browser
startup by the workspace socket policy; a successful CI/browser run is still
required for end-to-end DOM and iframe navigation evidence.
