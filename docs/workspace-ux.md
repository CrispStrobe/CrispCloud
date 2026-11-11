# File workspace UX implementation

## Current integrated implementation

The current runtime performance checkpoint is
[`e9dd5dbbb8581e16f228d4f51239adf7d0b22660`](https://github.com/CrispStrobe/CrispCloud/commit/e9dd5dbbb8581e16f228d4f51239adf7d0b22660).
It adds aggregate-only inline totals, cached derived storage identities with live
input checks, and bounded durable catalog page batches. The
[2026-11-11 performance record](storage-scan-update-2026-11-11.md) reports the
measured gains, inconsistent full-scan/load timings and current validation limits.
The additional multi-root batch UI and its final publication-status repair are
preserved as [inert recovery artifacts](recovery/README.md), not active runtime
code. The execution workspace became unavailable before their final validation.

The preceding integrated UX checkpoint is
[`12924a58b7c87b58d172fae829349e97aec3a64f`](https://github.com/CrispStrobe/CrispCloud/commit/12924a58b7c87b58d172fae829349e97aec3a64f),
with application version `1.1.0+12`. It combines the latest integrated startup
and native-release work with bounded folder measurement, original-result
reports, reviewed inactive-tab drops, exact-session status/quota presentation,
complete analyzer localization and optional SMB backend selection. The earlier
navigation, keyboard, column browsing and transfer-inspection work remains part
of this branch.

The completed local behavioral checks and final analysis/build results are
recorded in [Historical integrated UX verification](#historical-integrated-ux-verification).
Those results predate the current performance changes.
Current hosted, native-platform and live-provider acceptance remain separate
gates. Earlier test, render and build results are explicitly historical.

## Scope and baseline

This effort starts from `92078b5d7db04c2f1c211cff62c08eceaf9ddf8a` and is
checkpointed on `feature/file-manager-ux-20261110`. At the initial review, the
repository had no open pull requests. That initial branch audit examined 18
remaining non-main branches: 15 were already ancestors of main and one was
patch-equivalent. The two remaining review and editor checkpoint branches were
reviewed individually. Useful source-restoration and collection-coherence fixes
were adapted into this branch; the existing integrated editor implementation
was retained after comparison.

This continuation integrates main at
[`05de9cfaa1d3727e7e4fd53b51ec63c5c39438cc`](https://github.com/CrispStrobe/CrispCloud/commit/05de9cfaa1d3727e7e4fd53b51ec63c5c39438cc).
PRs #41 and #42 add explicit startup credential-store recovery and access grants
for selected keychains. PRs #43, #45 and #47 supply local macOS signing support,
the `1.1.0+12` version update and real-app screenshot automation. The optional
SMB branch is integrated through
[`ffeae11`](https://github.com/CrispStrobe/CrispCloud/commit/ffeae11) and
[`4b44dc4`](https://github.com/CrispStrobe/CrispCloud/commit/4b44dc4), followed by
[`087b2d9`](https://github.com/CrispStrobe/CrispCloud/commit/087b2d9d38797bd96eda64962e1998b1f8731c1f). This includes the
independent Rust engine, bridge and persisted GUI/CLI backend choices. libsmb2
remains the default. Integration corrections preserve invalid-profile handling,
legacy default diagnostics and literal CLI credential strings. Source/dependency
review and runtime boundaries are recorded in the
[engineering review](crypto-source-review-2026-11-11.md) and
[SMB rollout notes](SMB_RUST_ROLLOUT.md).

The incoming-ref audit at **2026-11-11 11:06:19 UTC** found no additional
main or SMB commits at that time. Both heads listed above are proven ancestors of
this branch. A later review identified optional SMB commits
[`445c20b`](https://github.com/CrispStrobe/CrispCloud/commit/445c20b) and
[`13ca681`](https://github.com/CrispStrobe/CrispCloud/commit/13ca681).
They are not integrated in the performance checkpoint; their updated native
runtime and Apple packaging evidence still need independent acceptance. The latest CI adjustment runs macOS package tests from a bounded short
physical path to address the pinned native library’s install-name limit; macOS
execution and application packaging still need their own hosted acceptance.

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
| Credential-store recovery | Startup can apply a confirmed choice of another credential store. Selecting a keychain probes access and can request a targeted picker grant; failure or cancellation does not silently select another store. | `credential_storage_recovery_widget_test.dart`, `credential_storage_setup_test.dart` |
| Local grant lifetime | Virtual local listings and origins retain their exact access tokens; replaced grants cannot publish delayed rows or supply operation authority. Choosing another native saved root preserves existing scoped access to the original destination. | `local_grant_origin_test.dart`, `widget/file_column_view_test.dart`, `folder_drop_snapshot_test.dart` |
| Saved collections | Collection renames, additions and removal update open tabs in both panes. Queued persistence cannot recreate a removed collection; replacement review is bound to its original collection and session. | `file_collection_panel_paging_test.dart`, `file_collection_paging_store_test.dart` |
| Command discovery | The palette ranks multi-word searches across command words, action names and current shortcuts. It exposes navigation, recovery, sorting and pane commands with current availability. | `command_search_test.dart`, `widget/command_palette_localization_test.dart` |
| Listing states | Empty folders, empty collections, filters with no results, loading, unselected browser folders, disconnected storage and failed reads have distinct states. Recovery acts on the owning pane; another pane cannot clear its failure or supply a replacement account. | `panel_listing_presentation_test.dart`, `widget/panel_listing_placeholder_test.dart` |
| Folder tree | Lazy child reads follow the actual account, tab, source root and access grant. Source changes invalidate cached children and stale results are discarded. Failed expansion has a local retry action. | `widget/tree_sidebar_source_test.dart` |
| Folder drops | Normal file views and visible ancestor columns support reviewed folder-row drops. Source files and accounts are captured at drag start. Ancestor destinations are freshly verified without navigating, then checked again before review and execution. | `folder_drop_snapshot_test.dart`, `widget/file_column_view_test.dart`, `widget/folder_drop_target_test.dart`, `widget/panel_drop_options_test.dart`, `widget/file_operation_dialog_test.dart` |
| Directory-tab drops | In-app files can target an inactive directory tab without selecting it or replacing the current listing. Fresh destination verification preserves the drag's captured source groups and carries the original endpoints into review. Closed, retargeted or unavailable tabs cannot redirect a drop into the active pane. | `folder_drop_snapshot_test.dart`, `widget/folder_drop_target_test.dart`, `widget/workspace_tab_bar_test.dart` |
| Inline folder measurements | Marking a verified folder queues a metadata scan through its original source. Each pane runs at most two scans concurrently, with a 20,000-entry budget and depth limit of 128 per scan. Only a complete current result supplies an exact calculated folder size. | `panel_folder_size_test.dart`, `widget/folder_size_views_test.dart`, `storage_scan_service_test.dart`, `storage_scan_access_test.dart`, `storage_scan_virtual_test.dart` |
| Original-result reports | Calculate Size opens a detailed report for the captured verified folder, including search and collection results. Stop scan addresses the original queued or running row. Later selection or pane navigation cannot substitute another folder or account. | `widget/folder_size_result_context_test.dart`, `storage_analyzer_origin_test.dart`, `storage_analyzer_widget_test.dart` |
| Source-aware status | Labels, quota, connection state and local capacity follow the active pane's actual storage and client session. Unknown quota fields and unmeasured selections remain explicit; parent rows are excluded from counts, and paged collections use collection totals. | `widget/status_bar_source_test.dart`, `widget/status_bar_widget_test.dart` |
| Analyzer localization | All nine supported languages have complete 78-label catalogs, including queued scans. Literal paths retain left-to-right direction in report selection, scan issues and largest-files rows; narrow layouts retain accessible controls. | `storage_analyzer_strings_test.dart`, `storage_analyzer_widget_test.dart` |
| SMB connection choices | GUI and CLI connections persist libsmb2, Rust or Auto selection. libsmb2 remains the default; Auto permits fallback only at native initialization. Invalid saved GUI modes leave fields intact, and CLI scalar-looking credential strings retain their type. | `smb_backend_field_test.dart`, `smb_connection_profile_dialog_test.dart`, `smb_client_adapter_test.dart`; shared transport and CLI suites are linked in the [SMB rollout notes](SMB_RUST_ROLLOUT.md). |
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

When startup cannot open the configured credential store, **Choose another
credential store** offers a confirmed explicit selection and retries ordinary
initialization with that choice. Selecting an existing file vault retains its
password gate. A selected keychain can request a targeted access grant and retry
that path; cancelling the picker does not substitute another keychain.

Installed SMB connections expose **SMB transport** with libsmb2, Rust and Auto
choices. Save the choice with the connection and reconnect to apply it. Rust
requires the optional native library; strict Rust reports initialization
failure, while Auto can fall back to libsmb2 at that initialization boundary.
Connection and transfer failures remain with the selected backend. An invalid
saved GUI mode leaves the existing fields intact and requires an explicit valid
choice. CLI profiles without a stored choice report **build default** in text;
`providers --json` preserves that inherited choice as `smbBackend: null`. Saved
string values preserve literal text through YAML serialization. GUI and CLI
credentials retain their separate existing storage arrangements.

The status bar follows the active pane's actual directory source. Either pane
can show a local folder or a remote account. The connection label identifies the
displayed live session, and its tooltip includes the configured root and current
path. Quota belongs to that exact session, including when two live clients have
the same provider, account and root. Directory navigation within the same
session reuses its observation; switching sessions starts a separate request,
and a late completion cannot replace the newly selected session's value.

Quota shows loading, unavailable, used-only, total-only or complete used/total
states according to the fields the provider supplies. Activate the usage label
to refresh it or retry a failed request. Local free space appears only when the
active directory has a current capacity observation. Search results, archives
and flat views retain their own context. Item counts exclude the parent row;
paged collections use their matching and total counts. Selected-byte totals
include known file sizes and completely measured folders. When a nonzero known
sum excludes unmeasured items, the displayed total is marked as a lower bound.
The bar scrolls horizontally when localized text or increased text size exceeds
the available width.

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

Mark a verified folder with **Space** or **Insert** to queue an inline size
measurement while advancing the cursor. Queued, scanning and stopping states
remain visible in the size presentation, and its tooltip explains the measured
file and folder counts. Each pane processes two folder scans at a time. An
individual inline scan examines at most 20,000 entries and descends at most 128
levels. Repeated requests for the same active row share the existing work.
Scanning reads metadata through the folder's captured local or remote source;
it does not download file contents or follow symbolic links.

A complete result updates the folder's calculated size. A partial result shows
the known portion as a lower bound, with details for unknown sizes, skipped
links and traversal limits. Stopped, failed and partial scans never become an
exact calculated size. **Stop scan** removes a queued request or stops active
work after the current folder read. Navigation, a replaced row, or loss of the
original account or grant prevents delayed inline results from updating another
listing.

Choose **Calculate Size** from a verified folder's context menu to open its
detailed storage report. The report offers maps, folders and files, largest
files, file-type filters and scan details, including partial results. In search
and collection result menus, the folder and source are captured when the menu
opens. Later selection or pane navigation does not retarget the report. The
result menu's **Stop scan** action addresses the original request directly;
preparing another collection row cannot replace the row being stopped.
Unverified result folders do not offer a scan action, and a disconnected or
replaced original source cannot supply a new scan through another account.

Browser-local scans use noninteractive snapshots within the exact selected
root's access grant. Traversal preserves the browsing location and shared
file-handle cache, and a replaced grant invalidates pending reads. These scans
use available metadata for the entries actually returned by each snapshot;
new entries can have unknown sizes, and browser totals remain partial. Native
scans retain scoped worker reads, while remote scans use the captured provider's
reported metadata. The report controls and queued states are translated in
English, German, French, Spanish, Portuguese, Chinese, Japanese, Korean and
Arabic. Literal paths remain left-to-right inside right-to-left interfaces,
including selection details, scan issues and the largest-files list.

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
Drop preparation checks the original snapshot and source session. Review then
retains the captured endpoints and grant identities; ordinary pane navigation
does not redirect or itself revoke that reviewed operation. Virtual snapshot
verification does not request access. Native backend verification still follows
its existing scoped-access policy and may request access if permissions change.

Drop onto an inactive directory tab to review a copy into that tab's saved
folder; **Shift** alone requests move review. The active tab, directory and
selection remain in place. Verification uses the target tab's original storage
identity and a fresh folder read, including for a configured or granted root.
Search collections, archive and flat-view tabs do not advertise a directory
destination. Closing or retargeting the destination tab, replacing its grant or
changing its source before review rejects the drop. A rejected tab target does
not pass the files through to the active pane underneath it.

After destination preparation, operation review retains the captured source
groups, destination and access identities. Ordinary navigation does not change
that reviewed plan; loss of the original storage session still prevents it from
running. Tabs without a guarded destination handler do not advertise file-drop
acceptance.

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

### Historical integrated UX verification

The completed application run tested
[`ed05a8d57ce99b69cbfceeded2c1e92c7c166d45`](https://github.com/CrispStrobe/CrispCloud/commit/ed05a8d57ce99b69cbfceeded2c1e92c7c166d45).
Its application `lib/`, `test/`, shared transport/native sources, and application
manifest/lockfile are byte-identical at the final analysis/build checkpoint
[`1b15782263b8fcca36f6bffb75efd71a62ac4605`](https://github.com/CrispStrobe/CrispCloud/commit/1b15782263b8fcca36f6bffb75efd71a62ac4605).
The application inputs remained unchanged at that historical `12924a5` checkpoint.
They have changed in the later performance commits.
The CLI received formatting cleanup and the typed JSON correction described
above; its complete suite passed again after that correction. CI/source-evidence
changes are recorded separately in the engineering review. This table records that checkpoint's acceptance evidence; it does not validate
the later performance changes. Overlapping and historical batches are not added
to its totals.

| Check | Completed result | Scope and qualification |
| --- | --- | --- |
| Application workspace and SMB surfaces | **921 passed, zero failures, zero skips; 68 suites in 230.133 seconds** | Includes the dedicated workspace candidates, existing source/tab/collection regressions, upstream startup recovery, and SMB selection/profile/adapter surfaces. Actual authenticated local fixture runs cover libsmb2, Rust and Auto. |
| CLI package | **113 passed, zero failures, zero skips; all nine suites in 12.953 seconds** | Includes literal credential persistence, explicit rejection of invalid restored credentials, saved backend/default diagnostics, and all three SMB adapter selections. Analysis completed with zero errors/warnings and eight informational diagnostics. |
| Shared storage package | **23 passed, zero failures, zero skips in 12.795 seconds** | Native bridge and authenticated local SMB fixtures enabled; covers bounded I/O, resume, mutation, cancellation and security refusal. Analysis completed with zero errors/warnings and six informational diagnostics. |
| Native SMB core | **Eight passed, zero failed/ignored** | Release/locked/offline Cargo test run. Compilation completed in 63 seconds and tests in 0.03 seconds; this is Linux host evidence, not every platform or server. |
| Optional release bridge and build helper | **Passed; release build completed in 42.75 seconds** | The actual repository helper reports Cargo's emitted library under a custom target directory. That library was loaded by the shared, CLI and GUI fixture runs. Its exact identity is recorded below. |
| Committed Cargo dependency evidence | **143 resolved packages matched** | The existing checker matched locked dependency license declarations and evidence files. This does not establish final application packaging or a new legal classification. |
| Final full application analysis | **Passed in 156.3 seconds; zero errors, 78 warnings, 511 informational diagnostics** | Existing errors-only gate; no added suppressions or hidden warnings. |
| Changed-file formatting and whitespace | **139 Dart files passed; zero further changes required** | The final formatter-only corrections preserve CLI option strings, callbacks and test assertions. `git diff --check` passed. |
| Optimized JavaScript web release | **Passed; exit status 0 in 411.9 seconds** | `flutter build web --release --no-pub --no-wasm-dry-run`; version `1.1.0+12`. |
| Python release-evidence regressions and source gate | **76 passed, two existing platform skips; final source gate passed** | Verifier/preflight suites remain unchanged. The current source binding covers 128 reviewed paths, including the optional bridge, selected backend/credential flow, build inputs and macOS package-test wrapper. |
| macOS package-test wrapper flow | **Seven bounded flow checks passed on Linux** | A fake Dart process verifies copying, exact arguments, locked resolution, failure status and cleanup; termination is simulated. These checks are not a macOS execution result. |
| Hosted and interactive acceptance | **Pending for the current combined branch** | Keep hosted results tied to their exact revision. Native packaging, real servers, OS access dialogs and physical assistive-technology checks below remain separate requirements. |

The optimized Linux x86-64 bridge is 4,022,464 bytes, built from the committed
native/bridge inputs with Rust 1.99.1. The helper reported its actual path and
its SHA-256 was checked before the fixture runs:

```text
eabbe65a0bccd5ebe69a78e6b654e5d561b3d9b4530d996f9ae6aa8b59b1c5f5
```

The generated web version metadata confirms `1.1.0+12`. Its optimized
`main.dart.js` is 23,864,466 bytes with SHA-256:

```text
2e8165061b0df4caf7b9a6cfa691fa84acbd6e3d5304c3833602605a8499d8f7
```

Application checks use Flutter 3.47.8 and Dart 3.13.7. The local SMB fixture uses
Impacket 0.13.0. No private cloud account or real NAS was used for these tests.
The bridge identity above does not identify a separately supplied
`CRISP_SMB_LIBRARY` or a future packaged artifact.

The earlier 67-suite attempt at `552f608` recorded 914 passes and four failures.
Three exposed test-owned semantics handles that were disposed too late; the
fourth exposed a focused expanded row hiding Material selection/ink. The fixes
retain all rendering assertions and paint the row feedback on a local Material.
All four cases pass in the completed 68-suite run above. The first full CLI run
recorded 111 passes and one failed new fixture that incorrectly expected empty
or multiline credentials to connect. The corrected fixture verifies exact
round-trip serialization and the existing invalid-credential rejection; the
complete 113-case rerun passes. These unsuccessful attempts are not acceptance.

The [workspace CI workflow](../.github/workflows/workspace-ux.yml) retains
formatting, analysis and behavioral checks. Existing native CI gates remain in
place. The current local results do not replace pending hosted or interactive
platform acceptance.

### Historical verification

#### Workspace checkpoint `036922a`

The completed local regression runs at the earlier functional revision
`036922ad26fc971a040c16ddcf4d1046720120be` produced the results below. They predate
the current main/SMB integration and folder-size/status/tab-drop continuation.
Repository tests and temporary render checks are separate. All four repository
batches at that historical checkpoint completed successfully.

| Check | Observed result | Scope and qualification |
| --- | --- | --- |
| Workspace repository regressions | **705 passed, zero failed, zero skipped; 48 suites** | Covers navigation, breadcrumbs, path editing, grant replacement, source identity, collections, keyboard ownership, native menu mappings, columns, local snapshot access, listing recovery, ancestor drops, transfer diagnostics, accessibility and related existing workflows. |
| Temporary rendered-widget harness | **Two passed, zero failed, zero skipped** | Three captures show the actual expanded desktop queue, file diagnostics at 390 logical pixels in Arabic with 1.4 text scale, and the full details dialog. Production widgets, application fonts and deterministic transfer records were used; platform fallback fonts are supplied explicitly by the harness. |
| Full `lib/` and `test/` analysis | **Passed the existing errors-only gate; zero errors** | Exit status 0 in 92.0 seconds. The report contains 78 warnings and 500 informational diagnostics. The existing policy was retained and no analysis suppressions were introduced. |
| Changed-file formatting gate | **83 Dart files checked; zero changes required** | The formatting check covers changed Dart files at the same functional code revision. `git diff --check` also passed. |
| Optimized JavaScript web release build | **Passed; exit status 0 in 240.8 seconds** | Ran `flutter build web --release --no-pub --no-wasm-dry-run` at the verified functional revision. `CupertinoIcons.ttf` was bundled and tree-shaken from 257,628 to 1,472 bytes; the earlier missing-font warning was absent. |
| Release-evidence regression suites | **76 passed, two existing platform skips** | The evidence suite completed 41 tests with two skips; the preflight suite passed all 37. The existing `crypto_release_evidence.py --check` source gate also passed. No validators or rejection cases were weakened. |

Those four repository batches recorded 120, 252, 148 and 185 successful tests,
respectively, in a total of 175.098 seconds of test execution. Their 48 suites
include all 45 candidates in the dedicated workspace workflow and three existing
source, tab and collection suites. At that checkpoint, these completed runs
superseded its earlier focused rerun counts; an interrupted local aggregate was
not counted as acceptance. The earlier three column/shortcut render checks
remain evidence at their original revision and are not added to those totals.

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
[source and dependency review](crypto-source-review-2026-11-11.md) records that
refresh and the later integration deltas separately. At the earlier checkpoint,
the source gate and its regression suites passed after updating the reviewed
bindings. Existing declarations and distribution assertions retained their
recorded evidence. These historical results do not verify the current combined
tree or a later hosted artifact.

#### Earlier broad deterministic run

An earlier broader run recorded **7,571 passed, 39 skipped and 19 failed**. It
excluded tests tagged `benchmark`, `live`, `deploy`, `mock_server`, `integration`,
`connection_dialog` and `golden`; it was not a complete repository or native
platform acceptance run.

Sixteen failures occurred at Unix-socket `ServerSocket.bind` with errno 9 in the
FUSE IPC fixtures, before protocol work. The exact runtime cause remains
unproven. One child process could not find `dart` on PATH; that process-journal
case passed its earlier focused rerun with the executable available. The other
two failures exposed explicit-refresh ordering and compact file-row
accessibility defects, which were corrected before the historical `036922a`
regression checkpoint. The later hosted run above resolves the sixteen
Unix-socket fixture reruns; the earlier broad local run itself remains recorded
as unsuccessful. Skipped tests and unavailable platform checks are not
acceptance evidence.

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
- Inline folder measurement is limited to two concurrent scans per pane,
  20,000 processed entries and 128 levels per scan. The detailed analyzer uses
  its own bounded scan. These are traversal limits; a provider may return a
  whole directory in one response, so they do not impose a per-response network
  or allocation limit. A requested stop takes effect after an outstanding
  directory read returns.
- Measured bytes describe the known reported file sizes, which can differ from
  allocated disk space or account quota. Partial, stopped, failed or invalidated
  inline measurements do not supply exact folder sizes. Browser snapshots use
  available metadata and remain partial; unknown file sizes are retained in the
  report. Browser scanning requires an existing noninteractive snapshot
  capability and a selected-root grant. It cannot acquire access through a
  picker or recover an unavailable snapshot through an interactive listing.
- Folder-row drops apply to normal directory rows and freshly verified visible
  ancestor folders. Ancestor snapshots supply destinations only. A backend
  without suitable fresh metadata or noninteractive local snapshots cannot use
  that destination path. Source changes, ambiguous destination rows,
  self/descendant drops and same-folder moves require a new or different
  operation instead of silently changing the destination. These review
  guarantees apply to in-app drags; native/external drops retain their existing
  pane-level handling.
- Directory-tab drops require a saved directory location with an available
  original storage identity. Search, collection, archive and flat-view tabs are
  excluded, as are legacy tabs without a stored source. Fresh root verification
  remains subject to the backend's metadata and noninteractive snapshot
  capabilities. Closing or changing the target before review invalidates that
  destination; reviewed operations continue to use their captured endpoints.
- Fresh destination verification checks object/version evidence when the backend
  supplies it and opaque virtual-root tokens where supported. A backend without
  stable child-object identity cannot prove that a same-path directory is the
  identical underlying object using its name alone.
- Per-file inspection depends on the progress and saved transfer entries that a
  job exposes. Filtering and copying details do not create missing historical
  destinations or add new retry authority to an existing operation plan.
- Quota freshness depends on the provider response and explicit refresh. A
  provider that supplies no usable capacity information is shown as unavailable;
  missing fields are not assumed to be zero. Local capacity is omitted when it
  cannot be read for the current directory. Unknown selection sizes do not
  become zero-byte measurements.
- The optional Rust SMB path requires a separately available native bridge.
  Backend selection and source-level security policy do not establish final
  application packaging, real-server negotiation or device interoperability.
  libsmb2 remains the default, browser SMB sockets remain unsupported, and
  Auto cannot switch engines after authentication or transfer work fails.
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
