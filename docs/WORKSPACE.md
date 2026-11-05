# Commander workspaces

## Tabs and protected locations

The tab bar stays available with one tab. Add a tab with **+**, drag its handle to reorder it, or open its context menu with a secondary click or a touch long press. **Duplicate this tab** duplicates the tab you clicked, including its original storage account and saved collection. A duplicate starts unlocked. Custom titles survive folder navigation; **Use folder name** restores the automatic title.

Pinning prevents accidental closure. Location locks additionally control navigation:

| Mode | Behavior |
| --- | --- |
| Normal | Navigate and close normally. |
| Lock this location | Folder navigation keeps the current location and explains how to unlock it. Selecting a different storage source opens a separate tab. |
| Return to locked location on tab change | Browse within the tab; leaving it or restoring it after a restart returns to its original path and account. |
| Open other locations in new tabs | Folder navigation opens a new neighboring tab while retaining the original location. |

A protected tab can still be closed through its explicit context-menu confirmation. Closing other tabs preserves protected tabs. Duplicate cleanup also preserves protected tabs and compares complete storage identities, so identically named paths on different accounts remain separate.

Feeding search results into a locked folder opens a separate tab. When a result list uses **Open other locations in new tabs**, opening a containing folder preserves the original list. Save a transient result list as a collection before applying the return-to-location lock; the saved collection provides a stable place to return to.

Saved tab configurations retain full storage references and collection IDs. Unavailable accounts remain visibly unavailable; they are never replaced by whichever account happens to be active. Imported locations are validated before existing tabs are removed, and protected tabs are retained during replacement unless explicitly included.

The lock modes follow the behaviors described in the [Double Commander tab documentation](https://doublecmd.github.io/doc/en/help.html). CrispCloud binds each location to its storage account as well as its path.

## Saved views and workspace storage

Each tab retains its display mode, visible column order and widths, primary and secondary sort, hidden-file setting and manual name filter. Temporary type-ahead text is not saved. Switching or closing tabs restores the destination tab's settings. Compact file rows and their headers share the same responsive column calculation: narrower panes keep the name readable and show the remaining columns when space is available.

Views support size, modification date, extension, original path, storage source, collection status and supplied metadata fields. Metadata columns can address a direct key or a dotted nested key and sort numeric values numerically. They do not execute an external metadata plugin or download file contents merely to display a column.

Named groups capture both panes and their layout; paired bookmarks capture the two active locations. Both locations in a pair are checked against their original accounts before navigation begins. If a provider disconnects between opening the two panes, the error identifies that interruption; navigation is not a filesystem transaction.

The versioned workspace settings document is written only after complete validation and a successful persistence acknowledgment. Import merges entries by stable saved IDs, validates the entire document first, and is limited to 2 MiB. Credentials, client objects and file contents are excluded. Foreign local installations remain foreign; an imported local path does not grant access on another machine. File-list tabs refer to separately persisted collections, which must also be available when transferring settings between installations.
