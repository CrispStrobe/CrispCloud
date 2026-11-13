# Semantic recovery of older branch work — 13 November 2026

The integration starts from CrispCloud `223fb771` and inventories every live
branch and all 89 returned pull-request heads. Eighty-five PR heads are already
ancestors of that main revision. The non-ancestor PRs are the active #95/#97,
the old ebook candidate #84, and closed Commander review #14. Original branch
histories and source-specific verification records remain preserved separately
from qualification of the new combined app.

## Commander review #14

The closed review head is
`eff79b3c8ed03020aeaeac4dcd86058fb1e2e181`. Its five non-merge follow-up commits
are reviewed against the current implementation rather than replacing modern
source, tab recovery, paging, or operation-queue code with the old tree.

| Original checkpoint | Behavior | Current ownership and recovery |
| --- | --- | --- |
| `6ceb1043` | Keep saved collections coherent across panes/tabs; accept only reviewed replacement rows | `PanelNotifier._prepareCollectionMutation` and `_synchronizeCollectionPanels` invalidate both panes before reloading. `CollectionReplacementReview` captures exact keys, replacement evidence, current origins and store revision; `FileCollectionService.sameReplacementEvidence` rejects a replacement changed after review. Rename/remove actions still route through the panel owner. |
| `0911c144` | Preserve collection header and empty-state controls in gallery layouts | `FilePanel` renders `_buildFileListHeader` outside the list/grid/gallery/column layout selection. The header remains conditional on the collection state, not the number or visual type of rows. |
| `a93ba37c` | Avoid a Riverpod self-dependency when synchronizing collection panes | `_collectionPanels()` retains `this` directly and reads only `oppositePanel(side)`. Shared mutation and mark-flush paths use that captured panel list. |
| `24bbba76` | Bind new tabs to the actual pending source; reject stale refreshes | `duplicateTab` preserves the original source, view and history; collection tabs use `_createTabLocation` without an interim folder listing. This recovery additionally captures the current directory presentation's storage before a new path tab invalidates its pending listing. Refresh no longer substitutes the default primary cloud account while an explicitly selected local source is loading. |
| `eff79b3c` | Give newer source choices and explicit refreshes priority over startup | `PanelSourceNotifier._sourceRevision` rejects delayed preference restoration after source/navigation intent. `_initializeLocalPath` checks its generation after each asynchronous boundary. `refresh` reserves a new listing generation before preparation and refuses stale tab/path/source completions. Existing startup and source-restore regressions exercise these contracts. |

The recovered pending-source cases are in `test/commander_file_list_test.dart`:

- A right-pane Refresh remains on the selected local source while its first
  listing is blocked.
- A new path tab captures an explicitly selected local source before that
  source's first listing completes.
- A new path tab captures the original pending cloud source before its first
  listing completes.

Relevant existing coverage is in `test/panel_source_restore_test.dart`,
`test/panel_refresh_lifecycle_test.dart`, `test/file_collection_test.dart`,
`test/file_collection_panel_paging_test.dart`, `test/workspace_tabs_test.dart`,
and the gallery/source-selector widget suites. The mapping above records the
observed implementation; executed checks of the combined revision are recorded
in the integration receipt rather than inheriting historical test totals.

## Ebook candidate #84 and native-input checkpoint

`464e4dd3f548302ee5b9f78994fa09caf95437bc` contains native-input checkpoint
`7e20b40c1b797d463704106c881b9e84415f4fd7`. These heads predate extraction of the
ebook packages into [Crisperbooks](https://github.com/CrispStrobe/crisperbooks).
The extracted repository owns reader/converter/native implementation; the app
owns source access, persistence and its immutable dependency pin. Restoring old
bundled package directories would create two competing implementations.

The current extracted observer already retained trusted-parent native selection
polling, input routing, speech, and subsequent platform fixes. Three candidate
safeguards were still missing and are now recovered on canonical branch
`fix/reader-selection-recovery-20261113`, beginning at published checkpoint
`c8e65a075d2dc3de0c040905d3b76f3ebca6f785`:

1. Bound text extraction before materializing a large selection; stop at 20,000
   code units or a 4,096-step DOM traversal budget.
2. Report only range-zero text for a multi-range selection, matching its CFI.
3. Bind fixed-layout documents to trusted load-event section indices, with the
   observer installed before the first page initialization.

Reflow/CFI retry, invalid section rejection, eight-document scan bounds and
cleanup on failed initialization, replacement and disposal accompany those
recoveries. The public package API and the current reader's input/speech paths
remain in the extracted implementation.

The canonical recovery has eleven real-JSDOM selection cases, normal and forced
compatibility parser checks, pinned runtime/license verification, and new actual
browser selection assertions. Local Chromium could not initialize its
process-singleton socket in the managed environment, so those browser assertions
remain a hosted gate. Its source-specific details are in the canonical
`docs/reader-selection-recovery-20261113.md`; historical WebKit/device receipts
are not relabeled as results for the new source.
