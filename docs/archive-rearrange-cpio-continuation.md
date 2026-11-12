# Archive rearrangement and CPIO profile continuation

Date: 12 November 2026. Baseline: `7cb65d768f2b096230f8bd32afc6c954baae7416`
from [draft PR #92](https://github.com/CrispStrobe/CrispCloud/pull/92).
Branch: `feature/archive-rearrange-cpio-20261112`.
Review: [draft PR #93](https://github.com/CrispStrobe/CrispCloud/pull/93),
stacked on PR #92.

## Delivered

1. **Move within archive…** moves a captured group of members to an existing
   directory in one archive workspace. Complete selection/collision preflight
   precedes a single draft mutation. Stop without changes, keep-both and skip
   retain destination contents; folders are not merged. Recursive, empty and
   implicit folders, overlapping selections, pending draft edits and nested
   workspaces are supported. Original member identity retains the supported
   metadata and protection. The normal Save/review/verification/recovery workflow
   publishes the result. This does not introduce a move between two archives.
2. Create portable ASCII/odc and modern binary little-/big-endian CPIO archives,
   and rewrite eligible existing archives without changing their profile.
   Preserve understood member/root/trailer metadata, member order, stored-name
   conventions and supported padding. Reject unsupported structures and fields
   that cannot fit the original layout. The picker now has **31 choices**, up
   from 28. Source inspection controls the rewrite layout, including existing
   mixed newc/CRC behavior; a creation preference cannot convert an open archive.
3. Preserve the root-directory record's ordering relative to surviving source
   members when an earlier member is deleted. Independent review identified
   the same numeric-insertion issue in newc/CRC and the new legacy writers;
   one shared fix and five regressions cover all five header profiles.

The new move dialog and creation guidance support English and all eight existing
translations. The bundled English, German and French guides now describe the
current creation, copy, integrity and rearrangement workflows consistently.

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

| Remote commit | Checkpoint |
| --- | --- |
| `19bbb860` | Scope and continuation boundaries |
| `22f25063` | Legacy CPIO writers/inspectors, preservation tests and native reference tooling |
| `9fc44eb4` | 31 creation choices, translated guidance and creation integration |
| `bd11520a` | Atomic grouped member moves with 57 service tests |
| `41f3ed36` | Captured move picker, nine-language UI and 21 widget tests |
| `a68ad875` | Shared CPIO root-order fix, five regressions and actual JavaScript runtime checks |

All implementation checkpoints above are saved remotely. The complete affected
regression passed **1,773 tests across 70 files**, and all **21 changed Dart
files** passed fatal-info analysis. Independent libarchive readback passed all
nine CPIO cases; Dart2JS output passed actual Node execution, including the
33-bit odc timestamp case. The three offline guides have 23 matching topics.
Final release-build and help-reader gates are recorded in the
[verification record](archive-rearrange-cpio-verification.md).
