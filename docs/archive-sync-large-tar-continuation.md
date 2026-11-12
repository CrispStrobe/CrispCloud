# Directory/archive synchronization and large TAR continuation

Date: 12 November 2026. Baseline:
`efd6969aac4a7e9a9dccd3fbef4abee3f56bba32`.
Branch: `feature/archive-rearrange-cpio-20261112`.

## Scope in progress

1. Native one-way synchronization from a captured local folder's contents to a
   captured directory in an eligible top-level archive. Compare complete file
   contents and logical names, distinguish equal/new/changed/archive-only/type
   conflicts, and apply only explicitly selected actions. Removal requires a
   separate opt-in and cannot silently remove retained descendants. Stage the
   entire change set atomically, review the complete verified candidate, then
   publish through the existing recovery-aware archive publisher.
2. Persist a bounded, credential-free source-directory dependency with the
   synchronization publication. Re-scan the complete source namespace, metadata
   and content before publication and when finishing recovery or cleaning the
   original backup. Older apps must refuse this new record version. Changed
   source evidence must retain recovery material and permit only verified
   restoration when its evidence is available.
3. Extend fresh native uncompressed TAR/CBT creation to a header-inclusive
   2 GiB output ceiling with genuine streamed input, temporary output, member
   verification and staged publication. Measure real files above the previous
   64 MiB member and 256 MiB aggregate limits. Keep progress, cancellation,
   source validation and exact no-overwrite publication through every phase.

These are completion criteria, not claims that the implementation or validation
has finished. Completed checkpoints and observed gates will be recorded below.

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
