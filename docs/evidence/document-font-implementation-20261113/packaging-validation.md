# Packaging checkpoint validation

Baseline: `db5b6126fdfb7f31598c80e5adc96ea548139505`. These receipts precede the later browser font bridge changes. Sizes are raw asset bytes, not compressed download or final installed application size.

- Production build completed using the pinned source and installed locked dependencies. A second build produced a byte-identical manifest: SHA-256 `53d959d429f43fe630d0754e3f96ee6dd0eddc8af591eeae5a0fb21214d858ea`.
- All 61 Node/native/WASM parser and renderer contracts passed, with no skips.
- The runtime retention guard verified 154 runtime, source, overlay and notice records; all 9 mutation controls passed. Runtime CI now runs these controls before browser validation.
- All 86 original notice source mappings remain represented by 63 unique, complete source texts. Only the two authored PPT/XLS UPSTREAM descriptions changed. All native WASM and corresponding MPL source hashes are unchanged.
- The moved Material Icons screenshot font is byte-identical to the previous asset. The bundled-font license test passed. All five current screenshot renders are byte-identical to the unmodified old rootBundle loader in an isolated baseline project on the same Flutter SDK. Both old and new differ from the existing reference goldens; those reference images were not changed. See the comparison hashes.
- Local real Chromium 156 cannot start in this execution sandbox: `socket() failed: Operation not permitted` in `chrome/browser/process_singleton_posix.cc`. Browser rendering/lifecycle proof remains a CI check; this receipt does not claim a local browser pass.

The runtime-plus-notice assets shrink from 24,914,367 to 21,107,574 bytes. Removing the duplicate full icon asset saves a further 1,645,184 bytes. Combined raw saving: 5,451,977 bytes (about 5.20 MiB). Existing application font files, PS Base35 resources, native code and MPL archives are retained.
