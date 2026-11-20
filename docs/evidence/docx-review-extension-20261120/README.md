# Current Quds review integration — 2026-11-20

The Office packages match the published Quds main pin exactly (2,892 files).
This includes imported run/paragraph formatting revisions, paired text moves,
undoable review decisions, and the final empty-formatting attribution guard.
The same sync preserves the incoming layout, Zotero, mail, VBA and native spaCy
work from main.

The host run passed 111 cases and found one stale test expectation: page one
was expected to edit the default header despite the fixture having a separate
first-page header. The corrected test checks the first-page story changes, the
default story stays intact, and line breaks/tabs survive three asynchronous
save/reopen cycles. All 12 related host cases replayed against the final code
pin, giving **112 unique passing host cases**, with no unresolved failures.
See [acceptance](acceptance.json) and [final replay](host-final-replay.txt).

The local Dart cache was restored using the enforced existing lockfile. Native
hooks were rebuilt with the installed, version-pinned Rust toolchain after the
old temporary toolchain directories had been cleared. These environment repairs
do not alter application manifests or Rust package locks. No GitHub Actions
jobs or status endpoints were queried or awaited.

Quds has 140 unique regression cases plus a real Microsoft Word 16.111.1 round
trip: four pending native review types, followed by Quds decisions which Word
reopened with 4/0/0 pending/accepted/rejected changes. The separate Word Review
Preview is built, signed and startup-verified; its native libraries match the
qualified linguistic/grammar runtime. Detailed evidence is in the
[Quds validation record](https://github.com/CrispStrobe/quds_office_suite/blob/main/docs/validation/docx-review-extension-20261120/README.md).

## Preserve the simultaneous slide sync

CrispCloud main advanced independently to `702114c8`, pinning Quds slide branch
`9e647ae5`. Reconciled both lines in Quds main (`f9128aba`) first and regenerated
the vendor tree from that canonical merge. All 2,892 files verify exactly.
The unpublished local conflicted commit was replaced before any push. Incoming
Noto Emoji asset/license declarations on CrispCloud main are preserved.

Quds reconciliation passed 88 engine and 21 editor cases. The final host replay
passed **29 cases**, including the corrected first-page header expectations and
17 additional font/history/read-only cases, for **129 unique host cases** across
the acceptance runs. See [unified host replay](host-unified-replay.txt).
