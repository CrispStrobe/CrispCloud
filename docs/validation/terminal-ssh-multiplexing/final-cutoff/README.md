# Final remote cutoff

At **08:59:14.599291 UTC on 16 November 2026**, GitHub advertised **40 branch
heads and 153 PR heads** for CrispCloud. All **193 refs**, representing 155
unique commits, are actual ancestors of delivery source
`951b2450e16074a528a8d66eb62cc9749e06088d`. There are no new nonancestors or
differences between the fetched ref values and the following advertisement.

The local branch, its remote-tracking head and GitHub's advertised
`codex/terminal-screen-workspace` head all equal that exact commit. Local HEAD
was unchanged throughout verification. The accepted runtime source remains
`2ca566a3a386b5876274d36ff7d93ea21c93fa80`; the later checkpoint records its
acceptance and provenance.

| Phase | UTC timestamp |
| --- | --- |
| Fetch started | `2026-11-16T08:58:59.265012+00:00` |
| Fetch completed | `2026-11-16T08:59:08.672718+00:00` |
| Advertisement started | `2026-11-16T08:59:08.673519+00:00` |
| Advertisement completed | `2026-11-16T08:59:14.599291+00:00` |
| Ancestry verification completed | `2026-11-16T08:59:16.260139+00:00` |

Exactly one full fetch and one subsequent advertisement were performed:

```sh
git fetch --no-tags --prune origin '+refs/heads/*:refs/remotes/origin/*' '+refs/pull/*/head:refs/remotes/pr/*'
git ls-remote origin 'refs/heads/*' 'refs/pull/*/head'
```

Every captured SHA was checked with `git merge-base --is-ancestor` against
`951b2450`. The [receipt](receipt.json) contains the exact commands, timestamps,
head comparisons and per-reference ancestry results. The unmodified
[advertisement](advertised-refs.txt) and [fetch output](fetch.log) are retained.
No SDK process, application source edit, index edit, GitHub Actions query or
Actions wait was used. This is the single final cutoff; no later remote poll
is claimed.
