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

- **Code workspace:** F3, F4 and code previews share syntax colours, with a black canvas in dark mode. Empty directories keep their `..` navigation entry. Image mode is offered for recognized image content rather than every unknown file.
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
- **Background archive jobs:** archive creation and edited-archive publication share the Operations queue, with pause/resume/stop, priority, scheduling and conflict reservations. Native compression runs in a worker; closing its dialog leaves the job running. Saved creation recipes support reviewed restart without stored passwords. See [archive queue behavior and verification](docs/archive-operation-queue.md).
- **Archive workflows:** browse archives like folders; create and review edits to ZIP/7z/TAR, comic and unsigned Java aliases, compressed TAR/files, AR/CPIO/XAR and eligible data ISOs. Original-source verification and recovery protect publication.
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
- **CLI companion** (`crisp`): headless S3/SFTP/SMB/WebDAV operations, PDF tools and shell completions; see [CLI capabilities](cli/README.md). Filen/Internxt CLI adapters are planned.
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

For local Mac testing, `bash tool/build_macos_release.sh --no-pub` embeds the current source revision; `bash tool/sign_macos_local.sh` uses the installed development profile and `bash tool/macos_startup_smoke.sh build/macos/Build/Products/Release/CrispCloud.app 10` checks startup. The alternate Linux reader parity/canary branches remain separate pending native focus/selection acceptance; this integration retains the guarded isolated host and its runtime assertions.

Release `v1.2.0` (`1.2.0+13`) uses the multi-platform GitHub Release workflow for macOS, Windows, Linux, Android, iOS and Web archives. Store uploads use explicit `ios-v*` or `macos-v*` tags and their separate release workflows; the GitHub iOS archive is unsigned.

The `1.2.1` integration uses the pinned [CrisperBooks](https://github.com/CrispStrobe/crisperbooks) facade for edit transactions, portable reading, structured prose, appearance and reading data, with its matching reader/converter packages. That historical snapshot used vendored provenance; the current consumer is verified as described below. File/account persistence stays in CrispCloud. F4 audio editing accepts ID3-prefixed FLAC without changing the original and exports edited PCM WAV copies.

The `1.2.2` release also vendors the matching Quds reports facade. Standalone editor resolution uses the same engine/reports source as the app, avoiding the hosted-package conflict exposed by the release gate.

On macOS the browser uses a unified native title-bar toolbar beside the window controls and app title. The Find/Filter indicator reserves its own row below the file viewport. Defaults now show F8 for Delete (the Delete key remains an alias) and F9 for Terminal, including the function-key bar. NXC/NQC source uses C-family highlighting. Viewer and editor highlighting uses bounded, state-preserving chunks for large source, including generated Dart files; syntax coloring is painted only for visible viewer rows.

The final `1.2.2` integration includes lazy ISO/HFS+/DMG and package-container reading, bounded streamed archive writers, the current canonical DOC parser and CrisperBooks foreground read-aloud controls. The standalone parser mirror is verified separately from Quds, with obsolete mirror files removed. The canonical Word picture gate uses its controller-default fixture and strict 94.45-point native layout; historical 12-point workflow reports keep their original source scope.

The `1.2.3` integration consumes CrisperBooks directly at one immutable Git revision, including the complete browser Kindle export engine, worker lifecycle guards, local read-aloud controls and qualified Linux input behavior. Duplicate local packages are removed. `docs/ebook-source-manifest.json` binds the complete upstream tree; `python3 tool/verify_ebook_sources.py` checks the exact bytes Pub resolves for all four packages. GitHub release binaries and the separate iOS/macOS TestFlight uploads use this same source snapshot.

TestFlight uses the separate `ios-release.yml` and `macos-release.yml` signing/upload workflows. `testflight-external.yml` accepts an explicit `MAC_OS` or `IOS` platform and the exact reviewed build number for beta review after processing. The older app-local Linux candidate PR is superseded by the canonical CrisperBooks reader; its recovery branch is retained.

The `1.2.4` integration includes portable ASCII CPIO, classic RPM payloads, stored/MSZIP CAB archives and bounded PBZX/XAR payload handling. It also consumes the current canonical DOC shape/textbox/metafile/schema fixes, strengthens attached-content checks before clearing Word conversion warnings, preserves executable bits when refreshing the parser mirror, and backports complete Internxt trash names without replacing existing host transport guards. The previous TestFlight upload requests were cancelled so this newer snapshot can be validated first.

The previous 1.2.3 full GitHub suite completed with 10,066 passing tests and two integration failures: a missing container caption translation and a shortcut test that assumed F9 was unused. Both are corrected in 1.2.4; the 45 related caption/command-entry tests pass. The new archive cohort passes 271 tests and the combined Office host cohort passes 126 tests. The final release gate still runs the complete suite.

The `1.2.5` integration adds portable LZ4, LZMA-alone, Lzip and UNIX compress handling, cancellable archive integrity reports, and staged copies between archives. Current standalone legacy Word parser acceptance covers 773 Dart tests, 156 Python controls and 217 independently validated DOCX exports. Quds and the app consume the same canonical parser source; CrisperBooks remains pinned to its reviewed complete Git tree. Internxt receipt mutations gain the canonical one-shot API while preserving host transport patches.

The `1.2.6` follow-up includes the subsequently published native-backed parser corrections: corroborated shared header shapes and retraction of the experimental textbox table-depth reset. Canonical acceptance covers 809 Dart tests, 162 Python controls and 218 independent SDK-validated DOCX outputs. Word conversion inspection now ignores comment references nested inside attached objects.

The `1.2.7` integration includes the completed moves within an archive workspace, 33 creation choices including UNIX compress/TAR.Z and preserved legacy CPIO profiles. It consumes the final bounded native header/footer recovery and all retained continuation receipts. The new archive cohort passes 244 tests; canonical parser acceptance covers 826 Dart tests, 162 Python controls and 222 SDK-validated DOCX outputs. CrisperBooks is pinned to the corrected workspace and native-platform acceptance harnesses; its reader/converter production code remains the reviewed implementation.

The `1.2.8` integration restores selection and visibility of the containing archive when leaving it with `..`. It includes reviewed native archive-to-archive moves, destination-verified recovery, UNIX compress/TAR.Z creation, reviewed one-way directory-to-archive synchronization and qualified streamed native TAR creation. The canonical DOC parser includes floating-table anchors and padding, exact note endings, independent shared header/footer textbox instances, bounded internal hyperlinks, separate script font slots and stored drawing wrap clearances. Its README describes supported behavior and remaining fidelity limits.

File marks survive ordinary cursor clicks. Shift-click marks a visible range; Ctrl/Cmd-click toggles individual marks, and Shift-arrows toggle the rows being left. Find arrows navigate matching entries without discarding the query. Local selections can be handed to other desktop apps through native macOS file URLs, Windows Unicode file-drop data and Linux GTK URI lists; cancellation preserves the sources. Pane-to-pane drags retain the existing captured-source review workflow. Cloud/archive drag-out and native mobile/browser handoff still require separate export support.

The integrated archive regression runs 1,769 tests across 75 files, with five
conditional large-test skips. Four separate opt-in application cases passed:
creation/publication of ZIP, 7z and TAR.GZ beyond 2 GiB, plus TAR.GZ edit, review,
publication and reopen beyond 2 GiB. Desktop drag-out offers the complete local
selection through native macOS, Windows and Linux formats; cloud/archive members
still require a local copy. Hosted platform builds and TestFlight remain separate
release gates.

Android release packaging regenerates Flutter plugin registration for release
mode, matching the Android CI build. The manual `Rebuild Android release asset`
workflow can repair an APK for an existing tag only after verifying successful
application CI for that exact source commit; it retains release signing and
artifact evidence and does not recreate the release or replace other assets.


Development version `1.2.9+22` consumes the qualified canonical parser's
section/gutter direction, manual-break justification compatibility and bounded
explicit textbox-border frame conversion. Shared Office sources match Quds
`6d6e77d` and parser `cd9ab85` exactly across 1,219 managed files. The source
parser passes 931 Dart tests; the synchronized app Office gate passes 1,165
mandatory engine tests and 202 host tests, with complete host instrumentation.
These counts overlap the larger suites.

The integration also adds native streamed editing for eligible data ISO,
RAR5 Store/CBR and canonical HFSX data-volume DMG profiles, with reviewed
folder changes and preservation checks. Creation offers 35 choices. These
formats retain their documented size, metadata and profile limits; bootable,
hybrid, encrypted and other unsupported disk images remain read-only.
See [container profiles and verification](docs/archive-iso-rar-dmg.md). Apple's
`hdiutil` independently verified a generated data-image fixture on this Mac;
large hosted acceptance uses a fixed source checkpoint before release.

Cloud connections can stay open simultaneously in the two panes. See
[provider setup](docs/PROVIDER_SETUP.md#multiple-simultaneous-cloud-connections)
for session behavior and [Nextcloud browser requirements](docs/PROVIDER_SETUP.md#browser-access-webpwa)
for CORS, HTTPS and server configuration limits.
