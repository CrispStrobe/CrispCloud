# Directory/archive synchronization and large TAR continuation

Date: 12 November 2026. Baseline:
`efd6969aac4a7e9a9dccd3fbef4abee3f56bba32`.
Branch: `feature/archive-rearrange-cpio-20261112`.

## Implemented scope

1. Native one-way synchronization from a captured local folder's contents to a
   captured directory in an eligible top-level archive. Compare complete file
   contents and logical names, distinguish equal/new/changed/archive-only/type
   conflicts, and apply only explicitly selected actions. Removal requires a
   separate opt-in and cannot silently remove retained descendants. Stage the
   entire change set atomically, review the complete verified candidate, then
   publish through the existing recovery-aware archive publisher.
2. Persist a bounded, credential-free source-directory dependency with the
   synchronization publication. Re-scan the complete source namespace, captured metadata
   and content before publication and when finishing recovery or cleaning the
   original backup. Older apps must refuse this new record version. Changed
   source evidence must retain recovery material and permit only verified
   restoration when its evidence is available.
3. Extend fresh native uncompressed TAR/CBT creation to a header-inclusive
   2 GiB output ceiling with genuine streamed input, temporary output, member
   verification and staged publication. Measure real files above the previous
   64 MiB member and 256 MiB aggregate limits. Keep progress, cancellation,
   source validation and exact no-overwrite publication through every phase.

The implementation and focused gates are complete. The combined regression
passed **2,094 tests across 84 files**, all **23 changed Dart files** passed
fatal-info analysis and formatting, and **33 help tests** passed separately.
Release-build evidence is recorded in the
[verification document](archive-sync-large-tar-verification.md).

## Remote checkpoints

| Commit | Checkpoint |
| --- | --- |
| `3a1c18b3b9efd22db30c643e88f21458a8811869` | Scope, acceptance criteria and remaining boundaries |
| `f9ecb81260c7f2bed89b323f8380812d354dccd4` | Durable directory dependency, native snapshots and streamed TAR core |
| `cfc8eff48f267ceb69966c4556e83aa233607546` | Selected one-way sync service, atomic workspace adoption and native tests |
| `f11b1cad035c9ebe5e4674475097be1139fd45ea` | Compare routing, complete review, recovery UI and nine-language guidance |
| `6577554b29d6d0c0beec41975296f22d67546afc` | Large native TAR/CBT tests, independent checker and measured evidence |
| `d84c9db5acf8f903ae18523266aaba84bc4a4bd0` | Reviewed contracts, partial gap status and English/German/French bundled guides |

Every checkpoint uses a leased fast-forward update and an exact Git tree
comparison. Local history is reconciled to the returned remote commit without
discarding pending work. The existing closed PR #93 is not reopened, and no
replacement PR, merge or deployment is part of this increment. Review the
branch or its comparison against the baseline to include the continuation.

## Focused verification and review

- Publisher/dependency regression: 101 tests, including 38 new directory
  dependency cases with real native files and fault-injected publication phases.
- Native directory snapshot/synchronization: 40 tests, including content and
  complete namespace changes, exact removal selection, encrypted 7z, ZIP/TAR
  publication, private-owner bypass attempts and restart recovery.
- Existing TAR/creation regression: 112 tests. New large native TAR/CBT
  acceptance: 24 tests plus two independent Python/GNU tar readbacks.
- Synchronization UI: 25 tests; creation UI: 45 tests; help service/dialog:
  33 tests. All nine UI locales were exercised at narrow width/enlarged text.
- Independent code review covered the synchronization service and atomic
  adoption, v3 dependency publication/recovery/cleanup, and streamed TAR
  resource, source-validation and cancellation boundaries. Documentation review
  corrected capability and metadata wording to match the exact implementation.

The measured TAR contains 269,485,142 payload bytes and occupies 269,489,664
bytes; the CBT contains a 68,157,773-byte member. Both exceed the old member
bound, and the TAR exceeds the old aggregate bound. The saved reference run
observed 64 KiB source/staged reads, 256 KiB output-transfer chunks, exact byte
progress and event-loop timer ticks throughout substantial phases. RSS increase
was 43.38 MiB for TAR and 31.73 MiB for CBT in that Linux Flutter test process;
these are sampled measurements, not universal process-memory promises. The
configured 2 GiB output ceiling has header-inclusive preflight tests, not a
claim that a 2 GiB archive was written during this run.

An initial large-fixture run hit disk exhaustion, then completed after removing
disposable build outputs. The parallel combined gate also exceeded available
disk when independent image and TAR fixtures overlapped. Its results are not
accepted as a passing gate; combined acceptance runs serially to bound fixture
disk use. No production limit was weakened to accommodate the test environment.

## Boundaries

Synchronization is one-way and selected-action based. Source files are not
deleted or rewritten. Two-way baselines, nested archive destinations and
remote/browser publication remain separate. Independent external changes after
the last observed validation cannot be locked out of both endpoints.

The larger TAR path is fresh native foreground creation, not durable background
job restart or larger existing-container editing. Buffered formats, compression
wrappers and ordinary workspace limits retain their existing bounds. Entry,
name, metadata and path limits continue to constrain streamed archives. TAR
stores no payload checksum; creation compares decoded members with captured
source hashes. Temporary output and destination staging require disk space.

Implementation reuses CrispCloud's existing native access, writer, spool,
reader and publication architecture with the pinned permitted dependencies.
No dependency upgrade, external packer runtime, archive execution or mounting
is part of this scope. No VaultExplorer implementation, tests, assets or
dependencies are inspected or imported. Existing PR #93 remains closed.

Save coherent checkpoints incrementally to the remote branch with verified
trees and leased fast-forward updates. Do not merge or force-push.
