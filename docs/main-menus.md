# Main menus

Choose **Customize menus** in **Menu controls** or **More actions** to edit the file browser's menus. On macOS, the same command is in the application menu. The saved layout supplies the native browser menu bar on macOS and the in-app browser menus on other platforms.

The editor supports submenu groups, command entries and separators. Select a group to edit its contents, search for an available command, reorder entries, move them to another group, rename groups, or remove entries. **Preview** opens the draft menu with command execution disabled. **Save** applies and persists the draft; **Cancel** leaves the current layout unchanged. **Reset menus** loads the default layout into the editor for review and requires **Save** to apply it.

## Commands and context

Built-in commands have stable identifiers separate from their translated labels. Their bindings use the browser's existing action dispatcher and configured keyboard shortcuts. Changing the display language therefore preserves command identity. Default group titles follow the selected language; a group renamed by the user retains that chosen title.

Saved external commands can be added by reference. Selecting one opens its normal execution review; opening, importing or previewing a menu never starts a process. These entries require a supported desktop environment and an already reviewed executable definition. A menu entry cannot create an executable definition or grant access to a different source.

A user-command binding captures the active pane's actual local source, directory, selected paths, target directory, tab session, and navigation revision. It checks those details again before opening the review. Replacing a saved command, changing the selection, navigating, changing the active pane or target, or replacing the source's grant makes the captured callback unavailable. The review then owns its original captured paths. Browser callbacks also defer to the current modal dialog or editor's input ownership.

An unknown command identifier remains visible as an unavailable entry. It is preserved in the saved layout, so a layout can be inspected even when an extension or saved user command is missing. Only the running application's command registry can supply its callback.

## Controls that remain available

Settings, transfer recovery, trash recovery, rename recovery, split/combine recovery, menu customization and reset are supplied by the application outside the editable tree. Removing every custom group cannot remove these controls. On macOS they remain in the application menu while a document editor or terminal supplies its own menus. Document editor and terminal menus retain their existing command and shortcut ownership.

At narrow widths the browser presents a compact **Menus** control. Wide menus and the toolbar can scroll horizontally, while **More actions** stays outside the toolbar's scrolling region. The menu editor and preview scroll vertically when translated text or enlarged text needs more space.

## Import, export and recovery

**Export** presents the draft's versioned JSON for copying. **Import** validates pasted JSON and replaces only the editor draft; the running menus change after **Save**. The format stores menu structure and command identifiers, including `user:<saved-command-id>` references. It contains no executable paths, arguments or process definitions. A referenced user command must already exist on the receiving installation.

Version 1 accepts these limits:

| Field | Limit |
| --- | --- |
| Encoded JSON | 256 KiB of UTF-8 |
| All entries, including groups and separators | 512 |
| Top-level groups | 12 |
| Entry depth | 0 through 5, with top-level groups at 0 |
| Custom group title | 80 characters |
| Entry identifier | 96 characters |
| Command identifier | 256 characters |

The importer rejects unsupported schema versions or fields, duplicate entry identifiers, cyclic structures, malformed identifiers, control characters, invalid node shapes and exceeded limits. Unknown command identifiers are allowed as disabled references. Top-level entries must be groups; groups have either a custom title or a recognized translated title key.

Saving is serialized. The previous validated layout is written as a backup before the next layout becomes active. Failed saves leave the previous live layout in place and report the error in the editor. On startup a corrupt active record falls back to the validated backup or usable defaults. Opening the application does not overwrite either stored record during that recovery, and the editor reports that recovery occurred.

## Validation boundary

Regression coverage includes schema limits, duplicate identities and cycles, immutable drafts, persistence across store instances, serialized writes, backup recovery, failed saves, shared native/in-app command resolution, disabled unknown commands, preview without execution, cancellation, source-bound user-command callbacks, and narrow enlarged German and Arabic layouts. Real-screen checks cover the built-in registry and preservation of native editor and terminal ownership.

Native menu dispatch is exercised through Flutter's platform-menu model in tests. Actual system menu presentation and keyboard dispatch still need the target-runtime checks recorded in G50/G51. No dependency was added for this feature.

The final focused gate passed 96 tests across 11 suites, including the real file
browser screen, existing keyboard/toolbar/navigation behavior and the SQLite
runtime probe. The repository's opt-in system-SQLite test wrapper was used for
this Linux run; release dependency configuration is unchanged.
