# Commander file operations

CrispCloud supports a connected workflow: search or import a file list, refine
its selection, preview a multi-rename or transfer, and inspect per-item results.
Commands operate on the actual storage source and original paths, independent
of whether that source is shown in the left or right panel.

## Entry points

| Action | Keyboard | Other entry points |
| --- | --- | --- |
| Multi-Rename | Ctrl+M | More actions, Edit menu, command palette, selection context menu |
| Select by wildcard or regex | Numpad + | More actions, Edit menu, command palette, file-list toolbar |
| Deselect by wildcard or regex | Numpad - | Edit menu, command palette |
| Invert selection | Numpad * | Edit menu |
| Copy with options | F5 / Ctrl+C | More actions, context menu, selection bar, command palette |
| Move with options | F6 / Ctrl+X | More actions, context menu, selection bar, command palette |
| Import a file list | Ctrl+Shift+L | More actions, Edit menu, command palette, file-list toolbar |
| Export a file list | — | More actions, Edit menu, command palette, file-list toolbar |

These shortcuts apply while the file browser has focus. **More actions** is the
three-dot toolbar menu; the native **Edit** menu is available on macOS. The
file-list toolbar appears after feeding search results or importing a list;
its three-dot menu is **File list actions**. The normal multi-selection context
menu labels Multi-Rename as **Batch Rename**.

The keyboard handler also accepts Meta in place of Ctrl on macOS. Shift+F5
opens copy options. For a same-folder file duplicate, choose that folder and
**Keep both**.

## Multi-rename

Select items, open Multi-Rename, and compose a **Name mask** and **Extension
mask**. Their defaults, `[N]` and `[E]`, preserve the existing filename. Dotfiles
and folder names are treated as names; folders do not acquire file extensions.

| Mask | Meaning | Example |
| --- | --- | --- |
| `[N]` | Original name without its last extension | `report` from `report.pdf` |
| `[E]` | Original extension without the dot | `pdf` |
| `[C]` | Counter using the selected width | `001` |
| `[C:4]` | Counter with an explicit width | `0001` |
| `[P]` | Original parent folder name | `Invoices` |
| `[N1-4]` | Inclusive, one-based name slice | First four Unicode code points |
| `[N3-]` | Name from position three onward | Removes the first two code points |
| `[N-4--1]` | Positions counted from the end | Last four code points |
| `[E1-2]` | Extension slice | First two extension code points |
| `[Y]`, `[M]`, `[D]` | Modified year, month, day | `[Y]-[M]-[D]` |
| `[h]`, `[m]`, `[s]` | Modified hour, minute, second | `[h][m][s]` |
| `[[`, `]]` | Literal opening/closing brackets | `[[draft]]` |

For example, name mask `[P]_[N]_[C:3]` with extension mask `[E]` can produce
`Invoices_report_001.pdf`. Counter start, signed step, and padding are
configurable. The displayed ordering determines counter allocation and is
frozen during execution.

**Advanced rename rules** selects the saved mask dialect: CrispCloud, Total
Commander, or Double Commander. The supported TC/DC range forms include
`[N1-5]`, `[N1:5]`, and `[N1,5]` in their respective dialects. Date controls
choose the captured modified/created/accessed/photo time, the time zone, and a
minute offset. TC `[T2]` uses the time the dialog opened and `[T3]` uses the last
options-change time; rebuilding the preview does not advance either clock.
`[meta:artist]` reads supplied metadata and `[V:Project]` uses a variable such as
`Project=Holiday`. Missing metadata is an explicit error. This is a documented
mask subset; it does not load third-party Commander content plugins.

Find/replace can apply to the name, extension, or full filename. Literal and
regular-expression matching support case sensitivity and first/all matches.
Regex replacements expand numbered captures such as `$1`, named captures such
as `${name}`, and `$$` for a literal dollar sign. Separate case controls support
unchanged, lower, upper, title, and sentence case. Named presets persist the
settings between sessions.

Use **Add transformation** to apply another mask/replacement/case step to the
preceding proposed names without renaming anything in between. Earlier steps
can be removed individually and the complete pipeline can be saved as a preset.
**Multiple literal pairs** applies `red|blue` → `blue|green` simultaneously,
without cascading replacements.

Each preview row can be edited, moved earlier/later, or excluded from the batch.
Excluded rows remain untouched and can be restored. **Edit / import names**
accepts pasted text or a UTF-8 `.txt`/`.lst` file, exactly one complete name per
included row in preview order. Manual names stay attached to the original path
when rows are reordered. **Clear manual names** returns to the rules and enables
adding further transformation steps. **Check existing names** reads the original
parent folders; **Number colliding targets** allocates numbered alternatives in
the preview, accounting for both selected and existing names.

The full preview includes original paths, proposed names, and validation
messages. A batch is blocked for invalid names, duplicate destinations in one
parent, source/target overlaps, or conflicting selected folders and descendants.
Execution checks all sources and destinations before the first rename, then
checks again before each item. An occupied destination is never intentionally
overwritten. Cancel and stop/continue-on-error report completed, unchanged,
failed, and unattempted rows separately.

Successful renames update file lists at their original paths. After closing the
tool, **Edit → Undo** restores the completed batch as one history action, including
batches larger than the history's 50-action limit. Undo checks the entire reverse
plan before changing files, retains the original storage/account guard, and
refuses occupied original names. A failed partial undo retains only the remaining
rows for retry. History is session-only. The batch is not a transaction:
cancellation or a later failure retains successful earlier renames. Cycles and
occupied case-only renames require an unused intermediate name; parent/child
renames require separate batches. Date masks require the selected timestamp
rather than silently substituting today.

## Pattern selection

The **Select by pattern** dialog changes selection marks without filtering out
panel rows. Choose **Wildcards** or **Regular expression**, enter a pattern, and
choose an **Action**:

- **Add matches to selection** marks matching items.
- **Remove matches from selection** clears matching marks.
- **Invert matching marks** toggles matching items.
- **Replace selection with matches** clears the previous selection and marks
  only matches.

The first three actions preserve marks on nonmatching items. **Include** limits
matching to **Files and folders**, **Files only**, or **Folders only**. Enable
**Case sensitive** or **Match full original paths** when needed; otherwise the
pattern matches filenames without regard to case. The dialog previews the
matching count before **Apply**. Invalid expressions cannot be applied and
leave the existing selection unchanged.

Wildcard rules:

- `*` matches any number of characters; `?` matches one.
- `;` separates alternatives: `*.jpg;*.png`.
- `|` introduces excluded masks: `*.jpg;*.png|thumb*;*_small.*`.
- An exclusions-only expression such as `|*.tmp` includes everything else.
- `*.*` includes extensionless names, following Commander conventions.
- Wildcards match the entire name/path. Regex matches anywhere unless anchored;
  for example `^IMG_[0-9]{4}\.(jpg|png)$` matches a whole filename.

Selection applies to visible entries; parent-directory rows are never selected.
The same matcher filters files during copy/move while selected folders are
traversed according to the recursion option.

The pattern field's history button recalls the last 20 successfully applied
patterns, including regex/wildcard mode, case, path matching, and item type.
History is shared by the panes and survives restart; recalling a pattern keeps
the current select/deselect action. **Remember selection** and **Restore
selection** keep marks for the current tab/session. Restoration uses current,
visible, verified original paths and omits missing files or changed accounts.
Select all, invert, and Shift-click use the visible list; existing marks on
nonvisible rows are preserved unless the selected action replaces all marks.

## Search results and reusable file lists

Use **Feed all to panel** in search results to keep hits as a virtual file list
in the source panel. Mark result checkboxes to change the button to **Feed
selected to panel** and retain only those hits. Each row retains its original
full path and the storage/account that returned it. Same-named files from
different directories remain distinct. The result dialog also offers **Copy
paths** and an **Open containing folder** button on each result.

A list panel supports pattern selection, Multi-Rename, copy/move options,
original-path display, and opening the containing folder. **Remove from list
(keep files)** only removes rows; **Delete files…** is a separate command that
operates on the actual stored source. Use the toolbar's **Return to folder**
close button to leave the list. Lists survive refresh and tab switches within
the current app session. Completed operations update matching list tabs even
while another tab or storage source is active. They are not silently reloaded
as unrelated directory contents.

Choose **Import file list** to open the **Import paths** view. Use **Open .txt /
.lst**, **Paste paths**, or type paths into the text area, then choose **Load
into panel**. Choose **Export file list** for the **Export paths** view, optionally
enable **Selected items only**, and use **Save list…** or **Copy paths**. Both
commands are also available in the list toolbar's **File list actions** menu.

Import/export uses UTF-8 `.txt` or `.lst` files with one original path per line.
Local import accepts local file URLs; relative paths resolve against the current
directory in the chosen panel's storage source. Paths are normalized and
deduplicated. Imports reject filesystem roots, unrelated URLs, malformed
lines, more than 10,000 entries, and text larger than 4 MiB. Every imported item
is verified by listing its parent through the selected storage source; missing
or ambiguous entries are reported, and no unverified path gains mutation
permission. Exported lists contain paths, not credentials or account identities.
Choose the correct source before importing a saved list.

Export a list to retain it across app restarts. Session-only list tabs keep
account provenance in memory; saved path lists are verified again when loaded.
An account disconnect/change invalidates old result operations. Editors retain
their stronger existing origin checks; opening a list does not authorize editor
writeback to unverified data.

## Copy and move options

The opposite panel's verified source/directory is the initial destination when
available. The dialog also permits choosing this panel's storage and editing an
absolute destination directory. **Preview** enumerates the selected work and
shows the complete source-to-destination mapping before **Start** is enabled.
Changing any option invalidates that plan and requires another preview.

Available options:

- Exact destination name for a single selected root, or a file naming mask:
  `*.*` keeps names, `*.bak` changes extensions, `*.*.bak` appends a suffix,
  and `[N]_[C:000].[E]` adds a counter. The preview displays the exact paths.
- File conflicts: ask, skip, replace, replace only if source is newer/larger/
  smaller, or keep both with numbered destination names. Missing comparison
  metadata does not authorize replacement. Keep-both names are allocated in the
  preview and checked again during execution.
- Folder conflicts: ask, merge contents, or skip the whole folder.
- Individual conflicts can compare contents, rename the incoming item or preserve
  the existing destination under another name, and apply a decision to remaining
  conflicts. Both source and destination are rechecked after the decision.
- Include subfolders; explicitly selected children still work when recursion is
  disabled. Selecting a folder and its child with recursion enabled processes
  that child once.
- Wildcard/regex file filters, case sensitivity, full-path matching, size/date
  limits, excluded directories, hidden-item handling, and omission of folders
  with no matching contents.
- Direct placement in the destination or preservation of paths relative to an
  explicitly shown source base. Sources outside that base are rejected.
- Preserve file modification times when the native destination supports it.
- Optional SHA-256 content verification, which reads both copies and can add
  cloud traffic.
- Copy symbolic links as links between native local filesystems. Links are
  skipped by default and never traversed recursively.
- Preserve permissions, ownership, extended attributes, and ACLs only when both
  storage endpoints declare support. An incompatible checked profile setting can
  be cleared without modifying the saved profile.
- Verified resume checks the destination prefix against the source before
  completing it. Append combines the existing contents and incoming file. Both
  require known lengths, use staging, and verify the combined content.
- Prefer native/provider copy and move paths where the endpoint supports the
  required exact-destination and completion contracts.
- Stop on first error or continue, with per-item outcomes.

Named profiles persist the complete operation options. Changing a field or
loading a profile invalidates the old preview; Start always uses the newly
reviewed plan. In-app panel drops open these same source-aware copy options,
including after swapping which storage appears on each side.

Start runs through the existing transfer queue. The dialog and operations panel
support pause/resume/cancel. **Queue in background** is available when both
conflict policies have deterministic answers, so a closed dialog cannot leave
an unanswered overwrite prompt. Completed, skipped, filtered, failed, and
cancelled items remain distinguishable in operation results.

### Transfer safety and backend boundaries

Self-copies/moves, copies into a selected source folder, destination type
conflicts, ambiguous names, and incompatible destination parents are rejected.
Source versions and account guards are checked during execution. Failed,
filtered, skipped, or cancelled copies never authorize source deletion. A move
removes each source file only after its destination has been written and
verified; optional checksum verification adds content comparison.

Native writes use a temporary file in the destination directory and commit the
completed data afterward. Cloud writes upload under a unique temporary name,
verify that stage, preserve an existing destination under a recovery name, and
then rename the staged copy into place. Failed commits attempt restoration;
when recovery cannot complete, the error identifies the retained recovery path.
Account changes prohibit cleanup against the replacement account.

Cloud operations depend on the provider's listing/upload/rename contracts and
are not distributed transactions or atomic compare-and-swap operations.
Concurrent external changes can still cause an operation to fail. Empty source
folders are retained in browsers and on cloud backends whose API exposes only
recursive deletion; native move cleanup removes only truly empty directories.
This avoids deleting files that appear after an emptiness check. Browser
folder rename is unavailable; native and cloud folder rename use their actual
rename operation. Unsupported metadata controls are disabled.

These controls do not implement every platform-specific Commander operation:
reflinks, universal provider permission editing, persistent interrupted-job
recovery, and transactional whole-batch rollback are outside this change.
Metadata options are available only for endpoints with the corresponding
capability. Cross-storage transfers use the provider's streaming contracts; a
provider without streaming support may buffer data. Unknown-length cloud
uploads are buffered to determine an accurate length.

## Implementation and verification

The main components are `MultiRenameService`, `FileSelectionPattern`,
`FileOperationService`, and source-specific `FileOperationBackend` adapters.
Riverpod panel/transfer notifiers own the captured origins, list updates,
operation queue, audit logging, and source-bound rename undo.

Focused tests cover rename transformations/collisions, selection and import
validation, original-path/account provenance, list refresh/tabs/archive reads,
copy/move policy and failure behavior, real native writes, cloud staging and
recovery, and responsive dialog interactions. Existing panel, search, shortcut,
queue, progress, local filesystem, and undo regression suites are also run.
Validation uses the repository's pinned Flutter 3.47.8 / Dart 3.13.7 toolchain.
The release web build is checked without deploying the app. Live provider
credentials are not required by the deterministic tests.

Reference behavior:

- [Total Commander advanced tutorial](https://www.ghisler.com/advanced.htm)
- [Double Commander multi-rename](https://doublecmd.github.io/doc/en/multirename.html)
- [Double Commander file selection](https://doublecmd.github.io/doc/en/help.html)
- [Double Commander search results](https://doublecmd.github.io/doc/en/findfiles.html)
- [Double Commander copy/move](https://doublecmd.github.io/doc/en/copymove.html)
