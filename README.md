# CrispCloud

**Cross-platform dual-panel cloud file manager** built with Flutter. Open-source, privacy-first, running on macOS, Windows, Linux, Android, iOS, and Web/PWA.

Local, cloud and network storage. Automated unit, widget and native protocol tests. Block-level delta sync. End-to-end encryption. 9 UI languages, with English fallback for untranslated messages.

Credential-storage recovery identifies the selected store, its path where available,
the failed operation and native status, with copyable original stack traces.
Locked custom macOS keychains use the system unlock dialog with the saved file
grant; their passwords stay in macOS. Startup and unlock failures offer Retry,
access restoration for a genuinely missing grant, and
an explicit choice of another store without deleting the original credentials.
See [credential storage](docs/credential-storage.md).

New cloud connections retain the previous pane's live account, including when
connecting another account of the same provider. Additional accounts are currently
session-only. Nextcloud web connections provide endpoint and browser diagnostics;
server CORS still needs configuration. See the [live verification and limits](docs/cloud-issues-96-98-verification.md).

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

- **Code workspace:** F3, F4 and code previews share syntax colours, with a black canvas in dark mode. Text viewers offer optional wrapping (`Alt+Z`) where supported; long minified lines use bounded rendering windows. Empty directories keep their `..` navigation entry. Image mode is offered for recognized image content rather than every unknown file.
- **Flexible layout:** independent dual/single panes, an account-aware folder tree, detailed and compact lists, grids, and hierarchical columns with separately scrollable ancestor folders
- **Recoverable navigation:** source-bound history per tab, history menus, recent locations that retain their storage identity, and reopening closed tabs with their view and history
- **Path favorites:** a `*` menu at the top right of each pane opens searchable, grouped saved locations. Ctrl+Shift+B opens the active pane's picker. The editor supports grouping, ordering and reviewed JSON import/export while retaining each favorite's original storage account. See [path favorites](docs/path-favorites.md).
- **Edit and comparison commands:** configurable browser menus include clipboard actions, copy names/full paths, grouped selection, and Compare Directories. The latter compares the two verified pane listings and selects files in the active pane using names, dates and sizes. The separate folder comparison dialog retains its review workflow.
- **Keyboard workspace:** searchable shortcut customization with conflict checks; command palette, shortcut help, native menus and action buttons reflect saved bindings. Text fields, editors and terminals retain their own input.
- **Commander selection and Find:** Shift-click ranges, Cmd/Ctrl marks and Shift-arrow toggling preserve the mark set while ordinary clicks move the cursor. Find arrows traverse matches. Local selections can be copied into other apps by native drag-out on macOS, Windows and Linux; cloud/archive members first need a local copy. See [workspace controls and platform limits](docs/workspace-ux.md#selection-find-and-external-dragging-in-128).
- **Folder drop review:** drag marked files onto a folder in a list, grid or current column; hold Shift for a move. Source accounts and the destination are checked before the existing copy/move review opens. See [workspace controls and acceptance](docs/workspace-ux.md).
- **Storage analyzer:** interactive treemap and sunburst for local and cloud folders, folder drill-down, largest files, extension filters, faster background native scans, and lossless saved scans for offline browsing. Cancellable scans retain explicit partial results; saved history survives full rescans. See [storage analysis](docs/storage-analyzer.md) for controls, measured performance, size semantics and limits.
- **Image gallery and tiles:** adjustable thumbnails, image-only gallery, natural sorting and catalog filters, 0–5 ratings, color labels, favorites and tags. Fullscreen filmstrip/slideshow, linked 2–4-image comparison, image-editor handoff, batch conversion/resizing and contact-sheet export. See [image gallery](docs/image-gallery.md) for controls, format coverage and limits.
- **Encryption:** AES-256-GCM file encryption, Filen/Internxt E2EE, and Cryptomator/VeraCrypt format helpers. See the [crypto audit](docs/crypto-audit.md) for supported operations and remaining limits, and the [store export guide](docs/export-compliance.md) for the no-report release route.
- **Sync engine:** background sync, conflict resolution, selective sync
- **Backup engine:** scheduled backups with versioning
- **Preview pane:** images (zoom/pan), SVG, PDF (page navigation), syntax-highlighted code (30+ languages), markdown, CSV/TSV tables, DOCX/XLSX/PPTX/ODT text, fonts (TTF/OTF/WOFF2), audio/video
- **CSV/TSV spreadsheets:** viewer and text editor offer **Import as spreadsheet…** alongside text editing. Preview comma, semicolon or tab-separated data, select the text encoding, and create an editable XLSX copy in Quds. Quoted multiline cells and blank rows are retained. Values remain text by default; optional number recognition preserves leading-zero and long identifiers. The original file and existing XLSX files are never overwritten.
- **BASIC/VBA:** `.bas` and `.vba` use the same syntax highlighting in the viewer, preview pane and text editor.
- **XML content types:** ACSM fulfilment tokens, OPF/NCX ebook metadata, GPX/KML, XSPF, RSS/Atom and XML schemas open in the XML tree/source viewer and use XML syntax highlighting in the editor.
- **Background archive jobs:** archive creation and edited-archive publication share the Operations queue, with pause/resume/stop, priority, scheduling and conflict reservations. Native compression runs in a worker; closing its dialog leaves the job running. Saved creation recipes support reviewed restart without stored passwords. See [archive queue behavior and verification](docs/archive-operation-queue.md).
- **Archive workflows:** browse archives like folders; create and review edits to ZIP/7z/TAR, comic and unsigned Java aliases, compressed TAR/files, AR/CPIO/XAR and eligible data ISOs. Original-source verification and recovery protect publication.
- **Filesystem images:** browse, preview and extract supported FAT, ext2/ext3/ext4, NTFS and MBR/GPT images through the archive tools. These readers are read-only, retain raw partition access and refuse unsupported or unclean layouts; see the [ext profile](docs/archive-ext-profile.md) and [NTFS profile](docs/archive-ntfs-profile.md).
- **Commander archive tools:** separate archives per selection, batch extraction with masks and collision previews, batch integrity reports, checked installed 7-Zip/RAR creation and bounded 7z dictionary/thread/solid controls. Read complete numbered 7z sets and supported unsigned Windows SFX payloads. See [workflows and remaining parity boundaries](docs/archive-commander-workflows.md).
- **Large native archives:** eligible unencrypted ZIP/ZIP64, 7z and TGZ workflows use bounded streams and private file snapshots with an explicit 8 GiB budget. Standalone codecs have processed members above 2 GiB; the [commander comparison and verification record](docs/archive-parity-large-continuation.md) separates measured codec results and remaining limits. The integration also exercises creation, publication, editing, extraction and F3 in Flutter; final platform acceptance is tracked by release CI.
- **Extended file formats:** decoded EML/Outlook MSG viewing, including compressed RTF bodies and attachments; formatted RTF previews; legacy PPT/PPS/POT previews with native text fallback; formatted legacy DOC/DOT previews; protected DOCM/DOTM/DOTX rich editing; and Autodesk KBDX XML viewing/source editing. See [format coverage and limits](docs/file-format-viewers.md).
- **Legacy Word conversion:** the maintained [legacy_doc_parser](https://github.com/CrispStrobe/legacy-doc-parser) supplies portable formatted previews and separate, reviewed DOCX/DOCM copies. Supported installed Word/LibreOffice conversions and their PDF previews remain available, as does explicit text-only conversion. Originals stay unchanged; macros and embedded objects are never executed by the built-in parser. See [conversion support and limits](docs/legacy-word-conversion.md).
- **KeePass databases:** F3 views and F4 edits existing KDBX databases with password/key-file unlock, group management, entry moves, protected custom fields, entry history restoration, explicit password reveal/copy, automatic locking and encrypted saves to the original source. See [KeePass support and limits](docs/keepass.md).
- **Disk images and packages:** create streamed data ISO, HFSX and UDIF DMG images; browse supported disk filesystems and package containers, with guarded prebuilt Debian payload replacement. Format-specific creation/editing limits and read-only boundaries are in [archive format coverage](docs/archive-format-coverage.md).
- **Built-in editors:** F4 text/code and hex editors with explicit chooser and handoff, bounded edit history, and save/recovery tied to the original file and account. Text editing includes syntax highlighting, line numbers, encoding and newline controls; F3 also previews archive members
- **Binary header inspection:** F3 → Hex → Inspect structure explains selected PNG, WebAssembly, ELF, DOS/PE, Mach-O, ZIP and Java header fields and highlights their bytes. The bounded Dart adaptation uses only selected Apache-2.0 File Viewer source; see [scope, provenance and limits](docs/file-viewer-apache-integration.md).
- **Selected offline document engines:** bounded WordPerfect, CHM, legacy Excel, PowerPoint and PostScript previews, plus local XML schema validation and XSLT tools. MBOX indexes separate messages and retains the existing email attachment handling. The selected Apache/MIT/MPL source, runtime grants and platform limits are documented in [document previews](docs/file-viewer-selected-documents.md).
- **Timed lyrics:** F3 opens `.lrc` files as a selectable timeline with metadata, repeated line times, offsets and optional word timing. Lyrics shows source order; Source and Hex retain the complete text and bytes. The standalone Apache-2.0 parser adds no dependencies; see [LRC preview and limits](docs/file-viewer-lrc-integration.md).
- **Interactive terminal:** desktop PTY/Windows ConPTY, a built-in shell for sandboxed macOS, and SSH sessions with ANSI colors, full-screen programs, live resizing, raw control keys, scrollback, and mobile extra keys. Browser SSH uses your own secure WebSocket gateway. [Terminal design, licensing, and platform support](docs/terminal.md)
- **Office editing:** DOCX/XLSX/PPTX editing through the patched Quds engine, with independent Word round-trip verification and archive members kept view-only
- **PDF editor:** annotate, fill standard PDF forms, edit page content, and organize pages from F4, the file menu, or the preview pane. Includes conflict checks, save-copy/export recovery, and password-protected input; see [PDF editing](docs/pdf-editor.md) for supported behavior and limits.
- **Ebooks:** EPUB editing that preserves inline formatting, enhanced Kindle/FictionBook/comic reading and EPUB import, portable Linux search and bookmarks, offline browser Kindle metadata updates, native Kindle export, validated separate FictionBook FB2/FBZ export, and a retained text fallback. See [ebook reading and editing](docs/ebooks.md) for controls, platform differences and limits.
- **Web support:** full file operations (open folder, copy, move, delete, download) via File System Access API with Safari/Firefox fallback
- **CLI companion** (`crispcloud`, with `crisp` compatibility alias): headless S3/SFTP/SMB/WebDAV operations, largest-file/folder scans (`crispcloud du PATH`), persistent Rust/SQLite catalogues and Cathy/Catfish CAF interchange, PDF tools and shell completions; see [CLI capabilities](cli/README.md). Filen/Internxt CLI adapters are planned.
- **Plugin system** with local REST API and automation rules
- **Experimental macOS mounts:** read-only macFUSE FSKit, explicitly selected FUSE-T, or a separately configured rclone NFS remote. Runtime installation, limitations and current test status are described in the [mount guide](docs/USER_GUIDE.md#fuse-mounted-drives). Linux and Windows mounting is not yet implemented.
- **Unified Settings:** one surface for language, theme/accent, file-list fonts, quick search, cache, proxy/provider networking, accessibility, privacy and advanced options
- **9 languages:** EN, DE, FR, ES, PT, ZH, JA, KO, AR — persisted in-app language switch, ~256 localized strings
- **Accessibility:** 48dp touch targets on mobile, Semantics on file list items, tooltips on all buttons

## Shared components and validation

Office editing consumes the [Quds fork](https://github.com/CrispStrobe/quds_office_suite), while legacy binary Word parsing is maintained in [legacy-doc-parser](https://github.com/CrispStrobe/legacy-doc-parser). `tool/office_fidelity_manifest.json` and `packages/legacy_doc_parser/UPSTREAM.json` bind the managed files and parser source. The integrated source includes both November Office follow-up checkpoints and the completed worksheet-local-name, bookmark-copy and slide-arrangement expansion. Historical native rendering reports identify their original source snapshots; they do not automatically certify later edits.

Use the Flutter version in `.fvmrc`. Run `flutter analyze --no-fatal-warnings --no-fatal-infos`, `flutter test`, and `bash tool/check_office_fidelity.sh` after shared-source changes. The Office gate includes package inventories, independent validators and coverage collection receipts. See [Office fidelity](docs/office-fidelity.md) for scope and limits, [external editing](docs/external-remote-editing.md) for retained drafts and conditional publication, and [archive endpoints](docs/archive-endpoints.md) for supported archive operations.

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
threat model, [Dart/Rust storage engines](docs/STORAGE_ENGINE_ARCHITECTURE.md)
for the current split and proposed Filen/Internxt reuse, and [PLAN.md](PLAN.md)
for the feature roadmap.

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
| `F9` | Show / hide Terminal |
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

AGPL-3.0. See [LICENSE.txt](LICENSE.txt).

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

## Local and hosted release checks

For local Mac testing, `bash tool/build_macos_release.sh --no-pub` embeds the current source revision. `bash tool/sign_macos_local.sh` uses the installed development profile, and `bash tool/macos_startup_smoke.sh build/macos/Build/Products/Release/CrispCloud.app 10` checks startup. The desktop integration harness exercises real temporary ext/NTFS images, CSV-to-XLSX publication and collision recovery, and offline CAF import/search/folder navigation through the native Rust-backed GUI:

```sh
flutter test integration_test/native_storage_viewer_test.dart -d macos
```

GitHub `v*` release tags trigger macOS, Windows, Linux, Android, iOS and Web artifacts plus standalone CLI bundles. New releases remain drafts until every platform build succeeds and all eleven required binary assets are uploaded and nonempty. Reruns preserve existing releases and their assets. The generic iOS archive is unsigned. Signed store uploads use the separate `ios-release.yml` and `macos-release.yml` workflows. `testflight-external.yml` selects an explicit platform and reviewed build number after processing. Local acceptance, hosted builds and TestFlight are separate gates; a tag or queued workflow does not mean downloadable binaries exist. Pages and Vercel expose the deployed source in `deployment.json`.

The Android release build regenerates plugin registration for release mode. The manual Android repair workflow requires successful application CI for the exact source and preserves the release's other assets. Source fingerprints verify the current Quds engine/editor/reports, standalone legacy DOC parser and pinned CrisperBooks packages; historical validation records keep their original revisions and are not certification of later trees.

Current container support includes reviewed native archive moves/recovery, directory-to-archive synchronization and supported ISO/RAR/DMG editing. Unsupported, encrypted, bootable or hybrid image profiles remain read-only. See [container profiles](docs/archive-iso-rar-dmg.md), the [format matrix](docs/archive-format-coverage.md), and the bounded [ext](docs/archive-ext-profile.md) and [NTFS](docs/archive-ntfs-profile.md) reader contracts.

Cloud connections can remain open simultaneously in both panes. See [provider setup](docs/PROVIDER_SETUP.md#multiple-simultaneous-cloud-connections) and [Nextcloud browser requirements](docs/PROVIDER_SETUP.md#browser-access-webpwa) for session behavior, CORS, HTTPS and server configuration.

## Offline catalogues and CLI

Tools → Catalogues provides SQLite catalogue browsing, Cathy/Catfish CAF import/export, paged search and size rankings, cancellation and safe refresh. See [catalogue usage and limits](docs/catalogues.md). The primary CLI command is `crispcloud`; `crisp` remains an alias. CrispSorter uses `crispsorter` and its lightweight `crispcat` companion.

The shared CAF codec is the standalone MIT-licensed [`crispcat-format` Rust crate](https://github.com/CrispStrobe/CrispSorter/tree/main/crates/crispcat-format), consumed from an exact reviewed source snapshot. SQLite remains the queryable working index; CAF files are portable interchange/snapshot exports and are optional beside a database. No Python runtime or full CrispSorter application stack is required by the codec.
