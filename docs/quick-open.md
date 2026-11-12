# Quick Open

Open the command palette with its configured shortcut (Ctrl+Shift+P by default).
Search by a command or saved-item name, path, source label, account label, or
category. Arrow keys move the highlighted row; Enter opens an enabled result.

The palette includes direct entries for:

- Saved favorites, including paths on their original local or remote storage
  and saved file lists.
- Connected storage sources, distinguished by their source/account identity.
- Local devices and locations already enumerated by the drive bar.
- Saved workspaces containing both panes' tabs and layout.
- Saved rename presets, applied to the selected files or cursor item in the
  existing rename preview.

Each result shows its category and location/account or selection summary.
Unavailable accounts, unbound older favorites, missing file lists, and unsuitable
rename selections remain visible with an explanation. Load errors in saved
workspaces or rename presets do not hide independently readable sections.

## Target identity and asynchronous actions

Display names are searchable labels. They are never used to choose a storage
account. A favorite retains its saved storage reference, and a connected-source
entry also verifies its original live connection. An account with the same
provider label cannot substitute for a disconnected target.

Keyboard selection follows a stable item ID. If the highlighted target is
removed or disconnected while the palette is open, its row remains disabled
with an explanation. Enter does not silently choose another same-named account.

Actions recheck the captured pane and target after asynchronous reads. A newer
navigation or a newer Quick Open action supersedes pending work. Local path and
device actions use existing directory access. Direct navigation preserves its
current view on missing or inaccessible paths; an appended tab reports the load
failure and keeps the original tab intact. Grant folder access through Open Local Folder
when needed. This feature does not add device discovery or provider login flows.

## Workspaces

A workspace action verifies the saved account references and file-list
availability before opening either pane. Its tabs are appended, preserving
existing tabs. Opening the first pane does not authorize overwriting a newer
navigation in the second pane. The saved layout is applied only while both
appended views still belong to the action. If navigation supersedes a partially
loaded workspace, already appended tabs remain available and later pane/layout
changes stop.

Restoration passes the original live source through collection-mark saves and
tab loads. It does not resolve a replacement connection after an asynchronous
wait. Local tabs use existing access only, including locked favorites and saved
workspace tabs. A failed or cancelled active-tab load is an explicit failure;
later panes and the workspace layout are not applied.

## Rename presets

A preset action captures the selected originals and source, reloads the saved
rules, and opens the existing rename preview. Rules, proposed names, validation
errors, and the explicit execution controls remain available for review. Opening
the preset performs no file mutations. Subsequent pane/account changes do not
retarget the preview to a different account.

## Verification

Focused coverage is in `test/quick_open_service_test.dart`,
`test/quick_open_test.dart`, and `test/widget/quick_open_palette_test.dart`.
`test/quick_open_restore_test.dart` covers noninteractive locked/workspace tabs,
load errors, and account replacement during tab restoration and collection-mark
persistence.
Tests exercise duplicate names, account replacement and disconnection, disabled
legacy favorites, unavailable file lists, removed devices, pending navigation,
workspace append/layout behavior and stale loads, keyboard target preservation,
and preset review without writes. Existing palette-localization and rename
dialog suites cover the shared UI paths.

The final focused run passed all 193 tests across the nine Quick Open,
workspace/rename suites and three file-conversion suites. Focused static
analysis has no errors or warnings. Test counts overlap with the other feature
checkpoints and should not be summed.
