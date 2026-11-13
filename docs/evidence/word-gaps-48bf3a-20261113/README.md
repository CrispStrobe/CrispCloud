# Word continuation and remote source retention — 13 November 2026

This receipt records completed acceptance of clean, published CrispCloud
[`0233ed8e9501538a9e68051b58a048407b2e29d0`](https://github.com/CrispStrobe/CrispCloud/commit/0233ed8e9501538a9e68051b58a048407b2e29d0).
The subsequent evidence commit does not change that measured runtime identity.

## Exact integration

| Component | Identity |
| --- | --- |
| Measured app tree | `bea1c6b8a9d4f6533462e715b82017a6a62f4b6c` |
| Standalone parser | `48bf3a84e822b960e369f0134d597e025c775a41` |
| Quds pin, retained from current main | `6d6e77d14ead33de90c57ec5feb2ab3cc44f6501` |
| Managed Office inventory | 1,226 files: 805 exact parser source files and 421 unchanged other files |
| Root app version, retained | `1.2.9+22` |
| Root lockfile SHA-256, retained | `135a9ccb44a38b2b9c7dcb541540b52bf151e8f5af14bf6e13b95d9240ae18a5` |

The office branch first fast-forwarded to current main `3d9a8823`, preserving
its combined Office and ISO/RAR/DMG work. That main already consumed parser
`cd9ab85a`; the older handoff's parser pin was not restored. The final guarded
roll then adopted canonical parser `48bf3a`, including the explicit unsupported
fallback-stroke guard and independently retained note-source attribution.
Disabled lines requesting the binary format's dashed fallback are no longer
treated as fully supported by simply hiding the line. Their raw evidence is
retained, and visible/default line behavior has dedicated upstream regressions.

## Correcting a remote-retention defect

Current main's Office manifest expected six immutable parser diagnostic logs
that its Git tree omitted. The app's blanket `*.log` ignore rule had excluded
them during staging, although the prior working mirror could pass verification.
All six files were restored from the exact pinned upstream Git objects, with
matching manifest hashes and executable modes. Their original diagnostic
contents were not regenerated. The app now includes parser evidence logs under
`packages/legacy_doc_parser/doc/evidence/` explicitly.

The new `--require-tracked` check verifies staged bytes, executable modes and
source-pin declarations, and requires an exact parser-prefix inventory. It
rejects ignored new source, stale staged data, unmerged index stages, extra
parser files and upstream deletions that were not staged. Three actual Git
regressions exercise the omission, stale-data/mode and deleted-file failures.
An independent review also checked an extra staged file under an ignored
generated directory. Office CI runs the strict check before its SQLite helper
temporarily adds a test hook to the app manifest.

The fixes were checkpointed remotely at `25900447`, `3c9f9ab2` and `0233ed8e`.
Each GitHub-created tree was checked against the local staged Git tree before
its branch reference advanced under an expected-head lease. Ordinary Git push
was unavailable because this executor had no GitHub credential; the connected
GitHub API published the checkpoints. The final published commit was fetched,
and a separate detached checkout passed complete source and index verification.

## Completed acceptance on the exact runtime

| Check | Result and scope |
| --- | --- |
| Data-only app Word cohort | 107 tests in eight suites passed; no failures or skips |
| Cohort identity | All 1,179 captured source, dependency, fixture and adapter hashes unchanged |
| Complete tracked app identity | All 7,108 tracked file hashes and production package configuration unchanged |
| Production JavaScript | Existing DOC, RTF, PPT and MSG smoke passed |
| Actual installed-Office acceptance | All 13 existing LibreOffice/Poppler assertions passed |
| Source synchronization controls | 27 passed |
| Exact source retention | All 1,226 Office files passed working-copy and Git-index verification, including a separate checkout of the remote commit |
| Apple preflight controls | 38 passed |
| Crypto release-evidence controls | 40 passed; two expected macOS-only skips |
| Ebook source controls | 22 passed |
| Actual ebook source verification | All 279 pinned files at `32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52` verified |
| Existing release-input checker | Passed with the genuine production package configuration |

The cohort uses the existing import-only adapter and unchanged assertions.
Its 13 fake-process converter tests are separate from the 13 actual native
assertions. The native result retains `partialFormatting`; it checks tables,
basic formatting, page definitions, referenced stories, an image, independent
PDF structure/text/image presence and unchanged source/prepared bytes. The
existing tool deletes its temporary PDF, so this receipt does not claim retained
page rasters, exact pagination or Microsoft Word execution.

Only the reviewed-source fingerprint was refreshed after reviewing the parser
guard, source declarations and stricter verifier. The inventory, root lockfile,
Quds bytes, app version, policy decisions, dates, references and source plists
remain as recorded by current main. No release was qualified or deployed.

## Hosted checks on the same runtime

The GitHub-hosted [Office fidelity integration run](https://github.com/CrispStrobe/CrispCloud/actions/runs/43376296083)
also completed successfully on exact app `0233ed8e`. Its `host-roundtrip` job
passed the committed-source gate and shared corpus/application save workflow.
Its `external-schema` job passed actual-host export completeness, the deliberately
invalid XML control, Open XML SDK validation, and actual-host native rendering
with repeated saves. The separate
[Dart and Rust provider compatibility run](https://github.com/CrispStrobe/CrispCloud/actions/runs/43376296067)
completed successfully on the same commit.

[hosted-ci.json](hosted-ci.json) retains the observed run identities, exact head
SHA, timestamps, job URLs and step outcomes. These hosted results have their own
GitHub provenance. They are not relabeled as local executions, and the local
archive does not claim to contain the hosted workflow's downloaded artifacts.

## Runtime restoration and reproduction

Direct Dart 3.13.7 was downloaded from the official versioned archive. Both its
archive hash and executable hash match the previously retained official
identities. Flutter packages, `sky_engine` and original version metadata were
extracted from the official Flutter 3.47.8 archive after verifying its published
SHA-256. The recovery record binds all 4,334 extracted regular files. The Flutter
launcher was not invoked and no SDK version metadata was synthesized.

Initial online dependency resolution was a cache-restoration operation during
branch reconciliation. Its log is retained as setup evidence. Final acceptance
began with a separate successful `dart pub get --offline --enforce-lockfile` on
the exact clean app commit, with unchanged manifest, lockfile and `.fvmrc`.
The resulting production configuration contains 273 packages. Final native and
JavaScript checks use that production configuration; the cohort keeps its own
separately captured dependency configuration.

Verify the retained records from any checkout containing this directory:

```sh
python3 docs/evidence/word-gaps-48bf3a-20261113/verify.py
```

To rerun the data cohort, use a checkout of the measured app commit, a genuine
Dart 3.13.7 SDK and its cached locked dependencies. Keep the new workspace
nonexistent before invoking the retained helper:

```sh
python3 docs/evidence/word-continuation-7308125/run_word_cohort.py \
  --app /path/to/CrispCloud \
  --workspace /path/to/new-word-cohort \
  --dart /path/to/dart \
  --pub-cache /path/to/pub-cache
```

The archive retains the complete final command recorder and arguments,
production configuration and lockfile, full cohort logs/events/configuration,
before/after inventories, actual native output, source audits, remote-checkout
verification, exact SDK recovery records, and earlier repair/baseline probes.
Intermediate records retain their own identities and are not relabeled as final
acceptance. `manifest.json` binds every uncompressed record; `receipt.json`
binds the archive and verifier. Runtime binaries and dependency downloads are
not duplicated in this source repository.

The recorded local acceptance did not run Flutter widgets, native ebook build
hooks or a complete app build. Hosted checks retain their separate GitHub run
identities. These scoped checks do not establish arbitrary Word layout
equivalence, full editing semantics or release readiness. Renderer executable
records do not inventory every installed font or shared library.
