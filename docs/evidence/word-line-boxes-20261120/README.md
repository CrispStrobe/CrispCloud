# Word line boxes — Mac preview 38

Office is synchronized to Quds main `e06eb3a7e21b71c1d5d4b1d2cc9abde24774eb26`. The exact pin retains incoming slide transparency/shadows/gradients, complete background round trips, Zotero and native mobile proofing changes.

The expanded native Microsoft Word comparison passes **52/52 pages from 44 synthetic DOCX documents**, up from 27/52 at the prior baseline. The minimum score is **97.956% foreground-ink F1**, with unchanged 144-DPI/0.5-point tolerance and mandatory page geometry, page counts and visible text-row checks. The original 24 pages all pass. This qualifies the described Latin-text controls; arbitrary documents, complex layouts and scripts still need wider coverage.

Changes include fixed-line baselines, per-line font metrics, greedy Word wrapping, max adjacent paragraph gaps, tab stops, and native kerning thresholds through layout/paint/style resolution and sparse export. A language edit that creates a missing styles part now preserves the kerning fallback across save/reopen.

Validation: 299 primary engine tests, 31 save/style controls, 56 Mac editor tests, 56 native Ubuntu editor tests, 101 final source-integration tests, 10 comparator controls and 41 CrispCloud host tests passed. Additional reconciliation checks are recorded upstream; these counts overlap and are not a combined unique-test total. Static analysis passed.

The Ubuntu run used the SMS-created screen `362339.quds-word-layout-20261120`, native Flutter 3.47.8, no Docker. Screen remains detached for inspection; its workspace is `/mnt/volume1/quds-word-layout-20261120`. No GitHub Actions jobs or status endpoints were queried or awaited.

Full sources, native Word references, metrics and logs: [Quds validation](https://github.com/CrispStrobe/quds_office_suite/tree/e06eb3a7e21b71c1d5d4b1d2cc9abde24774eb26/docs/validation/word-line-boxes-20261120). No proprietary font bytes, font-bearing PDFs or model weights were added to the product. Mac canvas qualification uses the x64 tester under Rosetta; the release build is ARM64.

Build/signature/startup receipt is added after the release artifact is verified.
