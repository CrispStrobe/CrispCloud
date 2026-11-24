# CrispCloud user guide

A task-oriented guide to the bundled application. Availability depends on the
platform, account and storage capabilities shown in the current window.

The longer reference text is preserved in the
[user guide archive](user-guide-details.md).
The app's offline Help bundles the reviewed full guide in
[English](help/USER_GUIDE.en.md), [German](help/USER_GUIDE.de.md) and
[French](help/USER_GUIDE.fr.md).

## Start

1. Choose a local folder or connect an account.
2. Open a second location in the other pane, a new tab or a workspace.
3. Select a small set of files and review Copy/Move before starting.
4. Read conflict, permission and recovery messages rather than guessing.

Each pane has its own source, path, selection and history. Local and remote
locations can be mixed freely.

## Connect a provider

Select **Connect**, choose a provider and enter its details. Account labels are
useful when several accounts share a provider.

Supported families include:

- Filen and Internxt;
- SFTP, FTP/FTPS, WebDAV and SMB;
- S3-compatible storage, Azure Blob and Backblaze B2;
- Google Drive, OneDrive/SharePoint, Dropbox, Nextcloud and pCloud;
- Hetzner Storage Box and other services exposed by the build’s picker.

Credentials can use the system credential store, an encrypted file vault or
session-only storage. Session-only accounts ask for credentials again after the
app closes.

See [provider setup](PROVIDER_SETUP.md) for fields, OAuth steps and common
errors.

## Navigate

| Action | Default |
| --- | --- |
| Switch pane | `Tab` |
| Open folder / execute file | `Enter` |
| Parent folder | `Backspace` |
| Back / forward | `Alt+Left` / `Alt+Right` |
| New / close tab | `Ctrl+T` / `Ctrl+W` |
| Reopen closed tab | `Ctrl+Shift+T` |
| Go to path | `Ctrl+G` |
| Command palette | `Ctrl+Shift+P` |
| Filter current folder | `Ctrl+F` |
| Refresh | `Ctrl+R` |

On macOS, Command replaces Control for the primary modifier. All bindings can be
changed in **Settings → Customize shortcuts**.

Views include details, brief, thumbnails and gallery. Columns, sorting, hidden
files and per-pane view profiles are independent.

## Select files

- Plain click moves the cursor and keeps existing marks.
- Shift-click marks a visible range.
- Cmd-click on macOS or Ctrl-click elsewhere toggles one item.
- `Ctrl+A` selects all visible rows; selection commands operate on the visible
  filtered scope.
- Wildcard/regex selection, same-extension selection and path-list import are
  available from the Edit menu and command palette.
- Remembered selections are checked against their original accounts before
  restoration.

## Copy, move and delete

Choose **Copy** or **Move**, then review:

- source and actual destination;
- name rules and exclusions;
- conflict policy;
- metadata or capability warnings.

**Start** runs in the foreground. **Queue** and **Schedule** are available for
recoverable jobs. Unsupported destinations or unsafe writes are blocked before
work starts.

During conflicts you can skip, replace, keep both, rename or resume a verified
partial transfer. Append means concatenate; it does not mean resume.

Moves remove originals only after required copy and metadata steps succeed.
Cancellation stops remaining work but does not roll back completed items.
Read per-item outcomes instead of assuming the whole batch is atomic.

Delete/trash behavior depends on the provider. Permanent deletion is not
generally undoable.

## Preview and edit

- `F3` opens the internal viewer.
- `F4` opens the built-in text editor.
- `Shift+F4` chooses an available editor.

The viewer handles text/hex, images, HTML, PDF, supported Office/ODF documents,
archives and audio/video where the platform codec exists. Large files use
bounded pages and report their limit.

The text editor provides syntax highlighting, find/replace, folding, wrapping,
encoding and line-ending controls. Saves stay bound to the original account and
path. A changed or disconnected source requires review.

On supported native desktops, external editor and comparison tools use private
local copies and explicit argument review. Browser, mobile and Mac App Store
builds cannot launch arbitrary external processes.

## Search

Filter narrows the current listing. Search traverses selected roots using names,
patterns, extensions, size, dates or content. Results retain their original
storage identity.

- Plain-text content search streams the source.
- Regex, Office and archive search have explicit extraction budgets.
- Partial results are labelled.
- Duplicate search compares full contents with SHA-256; equal names or sizes are
  not enough.

## Compare and sync

Choose two folders, compare them and inspect proposed actions before executing.
One-way and two-way sync require an explicit plan and conflict decisions.

To compare two files byte-for-byte, select two files in one pane, or one file
in each pane, and choose **Tools → Compare by Content (byte-for-byte)…**. The
binary comparison opens directly at the first difference and never uploads or
changes either file. The same comparison is available from the selection
context menu.

A missing file on one side is not proof that it should be deleted on the other.
Saved relationships retain location identity, but execution still checks live
sources.

## Encryption

Client-side encryption is configured before connecting when the provider offers
it. Keep the exact key or recovery phrase: entering the same passphrase after a
restart creates a new salt and does not decrypt older files.

Key Management can export/import readable key material. A backup bundle is not
itself encrypted. Provider sharing, previews or plaintext search may need to be
disabled on encrypted connections.

## Archives and disk images

Browse ZIP, 7z, TAR, compressed TAR, RAR, ISO, DMG and supported package/disk
formats like folders. Readable does not imply writable.

- Create archives from a reviewed format picker.
- Edit only eligible profiles; unsupported metadata makes the archive read-only.
- Extract, test and recover through the operations queue.
- ZIP recovery writes a new file and never replaces the source.
- Disk-image and filesystem readers are read-only unless explicitly documented.

See [archive coverage](archive-format-coverage.md).

## Queues and recovery

The Operations queue retains active and historical jobs. You can pause, resume,
cancel, reorder and schedule eligible work. Source changes, destination
conflicts and interrupted writes require explicit review.

Copy/move journals and recovery artifacts are retained so a restart does not
silently repeat partial destructive work.

## Terminal

`F9` opens the terminal. It supports local PTYs on desktop, a sandbox shell on
mobile/App Store builds, and SSH with host-key verification. See
[terminal](terminal.md) for gateways, tmux, forwarding and security limits.

## Appearance and commands

Settings covers themes, colours, file-list fonts, view profiles and the main
menu. Custom toolbar commands launch approved executables with reviewed argument
templates.

The command palette searches commands, favourites, workspaces, saved sources,
devices and rename presets. Commands respect the active input owner; editors
and terminals keep their own keyboard handling.

## Related

- [Workspace controls](workspace-ux.md)
- [Commander operations](commander-file-operations.md)
- [Credential storage](credential-storage.md)
- [Transfer queue](transfer-queue.md)
- [Full guide archive](user-guide-details.md)
