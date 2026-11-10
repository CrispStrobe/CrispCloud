# File workspace UX implementation

## Scope and baseline

This effort starts from `92078b5d7db04c2f1c211cff62c08eceaf9ddf8a` and is
checkpointed on `feature/file-manager-ux-20261110`. The repository had no open
pull requests at the start of the review. Of 18 remaining non-main branches,
15 were already ancestors of main; another was patch-equivalent. The remaining
review and editor checkpoint branches require targeted review, not a blanket
merge. Recent integrated work already covers editors, transfer scheduling,
terminal sessions, source-bound file operations, storage analysis, and native
asset reliability.

The goal is a coherent, keyboard-accessible workspace across local and remote
storage. A menu entry or a historical completion checkbox is not acceptance
evidence. Existing provider and platform capability limits remain explicit.

## Confirmed gaps and acceptance

| Area | Confirmed gap | Required behavior | State |
| --- | --- | --- | --- |
| Keyboard commands | Persisted bindings are disconnected from browser handling; some modified function keys reach the wrong action | Actual dispatch, shortcut help and customization agree; text editors and terminals retain input ownership | In progress |
| Column browsing | Only the current directory is rendered in one narrow column | Visible ancestor columns, independent scrolling, safe ancestor activation and current-directory filtering | In progress |
| Navigation history | Pane-wide paths can be replayed in another tab or storage account | Source-bound per-tab back/forward history, safe recent locations and closed-tab recovery | In progress |
| Startup and refresh | Older asynchronous work can supersede a newer source or navigation choice | Revision checks before publishing state or starting a delayed listing | In progress |
| Saved collections | Renames/appends/removal leave open tabs stale; replacement consent is not tied to the reviewed session | Both panes update coherently; changed collection/session evidence requires a fresh review | In progress |
| Command discovery | Literal substring filtering and fixed shortcut labels hide useful workflows | Ranked multi-word matching, live binding labels and direct navigation/recovery commands | In progress |
| Empty and error states | An empty browser directory can be confused with no folder selected | Distinct empty, filtered-empty, loading, disconnected and unavailable states | Under review |
| Folder tree | Cache keys and listing selection assume pane position identifies storage | Lazy children use the actual account, tab, root and access grant; stale reads are discarded | Implemented; verification pending |
| Folder drops | Internal drags target pane backgrounds but not individual folders consistently | All normal file views offer folder-row review with drag-start source identity, destination revalidation and no silent parent fallback | Implemented; verification pending |

## Workspace controls

Choose **Columns** from the file-view selector to keep ancestor directories
visible beside the current directory. Each column scrolls independently. Opening
an ancestor row first verifies that directory in its original storage source;
filtering applies only to the current column. Archives, search results and flat
collections retain their existing list surfaces because their rows do not imply
a single directory hierarchy.

The back/forward history button belongs to the active tab. Its menu includes the
storage identity and position of each location. Reopen a closed tab from the
tab menu, command palette or the default **Ctrl+Shift+T** binding. History is
bounded to 100 entries per tab and closed-tab recovery to 20 tabs per pane.
Locations whose original account or access grant is unavailable explain the
problem instead of opening the same path in another source.

**Settings → Customize shortcuts** lets you search actions and record a new
combination. Conflicts must be resolved before saving. Each override can be
reset independently; resetting all bindings requires confirmation. Defaults use
Command as the primary modifier on macOS, while recorded modifiers remain
exact. The command palette searches command words, action names and current
shortcuts; unavailable history actions remain visible and disabled. Text entry,
modal workflows, editors and terminal sessions own their keys while focused.

The folder tree follows the active pane's actual source. Expanding a folder is
lazy, does not follow unverified symlinks, and stays within the source root or
granted local base where applicable. A failed expansion offers a local retry.
Switching accounts, tabs, roots or hidden-file visibility invalidates that tree's
cached children.

Drag a file or an existing marked group onto a folder row to open copy review.
Hold **Shift** alone to review a move. The hovered folder shows the operation and
destination. The drag retains its original files and accounts; a changed tab,
listing, connection or destination requires a new drag. Self/descendant drops,
same-folder moves and unverified destination rows are rejected. No files are
changed until the existing operation review is accepted. Dropping into the
active column works; ancestor columns must first be opened to verify their rows.

## Existing capabilities to preserve

- Independent pane sources, tabs, bookmarks, saved workspace layouts and views.
- Source-bound copy/move, conflict review, metadata handling, background queue,
  interruption recovery and honest cancellation outcomes.
- Recursive content search, saved searches and source-preserving collections.
- Preview and text, image, PDF, Office, media and hex editing with recovery.
- Batch rename previews, collision handling and durable undo.
- Archive browsing, bounded extraction and supported edit/repack workflows.
- Directory comparison, reviewed synchronization, checksums and split/combine.
- Connection management, encryption, platform access grants and credentials.
- Localized controls and accessible keyboard, touch and pointer interactions.

## Verification rules

Behavioral regressions must exercise competing navigation, source changes,
custom key bindings, real column transitions and stale collection review.
Existing deterministic and native CI gates remain intact. Record the exact
tested commit and distinguish automated results from interactive platform and
live-provider acceptance. Incremental remote checkpoints preserve work before
the final review. Reference research is kept outside project artifacts.
