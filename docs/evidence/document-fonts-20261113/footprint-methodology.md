# Font and selected-viewer footprint measurement

Measured the existing JavaScript web release generated in the previous continuation, whose code/runtime baseline is `087b73a14b64c445c5eb717f187925b5472ed9b3`. The measurement JSON separately records the Git head at measurement time (which may include later documentation-only checkpoints). Selected source and built asset hashes match exactly. No production files were changed and no application rebuild was run.

Reproduce from a checkout with the existing `build/web` output and installed selected tooling dependencies:

```sh
python3 measure_footprint.py --repo /path/to/crispcloud > footprint.json
node minify_estimate.mjs /path/to/crispcloud > minify-estimate.json
```

`footprint.json` measures exact raw bytes and SHA-256 hashes, compares the complete selected built assets to source, and reports each file's independent gzip level 9 size (Python zlib, fixed timestamp). Totals are sums of separate files. They are not actual HTTP transfer, APK/IPA/installer compressed size, RSS, or initial app load. Bundled source archives, tests, reports, and development checkout data are excluded because they are not Flutter runtime assets.

Per-engine sizes use actual host dynamic-import entry points plus explicitly identified worker/engine files, then conservatively traverse quoted filenames in JS. This includes optional dynamically imported features. Shared chunks are partitioned separately; the sum of each engine's entire reachable graph double-counts those shared chunks. This is static inspection, not a recorded network waterfall.

Font inventory covers standalone TTF/OTF/WOFF/WOFF2 in the current web build. Embedded PostScript font data inside `stet_wasm_bg.wasm` and user document fonts are not separate files and not included in the standalone-font total. There are no identical-byte standalone font duplicates in this build. Similar families used by different subsystems are not interchangeable merely because they share a purpose.

`minify-estimate.json` runs esbuild 0.28.2 `transform` in memory over only the current generated JS outputs. It excludes four copied vendor loaders/runtimes. The production build currently requests `minify:false`; changing that requires a real rebuild, regenerated manifest/hashes/notices, and the existing browser/worker controls. This estimate does not claim that validation. It also measures selected existing files with Node gzip level 9 and Brotli quality 9. Node and Python zlib versions differ, so compare within each reported series.

## Load behavior

`engines/host/index.ts` imports only the selected format. The web host (`lib/src/hosts/host_web.dart`) creates its iframe only when opened. `pubspec.yaml` bundles all selected assets for installed applications. Lazy runtime loading therefore reduces startup work/web loading but does not remove native package bytes.

The custom `web/service-worker.js` precaches only the app shell, not the selected renderers. It explicitly bypasses `.wasm` fetches. The existing generated Flutter service worker is an unregistering shim, not the former full resource precache. Therefore this build does not automatically download all format engines for offline use; offline availability of first or later WASM opens must not be promised from lazy-loading inspection alone.

## Specific cleanup candidates, not removals

- The explicit full `assets/fonts/MaterialIcons-Regular.otf` is 1,645,184 bytes and coexists with the 77,440-byte tree-shaken Flutter font. These are not identical copies. Searches of production app/package Dart and resolved hosted Dart packages found no loader referencing the explicit full asset path, and `FontManifest.json` registers only the tree-shaken Flutter MaterialIcons face. The store screenshot test does load the full asset through `FontLoader` (`test/store_assets/store_assets_test.dart`). A follow-up should preserve that test dependency as a test fixture or test-only retrieval, then remove its release asset declaration after focused icon/adaptive/PDF checks and a release rebuild.
- Original license notices and a concatenated `THIRD_PARTY.txt` are both bundled. Exact duplicate notice bytes are itemized separately; removing redundant copies requires retaining all grants/notices, updating generated manifest and notice references, and respecting source provenance. Legal/source content must not be stripped as an untested size fix.
- Quds and PDF assets have overlapping families by role, but no byte-identical font files. Shared registration/substitution policy can improve fidelity without adding fonts; deleting one collection needs layout/PDF substitution tests and upstream ownership review.
