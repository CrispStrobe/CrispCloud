# Browser font capability validation

This checkpoint follows the packaging-only receipts in this directory. It adds
font capability code and reuses existing application font assets; it adds no
font bytes to the renderer package.

- All 75 selected-engine Node/native/WASM contracts passed with no skips. This
  includes 10 font catalog/security/lifecycle controls and 4 PPT font contracts.
- The PPT contract executes the actual patched public runtime, proving its SVG
  transform runs before image decoding. A separate release-during-font-load
  case prevents late canvas paint. Exact-match patch drift is rejected.
- URL controls cover exact native sessions, Flutter web asset routes, foreign
  origins, traversal/encoded paths, queries, fragments and unsupported resources.
- Font controls cover aliases/styles, lazy loading, cached bytes, face disposal,
  fetch failure, oversized content, abort during decode, XML/CSS-safe names,
  unknown mixed Arabic/Latin content and explicit Noto with Latin text.
- The retention guard verified 158 records and all 9 mutation controls passed.
- The font helper passed TypeScript checking with the real TypeScript 6.0.3
  compiler and DOM definitions. Spreadsheet/PPT browser bundles build.
- A repeated production build produced an identical complete runtime manifest.
  The exact hash and raw asset sizes are in the adjacent measurement JSON.

The shipped-host browser smoke was extended to use real existing font files,
check that WPD and XLS wait for selected fonts, check PPT standalone SVG font
embedding, reject loading unused catalog faces, and check font disposal. The
Node-only CI job uses explicitly named Roboto control faces for its Calibri
alias; the production application catalog uses Carlito. No extra test font is
packaged. Local Chromium cannot start because the execution sandbox rejects
its socket creation. These browser assertions therefore require a successful
CI browser run; this receipt does not claim that local browser rendering passed.
