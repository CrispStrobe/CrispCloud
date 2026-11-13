# Bounded binary PowerPoint adapter

`src/entry.ts` exports `renderPpt(buffer, target, context)` and its default equivalent. The wrapper is an Apache-2.0 overlay of upstream `packages/renderers/presentation-ppt/src/index.ts` at `d264009ca6efb3daed79a39d1ae63133e0f25558`. It uses the exact Apache-2.0 **`@file-viewer/ppt` 1.0.2** JavaScript payload under `apps/viewer-demo/public/vendor/ppt/dist`. The runtime's TypeScript development repository is private; the distributed JavaScript and license are present. No private source or different native engine is implied.

Alias `@file-viewer/ppt` to that distribution's `dist/index.js`. Stage/bundle its already self-contained **`dist/pptjs.worker.js`** as `assets/runtime/pptjs.worker.js`. The entry resolves that local worker using `new URL('./pptjs.worker.js', import.meta.url)`. No WASM, LibreOffice, conversion service or bundled font is needed. Caller-controlled module/worker/WASM/font URLs are overridden. Parsing occurs in a mandatory module worker; browser SVG/canvas rendering uses local fonts.

## Bounds and lifecycle

Fixed parser ceilings are 32 MiB file/stream, 100,000 records, depth 32, 200 slides, 20,000 shapes, 64 MiB assets and two Mi text characters. The overlay passes these through `parseOptions.limits`; upstream's unmodified wrapper did not forward parser limits. Returned slide sizes are checked before the runtime creates canvases: finite positive dimensions at most 4096 each and at most 4,194,304 logical pixels per slide. The inherited zoom renderer can rasterize at up to 1.5 native scale, so its raster pixel count can be 2.25 times that logical ceiling.

`IntersectionObserver` is required so all slides are not rasterized eagerly. Virtual rendering stays enabled, with a 100-pixel preload margin and immediate offscreen release. Initial rendering has a 30-second deadline. Abort closes the active runtime immediately, terminating an outstanding parse worker; later cleanup still captures any mount that completed at the abort boundary. `unmount()` and the host signal own the returned view. Initial failure is propagated to the host rather than converted to text.

This remains a best-effort legacy PPT/POT/PPS renderer. The limits and static slide rendering do not promise exact PowerPoint typography, animation playback, embedded-object execution, or every drawing feature. The parent host restricts network/navigation. Existing native text extraction can be offered separately by the host as an explicitly selected view.

`test/ppt.test.mjs` parses hash-identified real PPT and POT fixtures using the exact distributed engine, checks its file/record limits, verifies pre-canvas size rejection, and exercises the actual runtime's worker request/cancellation. The shared real-browser smoke script is `../spreadsheet/test/browser-smoke.mjs`; browser bundling alone is not a visual pass.
