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

## Incremental checkpoints

- `e237cdc5`: preserved ext qualification, current remote reference ancestry
  and the separate hosted-CI state before new implementation work.
- `6593fe0f`: saved the fail-closed public contract and initial shared routing.
- `5bb28763`: saved the first functional reader, independently generated corpus,
  shared app and partition integration, and native viewer coverage.
- Draft review: [PR #103](https://github.com/CrispStrobe/CrispCloud/pull/103),
  stacked on the preserved ext branch/PR #102.
- The next checkpoint adds the public NTFS reader contract and shared
  recognition, read-only policy, streaming and MBR/GPT integration. The initial
  reader remains explicitly unsupported until its bounded parser is complete;
  this checkpoint does not claim working NTFS extraction or passing NTFS tests.
- Independent fixture production has demonstrated ordinary NTFS 3.1 images,
  Unicode and nested names, hard links, alternate streams, real sparse and
  fragmented data, and 4096-byte sectors. These are producer observations;
  reader qualification is still pending.
- System metadata records and `$Extend` descendants will be omitted from
  selectable files with an explicit notice while validating/reserving their
  allocations. Alternate stream notices retain exact names and sizes and state
  that those streams are not read, tested or extracted.

## First functional checkpoint

The full original reader now smoke-opens all three independently mastered
positive images (`ntfs31`, `ntfs31-small`, `ntfs31-4k`) and rejects the separate
real 4 KiB-sector image that requires an unsupported attribute list. The
positive corpus contains 143 regular unnamed file path instances; the
unsupported control contains 61 additional instances and is not counted as
supported extraction. All four complete images reproduce exactly. Separate
external tools extracted and hashed 204 unnamed path instances and eight named
streams without changing the source images. Final app/VM/JavaScript results
remain pending and will retain their actual source bindings.

Native recognition now honors the NTFS OEM signature before suffix-specific
dispatch. The F3/native file hint reads all 11 required prefix bytes; a renamed
`.zip` image can use the same bounded streaming path. Explicit NTFS child
notices are retained without shortening their original ADS names, within a
fixed notice allowance; overflow is refused explicitly.

The first standalone native viewer snapshot passed six tests, with no failures
or skips, including buffered preview, exact ADS notices, native 80 MiB `.ntfs`
and renamed `.zip` inputs, Hex/Archive transitions, cancellation, source
preservation and one access release. This snapshot is an intermediate result,
not a qualification claim for a later commit. Focused app and core adversarial
tests are still being completed.

## Source candidate and preliminary checks

The source candidate adds synthetic malformed/boundary coverage, reference
payload comparisons and portable acceptance. Required system-record kinds and
canonical metadata links now prevent omitted system directories from concealing
their referenced allocations. Directory/path limits, complete logical boot
sectors, true NTFS 3.0 FILE header layout and failed shared-budget attempts have
explicit regression coverage. The documented profile distinguishes structural
index validation from Windows collation and security-descriptor interpretation.

Before the final source freeze, the separate focused app run passed 50 tests;
the standalone viewer run passed six. Portable smoke acceptance passed 18 groups
and 2,037 checks on each of Dart VM and actual compiled JavaScript with matching
output. These runs used recorded working-tree snapshots and remain preliminary;
later source changes are not attributed to them. Full native regression,
source-bound portable acceptance, strict changed-file analysis and the
original-manifest production web build will qualify an explicit saved revision.

The external tool diagnostics are retained without treating exit status alone
as a pass: `ntfsinfo` reports a `$SDS` diagnostic on both an untouched `mkntfs`
control and a populated image. Security-descriptor content inspection remains
incomplete, while separate `ntfscat` payload extraction and read-only volume
checks retain their own results.

## Saved candidate results and test correction

- `dec983b2fcb71dea7f90e1020c5d73e3f926a3f6` saved the completed runtime and
  full regression candidate. `d7d66a43` then saved external provenance and
  preliminary records without changing source.
- The first 46-suite native gate at `dec983b2` finished with 1,186 passed,
  one failed expectation and one existing opt-in large-TGZ skip. The failed
  gate, complete log and source binding remain in
  `intermediate/candidate-dec983b2/`.
- The failed case named an ordinary file `.` in a root that already contained
  its legitimate self-entry. Correct rejection occurs earlier as a corrupt
  duplicate index key. A dedicated test now asserts that exact result; every
  other unsafe-name test retains its exact unsupported-name expectation. This
  is a test-only correction with no runtime or fixture change.
- At `dec983b2`, strict analysis passed all 25 changed Dart files, portable
  acceptance passed 18 groups / 2,037 checks on both VM and actual JavaScript
  with identical output, and the original-manifest production web build passed
  with the full revision and app version embedded. These executions retain
  their actual source attribution; the final native gate will use the saved
  corrected test revision.
