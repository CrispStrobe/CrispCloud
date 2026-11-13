# Selected spreadsheet source and modification notice

Source: [flyfish-dev/file-viewer](https://github.com/flyfish-dev/file-viewer/tree/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/spreadsheet), immutable commit **d264009ca6efb3daed79a39d1ae63133e0f25558**, package `@file-viewer/renderer-spreadsheet` **3.3.3**. Original renderer source is **Apache-2.0**, Copyright 2026 Flyfish Viewer. This selected route also imports the Apache-2.0 File Viewer core. `UPSTREAM.json` records exact original source, original license/notice, and test-material identities; test material is not an app runtime asset.

The original source checkout remains unchanged. During the root build, these `src/` overlays replace the corresponding files under `packages/renderers/spreadsheet/src`. `entry.ts`, `limits.ts`, `zipPreflight.ts` and `boundedWorker.ts` are new integration files. `spreadsheet.ts` and `spreadsheet/worker/sheetjs/parser.ts` are modified copies. Their leading modification notices and the corresponding Apache grants must be retained.

## Modifications and execution boundary

The selected entry retains the original styled grid, worksheet tabs, supported styles, formula display and supported embedded images. Shared OOXML chart-rendering code also remains, but does not establish chart support for the newly routed XLS/XLT/XLSB formats: BIFF inputs skip chart extraction, and the ZIP chart extractor requires `xl/workbook.xml` rather than XLSB's `xl/workbook.bin`. It requires a local module worker, removes the upstream main-thread fallback, waits for the first displayed grid window, and propagates initial failures. Cancellation, worker errors and a 30-second deadline release resources. `unmount()` releases owned DOM and the active worker.

Added limits cover source bytes, actual streamed ZIP inflation, aggregate expanded data, worksheet count/dimensions/cell text, merges/drawings/metadata and row-window requests. A row-limited parse that reports a larger original range is rejected, not presented as a complete workbook. Defaults are detailed in [README.md](README.md) and the original integration source. File input is 32 MiB; ZIP expansion is 64 MiB total/32 MiB per entry; display ceilings are 128 sheets, 100,000 rows, 512 columns and one million populated cells. There is no text substitute on failure and no added macro execution.

Bundle the staged `entry.ts` as the entry and staged `spreadsheet/worker/sheetjs/sheet.worker.ts` as **`sheet.worker.js`** in the same flat runtime directory. The fixed URL resolves from `import.meta.url`; caller-supplied worker URL/mode options do not override it. Native browser hosts must enforce their separate networking, navigation and lifecycle rules.

## Distribution licenses

Retain the original renderer `LICENSE` and `THIRD_PARTY_NOTICES.md`, the core/root Apache-2.0 grant, and the actual npm package license/notice payloads selected by the root build. The selected direct closure includes styled-exceljs 0.21.6 (Apache-2.0), e-virt-table 1.4.17 (MIT), JSZip 3.10.2 (MIT election), pako 1.0.11 (MIT/Zlib), xmldom 0.9.12 (MIT), tinycolor2 1.6.0 (MIT), UTIF 3.1.0 (MIT), plus their realized bundled transitive dependencies. The root lockfile and `RUNTIME_MANIFEST.json` identify exact resolved versions; `assets/licenses/` retains their actual grants. Those component grants are not replaced by the root Apache license.

The selected source has no full File Viewer preset, unrelated renderer, embedded sample document, external conversion service or font asset. Browser/layout fidelity is separate from parser success. Node tests and browser bundle checks passed locally; an actual browser pass requires the CI smoke script, as local Chromium startup was blocked by the workspace socket policy.
