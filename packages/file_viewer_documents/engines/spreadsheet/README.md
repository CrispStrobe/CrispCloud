# Bounded spreadsheet adapter

`src/entry.ts` exports `renderSpreadsheet(buffer, target, context)` and its default equivalent. It preserves the File Viewer 3.3.3 grid/worksheet/chart/image renderer at upstream commit `d264009ca6efb3daed79a39d1ae63133e0f25558`. Modified files are overlays matching the upstream `packages/renderers/spreadsheet/src` paths; the build stages an unchanged source checkout and applies these overlays.

The host supplies `context.filename`, `signal`, and locale/theme options. The entry forces a same-directory **`sheet.worker.js` module worker**, resolved from `import.meta.url`. It ignores caller-supplied worker URLs/modes. Build the worker from upstream `spreadsheet/worker/sheetjs/sheet.worker.ts` after applying the parser overlay. The returned instance resolves only after its initial grid window (or complete empty workbook) is ready. Call `unmount()` to release its worker, handlers, images, table and owned DOM; cancellation also releases them.

## Deliberate changes

- A real worker is mandatory; worker creation/load failure does not fall back to main-thread parsing or a text substitute.
- Input is limited to 32 MiB. ZIP workbook preflight checks directory ranges, entry count, compression/encryption support and declared expanded sizes, then performs streaming inflation with discarded 16 KiB chunks. It stops when actual expanded bytes exceed the declaration or budget. It never trusts an understated ZIP size alone. ZIP64 and multivolume archives are explicitly unavailable.
- Ceilings: 10,000 ZIP entries, 32 MiB per expanded entry, 64 MiB expanded archive, 128 worksheets, 100,000 rows, 512 columns, one million populated cells, 128 Ki characters per cell string, eight Mi characters across checked cell values/formulas, 10,000 merges and two million covered merge cells, 2,000 drawings. Chart/image output has an additional metadata-node/depth/string budget.
- The workbook reader stops after at most 100,001 rows. The post-read guard checks original `!fullref`, source positions and dimensions; exceeding a limit rejects the preview instead of presenting a truncated workbook as complete. Formula recovery and chart extraction run only after this guard.
- Worker requests use a 30-second inactivity deadline. Initial rendering also has a 30-second deadline. Row windows are bounded to 500 rows, and display dimensions are checked before grid allocation. Failed parsing clears any prior workbook context.
- Original supported stored styles, formulas/cached values and embedded images remain. The shared grid retains its OOXML chart renderer, but the newly routed XLS/XLT/XLSB formats do not gain chart extraction: BIFF inputs skip the ZIP chart path, and its `xl/workbook.xml` lookup does not read XLSB's `xl/workbook.bin`. The original bounded uncached-formula recovery is not an Excel calculation engine. Macro execution, external workbook execution and editing are not added.

Full workbook parsing still occurs within the worker before windowed display. These limits bound accepted input/model/expansion and keep parsing cancellable; this adapter is not a complete audit of the third-party workbook parser or a guarantee of exact Excel rendering. The parent host separately restricts networking and navigation.

## Licenses

The upstream wrapper/source is Apache-2.0. The selected closure also includes styled-exceljs 0.21.6 (Apache-2.0), e-virt-table 1.4.17 (MIT), its Floating UI dependencies (MIT), JSZip 3.10.2 (MIT election), pako 1.0.11 (MIT/Zlib), xmldom 0.9.12 (MIT), tinycolor2 1.6.0 (MIT), UTIF 3.1.0 (MIT), and actual bundled transitive packages. The root build records the exact realized closure and preserves original license/notice texts; this directory does not replace those grants. Pako is used directly for the bounded preflight and is also JSZip's dependency. No upstream preset or unrelated renderer is imported.

## Tests

`test/spreadsheet.test.mjs` runs the actual pinned parser and dependencies, synthetic BIFF8/XLSB generation, a hash-identified real binary XLS image fixture, hostile ZIP declarations/inflation, model/window budgets, and worker cancellation/timeout/error paths. Synthetic documents are not visual-fidelity oracles.

`test/browser-smoke.mjs` builds both this adapter and the PPT adapter in a real browser harness. It checks actual grid/slide canvases, worksheet navigation, embedded images, required workers, cleanup, cancellation and blocked worker loading. `--build-only` verifies browser bundling without claiming a browser pass. Local Chromium execution was unavailable in the restricted development environment; CI must run the full script.

Do not use upstream demo `excel.xls` versus `excel.xlsb` as independent format evidence: at the pinned commit they are byte-identical. The tests instead use actual BIFF8/OLE and generated XLSB containers.
