# Terminal session optimization, 16 November 2026

This continuation starts at `0c43c476ff33638306425c1427cf1d04a170a912`
and saves incremental checkpoints to
`codex/terminal-session-optimization-20261116`. Commits carry `[skip ci]`.
GitHub Actions are not queried, polled, awaited or rerun.

## Integrated baseline

The independent initial remote inventory contains all 43 branch heads and all
156 advertised PR heads. Every head is an actual ancestor of the starting
commit, including main `5d3a020d`, terminal PR #160 and Zotero PR #161.
No content merge or dependency-pin replacement is required. The saved
[inventory](integration-snapshot.json) also includes the newly created
continuation branch: 44 branches plus 156 PR heads, all 200 included.

## Changes and checkpoint status

- Ordinary terminal sessions keep one in-flight resize and the latest pending
  dimensions. Same-turn layout events coalesce, completed dimensions are not
  resent, and replacement/disconnected sessions revoke stale work.
- Screen exact attachment preserves full listing identifiers and validates
  listing completeness before selecting a target. Unsupported names must not
  be truncated into a different selectable session.
- Native tmux serializes resize requests, retains the last requested geometry
  even when it equals the previous completed size, and shares one completion
  per pending generation. The viewport also cancels an obsolete debounce when
  its dimensions return to the previously sent size.
- Native tmux captures up to eight panes per synchronous command group while
  retaining reply ordering and atomic workspace publication. A controlled
  20-pane fixture requires three capture writes instead of twenty. This is a
  protocol count comparison, not a measured end-to-end speed claim.

The first implementation checkpoint is intentionally saved before the complete
Flutter qualification. Local commands and outcomes will be added as they finish;
historical acceptance from earlier commits is not counted as new validation.

The [Screen resolver before/after proof](screen-resolver-regression.json) runs the
extracted production shell through actual `/bin/sh` and `awk` with controlled
Screen listings. It qualifies command resolution, not a live GNU Screen daemon.
