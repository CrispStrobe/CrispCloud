# PLAN.md — CrispCloud: The Ultimate Cross-Platform Cloud File Manager

> Previous hardening plan (completed 2026-05-29) moved to HISTORY.md.

## Vision

CrispCloud becomes the **open-source Cyberduck/Transmit/Commander One killer**: a single, beautiful, blazing-fast app that connects to *any* cloud or server, runs on *every* platform, and treats privacy and encryption as first-class citizens — not afterthoughts.

---

## Current State (v0.0.2-dev)

**What works:**
- Adapter pattern with **9 providers**: Filen, Internxt, SFTP, WebDAV, **S3** (+ S3-compat), **FTP/FTPS**, **Google Drive**, **OneDrive**, **Dropbox**
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
- **Version history**: view file versions (GDrive, Dropbox, OneDrive)
- **Share links**: generate provider-native shareable URLs
- **Duplicate finder**: MD5-based (local) or size-based (remote) duplicate detection
- **Sync engine**: two-way sync with **selective sync** (include/exclude globs) + **offline replay**
- **35 test files**, ~250+ unit tests + gated E2E suites

**What's still needed:**
- ~~Monolithic state (AppState)~~ — **Riverpod migration done** (8 focused providers)
- ~~Sync engine v1~~ — done (two-way, conflicts, selective sync, offline replay, filesystem watcher, system tray)
- ~~GDrive~~ + ~~OneDrive~~ + ~~Dropbox~~ — all Tier 1 providers done
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
- [ ] Web: encrypted IndexedDB with user-derived key (PBKDF2 from master password)
- [ ] Biometric unlock option (FaceID / TouchID / fingerprint) for mobile

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
- [ ] Split `file_toolbar.dart` (580 lines) into composable toolbar widgets
- [ ] `local_file_service.dart` (865 lines) → platform-specific files behind barrel export

### 1.4 Logging & Observability
- [x] Created `LogService` with `Log` named-logger class
- [x] Log levels: trace / debug / info / warn / error
- [x] In-memory ring buffer with configurable size + `LogConfig.export()`
- [x] Migrate existing `debugPrint` calls to `Log` (incremental, per-file) — 27+ files migrated, only legacy app_state.dart and local_file_service.dart remain
- [ ] Crash reporting integration (Sentry or self-hosted, opt-in)

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
- [ ] Desktop/Mobile: stream from disk via `LocalFileService` (wire `uploadStream` into AppState)
- [ ] Web: use `ReadableStream` via File System Access API for chunked reads
- [ ] Memory ceiling: never buffer more than 2 chunks ahead

### 2.2 Concurrent Transfers
- [x] `TransferQueue` service with configurable `maxConcurrent` (default 3)
- [x] Exponential backoff retry for transient errors (timeout, connection, 429, 503)
- [x] `TransferTask` with priority, `cancelAll()`, `clearCompleted()`
- [x] Wired `TransferQueue` into AppState — each file is a `TransferTask`, queue manages concurrency
- [x] Pause/Resume/Cancel already wired in `OperationsPanel` (verified)
- [ ] Per-provider rate limiting (respect API quotas)

### 2.3 Large File Support
- [ ] Multipart upload for providers that support it (S3, Filen chunked, Internxt)
- [ ] Resume interrupted uploads (track uploaded parts in local DB)
- [ ] Web: use `showSaveFilePicker` + writable stream for large downloads (no memory blob)
- [ ] Progress reporting at chunk granularity

### 2.4 Lazy Loading & Virtualization
- [x] `ListView.builder` with `itemExtent: 64` for O(1) scroll-to-index + skip off-screen layout
- [ ] Paginated listing for providers that support it (S3 `list-objects-v2`, WebDAV `PROPFIND Depth:1`)
- [ ] Incremental search/filter (client-side, don't re-fetch)
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
- [ ] **pCloud** — OAuth2, crypto folder
- [ ] **Storj** — decentralized, S3 gateway or native uplink
- [ ] **Hetzner Storage Box** — SFTP/WebDAV/CIFS, popular in EU
- [ ] **Nextcloud** — WebDAV + OCS API for native features (sharing, versions)

### 3.3 Provider Abstraction Improvements
- [x] Capability flags per provider: `supportsVersioning`, `supportsSharing`, `supportsSearch`, `supportsStreaming`, `supportsMultipart`, `supportsThumbnails`, `supportsTrash` — implemented in CloudStorageClient with per-adapter overrides
- [ ] Provider-specific settings (region, bucket, endpoint URL, custom headers)
- [ ] Multiple simultaneous connections to different providers
- [x] **Connection profiles**: save/load/delete named connections per provider via `ConnectionProfileService`
- [ ] Provider health check / latency indicator in toolbar
- [ ] Quota / usage display per provider

### 3.4 Multi-Cloud Operations
- [ ] Cloud-to-cloud transfer (remote A → remote B without downloading to local disk)
- [ ] Server-side copy when provider supports it
- [ ] Cross-provider file comparison (size, hash, modified date)
- [ ] Unified search across all connected providers

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
- [ ] Placeholder / "cloud-only" files on desktop (like OneDrive Files On-Demand)
- [ ] Smart sync: auto-evict files not accessed in N days
- [ ] Bandwidth scheduling: sync only on Wi-Fi, or during specified hours

### 4.3 Offline Mode
- [x] Queue operations while offline (OfflineQueue table in drift)
- [x] Cache recently accessed files for offline use — `FileCacheService` with LRU eviction, configurable max size, JSON index
- [x] Replay queued operations on reconnect — `replayOfflineQueue()` in SyncNotifier, chronological replay with error tracking
- [ ] Conflict resolution on reconnect
- [ ] Configurable cache size limit with LRU eviction

### 4.4 Background Sync Service
- [x] Desktop: system tray icon via `system_tray` package with context menu (Show / Sync All / Quit)
- [x] Sync status tooltip in system tray (syncing, pair count, last result)
- [ ] Mobile: `workmanager` (Android) + `BGTaskScheduler` (iOS)
- [ ] Native notifications for conflicts, errors, completion

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
- [ ] Provider-native thumbnails when available (GDrive, OneDrive, Dropbox)
- [ ] Thumbnail cache (local SQLite + file cache)
- [x] Markdown: rendered preview — `flutter_markdown` with theme-aware styling
- [x] PDF: page viewer — `pdfx` package, scrollable PDF in preview pane
- [ ] Video/Audio: streaming player

### 5.2 Tabbed Interface
- [x] Multiple tabs per panel — `PanelTab` model, tab bar widget, add/close/pin
- [x] Pin, close-all-but-this, duplicate tab (context menu)
- [x] Ctrl+T new tab, Ctrl+W close tab
- [x] Tab state persistence across app restarts — saved to SharedPreferences as JSON
- [ ] Drag files between tabs
- [x] Ctrl+Tab / Ctrl+Shift+Tab cycle between tabs

### 5.3 Responsive & Adaptive Layout
- [x] Mobile: swipe between panels (horizontal gesture)
- [x] Tablet/Desktop: side-by-side panels with draggable splitter (double-tap to reset)
- [ ] Desktop: optional detachable panels, multi-window support
- [ ] Web: responsive breakpoints improvements
- [ ] Layout presets: Commander (two-panel), Explorer (single-panel + tree), Gallery
- [ ] Pull-to-refresh on mobile

### 5.4 Theming & Customization
- [x] Built-in themes: System, Light, Dark, OLED Black, Nord, Dracula — with theme picker dialog
- [x] Custom accent color picker (11 preset colors + default)
- [x] Theme persistence via SharedPreferences
- [ ] Configurable font size and family
- [ ] Material You dynamic theming on Android
- [ ] Toolbar customization: show/hide buttons, reorder
- [ ] Rebindable keyboard shortcuts (persist to settings)

### 5.5 Advanced Navigation
- [x] Breadcrumb path bar (clickable path segments) — already existed in FileBreadcrumbs
- [x] Editable address bar: click edit icon → type path → Enter to navigate
- [x] Go-to-folder dialog (Ctrl+G)
- [x] Bookmarks / Favorites — `BookmarksNotifier` with SharedPreferences persistence, add/remove from tree sidebar
- [x] Recent locations — `RecentLocationsNotifier` with persistence, shown in tree sidebar
- [x] Go-to-folder dialog (Ctrl+G)
- [ ] Column view (Finder-style) as layout alternative
- [x] Grid / Gallery view for image-heavy folders (toggle in toolbar)
- [x] Tree view sidebar (expandable folder tree, toggle in app bar)

### 5.6 Drag & Drop
- [x] Drag between panels (local ↔ remote) via LongPressDraggable + DragTarget
- [x] Drag from OS file manager into app (desktop via `desktop_drop`)
- [ ] Drag from app to OS file manager (desktop)
- [ ] Visual drop zones with operation hint (copy vs move icon)
- [ ] Multi-file drag with count badge
- [ ] Touch drag on mobile/tablet

### 5.7 Status Bar & Info
- [x] Connection status indicator (provider name, connected/disconnected icon)
- [x] Items in folder / selected items count + total size
- [x] Active transfer count + progress
- [x] Active panel indicator (Local/Remote)
- [x] Live transfer speed (current + average + ETA) — in OperationProgress and OperationsPanel
- [ ] Free space / quota display (per provider)
- [ ] Sync status (when sync engine is active)

---

## Phase 6: Power User Features (Weeks 10-16)

### 6.1 Built-in Editor
- [x] Text/code editor with line numbers — full-screen `FileEditorDialog`, Ctrl+S save, unsaved-changes warning
- [x] Edit remote files in-place (download → edit → auto-upload on save)
- [x] Diff viewer: compare two files (local vs remote) — `DiffViewerDialog` with LCS diff, sync-scrolling, line numbers
- [ ] Auto-save with conflict detection
- [ ] Configurable: use built-in editor or launch external app

### 6.2 Terminal & Command Palette
- [ ] Embedded SSH terminal for SFTP connections
- [x] Command palette (Ctrl+Shift+P) — type to search, arrow keys, Enter to execute, context-aware
- [ ] Action history / undo recent operations

### 6.3 Advanced File Operations
- [x] Calculate folder sizes (recursive, context menu "Calculate Size")
- [x] Checksum verification (MD5 + SHA-256, context menu "Checksum", ChecksumService)
- [x] File permissions editor (SFTP: chmod, chown) — `PermissionsDialog` with visual rwx grid, octal presets, owner/group editing
- [ ] Symbolic link support (SFTP, local)
- [x] Archive support: extract .zip (context menu "Extract Here"), create .zip from selected files
- [x] Batch rename: 4 modes (find/replace with regex, numbering, prefix/suffix, extension), live preview, context menu integration

### 6.4 Sharing & Collaboration
- [x] Generate shareable links (provider-native: GDrive, Dropbox, OneDrive) — `ShareLinkDialog`
- [ ] Password-protected and expiring share links
- [ ] Share via native share sheet (mobile)
- [ ] Shared folder management UI

### 6.5 Version History
- [x] Show file versions when provider supports it (GDrive, Dropbox, OneDrive) — `VersionHistoryDialog`
- [x] Restore previous version — GDrive (revision download + re-upload), Dropbox (restore endpoint), OneDrive (restoreVersion action)
- [ ] Version diff for text files
- [ ] Local version snapshots before overwrite

### 6.6 Search & Filters
- [ ] Full-text search when provider supports it
- [ ] Saved searches / smart folders
- [ ] Filter by: type, size range, date range, owner
- [x] Regex search in file names — regex toggle in Find dialog, client-side filtering
- [x] Duplicate file finder (by hash for local, size for remote) — `DuplicateFinderDialog`
- [ ] Search results as virtual folder (act on results directly)

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
- [ ] Compatible with Cryptomator vault format (interop with other tools)

### 7.2 Secure Networking
- [x] Certificate pinning for known providers — `CertPinningService` with SPKI SHA-256 pins for Google/Microsoft/Dropbox/Amazon, wired into `ProxyHttpOverrides`
- [ ] Custom CA certificate support (corporate/self-signed)
- [x] HTTP/SOCKS5 proxy support — `ProxyService` with env auto-detection, `ProxyHttpOverrides` for global routing, `ProxySettingsDialog` UI
- [ ] Tor/onion routing support (optional)
- [ ] TLS version enforcement (minimum TLS 1.2)

### 7.3 Access Control
- [x] App lock: PIN/password required to open — `AppLockService` with salted SHA-256 hashing, `LockScreen` + `AppLockSetupDialog`
- [x] Auto-lock after configurable timeout — `_AppLockGate` with `WidgetsBindingObserver` lifecycle detection
- [x] Secure clipboard: auto-clear after 30s via `SecureClipboard` utility
- [ ] Disable screenshots on mobile (opt-in)

### 7.4 Privacy Dashboard
- [ ] Visual encryption status indicator per connection
- [ ] "Privacy Score" per provider (E2E > encrypted-at-rest > unencrypted)
- [ ] Audit log: local record of all operations
- [ ] Data flow visualization: show where your data goes

---

## Phase 8: Platform-Specific Polish (Weeks 12-18)

### 8.1 macOS
- [ ] Native menu bar integration (File, Edit, View, Go menus)
- [ ] Finder Quick Action extension: right-click → "Upload to CrispCloud"
- [ ] Share extension (share from any app)
- [ ] Spotlight integration for synced files
- [ ] Notarization + Developer ID signing
- [ ] Mac App Store distribution
- [ ] Touch Bar support (legacy but nice)

### 8.2 Windows
- [ ] Explorer context menu: right-click → "Upload to CrispCloud"
- [ ] Windows Hello biometric support
- [ ] Jump list (recent connections in taskbar)
- [ ] Microsoft Store (MSIX) distribution
- [ ] Virtual filesystem driver for mounted drives (like Mountain Duck)

### 8.3 Linux
- [ ] Nautilus/Dolphin/Thunar right-click integration
- [ ] D-Bus notifications
- [ ] Distribution: .deb, .rpm, AppImage, Flatpak, Snap
- [ ] GNOME Keyring / KDE Wallet integration (via flutter_secure_storage)
- [ ] XDG compliance (config in `~/.config/crispcloud/`)

### 8.4 Android
- [ ] SAF (Storage Access Framework) full integration
- [ ] Material You / dynamic theming
- [ ] Home screen widget: quick upload, recent files, sync status
- [ ] Foreground service for long transfers (with notification)
- [ ] Play Store + F-Droid distribution
- [ ] Intent handling: open-with, share-to CrispCloud

### 8.5 iOS / iPadOS
- [ ] Files.app integration (FileProvider extension) — CrispCloud as a location in Files
- [ ] Share extension (upload from Photos, Safari, etc.)
- [ ] Shortcuts/Siri integration ("Upload my screenshots to S3")
- [ ] Stage Manager multi-window (iPadOS)
- [ ] App Store distribution
- [ ] iCloud Keychain credential sync

### 8.6 Web (PWA)
- [ ] Service Worker: offline app shell, cache static assets
- [ ] Web Push notifications for long-running operations
- [ ] Persistent file handles via File System Access API
- [ ] Web Share Target API (receive shares from other PWAs)
- [ ] Installable PWA with standalone display mode
- [ ] OPFS (Origin Private File System) for offline cache

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
- [ ] Standalone Dart CLI for headless/scripted use:
  ```
  crisp connect sftp user@host
  crisp ls /remote/path
  crisp upload ./local /remote/
  crisp sync ./local s3://bucket/prefix --delete
  crisp search "*.log" --provider filen --recursive
  crisp share /remote/file.pdf --expires 7d
  ```
- [ ] Config file: `~/.config/crispcloud/config.yaml`
- [ ] Shell completions (bash, zsh, fish, PowerShell)
- [ ] JSON output mode for piping
- [ ] Usable in CI/CD pipelines

### 9.3 Automation & Rules
- [ ] Folder actions: auto-upload when files appear in watched folder
- [ ] Scheduled transfers (built-in cron)
- [ ] Webhooks: notify external services on events
- [ ] Rule engine: "when file matches *.pdf in /Scans/, upload to Filen/Documents/"
- [ ] Conflict-free automation (rules define conflict policy upfront)

### 9.4 Local API (Headless Mode)
- [ ] REST API on localhost for integration with other apps
- [ ] Operations: list, upload, download, sync, share
- [ ] Auth via local token file
- [ ] Useful for: NAS integration, media servers, backup scripts, Zapier-style workflows

---

## Phase 10: Quality & Distribution (Weeks 16-22)

### 10.1 Testing
- [ ] Unit test coverage >80% on all services and providers
- [ ] Widget tests for every screen and dialog
- [ ] Integration tests: full user flows (connect → browse → transfer → disconnect)
- [ ] Golden tests for UI regression
- [ ] Performance benchmarks: 1K-file listing, 1GB upload, 10K-file sync
- [ ] Fuzz testing: Unicode filenames, special chars, path traversal, long paths
- [ ] Provider mock server for offline CI testing

### 10.2 CI/CD
- [ ] Build artifacts for all 6 platforms on every PR
- [ ] Automated release pipeline: tag → build → sign → publish
- [ ] Code signing: macOS (Developer ID), Windows (Authenticode), Android (Play signing), iOS (App Store)
- [ ] Beta channels: TestFlight, Play internal track, GitHub pre-releases
- [ ] Auto-update: Sparkle (macOS), MSIX auto-update (Windows), in-app (mobile)
- [ ] Nightly builds from `main`

### 10.3 Internationalization (i18n)
- [ ] Extract all user-facing strings to ARB files
- [ ] Launch languages: English, German, French, Spanish, Portuguese, Chinese (Simplified), Japanese, Korean, Arabic (RTL)
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
- [ ] User guide with screenshots (hosted on docs site)
- [ ] Provider setup guides (API keys, CORS, SFTP config)
- [ ] Contributing guide: how to add a new provider
- [ ] Plugin development guide
- [ ] Architecture decision records (ADRs)
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
- [ ] On-device file categorization (documents, photos, videos, code, archives)
- [ ] Duplicate detection across all connected providers
- [ ] Storage analytics dashboard: what's using space, what's stale, what's duplicated
- [ ] Smart cleanup: "You have 3 copies of this 2GB video across Filen, S3, and local"
- [ ] OCR on images/PDFs for searchable content (on-device via `google_mlkit_text_recognition` or WASM)

### 11.2 Migration Wizard
- [ ] "Move from Provider A to Provider B" guided workflow
- [ ] Progress tracking, resumable, full conflict handling
- [ ] Preserve folder structure, metadata, timestamps
- [ ] Bandwidth throttling to avoid API rate limits
- [ ] Post-migration verification (hash comparison)
- [ ] Provider comparison: cost/GB, features, privacy score

### 11.3 Backup Engine
- [ ] Scheduled backups: local folder → cloud provider
- [ ] Incremental backups (only changed files, tracked via SQLite)
- [ ] Backup versioning (keep last N snapshots)
- [ ] Backup integrity verification (periodic hash check)
- [ ] Restore wizard: browse snapshots, restore individual files or full backup
- [ ] Backup encryption (independent of provider encryption)

### 11.4 Mounted Drives (Desktop)
- [ ] Mount remote storage as a local drive letter / mount point
- [ ] macOS: FUSE / macFUSE integration
- [ ] Windows: WinFsp / Dokan virtual filesystem
- [ ] Linux: FUSE mount
- [ ] Read/write with caching, works with any native app
- [ ] Automatic disconnect on sleep/hibernate

---

## Priority Matrix

| Phase | Impact | Effort | Status |
|-------|--------|--------|--------|
| 1. Foundation Hardening | Critical | Medium | **~95% done** — Riverpod, credentials, logging (migrated), formatters, decomposition all done |
| 2. Performance & Streaming | High | Medium | **~70% done** — streaming, queue, virtual scroll done; multipart/large-file pending |
| 3.1 S3 + GDrive + OneDrive + Dropbox | High | Medium | **All 4 done** |
| 3.2 Tier 2 providers | Medium | Medium | **FTP done** — Azure, B2, Mega, pCloud pending |
| 4. Sync Engine | Very High | Very High | **~85% done** — two-way, selective, offline replay+cache, watcher, tray, delta sync done; mobile bg pending |
| 5. UI/UX | High | Medium | **~85% done** — preview, tabs, themes, nav, DnD, tree, grid+thumbnails, bookmarks done |
| 6. Power User Features | Medium | High | **~75% done** — editor, palette, batch rename, archives, versions+restore, share, dupes, diff, permissions done |
| 7.1 Client-Side Encryption | High | High | **~90% done** — encryption + key management + BIP39 done; Cryptomator compat pending |
| 7.2-7.4 Security extras | Medium | Medium | **~70% done** — proxy, app lock, cert pinning, secure clipboard done; biometric pending |
| 8. Platform Polish | Medium | High | **P3 — Later** |
| 9. Extensibility & CLI | Medium | High | **P3 — Later** |
| 10. Quality & Distribution | High | High | **P3 — Ongoing** |
| 11. Differentiation | High | Medium | **P3 — After core** |

---

## Milestone Targets

### v0.1.0 — "Solid Foundation" *(~95% complete)*
Phases 1 + 2. Secure credentials, streaming transfers, transfer queue, Riverpod, structured logging.
Remaining: multipart upload, large file streaming on Web.
*The app you'd trust with real data.*

### v0.2.0 — "See Everything" *(~80% complete)*
Phases 5.1-5.3. Preview (image/text/markdown/PDF), tabs+persistence, themes, responsive layout, bookmarks, tree view, grid view, drag-and-drop.
Remaining: column view, thumbnails, video/audio preview.
*The app that looks as good as Transmit.*

### v0.3.0 — "Connect Everywhere" *(done)*
Phase 3.1. S3 + FTP + Google Drive + OneDrive + Dropbox all done.
Remaining: connection profiles, Tier 2 providers (Azure, B2, Mega, pCloud).
*The app that replaces Cyberduck.*

### v0.5.0 — "Privacy First" *(~80% complete)*
Phase 7. Encryption layer + key management + BIP39 recovery + proxy support + app lock done.
Remaining: Cryptomator compat, certificate pinning, biometric auth.
*The app privacy advocates recommend.*

### v0.7.0 — "Always In Sync" *(~75% complete)*
Phase 4. Two-way sync, selective sync (glob filters), offline replay, filesystem watcher, system tray done.
Remaining: delta sync, mobile background sync, offline file cache.
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
| Providers | **9** | 14+ | 15+ | 12 | 12 | 15+ | Local |
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
