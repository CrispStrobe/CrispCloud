# File workspace UX implementation

## Verified implementation

Functional code `036922ad26fc971a040c16ddcf4d1046720120be` passed **705 repository
tests across 48 suites**, with zero failures and zero skips. Two additional
rendered-widget checks exercised the expanded transfer queue and a narrow Arabic
layout at increased text scale. Full `lib/` and `test/` analysis completed with
zero errors; 78 warnings and 500 informational diagnostics remain. All 83 changed
Dart files passed formatting. The optimized JavaScript web release build of this
same code passed, including the adaptive-control icon font.

This continuation adds source-bound breadcrumbs and path entry, searchable
per-file transfer diagnostics, and reviewed drops into visible ancestor folders.
Local grant lifetime and delayed-read regressions are covered separately from
the presentation checks. Current hosted checks are queued; earlier hosted
results and the remaining interactive acceptance are recorded below.

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
| Breadcrumbs and path entry | Breadcrumbs start at the actual configured or granted root, including Windows drives and UNC shares. Path entry and open location menus retain their original source and owning tab. Invalid paths remain editable; explicit local access choices bind the target grant independently. | `panel_breadcrumb_test.dart`, `widget/panel_header_navigation_test.dart` |
| Startup, refresh and focus | Superseded initialization, source restoration and directory reads cannot replace newer navigation. An explicit local refresh supersedes older startup work; delayed completion preserves input ownership. | `panel_source_restore_test.dart`, `panel_file_origin_test.dart`, `commander_file_list_test.dart` |
| Local grant lifetime | Virtual local listings and origins retain their exact access tokens; replaced grants cannot publish delayed rows or supply operation authority. Choosing another native saved root preserves existing scoped access to the original destination. | `local_grant_origin_test.dart`, `widget/file_column_view_test.dart`, `folder_drop_snapshot_test.dart` |
| Saved collections | Collection renames, additions and removal update open tabs in both panes. Queued persistence cannot recreate a removed collection; replacement review is bound to its original collection and session. | `file_collection_panel_paging_test.dart`, `file_collection_paging_store_test.dart` |
| Command discovery | The palette ranks multi-word searches across command words, action names and current shortcuts. It exposes navigation, recovery, sorting and pane commands with current availability. | `command_search_test.dart`, `widget/command_palette_localization_test.dart` |
| Listing states | Empty folders, empty collections, filters with no results, loading, unselected browser folders, disconnected storage and failed reads have distinct states. Recovery acts on the owning pane; another pane cannot clear its failure or supply a replacement account. | `panel_listing_presentation_test.dart`, `widget/panel_listing_placeholder_test.dart` |
| Folder tree | Lazy child reads follow the actual account, tab, source root and access grant. Source changes invalidate cached children and stale results are discarded. Failed expansion has a local retry action. | `widget/tree_sidebar_source_test.dart` |
| Folder drops | Normal file views and visible ancestor columns support reviewed folder-row drops. Source files and accounts are captured at drag start. Ancestor destinations are freshly verified without navigating or requesting a grant, then checked again before review and execution. | `folder_drop_snapshot_test.dart`, `widget/file_column_view_test.dart`, `widget/folder_drop_target_test.dart`, `widget/panel_drop_options_test.dart`, `widget/file_operation_dialog_test.dart` |
| Transfer inspection | Expanded batches search names, literal paths and saved destinations, and filter files by attention, unfinished, completed or skipped status. Rows expose errors; keyboard and touch open selectable full details with copy support. | `widget/transfer_file_details_test.dart`, `widget/operations_panel_test.dart`, `operations_i18n_test.dart` |

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

Breadcrumbs start at the connected source's configured root or the granted local
folder. Windows drive roots and UNC shares remain absolute. An unrelated root
does not produce an invented ancestor trail. Breadcrumb actions, path editing
and open location menus capture the original source and owning tab; a later
account, client, tab or source change invalidates them. Relative remote paths
resolve within that original root. Local input resolves to an absolute path;
Escape cancels editing and invalid input remains available for correction.

An explicit local location outside the current grant may request access through
the existing picker. The target is resolved through the same local storage and
retains its own grant identity, including when opened from the browser's
synthetic root. Its lifetime does not depend on the previous grant. Background
reads never use that explicit-access path. Virtual root rows bind independently
to their corresponding grants; replacing one does not invalidate unrelated
rows. Native backends continue to verify scoped access to the actual path, so
selecting another saved folder does not revoke an already reviewed destination.

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

Drag a file or an existing marked group within the application onto a folder
row to open copy review.
Hold **Shift** alone to review a move. The hovered folder shows the operation and
destination. The drag retains its original files and accounts; a changed tab,
listing, connection or destination requires a new drag. Self/descendant drops,
same-folder moves and unverified destination rows are rejected. No files are
changed until the existing operation review is accepted. Dropping into the
active column or any visible ancestor folder preserves the current directory.
An ancestor row is a destination candidate only: it cannot supply operation
sources. Verification uses fresh backend metadata or a noninteractive local
parent listing, with exact direct-child matching, folder type and root checks.
Verification rejects missing or ambiguous destinations and any detected changes.
The drag retains the original snapshot and source session throughout verification
and review.

Expand a transfer batch to search its file names, literal paths or saved
destinations, including renamed targets. **All**, **Attention**, **Unfinished**,
**Completed** and **Skipped** show counts for the current search. A queue search
that matches a member seeds the file search; a user's later file-search edits
remain intact during progress updates. Metadata failures stay in Attention and
Unfinished even when all payload bytes have copied. Pending conflict decisions
also remain visible. These controls inspect the existing batch without changing
its operation plan or recovery authority.

Errors appear directly beneath the affected file. Activate a row with a pointer,
keyboard or screen reader to inspect its full selectable name, literal path,
saved destination, status, size and error. Literal paths retain left-to-right
direction inside right-to-left interfaces. **Copy details** reports clipboard
failure in the same dialog and permits retry. Filters wrap on narrow layouts,
and the details dialog supports increased text scale.

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

The final local regression runs tested functional code
`036922ad26fc971a040c16ddcf4d1046720120be`. Repository tests and temporary render
checks are reported separately so visual harness checks do not inflate the
repository test count. All four repository batches completed successfully.

| Check | Observed result | Scope and qualification |
| --- | --- | --- |
| Workspace repository regressions | **705 passed, zero failed, zero skipped; 48 suites** | Covers navigation, breadcrumbs, path editing, grant replacement, source identity, collections, keyboard ownership, native menu mappings, columns, local snapshot access, listing recovery, ancestor drops, transfer diagnostics, accessibility and related existing workflows. |
| Temporary rendered-widget harness | **Two passed, zero failed, zero skipped** | Three captures show the actual expanded desktop queue, file diagnostics at 390 logical pixels in Arabic with 1.4 text scale, and the full details dialog. Production widgets, application fonts and deterministic transfer records were used; platform fallback fonts are supplied explicitly by the harness. |
| Full `lib/` and `test/` analysis | **Passed the existing errors-only gate; zero errors** | Exit status 0 in 92.0 seconds. The report contains 78 warnings and 500 informational diagnostics. The existing policy was retained and no analysis suppressions were introduced. |
| Changed-file formatting gate | **83 Dart files checked; zero changes required** | The formatting check covers changed Dart files at the same functional code revision. `git diff --check` also passed. |
| Optimized JavaScript web release build | **Passed; exit status 0 in 240.8 seconds** | Ran `flutter build web --release --no-pub --no-wasm-dry-run` at the verified functional revision. `CupertinoIcons.ttf` was bundled and tree-shaken from 257,628 to 1,472 bytes; the earlier missing-font warning was absent. |
| Release-evidence regression suites | **76 passed, two existing platform skips** | The evidence suite completed 41 tests with two skips; the preflight suite passed all 37. The existing `crypto_release_evidence.py --check` source gate also passed. No validators or rejection cases were weakened. |
| Hosted GitHub checks at the current functional revision | Queued at this documentation checkpoint | These runs have not established hosted acceptance for the new code. Earlier hosted results below apply to their recorded revision. |

The four repository batches recorded 120, 252, 148 and 185 successful tests,
respectively, in a total of 175.098 seconds of test execution. Their 48 suites
include all 45 candidates in the dedicated workspace workflow and three existing
source, tab and collection suites. These completed runs supersede the earlier
focused rerun counts; an interrupted local aggregate was not counted as
acceptance. The earlier three column/shortcut render checks remain historical
evidence at their original revision and are not added to this run's totals.

#### Earlier hosted results and evidence refresh

Hosted [CI run 42930629411](https://github.com/CrispStrobe/CrispCloud/actions/runs/42930629411)
tested the earlier branch revision
[`6a8e24c917479d83cc468e072d47405eda8d86a1`](https://github.com/CrispStrobe/CrispCloud/commit/6a8e24c917479d83cc468e072d47405eda8d86a1).
Its [Linux analysis/test job](https://github.com/CrispStrobe/CrispCloud/actions/runs/42930629411/job/130228172217)
reported **7,644 tests passed and 35 skipped**. All **18 FUSE protocol cases**
passed, including the sixteen previously blocked at local Unix-socket startup.
The separate workspace, text/hex, image, PDF and media workflows also succeeded
at that earlier revision.

The CI run was not wholly green: its standalone source-evidence job and the
iOS, macOS and Android artifact-evidence steps rejected stale recorded source
and lockfile hashes after their build commands had succeeded. The
[source and dependency review](crypto-source-review-2026-11-11.md) records the
exact changed inputs and refreshes only their review date and fingerprints.
Existing declarations and distribution assertions retain their prior evidence;
this engineering review does not claim a new legal, live-store or distribution
review. The refreshed source gate and its regression suites passed locally at
the current functional revision; current hosted artifact results remain pending.

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
regressions. The later hosted run above resolves the sixteen Unix-socket fixture
reruns; the earlier broad local run itself remains recorded as unsuccessful.

The [workspace CI workflow](../.github/workflows/workspace-ux.yml) retains
formatting, analysis and behavioral checks. Native CI gates are unchanged.
Hosted CI completion for the current revision and interactive platform
acceptance remain outstanding. Skipped tests and unavailable platform checks
are not acceptance evidence.

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
- Folder-row drops apply to normal directory rows and freshly verified visible
  ancestor folders. Ancestor snapshots supply destinations only. A backend
  without suitable fresh metadata or noninteractive local snapshots cannot use
  that destination path. Source changes, ambiguous destination rows,
  self/descendant drops and same-folder moves require a new or different
  operation instead of silently changing the destination. These review
  guarantees apply to in-app drags; native/external drops retain their existing
  pane-level handling.
- Fresh destination verification checks object/version evidence when the backend
  supplies it and opaque virtual-root tokens where supported. A backend without
  stable child-object identity cannot prove that a same-path directory is the
  identical underlying object using its name alone.
- Per-file inspection depends on the progress and saved transfer entries that a
  job exposes. Filtering and copying details do not create missing historical
  destinations or add new retry authority to an existing operation plan.
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

The earlier local browser surface could not reach the temporary preview server.
The rendered-widget checks establish layout and widget behavior only, not
interactive browser acceptance. The native scoped-access regression uses the
actual local service with injected bookmark access and temporary directories;
it does not replace an operating-system permission-dialog test. Live storage
connections were not exercised in these checks.
