# Archive move and UNIX compress continuation

Date: 12 November 2026. Baseline:
`19d359ba1dd5730fc01824efe69e309be26f876d`.
Branch: `feature/archive-rearrange-cpio-20261112`.

## Scope in progress

1. Reviewed moves between two distinct, top-level native archives on the same
   persistent local storage. Build and review both destination additions and
   source removals before publishing. Publish and verify the destination first;
   source publication must durably retain its exact destination dependency.
   Partial results must distinguish a published copy from a completed move.
2. Persist the source-removal publication as a versioned recovery record that
   older apps refuse. Restart recovery must verify the destination's captured
   identity, complete contents and access policy before finishing source
   publication or deleting its original backup. If the destination changed,
   retain the source recovery material and offer only verified restoration.
3. Add UNIX compress (`.Z`) and TAR.Z creation and narrowly eligible rewrites,
   with independent native readback and actual JavaScript execution. Keep
   dictionary/framing choices and the absence of a stored checksum explicit.

These are planned completion criteria, not claims of delivered capability.
Completed checkpoints and observed validation will be recorded below.

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
