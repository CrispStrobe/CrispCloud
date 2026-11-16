# Refreshed incoming CrispCloud work accounting

Observed UTC: `2026-11-16T13:41:21.389360+00:00`. Ancestry is evaluated against exact
published continuation commit `c12e7ee7a0045c125cf35fee94ecc2027ffd8848`. This refresh reads only
already-fetched local `origin` refs; it performs no new fetch.

The observed refs and times above are unchanged. Ancestry was re-evaluated at
`2026-11-16T13:45:09.118256+00:00` against this published checkpoint, whose tree
is `5ac39493df4091136b9ad478dd538220b06848b9`. That tree is identical to the local checkpoint originally
used for this inventory. Any local-only checkpoint hashes in the JSON are
explicit provenance and are not required to reproduce the graph results or
recover the preserved initial files.

## Cutoff and original evidence

The [machine-readable inventory](incoming-refs.json) records every local ref,
remote-ref mapping, SHA and ancestry result, plus the exact raw ref snapshot
and its SHA-256. These observed refs define the cutoff; the inventory does not
claim that remote branches stopped changing.

The initial inventory and narrative remain byte-for-byte copies:

| Preserved file | SHA-256 |
| --- | --- |
| [initial-incoming-refs.json](initial-incoming-refs.json) | `1fca3724897d37038906abb56599e88ea49c7cd24331be39670f09ead87297dd` |
| [initial-incoming-work.md](initial-incoming-work.md) | `d543b728d732657045dfda1748bbf5429a9f24e06d207eadfc3f0b2e73d77903` |

The incoming count remains 208. `origin/main` and
`origin/integrate/current-repos-20261116` advanced from `dfca0b6b` to
`f7353bf5`; no incoming refs were added or removed relative to the initial
inventory.

The origin-main reflog records a heads-plus-PR-heads fetch update at
`2026-11-16T13:28:02+00:00`. This is an exact ref update observation, not a
claim about the completion time of every later unchanged-ref fetch. The latest
local `FETCH_HEAD` write, `2026-11-16T13:31:51.895708+00:00`,
contains only a subsequent continuation-branch verification fetch at
`189ab0b3`. It must not be treated as the full incoming-ref cutoff.

## Exact integration

Fetched main is `f7353bf5cdbdd1a3e1b5d02615b051eaa0dae644`. Its two commits
since the initial main add persistent keychain lock controls, direct pane
favorites menus and their policy/acceptance evidence (`0f87058b` and
`f7353bf5`). The continuation retains this main as a parent of merge
`189ab0b3bdf6816ddb7319ca2d830e2ab69ccea1`, alongside the Zotero continuation
at `501c3a66`.

Every observed incoming head is already an ancestor of fetched main and of
the recorded continuation source. This is a graph result, not a claim that
this refresh independently merged every branch or that every branch has a
distinct new patch. No nonancestor or supersession exception is required for
this CrispCloud snapshot.

The earlier Zotero large-library, terminal, recovery and ODS baseline remains
documented in the [preserved initial narrative](initial-incoming-work.md).
Office vendoring pins and runtime qualification belong to their separate
source and qualification checkpoints; this audit does not infer a tested
host pin from ancestry alone.

## Complete observed ref accounting

| Remote | Branch heads | PR heads | Ancestors of fetched main and continuation |
| --- | ---: | ---: | ---: |
| `CrispStrobe/CrispCloud` | 48 | 160 | 208 |

All **208 observed incoming refs are accounted for by ancestry**.
No upstream remote is included in this repository's inventory.

## Scope and exclusions

The current continuation branch `codex/zotero-capabilities-20261116` is excluded
from incoming counts, including its observed remote-tracking value. Symbolic
remote `HEAD`, tags, local-only branches and synthetic PR merge refs are also
excluded. Refs advertised after the recorded observation, or not present in
the existing local remote-tracking inventory, are outside this snapshot.
PR heads alone do not establish PR state or review approval.

This refresh modifies only these audit documents and preserves the initial
copies. It makes no merge, commit, push, fetch, GitHub Actions, workflow-job,
commit-status or check query. Runtime qualification is recorded separately.
