# Directory scan recovery checkpoint

These bundles preserve unfinished source after the execution workspace became
unavailable on 2026-11-11. They are **inert documentation artifacts**: this
recovery checkpoint does not itself activate product code. A later source
checkpoint,
[`43a2c0f`](https://github.com/CrispStrobe/CrispCloud/commit/43a2c0f26ad89f0514ad0c4aff3edb351e017697),
restores the multi-root batch UI, final publication repair, benchmark and expanded
workspace gate. Check the [performance and validation record](../storage-scan-update-2026-11-11.md)
for its acceptance status. The later formatted checkpoint `ef3ca3c` passed
[913 hosted workspace tests](https://github.com/CrispStrobe/CrispCloud/actions/runs/43035543058)
and the Chrome persistence job. Do not reapply these artifacts over restored files.

The three runtime performance commits through
[`e9dd5db`](https://github.com/CrispStrobe/CrispCloud/commit/e9dd5dbbb8581e16f228d4f51239adf7d0b22660)
are already on the feature branch. Their measured results and validation limits
are in the [performance record](../storage-scan-update-2026-11-11.md).

## Preserved artifacts

All bundles target base commit
`e9dd5dbbb8581e16f228d4f51239adf7d0b22660`.
Git blob hashes below cover the complete UTF-8 JSON files.

| Bundle | Contents | Git blob SHA |
| --- | --- | --- |
| [Publication repair](scan-publication-2026-11-11.json) | Exact replacements for the typed unconfirmed-publication outcome and its durable store race regression | `deba75c0d4f995e836128fabd7fe9db45ebbcc7e` |
| [Batch UI](scan-batch-ui-2026-11-11.json) | Four complete new Dart files, four existing-file patches and separately recorded pending localization/widget repairs | `0e8d9082ab6e00eed3a8157a0c1cf03406f7e881` |
| [Benchmark](scan-benchmark-2026-11-11.json) | Collection import benchmark, benchmark README changes, translation corroboration and unexecuted AOT preparation | `4f3311af703908666a301f95882fd3b76d3724f2` |
| [Captured-session label follow-up](scan-batch-source-label-2026-11-11.json) | Exact source-label correction and a duplicate-session production-dialog regression; apply after the UI bundle and pending repairs | `a18548e1d34af09174fb07571d670f1f1e998e27` |
| [Validation workflow](scan-validation-2026-11-11.json) | Exact replacements extending the workspace analysis and regression candidates after the batch files are restored | `cdbc5fe79ee7327930110d1ff25e1c1fb6ade655` |

The publication and workflow bundles use
`crispcloud.recovery.exact_replacements.v1`. The UI, benchmark and label-follow-up bundles have
their own explicit fields. Do not feed all files to an assumed uniform patch
parser.

## Evidence boundary at recovery

The initial batch implementation passed a focused 62-test gate, including its
first 17 new batch cases. That gate preceded the final uncertain-publication
repair and does not validate these recovered files.

The publication repair was formatted and its diff checked before the outage;
its reconstructed result hashes match the recorded post-format diff prefixes.
It was not tested. Complete UI and benchmark files are reconstructed from
executed edit history and may differ in formatting from the former workspace.
The last UI localization and compact Arabic history regression were still
proposed changes. The new AOT comparison was never compiled or run.

Recovery checks verified the uploaded blobs, base-file hashes, exact replacement
counts and cross-bundle translation agreement. The UI has 30 replacement records
covering 31 occurrences; one menu insertion deliberately applies twice.
The fully applied proposed UI has 93 keys in each of nine catalogs, with matching
added placeholders. These are assembly checks, not runtime acceptance.
The measurement JSON retains captured samples and explicitly marked summary-only
records; the original complete workspace logs are unavailable.

After restoration and hosted formatting, the collection benchmark's SHA-256
exactly matched its recorded frozen source:
`c3ab5063a691b1b7f224ea596ec12f65e2c50ec2a9f6337cf0343b4310226200`.
The restored README also matched
`31d2196e5212c99759e4b31c223f012e5699952abe216d8571ac45dbae416d41`.
The source checkpoint is
[`ef3ca3c`](https://github.com/CrispStrobe/CrispCloud/commit/ef3ca3c038bab1a2af7765eb09d395d994431e99).
This later identity check strengthens benchmark provenance without changing the
historical status of the pre-format recovery bundle.

## Restore order

1. Prepare an isolated checkout at the exact base commit. Keep these artifacts
   available from their checkpoint, verify their Git blob hashes before parsing,
   and preserve unrelated work. If restoring onto later code, stop on any base
   hash or context mismatch and review the intervening changes.
2. Apply the publication bundle first. For each `files[]` entry, require
   `baseBlobSHA`, apply its replacements in order with the specified
   `expectedOccurrences`, and verify `expectedResultBlobSHA` and
   `expectedResultBytes`. This supplies the exception used by the batch service.
3. Restore the UI bundle. Write `new_files[].content` only to absent target
   files. Require each `existing_file_patches[].base_blob_sha`, then apply its
   replacements. Apply `pending_final_repairs` afterward. Enforce every
   `expected_occurrences` and replace all required matches: the file-browser
   menu anchor intentionally occurs twice. Then apply the label follow-up's
   `patches[].replacements` with their exact occurrence guards.
4. Restore the benchmark file and apply its README's two exact-anchor changes.
   Require the patched README to equal the supplied complete content. The
   translation maps corroborate the UI bundle; do not insert them again.
   Historical SHA-256 records are distinct from Git blob hashes and do not
   establish byte identity with reconstructed pre-format source.
5. With the new runtime and test files present, apply the workflow bundle using
   its base hash, exact replacement counts and result hash. Keep the existing
   independent browser persistence job; the bundle does not replace it.
6. Use the pinned toolchain, format the combined source, review the diff, and
   run analysis and the snapshot-store, batch-service, batch-widget, analyzer
   and localization gates serially. Verify the uncertain-publication/Stop race
   and opening saved history. Run the required broader regression, source
   evidence and build gates before claiming current acceptance.
7. Reproduce benchmarks separately with the same verified harness in both
   comparison worktrees. Retain new revision metadata, logs and raw samples.
   Recheck toolchain paths and cached dependencies. The recorded optional AOT
   commands describe preparation, not a completed result.

Checkpoint the validated runtime changes separately from this recovery commit.
Neither applying a patch nor preserving a blob establishes that the product
flow is ready.

## Reviewed source binding follow-up

The [source-evidence refresh record](source-evidence-refresh-2026-11-11.json)
preserves the independent audit of all 128 inventoried inputs after hosted CI
rejected a stale source fingerprint. Its blob is
`1550146cb602805f8efde52042725b8cfebe7255`. The two proposed target edits are
applied separately to the policy and audit note; this JSON remains a record of
the review and exact guards. See [the audit note](../crypto-audit.md) for scope
and [PR #40](https://github.com/CrispStrobe/CrispCloud/pull/40) for the subsequent
hosted check. Do not apply its base-bound replacements over an updated policy.
