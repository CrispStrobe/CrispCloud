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
