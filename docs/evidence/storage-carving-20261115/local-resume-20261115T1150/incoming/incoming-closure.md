# Incoming branch closure

**All 53 distinct relevant heads in the saved finite branch/PR inventories are
accounted for: 49 are ancestors of the final source heads, and four are
demonstrably superseded. No observed relevant head remains unaccounted for.**

This is an immutable local-history closure, not a new remote refresh or runtime
qualification. Per-head results, inventory hashes and exact proofs are in
[`incoming-closure.json`](incoming-closure.json).

| Repository | Final source commit | Observed heads | Ancestors | Superseded |
| --- | --- | ---: | ---: | ---: |
| CrispCloud | `48432b5d0eb22caf365e8659e44ab74cb6aa5a46` | 22 | 20 | 2 |
| Quds | `693dfe543ee0cc2934e23bd53aa3dd72156af1b3` | 24 | 22 | 2 |
| Legacy parser | `09c8b3731edb60bf6e5309578260af36b9433570` | 7 | 7 | 0 |

The late app heads `b0e0f174` and `c8fd8d76`, Quds `9cc8c6e9`, and parser main
`7df906d2` are all direct ancestry inclusions. The original user handoff
`71c14b98` is also an ancestor of the final app source. Already merged PR heads,
the independent qualification/evidence branches, and earlier integration heads
are included in the per-head accounting.

## Four superseded heads

| Observed head | Closure proof |
| --- | --- |
| App `7bfe1ed6`, old Excel branch | Reverified all 52 historical blob matches from the saved 59-path review, including that each matching revision is a final-app ancestor. The remaining four shared app files, service test and two source-pin documents retain the previously reviewed later combined implementations/pins. See the existing README, feature patch and path-lineage evidence. |
| App `eab538e7`, consistency branch | Reverified all 20 historical blob matches. The sole remaining path is fork documentation containing an older pin. |
| Quds `b6d2c587`, old ODS introduction | Reader, fixture and test blobs exactly match merged PR23 head `e002b958`, a final ancestor. Its fourth file differs only by two additional Word exports in PR23; every old export remains in the final source. |
| Quds `01f167cc`, earlier reconciliation | Its entire repository tree `83d3afe9597bd5cad919f3acc34f8d80b78ba05d` exactly matches final ancestor `afe8c511`. This is full-tree equivalence, not an inference from merge ancestry alone. |

## Final app pin binding

The requested initial closure checkpoint `fb109e8d` contained the late feature
merge but still referenced Quds `b4950d60`; its writer lacked the subsequent
linear author-table correction. Root saved follow-up `48432b5d`, and this
closure is bound to that corrected checkpoint.

At `48432b5d`, the Office manifest points to `693dfe54`, both parser pin records
point to `09c8b373`, and the app/canonical writer share blob
`e8eaba8e0ac388511bc282b6b913b127e1194e64`. The follow-up descends from
`fb109e8d`, so all earlier ancestry results remain valid. The old-pin observation
is retained in the JSON as evidence for why the follow-up was necessary.

No repositories were modified. Upstream refreshes, GitHub Actions polls and CI
waits: **zero**. Lazy object fetching was disabled for the closure checks.
