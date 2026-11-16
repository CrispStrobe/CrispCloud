# Incoming Office integration before recovery acceptance

This record covers the incoming repository refresh immediately before final
workspace-recovery validation. The pre-integration checkpoint was
`28dd2e9897a0c41e92ed7faaf4c587c68d8bb594`. No GitHub Actions were queried or awaited.

## Repository inventory and original PR ancestry

The saved advertisement contains 199 references: 43 branch heads and 156 PR
heads. All but four unique tips were ancestors of the pre-integration checkpoint:

| Incoming reference | Original tip | Integrated main commit |
| --- | --- | --- |
| PR #164 / `fix/ods-custom-validation-vendor` | `9898961e5cb64cdfc704f85c8f6f5ebedad3c39a` | `621a510aec044ca9a26180a43f9ecd8ec43ce10b` |
| PR #165 / `fix/ods-validation-messages-vendor` | `a617e188cf69f3d3c14dba614593f953dadf1436` | `28db447a9550ffc03ea1891147deed920cdbed79` |
| PR #166 / `docs/validation-complete` | `8197b59177827cfa7b426c55acd0cdca19f9b6eb` | `5d3a020d4d3c5e1a89c0209378df0fce3f78efe3` |
| `main` | `5d3a020d4d3c5e1a89c0209378df0fce3f78efe3` | same |

Each original PR head has exactly the same full Git tree as its corresponding
main squash commit. `squash-head-identities.json` records those identities.
The host integration can therefore merge main's content and add each original
PR tip as an additional parent without inventing or duplicating changes. The
saved inventory describes ancestry before that integration; a post-integration
ancestry check must use the actual resulting host commit.

Main changes four managed ODS files plus two explanatory documents and the
Office manifest. It adds custom-formula validation and validation help/error
messages and styles. Its manifest predates 18 newer Zotero files retained on the
feature branch. Taking that entire manifest would lose the current source
inventory. The ordinary host merge combines the four new ODS hashes with the
existing 2,409 entries; its only conflict is the canonical source branch/pin.

## Canonical combined source

The retained Quds pin `4235e690602195cc504438a6b937972c71f1ad39` and incoming
pin `14fde4b1bd2539f0c6168be4569ac1adcc5105cd` diverge at
`4ffdf113803806ba5f8ade4a0846eee85dcfbe68`. None of the 89 advertised canonical
references (34 branches and 55 PR heads) contained both pins at the snapshot.
The canonical advertisement intentionally precedes creation of the new branch.

Their clean local merge produced tree
`f0e47bfd8f0be406ba6aa69886e76371faa86b03`. The same tree was created using the
GitHub Git Data API and published as a two-parent commit:

- Repository: `CrispStrobe/quds_office_suite`
- Branch: `codex/terminal-recovery-office-20261116`
- Commit: `be2c3a91b0dd5b4abb1b9a7baa8f5e10769bc87a`
- First parent: `4235e690602195cc504438a6b937972c71f1ad39`
- Second parent: `14fde4b1bd2539f0c6168be4569ac1adcc5105cd`

The published branch was then fetched into a filtered bare repository. Its
commit, parents and tree match the reviewed local merge. Both source parents
are actual ancestors. Exactly four ODS implementation/regression files differ
from the retained parent; all other source content, including the newer Zotero
work, remains present. The host manifest now names this combined source pin.

## Fresh byte and mode verification

`combined-vendor-proof.json` and the compressed per-file inventory establish:

- All 2,409 manifest file SHA-256 values match the current host files.
- All 2,409 blobs and executable bits match the stage-zero host Git index.
- All 552 Quds-managed blobs and modes match the fetched combined canonical
  commit exactly.
- All 1,857 separately pinned legacy-parser blobs and modes match the
  pre-integration host checkpoint; their independent source pin remains
  `4895712158127b2fc930d796e17035c3ca0dac62`.
- The managed path inventory is unchanged. There are exactly four changed
  managed file contents, and no mode corrections were needed.

The ordinary host verifier also passed:

```sh
python3 tool/verify_office_fidelity.py --require-tracked
```

The supplemental proof can be reproduced after fetching the canonical branch:

```sh
python3 docs/validation/terminal-workspace-recovery/incoming-audit/verify_combined_vendor.py \
  --source ../quds-recovery-integration.git
```

The supplemental script reads local and Git data and writes this evidence only;
it does not edit source, dependencies, refs, or the index. It deliberately
compares the standalone parser with the prior accepted host checkpoint rather
than claiming a fresh download of that unchanged standalone repository.

## Validation scope

The targeted incoming regression cohort is the vendored ODS reader and sheet
formula suites plus the host ODS editor workflow suite. The existing adapter
runner under `terminal-ssh-multiplexing/incoming-office-tests/run.py` can execute
these against the production dependency graph while preserving original vendor
bytes. Its only adapter edits replace the test import and qualify two fixture
paths. Test execution and platform limitations belong in the final recovery
acceptance record; this directory establishes source integration and provenance.
