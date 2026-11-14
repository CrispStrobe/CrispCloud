# NTFS continuation — recoverable progress

## Preserved starting state

- Continuation branch: `integration/storage-ntfs-20261114`.
- Baseline: `ffdd6a86820b0d58cf8b93b4e626d0439beefab9`, the completed ext
  implementation and evidence checkpoint.
- The ext implementation is qualified at `8bbdc25c`; its original receipts
  remain in `../storage-ext-20261114/`. PR #102 remains open and draft.
- Main remains at `a34f7fcab53441da7d1d6c96e9d9e5ba25111907`.
- All fetched 12 existing branch heads and 92 PR heads are ancestors of the
  baseline. All 21 tags are retained. See `reconciliation-start.json`.
- The latest ext checkpoint has 28 queued hosted checks at this continuation's
  first read. This is not a hosted pass; see `prior-ext-hosted-status.json`.

## This increment

Add a bounded, read-only NTFS filesystem adapter through the existing Archive,
F3, workspace and extraction contracts. The intended initial profile covers
clean NTFS 3.0/3.1 geometry, validated file/directory records, resident and
uncompressed nonresident data, sparse/initialized data semantics and strict
Unicode names. Exact admitted layouts will be documented after independent
fixture qualification; this plan is not a support claim.

The implementation is original MIT Dart and adds no runtime dependency. External
filesystem tools may construct and verify test inputs; their implementations
are not shipped, linked or invoked by the application. No physical-device
access, mounting, filesystem writing, repair or journal replay is introduced.

Alternate data streams must remain explicitly identified by their original
names and sizes and must never be silently flattened into ordinary data.
Compression, encryption, reparse points, attribute-list extensions and other
uncertain layouts require explicit refusal unless separately specified and
qualified during this increment.

Eligible partition types are primary MBR `0x07` and GPT Microsoft Basic Data.
Recognition alone does not establish validity; failed filesystem validation
retains raw partition access with an explicit notice. Source failures and
cancellation remain fatal. FAT, ext and NTFS children share the disk-wide work
and allocation allowances, including failed attempts.

## Work ownership

- Core reader and malformed/boundary fixtures.
- Shared admission, read-only policy, partition integration and app flows.
- Independently mastered complete reference images and VM/actual JavaScript
  acceptance, with tool and input provenance.
- Source-bound native regression and original-manifest production web build.

Root owns all commits and remote reference changes. Work is saved incrementally
with ordinary descendant commits; existing branches and evidence are retained.
No final NTFS qualification has run at this checkpoint.

## Resume guidance

1. Fetch this branch and the ext/main branches before editing.
2. Read this progress file, any later profile, and the actual qualification
   receipts before attributing results to a source revision.
3. Keep failed/intermediate attempts separate from final results.
4. Save concrete increments remotely; do not rewrite earlier checkpoints.
