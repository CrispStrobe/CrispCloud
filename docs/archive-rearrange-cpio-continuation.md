# Archive rearrangement and CPIO profile continuation

Date: 12 November 2026. Baseline: `7cb65d768f2b096230f8bd32afc6c954baae7416`
from [draft PR #92](https://github.com/CrispStrobe/CrispCloud/pull/92).
Branch: `feature/archive-rearrange-cpio-20261112`.

## Scope in progress

1. Move a captured group of members to an existing directory in one archive
   workspace. Preflight the complete selection and collision policy, preserve
   original member identity and supported metadata, and publish a single draft
   mutation. Keep both, skip and fail are explicit collision choices. The
   existing whole-container review, verification and recovery journal publish
   the result. This does not introduce a move between two archives.
2. Create portable ASCII/odc and modern binary little-/big-endian CPIO archives,
   and rewrite eligible existing archives without changing their profile.
   Preserve understood member/root/trailer metadata, member order, stored-name
   conventions and supported padding. Reject unsupported structures and fields
   that cannot fit the original layout. Existing newc/CRC behavior remains.

## Completion gates

- Grouped moves are all-or-nothing draft changes. Cancellation, stale dialog
  state, self/descendant destinations, collision failure and publication failure
  must preserve the prior draft or original archive as appropriate.
- Reopened candidates preserve content, supported metadata and protection,
  including representative nested and metadata-rich archives.
- CPIO creation/rewrite has independent libarchive readback, original fixtures,
  malformed-input and field-overflow tests, and exact byte-order/alignment
  coverage. Reader support alone does not enable a writer.
- Focused service/widget tests, affected archive regressions, fatal-info static
  analysis and the pinned Flutter release web build establish observed gates.
- Save coherent implementation and documentation checkpoints incrementally to
  the remote branch. Do not force push or merge the preceding draft PRs.

## Boundaries and provenance

Existing 64 MiB member and 256 MiB interactive container/aggregate limits remain.
Remote/browser publication, two-container moves, durable packing jobs and full
platform release acceptance remain separate work. No additional application
dependency, subprocess packer, mounting or package installation is planned.

Implementation uses CrispCloud's existing workspace/reader/writer architecture,
primary format references and the existing permitted dependencies. The preceding
VaultExplorer ideas-only boundary remains: no implementation source, tests,
assets or dependencies from that project are inspected or imported.

## Checkpoints and observed validation

This file will be updated as implementation checkpoints and validation finish.
The baseline's recorded gates do not establish acceptance of this increment.
