# Final release verification

The genuine Flutter 3.47.8 / Dart 3.13.7 release web build passed with the normal
workspace graph and native hooks. The command was
`flutter build web --no-pub --release --no-wasm-dry-run`. The flag skips Flutter's
optional dry-run probe for its separate Dart-to-WASM target; the six selected
document engines and their actual WASM assets remain in this JavaScript build.
Flutter reported 231.3 seconds for the completed build. Relevant source hashes
at the start and finish match, including the final cache cleanup and lint edits.

The complete build log and source/SDK receipt are retained beside this file.
Two earlier compilations were explicitly stopped when source changes arrived;
they are not counted as successful releases.

## Exact bundle checks

- All 47 selected renderer assets match their source bytes and hashes exactly.
- All 21 shared catalog font assets exist once, with no duplicate font hashes.
- The extra full Material Icons font is absent. The normal production icon font
  remains tree-shaken to 77,552 bytes (the source is 1,645,184 bytes).
- The three distributed license files are present. Complete source-only notice
  copies and corresponding MPL archives are not included in application assets.
- PS/EPS native resources and all other selected WASM hashes remain unchanged.

## Comparable footprint

The script uses the original audit's exact scope and method: raw file bytes and
`gzip.compress(data, compresslevel=9, mtime=0)` for each file, then summed. These
are asset measurements and a compression estimate, not an APK/installer size or
measured HTTP transfer. Standalone font totals exclude fonts inside WASM or
documents. The runtime row and notices row are included in selected renderer
assets; they should not be added to that subtotal again.

| Scope | Before raw bytes | After raw bytes | Raw bytes saved | Gzip-9 bytes saved |
| --- | ---: | ---: | ---: | ---: |
| Selected runtime (with manifest) | 21,532,980 | 19,895,460 | 1,637,520 | 191,073 |
| Distributed notices | 3,379,595 | 1,224,387 | 2,155,208 | 339,083 |
| Selected renderer assets | 24,914,367 | 21,121,639 | 3,792,728 | 530,156 |
| Standalone fonts | 14,213,736 | 12,568,664 | 1,645,072 | 555,431 |

Selected renderer assets plus standalone fonts now total
**33,690,303 raw bytes** and
**19,678,616 gzip-9 bytes**. The measured
saving is **5,437,800 raw bytes (5.186 MiB)** and
**1,085,587 gzip-9 bytes (1.035 MiB)**. The normal
tree-shaken icon gained 112 bytes for the app's current icon set, which is
included in these net savings. No additional font files were added.

## Rendering validation boundary

All 75 engine/font Node/native/WASM contracts and all 9 runtime-retention
mutation controls passed. Real local Chromium remains blocked before startup by
the sandbox's socket restriction. Browser layout, loaded-face metrics, PPT SVG
font decoding and WebView behavior therefore require the existing CI/browser
checks; the successful Flutter release compile does not claim those checks ran.
