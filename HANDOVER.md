# Handover Prompt for Continuing CrispCloud Development

> Copy this entire file as a prompt to a new Claude Code session to continue development.

---

## Context

You are continuing development on **CrispCloud**, a cross-platform Flutter cloud file manager at `/mnt/akademie_storage/CrispCloud`. Read `PLAN.md` for the full roadmap and `HISTORY.md` for what's been done.

The project uses the **Adapter pattern** (`CloudStorageClient` interface) with **9 providers** (Filen, Internxt, SFTP, WebDAV, S3, FTP, Google Drive, OneDrive, Dropbox). State management is **Riverpod 2** with 8 focused providers. Tests are in `test/`, ~35+ files, ~250+ unit tests.

## What's Been Done (don't redo these)

### Foundation (Phase 1)
- Secure credentials via `flutter_secure_storage` + auto-migration from plaintext
- `SecureStorage` abstraction with `InMemorySecureStorage` test double
- Structured logging (`Log` service with ring buffer + export)
- Centralized `formatters.dart` (formatBytes/Date/Duration/Speed)
- File decomposition: screen split to 4 files, context menu split, search dialogs extracted
- **Riverpod 2 state management**: `AppState` split into `authProvider`, `panelProvider(side)`, `transferProvider`, `errorProvider`, `searchProvider`, `syncProvider`, `activePanelProvider`, `showPreviewProvider`

### Performance (Phase 2)
- `uploadStream`/`downloadStream` on `CloudStorageClient` with SFTP native streaming
- `TransferQueue` with 3 concurrent transfers, exponential backoff retry, cancel
- Queue wired into `transferProvider.uploadFiles()`/`downloadFiles()`
- `ListView.builder` with `itemExtent: 64` for virtual scrolling

### Providers (Phase 3) — 9 total
- **S3** adapter (715 lines): SigV4 signing, path/virtual-hosted auto-detect, XML parsing
- **FTP/FTPS** adapter: `ftpconnect`, TLS toggle, stateful connections
- **Google Drive** (~450 lines): Drive REST API v3, OAuth2 browser flow, path-to-ID caching
- **OneDrive** (~380 lines): Microsoft Graph v1.0, OAuth2 browser flow, path-based addressing
- **Dropbox** (~400 lines): Dropbox API v2, OAuth2 browser flow, cursor-based pagination
- 7 capability flags on all providers

### Sync Engine (Phase 4)
- **Database**: drift/SQLite with 3 tables (SyncPairs, SyncEntries, OfflineQueue)
- **Engine**: two-way sync with 5 conflict policies (newest/local/remote/keep-both/manual), 3 directions
- **Filesystem watcher**: `package:watcher` with 5s debounce for real-time change detection
- **System tray**: `system_tray` on desktop with context menu + status tooltip
- **UI**: Sync Manager dialog, pair CRUD, watch toggle

### UI/UX (Phase 5)
- **Preview pane**: image (zoom/pan), text/code (40+ extensions), metadata — Space key toggle
- **Status bar**: connection status, item count, selection, transfer progress, sync status
- **Tabs**: multiple tabs per panel, pin, close, duplicate, Ctrl+T/W
- **Themes**: 6 built-in (System/Light/Dark/OLED/Nord/Dracula) + accent color picker
- **Command palette**: Ctrl+Shift+P with type-to-filter
- **Breadcrumbs + selection bar**: clickable path segments, editable address bar
- **Draggable panel splitter**: resizable two-panel layout, double-tap to reset
- **Tree view sidebar**: toggleable folder tree (like VS Code), click to navigate
- **Grid/Gallery view**: toggle between list and icon grid per panel
- **Drag & drop between panels**: LongPressDraggable + DragTarget for upload/download
- **Mobile swipe**: horizontal gesture to switch panels

### Power Features (Phase 6)
- **Batch rename**: 4 modes (find/replace/regex, numbering, prefix/suffix, extension)
- **Archive support**: extract .zip, create .zip from selected files
- **Command palette**: context-aware action search

### Security (Phase 7)
- **Encryption**: `EncryptionService` (AES-256-GCM, PBKDF2) + `EncryptedStorageWrapper`
- Wired into connection dialog (toggle + passphrase) and authProvider

## What Needs to Be Done (in priority order)

### 1. Power User Features — HIGH PRIORITY
- **Built-in editor** (6.1): `code_text_field` or `re_editor`, edit remote files in-place
- **SSH terminal** (6.2): embed `xterm` for SFTP connections
- **Shareable links** (6.4): provider-native share link generation
- **Version history** (6.5): show/restore file versions (GDrive, Dropbox, S3, OneDrive)
- **Duplicate finder** (6.6): hash-based dedup across providers

### 2. Security Additions
- **Key management** (7.1): export/import master key, BIP39 mnemonic recovery
- **Cryptomator vault format** (7.1): interop with Cyberduck/Mountain Duck
- **App lock** (7.3): PIN/biometric via `local_auth`
- **Proxy support** (7.2): HTTP/SOCKS5 via environment variables

### 3. Sync Engine — Remaining
- **Selective sync** (4.2): choose which remote folders to sync, placeholder files
- **Offline replay** (4.3): replay queued operations on reconnect
- **Mobile background sync** (4.4): `workmanager` (Android) + `BGTaskScheduler` (iOS)
- **Delta sync**: only transfer changed bytes (OneDrive, Dropbox support this)

### 4. Remaining UI/UX
- **Thumbnails** (5.1): generate in isolate, cache in drift DB
- **Markdown/PDF preview** (5.1): `flutter_markdown` for .md, `pdfx` for .pdf
- **Tab state persistence**: save/restore tabs across app restarts
- **Bookmarks/Favorites**: pin frequently used folders
- **Column view**: Finder-style as layout alternative

### 5. Platform Polish (Phase 8)
- macOS: native menu bar, Finder extension, notarization
- Windows: Explorer context menu, Windows Hello, MSIX
- Linux: .deb/.rpm/AppImage/Flatpak/Snap, XDG compliance
- Android: SAF, Material You, foreground service, Play Store
- iOS: Files.app integration, share extension, App Store
- Web: Service Worker, Web Push, OPFS

### 6. Distribution & Quality (Phase 10)
- **i18n**: extract strings to ARB, support 9+ languages
- **a11y**: screen reader labels, focus management, WCAG 2.1 AA
- **CI/CD**: build all 6 platforms, code signing, auto-update
- **Docs**: user guide, provider setup guides, plugin dev guide

### 7. Differentiation (Phase 11)
- **Migration wizard**: Provider A → Provider B guided workflow
- **Backup engine**: scheduled incremental backups with versioning
- **CLI companion**: `crisp` Dart CLI for scripting
- **Plugin system**: `CrispCloudPlugin` API
- **Mounted drives**: FUSE on Linux/macOS, WinFsp on Windows

## Key Files to Know

| File | Purpose |
|------|---------|
| `lib/providers/` | 8 Riverpod providers (auth, panel, transfer, error, search, sync, settings) |
| `lib/providers/auth_provider.dart` | Login/logout, provider switching, encryption, auto-login |
| `lib/providers/panel_provider.dart` | File listing, selection, sort, tabs, navigation (family per PanelSide) |
| `lib/providers/sync_provider.dart` | Sync pair CRUD, syncAll/syncOne, filesystem watcher, system tray |
| `lib/services/cloud_storage_interface.dart` | `CloudStorageClient` abstract + `CloudProvider` enum (9 values) + factory |
| `lib/services/sync_engine.dart` | Core two-way sync: scan, diff, conflict resolution, execute |
| `lib/services/sync_database.dart` | Drift/SQLite tables for sync metadata |
| `lib/services/gdrive_client_adapter.dart` | Google Drive — good template for new OAuth2 providers |
| `lib/services/s3_client_adapter.dart` | S3 reference adapter (715 lines) — template for non-OAuth providers |
| `lib/services/transfer_queue.dart` | Concurrent transfer manager |
| `lib/widgets/file_panel.dart` | Panel orchestrator (tabs, toolbar, breadcrumbs, file list/grid, drag target) |
| `lib/widgets/sync_dialog.dart` | Sync pair management UI |
| `lib/widgets/panel_splitter.dart` | Draggable resizable panel divider |
| `lib/screens/file_browser_screen.dart` | Main scaffold + layout |
| `PLAN.md` | Full roadmap with checkboxes |
| `HISTORY.md` | Completed work audit trail |

## Conventions

- **Tests**: every new service/adapter gets a `test/<name>_test.dart`. Use `InMemorySecureStorage` for credential tests. Use `SharedPreferences.setMockInitialValues({})` in setUp. Use `ProviderContainer` with overrides for Riverpod tests.
- **Config services**: `<Provider>ConfigService` with `SecureStorage` parameter for credentials.
- **Adapters**: implement `CloudStorageClient`, override capability flags, use `_ensureConnection()` or `_ensureToken()` pattern.
- **OAuth2 adapters**: browser flow via `url_launcher` + localhost `HttpServer`, `restoreCredentials()` for auto-login.
- **Riverpod**: widgets use `ConsumerWidget`/`ConsumerStatefulWidget`, `ref.watch()` for reactive, `ref.read()` for one-shot.
- **File naming**: `<provider>_client_adapter.dart`, `<provider>_config_service.dart`
- **When done**: check off items in `PLAN.md`, add entries to `HISTORY.md`

## How to Verify

```bash
flutter analyze   # should pass with warnings only
flutter test      # should pass all unit tests (live tests auto-skip without env vars)
flutter run -d chrome --release  # test Web build
flutter run -d macos             # test macOS build
```

## Deployment

- **Vercel**: auto-deploys on push to main. Config in `vercel.json` (SPA rewrites + Internxt API proxy + CORS headers).
- **CI**: `.github/workflows/ci.yml` — analyze + test + build-web + build-macos on push/PR.
- **GitHub**: `github.com/CrispStrobe/CrispCloud`

## Session Rules

1. Unit and live tests for all key features/methods
2. Once something is done, move it from `PLAN.md` to `HISTORY.md`
3. Work in priority order unless user specifies otherwise
4. Read files before modifying them
5. Don't re-implement what's already done — check `HISTORY.md` first
