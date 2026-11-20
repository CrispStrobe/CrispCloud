# Word-native layout integration — 20 November 2026

Integrated the canonical Quds main source identified in acceptance.json. It
retains the host's current geometric shapes, picture borders/backgrounds, Zotero
and mail work, and adds actual-font line spacing, canvas baseline alignment and
imported blank-paragraph font metrics.

41 actual host cases pass, covering native font dialogs, fallback reading, layout
units, separate first-page headers, save/copy/export failures and concurrent edits.
The Quds record retains 182 engine cases, 32 editor cases and eight metric controls
plus native Microsoft Word 16.111.1 page references.

The first corpus passes 20/24 pages strictly above 95% foreground-ink F1, with
correct text and pagination on all 24. This is bounded progress, not full Word
fidelity. Four exact-spacing Arial/Times pages still fail the target; wrapped
paragraphs, complex stories/tables and additional scripts/devices need coverage.
See the [source validation record](https://github.com/CrispStrobe/quds_office_suite/blob/main/docs/validation/word-native-layout-20261120/README.md)
for fixed metric tolerances, raw comparisons, the retained failing gate and next
work. No CI jobs/status endpoints were queried or awaited.
