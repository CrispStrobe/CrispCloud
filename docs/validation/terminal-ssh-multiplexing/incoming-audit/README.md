# Incoming integration audit: 16 November 2026

All **193 advertised CrispCloud references** in the snapshot below are actual
ancestors of integration checkpoint
`2ca566a3a386b5876274d36ff7d93ea21c93fa80`: 40 branch heads and 153 PR heads.
The integrated Office inventory retains all 2,409 entries. Its 552 canonical
Quds files match the newly published combined canonical commit by exact Git
blob and mode; its 1,857 separately pinned legacy parser files retain their
original bytes and source boundary. No GitHub Actions were queried or awaited.

## Snapshot and incoming changes

The independent `git ls-remote` snapshot began at **08:46:17.128180 UTC** and
finished at **08:46:21.509531 UTC**. The comparison baseline is
`ea560e8c20c897f98809664e54961509e570b9cb`.

| Incoming reference | Exact commit | Relationship to the baseline |
| --- | --- | --- |
| `main` | `c7463402d878a418d6b31cfd0bfce5c8f6cca63c` | Advances previously integrated `45ed126a` with the PR 162 and 163 squash commits |
| `fix/ods-validation-vendor2`, PR 162 | `2b6ac08219418cf2c2d91968d117437684370c4d` | New original branch/PR head |
| `docs/validation-operators`, PR 163 | `11d4fbd9bc0a6e9fb3fa6cdc7604a45aaeae3210` | New original branch/PR head |

These are the only three unique incoming commits that were not ancestors of
the baseline, represented by five refs. The other 188 advertised ref values
were already ancestors. See [the exact advertisement](advertised-refs.txt)
and [the complete initial ancestry inventory](ref-inventory.json).

The incoming main delta changes seven files: three Office runtime files, one
Office test file, two documents and the Office source manifest. It adds ODS
whole-number, decimal, date and text-length validation import, comparison
operators and XLSX operator round-tripping. It changes no terminal code,
application dependency declaration, lockfile or workflow. The complete delta
is preserved in [incoming-main.diff](incoming-main.diff). Test results quoted
inside incoming documentation remain that work's own source-bound results;
this audit does not relabel them as new application acceptance.

## Squash identity and actual ancestry

The original PR heads were not actual ancestors of the new main, despite
their identical trees:

| PR | Original head | Squash commit | Shared exact tree |
| --- | --- | --- | --- |
| 162 | `2b6ac082` | `3f7bc046` | `eb271f6fdf1d8e644aca67757dd7eab678dd3a4c` |
| 163 | `11d4fbd9` | `c7463402` | `1cbdbd14d3ebac1c2f0f823567da9740624d04af` |

[The identity proof](squash-head-identities.json) records full SHAs, parents,
trees and the distinct ancestry checks. Integration therefore uses the
normally merged main tree while retaining both verified original heads as
additional commit parents. The four parents of `2ca566a3` are the previous
application checkpoint `01e231b5`, incoming main `c7463402`, original PR 162
head `2b6ac082`, and original PR 163 head `11d4fbd9`.

[The post-integration ancestry proof](integrated-ref-ancestry.json), verified
at **08:51:16.327041 UTC**, checks each of the 193 captured ref values against
`2ca566a3` using `git merge-base --is-ancestor`. All pass; no patch-equivalence
substitute is used for the final ancestry claim.

## Combined canonical Office source

A normal host merge produced one conflict, confined to the manifest's source
branch and commit. The four runtime/test files merged cleanly. Taking the
incoming manifest wholesale would have discarded newer Zotero inventory and
would have claimed that the combined files all came from the older ODS-only
pin. The preserved [merge preview](merge-tree.txt) records that conflict.

The isolated Quds clone found no existing branch that contained both required
pins. A later independent branch/PR snapshot includes the newly published
integration branch as its sole combined reference; all other 28 branch heads
and 52 PR heads lack at least one required pin. The exact [Quds
advertisement](quds-advertised-refs.txt), [ancestry inventory](quds-ref-inventory.json)
and [clean merge preparation](quds-combination-preparation.json) are retained.

The published canonical result is:

- Repository: `CrispStrobe/quds_office_suite`
- Branch: `codex/terminal-sharing-office-20261116`
- Commit: `4235e690602195cc504438a6b937972c71f1ad39`
- Exact tree: `bb5f1912fe2ff2b5cfb3d9c7091a184ba54de0ae`
- First parent: `428679a33381f943a8ae63117d4207f01dd15462`
- Second parent: `4ffdf113803806ba5f8ade4a0846eee85dcfbe68`

Its delta from the previous Zotero source is exactly the four incoming ODS
files, with 297 insertions and 56 deletions. It adds or deletes no managed
file. [quds-combined.diff](quds-combined.diff) preserves the exact source delta.
The host manifest now names this actual published commit and retains all
2,409 file hashes, replacing only the four ODS hashes.

The audit also found one pre-existing executable-bit drift:
`packages/quds_office_engine/lib/src/pdf/pdf_canvas.dart` was mode `100755`
in the host and `100644` in the canonical source, with identical blob
`e3c1270563fd8c192c8c615b41584630816415c5`. Integration corrects the host mode to
`100644`; no file bytes change. The [pre-integration proof](pre-integration-vendor-proof.json)
retains this detected difference instead of hiding it.

## Reproducible content and mode proof

[combined-vendor-proof.json](combined-vendor-proof.json) verifies the committed
host checkpoint `2ca566a3` at **08:51:14.571013 UTC**, after the source merge
completed. It confirms:

- All 2,409 host files freshly match their manifest SHA-256 hashes and their
  stage-0 Git index blobs and filesystem modes.
- All 552 canonical Quds entries match the fetched canonical commit's exact
  Git blobs and modes.
- All 1,857 standalone legacy parser entries preserve their baseline hashes
  and `UPSTREAM.json` source boundary at
  `4895712158127b2fc930d796e17035c3ca0dac62`.
- Only the four expected content changes and the one described mode
  correction occurred in the managed inventory.

The full per-file inventory is [combined-vendor-inventory.json.xz](combined-vendor-inventory.json.xz).
Its uncompressed JSON SHA-256 is
`7167b6ed148ff4865212aed6a87cdec15f7ed5d71974b69cf07f88f77462431a`.
Reproduce the proof from the application root with:

```sh
git -C ../quds-sharing-integration fetch --no-tags origin refs/heads/codex/terminal-sharing-office-20261116:refs/remotes/origin/codex/terminal-sharing-office-20261116
python3 docs/validation/terminal-ssh-multiplexing/incoming-audit/verify_combined_vendor.py
```

The verifier reads Git objects directly and requires no Quds working-tree
checkout. A no-checkout clone cannot be passed to the separate filesystem-based
Office verifier's `--source` option; its missing-file result is not a content
mismatch. Application and live SSH acceptance are recorded separately against
the resulting frozen application source.
