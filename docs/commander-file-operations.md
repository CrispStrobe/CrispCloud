# Commander file operations

CrispCloud connects search, selection, reusable collections, rename, copy/move,
recovery, comparison, archives, viewers and integrity tools. Commands capture
each item's original storage account and path. The left/right pane label never
determines which account an operation changes.

Development is checkpointed on `feature/commander-file-operations`. This guide
describes integrated behavior; the [completion plan](commander-completion-plan.md)
records current implementation and acceptance status. Earlier limits concerning session-only lists,
individual rename undo, rename cycles and basic copy dialogs are superseded.

## Entry points

| Action | Shortcut | Other entry points |
| --- | --- | --- |
| Multi-Rename | Ctrl+M | More actions, Edit menu, palette, selection context menu |
| Select / deselect by wildcard or regex | Numpad + / - | Edit menu, palette, file-list controls |
| Select / deselect same extension | Shift+Numpad + / - | Edit menu, palette, pattern dialog |
| Load selection from paths | — | More actions, Edit menu, palette, file-list controls |
| Change attributes | — | Properties, selection context menu, Edit menu, palette |
| Invert selection | Numpad * | Edit menu |
| Copy / move with options | F5 / F6 | More actions, context menu, selection bar, palette |
| File clipboard copy / cut / paste | Ctrl+C / Ctrl+X / Ctrl+V | Context menu, native clipboard where supported |
| Import path list | Ctrl+Shift+L | More actions, Edit menu, palette, file-list controls |
| Collections and rename/trash/transfer history | — | More actions, Edit menu, palette |
| Checksums, split, combine and split/combine recovery | — | More actions, Edit menu, palette, context menus |
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
and content matching with encoding options. Literal plain-text searches consume
the entire source stream with bounded memory. Regex, Office extraction and archive
member content retain explicit extraction budgets (64 MiB by default); exceeding
a budget is reported rather than treated as a non-match. Feed all or marked search
hits to a source-aware panel list. Branch view uses the recursive search engine
for local and cloud sources, with progress and cancellation.

Select by pattern adds, removes, toggles or replaces marks on visible rows.
Parent-directory entries are never marked. Selection memory, same-name/
extension/parent-folder commands and pattern history complement the dialog.
Same name compares the stem without its final extension. Path-list selection
marks only verified visible rows in a chosen source, retaining the panel contents
and cursor. Saved directory exclusions also apply to ancestors in flat lists.
Archive matches retain their member paths and evidence in saved collections.

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

Clipboard copy/cut captures the source selection. Paste opens the same reviewed
transfer options at the destination; it does not immediately overwrite files.

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

Single-file Rename uses this same journal, fingerprint and Undo path. Its prompt
captures the source before input and supports cancellation during streamed
fingerprinting. New Folder likewise captures the destination before its prompt;
changing accounts or locations cannot redirect submission, and a failed operation
keeps its error visible instead of producing a success notification.

Native directory fingerprints enumerate with cancellation and share limits of
200,000 entries, 256 levels and 32 MiB of listed path bytes. Directory digests are
hashed incrementally in the existing stable format. Exceeding a budget blocks
the reviewed rename; it does not silently omit descendants.
The browser rename fallback has an explicit 64 MiB per-file buffer ceiling.

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
- Keep-both templates use `{name}`, `{ext}` and a required `{counter}` or
  `{counter:000}`. Preview, late conflicts, profiles and recovery use the same
  filename-only template; the counter always starts from the original base name.
- Optional client streaming rate in KiB/s, retained in profiles and recovery.
  This paces bytes supplied to the copy stream. Verification and native or
  server-side copies are excluded; providers that spool uploads can still burst
  on the later network send, so this is not a network bandwidth guarantee.
- Ask, skip, replace, newer/larger/smaller decisions, Keep both, verified partial
  resume and explicit append. Unknown metadata cannot authorize a comparison.
- Per-conflict rename, compare and apply-to-all, including rename-existing-target.
- Folder merge/skip/ask, recursion, name/metadata filters, saved criteria,
  directory exclusions and empty-result exclusion.
- SHA-256 verification, modification times and capability-gated permissions,
  ownership, extended attributes, ACLs, Windows attributes and symbolic links.
- Native/provider fast paths with explicit capabilities and completion checks.
- Automatic, streamed or required copy-on-write methods and native preallocation
  where supported. Required copy-on-write never silently becomes a full copy.
- Stop/continue-on-error and separate content-copy versus metadata-failure results.

Moves delete sources only after confirmed destination data. Failed, skipped,
filtered and cancelled rows retain sources. Metadata failure leaves move cleanup pending and retains the source.
Folder metadata is applied after descendants; a child requiring retry prevents
restrictive parent metadata from blocking that retry. Missing requested metadata
is reported as a failure, rather than silently omitted. Staging and backup paths remain visible when restoration
cannot finish.

Durable transfer history retains jobs, entry states, staging/backup evidence,
source identities and queue settings. Interrupted jobs return for explicit review
rather than automatic execution. Retry remaining, restart, reconcile a lost
response and restore a verified backup use fresh evidence. Partial resume
validates the existing prefix and original source.

Concurrency, priority and pending order persist. Paused pending jobs do not occupy
running slots; cancelled queued jobs do not start. Foreground conflicts wait for
a decision. Recoverable background jobs with Ask enter a persisted waiting state
and release their worker slot. Resolve conflict in the operations panel opens
fresh source/account/file validation before continuing through the usual conflict
chooser. Temporary storage without recovery support keeps conflict review in the
open foreground dialog. Clearing visible outcomes retains durable recovery records.

Mobile background sync writes a separate journal for each invocation. An OS-held
lease prevents foreground recovery from reading an active writer's log, including
another isolate in the same process. App startup, resume and transfer history
discover released logs. Imports retain account bindings, temporary paths and
checkpoint states; durable receipts prevent duplicate recovery after retry or
history compaction. An incomplete journal remains available for diagnosis.
Mobile workers reconstruct authenticated FTP/FTPS and WebDAV sessions from the
same secure credential maps as the foreground app. Each worker uses a private
in-memory copy, so closing a connection or failing authentication cannot erase
the foreground account's credentials. Saved endpoint/account bindings are still
checked before synchronization. Missing credentials and providers without a
background reconstruction implementation produce a failed task and a visible
result; they are not silently counted as successful synchronization. Other
providers continue through foreground sync or an available connected client.

Android and iOS callbacks accept their actual registered task identifiers; the
iOS headless engine registers the required plugins. The interval is a requested
minimum, and the operating system controls execution. iOS applies the latest
desired interval when its pending wake reschedules, including when an older
request remains after a replacement submission was rejected internally by the
plugin. A pending identifier proves that a wake exists, not that a replacement
request was accepted. Reported scheduling/cancellation failures retain the
previous setting and appear in the controls instead of toggling them optimistically.

## Reviewed bulk attributes

Change attributes accepts a multi-file selection, including verified rows from
several sources. Blank fields retain their existing values. Permissions are
entered as three or four octal digits; ownership uses the backend's IDs. Modified
and accessed timestamps, plus creation time where supported, use an explicit
local-time or UTC interpretation, and
invalid calendar dates are rejected. Each row is capability-checked during the
read-only preview. Unsupported rows and links are shown individually.

Windows Read-only, Hidden, System and Archive controls have three states: keep,
set and clear. Only explicitly selected bits change; directory, sparse,
compression and other unrelated native flags are retained. Permissions are
shown only for sources with a POSIX mode; Windows ownership uses SIDs.

Applying revisits the captured account, file version and requested metadata before
each write, then reads those fields back. Recursive edits process descendants
before parents. Cancellation stops remaining items; a failed child retains its
parent's attributes for retry. A batch is a sequence of reported per-item changes,
not a filesystem-wide atomic transaction. Linux/macOS native metadata uses
non-following descriptors for ownership, xattrs, ACLs and timestamp operations;
platform-specific behavior is validated by the desktop test gates. Windows
uses checked handles for SIDs, DACLs and native file attributes. It preserves
DACL protection and distinguishes a null DACL from an empty DACL. SACL/audit
policy is outside the copied ACL contract. Creation-time editing is currently
implemented on Windows; Linux/macOS do not advertise that capability.
macOS can omit ACL evidence for both a missing ACL and an unavailable ACL.
That omission is reported as unavailable: preserving an ACL then fails explicitly
instead of clearing the destination's security settings from an assumption.
Named ACLs with returned evidence remain readable and writable.

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

Sync review defaults to a fast metadata comparison. **Compare full file contents**
streams every included file, including files with matching size and modification
time, and compares SHA-256 evidence against the last verified common baseline.
It reports progress and supports cancellation. Conflicting changes without a
trusted baseline or an unambiguous winner require a decision. Equal rows are
revalidated before execution too; an external change invalidates the review.
Source bindings include account, endpoint/bucket, device and roots. Older saved
pairs require explicit binding, and rebinding does not redirect queued jobs.
Cloud-only placeholders cannot authorize deletion of the remote original.

Text comparison offers editable merge output and guarded saves, with independent
UTF-8, UTF-16/32 LE/BE and Latin-1 decoding on the two sides. BOM-less Unicode
and line-ending style survive repeated saves. Text merge is bounded to 8 MiB.
Binary comparison streams whole files, counts exact contiguous difference ranges
and provides first/previous/next/last navigation, decimal or `0x` byte offsets,
and paged highlighted hex/ASCII. Its sparse index avoids retaining every range;
some navigation rescans the file. Editors retain their captured
account and detect external changes. Browser download-copy saves are not
represented as confirmed in-place writes.

The archive workspace supports ZIP, 7z, TAR and TAR.GZ edit/repack and selected
member copy-out. Edits are staged until Save. Moving a member out removes its
staged entry only after the copy succeeds. Containment checks, expansion budgets,
source fingerprints and hashes guard extraction/repack. Unsupported formats or
transformations fail explicitly.

Nested archives retain a route to the original physical container. Leaving an
inner archive restores its parent's directory and cursor; supported nested
updates propagate through owned workspaces and save only the captured outer
file after validating it. Navigation is limited to eight archive levels.
Native browsing spools at most 2 GiB of container input; web browsing is limited
to 256 MiB. Individual members and nested containers are limited to 64 MiB, as
are compressed formats whose decoder requires buffering. Editing also enforces
its existing total expansion and repack budgets. These limits produce explicit
errors instead of silently incomplete listings.

Viewer playlists retain each row's original source, support reload and bounded
tail, and route F4 to the correct editor. Remote media/PDF use owned spool files
and release resources on close. Generic byte previews default to 64 MiB; remote
viewer spooling is bounded to 2 GiB. Native viewing can use file-backed windows.
Preview and Properties use captured origins rather than guessing locality from
the path.

Text and byte search scan the entire available viewer source. Text search uses
decoded characters, supports Match case, and treats whitespace and `0x` text
literally; Hex mode accepts byte patterns. At most 2,000 matches are indexed per
page, but all matches remain navigable. Forward pages continue from their
recorded cursor; backward/last pages may rescan with progress and cancellation.
Text windows are 4 MiB with bounded line indexing, and preserve UTF-8 characters
and UTF-16 surrogate pairs at boundaries. Reload, source changes and edited or
stopped queries invalidate old results.

Checksum tools stream MD5, SHA-1, SHA-256, SHA-512 and CRC32 and validate GNU/SFV
manifests with exact filenames and safe paths. Split manifests record ordered
parts, sizes, per-part SHA-256 and whole-file SHA-256. Combine preflights all
parts and the destination, writes and verifies a stage, then commits. Missing/
corrupt/changed parts, traversal, cancellation and account changes stop the
operation. Legacy numbered parts require consent because no original checksum
is available. A reviewed manifest's complete effective definition is checked
again before writing, so an edited manifest cannot silently substitute parts;
harmless JSON formatting changes remain acceptable.

Split and combine save their reviewed definition and write intent before changing
outputs. After interruption, **Split/combine recovery** is available from the
keyboard palette, menus, the original operation dialog and saved operation
history. It reconnects only to the original storage accounts and verifies source
bytes, parts, manifests and existing outputs before offering continuation.
Split resumes missing parts while retaining verified completed parts. An unfinished
combine restarts from verified inputs into a new stage; a matching completed
output can instead be recorded without another copy. A changed source, part,
account, destination directory or unreviewed file at an output path blocks the
operation. Retained staging and backup files are listed for inspection.

Recovery never appends to an unverified file or automatically retries after
restart. **Forget recovery, keep files** removes only the saved instructions;
originals, parts, manifests, completed output and retained recovery files remain.
An unreadable journal is reported rather than presented as an empty history.

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

| Workflow | Native filesystem | Browser filesystem | Cloud source |
| --- | --- | --- | --- |
| Copy/move data | Streams, verified stages, supported native fast paths | Writable handles; OPFS for private spooling where needed | Adapter streams/spools and confirmed provider operations |
| Exclusive rename | OS no-replace primitive where available | Verified fallback subject to handle and size limits | Exclusive/conditional API where available; weaker prechecks are identified |
| Permissions and ownership | POSIX mode/UID/GID on Unix; SID ownership on Windows | Not advertised by the current browser backend | Only adapters with explicit metadata capabilities |
| Extended attributes and ACLs | Unix xattrs and returned ACL evidence; Windows DACLs | Not advertised | Only when the adapter can read, write and verify the requested field |
| Creation time and DOS attributes | Windows checked-handle implementation | Not advertised | Only when explicitly advertised by the adapter |
| Trash and restore | Native supported trash implementation and retained restore identity | Depends on the filesystem API; permanent deletion stays explicit | Provider trash/restore contract; no invented undo for permanent deletion |
| Restart recovery | Flushed journals and captured installation/account references | Acknowledged persistent storage; eviction remains a limitation | Reconnect the original account; provider-specific resume evidence is checked |
| Clipboard | App selection plus native file-manager interoperability | App selection; browser clipboard permission applies | App selection retains original accounts; paste opens reviewed transfer |
| Background mobile sync | Separate leased log on Android/iOS; OS scheduling applies | Unavailable | Reconstructible FTP/FTPS/WebDAV credentials; other providers use foreground paths |

Pause and cancellation take effect at supported transfer checkpoints. An already
accepted provider request can finish writing a private stage before returning;
cancellation prevents subsequent forward commit steps. Recovery retains evidence
when a provider cannot confirm or reverse an operation already in flight.

Distributed atomic rollback across unrelated stores and all legacy binary
Commander plugins are not universal guarantees. Recovery uses recorded evidence
and fresh validation. The implementation plan concerns the workflows
described here, with these explicit platform, provider and resource boundaries.

## Verification

Tests exercise captured accounts, persistent collections, rename staging/undo,
restart/recovery, failed transfers, native temporary files, mocked provider
protocols, archives, integrity manifests and narrow widget layouts. Provider
tests use fixtures, not live credentials. Validation uses Flutter 3.47.8 /
Dart 3.13.7. The implementation was merged through
[PR #13](https://github.com/CrispStrobe/CrispCloud/pull/13); historical development
checkpoints are recorded in the closed
[PR #12](https://github.com/CrispStrobe/CrispCloud/pull/12).

The deterministic application gate excludes explicitly tagged benchmarks, live
provider/deployment tests, integration fixtures and goldens. Run the same scope
after resolving the pinned dependencies:

```sh
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub --concurrency=2 --reporter=expanded \
  --exclude-tags=benchmark,live,deploy,mock_server,integration,connection_dialog,golden
flutter build web --no-pub --release --no-wasm-dry-run
```

CI separately runs shared-storage and CLI contracts, desktop crypto checks on
Linux/Windows/macOS, and native platform builds. Analysis follows the repository's
errors-only policy; a successful check does not mean all existing lint notices
have been removed.

At merged commit `0b35b16`, the
[main CI run](https://github.com/CrispStrobe/CrispCloud/actions/runs/42139152722)
passed 6,006 deterministic application tests with 12 skipped, 14 shared-storage
contracts, 104 CLI contracts, and 44 crypto tests on each desktop OS. Release
builds passed for Web, Linux, Windows, macOS, Android and unsigned iOS. The macOS
job also passed 102 regression tests and a 12-second release-app startup check.
The [image-editor workflow](https://github.com/CrispStrobe/CrispCloud/actions/runs/42139152665)
and [PDF-editor workflow](https://github.com/CrispStrobe/CrispCloud/actions/runs/42139152677)
passed for the same commit. These are merged-head results, not validation of a
later follow-up commit. Builds and startup checks do not replace interactive
provider testing or signed-device validation.

Reference behavior:

- [Total Commander advanced tutorial](https://www.ghisler.com/advanced.htm)
- [Double Commander multi-rename](https://doublecmd.github.io/doc/en/multirename.html)
- [Double Commander selection](https://doublecmd.github.io/doc/en/help.html)
- [Double Commander search](https://doublecmd.github.io/doc/en/findfiles.html)
- [Double Commander copy/move](https://doublecmd.github.io/doc/en/copymove.html)
