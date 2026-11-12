# Ebook continuation checkpoints — 12 November 2026

Continue on `feature/ebook-reader-editor` in both `CrispStrobe/CrispCloud`
and `CrispStrobe/crisperbooks`. The user requires frequent remote checkpoints;
save coherent increments before long builds. No merge to main is requested.

## Recovered remote state

- CrispCloud: `bffdfbb49433859823081f2198f16e33be8369a6`.
- Crisperbooks: `c7d2dcdd64665fd4bd28f6818c1083274aae8141`.
- Shared package extraction, edit transaction protections, selection polling,
  read-aloud controls, and trusted-host Linux page/link handling are saved.
- The earlier session's app migration and full browser Kindle conversion were
  absent from those branch heads and must be reconstructed.
- The last completed Linux runtime failure timed out while converting native
  keyboard selection to a Foliate CFI. Newer selection/input fixes still need
  real-runtime validation. Cancelled workflows do not establish a pass.

## App migration checkpoint

All four shared packages now use the same full Git revision. The portable
reader, appearance/prose controls, reading-data model and edit-session API are
consumed through shared adapters. App-owned files, persistence and conflict
handling remain in CrispCloud. Dependency resolution and regression results
will be recorded as they complete; this checkpoint is not a release claim.

## Remaining continuation work

1. Finish app speech controls, remove the unused bundled ebook engines, and
   preserve source/license checks against the exact resolved external bytes.
2. Recover full browser AZW3/MOBI conversion, worker lifecycle/cancellation,
   source/build provenance and native-versus-Wasm output verification.
3. Update the app pin and run focused save/discard/routing/reading regressions.
4. Observe real Linux and other hosted gates. Record failures and qualification
   limits explicitly, and checkpoint fixes without waiting for every job.

For Flutter automation use `CI=true BOT=true` to avoid its optional environment
probe. Use the repository-pinned Flutter 3.47.8 / Dart 3.13 toolchain.

## Verified app checkpoint

`13a1d78abdbddf0608a9c5e8c212771a6058ea30` saves the migration and actual enhanced-reader speech controls. The 14-file app regression suite passes **158 tests**, including save/discard conflicts, reading-data rollback and limits, routing, editing, portable fallback and speech integration. Analysis of the nine changed source/test files reports no issues. These results use package revision `c7d2dcdd64665fd4bd28f6818c1083274aae8141`.

The unused in-app ebook packages and their duplicate package workflows are removed. EPUB/Kindle/reader/native platform qualification belongs to crisperbooks; CrispCloud retains its app integration and actual web build gate. The source verifier checks all **262 files** in the initial pin, including native code, assets, hooks and licenses, against the manifest, Git tree and actual Pub-resolved bytes.

## Browser converter integrated

The app now pins `b5b698ba872cc4a11b0b88f0fae2dc5324faf3c5`, with **276 verified dependency files**. Browser EPUB-to-AZW3/MOBI export and metadata editing use the packaged Kindling WASI worker. Kindle cover replacement remains native-only. The deterministic gzip module, runtime, shim and license inventory are saved remotely; app builds do not require a Wasm compiler.

Package verification: Rust **4/4**, native Dart **27/27**, converter analyzer clean; native/Wasm complete output parity for AZW3 and MOBI (only build timestamps excluded), including large-book compression; compiled Dart adapter **41 assertions / 22 real Node workers**, with cancellation, timeout, concurrent requests and zero workers leaked. Metadata regression: three fixtures, 11 edge cases and eight encoding rejections. Independent Foliate import of both browser outputs preserves metadata, Unicode, nested contents, links, chapters and resources. Actual local Chromium cannot start because the executor rejects its process-singleton socket; the hosted actual-browser gate remains required.

The external-source verifier now has **22 passing failure-path tests**, including byte tampering, omitted files, mismatched pins, redirected package roots/import directories, symlinks and ignored injected files. Existing source evidence tests: 42 total with two platform-only skips; Apple preflight tests: 38 pass. No distribution declarations or territory decisions were changed.
