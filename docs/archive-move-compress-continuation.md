# Archive move and UNIX compress continuation

Date: 12 November 2026. Baseline:
`19d359ba1dd5730fc01824efe69e309be26f876d`.
Branch: `feature/archive-rearrange-cpio-20261112`.

## Delivered scope

1. F6/context Move and a clean workspace's Move out prepare reviewed moves
   between two distinct, top-level native archives on the same persistent local
   storage. Both destination additions and source removals are built and verified
   before publication. Destination publication comes first; source publication
   durably retains its exact destination dependency. Results distinguish a
   completed move, destination-only publication and required source recovery.
2. Source-removal recovery records use version 2, which older apps refuse.
   Restart recovery verifies the destination's captured identity, complete
   contents and access policy before finishing source publication or deleting
   the original backup. A changed destination retains available source recovery
   material; explicit restoration uses verified, exclusive moves.
3. UNIX compress (`.Z`) and TAR.Z increase creation from 31 to 33 choices.
   Fast/Normal/Maximum use 12/14/16-bit block dictionaries; eligible existing
   9–16-bit block/nonblock streams rewrite using the normal 14-bit profile.
   All 23 independent native readback cases and 18 actual JavaScript profiles
   pass. The format's absence of a checksum or decoded length remains explicit.

Both candidates share the existing content/metadata and publication checks.
An exposed source review cannot publish removal without its owner's private
authority and verified destination dependency. Source draft and physical
identity changes invalidate removal. The move UI preserves results through
dismissal and invalidates a borrowed source host before publication or recovery.

## Saved remote checkpoints

| Commit | Checkpoint |
| --- | --- |
| [`fccaf483`](https://github.com/CrispStrobe/CrispCloud/commit/fccaf4831062eb9f29577648406f368ecfbde3d0) | Scope, recovery ordering and acceptance boundaries |
| [`0a5e269a`](https://github.com/CrispStrobe/CrispCloud/commit/0a5e269a18a9250f210ec2c2927efe6ebfc3f0f5) | UNIX compress writer/creation and durable publication dependencies |
| [`de2d27d7`](https://github.com/CrispStrobe/CrispCloud/commit/de2d27d7d6a782fceecd44c1c450b184188e00e6) | Reviewed native move coordinator, source authority, restart tests and independent codec evidence |
| [`d68c2e1c`](https://github.com/CrispStrobe/CrispCloud/commit/d68c2e1c6a13f5f99ea312f3088cb60aa691a8bc) | Paired review/result/recovery UI and nine-language controls |
| [`dee4ec1a`](https://github.com/CrispStrobe/CrispCloud/commit/dee4ec1aa7a44484fc65f2805632fee38e61b534) | Escape, completed outcomes and shared-journal source-recovery lifetime |
| [`b9619927`](https://github.com/CrispStrobe/CrispCloud/commit/b96199272e193439439e7db4958782cd66301f30) | Reviewed English/German/French guides, format/endpoint contracts and complete regression evidence |

Each checkpoint was saved through a leased fast-forward ref update after its
remote tree was verified against the local committed tree. No force push or
merge was used. [PR #93](https://github.com/CrispStrobe/CrispCloud/pull/93)
was already closed by the repository owner during the preceding increment;
its closure is preserved. The branch contains all later checkpoints.

## Verification

The full combined archive/viewer and affected file-operation/transfer regression
passes **1,951 tests across 78 files**. Fatal-info static analysis is clean for
all **43 changed Dart files**. The focused gates are included in that total:
404 codec/creation/writer tests, 29 native move tests, 94 publication/affected
transfer recovery tests, and all three final borrowed-workspace lifecycle cases.
Three reviewed help guides retain 23 matching topics each; all 33 help
service/widget tests pass against those final bytes. The versioned release web
build passes at `b9619927` with `APP_VERSION=1.2.0+13`. Both version/hash defines
are present in the compiled JavaScript, and all three packaged guide hashes and
the manifest match their reviewed source.

The final documentation-only checkpoint records those observed gates in the
[verification record](archive-move-compress-verification.md). Application and
bundled guide bytes remain identical to that successful build. Dependency
configuration and lockfile match the baseline byte-for-byte. GitHub Actions
returned no runs for the release-build checkpoint; local results do not imply
completed GitHub CI or full native release acceptance.

Independent review corrected timestamp representation in durable file snapshots,
recognized revision persistence, source-draft ownership, mid-publication draft
changes and borrowed UI lifetime. The final lifecycle review is clean. Detailed
coverage, reproducible commands and the independent codec evidence are retained
with the verification record.

## Boundaries

Two physical publications are ordered operations, not an atomic transaction.
Destination publication followed by a source failure can leave a verified copy
and retained source data. Independent external changes cannot be locked across
both files; checks and recoverable source backups must make that boundary
explicit. Same physical containers and native hard-link aliases are refused.

Nested cross-container moves, remote/browser publication, directory/archive
synchronization, durable background packing and full native-platform acceptance
remain separate. Existing interactive memory, path and entry limits remain.
No dependency upgrade, package installation, archive execution or mounting is
part of this increment. Existing PR #93 remains closed.

Implementation uses CrispCloud's existing reader/workspace/publication
architecture, primary format references and existing permitted dependencies.
No VaultExplorer implementation source, tests, assets or dependencies are
inspected or imported. Save coherent checkpoints to the remote branch without
force pushes or merges.
