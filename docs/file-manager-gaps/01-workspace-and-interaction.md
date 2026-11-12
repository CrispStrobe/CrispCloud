# Workspace and interaction

[Gap register and closure rules](README.md). Baseline: `28b7b9c`.

Every item below has a separate completion boundary. A prototype, reader-only
codec or passing loopback test does not imply the broader platform or write
capability. Required live/device checks remain visible after code implementation.

## G01

### Source-bound incoming drops

**Status:** Implemented / native and browser acceptance pending. **Dependencies:** None for the implemented copy workflow.

**Scope:** Capture the actual destination, then route native and browser drops through reviewed copy operations.

**Implementation:** Replace pane-side routing and direct writes with an immutable destination capture and a read-only external source adapter. Native paths hold only their own scoped access; browser inputs retain their original handles. Reuse the copy planner, conflict review and cancellation path.

**Boundary:** Incoming files and native folder trees are covered by the supported source adapter. Opaque browser directory payloads must be rejected explicitly until a real hierarchy/handle can be captured. Temporary sources cannot be scheduled or advertised as recoverable after their lifetime ends.

**Acceptance:**

- A local folder in either visual pane receives the copy locally; a selected secondary remote account receives it in that exact account.
- Changing tab, account, directory, listing or navigation intent during async inspection rejects the old drop before review or writes.
- Existing destinations require normal conflict decisions; cancellation and unsupported input make no destination writes and release scoped access.

**Starting points:** lib/widgets/file_panel.dart; lib/services/folder_drop_service.dart; existing operation backend/planner.

**Delivered:** [Incoming files and folders](../external-drops.md) documents the
captured destination, read-only native/browser sources, normal copy review,
conflicts and foreground lifetime. Either visual pane can receive a drop at its
actual local folder or selected remote account. Supported directory manifests
retain their hierarchy; native scoped access is released on completion/close.
No dependency was added.

**Observed validation:** The final focused run passed 118 tests across six
drop/operation suites and the external-terminal service regression suite. Tests
exercise actual pane callbacks, copies to secondary remote and opposite-pane
local destinations, case-sensitive paths, strict browser names, mutation races,
bounded streaming, unchanged destination bytes on cancellation and source release.
Focused static analysis is clean. A discovered mutable-list contract mismatch
was corrected by returning an independent directory snapshot to the planner.

**Remaining acceptance:** Real operating-system drag sessions, signed macOS
security scopes and actual browser file/directory handles require target-runtime
checks under G50/G51. Native drag-out remains a separate G06 gap.

## G02

### Direct Quick Open actions

**Status:** Closed for the direct saved-item workflow. **Dependencies:** Existing source/device availability.

**Scope:** Search and invoke saved paths, sources, devices, workspaces and rename presets with original-source validation.

**Implementation:** Create a stable-ID action catalog for saved paths/collections, connected sources, local devices, workspaces and rename presets. Keep category, account/path and unavailable reasons searchable. Reuse normal pane navigation and reviewed rename/workspace flows.

**Boundary:** Only saved or currently available targets are indexed. Discovery of new network services is G30. Rename presets seed a review, never execute a batch automatically. A saved layout must not overwrite newer user navigation after an await.

**Acceptance:**

- Favorites resolve their saved source identity, not the currently selected account or the pane label.
- Stale catalog entries, disconnected sessions, revoked grants and deleted presets become unavailable without fallback to another target.
- Search, keyboard activation and narrow/localized layouts work; a preset opens a populated rename review and a workspace preserves independent pane intent.

**Starting points:** lib/widgets/command_palette.dart; bookmarks/source/workspace providers; RenamePresetStore.

**Delivered:** [Quick Open](../quick-open.md) includes searchable favorites,
connected sources, local devices, workspaces and rename presets. Stable item IDs
retain the highlighted target across updates. Captured-source and noninteractive
restoration guards run before and after asynchronous work; stale or failed tab
loads stop subsequent workspace changes. Presets open reviewed rename previews.
No dependency was added.

**Observed validation:** All 193 tests passed across nine Quick Open,
workspace/rename suites and three file-conversion suites. Coverage includes
same-label accounts, replaced sessions, locked tabs without access pickers,
collection-mark saves, explicit load failures, newer navigation, keyboard
activation, localized layouts and preset preview without writes. Focused
analysis has no errors or warnings. New network discovery remains G30.

## G03

### Conflict previews and details

**Status:** Closed for the bounded preview scope below. **Dependencies:** None.

**Scope:** Show bounded image previews and selected safe metadata for both captured conflict candidates.

**Implementation:** Read each captured conflict candidate through its original backend. Re-stat and compare available identity/version evidence around bounded image decoding. Present thumbnail state and an allowlist of useful metadata beside the existing decision controls.

**Boundary:** The review stays write-free. Reject oversized bytes, excessive dimensions, corrupt data and changed sources before displaying an apparently current preview. Never render arbitrary provider metadata, credentials or untrusted thumbnail URLs.

**Acceptance:**

- Both sides remain bound to their original accounts and paths when the visible panes change.
- Byte/dimension limits, corruption, missing files, disconnects, cancellation and late decodes produce explicit states and cannot replace a newer preview.
- Decision buttons, apply-to-all behavior and keyboard/narrow layouts retain their existing semantics.

**Starting points:** lib/widgets/file_operation_conflict_dialog.dart; FileOperationConflict and captured backends.

**Delivered:** [Conflict review](../conflict-review.md) documents paired image
previews, safe metadata, captured-session checks and explicit unavailable states.
Automatic reads require a bounded-download backend. Inputs are capped at 4 MiB,
16 million pixels and an 8192-pixel edge; thumbnail output is capped at 384 pixels
and 1 MiB, with a 15-second deadline. No dependency was added.

**Observed validation:** 140 tests passed across the preview service, conflict
dialog, operation dialog and operation service suites on the pinned Flutter
toolchain. Coverage includes real decoding, cancellation, source replacement,
metadata redaction, explicit decisions and narrow enlarged German/Arabic layouts.
Decoder-format availability remains a platform capability; this increment does
not claim additional image formats or live-provider certification.

## G04

### Configurable main menus

**Status:** Implemented / target-runtime acceptance pending. **Dependencies:** None for saved configuration and application command routing.

**Scope:** Persist command-based menu layouts, user commands, reset and import/export.

**Implementation:** Separate stable command IDs from labels and keyboard bindings. Persist a versioned menu tree with separators, submenus, built-in commands and reviewed user-command entries. Add preview, reset, import/export and a command picker.

**Boundary:** Validate depth, size, duplicate IDs and unsupported commands. Preserve mandatory access to settings, recovery and reset. Platform system-menu requirements remain enforced; unknown imported IDs are disabled rather than executed.

**Acceptance:**

- Saved layouts survive restart and locale changes without changing command identity.
- Invalid/cyclic/deep imports cannot replace the last valid menu; reset restores a usable default.
- User commands receive captured file/path parameters and open their normal execution review; menu and shortcut enablement agree.

**Starting points:** lib/screens/file_browser_screen.dart; keyboard_shortcut_service.dart; custom_toolbar_command_service.dart.

**Delivered:** [Main menus](../main-menus.md) documents saved command-based
menu trees, submenus, separators, a command picker, reorder/move/rename,
inactive preview, reset and bounded JSON import/export. Native macOS browser
menus and in-app menus share the same configuration. Settings, recovery and
reset remain reachable outside the editable tree. Saved external commands are
references that open the existing captured-context execution review. No
dependency was added.

**Observed validation:** 96 tests passed across 11 suites, including schema and
persistence failures, last-valid recovery, source-bound user-command callbacks,
real-screen registry resolution, native editor/terminal ownership, keyboard
bindings, legacy translated labels, panel headers and narrow enlarged German
and Arabic layouts. The existing system-SQLite test wrapper and runtime probe
were used after the environment's native-asset download failed its checksum;
the release dependency configuration was restored unchanged.

**Remaining acceptance:** Actual operating-system menu presentation and native
keyboard dispatch remain target-runtime checks under G50/G51. Flutter's
platform-menu model passing tests does not establish signed application behavior.

## G05

### Gathering stack

**Status:** Scoped. **Dependencies:** G01; existing collections.

**Scope:** Gather source-bound references from different folders and transfer them through one reviewed plan.

**Implementation:** Build a gathering surface backed by existing source-bound collections. Add/remove/reorder references from independent locations, display missing/offline states and prepare one reviewed destination copy/move plan.

**Boundary:** References do not imply ownership or a copied snapshot. Keep entries until their successful transfer outcome is known. Deduplicate by source/object/path identity, not by filename alone.

**Acceptance:**

- Same-named files from different accounts remain distinct and expose collisions during review.
- Disconnects, renamed/replaced files and revoked grants are shown before execution; a canceled plan retains stack entries.
- Partial completion removes only confirmed successes and keeps failed or untouched references available.

**Starting points:** FileCollectionService; panel collection origins; FileOperationService.

## G06

### Native outgoing drag

**Status:** Scoped. **Dependencies:** G01; native bridge.

**Scope:** Export verified files through native drag sessions with explicit staging lifetime.

**Implementation:** Implement platform drag-session adapters for captured native files and reviewed staged remote files. Keep staged copies and access scopes alive through native completion/cancellation, with explicit copy/move semantics.

**Boundary:** Start with local desktop drag-out, then remote promised-file support where the OS permits it. Browser drag/download constraints require their own capability statement. Do not delete originals merely because an external target accepted a drag.

**Acceptance:**

- Drag to the desktop and another native application works for files and supported folder trees on each claimed OS.
- Cancel, receiver failure, disconnect and source replacement leave original data intact and clean temporary staging.
- Large/remote drags report preparation and enforce cancellation/space limits; signed sandbox behavior is tested.

**Starting points:** New native drag bridge; captured source services; G50 native acceptance.

## G07

### General file tags

**Status:** Scoped. **Dependencies:** Stable file identity; native metadata bridge.

**Scope:** Add portable file tagging, search/selection integration and supported native metadata roundtrips.

**Implementation:** Define portable tag identities and source-bound item references, then integrate tag editing, filtering, quick selection and search. Add explicit adapters for supported native tag metadata and preserve unsupported native fields.

**Boundary:** Distinguish app catalog tags from native filesystem tags in capabilities and UI. A path reused by a different object must not inherit old tags silently. Native write permission and cloud metadata support vary by backend.

**Acceptance:**

- Tags roundtrip through persistence and supported native metadata without erasing other metadata.
- Rename/move/replacement/offline cases retain or invalidate tag references according to verified object identity.
- Search/selection honors add/exclude semantics and source boundaries across local and remote items.

**Starting points:** Existing image annotations, collections and search criteria; new general tag adapters.

## G08

### Favorite synchronization

**Status:** Scoped. **Dependencies:** Versioned favorites; selected sync backend.

**Scope:** Synchronize portable favorites with encrypted storage and deterministic conflict handling.

**Implementation:** Version portable favorite records with stable IDs, deletion tombstones and merge metadata. Synchronize via an explicitly chosen supported backend using verified writes and a reviewed conflict policy; protect sensitive paths/settings appropriately.

**Boundary:** Never sync credentials, active sessions or local access-grant tokens. Restored favorites may remain unbound until their account/device mapping is explicitly resolved. Automatic account/container selection is not implied.

**Acceptance:**

- Two replicas converge after independent edits/deletes without resurrecting deleted entries or silently losing conflicting edits.
- Interrupted uploads, rollback, malformed snapshots and unavailable keys preserve the last usable local/remote versions.
- Imported references require the original storage mapping; synchronization can be paused and conflicts inspected.

**Starting points:** bookmarks_provider.dart; existing secure storage and provider operation backends.

## G09

### Command entry and keyboard conventions

**Status:** Scoped. **Dependencies:** G04; existing terminal/custom commands.

**Scope:** Complete reviewed program launch and file/path insertion shortcuts across supported desktop targets.

**Implementation:** Add explicit command-entry actions for inserting the selected filename or full path and for running configured programs with arguments. Connect user commands to the configurable menu and shortcut editor using stable actions.

**Boundary:** Preserve text-field/editor/terminal input ownership. Parameter insertion must quote for the selected execution model and must never turn a filename into shell syntax. Platform key differences are visible and customizable.

**Acceptance:**

- Filename/path insertion handles spaces, quotes, Unicode and shell metacharacters as data.
- Selected file and directory parameters come from the captured active source; remote paths are not passed as local files without reviewed staging.
- Default and customized shortcuts work without stealing input from editors or the terminal; launch requires the existing command review.

**Starting points:** keyboard_shortcut_service.dart; keyboard_shortcuts.dart; custom_toolbar_command_service.dart.
