# Path favorites

The `*` button at the top right of either pane opens its favorites picker. The
configurable **Path favorites** command also opens the picker for the active
pane; its default shortcut is **Ctrl+Shift+B**. Ctrl+D keeps its existing download
action. Favorites use the same saved-location store as Commander workspaces,
the drive bar, and the bookmark controls.

## Find and open a location

Search matches names, paths, source labels, and group names without regard to
case. Multiple words must all match. The group selector narrows the results to
one group or to ungrouped favorites. Press Enter when a single available match
remains, or select a row to open it in the pane that owns the picker.

Each row shows its original source and path. An unavailable source stays visible
with opening disabled. Connecting a different account with the same provider or
folder name does not grant access to that favorite. A saved file-list favorite
also remains unavailable if its collection has not been imported separately.

Opening uses the existing saved-location resolver and a captured pane session.
If the pane navigates or changes sources while the picker is open, the selection
does not redirect that changed pane. A favorite is never opened as a consequence
of importing it.

## Organize favorites

Choose **Add current path…** to save the current folder, then edit its name,
absolute path, and optional group. Choose an existing group from the group
button or type a new group name. Archive interiors and unsaved search results
cannot become ordinary directory favorites.

**Edit path favorites…** opens the shared editor. It supports searching, group
filtering, opening available locations, editing, removing, and moving favorites
up or down within their group. Both pane pickers reflect these changes.

To rename a whole group, select it in the editor and use **Rename or remove
group**. Renaming into an existing group combines the groups. An empty name
removes the group while retaining its favorites. Group names have a maximum of
80 characters and cannot contain control characters.

Changing a name, group, or path preserves the original storage reference.
Older favorites with no saved source still require the explicit **Bind original
source…** action. Imported favorites that already identify an account are never
silently bound to the current account.

## Export and import

The editor provides **Export favorites…** and **Import favorites…**. The text
exchange dialog can load or save a JSON file, or copy and paste text. Copying to
the clipboard and saving a file require their respective explicit buttons.

An export contains favorite names, paths, groups, pane preferences, and source
identifiers. Storage identifiers contain a provider, account/namespace identity,
root, and persistence flag. The export does not serialize storage clients,
passwords, access tokens, or connection credentials. Paths and names can still
describe private locations, so export only the information you intend to share.

Import has two steps:

1. Load or paste a file and select **Preview import**. The whole document is
   validated before any favorites change.
2. Review the new favorites, duplicate count, and unavailable-source count, then
   select **Merge favorites**. Cancel leaves the store unchanged.

Merge adds new destinations and keeps existing names, groups, and source
references. It deduplicates both repeated rows in the file and rows already in
the store. Destination identity includes the original account and namespace
root plus the normalized path; a pane preference does not create a second
destination. Paths remain stored as originally written. The merge rechecks
duplicates if another window changes the store while the preview is open.

Unknown accounts remain saved and unavailable until their matching source is
connected. Local references retain their installation identity, so importing a
local favorite on another device does not grant that device access to the
original location. Saved file lists require their separate collection data.

The Commander workspace importer uses this same preview and merge step.

## Exchange format and limits

Exports use `format: "crispcloud.bookmarks"` and `version: 3`. The `bookmarks`
array contains the existing favorite fields plus an optional `group` string.
Version 2 exports remain readable; absent groups are treated as ungrouped.
Existing on-device favorites are migrated without changing their source.

Imports accept at most 2 MiB of UTF-8 JSON and 10,000 rows. Names remain limited
to 160 characters and absolute paths to 8,192 characters. Unknown fields,
invalid field types, unsupported format versions, invalid source references,
relative paths, and invalid groups reject the entire import. Error messages do
not echo imported JSON. A damaged existing preferences store is not overwritten
by an import.

## Regression coverage

Provider tests cover group persistence, group-only ordering, unchanged account
references, strict validation, version compatibility, source/root-aware
deduplication, stale previews, and retention of existing rows. Widget tests cover
both pane targets, stale pane sessions, grouped search and Enter navigation,
group rename/removal, preview cancellation, unknown-account visibility,
explicit clipboard export, and continued archive and legacy-bookmark behavior.
All picker, group, and exchange controls are localized in the app's nine
supported languages.
