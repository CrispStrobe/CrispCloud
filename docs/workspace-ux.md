# File workspace UX implementation

## Verified implementation

Functional code `d5fddb6a269f56fdae3a370765eed08dc794fadb` passed **618 repository
tests across 42 files**, plus **three rendered-widget checks** in a separate
temporary harness. The combined run recorded zero failures and zero skips.
Full `lib/` and `test/` analysis completed with zero errors; 86 warnings and 500
informational diagnostics remain. All 72 changed Dart files passed the formatting
gate. The optimized JavaScript web release build of this same code passed,
including the previously missing adaptive-control icon font.

## Scope and baseline

This effort starts from `92078b5d7db04c2f1c211cff62c08eceaf9ddf8a` and is
checkpointed on `feature/file-manager-ux-20261110`. The repository had no open
pull requests at the start of the review. The branch audit is complete: of 18
remaining non-main branches, 15 were already ancestors of main and one was
patch-equivalent. The two remaining review and editor checkpoint branches were
reviewed individually. Useful source-restoration and collection-coherence fixes
were adapted into this branch; the existing integrated editor implementation
was retained after comparison. Recent integrated work also covers transfer
scheduling, terminal sessions, source-bound file operations, storage analysis,
and native asset reliability.

The goal is a coherent, keyboard-accessible workspace across local and remote
storage. A menu entry or a historical completion checkbox is not acceptance
evidence. Existing provider and platform capability limits remain explicit.

## Implemented changes

The implementation covers the concrete gaps found in this review. The
verification record below distinguishes completed checks from platform and
live-provider acceptance that still needs a suitable runtime.

| Area | Resulting behavior | Regression coverage |
| --- | --- | --- |
| Keyboard commands | Saved bindings drive browser dispatch, native menu accelerators, shortcut help, palette labels and the action bar. Custom modifier combinations retain their exact meaning; editors, dialogs and terminals retain input ownership. | `workspace_keyboard_test.dart`, `browser_menu_shortcut_test.dart`, `widget/keyboard_shortcut_dialog_test.dart`, `widget/fkey_bar_widget_test.dart` |
| Column browsing | Deep links and bookmarks load available ancestor directories in the background while the current directory remains usable. Columns scroll independently; ancestor activation reopens the original source and resolves the row again before acting. Filtering applies to the current column. | `widget/file_column_view_test.dart`, `local_directory_snapshot_test.dart`, `ios_local_file_service_test.dart` |
| Navigation and recovery | Each tab has source-bound back/forward history; recent locations retain their storage identity. Closed tabs recover their original source. Source choices identify the exact account, preserve unavailable locations and open each connection's configured root. | `panel_navigation_model_test.dart`, `panel_navigation_recovery_test.dart`, `recent_locations_identity_test.dart`, `widget/navigation_recovery_ui_test.dart`, [source-picker tests](../test/widget/panel_source_selector_widget_test.dart) |
| Startup, refresh and focus | Superseded initialization, source restoration and directory reads cannot replace newer navigation. An explicit local refresh supersedes older startup work; delayed completion preserves input ownership. | `panel_source_restore_test.dart`, `panel_file_origin_test.dart`, `commander_file_list_test.dart` |
| Saved collections | Collection renames, additions and removal update open tabs in both panes. Queued persistence cannot recreate a removed collection; replacement review is bound to its original collection and session. | `file_collection_panel_paging_test.dart`, `file_collection_paging_store_test.dart` |
| Command discovery | The palette ranks multi-word searches across command words, action names and current shortcuts. It exposes navigation, recovery, sorting and pane commands with current availability. | `command_search_test.dart`, `widget/command_palette_localization_test.dart` |
| Listing states | Empty folders, empty collections, filters with no results, loading, unselected browser folders, disconnected storage and failed reads have distinct states. Recovery acts on the owning pane; another pane cannot clear its failure or supply a replacement account. | `panel_listing_presentation_test.dart`, `widget/panel_listing_placeholder_test.dart` |
| Folder tree | Lazy child reads follow the actual account, tab, source root and access grant. Source changes invalidate cached children and stale results are discarded. Failed expansion has a local retry action. | `widget/tree_sidebar_source_test.dart` |
| Folder drops | Normal file views support reviewed folder-row drops. Source files and accounts are captured at drag start; destination identity is checked again before review and execution. | `widget/folder_drop_target_test.dart`, `widget/panel_drop_options_test.dart`, `widget/file_operation_dialog_test.dart` |

Test paths in this table are relative to `test/`.

## Workspace controls

Choose **Columns** from the file-view selector to keep ancestor directories
visible beside the current directory, including when opening a deep bookmark or
entering a path directly. Available ancestors load in the background up to the
source root or granted local folder. Each column scrolls independently. Opening
an ancestor row first verifies that directory in its original storage source;
filtering applies only to the current column. Archives, search results and flat
collections retain their existing list surfaces because their rows do not imply
a single directory hierarchy.

Background local reads use existing access without changing the selected
directory or requesting a new grant. A replaced browser folder invalidates both
pending and already displayed ancestor snapshots, even when its name matches
the old folder. Delayed reads and clicks cannot transfer those snapshots to
another tab, account or grant.

The back/forward history button belongs to the active tab. Its menu includes the
storage identity and position of each location. Reopen a closed tab from the
tab menu, command palette or the default **Ctrl+Shift+T** binding. History is
bounded to 100 entries per tab and closed-tab recovery to 20 tabs per pane.
Locations whose original account or access grant is unavailable explain the
problem instead of opening the same path in another source.

The source picker identifies the exact connection and storage account even
when multiple accounts share a provider or display name. Its current entry
reflects the pane's actual requested or listed storage. An unavailable original
source stays visible as a disabled entry, and choosing a connected source opens
that connection's configured root. An open menu retains its original choices
and owning tab; activation rechecks the live client, storage identity and root
before changing the pane. A replaced connection or a switched tab invalidates
that menu choice. These behaviors are covered by the
[source-picker regression tests](../test/widget/panel_source_selector_widget_test.dart).

**Settings → Customize shortcuts** lets you search actions and record a new
combination. Conflicts must be resolved before saving. Each override can be
reset independently; resetting all bindings requires confirmation. Defaults use
Command as the primary modifier on macOS, while recorded modifiers remain
exact. The command palette searches command words, action names and current
shortcuts; unavailable history actions remain visible and disabled. Text entry,
modal workflows, editors and terminal sessions own their keys while focused.
The bottom action bar reflects customized shortcuts and inherits application
typography. A long binding keeps its complete tooltip and accessible label when
the compact visual label is truncated.

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

A filter with no matching files offers **Clear filter**, including when the
only remaining navigation row is the parent folder. Directory failures remain
visible until that pane retries or changes location. A disconnected saved tab
names the need to reconnect its original storage and stops an obsolete loading
indicator. Local permission recovery requests access for the affected folder.
The browser's synthetic empty root offers **Open local folder**; an opened
named folder can be empty without being treated as an unselected workspace.
These states keep the pane's navigation controls available in visual layouts.

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

### Verification record

The final combined regression run tested functional code
`d5fddb6a269f56fdae3a370765eed08dc794fadb`. Repository tests and temporary render
checks are reported separately so visual harness checks do not inflate the
repository test count.

| Check | Observed result | Scope and qualification |
| --- | --- | --- |
| Workspace repository regressions | **618 passed, zero failed, zero skipped; 42 files** | Covers navigation, source identity, collections, keyboard dispatch and ownership, native menu mappings, columns, local snapshot access, listing recovery, folder drops, accessibility and related existing workflows. |
| Temporary rendered-widget harness | **Three passed, zero failed, zero skipped** | Opens a deep folder directly and verifies ancestor context, then renders desktop and narrow shortcut settings. The real column/tree widgets, application fonts and corrected action-bar typography were visually reviewed with verified fake storage. |
| Full `lib/` and `test/` analysis | **Passed the existing errors-only gate; zero errors** | Exit status 0 in 84.2 seconds. The report contains 86 warnings and 500 informational diagnostics. The existing policy was retained and no analysis suppressions were introduced. |
| Changed-file formatting gate | **72 Dart files checked; zero changes required** | The formatting check covers the changed Dart files at the same functional code revision. |
| Optimized JavaScript web release build | **Passed; exit status 0 in 202.2 seconds** | Ran `flutter build web --release --no-pub --no-wasm-dry-run` at the verified functional revision. `CupertinoIcons.ttf` was bundled and tree-shaken from 257,628 to 1,472 bytes; the earlier missing-font warning was absent. |
| Hosted GitHub checks | Queued at this documentation checkpoint | A completed hosted CI result remains outstanding. The local validation results above are recorded independently. |

The combined run completed all 43 suites in 102.11 seconds with 621 successful
checks in total. These final results supersede the earlier focused and targeted
rerun counts for the covered workspace changes.

#### Earlier broad deterministic run

An earlier broader run recorded **7,571 passed, 39 skipped and 19 failed**. It
excluded tests tagged `benchmark`, `live`, `deploy`, `mock_server`, `integration`,
`connection_dialog` and `golden`; it was not a complete repository or native
platform acceptance run.

Sixteen failures occurred at Unix-socket `ServerSocket.bind` with errno 9 in the
FUSE IPC fixtures, before protocol work. The exact runtime cause remains
unproven. One child process could not find `dart` on PATH; the final workspace
run covers that process-journal case with the executable available. The other
two failures exposed explicit-refresh ordering and compact file-row
accessibility defects, which were corrected and covered by the final passing
regressions. A successful rerun of the sixteen Unix-socket fixtures remains
outstanding, and the earlier broad run remains recorded as unsuccessful.

The [workspace CI workflow](../.github/workflows/workspace-ux.yml) retains
formatting, analysis and behavioral checks. Native CI gates are unchanged.
Hosted CI completion, the remaining Unix-socket fixture rerun and interactive
platform acceptance remain outstanding. Skipped tests and unavailable platform
checks are not acceptance evidence.

## Product boundaries and platform acceptance

The following are explicit limits of the current workflows:

- Column context loads at most 128 ancestors with two concurrent reads. An
  unavailable or unreadable ancestor is omitted without blocking the current
  directory; an explicit refresh can retry it. Local implementations without
  the noninteractive snapshot capability retain the current directory and any
  already visited context. Archives, search results and flat collections use
  their existing list surfaces because they do not provide a single physical
  directory hierarchy.
- History retains up to 100 locations per tab, recent locations up to 20
  entries, and recovery up to 20 closed tabs per pane. Older persisted entries
  without storage identity require an explicit source choice. Reconnecting
  another account with the same folder path does not make them available.
- Browser-local writes depend on browser capabilities and a granted writable
  folder handle. File-input fallback does not create writable access. A
  revoked or replaced grant requires a new selection or permission request.
- Folder-row drops apply to normal directory rows. A retained ancestor column
  must be opened before it can be a destination. Source changes, ambiguous
  destination rows, self/descendant drops and same-folder moves require a new
  or different operation instead of silently changing the destination.
- Remote operations remain subject to each connected provider's supported
  capabilities. The new workflows preserve those capability checks and the
  existing operation review; they do not add support for backend operations
  that a provider cannot perform.

Release acceptance still needs the following interactive checks:

| Environment | Required acceptance |
| --- | --- |
| macOS, Windows and Linux desktop | Exercise native menus and customized shortcuts with physical keyboards; verify focus while switching panes, opening dialogs and using the terminal or editors; revoke and renew local folder access where the platform supports it. |
| Supported browsers | Open an empty local folder, cancel and revoke a grant, exercise writable-handle and file-input fallback flows, and verify unavailable storage recovery in each visual layout. Check narrow layouts with the browser's real text scaling and input behavior. |
| Live storage connections | Switch between two accounts with overlapping paths, disconnect during navigation and operation review, reconnect the original source, and verify capability-specific copy/move and failure recovery. |
| Accessibility and large workspaces | Exercise screen-reader announcements, keyboard-only recovery, large text, long localized labels, and large or paged directory/collection contents on the target platforms. |

The local browser surface could not reach the temporary preview server, so the
rendered-widget checks do not establish interactive browser acceptance.
Live storage connections were not exercised in these checks.
