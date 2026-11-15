# Audit of the newly observed VeraCrypt-named branch

Observed 2026-11-15 UTC, using read-only GitHub connector queries and immutable local Git objects. No repository, remote ref, or working tree was changed.

## Decision

At exact head `7c1c925028d66f8109c628b8c17a0d4f1d70cb73`, `feature/veracrypt-compatibility-20261115` contains no new VeraCrypt feature implementation or experimental feature delta. Its new content is directly relevant Office/storage qualification evidence. Incorporating this exact checkpoint into the active integration preserves that evidence without introducing a VeraCrypt code change. Preserve the feature branch itself for its owner's future work; this audit makes no claim about later commits.

The branch name alone is not evidence that feature work exists. The live GitHub branch list still resolved it to the exact audited commit. Exact-head PR search and the REST list with `head=CrispStrobe:feature/veracrypt-compatibility-20261115` both returned an empty result. A broader VeraCrypt PR search returned historical PRs 18, 24 and 25, not a new PR for this branch.

## Exact ancestry and scope

| Comparison base | Commits only on base | Commits only on audited head | Changed paths |
| --- | ---: | ---: | ---: |
| Main `686318626e209220011f7da194cfe4e41ca4adeb` | 0 | 120 | 1,373 |
| Active storage integration `7d0de79eeb5932e355e66af0be073d58f9fcf3c4` | 0 | 2 | 13 |

Both comparison bases are ancestors. The large main comparison includes already integrated Office/storage work and must not be interpreted as a new VeraCrypt feature diff.

The audited commit is a merge with parents `7d0de79eeb5932e355e66af0be073d58f9fcf3c4` and `6a5603236c9f3f9e186c5eb3ba5fd76a085b1df6`. The latter is titled “docs: preserve completed source-scoped acceptance before incoming refresh [skip ci]”. The merge is titled “Merge recent source branches and final local acceptance evidence [skip ci]”.

All 13 changed paths relative to the active storage integration are under `docs/evidence/storage-carving-20261115/local-resume-20261115T1150/`: the existing README, final acceptance record, independent review, source/receipt cross-bindings, incoming closure supplements, and visual-review records. There is no app, engine, parser, build, dependency, or test-source change in this delta. All seven named VeraCrypt source/test files have identical Git blob IDs at both commits; `veracrypt-blobs.json` records each comparison.

## Evidence scope

The incoming README and `final-acceptance.json` explicitly qualify production source `20ee83ff965d5433aeb528ae84debdb304edcf4a` and source-identical descendants through `137c95de221a0e30b14b59613b2f23447dcc57da`. They mark those results as superseded for acceptance of later source `41885d7d1d67348f5abe3579b99d9d2951fc909f`. Retain that boundary when importing these records. Their saved 1,253 host/Office tests must not be relabeled as tests of the current changed source.

This branch audit did not run product tests, wait for GitHub Actions, or independently rerun the incoming record's scripts. The earlier receipt audit already covers the historical source cohort; the current integration still needs its separately planned source-bound qualification.

## Saved audit records

- `git-audit.json`: exact commits, merge bases, divergence, changed path and numstat inventories, and inspected record identities.
- `github-proof.json`: live branch values and the empty exact-head PR query results.
- `veracrypt-blobs.json`: exact identity of the seven preexisting VeraCrypt files.
- `diff-7d0de79e.txt`: the 13 relevant incoming paths.
- `diff-68631862.txt`: the larger historical comparison to main.

The copied README and final-acceptance/closure records in this audit directory are read-only inspection conveniences; the authoritative originals remain in Git at the audited commit.
