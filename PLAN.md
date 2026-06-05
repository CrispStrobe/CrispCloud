# PLAN.md — CrispCloud: The Ultimate Cross-Platform Cloud File Manager

> Previous hardening plan (completed 2026-05-29) moved to HISTORY.md.

## Vision

CrispCloud becomes the **open-source Cyberduck/Transmit/Commander One killer**: a single, beautiful, blazing-fast app that connects to *any* cloud or server, runs on *every* platform, and treats privacy and encryption as first-class citizens — not afterthoughts.

---

## Current State (v0.0.2-dev)

**What works:**
- Adapter pattern with **11 providers**: Filen, Internxt, SFTP, WebDAV, **S3** (+ S3-compat), **FTP/FTPS**, **Google Drive**, **OneDrive**, **Dropbox**, **Nextcloud**, **pCloud**
- Two-panel Commander layout with keyboard shortcuts + breadcrumbs + selection bar
- **TransferQueue**: concurrent transfers (3 parallel), exponential backoff retry, pause/resume/cancel
- **Streaming interface**: `uploadStream`/`downloadStream` on all providers, SFTP native streaming
- **Secure credentials**: `flutter_secure_storage` (Keychain/Keystore/libsecret/DPAPI) + auto-migration
- **Preview pane**: image (zoom/pan), text/code (40+ ext), **markdown** (rendered), **PDF** (pdfx), metadata
- **Built-in editor**: edit remote files in-place (download → edit → Ctrl+S → auto-upload)
- **Status bar**: connection status, item count, selection info, transfer progress
- Structured logging (`Log` service) with ring buffer + export — **migrated across 33+ files**
- Centralized formatters, decomposed screen files, search dialogs extracted
- Cross-platform: Web (PWA), macOS, Windows, Linux, Android, iOS
- CI pipeline (analyze + test + build-web + build-macos)
- **Tabbed interface**: multiple tabs per panel, pin, close, duplicate, Ctrl+T/W, **tab persistence across restarts**
- **Theme system**: 6 themes (System/Light/Dark/OLED/Nord/Dracula) + accent color picker
- **Client-side encryption**: AES-256-GCM wrapper for any provider, **BIP39 key management + backup/recovery**
- **Command palette**: Ctrl+Shift+P, type-to-filter, context-aware actions
- **Batch rename**: 4 modes (find/replace, numbering, prefix/suffix, extension)
- **Archive support**: extract .zip, create .zip from selected files
- **Bookmarks**: pin favorite folders with persistence
- **Version history**: view + **restore** file versions (GDrive, Dropbox, OneDrive)
- **Share links**: generate provider-native shareable URLs
- **Duplicate finder**: MD5-based (local) or size-based (remote) duplicate detection
- **Diff viewer**: side-by-side file comparison with LCS algorithm, sync scrolling
- **SFTP permissions**: chmod/chown with visual rwx grid + octal presets
- **Sync engine**: two-way sync with **selective sync**, **offline replay**, **delta sync** (content hash), **file cache** (LRU), **placeholder files** (cloud-only on demand)
- **Security**: HTTP/SOCKS5 **proxy** (env auto-detect), **app lock** (PIN/password + auto-lock), **certificate pinning** (Google/Microsoft/Dropbox/Amazon)
- **Thumbnails**: compute-isolate generation, disk+memory cache, grid view integration
- **Platform extensions**: macOS Finder Quick Action, Windows Explorer context menu, iOS Share Extension + Siri Shortcuts, Android home widget + foreground service + SAF
- **Web PWA**: Service Worker (offline), Web Push, File System Access API, OPFS, Share Target
- **CLI companion** (`crisp`): standalone Dart CLI with S3/SFTP/WebDAV, 9 commands, shell completions
- **FUSE mounted drives**: mount cloud storage as local filesystem (macFUSE/libfuse/WinFsp), caching, mount dialog
- **Crash reporting**: opt-in `CrashReportingService` with local JSONL storage, breadcrumb ring buffer, `CrashLog` hook, `SentryBackend` placeholder
- **Automation rules**: `AutomationRuleService` + `AutomationEngine` — folder watchers, cron scheduling, webhooks, glob-based rule engine
- **Backup engine**: `BackupService` — scheduled incremental backups, versioning, integrity verification, restore wizard
- **Local REST API**: `LocalApiService` — 11 endpoints on localhost, token auth, rate limiting, CORS
- **Auto-update**: `AutoUpdateService` — GitHub Releases checker, version comparison, update channels
- **Cryptomator vault** v8 interop + **VeraCrypt container** (.vc/.hc) support
- **Rebindable keyboard shortcuts**: 24 actions, conflict detection, import/export
- **XDG compliance** (Linux): proper config/data/cache/state paths
- **Performance benchmarks**: 11 benchmarks with timing validation
- **Mock S3 + WebDAV servers** for offline CI testing
- **80+ test files**, **2500+ unit tests** + gated E2E suites

**What's still needed:**
- ~~Monolithic state (AppState)~~ — **Riverpod migration done** (8 focused providers)
- ~~Sync engine v1~~ — done (two-way, conflicts, selective sync, offline replay, filesystem watcher, system tray)
- ~~GDrive~~ + ~~OneDrive~~ + ~~Dropbox~~ — all Tier 1 providers done
- ~~Security hardening~~ — proxy, app lock, biometric, cert pinning done; Cryptomator pending
- No plugin/extension system
- No i18n, no accessibility audit

---

## Phase 1: Foundation Hardening (Weeks 1-3)

*Goal: Make the existing app production-grade before adding features.*

### 1.1 Secure Credential Storage
- [x] Replace `SharedPreferences` with `flutter_secure_storage` (Keychain, Keystore, libsecret, DPAPI)
- [x] Migration path: `CredentialMigration.migrateIfNeeded()` — idempotent, wipes old keys
- [x] `SecureStorage` abstraction + `InMemorySecureStorage` test double
- [x] All config services + adapters + tests updated
- [x] Web: encrypted localStorage with user-derived key (PBKDF2 + AES-256-GCM from master password)
- [x] Biometric unlock option (FaceID / TouchID / fingerprint) via `local_auth`

### 1.2 State Management Overhaul
- [x] Migrate from `Provider` + single `ChangeNotifier` to **Riverpod 2**
- [x] Split `AppState` (1,783 lines) into focused providers:
  - `authProvider` — login state, credentials, auto-login, provider switching, encryption
  - `panelProvider(side)` — file listing, selection, sort, tabs, navigation (family provider per panel)
  - `transferProvider` — operation queue, progress, cancel/pause, upload/download
  - `errorProvider` — error queue with severity levels
  - `activePanelProvider` / `showPreviewProvider` — UI state
  - `searchProvider` — query, results, filters
- [x] Each provider independently testable, independently rebuilds UI
- [x] Update all widget `Consumer`/`watch` calls to Riverpod `ref.watch`/`ref.read`

### 1.3 File Decomposition
- [x] Split `file_browser_screen.dart` (1,331 → 459 lines) into:
  - `keyboard_shortcuts.dart` (112 lines)
  - `screen_dialogs.dart` (478 lines)
  - `about_dialog.dart` (158 lines)
- [x] Removed dead code: `_buildFAB`, `_showUserMenu`
- [x] Split `file_context_menu.dart` (662 → 523 lines) — search dialogs extracted to `search_dialogs.dart`
- [x] Split `file_toolbar.dart` into `FileToolbar`, `FileBreadcrumbs` (file_breadcrumbs.dart), `FileSelectionBar` (file_selection_bar.dart)
- [x] `local_file_service.dart` → abstract interface + factory, platform implementations in `local_file_service_native.dart` and `local_file_service_web.dart`

### 1.4 Logging & Observability
- [x] Created `LogService` with `Log` named-logger class
- [x] Log levels: trace / debug / info / warn / error
- [x] In-memory ring buffer with configurable size + `LogConfig.export()`
- [x] Migrate existing `debugPrint` calls to `Log` (incremental, per-file) — 27+ files migrated, only legacy app_state.dart and local_file_service.dart remain
- [x] Crash reporting integration (Sentry or self-hosted, opt-in) — `CrashReportingService` with opt-in toggle, local JSONL storage, breadcrumb ring buffer, `CrashLog` hook, `SentryBackend` placeholder

### 1.5 Utilities
- [x] Implemented `formatters.dart`: `formatBytes`, `formatDate`, `formatDateFull`, `formatDuration`, `formatSpeed`
- [x] Consolidated 5 duplicate `formatBytes` + 2 duplicate `formatDate` functions
- [x] Used in `FileListTile`, `OperationsPanel`, `FileToolbar`, `FileContextMenu`, `AppState`

---

## Phase 2: Performance & Streaming (Weeks 3-6)

*Goal: Handle files of any size without memory issues.*

### 2.1 Streaming File Transfers
- [x] Added `uploadStream` / `downloadStream` to `CloudStorageClient` with buffer-fallback defaults
- [x] SFTP adapter: true streaming upload/download (32KB chunks, no full-file buffering)
- [x] Added 7 capability flags (`supportsStreaming`, `supportsMultipart`, etc.)
- [x] Desktop/Mobile: stream from disk via `File.openRead()` → `uploadStream`, `downloadStream` → `File.openWrite()`
- [x] Web: use `ReadableStream` via File System Access API for chunked reads — `WebStreamingService` with blob slicing, conditional import facade
- [x] Memory ceiling: 2-chunk back-pressure via StreamController transform

### 2.2 Concurrent Transfers
- [x] `TransferQueue` service with configurable `maxConcurrent` (default 3)
- [x] Exponential backoff retry for transient errors (timeout, connection, 429, 503)
- [x] `TransferTask` with priority, `cancelAll()`, `clearCompleted()`
- [x] Wired `TransferQueue` into AppState — each file is a `TransferTask`, queue manages concurrency
- [x] Pause/Resume/Cancel already wired in `OperationsPanel` (verified)
- [x] Per-provider rate limiting (respect API quotas) — configurable per-provider concurrent limits and min delay in TransferQueue

### 2.3 Large File Support
- [x] Multipart upload for S3 (CreateMultipartUpload, UploadPart, CompleteMultipartUpload, auto for files >5MB)
- [x] Resume interrupted uploads (track parts in SharedPreferences, listParts API, resumeMultipartUpload)
- [x] Web: use `showSaveFilePicker` + writable stream for large downloads (no memory blob) — `downloadWithWritableStream` in `WebStreamingService`, wired into `TransferNotifier`
- [x] Progress reporting at chunk granularity — multipart upload reports per-part progress

### 2.4 Lazy Loading & Virtualization
- [x] `ListView.builder` with `itemExtent: 64` for O(1) scroll-to-index + skip off-screen layout
- [x] Paginated listing for S3 with explicit `max-keys` control
- [x] Incremental search/filter (client-side, don't re-fetch) — `PanelNotifier.setFilter()` / `filteredFiles` getter
- [x] Debounced directory refresh — `refreshDebounced()` with 500ms coalescing

---

## Phase 3: Provider Ecosystem (Weeks 5-10)

*Goal: Connect to anything.*

### 3.1 New Providers — Tier 1 (most demanded)
- [x] **Amazon S3** (+ S3-compatible: MinIO, Backblaze B2, Wasabi, DO Spaces, Cloudflare R2)
  - Pure Dart SigV4 signing, virtual-hosted + path-style auto-detection
  - 715-line adapter, connection dialog, auto-login, 480 lines of tests
  - [ ] Multipart upload, presigned URLs, server-side encryption, storage classes
- [x] **Google Drive**
  - Pure HTTP + OAuth2 browser flow (no googleapis SDK dependency)
  - Path-to-ID resolution with caching, paginated listing, multipart upload
  - [ ] Shared drives, starred files, file versions, Google Docs export
- [x] **OneDrive / SharePoint**
  - Pure HTTP + Microsoft Graph API v1.0, OAuth2 browser flow (no MSAL)
  - Path-based addressing (no ID resolution needed), paginated listing
  - [ ] Delta sync support, shared libraries
- [x] **Dropbox**
  - Pure HTTP + Dropbox API v2, OAuth2 browser flow
  - Paginated list_folder, overwrite upload, content download
  - [ ] Shared folders, Paper docs, content hash for dedup

### 3.2 New Providers — Tier 2
- [ ] **Azure Blob Storage** — SAS token + OAuth2, blob tiers
- [x] **FTP / FTPS** — `ftpconnect` package, TLS toggle, connection dialog, auto-login
- [ ] **Backblaze B2** (native API, not just S3 compat) — large file API, app keys
- [ ] **Mega.nz** — E2E encrypted
- [x] **pCloud** — OAuth2, crypto folder, EU server support
- [ ] **Storj** — decentralized, S3 gateway or native uplink
- [ ] **Hetzner Storage Box** — SFTP/WebDAV/CIFS, popular in EU
- [x] **Nextcloud** — WebDAV + OCS API for native features (sharing, versions)

### 3.3 Provider Abstraction Improvements
- [x] Capability flags per provider: `supportsVersioning`, `supportsSharing`, `supportsSearch`, `supportsStreaming`, `supportsMultipart`, `supportsThumbnails`, `supportsTrash` — implemented in CloudStorageClient with per-adapter overrides
- [x] Provider-specific settings (timeout, custom headers, SSL verify, redirects) — `ProviderSettingsDialog`
- [x] Multiple simultaneous connections to different providers — `MultiCloudService` with connection registry
- [x] **Connection profiles**: save/load/delete named connections per provider via `ConnectionProfileService`
- [x] Provider health check / latency indicator — `CloudStorageClient.healthCheck()` returns latency ms
- [x] Quota / usage display per provider — `CloudStorageClient.getQuota()` returns used/total/free bytes

### 3.4 Multi-Cloud Operations
- [x] Cloud-to-cloud transfer (remote A → remote B, streams when supported) — `MultiCloudService.transferBetweenClouds()`
- [x] Server-side copy when provider supports it — S3 COPY, GDrive/OneDrive/Dropbox copy APIs, `supportsServerSideCopy` flag
- [x] Cross-provider file comparison (size, hash, modified date) — `MultiCloudService.compareFiles()` with `FileDiff` results
- [x] Unified search across all connected providers — `MultiCloudService.searchAcrossProviders()`

---

## Phase 4: Sync Engine (Weeks 8-14)

*Goal: Keep files in sync automatically, with offline support.*

### 4.1 Two-Way Sync
- [x] Define sync pairs: local folder ↔ remote folder (SyncPair model + drift table)
- [x] Conflict detection: modified-on-both-sides → prompt or apply policy
- [x] Conflict policies: newest wins, local wins, remote wins, keep both, manual
- [x] Change detection: recursive local fs scan + remote listing comparison against DB state
- [x] Filesystem watcher (`watcher` package on desktop) with 5s debounce for real-time change detection
- [x] Delta sync: content hash comparison (Dropbox content_hash, OneDrive crc32/sha1) — hash-based change detection in SyncEngine, stored in DB remoteHash
- [x] Sync metadata stored in local SQLite (via `drift`)

### 4.2 Selective Sync
- [x] Choose which remote folders to sync locally — include/exclude glob patterns on SyncPairs, filtered in SyncEngine
- [x] Placeholder / "cloud-only" files (like OneDrive Files On-Demand) — `PlaceholderService` with `.crispcloud` stubs, hydrate/dehydrate, per-pair toggle
- [x] Smart sync: auto-evict files not accessed in N days — `PlaceholderService.autoEvict()` with configurable days
- [x] Bandwidth scheduling: sync only on Wi-Fi, or during specified hours — `setSyncOnlyOnWifi()`, `setSyncHours()`, `isSyncAllowedNow` gate

### 4.3 Offline Mode
- [x] Queue operations while offline (OfflineQueue table in drift)
- [x] Cache recently accessed files for offline use — `FileCacheService` with LRU eviction, configurable max size, JSON index
- [x] Replay queued operations on reconnect — `replayOfflineQueue()` in SyncNotifier, chronological replay with error tracking
- [x] Conflict resolution on reconnect — checks remote modification time before replaying upload ops
- [x] Configurable cache size limit with LRU eviction — `FileCacheService` with 500MB default, evicts at 80%

### 4.4 Background Sync Service
- [x] Desktop: system tray icon via `system_tray` package with context menu (Show / Sync All / Quit)
- [x] Sync status tooltip in system tray (syncing, pair count, last result)
- [x] Mobile: `workmanager` (Android) + `BGTaskScheduler` (iOS) — `BackgroundSyncService` with configurable interval
- [x] Native notifications for conflicts, errors, completion — `flutter_local_notifications`

---

## Phase 5: UI/UX Overhaul (Weeks 6-12)

*Goal: Look and feel as good as Transmit / Forklift / Commander One.*

### 5.1 File Preview & Thumbnails
- [x] Preview pane (toggle with Space key or eye icon in app bar):
  - Images: inline viewer with InteractiveViewer (zoom/pan), up to 20MB
  - Text/Code: monospace read-only viewer for 40+ extensions, up to 5MB
  - Metadata: file icon, type badge, size, modified date, path, UUID
  - 280px sidebar in two-panel layout
- [x] Thumbnail generation for images (JPEG, PNG, WebP, GIF, BMP) — `ThumbnailService` with compute isolate, disk+memory cache, grid view integration
- [x] Provider-native thumbnails when available (GDrive, OneDrive, Dropbox) — `CloudStorageClient.getThumbnail()` with per-provider implementations
- [x] Thumbnail cache stats (disk size, count, memory size) — added to ThumbnailService
- [x] Markdown: rendered preview — `flutter_markdown` with theme-aware styling
- [x] PDF: page viewer — `pdfx` package, scrollable PDF in preview pane
- [x] Video/Audio: streaming player via `video_player`, inline controls (seek, play/pause, volume)

### 5.2 Tabbed Interface
- [x] Multiple tabs per panel — `PanelTab` model, tab bar widget, add/close/pin
- [x] Pin, close-all-but-this, duplicate tab (context menu)
- [x] Ctrl+T new tab, Ctrl+W close tab
- [x] Tab state persistence across app restarts — saved to SharedPreferences as JSON
- [x] Drag files between tabs — DragTarget on PanelTabBar accepts file drops
- [x] Ctrl+Tab / Ctrl+Shift+Tab cycle between tabs

### 5.3 Responsive & Adaptive Layout
- [x] Mobile: swipe between panels (horizontal gesture)
- [x] Tablet/Desktop: side-by-side panels with draggable splitter (double-tap to reset)
- [ ] Desktop: optional detachable panels, multi-window support
- [ ] Web: responsive breakpoints improvements
- [x] Layout presets: Commander (two-panel), Explorer (single-panel + tree), Gallery — `LayoutPreset` enum with persistence
- [x] Pull-to-refresh on mobile — `RefreshIndicator` wrapping file list

### 5.4 Theming & Customization
- [x] Built-in themes: System, Light, Dark, OLED Black, Nord, Dracula — with theme picker dialog
- [x] Custom accent color picker (11 preset colors + default)
- [x] Theme persistence via SharedPreferences
- [x] Configurable font size and family — `fontSizeProvider` (10-20px) + `fontFamilyProvider` with persistence
- [ ] Material You dynamic theming on Android
- [ ] Toolbar customization: show/hide buttons, reorder
- [x] Rebindable keyboard shortcuts (persist to settings) — `KeyboardShortcutService` with 24 actions, conflict detection, import/export, SharedPreferences persistence

### 5.5 Advanced Navigation
- [x] Breadcrumb path bar (clickable path segments) — already existed in FileBreadcrumbs
- [x] Editable address bar: click edit icon → type path → Enter to navigate
- [x] Go-to-folder dialog (Ctrl+G)
- [x] Bookmarks / Favorites — `BookmarksNotifier` with SharedPreferences persistence, add/remove from tree sidebar
- [x] Recent locations — `RecentLocationsNotifier` with persistence, shown in tree sidebar
- [x] Go-to-folder dialog (Ctrl+G)
- [x] Column view (Finder-style) as layout alternative — `FileColumnView` widget, toolbar cycles list→grid→column
- [x] Grid / Gallery view for image-heavy folders (toggle in toolbar)
- [x] Tree view sidebar (expandable folder tree, toggle in app bar)

### 5.6 Drag & Drop
- [x] Drag between panels (local ↔ remote) via LongPressDraggable + DragTarget
- [x] Drag from OS file manager into app (desktop via `desktop_drop`)
- [ ] Drag from app to OS file manager (desktop)
- [x] Visual drop zones with operation hint (upload/download icon, file count badge)
- [x] Multi-file drag with count badge — drags all selected files, shows count badge
- [x] Touch drag on mobile/tablet — reduced LongPressDraggable delay to 200ms on mobile

### 5.7 Status Bar & Info
- [x] Connection status indicator (provider name, connected/disconnected icon)
- [x] Items in folder / selected items count + total size
- [x] Active transfer count + progress
- [x] Active panel indicator (Local/Remote)
- [x] Live transfer speed (current + average + ETA) — in OperationProgress and OperationsPanel
- [x] Free space / quota display (per provider) — status bar shows used/total when connected
- [x] Sync status (when sync engine is active) — status bar shows last sync changes count

---

## Phase 6: Power User Features (Weeks 10-16)

### 6.1 Built-in Editor
- [x] Text/code editor with line numbers — full-screen `FileEditorDialog`, Ctrl+S save, unsaved-changes warning
- [x] Edit remote files in-place (download → edit → auto-upload on save)
- [x] Diff viewer: compare two files (local vs remote) — `DiffViewerDialog` with LCS diff, sync-scrolling, line numbers
- [x] Auto-save with conflict detection — 30s timer, remote modification check before save, conflict banner
- [x] Configurable: use built-in editor or launch external app — `preferExternalEditorProvider`, context menu submenu

### 6.2 Terminal & Command Palette
- [ ] Embedded SSH terminal for SFTP connections
- [x] Command palette (Ctrl+Shift+P) — type to search, arrow keys, Enter to execute, context-aware
- [x] Action history / undo recent operations — `ActionHistoryService` with undo for delete/rename/move/copy/createFolder

### 6.3 Advanced File Operations
- [x] Calculate folder sizes (recursive, context menu "Calculate Size")
- [x] Checksum verification (MD5 + SHA-256, context menu "Checksum", ChecksumService)
- [x] File permissions editor (SFTP: chmod, chown) — `PermissionsDialog` with visual rwx grid, octal presets, owner/group editing
- [x] Symbolic link detection (SFTP) — `isSymlink` flag in listPath results
- [x] Archive support: extract .zip (context menu "Extract Here"), create .zip from selected files
- [x] Batch rename: 4 modes (find/replace with regex, numbering, prefix/suffix, extension), live preview, context menu integration

### 6.4 Sharing & Collaboration
- [x] Generate shareable links (provider-native: GDrive, Dropbox, OneDrive) — `ShareLinkDialog`
- [x] Password-protected and expiring share links — Dropbox + OneDrive support, options UI in ShareLinkDialog
- [x] Share via native share sheet (mobile) — `share_plus` integration for local and remote files
- [ ] Shared folder management UI

### 6.5 Version History
- [x] Show file versions when provider supports it (GDrive, Dropbox, OneDrive) — `VersionHistoryDialog`
- [x] Restore previous version — GDrive (revision download + re-upload), Dropbox (restore endpoint), OneDrive (restoreVersion action)
- [x] Version diff for text files — download version content, compare with current via LCS diff viewer
- [x] Local version snapshots before overwrite — saves to temp dir before editor save

### 6.6 Search & Filters
- [x] Full-text search — GDrive (fullText query), Dropbox (search_v2), OneDrive (Graph /search/query), fallback (download+search text files)
- [x] Saved searches / smart folders — `SavedSearchService` with CRUD, run saved searches as virtual folders
- [x] Filter by: type, size range, date range — `SearchNotifier.setFilters()` with 6 file type categories, min/max size, date range
- [x] Regex search in file names — regex toggle in Find dialog, client-side filtering
- [x] Duplicate file finder (by hash for local, size for remote) — `DuplicateFinderDialog`
- [x] Search results as virtual folder (act on results directly) — `PanelNotifier.showSearchResults()`, "Show as Folder" button

---

## Phase 7: Security & Privacy (Weeks 8-14)

*Goal: Make CrispCloud the most privacy-respecting cloud client.*

### 7.1 Client-Side Encryption Layer
- [x] `EncryptionService` — AES-256-GCM, PBKDF2 key derivation (100K iterations), nonce + tag
- [x] `EncryptedStorageWrapper` — wraps any `CloudStorageClient`, transparent encrypt/decrypt
- [x] Optional encrypted filenames (base64url-safe)
- [x] Capability flags auto-disabled (sharing, search, thumbnails)
- [x] 28 tests covering round-trip, wrong key, 1MB data, wrapper behaviour
- [x] Wired into UI: connection dialog toggle + passphrase, AppState enableEncryption/disableEncryption
- [x] Key management: export/import master key (hex), BIP39 24-word mnemonic, backup bundle with verification — `KeyManagementDialog`
- [x] Compatible with Cryptomator vault format (interop with other tools) — `CryptomatorService` with v8 vault detection, scrypt KDF, AES key wrap (RFC 3394), SIV filename encryption, directory ID hashing
- [x] VeraCrypt container support (.vc/.hc) — `VeraCryptService` with AES-256-XTS header decryption, SHA-512/SHA-256/Whirlpool KDF, live integration tests

### 7.2 Secure Networking
- [x] Certificate pinning for known providers — `CertPinningService` with SPKI SHA-256 pins for Google/Microsoft/Dropbox/Amazon, wired into `ProxyHttpOverrides`
- [x] Custom CA certificate support — import PEM/CRT/CER files, persist as base64, validate against stored CAs, inject into SecurityContext
- [x] HTTP/SOCKS5 proxy support — `ProxyService` with env auto-detection, `ProxyHttpOverrides` for global routing, `ProxySettingsDialog` UI
- [ ] Tor/onion routing support (optional)
- [x] TLS version enforcement — minimum TLS 1.2 (default), TLS 1.3 (strict), Any (user override), dropdown in proxy settings

### 7.3 Access Control
- [x] App lock: PIN/password required to open — `AppLockService` with salted SHA-256 hashing, `LockScreen` + `AppLockSetupDialog`
- [x] Auto-lock after configurable timeout — `_AppLockGate` with `WidgetsBindingObserver` lifecycle detection
- [x] Biometric unlock: FaceID/TouchID/fingerprint via `local_auth`, auto-prompt on lock screen, toggle in setup dialog
- [x] Secure clipboard: auto-clear after 30s via `SecureClipboard` utility
- [x] Disable screenshots on mobile (opt-in) — `disableScreenshotsProvider` with persistence

### 7.4 Privacy Dashboard
- [x] Visual encryption status indicator per connection — lock icon in status bar when encrypted
- [x] "Privacy Score" per provider (E2E > encrypted-at-rest > unencrypted) — shield icon with score tooltip
- [x] Audit log: local record of all operations — `AuditService` with JSON-lines storage, dialog with export/clear
- [ ] Data flow visualization: show where your data goes

---

## Phase 8: Platform-Specific Polish (Weeks 12-18)

### 8.1 macOS
- [x] Native menu bar integration (CrispCloud, File, View menus) via `PlatformMenuBar`
- [x] Finder Quick Action extension: right-click → "Upload to CrispCloud" — FinderSync extension + `crispcloud://` URL scheme + Dart service
- [ ] Share extension (share from any app)
- [ ] Spotlight integration for synced files
- [ ] Notarization + Developer ID signing
- [ ] Mac App Store distribution
- [ ] Touch Bar support (legacy but nice)

### 8.2 Windows
- [x] Explorer context menu: right-click → "Upload to CrispCloud" — C++ registry registration + Dart service + settings toggle
- [x] Windows Hello biometric support — `local_auth` fixes for Windows (biometricOnly, canCheckBiometrics, label)
- [ ] Jump list (recent connections in taskbar)
- [ ] Microsoft Store (MSIX) distribution
- [ ] Virtual filesystem driver for mounted drives (like Mountain Duck)

### 8.3 Linux
- [ ] Nautilus/Dolphin/Thunar right-click integration
- [ ] D-Bus notifications
- [ ] Distribution: .deb, .rpm, AppImage, Flatpak, Snap
- [ ] GNOME Keyring / KDE Wallet integration (via flutter_secure_storage)
- [x] XDG compliance (config in `~/.config/crispcloud/`) — `XdgService` with config/data/cache/state/runtime paths, env var resolution, legacy migration

### 8.4 Android
- [x] SAF (Storage Access Framework) full integration — `SAFService` + Kotlin `SAFHandler` with Activity Result API
- [x] Material You / dynamic theming — `dynamic_color` package, 7th theme option, wallpaper-derived ColorScheme
- [x] Home screen widget: quick upload, recent files, sync status — `CrispCloudWidget.kt` + XML layouts
- [x] Foreground service for long transfers (with notification) — `ForegroundTransferService` with auto-promote after 5s
- [ ] Play Store + F-Droid distribution
- [x] Intent handling: open-with, share-to CrispCloud — `IntentHandlerService` wrapping `receive_sharing_intent`

### 8.5 iOS / iPadOS
- [x] Files.app integration (FileProvider extension) — CrispCloud as a location in Files
- [x] Share extension (upload from Photos, Safari, etc.) — `ShareViewController.swift` + App Group + `ShareExtensionService`
- [x] Shortcuts/Siri integration ("Upload my screenshots to S3") — `SiriShortcutsService` with 3 shortcuts + `SceneDelegate` activation handler
- [x] Stage Manager multi-window (iPadOS) — `UIApplicationSceneManifest` + `SceneDelegate` + `MultiWindowService`
- [ ] App Store distribution
- [ ] iCloud Keychain credential sync

### 8.6 Web (PWA)
- [x] Service Worker: offline app shell, cache static assets — `web/service-worker.js` with cache-first/network-first strategies
- [x] Web Push notifications for long-running operations — `WebPushService` with browser Notification API + conditional import
- [x] Persistent file handles via File System Access API — `FileSystemAccessService` with IndexedDB persistence
- [x] Web Share Target API (receive shares from other PWAs) — `WebShareTargetService` + manifest `share_target` entry
- [x] Installable PWA with standalone display mode — manifest shortcuts, screenshots, categories
- [x] OPFS (Origin Private File System) for offline cache — `OpfsService` with navigator.storage.getDirectory()

---

## Phase 9: Developer Experience & Extensibility (Weeks 14-20)

### 9.1 Plugin System
- [ ] Plugin API: `CrispCloudPlugin` interface
  - `onFileAction(action, files)` — hook into operations
  - Custom context menu entries
  - Custom toolbar buttons
  - Custom preview renderers
  - Custom provider implementations
- [ ] Plugin discovery: pub.dev packages tagged `crisp_cloud_plugin`
- [ ] Plugin settings UI (per-plugin configuration)
- [ ] Sandboxed execution (plugins can't access credentials)

### 9.2 CLI Companion (`crisp`)
- [x] Standalone Dart CLI for headless/scripted use — `cli/` subdirectory with 9 commands (connect, ls, upload, download, sync, search, share, providers, config)
- [x] Config file: `~/.config/crispcloud/config.yaml` — `CliConfig` with YAML persistence
- [x] Shell completions (bash, zsh, fish, PowerShell) — `crisp completion bash/zsh/fish`
- [x] JSON output mode for piping — `--json` flag on all listing commands
- [x] Usable in CI/CD pipelines — exit codes 0/1/2, `--progress` to stderr, pure Dart S3/SFTP/WebDAV adapters

### 9.3 Automation & Rules
- [x] Folder actions: auto-upload when files appear in watched folder — `AutomationEngine` with `FilePatternTrigger` + directory watchers
- [x] Scheduled transfers (built-in cron) — `CronParser` with 5-field expressions, `ScheduleTrigger`, per-minute timer
- [x] Webhooks: notify external services on events — `WebhookExecutor` with GET/POST/PUT/PATCH/DELETE + custom headers
- [x] Rule engine: "when file matches *.pdf in /Scans/, upload to Filen/Documents/" — sealed `AutomationTrigger`/`AutomationAction` hierarchies, glob matching, CRUD
- [x] Conflict-free automation (rules define conflict policy upfront) — per-rule conflict policy in `AutomationRule`

### 9.4 Local API (Headless Mode)
- [x] REST API on localhost for integration with other apps — `LocalApiService` with `dart:io` HttpServer, 11 endpoints, CORS, rate limiting
- [x] Operations: list, upload, download, sync, share — GET/POST/DELETE for files, sync trigger/status, transfers
- [x] Auth via local token file — `ApiTokenManager` with secure random 48-char hex tokens, Bearer auth
- [x] Useful for: NAS integration, media servers, backup scripts, Zapier-style workflows

---

## Phase 10: Quality & Distribution (Weeks 16-22)

### 10.1 Testing
- [ ] Unit test coverage >80% on all services and providers
- [ ] Widget tests for every screen and dialog
- [ ] Integration tests: full user flows (connect → browse → transfer → disconnect)
- [ ] Golden tests for UI regression
- [x] Performance benchmarks: 1K-file listing, 1GB upload, 10K-file sync — `BenchmarkService` with 11 benchmarks, Stopwatch timing, median of N iterations
- [x] Fuzz testing: Unicode filenames, special chars, path traversal, long paths — `PathSanitizer` utility + 131 tests
- [x] Provider mock server for offline CI testing — `MockS3Server` + `MockWebDavServer` in-process HTTP servers with full CRUD

### 10.2 CI/CD
- [x] Build artifacts for all 6 platforms on every PR — ci.yml matrix builds web/linux/android + windows/macOS/iOS
- [x] Automated release pipeline: tag → build → sign → publish — release.yml with changelog generation, pre-release support
- [x] Code signing: macOS (Developer ID), Windows (Authenticode), Android (Play signing), iOS (App Store) — placeholder steps with instructions in release.yml
- [x] Beta channels: TestFlight, Play internal track, GitHub pre-releases — `UpdateChannel` enum (stable/beta/nightly), pre-release flag
- [x] Auto-update: Sparkle (macOS), MSIX auto-update (Windows), in-app (mobile) — `AutoUpdateService` checks GitHub Releases API, version comparison, platform URL selection
- [x] Nightly builds from `main` — nightly.yml with change detection, scheduled at 2:00 AM UTC

### 10.3 Internationalization (i18n)
- [x] Extract all user-facing strings to ARB files — `lib/l10n/app_en.arb` (150+ keys), `l10n.yaml` config
- [x] Launch languages: English, German — `app_en.arb`, `app_de.arb`
- [x] Additional languages: French, Spanish, Portuguese, Chinese (Simplified), Japanese — `app_fr.arb`, `app_es.arb`, `app_pt.arb`, `app_zh.arb`, `app_ja.arb`
- [ ] Additional languages: Korean, Arabic (RTL)
- [ ] Crowdsourced via Weblate or Crowdin
- [ ] Date/number/size formatting per locale (use formatters from 1.5)

### 10.4 Accessibility (a11y)
- [ ] Full screen reader support (TalkBack, VoiceOver, NVDA, Narrator)
- [ ] Semantic labels on all interactive elements
- [ ] Focus management and tab order audit
- [ ] High-contrast mode
- [ ] Reduced-motion mode (respect `prefers-reduced-motion`)
- [ ] Minimum 48dp touch targets on mobile
- [ ] WCAG 2.1 AA compliance

### 10.5 Documentation
- [x] User guide with screenshots (hosted on docs site) — `docs/USER_GUIDE.md` (640 lines), all 21 feature areas
- [x] Provider setup guides (API keys, CORS, SFTP config) — `docs/PROVIDER_SETUP.md` (413 lines), all 11 providers + troubleshooting
- [x] Contributing guide: how to add a new provider — `docs/CONTRIBUTING.md` (463 lines), 6-step provider guide, code style, PR process
- [ ] Plugin development guide
- [x] Architecture decision records (ADRs) — 6 ADRs in `docs/adr/` (Riverpod, adapter pattern, encryption, drift, streaming, secure creds)
- [ ] Video walkthroughs

### 10.6 Distribution
- [ ] Landing page / website with feature comparison
- [ ] Package managers: `brew install crisp-cloud`, `winget`, `choco`, `scoop`, `apt`
- [ ] App stores: Mac App Store, Microsoft Store, Play Store, App Store, F-Droid
- [ ] Auto-update with changelog display
- [ ] Opt-in anonymous usage analytics (feature usage, not file data)

---

## Phase 11: Differentiation — What No Competitor Has

### 11.1 Smart Features (On-Device AI, No Cloud)
- [x] On-device file categorization (documents, photos, videos, code, archives) — `StorageAnalyticsService.categorizeFile()` with 160+ extension mappings
- [x] Duplicate detection across all connected providers — `findDuplicatesAcrossProviders()` by size+name
- [x] Storage analytics dashboard: what's using space, what's stale, what's duplicated — `StorageBreakdown`, `CategoryStats`, stale/largest file detection
- [x] Smart cleanup: "You have 3 copies of this 2GB video across Filen, S3, and local" — `generateCleanupSuggestions()` with savings estimation
- [ ] OCR on images/PDFs for searchable content (on-device via `google_mlkit_text_recognition` or WASM)

### 11.2 Migration Wizard
- [x] "Move from Provider A to Provider B" guided workflow — `MigrationService` with `MigrationPlan`, guided workflow
- [x] Progress tracking, resumable, full conflict handling — pause/resume/cancel, 4 conflict policies (skip/overwrite/rename/newest)
- [x] Preserve folder structure, metadata, timestamps — `preserveStructure` flag, recursive scan
- [x] Bandwidth throttling to avoid API rate limits — configurable `throttleMBps` with delay calculation
- [x] Post-migration verification (hash comparison) — `verifyMigration()` with size + hash comparison
- [x] Provider comparison: cost/GB, features, privacy score — `ProviderComparisonService` with data for all 11 providers, privacy scoring algorithm

### 11.3 Backup Engine
- [x] Scheduled backups: local folder → cloud provider — `BackupService` with `BackupPlan` model, cron scheduling
- [x] Incremental backups (only changed files, tracked via SQLite) — MD5 hash + modified date comparison against previous snapshot
- [x] Backup versioning (keep last N snapshots) — `pruneSnapshots()`, configurable `maxVersions`
- [x] Backup integrity verification (periodic hash check) — `verifySnapshot()` re-hashes and compares
- [x] Restore wizard: browse snapshots, restore individual files or full backup — `getRestorePreview()` + `restoreSnapshot()`
- [x] Backup encryption (independent of provider encryption) — encryption flag + key on `BackupPlan`, callback-based encrypt/decrypt

### 11.4 Mounted Drives (Desktop)
- [x] Mount remote storage as a local drive letter / mount point — `FuseMountService` + `MountDialog` + `MountNotifier`
- [x] macOS: FUSE / macFUSE integration — helper script detects macFUSE/FUSE-T
- [x] Windows: WinFsp / Dokan virtual filesystem — helper script detects WinFsp
- [x] Linux: FUSE mount — helper script detects fusermount3/fusermount
- [x] Read/write with caching, works with any native app — dir listing cache (30s TTL), read-ahead (256KB), write-back on close
- [x] Automatic disconnect on sleep/hibernate — `autoUnmountOnExit` flag, `unmountAll()` on dispose

---

## Priority Matrix

| Phase | Impact | Effort | Status |
|-------|--------|--------|--------|
| 1. Foundation Hardening | Critical | Medium | **~100% done** — Riverpod, credentials (incl. web encrypted storage), logging, formatters, decomposition all done |
| 2. Performance & Streaming | High | Medium | **100% done** — streaming (all platforms including web), queue, virtual scroll, multipart S3 + resume, rate limiting, back-pressure done |
| 3.1 S3 + GDrive + OneDrive + Dropbox | High | Medium | **All 4 done** |
| 3.2 Tier 2 providers | Medium | Medium | **FTP, Nextcloud, pCloud done** — Azure, B2, Mega pending |
| 4. Sync Engine | Very High | Very High | **~95% done** — two-way, selective, offline replay+cache, watcher, tray, delta sync, placeholder files, **mobile background sync** done |
| 5. UI/UX | High | Medium | **~98% done** — preview, tabs, themes, nav, DnD (multi-file badge), tree, grid+thumbnails (provider-native), column view, bookmarks, pull-to-refresh, quota display done |
| 6. Power User Features | Medium | High | **~90% done** — editor, palette, batch rename, archives, versions+restore+diff, share, dupes, diff, permissions, search filters, **full-text search** done |
| 7.1 Client-Side Encryption | High | High | **100% done** — encryption + key management + BIP39 + Cryptomator v8 + VeraCrypt done |
| 7.2-7.4 Security extras | Medium | Medium | **~95% done** — proxy, app lock, biometric, cert pinning, custom CA, TLS enforcement, secure clipboard done |
| 8. Platform Polish | Medium | High | **~75% done** — macOS (Finder ext), Windows (Explorer menu, Hello), Android (SAF, Material You, widget, foreground, intents), iOS (Share ext, Siri, Stage Manager), Web (SW, Push, FSA, Share Target, OPFS, PWA) done |
| 9. Extensibility & CLI | Medium | High | **~85% done** — CLI, automation rules, local REST API done; plugin system pending |
| 10. Quality & Distribution | High | High | **2500+ tests** — CI/CD, docs, i18n (7 langs), fuzz, benchmarks, mock servers done; a11y, distribution pending |
| 11. Differentiation | High | Medium | **~95% done** — mounted drives, backup, migration wizard, storage analytics, provider comparison done; OCR pending |

---

## Milestone Targets

### v0.1.0 — "Solid Foundation" *(~95% complete)*
Phases 1 + 2. Secure credentials, streaming transfers, transfer queue, Riverpod, structured logging.
Remaining: multipart upload, large file streaming on Web.
*The app you'd trust with real data.*

### v0.2.0 — "See Everything" *(~90% complete)*
Phases 5.1-5.3. Preview (image/text/markdown/PDF), tabs+persistence, themes, responsive layout, bookmarks, tree view, grid view+thumbnails, drag-and-drop.
Remaining: column view, video/audio preview.
*The app that looks as good as Transmit.*

### v0.3.0 — "Connect Everywhere" *(done)*
Phase 3.1. S3 + FTP + Google Drive + OneDrive + Dropbox all done.
Remaining: connection profiles done, Tier 2 providers (Azure, B2, Mega, pCloud).
*The app that replaces Cyberduck.*

### v0.5.0 — "Privacy First" *(~90% complete)*
Phase 7. Encryption + key management + BIP39 + proxy + app lock + cert pinning done.
Remaining: Cryptomator compat, biometric auth.
*The app privacy advocates recommend.*

### v0.7.0 — "Always In Sync" *(~85% complete)*
Phase 4. Two-way sync, selective sync, offline replay, file cache (LRU), delta sync (content hash), filesystem watcher, system tray done.
Remaining: mobile background sync, placeholder files.
*The app that replaces Mountain Duck.*

### v1.0.0 — "Ready for Everyone"
Phases 8 + 10. Platform polish, i18n, a11y, app store distribution, auto-update.
*The app your non-technical friends can use.*

### v2.0.0 — "The Platform"
Phases 9 + 11. Plugins, CLI, automation, AI features, migration wizard, backup engine, mounted drives.
*The app developers build on top of.*

---

## Competitor Landscape

| Feature | CrispCloud (now) | CrispCloud (v2) | Cyberduck | Transmit | Commander One | Mountain Duck | FileBrowser |
|---------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| Open Source | AGPL | AGPL | GPL | No | No | No | Apache |
| Platforms | 6 | 6 | 3 (W/M/L) | macOS | macOS | 2 (W/M) | Web |
| E2E Encryption | **Any provider** | Any provider | Cryptomator | No | No | Cryptomator | No |
| Two-Panel | Yes | Yes + tabs | No | Yes | Yes | No | No |
| Providers | **11** | 14+ | 15+ | 12 | 12 | 15+ | Local |
| Streaming | **Yes (SFTP)** | All providers | Yes | Yes | Yes | Yes | No |
| Concurrent Xfer | **Yes (3)** | Configurable | Yes | Yes | No | Yes | No |
| File Preview | **Yes** | Full | Quick Look | Yes | Yes | Via OS | Yes |
| Secure Creds | **Yes** | Yes | Yes | Yes | Yes | Yes | No |
| Sync Engine | **Yes** | Yes | No | No | No | Yes | No |
| Mobile | Basic | Full | No | No | No | No | Responsive |
| CLI | No | Yes | Yes | No | No | No | No |
| Price | Free | Free | Free/$ | $55 | $30-60 | $39/yr | Free |

**CrispCloud's unique position:** The only open-source, truly cross-platform (6 platforms including mobile + web), privacy-first cloud file manager with two-panel interface, sync engine, and multi-provider support. No competitor covers all these axes simultaneously.

---

## Key Technical Decisions (Decide Before Phase 1)

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| State mgmt | **Riverpod 2** | Less boilerplate than BLoC, code-gen for type safety, better testability than Provider |
| Navigation | **go_router** | Deep linking, web URL support, declarative routing |
| Local DB | **drift** (SQLite) | Needed for sync metadata, file cache, settings; SQL power + web support (via sql.js) |
| Encryption | **cryptography** package | Platform-optimized (uses OS crypto libs), faster than pure-Dart pointycastle |
| Provider SDKs | Thin REST clients | Minimize dependency weight; use official SDK only when it's small and maintained |
| Background service | `workmanager` (Android) + BGTaskScheduler (iOS) + isolate (desktop) | No single cross-platform solution exists |
| Thumbnails | Generate in isolate + cache in drift | Non-blocking, persistent, shared across sessions |

---

*This plan is a living document. Priorities shift as user feedback arrives and the landscape evolves. Update this file — don't let it rot.*
