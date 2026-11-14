# ext filesystem continuation — recoverable progress

## Starting state

- Branch: `integration/storage-ext-20261114`.
- Baseline: `a34f7fcab53441da7d1d6c96e9d9e5ba25111907` on current main.
- PR [#101](https://github.com/CrispStrobe/CrispCloud/pull/101) is merged.
  Its FAT implementation, native/JavaScript results and production build were
  saved successfully before the previous agent stalled. The original records
  remain in `../storage-fat-20261114/` with their original source revisions.
- All remote branch heads, PR heads and tags were refreshed. See
  `reconciliation-start.json`; existing references have not been replaced.
- Main's later catalogue, 1.3.0 release and DOC fixes are preserved.

## This increment

Implement an original MIT, bounded, read-only ext-family filesystem adapter
using the existing archive byte-source, preview and extraction contracts.
The exact supported feature profile will be written after implementation and
independent fixture validation. Unsupported layouts and journal recovery must
be explicit; there is no filesystem write or repair authority.

Work is divided into the core reader, archive/image integration, independent
fixtures and validation. Checkpoints are saved remotely as each part becomes
concrete. Final qualification is still in progress; intermediate checks are preserved
with their exact source hashes and are not presented as later source runs.

## Prior hosted CI follow-up

The previous archive hosted job passed 992 tests then failed downloading the
external FatFs reference archive. The workspace job passed 947 tests then
failed a formatter cleanliness gate. These are separate from the earlier
recorded local qualification and will be assessed during this continuation.

## Resume guidance

1. Fetch this branch and current main before editing.
2. Read this file and the eventual ext profile and validation receipts.
3. Preserve existing evidence and bind every new test result to its source.
4. Push incremental commits; do not rewrite existing branch history.

## Incremental checkpoints

- `71fa70c8`: recovered prior completed FAT qualification and refreshed all refs.
- `3c868b26`: saved fail-closed ext API skeleton, bounded hash-verified external
  FatFs retrieval, and stable generated/UI formatting.
- `eeefe937`: saved functional ext reader, standalone/MBR/GPT integration,
  read-only workspace/F3 tests and first independent reference corpus.

Current follow-up adds the CRC16 external reference, malformed-image tests,
combined-disk budgets, source-length checks, resize/symlink allocation checks,
and VM/JavaScript-stable timestamps. Five complete external images reproduce
exactly and contain 48 regular file instances. Preliminary portable checks pass;
final pinned native, JavaScript, analysis and production build remain in progress.

The first native core/reference run passed 68 tests and failed one assertion:
the extended timestamp test incorrectly selected a 128-byte inode specimen.
The test now selects the 256-byte inode specimen it requires. Its full original
logs, summary, receipt and source hashes are preserved here (larger records use
lossless gzip). See `intermediate-evidence-index.json`.
