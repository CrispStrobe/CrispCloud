# File workspace UX

This page describes the current file-browser controls and interaction rules.
It is not a historical implementation log; the detailed checkpoint record is in
the [workspace UX archive](workspace-ux-details.md).

## Selection

| Input | Result |
| --- | --- |
| Plain click | Move cursor, keep existing marks |
| Shift-click | Mark visible range from the previous cursor anchor |
| Cmd-click / Ctrl-click | Toggle one item |
| Shift+arrow | Toggle the departed row, including removing marks |
| `Ctrl+A` | Select all visible rows |
| Numpad `+` / `-` | Select/deselect by pattern |
| `Shift+Numpad +` / `-` | Select/deselect same extension |

Marks apply to the visible filtered scope. File operations use marks; `F3` and
`F4` use the focused file. Selection memory is per tab and is revalidated
against the original source before restoration.

## Panes and layouts

- Two independent panes, each with its own source, path, selection and tabs.
- Tree sidebar, brief/details/thumbnail/gallery views and density controls are
  independent.
- `Tab` changes the active pane when no text field or editor owns the keyboard.
- Breadcrumbs, Back/Forward history and Go to Folder navigate within the pane.
- `..` from an archive restores the archive cursor, marks and scroll position in
  its containing folder.
- Synchronized browsing maps relative navigation between two chosen roots; it
  stops when either side becomes unavailable.

## Find and filtering

- Filter narrows the current list.
- Find supports jump, mark and filter modes.
- Up/Down traverse matching files.
- Jump/mark modes wrap; filter mode stops at the visible ends.
- A modifier is captured on pointer-down, so releasing Shift before a delayed
  click does not change the action.

## Drag and drop

In-app drops capture the original source and destination before review. Folder
and pane drops require a visible transfer preview when work can be recovered.

On native desktops, dragging local files outside the window exports file URLs
and offers the receiver a copy. The sandbox read grant stays held until the
receiver accepts or cancels.

Cloud and archive members must be saved locally before external drag-out.
External drag-out is not implemented on Android, iOS or the browser.

## File operations

- Copy/move/rename actions capture source identity, not just the visible path.
- Conflicts and unsupported metadata are reviewed before execution.
- Search results, archive members and saved collections retain their origin.
- Gallery operations apply to the visible order; hidden selections are removed
  before batch actions.
- Directory history and tab restoration preserve source identity.

## Columns and view profiles

Saved view profiles control visible columns, sorting, widths, density and file
list font. Hidden files can be toggled independently of permissions. A saved
tree mode cannot hide a selected gallery or replace the current source.

## Product boundaries

- The browser cannot use native mounts or external drag-out.
- Native external drag behavior requires a platform build; a Dart gesture test
  is not OS acceptance.
- Archive and search contexts are view/export-only where mutation routing is
  not verified.
- Source-account changes invalidate stale viewers and selections.
- Accessibility, narrow windows and larger text remain required checks for new
  controls.

## Verification

Use focused provider/widget tests for selection and routing, plus the native
platform build for OS drag and file grants. Historical test counts and exact
checkpoints belong in the [archive](workspace-ux-details.md), not in
the current control reference.

## Related

- [User guide](USER_GUIDE.md)
- [Commander operations](commander-file-operations.md)
- [Transfer queue](transfer-queue.md)
- [Gallery](image-gallery.md)
