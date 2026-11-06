# Commander file operations

CrispCloud connects search, selection, reusable collections, rename, copy/move,
recovery, comparison, archives, viewers and integrity tools. Commands capture
each item's original storage account and path. The left/right pane label never
determines which account an operation changes.

Development is checkpointed on `feature/commander-file-operations`. This guide
describes integrated behavior; the [completion plan](commander-completion-plan.md)
tracks remaining integration. Earlier limits concerning session-only lists,
individual rename undo, rename cycles and basic copy dialogs are superseded.

## Entry points

| Action | Shortcut | Other entry points |
| --- | --- | --- |
| Multi-Rename | Ctrl+M | More actions, Edit menu, palette, selection context menu |
| Select / deselect by wildcard or regex | Numpad + / - | Edit menu, palette, file-list controls |
| Invert selection | Numpad * | Edit menu |
| Copy / move with options | F5 / F6 | More actions, context menu, selection bar, palette |
| File clipboard copy / cut / paste | Ctrl+C / Ctrl+X / Ctrl+V | Context menu, native clipboard where supported |
| Import path list | Ctrl+Shift+L | More actions, Edit menu, palette, file-list controls |
| Collections and rename/trash/transfer history | — | More actions, Edit menu, palette |
| Checksums, split, combine | — | More actions, Edit menu, palette, context menus |
| View / edit | F3 / F4 | Context menu |

Shortcuts apply while the browser has focus. Relevant Ctrl commands also accept
Meta on macOS. More actions is the three-dot toolbar menu; macOS has a native
Edit menu. A selection context menu may label Multi-Rename as Batch Rename.
Native clipboard integration includes paths and cut/copy intent. The app
clipboard also retains source identities for mixed cloud collections.

## Identity, search results and persistent collections

Named collections persist source-aware references, marks and optional search
definitions. Identical paths from different accounts remain different items.
Refresh verifies the listed items; rerun executes the saved search again.

File Collections opens, saves, appends marked items, renames, imports/exports
and removes collections. Removing a collection or row keeps its stored files.
Delete files is a separate operation. Verified moves and renames update active
and inactive list tabs, including selected folder descendants.

Unavailable accounts, missing items, metadata changes and replacement objects
are distinguished. A different object at a saved path requires review before
mutation. Cancelled refresh/rerun keeps the previous list. Restored tabs retain
source identity and cannot fall back to another currently connected account.

Collection JSON preserves account references. Plain UTF-8 `.txt` / `.lst`
files contain paths only and must be imported against the correct source.
Relative paths resolve against that source's directory. Malformed, missing or
ambiguous paths never gain mutation permission. Plain import is bounded to
10,000 entries / 4 MiB; collection documents to 100,000 entries / 32 MiB.

Local references use an acknowledged random installation identity. A collection
from another computer cannot bind to unrelated files with the same path.
If identity persistence fails, references are session-only and cross-restart
recovery is unavailable. Cloud identities include provider, account and
endpoint/bucket namespace without storing credentials.

## Search and selection

Recursive search supports explicit roots, recursion/depth, wildcard/regex names,
directory exclusions, hidden items, files/folders, extensions, size/date ranges,
and bounded content matching with encoding options. Feed all or marked search
hits to a source-aware panel list. Branch view uses the recursive search engine
for local and cloud sources, with progress and cancellation.

Select by pattern adds, removes, toggles or replaces marks on visible rows.
Parent-directory entries are never marked. Selection memory, same-name/
extension/path commands and pattern history complement the dialog.

- `*` matches any sequence; `?` matches one character.
- `;` separates alternatives, such as `*.jpg;*.png`.
- `|` introduces exclusions: `*.jpg;*.png|thumb*;*_small.*`.
- Exclusions-only `|*.tmp` includes everything else.
- `*.*` includes extensionless names.
- Wildcards match the whole name/path. Regex searches within it unless anchored.

Saved criteria are shared by Search, Select by pattern and transfers. Transfers
combine saved name/type/size/date/hidden/exclusion criteria with the visible
filters. Selected items and Include subfolders define the transfer scope; saved
search roots never replace the reviewed source list. Content/archive criteria
must run as a search first, then feed verified results into a panel. They are
not silently discarded by a selection or transfer.

## Multi-rename

The [multi-rename guide](MULTI_RENAME.md) documents syntax and recovery.

- Name/extension masks, counters, Unicode ranges, parent/path/date fields,
  available metadata, variables and explicit CrispCloud / TC / DC syntax modes.
- Literal/regex replacement, capture groups, simultaneous literal pairs,
  case conversion and editable, reorderable transformation pipelines.
- Manual names, clipboard/file name-list exchange, exclusion and row ordering.
- Persistent presets, JSON preset exchange and previewed collision numbering.
- Chains, swaps, case-only and selected parent/child renames through recorded
  temporary paths, with complete original/final path previews.
- One whole-batch Undo, persistent history, reverse preview, recovery,
  continue-from-current-items and exportable reports.

Each physical mutation has a saved intent and completion. Native records are
flushed and atomically replaced; browser records use acknowledged updates.
Failed persistence stops the next mutation. Undo is a checked reverse operation:
changed files, occupied old names and disconnected accounts block unsafe reversal.

One multi-rename batch belongs to one captured storage account. Files from
several directories on that account may share a batch. A collection containing
several accounts must be renamed in source-specific batches; copy/move can
review multiple source groups against one captured destination.

Native no-replace operations are used where available. Provider prechecks are
identified as weaker when the API cannot enforce exclusion atomically.
Individual object keys require exclusive version-conditional copy and delete;
virtual folder prefixes are not native directory renames. Missing metadata
produces a preview error. Legacy binary Commander content plugins are not loaded.

## Copy, move, queue and recovery

Both endpoints are captured. The opposite verified pane is the initial
destination. Preview shows the mapping before execution; changed options require
another preview. Mixed-account collections are reviewed as captured source
groups against one fixed destination, protecting all selected sources.

- Exact destination names, destination masks, relative paths, profiles and defaults.
- Ask, skip, replace, newer/larger/smaller decisions, Keep both, verified partial
  resume and explicit append. Unknown metadata cannot authorize a comparison.
- Per-conflict rename, compare and apply-to-all, including rename-existing-target.
- Folder merge/skip/ask, recursion, name/metadata filters, saved criteria,
  directory exclusions and empty-result exclusion.
- SHA-256 verification, modification times and capability-gated permissions,
  ownership, extended attributes, ACLs and symbolic links.
- Native/provider fast paths with explicit capabilities and completion checks.
- Automatic, streamed or required copy-on-write methods and native preallocation
  where supported. Required copy-on-write never silently becomes a full copy.
- Stop/continue-on-error and separate content-copy versus metadata-failure results.

Moves delete sources only after confirmed destination data. Failed, skipped,
filtered and cancelled rows retain sources. Metadata failure may leave move
cleanup pending. Staging and backup paths remain visible when restoration
cannot finish.

Durable transfer history retains jobs, entry states, staging/backup evidence,
source identities and queue settings. Interrupted jobs return for explicit review
rather than automatic execution. Retry remaining, restart, reconcile a lost
response and restore a verified backup use fresh evidence. Partial resume
validates the existing prefix and original source.

Concurrency, priority and pending order persist. Paused jobs do not occupy
running slots; cancelled queued jobs do not start. Foreground conflicts wait for
a decision. Background queuing requires choices that can finish without an
abandoned dialog. Clearing visible outcomes retains durable recovery records.

## Large files and resource limits

Commander transfers use bounded streams or private disk-backed spools. Native
spools use owned temporary directories; browser uploads use OPFS-backed files
and fetch bodies instead of assembling entire request bodies in memory. Provider
metadata responses are bounded separately. Browser storage quotas and missing
OPFS support produce explicit errors, and cancelled/failed spools are removed.

- S3 multipart recovery attaches to the saved job's exact private staging key,
  account and upload session. Recovered parts are verified against the original
  source; restarting explicitly discards that attachment. Large parts are spooled
  without making the part size the RAM requirement.
- B2 uses adaptive, verified private parts and checks the completed object's
  identity. A lost finish response is reconciled against the new file ID.
- Filen processes its encrypted chunks sequentially and verifies plaintext size
  and hash. FTP/FTPS transfers own separate sessions so cancelling one transfer
  does not close a browsing connection.
- Internxt streams its existing continuous encryption format through private
  native/OPFS staging and verifies size, checksums and registered identity. Its
  SDK's 20 GiB upload limit and single-shard layout remain explicit; see
  [Internxt transfer behavior](INTERNXT_TRANSFERS.md).
- CrispCloud's optional AES-GCM wrapper keeps the existing encrypted format.
  Decrypted content remains in a private spool until its authentication tag
  verifies. This requires temporary disk space before plaintext can be read.
  The format supports at most 68,719,476,704 plaintext bytes per encrypted file.
  Cancellation interrupts an unfinished authenticated download.

All production cloud adapters provide their own transfer streams. A legacy
adapter without a real streaming download is rejected. Its compatibility upload
accepts at most 32 MiB, checks exact EOF before committing, and checks the original
account/endpoint throughout. This ceiling does not replace the real adapters'
provider-specific limits. Plaintext lengths from encrypted/transforming adapters
are kept separate from stored object sizes.

Large-tree preview reports incremental progress and supports pause/cancel, with
limits of 200,000 planned entries and 256 directory levels. Split a larger job
into narrower roots. These limits bound planning work without hiding skipped
rows or silently changing the requested selection.

## Comparison, archives, viewers and integrity

Folder comparison produces a reviewed plan with per-item decisions and fresh
fingerprint checks. Synchronization Keep both preserves both contents. Duplicate
candidates require content confirmation before being presented as identical.

Text comparison offers editable merge output and guarded saves; binary
comparison and bounded reads are available. Editors retain their captured
account and detect external changes. Browser download-copy saves are not
represented as confirmed in-place writes.

The archive workspace supports ZIP, 7z, TAR and TAR.GZ edit/repack and selected
member copy-out. Edits are staged until Save. Moving a member out removes its
staged entry only after the copy succeeds. Containment checks, expansion budgets,
source fingerprints and hashes guard extraction/repack. Unsupported formats or
transformations fail explicitly.

Viewer playlists retain each row's original source, support reload and bounded
tail, and route F4 to the correct editor. Remote media/PDF use owned spool files
and release resources on close. Generic byte previews default to 64 MiB; remote
viewer spooling is bounded to 2 GiB. Native viewing can use file-backed windows.
Preview and Properties use captured origins rather than guessing locality from
the path.

Checksum tools stream MD5, SHA-1, SHA-256, SHA-512 and CRC32 and validate GNU/SFV
manifests with exact filenames and safe paths. Split manifests record ordered
parts, sizes, per-part SHA-256 and whole-file SHA-256. Combine preflights all
parts and the destination, writes and verifies a stage, then commits. Missing/
corrupt/changed parts, traversal, cancellation and account changes stop the
operation. Legacy numbered parts require consent because no original checksum
is available.

## Workspaces, commands and backend boundaries

Tabs support labels, reordering, four lock modes and source-bound snapshots.
Inactive-tab duplication uses the clicked tab. Locked result tabs retain their
rows, and account switching cannot rebind a protected tab. The workspace manager
saves/restores named tab groups, paired locations and view profiles. Bookmarks
retain original source identity, and older unbound bookmarks require explicit
binding. Profiles store display mode, ordered columns, widths, supplied metadata
fields, sorting and manual filters. Built-in column labels follow the app locale;
user-entered titles remain literal. See the [workspace guide](WORKSPACE.md).

The [custom-command manager](COMMANDS.md) configures installed executables with
literal argument templates, working directories and timeouts. It supports
reviewed import/export, editing and reordering. Running a command requires a
reviewed captured local context and provides bounded output and cancellation.
Existing shell-string definitions remain visible but need conversion before use.

The live panel command bar hosts custom commands and enabled extension actions.
The [extension manager](EXTENSIONS.md) imports reviewed declarative manifests,
installs replacements disabled, persists effective command settings, and supports
export, removal, initialization retry and first-party plugin lifecycle management.
Disabling or changing an extension invalidates already-open command reviews.
Native process and path-only plugin actions require verified local rows.

Capabilities remain platform/provider-specific. Browser storage can be evicted
and directory permission revoked. Metadata, links, clipboard actions, exclusive
rename and server operations differ by backend. Unsupported controls are
disabled or rejected before mutation. An accepted asynchronous request is not
proof of completion.

Distributed atomic rollback across unrelated stores and all legacy binary
Commander plugins are not universal guarantees. Recovery uses recorded evidence
and fresh validation. The completion plan tracks remaining adapter,
extension and localization checkpoints; do not treat those
unchecked items as complete.

## Verification

Tests exercise captured accounts, persistent collections, rename staging/undo,
restart/recovery, failed transfers, native temporary files, mocked provider
protocols, archives, integrity manifests and narrow widget layouts. Provider
tests use fixtures, not live credentials. Validation uses Flutter 3.47.8 /
Dart 3.13.7. These checkpoints do not deploy or merge the feature branch.

Reference behavior:

- [Total Commander advanced tutorial](https://www.ghisler.com/advanced.htm)
- [Double Commander multi-rename](https://doublecmd.github.io/doc/en/multirename.html)
- [Double Commander selection](https://doublecmd.github.io/doc/en/help.html)
- [Double Commander search](https://doublecmd.github.io/doc/en/findfiles.html)
- [Double Commander copy/move](https://doublecmd.github.io/doc/en/copymove.html)
