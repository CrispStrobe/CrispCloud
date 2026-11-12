# CrispCloud User Guide

This guide describes the bundled application. Availability depends on the platform, connected account and storage capabilities. Disabled commands and review messages explain the current boundary. Help is bundled in English, German and French and works offline.

**Contents:** [Start](#getting-started) · [Connections](#supported-providers) · [Navigation](#two-panel-interface) · [Operations](#file-operations) · [Recovery](#backup-engine) · [Search](#search-and-filters) · [Archives](#archive-support) · [Commands](#cli-companion) · [Security](#security-features)

<a id="getting-started"></a>
## Getting started

1. Open CrispCloud and choose a local folder or a connection. Grant access to the folder when the operating system or browser requests it.
2. Open **Connect**, select a provider and enter the details for that account. Keep account labels descriptive when using several accounts.
3. Open a second location in the other pane or a new tab. Either pane can show local or remote storage; its position does not identify its account.
4. Select a small set of files, choose Copy and review the original source, destination and conflict policy before starting.

Persistent credentials use the configured storage backend. If the operating-system credential store is unavailable, Settings offers an encrypted file vault with a master password or session-only storage. Session-only connections require credentials again after the application closes.

Browser and mobile folder access depends on grants and platform support. Reconnect the original account or restore the original grant when a source is unavailable. A different account with a similar folder name does not restore that operation.

<a id="supported-providers"></a>
## Connections and providers

The connection picker is the authoritative list for your build. Adapters include SFTP, FTP with plain or protected modes, WebDAV, S3-compatible storage, Backblaze B2, Azure Blob, Google Drive, OneDrive, Dropbox, SMB and other account services exposed by that picker. Capabilities differ: copying does not imply sharing, permissions, native moves or resumable uploads.

Multiple connections can remain open. Cross-account transfers normally pass through the application. Direct server-to-server FTP transfer is unavailable. Native FTP/SSH/SMB transports are not browser transports.

For FTP, select the server's security mode explicitly. Explicit TLS secures the control connection before login; implicit TLS begins before the greeting. Secure modes protect passive data connections and validate certificates. Failed TLS negotiation stops the connection.

FTP download resume requires server restart support and a verified original file. Recovery validates the full source and existing partial bytes before requesting a suffix; verification can read the source again. Unsupported restart, a changed source or unconfirmed partial data prevents resume. FTP upload resume is unavailable. See [Recovery](#backup-engine).

<a id="two-panel-interface"></a>
## Panes, navigation and selection

Each pane has its own source, path, selection and tabs. Use breadcrumbs, Back/Forward history or Go to Folder to navigate. **Backspace** goes up or leaves an archive. **Tab** changes the active pane when a text field or editor does not own the keyboard.

Choose details, brief or thumbnail/grid views. Custom columns and saved view profiles control visible details. Hidden files can be toggled from the view controls; showing them does not grant additional permissions.

Selection by wildcard or regular expression can add or remove marks. Size, date and content criteria are available in the relevant selection/search dialogs. Remember Selection and Restore Selection operate on the original tab and storage. Missing or replaced items are skipped; restoring marks does not undo file changes.

Synchronized browsing maps relative navigation between two chosen roots. It stops when the counterpart is missing, inaccessible or no longer the original source. It navigates without creating folders or copying contents. Use [folder synchronization](#sync-engine) to change files.

<a id="file-operations"></a>
## Copy, move, rename and delete

Choose Copy or Move, then review planned items, the actual destination, name rules, exclusions and conflict policy. **Start** runs work in the foreground. **Queue** and **Schedule** are available for recoverable jobs. Resolve review errors before execution.

Conflict review can show bounded image previews and file details. Choose an available action deliberately: skip, replace, keep both, rename or verified resume. Append joins contents; it does not mean resume. Unsupported metadata preservation or unsafe write capabilities are reported.

Moves remove originals only after required copy checks and requested metadata steps succeed. A directory move can finish partly; skipped or failed source items remain. Cancellation stops remaining work and does not roll back completed items. Read per-item outcomes in activity and history.

Incoming desktop or browser drops capture the original source and destination before review. Temporary browser uploads and other ephemeral sources use foreground work when they cannot be safely recovered. Dragging out to another native application is a separate platform capability.

Delete and trash behavior depends on storage support. Check the deletion review and Trash History where available. Undo is operation-specific; permanent deletion is not generally undoable. See [batch rename](#batch-rename) and [recovery](#backup-engine).

<a id="tabbed-interface"></a>
## Tabs, workspaces and the gathering stack

Open tabs to keep several folders available. Reopen a closed tab or save a workspace to restore a layout and its locations. Restoring a location still requires the original account or local grant.

The gathering stack holds references to files and folders collected from several locations. Add the active selection, review the stack, remove or reorder references, then choose a destination pane and Copy or Move. Review shows the captured destination and original sources.

The stack stores references, not duplicate bytes. Identical references are deduplicated by source identity and path. Different accounts may contain identically named files. Transfer proceeds through reviewed source groups; a later group can fail after an earlier one succeeds. Only confirmed successful items are removed. Skipped, canceled, changed or unavailable items remain. A folder is removed only after its required subtree outcomes succeed.

<a id="preview-pane"></a>
## Preview and the internal viewer

Use the preview pane for quick inspection and **F3** for the internal viewer. Renderers include text, hex/binary, images, HTML, PDF, supported documents and audio/video. Media decoding depends on the platform. Preview support does not imply editing support.

Text controls include font size, line display and encoding choices. UTF-8/16/32 and explicit legacy encodings are supported. Choose CP437 or Windows-1252 deliberately; ambiguous bytes do not trigger an automatic guess.

Large-file text/hex views use bounded pages. Remote staging has a 2 GiB ceiling; rich documents and archive members have smaller budgets. A limit message requires a supported external workflow or a smaller input. The viewer does not promise unlimited files or extracted content.

Native temporary-copy preparation stops after two minutes without successfully written data or six hours overall. Cancel also stops preparation while a remote read is stalled; an unresponsive provider may take longer to confirm that its connection has closed. CrispCloud checks the captured account and reported version metadata before and after reading. When a provider cannot enforce a fixed version, these checks do not guarantee an immutable snapshot.

<a id="built-in-editor"></a>
## Editing files

Use **F4** for the built-in text editor and **Shift+F4** to choose an available editor. The text editor provides syntax highlighting, find/replace, folding, line navigation, wrapping and encoding/line-ending controls.

Saving stays bound to the originally opened account and file. If that source changed, disconnected or lost its grant, review the conflict or reconnect before saving. Automatic save, where enabled, uses the same checks; a failed save leaves the document dirty. Do not assume a fixed autosave interval or that an open editor has already uploaded changes.

Saving a character that the selected legacy encoding cannot represent fails instead of silently substituting it. Choose Unicode when necessary. Text comparison and merge have their own size limits; binary comparison reads complete streams.

On supported native desktop builds, select one verified remote file and choose **Edit with external editor**. **External remote editing** in Tools stores the editor preference and lists retained sessions. Use an installed executable's absolute path and include `{file}` once as a complete argument. Prepare the private local copy, then review the original source, executable and actual arguments before launching. External process launch is unavailable in browser/mobile builds and the Mac App Store build.

Each remote editing file is limited to 64 MiB. Automatic upload is initially off and requires explicit consent in the launch review. It is currently available for Dropbox files with a verified account, file ID and revision. Other providers with bounded download support can supply an editable copy for independent export; they do not gain an original-file upload action. A save in the external editor changes the local copy first. CrispCloud reports the original saved only after a confirmed revision-guarded upload, and keeps any newer local save pending.

You may browse elsewhere or close the dialog while a consented watcher remains active. Use Pause to stop it. Disconnecting or replacing the original account blocks further uploads. A remote conflict requires reviewing the current remote revision before replacement; an uncertain response requires reconciliation, without an unconditional retry. Export creates an independent local copy and never marks the original saved.

Retained sessions and unsent edits survive dialog closure and app restart. Recovered sessions start paused: select the original remote file and explicitly reconnect that session before publishing again. Recovery does not relaunch an editor or restore automatic-upload consent. Close every external window using the local copy before confirming its deletion from the retained-session list.

On a native desktop, select two files in one pane, or one file in each pane, and choose **Compare with external tool**. A file's context menu also offers this action when exactly one file with the same name exists in the other pane. **External comparison tools** stores separate text and image tool settings. Choose an installed executable by its absolute path and use `{left}` and `{right}` once each as complete arguments; no shell expansion is performed. Review the captured sources and actual arguments before launching.

Both comparison inputs are private copies, including local files. Each input is limited to 256 MiB, preparation/final validation has a 15-minute deadline, and at most eight comparisons are retained. Changes in the external tool never update the originals. Close every external window using the copies, then explicitly release that session from **External comparison tools**. Closing a dialog or restarting the app retains the copies; recovery lists them for cleanup and does not relaunch a tool. A changed or disconnected source requires a new selection and review.

<a id="search-and-filters"></a>
## Search, filters and duplicate files

Filter narrows the current list. Search traverses selected roots with name patterns, regular expressions, extensions, size, dates and contents. Check roots and options before starting. Results retain their original storage identity when opened or used in another operation.

Literal plain-text search streams contents. Regular-expression, document and archive searches have extraction/traversal budgets; partial results report reached limits. Arbitrary nested or encrypted archive content is not universally searchable. Application search is separate from the operating-system search index.

Duplicate search narrows candidates by size, then verifies complete contents with SHA-256. Matching names or sizes alone do not establish duplicates. Review groups before deleting.

Storage analysis provides visual size maps and saved reports. A partial scan is labeled. An offline report describes its captured scan; it does not prove the directory still has those sizes.

<a id="sync-engine"></a>
## Folder comparison and synchronization

Choose actual source and target folders, compare them and inspect proposed actions. Local and remote folders can be compared recursively. One-way and two-way synchronization require an explicit plan and conflict decisions.

Pay attention to deletions and differing versions. A missing file on one side does not by itself prove that deleting the other copy is intended. Saved relationships retain location identity; execution still checks live sources.

Archive contents are not general synchronization endpoints: directory-to-archive synchronization remains unavailable, while copying between archives uses the separate reviewed workflow described in [Archives](#archive-support).

<a id="client-side-encryption"></a>
## File encryption and keys

Where the connection dialog offers client-side encryption, enable it before connecting and confirm the displayed recovery phrase. The active wrapper encrypts uploaded file contents. Ordinary setup leaves names and sizes visible. Dedicated Azure/B2 dialogs do not expose this setup option.

Keep the exact confirmed key or recovery phrase. Entering the same passphrase after a restart creates a different salt/key and does not recover older encrypted files. Restore the original phrase, raw key or backup bundle. Signing out or changing providers retires the active encryption session.

Key Management supports export/import. A backup bundle contains readable key material and is not itself encrypted; protect it like the raw key. Disable an active encrypted connection before importing another key, and retain the old key for its existing files.

Provider sharing, previews or search that require plaintext can be disabled on encrypted connections. File encryption is separate from TLS/SSH and archive passwords. Losing the original key can make files unrecoverable.

<a id="themes-and-appearance"></a>
## Appearance and menus

Settings offers themes, colors and file-list fonts. Pane view profiles control columns and display choices. Check custom layouts with larger text and a narrower window.

The configurable main menu stores references to application and user commands. Edit its structure, preview, then apply. Import/export and reset are available. Settings and recovery controls remain reachable outside the editable tree.

Custom toolbar commands launch an approved executable with argument templates using the captured directory and selection. Review literal arguments before execution. A saved command does not grant filesystem access or turn a remote path into a local one.

<a id="command-palette"></a>
## Quick Open

Open the command palette with its configured shortcut; the default is **Ctrl+Shift+P**. Search commands, favorites, workspaces, connected sources, available devices and saved rename presets.

A saved path restores its original storage context. Unavailable accounts or grants receive an explanation. A rename preset opens review for the captured selection; choosing it does not immediately rename files.

Commands respect the active input owner. Editors and terminals keep their keyboard commands while focused. Close a modal dialog or focus the file pane to use browser commands.

<a id="keyboard-shortcuts"></a>
## Keyboard control

**F1** opens the shortcut reference and links to this guide. Customize shortcuts in shortcut settings. The reference displays current bindings. On macOS the primary modifier follows the platform convention; command-entry insertion uses literal Control as labeled.

| Default | Action |
| --- | --- |
| F2 / Shift+F6 | Rename |
| F3 / F4 | View / edit |
| F5 / F6 | Copy / move review |
| F7 | New folder |
| Ctrl+R | Refresh |
| Ctrl+M | Multi-rename |
| Ctrl+G / Ctrl+L | Go to folder |
| Alt+F7 / Ctrl+F | Search / filter |
| Ctrl+T / Ctrl+W | Open / close tab |
| Ctrl+Shift+P | Quick Open |
| Ctrl+Shift+O | Command entry |

In the browser, **Ctrl+Enter** opens an item in the other pane. Inside command entry, **Ctrl+Enter** inserts captured filenames and **Ctrl+Shift+Enter** inserts full paths. These scopes are separate. Text fields, editors and terminals retain their editing/input keys.

<a id="bookmarks-and-recent-locations"></a>
## Favorites and recent locations

Save frequently used paths as bookmarks, including source-bound remote paths and paired locations. Recent history returns to previously visited folders. Workspaces save layouts, tabs and locations.

Import/export can move configuration between installations. Automatic favorites synchronization across computers is not provided. Credentials and local grants still need to be established on each installation.

<a id="share-links"></a>
## Sharing

Use Share when the connected provider exposes supported link operations. Review audience and expiry options where available. Generated links follow provider permissions; copying a path is not publishing a share link.

A local file inside an independently synchronized folder does not automatically resolve to a provider share link. Open the original provider connection for its sharing feature. Encrypted connections can restrict sharing.

<a id="batch-rename"></a>
## Rename tools and file utilities

Multi-rename supports masks, regular expressions, counters, pipelines, editable names and presets. Preview the whole mapping and resolve collisions before applying. Rename History records supported recovery and whole-batch undo; interruptions require review.

Split/combine uses manifests, content hashes and separate recovery. Keep the manifest and all parts together. Checksums verify contents; they do not establish who created a file.

Encode/decode supports UUE, XXE and single-part Base64 MIME. Choose a new output name explicitly. Decoding validates the format and publishes verified output to a capable destination. Multipart/quoted-printable MIME and unsupported destination backends are unavailable.

<a id="archive-support"></a>
## Archives

Supported archives and disk images open like folders, with bounded previews and extraction. Reading includes ZIP/7z/TAR families, AR, CPIO, XAR, ISO and supported HFS+/HFSX/DMG trees. Read-only access also includes supported RAR, RPM, CAB (stored/MSZIP), Lzip, UNIX compress, CRX and Apple package payloads. Format and metadata limits remain explicit; recognizing a container does not make it writable or authenticate its publisher.

**Create archive…** uses native local selections and a new local output name. Its **31 choices** cover ZIP/7z/TAR and CBZ/CB7/CBT; six compressed TAR and six single-file formats using gzip, bzip2, XZ, Zstandard, LZ4 or LZMA; AR; CPIO newc, odc and binary little-/big-endian; XAR; unsigned JAR/WAR/EAR; KMZ; and ISO/HFSX/DMG data images. Single-file compression takes one regular file; AR takes flat files; KMZ needs a top-level KML document. Only ZIP/CBZ and 7z/CB7 offer passwords; 7z/CB7 can also hide filenames. CPIO defaults to newc; choose an older profile only for compatibility. Legacy CPIO has no payload checksum or encryption and rejects values that do not fit its fields.

Eligible native local archives have a reviewed update workflow. This includes supported ZIP/7z/TAR families, AR, CPIO, unsigned XAR/Java archives, KMZ and data ISO profiles; individual unsupported structures make a file read-only. Existing HFS/DMG images and signed packages are not rebuilt. DEB permits only coordinated replacement of externally prepared payloads. Edit, rename, remove and create-folder actions change a draft. **Save archive** prepares the whole container for review; **Publish verified archive** applies the verified result. Closing the review leaves the original unchanged. Eligible CPIO rewrites retain their original layout and inspected metadata.

To rearrange members in one open archive workspace, select files or folders and choose **Move within archive…**. Navigate to an existing destination folder, then choose **Stop without changes**, **Keep both**, or **Skip conflicting items**. Keep both generates new names; destination folders are never merged or replaced. **Stage move** changes the working copy, including subfolders and empty directories; **Save archive** reviews and applies it. Moving a folder into itself is refused. The move stays within the currently opened archive, including when that archive is nested.

To add ordinary files, open the destination archive directory in the other pane and use Copy/Move or paste. Review collisions and the complete container before publication. A move publishes and verifies first, then removes only source files whose identity and contents still match. Source directories and files that cannot be safely removed remain listed in the result. Cancelling an archive paste preserves its cut selection.

To **copy between archives**, open one in each pane, select source members and use **F5** or **Copy**. The destination must be an eligible local archive in the native app. Save or discard a source draft first; a clean workspace's Copy out action also accepts an archive destination. The review captures separate routes and passwords, retains supported times, permission bits and empty folders, and uses the destination archive's protection. Ownership, ACLs, resource forks, links and signatures are not imported. The source remains intact. Two routes to the same physical outer archive are refused; use the workspace action above for rearrangement. Moving between two archives remains unavailable.

In F3's archive listing, choose **Test archive** to read regular members, check the integrity information available from their readers and calculate SHA-256 values. Checked, failed, skipped and unprocessed members are reported separately; **Copy report** copies the details. Cancellation or limits cannot appear as a complete successful check. This does not repair data or authenticate a publisher. LZMA-alone, UNIX compress and legacy CPIO have no stored payload checksum; other formats may omit optional checksums.

Updates preserve supported metadata and the original protection policy. Unsupported, mixed or ambiguous ZIP protection is refused; eligible AES-256 protection is retained. Nested archives keep separate passwords per level and publish through the outer container. Passwords are not saved. Ordinary editing and creation retain limits of **64 MiB per file and 256 MiB total content/output**, with entry/path/depth limits; compressed TAR is limited to 64 MiB decoded, including headers. Updates allow at most eight nested archive levels. Fresh native **ISO/HFSX/DMG creation has a separate streamed 2 GiB image-output limit**; this does not enlarge existing-image editing limits. These data images do not preserve a complete application filesystem or resource forks.

After interrupted publication, choose **Archive publication recovery** in Tools. Open the original parent folder if the archive path is temporarily absent. Recovery can verify and publish the recorded candidate or restore the original backup to a vacant path; keep both until the outcome is confirmed. Unsaved drafts are not restored after an app restart. Remote/browser archives remain readable where supported, but creation and publication there, directory synchronization and durable background packing remain unavailable.

<a id="fuse-mounted-drives"></a>
## Experimental mounted drives

macOS mounting is experimental and read-only. Open Mount as Drive, select an available backend and choose an empty local mount point. Install required runtimes separately; they are not bundled. Follow their installation, permission and license instructions.

The default bridge uses macFUSE FSKit; FUSE-T and separately configured rclone NFS have distinct requirements. A separate remote does not inherit an application connection. Local mount endpoints can be accessed by local processes.

The bridge uses bounded Azure Blob range reads where supported; whole-file fallback retains a 64 MiB limit. Separate ranges are not an immutable snapshot. Other operating systems lack this mounting implementation. Local fixtures do not establish signed-app/live-provider acceptance. Read the [mount setup and test guide](https://github.com/CrispStrobe/CrispCloud/blob/main/docs/macos_mount_testing.md) before setup.

<a id="cli-companion"></a>
## Program commands

Command entry is available for verified native local folders on supported desktop builds. Choose a saved program or type a program name/absolute executable path and literal arguments. Spaces separate arguments; JSON double quotes preserve spaces inside one argument. Shell substitutions, pipes and redirections are not evaluated.

The dialog captures the folder and selection when opened. Filename/path insertion uses those captured items. Review shows the resolved executable, working directory and complete arguments. Launch rechecks context; navigation, account/grant changes or changed executable settings require another review.

Command entry and the [terminal](#terminal) are distinct workflows. Web/mobile and sandboxed builds restrict host process launch. This guide does not prescribe a separately published command-line package or global installation command.

<a id="security-features"></a>
## Credentials, transport and access

Choose OS credential storage, an explicit encrypted file vault or session-only mode in Settings. Back up the vault password and encryption keys separately. Credentials do not substitute for a local access grant.

TLS/SSH verification and provider policies protect supported connections. Invalid certificates or changed host identity require deliberate review; secure mode must not silently become plaintext. The HTTP custom-CA setting does not change FTP trust.

Proxy settings apply to supported native HTTP/HTTPS traffic. HTTP, SOCKS4, SOCKS4a and SOCKS5 have distinct DNS/authentication options. Direct FTP/SSH/SMB and browser traffic are outside this setting. Check the route for the connection actually used.

Filesystem permissions, scoped grants and platform restrictions still apply. Showing hidden files or using a terminal does not enable a root/UAC broker. Inspect activity/audit records for failures; avoid sharing credentials or private paths in reports.

<a id="backup-engine"></a>
## Transfer history and recovery

Open Transfer Queue and Recovery to inspect jobs, phases and per-item results. A restored job does not start automatically. Reconnect the original source/destination, review the saved plan and choose an available retry/restart action.

Recovery verifies source identity, original contents where required and saved partial prefixes before reuse. A successfully journaled native streamed download can retain a private partial file after interruption. Changed or corrupt partial data is not silently appended. Failed retries can leave earlier recovery evidence for review.

Completed copies can be verified and remaining metadata/source cleanup finished separately. A changed destination requires review. Cancellation leaves completed work in place; failed required verification retains a move's source.

The journal is recovery evidence, not a versioned backup of all data. Keep independent backups for irreplaceable files. Rename, trash and split/combine have their own recovery views.

<a id="automation-rules"></a>
## Queues and scheduling

Queue admits reviewed recoverable jobs for background execution inside the running application. Reorder or change priority where available. Pausing queue admission does not instantly stop active jobs; individual pause is cooperative and waits for checkpoints.

Schedule chooses an earliest start while the application runs. It is not an OS wake service or general recurring automation. After restart, interrupted jobs require recovery review and original-account rebinding.

Per-operation client-stream pacing is available. It is not a separate global upload/download wire limit; provider-native server-side operations are not paced by that stream. Consult capability and progress messages.

<a id="terminal"></a>
## Terminal workflows

The embedded terminal shows its backend. Native desktop builds can use a host PTY or Windows ConPTY where supported. Sandboxed/mobile builds use restricted runtimes; browser sessions do not become a host shell. iOS uses its embedded command runtime. SSH terminals require their native or gateway connection.

Open in Terminal launches the configured external terminal only for verified local folders on supported desktop builds. Review the application and captured working directory. Remote URLs and collection results do not silently become a local directory.

Terminal commands can change files outside a reviewed operation plan. Use Copy/Move review and recovery when you need per-item checks and durable history.
