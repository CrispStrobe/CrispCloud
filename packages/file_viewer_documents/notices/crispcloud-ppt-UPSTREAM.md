# Selected binary PowerPoint source and modification notice

Source: [flyfish-dev/file-viewer](https://github.com/flyfish-dev/file-viewer/tree/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/presentation-ppt), immutable commit **d264009ca6efb3daed79a39d1ae63133e0f25558**. The surrounding `@file-viewer/renderer-ppt` wrapper is version **3.3.3**, **Apache-2.0**, Copyright 2026 Flyfish Viewer. Its exact runtime is the distributed **`@file-viewer/ppt` 1.0.2** JavaScript under [the pinned public vendor directory](https://github.com/flyfish-dev/file-viewer/tree/d264009ca6efb3daed79a39d1ae63133e0f25558/apps/viewer-demo/public/vendor/ppt), **Apache-2.0**, Copyright 2026 Flyfish. It declares no production npm dependencies. The selected wrapper also imports the Apache-2.0 File Viewer core and any actual retained dependency grants recorded by the root bundle.

`UPSTREAM.json` records exact original wrapper/distributed-runtime/license/notice and test-material identities. The original checkout and PPT runtime payload are unchanged. `src/index.ts` is the explicitly modified wrapper overlay; `entry.ts` and `limits.ts` are new integration files. All source modification notices must remain.

## Modifications and execution boundary

The entry forces local module-worker parsing, same-directory `pptjs.worker.js`, virtual slide rendering and bounded parser options. It rejects missing worker/virtualization support instead of falling back to direct parsing. Fixed input/stream, record, depth, slide, shape, asset and text limits are passed to the real parser. Slide dimensions/pixels are checked before canvas allocation. Startup has a 30-second deadline; cancellation immediately closes the active runtime and pending worker, and later mount cleanup remains owned. The original browser SVG/canvas renderer, zoom behavior and supported drawings remain. There is no text substitute on render failure.

Alias `@file-viewer/ppt` to `apps/viewer-demo/public/vendor/ppt/dist/index.js`; bundle/copy `dist/pptjs.worker.js` to the flat runtime directory. The distributed worker is already self-contained. No WASM, LibreOffice, server conversion or font binary is loaded by this runtime. Full resource ceilings and layout limitations are documented in [README.md](README.md).

## Distribution licenses and source boundary

Retain the wrapper's original `LICENSE`, its `THIRD_PARTY_NOTICES.md`, and the distributed PPT runtime's original **`LICENSE`**, **`NOTICE.md`**, and package metadata. The notice discloses reused binary/vector foundations and excluded private QA material; do not omit it or relabel earlier native/WASM package versions with this version's grant. The root build includes every complete license/notice text in `assets/licenses/THIRD_PARTY.txt`, retains exact copies in source-only `notices/`, and maps all original sources and final bundled dependencies/hashes in `RUNTIME_MANIFEST.json`.

The runtime's TypeScript development repository remains private. The public archive supplies compiled JavaScript and declarations under the stated Apache grant; this integration does not claim access to private implementation sources, private documents, QA fonts or a rebuild from that private repository. The tests execute the exact published JavaScript. Public binary fixtures are referenced by hash only for testing and are not shipped in the runtime.

PPT/POT/PPS compatibility and generated canvas output remain best effort. Parser success, model counts and browser paint are separate from native PowerPoint pixel equivalence. Node tests and browser bundle checks passed locally; actual browser execution is delegated to the CI smoke script because local Chromium startup was blocked by the workspace socket policy.
