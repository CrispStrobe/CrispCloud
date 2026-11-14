# Storage capability assessment evidence

This directory supports the
[2026-11-14 architecture and library study](../../storage-capabilities-20261114.md).
The study is documentation-only. Its upstream observations are candidate
evidence, not approved dependency pins or claims of newly working runtime
features.

## Preserved baseline

All 10 pre-existing remote branch heads and 90 historical PR heads were fetched
and checked with Git ancestry against
4d65b86dab36ca8f5dcd192c776de369aa5a4932. All 100 checks passed; there were no open
PRs at intake. The baseline includes the seven commits following the previous
handoff's 81639c44 merge.

[ancestry.json](ancestry.json) includes the exact refs, PR metadata, observed
commit IDs and per-head results. It records preservation/reachability, not a new
semantic re-review of all historical code. The previous integration's semantic
reconciliation remains documented in its own evidence.

The new integration/storage-capabilities-20261114 branch retains this baseline
and incremental assessment checkpoints. Existing branches were not deleted or
rewritten. Authenticated GitHub Git-data operations publish commits with a
checked expected branch head; each remote tree is checked against the local
staged tree and fetched back before the next checkpoint.

## Library ledgers

| File | Scope |
| --- | --- |
| [archive-library-evidence.json](archive-library-evidence.json) | Six archive/container/codec candidates, selected license texts, configuration and decoder limits |
| [filesystem-library-evidence.json](filesystem-library-evidence.json) | Nine filesystem/partition/recovery candidates plus the explicitly excluded mixed-license lwext4 build |
| [hex-copy-library-evidence.json](hex-copy-library-evidence.json) | Eleven binary/copy/backup candidates, including the xxHash library-versus-CLI distinction |
| [evidence-validation.json](evidence-validation.json) | Independent rehash of 63 pinned source files, including 33 license files |

Each ledger preserves immutable upstream source URLs, observed commit IDs,
source byte counts, SHA-256 and Git blob IDs. The entries distinguish a source
license from approval of its optional dependencies or complete build.
The original retrieved bytes were independently rehashed by the parent reviewer.
The ledgers preserve the source references and hashes; third-party runtime
sources or binary artifacts are not imported into this directory.

The combined 27-entry count includes one exclusion. It is not a promise that 27
libraries will be integrated or that every mentioned build satisfies the
policy. Several candidates are alternatives. This study did not build them,
resolve every transitive dependency graph, or qualify native/mobile/Wasm targets.

## Source-review investigation

[delta-source-review.txt](delta-source-review.txt) records source-level
observations in the existing opt-in/incomplete delta transfer paths. It
contains six pinned baseline source-file hashes, locations, uncertain caller
reachability and proposed reproductions. The parent reviewer rechecked all six
hashes against the baseline Git blobs.

The note does not establish runtime failures, user impact, or a defect in the
ordinary journaled copy/move path. It is a scoped follow-up investigation in the
roadmap.

## Verification scope

The assessment verifies source identity, branch preservation, JSON consistency,
document links, and the documentation-only change boundary. Focused reviewers
checked archive, filesystem/recovery and hex/copy scope; their wording
corrections are incorporated in the plan.

There are no new runtime test or build results for this branch. Existing
verification logs elsewhere in the repository retain their original source
and environment attribution.
