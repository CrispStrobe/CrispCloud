# CrispCloud User Guide

CrispCloud is an open-source, cross-platform cloud file manager. It connects to 11 cloud providers and servers from a single two-panel interface, running natively on macOS, Windows, Linux, Android, iOS, and as a Progressive Web App.

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Supported Providers](#supported-providers)
3. [Two-Panel Interface](#two-panel-interface)
4. [File Operations](#file-operations)
5. [Tabbed Interface](#tabbed-interface)
6. [Preview Pane](#preview-pane)
7. [Built-in Editor](#built-in-editor)
8. [Search and Filters](#search-and-filters)
9. [Sync Engine](#sync-engine)
10. [Client-Side Encryption](#client-side-encryption)
11. [Themes and Appearance](#themes-and-appearance)
12. [Command Palette](#command-palette)
13. [Keyboard Shortcuts](#keyboard-shortcuts)
14. [Bookmarks and Recent Locations](#bookmarks-and-recent-locations)
15. [Share Links](#share-links)
16. [Batch Rename](#batch-rename)
17. [Archive Support](#archive-support)
18. [FUSE Mounted Drives](#fuse-mounted-drives)
19. [CLI Companion](#cli-companion)
20. [Security Features](#security-features)
21. [Backup Engine](#backup-engine)
22. [Automation Rules](#automation-rules)

---

## Getting Started

### Installation

Download the latest release for your platform from the GitHub Releases page:

- **macOS**: `.dmg` disk image
- **Windows**: `.exe` installer
- **Linux**: `.AppImage`, `.deb`, or `.rpm`
- **Android**: `.apk` or Play Store
- **iOS**: App Store
- **Web (PWA)**: Open in browser, click "Install" in the address bar

### First Connection

1. Launch CrispCloud. The app opens with a two-panel layout — local filesystem on the left, remote (cloud) panel on the right.
2. In the remote panel, click **Connect** (or press **Ctrl+Shift+C**) to open the connection dialog.
3. Select a provider from the dropdown.
4. Enter credentials for your chosen provider (see [Provider Setup Guide](PROVIDER_SETUP.md) for details).
5. Click **Connect**. The remote panel populates with your files.

CrispCloud saves credentials using your OS keychain (Keychain on macOS, Keystore on Android, Credential Manager on Windows, libsecret on Linux) by default. If no keychain is usable, choose **Settings → Credentials → Credential storage** and select the encrypted file vault (master password) or session-only mode. See [credential-storage.md](credential-storage.md). You will not be asked to re-enter credentials on subsequent launches when a persistent backend is used.

### Multiple Connections

To connect to a second provider simultaneously, click the **+** button in the remote panel tab bar to open a new tab, then connect to a different provider. Cloud-to-cloud transfers work between any two connected tabs.

---

## Supported Providers

| Provider | Auth | Streaming | Versioning | Sharing | Full-Text Search |
|----------|------|-----------|------------|---------|------------------|
| **Filen** | Email + password | Yes | No | No | No |
| **Internxt** | Email + password | No | No | No | No |
| **SFTP** | Password or SSH private key | Yes (native) | No | No | No |
| **WebDAV** | Username + password | No | No | No | No |
| **S3 / S3-compatible** | Access key + secret | Yes | No | No | No |
| **FTP / FTPS** | Username + password | No | No | No | No |
| **Google Drive** | OAuth2 | No | Yes | Yes | Yes |
| **OneDrive** | OAuth2 | No | Yes | Yes | Yes |
| **Dropbox** | OAuth2 | No | Yes | Yes | Yes |
| **Nextcloud** | Username + app password | No | No | Yes | No |
| **pCloud** | OAuth2 | No | No | No | No |

**S3-compatible endpoints** include MinIO, Backblaze B2, Wasabi, DigitalOcean Spaces, and Cloudflare R2.

**Capability notes:**
- Providers marked "Streaming" support true chunk-based transfers without loading entire files into memory.
- "Versioning" allows viewing and restoring previous file versions.
- "Sharing" generates provider-native public or restricted share links.
- "Full-Text Search" queries file contents server-side without downloading files.

---

## Two-Panel Interface

The default layout displays two panels side by side:

- **Left panel**: local filesystem (your device)
- **Right panel**: remote connection (cloud or server)

### Navigation

- Click a folder to enter it.
- Click the breadcrumb segments at the top of each panel to jump up the hierarchy.
- Click the **edit icon** in the breadcrumb bar to type a path directly and press **Enter** to navigate.
- Press **Ctrl+G** to open the Go To Folder dialog.
- Press **Backspace** or **Alt+Left** to go up one directory level.

### Panel Modes

Switch between layout presets from the View menu or toolbar:
- **Commander**: two-panel side by side (default)
- **Explorer**: single panel with collapsible folder tree on the left
- **Gallery**: grid view optimized for image-heavy directories

On mobile, swipe left and right to switch between panels. On tablet and desktop, drag the center splitter to resize panels; double-tap the splitter to reset to 50/50.

### Status Bar

The status bar at the bottom of each panel shows:
- Provider name and connection status
- Item count in the current folder
- Count and total size of selected items
- Active transfer count and aggregate progress
- Storage quota (used / total) when the provider reports it
- Sync status (number of changes in last sync run)

---

## File Operations

All operations are accessible from the toolbar, the right-click context menu, or keyboard shortcuts.

For Multi-Rename, wildcard/regex selection, reusable search-result lists, and detailed copy/move options, see [Commander file operations](commander-file-operations.md).

### Upload

- **Drag and drop** files or folders from your OS file manager onto the remote panel.
- **Toolbar upload button**: opens a file picker to select files for upload.
- On mobile, use the **+** FAB and choose "Upload".

Uploads run through the transfer queue with up to 3 concurrent transfers. Each transfer shows per-file progress, speed, and ETA. The queue supports pause, resume, and cancel per transfer or for all transfers.

S3 uploads larger than 5 MB automatically use multipart upload with per-part progress. Interrupted multipart uploads can be resumed.

### Download

- Select one or more files and press **F5** or use the context menu → **Download**.
- Files download to the local panel's current directory.

### Move and Copy

- **Move**: select files and press **F6** to review move options, or **Ctrl+X** followed by **Ctrl+V** in the destination.
- **Copy**: select files and press **F5**, drag them to the other pane, or use **Ctrl+C** followed by **Ctrl+V**. Each route opens copy options before starting a transfer.
- **Copy/move with options**: F5/F6 opens a preview with destination, conflict, recursion, filter, metadata, and verification controls. Cloud transfers through this dialog use the provider streaming contracts and may transfer data through your device; providers without streaming support may buffer it.

### Delete

- Select files and press **Delete** or **F8**.
- A confirmation dialog shows the count and total size of items to be deleted.
- Deletion is sent to the provider's trash when available, or permanently deleted otherwise.

### Rename

- Select a single file and press **F2**, or double-click the name.
- Type the new name and press **Enter**.

### Create Folder

- Press **F7** or use toolbar → **New Folder**.

### Calculate Folder Size

Right-click a folder → **Calculate Size**. CrispCloud recursively sums all file sizes and displays the result in the status bar.

### Checksum

Right-click a file → **Checksum** to compute MD5 and SHA-256 hashes for integrity verification.

### File Permissions (SFTP)

Right-click a file on an SFTP connection → **Permissions** to open the permissions editor. A visual rwx grid lets you toggle read/write/execute bits for owner, group, and others. Octal presets (644, 755, 700, etc.) are available as quick-select buttons. You can also change the owner and group.

### Undo

Use **Ctrl+Z** or Edit → **Undo Last Action** for a reversible action in the history. The history keeps the last 50 actions for the current session. Multi-Rename records the completed batch as one action, including batches of more than 50 files, and binds undo to the original storage account. Undo refuses occupied original names and can retry the remaining items after a partial failure. Copy/move with options reports each completed, skipped, or failed item; it does not offer whole-batch rollback. Delete recovery depends on the provider and available trash support.

Multi-Rename also has **History / recovery**, which keeps its batch records across restarts. Reconnect the original storage account to inspect, resume, or restore a recorded batch. Its checks still apply to the current files and occupied names; recovery is a sequence of checked operations, not an atomic rollback. See [Multi-rename and recovery](MULTI_RENAME.md).

---

## Tabbed Interface

Each panel supports multiple tabs, like a browser.

### Tab Operations

| Action | Shortcut |
|--------|----------|
| New tab | Ctrl+T |
| Close tab | Ctrl+W |
| Cycle next tab | Ctrl+Tab |
| Cycle previous tab | Ctrl+Shift+Tab |
| Duplicate tab | Right-click tab → Duplicate |
| Pin tab | Right-click tab → Pin |
| Close all other tabs | Right-click tab → Close Others |

Pinned tabs cannot be closed accidentally with Ctrl+W. They are visually distinguished with a pin icon.

### Tab Persistence

Directory tabs, including their paths and pinned state, are saved automatically and restored on the next launch. Search-result and imported file-list contents persist only within the current app session; export a file list to retain its paths across restarts.

### Drag Between Tabs

Drag selected files onto a tab header to move or copy them to that tab's location. A visual drop indicator appears on the tab.

---

## Preview Pane

Press **Space** or click the eye icon in the toolbar to toggle the preview pane. It opens as a 280 px sidebar on the right side of the active panel.

### Supported Preview Types

| Type | Details |
|------|---------|
| **Images** | JPEG, PNG, WebP, GIF, BMP — interactive zoom and pan |
| **Text / Code** | 40+ extensions (dart, py, js, md, json, yaml, etc.) — monospace viewer, up to 5 MB |
| **Markdown** | Rendered with full styling (headings, code blocks, tables, links) |
| **PDF** | Page-by-page scrollable viewer |
| **Video / Audio** | Inline player with seek, play/pause, and volume controls |
| **Metadata** | File name, type, size, modified date, full path for any file type |

Thumbnails for image files are generated in a background isolate and cached on disk. Provider-native thumbnails are fetched for Google Drive, OneDrive, and Dropbox.

---

## Built-in Editor

Double-click any text or code file in the remote panel to open it in the built-in editor. CrispCloud downloads the file, opens it in a full-screen editor with line numbers, and re-uploads it automatically when you save.

### Saving

- **Ctrl+S**: save and upload. The editor checks whether the file was modified on the server since you opened it. If so, a conflict banner appears — you can overwrite, discard your changes, or open a diff.
- **Auto-save**: the editor auto-saves every 30 seconds. A local snapshot is created before any save that would overwrite a changed remote file.

### Diff Viewer

Right-click two files → **Compare** to open the diff viewer. It shows a side-by-side comparison with highlighted additions and deletions, synchronized scrolling, and line numbers. The diff is computed locally using the LCS algorithm.

### External Editor

To use your system's default editor instead, go to Settings → Editor → **Prefer external editor**. The file is downloaded to a temp path and opened with the system `open`/`xdg-open`/`start` command.

---

## Search and Filters

Open search with **Ctrl+F** or the toolbar magnifier icon.

### Filename Search

Type in the search bar to filter the current directory listing client-side. The filter is debounced and incremental — no round-trip to the server.

Toggle **Regex** mode to match filenames using regular expressions.

### Full-Text Search

For providers that support it (Google Drive, OneDrive, Dropbox), the search queries file contents server-side. For other providers, CrispCloud downloads small text files (under 1 MB) and searches their contents locally.

### Filters

Click the filter icon to narrow results by:
- **Type**: Documents, Images, Video, Audio, Code, Archives
- **Size range**: minimum and maximum file size
- **Date range**: modified before or after a date

### Saved Searches (Smart Folders)

Click **Save Search** after performing a search. Saved searches appear in the sidebar and behave like virtual folders — selecting one re-runs the search and shows results as a browsable directory.

### Duplicate Finder

Right-click a folder → **Find Duplicates**. For local files, duplicates are found by MD5 hash. For remote files, duplicates are identified by size. Results show groups of duplicate files with their paths and sizes, so you can select and delete unwanted copies.

### Search Results as Folder

In the search results dialog, click **Feed all to panel**, or mark result checkboxes and choose **Feed selected to panel**, to keep results as a virtual list in the source panel. The list supports pattern selection, Multi-Rename, and copy/move options using each item's original path. **Remove from list (keep files)** removes rows without deleting files; **Return to folder** leaves the list. See [search results and reusable file lists](commander-file-operations.md#search-results-and-reusable-file-lists) for importing, exporting, and saving lists between sessions.

---

## Sync Engine

The sync engine keeps a local folder and a remote folder in two-way sync automatically.

### Setting Up a Sync Pair

1. Go to **Sync** in the sidebar or menu.
2. Click **Add Sync Pair**.
3. Choose a local folder and a remote folder.
4. Set a sync direction: **Two-way**, **Local → Remote only**, or **Remote → Local only**.
5. Optionally configure include/exclude glob patterns (e.g., `*.tmp`, `node_modules/**`).
6. Click **Save**. The first sync runs immediately.

### Selective Sync

To exclude specific remote subfolders from being downloaded locally, edit the sync pair and add exclusion patterns. Files matching exclusion patterns remain in the cloud and appear as placeholder files locally.

### Placeholder Files (Files On-Demand)

When placeholders are enabled for a sync pair, cloud-only files appear as `.crispcloud` stub files on disk. Open a placeholder to trigger an on-demand download. Files not accessed for a configurable number of days are automatically evicted back to placeholder state.

### Conflict Resolution

When a file is modified on both sides before a sync:
- **Newest wins** (default): the more recently modified version overwrites the other.
- **Local wins**: the local version always wins.
- **Remote wins**: the remote version always wins.
- **Keep both**: both versions are preserved with `_local` and `_remote` suffixes.
- **Manual**: a conflict dialog appears for each file to choose.

Change the policy per sync pair in its settings.

### Offline Mode

Operations performed while offline (uploads, deletes, renames, creates) are queued in a local database. On reconnect, the queue replays in chronological order. Before replaying an upload, CrispCloud checks the remote modification time to detect conflicts.

### Bandwidth Scheduling

In sync pair settings, toggle **Sync only on Wi-Fi** to prevent mobile data usage. Set **Sync hours** to restrict syncing to a time window (e.g., 22:00–06:00 for overnight runs).

### Background Sync

On desktop, a system tray icon shows sync status. On Android, a foreground service handles long-running syncs with a persistent notification. On iOS, Background App Refresh triggers syncs via BGTaskScheduler.

---

## Client-Side Encryption

The optional encryption wrapper encrypts file contents before upload and decrypts them on download. It applies to transfers through the active encrypted connection; provider-native encryption, background jobs and other connections are separate. File names and sizes remain visible in ordinary setup.

### Enabling Encryption

1. Open a provider connection dialog that offers client-side encryption. The dedicated Azure/B2 dialogs do not expose this option.
2. Toggle **Enable client-side encryption**.
3. Enter a passphrase. CrispCloud derives a 256-bit AES-GCM key using PBKDF2 with 100,000 iterations.
4. Save the displayed 24-word recovery phrase somewhere safe and re-enter it to confirm. Cancelling does not activate file encryption.
5. Connect. The exact confirmed key encrypts uploads and decrypts downloads through this connection. Keep separate connections for existing plaintext files.

The key is kept for this session only. Restarting and entering the same passphrase generates a different salt/key; it will not recover old files. Import the original recovery phrase, raw key or backup bundle to regain access. Logging out or changing providers retires the active encryption session.

When encryption is active, a lock icon appears in the status bar. Provider capabilities that require server-side access (sharing, thumbnails, full-text search) are automatically disabled for encrypted connections.

### Encrypted Filenames

Ordinary setup encrypts file contents and leaves filenames visible. The code contains filename-encryption helpers, but the current connection dialog does not offer a filename-encryption toggle or a complete encrypted-name directory view.

### Key Management

Go to **Settings → Encryption → Manage Keys** (or press the key icon when connected to an encrypted provider) to open the Key Management dialog.

- **Export master key**: copies the 64-character hex key to the clipboard for backup.
- **BIP39 mnemonic**: generates a 24-word recovery phrase from your master key. Store this offline.
- **Import key**: restore a key from hex or a 24-word mnemonic.
- **Backup bundle**: export readable JSON containing the key mnemonic, salt and an encrypted verification value. The bundle itself is **not encrypted**; protect it like the raw key.

Disable an active encryption connection before importing a different key, and retain the old key for its existing files. Importing the current key again does not replace it.

Losing your key means losing access to all encrypted files. Always keep a BIP39 backup.

---

## Themes and Appearance

Open **Settings → Appearance** or press **Ctrl+,** to change visual settings.

### Built-in Themes

| Theme | Description |
|-------|-------------|
| System | Follows OS light/dark mode |
| Light | Clean light interface |
| Dark | Standard dark mode |
| OLED Black | True black backgrounds for OLED screens |
| Nord | Arctic, blue-toned palette |
| Dracula | Purple-accented dark theme |

### Accent Color

Choose from 11 preset accent colors or pick a custom color. The accent color affects buttons, selection highlights, and active indicators.

### Font

Adjust font size (10–20 px) and family in Settings → Appearance → Font. Changes apply to file lists, the editor, and the preview pane.

### Android: Material You

On Android 12+, enable **Material You** in Settings → Appearance to derive the color scheme from your wallpaper dynamically.

---

## Command Palette

Press **Ctrl+Shift+P** to open the command palette. Type to filter all available actions:

- File operations: New Folder, Upload, Download, Delete, Rename, Move, Copy
- Navigation: Go To, Refresh, Toggle Preview, Toggle Tree, Go Up
- Connection: Connect, Disconnect, Switch Provider, Add Sync Pair
- View: Change Theme, Change Layout, Toggle Thumbnails, Open Settings
- Search: Find Duplicates, Saved Searches, Full-Text Search
- Security: Enable Encryption, Manage Keys, App Lock Settings

Use **Arrow keys** to navigate and **Enter** to execute. The palette is context-aware: it shows only actions valid for the current selection and panel.

---

## Keyboard Shortcuts

### Navigation

| Shortcut | Action |
|----------|--------|
| Enter / F4 | Open folder or file |
| Backspace / Alt+Left | Go up one level |
| Ctrl+G | Go to folder dialog |
| Ctrl+R | Refresh directory listing |
| Tab | Switch active panel |
| Space | Toggle preview pane |

### File Operations

| Shortcut | Action |
|----------|--------|
| F2 | Rename selected file |
| F5 / Shift+F5 | Open copy options for selected files |
| F6 | Open move options for selected files |
| Ctrl+C / Ctrl+X | Copy / cut the captured file selection |
| Ctrl+V | Paste through reviewed copy/move options |
| F7 | Create new folder |
| F8 / Delete | Delete selected files |
| Ctrl+Z | Undo last action |
| Ctrl+A | Select all |
| Ctrl+M | Multi-Rename |
| Numpad + / Numpad - | Select / deselect by wildcard or regex |
| Numpad * | Invert selection |
| Ctrl+Shift+L | Import a file list |
| Ctrl+Click | Toggle selection |
| Shift+Click | Range select |

### Tabs

| Shortcut | Action |
|----------|--------|
| Ctrl+T | New tab |
| Ctrl+W | Close tab |
| Ctrl+Tab | Next tab |
| Ctrl+Shift+Tab | Previous tab |

### Application

| Shortcut | Action |
|----------|--------|
| Ctrl+Shift+P | Command palette |
| Ctrl+F | Search / filter |
| Ctrl+, | Settings |
| Ctrl+Shift+C | Connect dialog |
| Ctrl+S | Save (in editor) |

---

## Bookmarks and Recent Locations

### Bookmarks

- **Add bookmark**: navigate to a folder, then click the star icon in the toolbar or right-click → **Bookmark This Folder**.
- Bookmarks appear in the tree sidebar under **Favorites**.
- Right-click a bookmark to remove it or rename it.
- Bookmarks persist across app restarts.

### Recent Locations

The **Recent** section in the tree sidebar lists the last folders you visited, across all providers. Click any entry to navigate there directly. Recent locations also persist across restarts.

---

## Share Links

For providers that support sharing (Google Drive, OneDrive, Dropbox, Nextcloud), right-click a file or folder → **Share Link** to open the share dialog.

- **Anyone with link**: generates a public URL.
- **Specific people**: (Google Drive, OneDrive) restrict access to email addresses.
- **Expiry date**: (Dropbox, OneDrive) set a link expiration date.
- **Password protection**: (Dropbox) add a password to the shared link.

The generated URL is copied to your clipboard. On mobile, the native share sheet is offered as an alternative.

---

## Batch Rename

Select files, then press **Ctrl+M** or choose **More actions → Multi-Rename**. The normal multi-selection context menu also opens this tool through **Batch Rename**.

Use name and extension masks, counters, literal or regex find/replace, and case conversion to compose new names. Advanced controls select the CrispCloud/Total Commander/Double Commander mask dialect, dates, variables, and collision numbering. You can chain transformation steps, edit proposed names, import names from clipboard or a text file, reorder rows, or exclude items before execution. The preview shows original paths, proposed names, and validation errors. See [Multi-rename](commander-file-operations.md#multi-rename) for examples, presets, and undo.

---

## Archive Support

### Extract

Right-click a `.zip` file → **Extract Here**. CrispCloud downloads the archive, extracts it to the current directory on the destination side, and removes the temporary download.

### Create Archive

Select files or folders → right-click → **Create ZIP**. CrispCloud compresses the selection and uploads the resulting `.zip` to the current remote directory.

---

## FUSE Mounted Drives

Mounted drives are experimental and read-only. On macOS, open **Mount as Drive**, select a backend, and choose an empty local mount point. CrispCloud does not install or bundle these runtimes.

- **macFUSE FSKit** is the automatic choice. Install macFUSE separately and enable its file-system extension in System Settings under **Login Items & Extensions → By Category → File System Extensions**. Its kernel-extension backend is a separate explicit choice; Apple silicon requires Reduced Security for that backend.
- **FUSE-T** must be installed and selected explicitly. Choose its NFS or SMB backend; CrispCloud asks you to confirm non-commercial FUSE-T use for each mount. Review [FUSE-T's license](https://github.com/macos-fuse-t/fuse-t/blob/main/License.txt). System-wide NFS options can interfere with the NFS backend; SMB is an alternative.
- **rclone NFS** uses a separately installed rclone and its own configured remote, such as `work:documents`; it does not reuse CrispCloud connections. The read-only NFS endpoint listens on the local machine and can be accessed by local processes.

The macFUSE and FUSE-T bridge supports files over 64 MiB for Azure Blob using bounded range reads. Other providers and encrypted connections, including encrypted Azure connections, use a whole-file download and retain the 64 MiB limit. If a provider does not report the size in advance, that fallback may briefly exceed the limit before rejection. Separate Azure range requests do not provide a snapshot if the remote file changes while open. The limit does not apply to rclone's independent NFS backend.

Live local-fixture tests passed for macFUSE FSKit, FUSE-T NFS and SMB, and rclone NFS. Finder, real cloud remotes, and the signed sandboxed app still need end-to-end testing. Linux and Windows mounting is not implemented. See the [developer mount test guide](macos_mount_testing.md) for details.

---

## CLI Companion

The `crisp` CLI provides headless access to all connected providers for scripting and CI/CD use.

### Installation

```bash
dart pub global activate crisp_cloud_cli
```

Or download a prebuilt binary from the Releases page.

### Commands

| Command | Description |
|---------|-------------|
| `crisp connect <provider>` | Store credentials for a provider |
| `crisp ls <path>` | List directory contents |
| `crisp upload <local> <remote>` | Upload a file or directory |
| `crisp download <remote> <local>` | Download a file or directory |
| `crisp sync <local> <remote>` | Run a two-way sync |
| `crisp search <query> <path>` | Search filenames |
| `crisp share <remote-path>` | Generate a share link |
| `crisp providers` | List configured connections |
| `crisp config` | View or set CLI configuration |

### Options

- `--json`: output results as newline-delimited JSON for piping into `jq` or other tools.
- `--progress`: write progress to stderr so stdout stays clean for piping.

### Shell Completions

```bash
crisp completion bash >> ~/.bashrc
crisp completion zsh  >> ~/.zshrc
crisp completion fish > ~/.config/fish/completions/crisp.fish
```

### Config File

`~/.config/crispcloud/config.yaml` stores named connection profiles. Credentials are stored separately in the OS keychain and referenced by profile name.

---

## Security Features

### App Lock

Go to **Settings → Security → App Lock** to set a PIN or password. CrispCloud locks itself after a configurable idle timeout. Biometric unlock (Face ID, Touch ID, fingerprint) is available on supported devices.

### Proxy

Go to **Settings → Network → Proxy** to configure an HTTP or SOCKS5 proxy. CrispCloud also auto-detects `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` environment variables. All provider connections route through the proxy.

### Certificate Pinning

CrispCloud ships with pinned SPKI SHA-256 hashes for Google, Microsoft, Dropbox, and Amazon endpoints. Connections to these services fail if the certificate does not match the pinned hash, protecting against MITM attacks even with a compromised system trust store.

### Custom CA Certificates

Go to **Settings → Network → Custom CAs** to import PEM, CRT, or CER certificate files. This is useful in enterprise environments with a private PKI or when using self-signed certificates on private servers.

### TLS Version

Go to **Settings → Network → TLS** to set the minimum TLS version:
- **TLS 1.2** (default): secure and compatible
- **TLS 1.3** (strict): maximum security, may break older servers
- **Any**: allow all versions (not recommended)

### Secure Clipboard

Passwords and keys copied from CrispCloud are automatically cleared from the clipboard after 30 seconds.

### Screenshots

On mobile, go to **Settings → Security → Disable Screenshots** to prevent the OS screenshot API and app switcher from capturing the app's contents.

### Audit Log

Go to **Settings → Security → Audit Log** to view a local record of all operations (connect, upload, download, delete, rename). The log can be exported as JSON-lines or cleared.

---

## Backup Engine

CrispCloud's backup engine (planned for v2.0) will schedule incremental backups from a local folder to any cloud provider:

- **Scheduled backups**: daily, weekly, or custom cron schedule
- **Incremental**: only changed files are uploaded (tracked via local SQLite)
- **Versioning**: keep the last N snapshots
- **Integrity verification**: periodic hash checks against stored checksums
- **Restore wizard**: browse snapshots, restore individual files or entire backups
- **Independent encryption**: encrypt backups regardless of the provider's own encryption

---

## Automation Rules

Automation rules (planned for v2.0) will allow event-driven file operations:

- **Folder watch**: auto-upload when files appear in a watched local folder
- **Scheduled transfers**: built-in cron for recurring uploads or downloads
- **Rule engine**: match files by name pattern, size, or extension and apply an action ("upload `*.pdf` from `/Scans/` to Filen `/Documents/`")
- **Webhooks**: call an external URL when an event occurs
- **Conflict policy**: each rule defines its own conflict handling so automation never blocks on a prompt

## Terminal

The embedded terminal opens with **View → Toggle Terminal** or the terminal
button in the title bar. Desktop builds use a real shell where the operating
system and distribution permit it. The macOS App Store build uses the built-in
shell, as do Android, iOS, and the browser. The browser shell has an in-memory
filesystem.

- Copy terminal output with the **Copy all** button in the terminal header, or
  select text and use the right-click menu / Cmd+C.
- Paste into the command line with Cmd+V.
- On macOS the terminal inherits only folders granted through **Browse** or
  **Grant Access**. Grant a parent folder to work across a project tree.
- Root-owned files remain unreadable even after a folder grant; open them with
  Finder, `sudo`, or an elevated/unsandboxed build.

See [terminal.md](terminal.md) for the platform/distribution matrix, sandbox
details and the built-in command list.
