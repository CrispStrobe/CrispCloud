# CrispCloud

**Cross-platform dual-panel cloud file manager** built with Flutter. Open-source, privacy-first, running on macOS, Windows, Linux, Android, iOS, and Web/PWA.

14 cloud providers. 4,000+ tests. Block-level delta sync. End-to-end encryption. 9 UI languages, with English fallback for untranslated messages.

## Providers

| Provider | Features |
|----------|----------|
| **Filen.io** | E2E encrypted, WebCrypto on web |
| **Internxt** | Decentralized encrypted storage |
| **SFTP** | Native streaming, key auth |
| **WebDAV** | Standard operations |
| **SMB / NAS** | Native SMB2/3 browsing, streaming reads/writes, file operations, signed connections and required SMB3 encryption by default |
| **S3** | Presigned URLs, SSE-S3/KMS/C, 8 storage classes, delta sync (Range GET) |
| **FTP/FTPS** | Standard + TLS |
| **Google Drive** | OAuth2, shared drives, starred files, file versions, Google Docs export (6 formats) |
| **OneDrive / SharePoint** | Graph API, delta sync, shared libraries (SharePoint sites + drives) |
| **Dropbox** | Shared folders, content hash, Paper docs (list + export) |
| **Nextcloud** | Block-level delta sync (server app), chunked upload v2, ETag tracking |
| **pCloud** | Random-access I/O (pread/pwrite), delta sync |
| **Azure Blob** | SAS tokens, blob operations |
| **Backblaze B2** | S3-compatible + native API |
| **Hetzner Storage Box** | SFTP/WebDAV/FTP access |

## Block-Level Delta Sync

For large files (VeraCrypt containers, disk images, databases), CrispCloud uploads only the 4 MB blocks that changed instead of the entire file.

- **Algorithm:** Adler-32 weak hash + SHA-256 strong hash per block
- **Providers:** Nextcloud (via [server app](https://github.com/CrispStrobe/crispcloud-delta-sync)), pCloud (native pread/pwrite), S3 (Range GET download)
- **Savings:** A 500 MB file with 8 MB changed = 98.4% bandwidth saved

### Desktop Client Forks

We also maintain patched Nextcloud and ownCloud desktop clients with delta sync support, settings UI, activity display, and notifications:

- **[Nextcloud Desktop (delta sync)](https://github.com/CrispStrobe/nextcloud-desktop)** — [download binaries](https://github.com/CrispStrobe/nextcloud-desktop/releases/tag/delta-sync-latest) (Linux, Windows, macOS)
- **[ownCloud Desktop (delta sync)](https://github.com/CrispStrobe/owncloud-client)** — [download binaries](https://github.com/CrispStrobe/owncloud-client/releases/tag/delta-sync-latest) (Linux, Windows, macOS)
- **[Server App](https://github.com/CrispStrobe/crispcloud-delta-sync)** — PHP app for Nextcloud 25+ / ownCloud 10.11+, plus Dart CLI demo

## Key Features

- **Flexible layout:** independent dual/single panes, an account-aware folder tree, detailed and compact lists, grids, and hierarchical columns with separately scrollable ancestor folders
- **Recoverable navigation:** source-bound history per tab, history menus, recent locations that retain their storage identity, and reopening closed tabs with their view and history
- **Keyboard workspace:** searchable shortcut customization with conflict checks; command palette, shortcut help, native menus and action buttons reflect saved bindings. Text fields, editors and terminals retain their own input.
- **Folder drop review:** drag marked files onto a folder in a list, grid or current column; hold Shift for a move. Source accounts and the destination are checked before the existing copy/move review opens. See [workspace controls and acceptance](docs/workspace-ux.md).
- **Storage analyzer:** interactive treemap and sunburst for local and cloud folders, folder drill-down, largest files, extension filters, faster background native scans, and lossless saved scans for offline browsing. Cancellable scans retain explicit partial results; saved history survives full rescans. See [storage analysis](docs/storage-analyzer.md) for controls, measured performance, size semantics and limits.
- **Image gallery and tiles:** adjustable thumbnails, image-only gallery, natural sorting and catalog filters, 0–5 ratings, color labels, favorites and tags. Fullscreen filmstrip/slideshow, linked 2–4-image comparison, image-editor handoff, batch conversion/resizing and contact-sheet export. See [image gallery](docs/image-gallery.md) for controls, format coverage and limits.
- **Encryption:** AES-256-GCM file encryption, Filen/Internxt E2EE, and Cryptomator/VeraCrypt format helpers. See the [crypto audit](docs/crypto-audit.md) for supported operations and remaining limits, and the [store export guide](docs/export-compliance.md) for the no-report release route.
- **Sync engine:** background sync, conflict resolution, selective sync
- **Backup engine:** scheduled backups with versioning
- **Preview pane:** images (zoom/pan), SVG, PDF (page navigation), syntax-highlighted code (30+ languages), markdown, CSV/TSV tables, DOCX/XLSX/PPTX/ODT text, fonts (TTF/OTF/WOFF2), audio/video
- **Archive browsing:** browse ZIP/TAR/TGZ files like folders (including on web)
- **Built-in editors:** F4 text/code and hex editors with explicit chooser and handoff, bounded edit history, and save/recovery tied to the original file and account. Text editing includes syntax highlighting, line numbers, encoding and newline controls; F3 also previews archive members
- **Interactive terminal:** desktop PTY/Windows ConPTY, a built-in shell for sandboxed macOS, and SSH sessions with ANSI colors, full-screen programs, live resizing, raw control keys, scrollback, and mobile extra keys. Browser SSH uses your own secure WebSocket gateway. [Terminal design, licensing, and platform support](docs/terminal.md)
- **Office editing:** DOCX/XLSX/PPTX editing through the patched Quds engine, with independent Word round-trip verification and archive members kept view-only
- **PDF editor:** annotate, fill standard PDF forms, edit page content, and organize pages from F4, the file menu, or the preview pane. Includes conflict checks, save-copy/export recovery, and password-protected input; see [PDF editing](docs/pdf-editor.md) for supported behavior and limits.
- **Web support:** full file operations (open folder, copy, move, delete, download) via File System Access API with Safari/Firefox fallback
- **CLI companion** (`crisp`): headless S3/SFTP/WebDAV operations, 9 commands, shell completions
- **Plugin system** with local REST API and automation rules
- **Experimental macOS mounts:** read-only macFUSE FSKit, explicitly selected FUSE-T, or a separately configured rclone NFS remote. Runtime installation, limitations and current test status are described in the [mount guide](docs/USER_GUIDE.md#fuse-mounted-drives). Linux and Windows mounting is not yet implemented.
- **Unified Settings:** one surface for language, theme/accent, file-list fonts, quick search, cache, proxy/provider networking, accessibility, privacy and advanced options
- **9 languages:** EN, DE, FR, ES, PT, ZH, JA, KO, AR — persisted in-app language switch, ~256 localized strings
- **Accessibility:** 48dp touch targets on mobile, Semantics on file list items, tooltips on all buttons

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.47+; pinned to 3.47.8 in `.fvmrc`)

### Build and Run

```bash
git clone https://github.com/CrispStrobe/CrispCloud.git
cd CrispCloud
flutter pub get
flutter run -d chrome    # Web
flutter run -d macos     # macOS
flutter run -d windows   # Windows
flutter run -d linux     # Linux
```

For a macOS release build that records its version and git commit for the
About dialog, use:

```bash
tool/build_macos_release.sh
```

### Tests

```bash
flutter test              # deterministic unit/widget suite
flutter test --tags live --run-skipped       # credentialed provider tests
flutter test --tags benchmark --run-skipped  # load-sensitive benchmarks
flutter analyze           # errors fail CI; warning debt is tracked separately
```

## Architecture

Modular adapter pattern with provider-agnostic interfaces:

- **`CloudStorageClient`** — abstract interface for all 14 providers
- **`DeltaSyncService`** — block-level diff engine (Adler-32 + SHA-256)
- **`TransferQueue`** — concurrent transfers with exponential backoff retry
- **Copy/move job management** — path reservations, scheduled starts, queue and
  bulk controls, truthful job progress and journaled recovery; see
  [transfer queue behavior](docs/transfer-queue.md).
- **`SyncEngine`** — background sync with conflict resolution
- **`PanelProvider`** — dual-panel state management (Riverpod)

See [the architecture guide](docs/ARCHITECTURE.md) for state and provider
boundaries, [the security architecture](docs/SECURITY_ARCHITECTURE.md) for the
threat model, and [PLAN.md](PLAN.md) for the feature roadmap.

## Keyboard Shortcuts

These are the defaults. On macOS, Command is the primary modifier for the
Control shortcuts below. Recorded custom modifiers remain exact. Open
**Settings → Customize shortcuts**, or find that action in the command palette,
to change a binding, review conflicts or restore defaults.

| Key | Action |
|-----|--------|
| `Tab` | Switch panels |
| `Enter` | Open folder / execute file |
| `Backspace` | Parent folder |
| `Alt+Left` / `Alt+Right` | Back / forward within the active tab |
| `Ctrl+T` / `Ctrl+W` | New / close tab |
| `Ctrl+Shift+T` | Reopen the most recently closed tab |
| `Ctrl+G` | Go to a path in the current storage source |
| `Ctrl+Shift+P` | Search commands and shortcuts |
| `Ctrl+K` | Connect to cloud storage |
| `Ctrl+A` | Select all |
| `Ctrl+C` / `Ctrl+X` | Capture files for clipboard copy / cut |
| `Ctrl+V` | Review a paste into the current folder |
| `F5` / `F6` | Review copy / move to the other pane |
| `F2` | Rename |
| `F3` / `F4` | View / edit |
| `F7` | New folder |
| `F8` / `Delete` | Delete |
| `Ctrl+F` | Filter the current listing |
| `Alt+F7` | Recursive file and content search |
| `Ctrl+R` | Refresh the active pane |
| `Ctrl+M` | Batch rename review |
| `Ctrl+F3` / `Ctrl+F4` / `Ctrl+F5` / `Ctrl+F6` | Sort by name / extension / date / size |
| `Ctrl+Alt+P` | Toggle the preview pane |
| `Ctrl+Shift+3` | Toggle the folder tree |
| `Ctrl+Shift+2` | Cycle file views |
| `Space` | Select + advance cursor |
| `Ctrl+U` | Swap pane sources |

## License

AGPL-3.0. See [LICENSE](LICENSE).

Not affiliated with any cloud provider. All trademarks belong to their respective owners.

### SMB / NAS

In the installed app, choose **SMB / NAS** and enter `smb://host/share/`,
a username (or `DOMAIN\user`) and password. SMB3 encryption is required by
default. Turn it off only for an older NAS on a trusted network; signing remains
required. SMB1 and browser connections are unsupported. Saved credentials use
the existing secure store. The provider supports nested folders, uploads,
resumable downloads, moves, renames and deletion (without a trash folder).

The native transport is shared with CrisperPlayer in `packages/crisp_storage`.
To run the isolated SMB file-manager test, install Python `impacket` and use
`CRISPER_SMB_PYTHON=/path/to/python flutter test test/smb_client_adapter_test.dart`.

## Internxt download regression checks

The adapter stages SDK 0.2.3 downloads under their real remote filename before
publishing the requested local name. This fixes previews and copies whose
temporary filename differs, including the SDK’s extension-free path aliases.
A private inbox avoids touching unrelated files with the remote basename. Normal
folder access uses a same-volume rename; selected-file sandbox access falls back
to a private temporary directory. Interrupted transfers preserve the destination.

Run the isolated SDK and filesystem checks with
`flutter test test/internxt_download_path_test.dart test/internxt_rewire_test.dart`.
The local live check uses only `INTERNXT_LOGIN_TESTS` and `INTERNXT_PW_TESTS`:

```sh
python3 test/run_internxt_download.py --env-file /path/to/test.env
```

The launcher refuses CI execution. Its live test creates a UUID-named folder,
checks renamed downloads and SDK path aliases, then moves only its owned folder
to trash. Existing files and personal-account credentials are unused. On
19 October 2026, all eleven isolated checks and the live account check passed.
