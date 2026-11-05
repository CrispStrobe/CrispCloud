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
| Invert selection | Numpad * | Existing Edit menu |
| Copy with options | F5 / Ctrl+C | More actions, context menu, selection bar, command palette |
| Move with options | F6 / Ctrl+X | More actions, context menu, selection bar, command palette |
| Import a file list | Ctrl+Shift+L | More actions, Edit menu, command palette, file-list toolbar |
| Export a file list | — | More actions, Edit menu, command palette, file-list toolbar |

The keyboard handler also accepts Meta in place of Ctrl on macOS. Shift+F5
opens copy options; it no longer opens a rename operation. For a same-folder
file duplicate, choose that folder and **Keep both**.

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

Find/replace can apply to the name, extension, or full filename. Literal and
regular-expression matching support case sensitivity and first/all matches.
Regex replacements expand numbered captures such as `$1`, named captures such
as `${name}`, and `$$` for a literal dollar sign. Separate case controls support
unchanged, lower, upper, title, and sentence case. Named presets persist the
settings between sessions.

The full preview includes original paths, proposed names, and validation
messages. A batch is blocked for invalid names, duplicate destinations in one
parent, source/target overlaps, or conflicting selected folders and descendants.
Execution checks all sources and destinations before the first rename, then
checks again before each item. An occupied destination is never intentionally
overwritten. Cancel and stop/continue-on-error report completed, unchanged,
failed, and unattempted rows separately.

Successful renames update file lists at their original paths. Individual undo
records retain their original storage/account guard and refuse occupied target
names. The batch is not a transaction: cancellation or a later failure retains
successful earlier renames. Cycles and occupied case-only renames require an
unused intermediate name; parent/child renames require separate batches. Date
masks require an available modified timestamp rather than substituting today.

## Pattern selection

The selection dialog changes selection marks without filtering out panel rows.
Choose **Select**, **Deselect**, **Invert matches**, or **Replace selection**,
then wildcard or regex matching, case sensitivity, filename/full-path matching,
and files/folders/both. It previews the matching count. Invalid expressions
cannot be applied and leave the existing selection unchanged.

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

## Search results and reusable file lists

Use **Feed all to panel** or **Feed selected to panel** in search results to keep
hits as a virtual file list. Each row retains its original full path and the
storage/account that returned it. Same-named files from different directories
remain distinct. The result dialog can copy paths or reveal the original
containing folder.

A list panel supports pattern selection, Multi-Rename, copy/move options,
original-path display, and opening the containing folder. **Remove from list**
only removes rows; **Delete files** is a separate command that operates on the
actual stored source. The toolbar can return to the real directory. Lists
survive refresh and tab switches within the current app session. They are not
silently reloaded as unrelated directory contents.

Import/export uses UTF-8 `.txt` or `.lst` files with one original path per line.
Clipboard import/export is available too. Local import accepts local file URLs;
relative paths resolve against the chosen panel source. Paths are normalized
and deduplicated. Imports reject filesystem roots, unrelated URLs, malformed
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

- File conflicts: ask, skip, replace, replace only if source is newer, or keep
  both with numbered destination names. Unknown timestamps never authorize
  replace-if-newer. Keep-both names are allocated in the preview and checked
  again during execution.
- Folder conflicts: ask, merge contents, or skip the whole folder.
- Include subfolders; explicitly selected children still work when recursion is
  disabled. Selecting a folder and its child with recursion enabled processes
  that child once.
- Wildcard/regex file filters, case sensitivity, and full-path matching.
- Direct placement in the destination or preservation of paths relative to an
  explicitly shown source base. Sources outside that base are rejected.
- Preserve file modification times when the native destination supports it.
- Optional SHA-256 content verification, which reads both copies and can add
  cloud traffic.
- Copy symbolic links as links between native local filesystems. Links are
  skipped by default and never traversed recursively.
- Stop on first error or continue, with per-item outcomes.

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
append/resume into existing files, reflinks, ownership/ACL preservation, provider
permission editing, and transactional whole-batch rollback are outside this
change. Cross-storage transfers use the provider's streaming contracts; a
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
