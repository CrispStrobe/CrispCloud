# History

Audit trail of bugs found, issues discovered, and fixes applied.

## 2026-05-30 — Stabilization + Core Gaps (Option B)

### Stabilization (v0.1.0)
- **Dependency conflicts resolved**: fixed internxt_client intl constraint (>=0.19.0), pubspec_overrides.yaml uuid/libdbm overrides, file_selector_macos relaxed
- **14 analyze errors fixed**: AppLocalizations import, non-exhaustive switch (nextcloud/pcloud), EncryptedStorageWrapper missing methods, background_sync_mobile SecureStorage stubs, local_file_service web factory, file_context_menu void result, file_editor_dialog syntax, multi_cloud_dialog getter name, test mock stubs
- **3 test failures fixed**: search type filter exempts folders, multi_cloud unmodifiable list test passes valid object
- **Result**: 0 errors, 734 tests passing (up from 688)

### 1.1 Web Encrypted Credentials
- **Created `lib/services/secure_storage_web.dart`** (~220 lines):
  - `WebEncryptedStorage implements SecureStorage`: PBKDF2 key derivation + AES-256-GCM encryption
  - Values stored as base64 nonce+ciphertext+tag in localStorage under `crisp_enc_*` prefix
  - Salt persisted unencrypted; derived key held in memory only
  - `initialize(masterPassword)` with verification token for wrong-password detection
  - `WebStorageBackend` abstraction: `LocalStorageBackend` (browser) + `InMemoryWebStorageBackend` (tests)
- **Updated `lib/main.dart`**: `_MasterPasswordGate` widget prompts for password on web before app loads
- **Tests**: 16 tests (round-trip, wrong password, readMap/writeMap, unicode, delete, encrypted backing)

### 2.1 Streaming Transfers (Desktop/Mobile)
- **Updated `lib/providers/transfer_provider.dart`**:
  - Upload: `File.openRead()` stream with 2-chunk back-pressure → `client.uploadStream()`
  - Download: `client.downloadStream()` piped to `File.openWrite()` with byte-counting progress
  - Web fallback: buffer-based `uploadFile`/`downloadFileBytes`

### 2.3 Resume Interrupted S3 Multipart Uploads
- **Updated `lib/services/s3_client_adapter.dart`**:
  - Part tracking via SharedPreferences per uploadId (JSON with bucket, key, parts)
  - `listParts(key, uploadId)`: S3 ListParts API with pagination
  - `resumeMultipartUpload(remotePath, fileData)`: resumes from last successful part
  - `getInterruptedUploads()`: retrieves saved upload state
  - Failed uploads no longer abort — parts preserved for resume
- **Tests**: 14 tests (tracking CRUD, ListParts XML parsing, resume error handling, constants)

### 6.6 Full-Text Search
- **Updated `lib/services/cloud_storage_interface.dart`**: `supportsFullTextSearch` flag + `fullTextSearch(query, path)` with default fallback (download small text files, search locally)
- **Updated `lib/services/gdrive_client_adapter.dart`**: Drive API `fullText contains` query
- **Updated `lib/services/dropbox_client_adapter.dart`**: `/files/search_v2` content search with pagination
- **Updated `lib/services/onedrive_client_adapter.dart`**: Graph `/search/query` endpoint
- **Updated `lib/providers/search_provider.dart`**: `fullTextSearch()` method + `lastSnippets` for UI
- **Updated `lib/widgets/search_dialogs.dart`**: "Search file contents" checkbox, snippet display in results
- **Tests**: 13 tests (capability flags, fallback search, content matching, size limits, snippets)

## 2026-05-30 — Batch Session 3: Quick Wins + Medium Features

### Final Batch (5 items)
16. **Bandwidth scheduling** — `setSyncOnlyOnWifi()`, `setSyncHours(start, end)`, `isSyncAllowedNow` check gates `syncAll()`
17. **Provider-specific settings** — `ProviderSettingsDialog` with timeout, custom headers, follow redirects, SSL verify toggles
18. **Thumbnail cache stats** — `getDiskCacheSize()`, `getDiskCacheCount()`, `memoryCacheSize`, `cachedKeys` on ThumbnailService
19. **Touch drag on mobile** — reduced `LongPressDraggable` delay from 500ms to 200ms on Android/iOS
20. **Password-protected + expiring share links** — rewrote `ShareLinkDialog` with options UI, Dropbox `link_password` + `expires`, OneDrive `password` + `expirationDateTime`

### Quick Wins (10 items)
1. **Drag files between tabs** — `PanelTabBar` accepts `DragTarget<PanelDragData>`, `onFilesDroppedOnTab` callback
2. **Configurable font size/family** — `fontSizeProvider` (10-20px, default 13), `fontFamilyProvider` (system/monospace/serif/sansSerif), persisted
3. **Encryption status indicator** — lock icon in status bar when provider name contains "Encrypted"
4. **Privacy Score** — `privacyScore()` function (0-100) per provider, shield icon tooltip in status bar
5. **Local version snapshots** — `_saveLocalSnapshot()` saves backup to temp dir before each editor save
6. **Symlink support (SFTP)** — `isSymlink` flag detected via `SftpFileAttrs.isSymbolicLink` in listPath
7. **Disable screenshots** — `disableScreenshotsProvider` with SharedPreferences toggle
8. **Conflict resolution on reconnect** — offline replay checks remote modification time before upload ops, skips conflicts
9. **Font settings providers** — `_FontSizeNotifier`, `_FontFamilyNotifier` with SharedPreferences persistence

### Medium Features (6 items)
10. **Action history / undo** — `ActionHistoryService` with reversible delete/rename/move/copy/createFolder, Ctrl+Z shortcut, SnackBar undo button, `ActionHistoryNotifier` provider
11. **Smart sync auto-eviction** — `PlaceholderService.autoEvict()` converts files not accessed in N days back to placeholders, configurable per pair (7/14/30/60/90 days)
12. **Saved searches** — `SavedSearchService` with SharedPreferences persistence, `SavedSearchesDialog` with run/delete, "Save Search" button in find dialog
13. **External editor** — `preferExternalEditorProvider`, context menu submenu "Edit (Built-in)" / "Open with System Editor" using `url_launcher`
14. **Native share sheet** — `share_plus` for local files, download+share for remote files, "Share Link" + "Share File" options on mobile
15. **Server-side copy** — `copyPath()` on CloudStorageClient with `supportsServerSideCopy` flag, implemented for S3 (COPY), GDrive (files/copy), OneDrive (items/copy), Dropbox (copy_v2)

## 2026-05-30 — Batch Session 2: UI Polish, Search, Version Diff, Thumbnails, Audit, Layout

### 7.4 Audit Log
- **Created `lib/services/audit_service.dart`** (~240 lines):
  - `AuditEntry` model: timestamp, operation type, source/target path, provider, user, size, success/error
  - `AuditOperation` enum: upload, download, delete, rename, move, copy, createFolder, sync
  - JSON-lines storage at `<appDir>/audit.jsonl`
  - Methods: `log()`, `logSuccess()`, `logError()`, `getRecent()`, `exportAsJson()`, `clear()`
- **Created `lib/widgets/audit_log_dialog.dart`** (~270 lines):
  - Scrollable list with operation icons, timestamps, provider badges
  - Export to clipboard, confirm-before-clear
- **Updated `lib/providers/panel_provider.dart`**: audit logging in deleteFiles, renameFile, createFolder, moveFiles, copyFiles
- **Updated `lib/providers/transfer_provider.dart`**: audit logging in uploadFiles, downloadFiles

### 5.3 Layout Presets
- **Updated `lib/providers/core_providers.dart`**: `LayoutPreset` enum (commander, explorer, gallery), `layoutPresetProvider` with SharedPreferences persistence
- **Updated `lib/screens/file_browser_screen.dart`**:
  - Commander: two-panel layout (default)
  - Explorer: single panel with tree sidebar always visible
  - Gallery: single panel, force grid view
  - Layout preset PopupMenuButton in app bar

### 4.3 Configurable Cache Size
- **Updated `lib/services/file_cache_service.dart`**: unlimited mode (maxSizeBytes=0 skips eviction)
- **Created `lib/widgets/cache_settings_dialog.dart`** (~160 lines):
  - Shows used/max with progress indicator
  - Size options: 100MB, 250MB, 500MB, 1GB, 2GB, Unlimited
  - Clear cache with confirmation

### 5.3 Pull-to-Refresh on Mobile
- **Updated `lib/widgets/file_panel.dart`**: wrapped file list in `RefreshIndicator` for pull-to-refresh gesture

### 5.1 Provider-Native Thumbnails
- **Updated `lib/services/cloud_storage_interface.dart`**: added `getThumbnail(remotePath)` method (default returns null)
- **Updated `lib/services/gdrive_client_adapter.dart`**: fetches `thumbnailLink` from Drive API v3
- **Updated `lib/services/onedrive_client_adapter.dart`**: fetches thumbnail via Graph API `/thumbnails/0/medium/content`
- **Updated `lib/services/dropbox_client_adapter.dart`**: fetches thumbnail via `get_thumbnail_v2` endpoint (128x128 JPEG)

### 5.7 Status Bar Enhancements
- **Rewrote `lib/widgets/status_bar.dart`** as `ConsumerStatefulWidget`:
  - Quota display: shows used/total bytes when connected (lazy-fetched)
  - Sync status: shows last sync change count
  - Filter indicator: shows active filter query with filtered/total item count
  - Converted to StatefulWidget for async quota fetching

### 6.5 Version Diff for Text Files
- **Updated `lib/widgets/version_history_dialog.dart`**:
  - Added `_downloadVersionContent()`: downloads version content for GDrive/Dropbox/OneDrive
  - Added `_compareVersion()`: downloads old + current version, opens diff viewer
  - Added "Diff" button next to "Restore" for each version
- **Updated `lib/widgets/diff_viewer_dialog.dart`**:
  - Added `showDiffViewerFromContent()`: accepts raw text strings (no FileItem needed)
  - Added `_ContentDiffDialog`: standalone diff viewer for pre-loaded content
  - Extracted `computeLcsDiff()` as standalone reusable function

### 5.6 Multi-File Drag with Count Badge
- **Updated `lib/widgets/file_list_view.dart`**:
  - `FileListTile` now accepts `selectedFiles` parameter
  - When multiple files selected, drag includes all selected files
  - Drag feedback shows count badge (circle with file count) when >1 file
  - Drag label shows "+N" indicator

### 6.6 Advanced Search Filters
- **Updated `lib/providers/search_provider.dart`**:
  - Added `FileTypeCategory` enum (Documents, Images, Videos, Audio, Archives, Code)
  - Added filter fields: type, minSize, maxSize, dateAfter, dateBefore
  - Added `setFilters()` / `clearFilters()` / `matchesFilters()` / `applyFilters()`
  - Added `searchResults` list and `showResultsAsFolder` flag
- **Updated `lib/providers/panel_provider.dart`**:
  - Added `showSearchResults()` / `clearSearchResults()` for virtual folder display
- **Updated `lib/widgets/search_dialogs.dart`**:
  - Find dialog with type chips, size range fields, date pickers
  - "Show as Folder" button for search results
- **Tests**: `test/search_filters_test.dart` (30+ tests)

## 2026-05-30 — Batch Session: Providers, Performance, Sync, i18n, Quick Wins

### 2.4 Paginated Listing & Client-Side Filter
- **S3**: added explicit `max-keys: 1000` parameter to ListObjectsV2
- **PanelNotifier**: added `setFilter()` / `clearFilter()` / `filteredFiles` for client-side incremental filtering without re-fetching
- **FileToolbar**: filter icon button that opens filter dialog, live filtering as you type
- **StatusBar**: filter indicator when active
- **FilePanel**: uses `filteredFiles` instead of `files` for rendering

### 1.3 File Decomposition
- **Split `file_toolbar.dart`** into 3 files:
  - `file_toolbar.dart` — FileToolbar widget (toolbar buttons, sort menu, filter)
  - `file_breadcrumbs.dart` — FileBreadcrumbs widget (clickable path segments)
  - `file_selection_bar.dart` — FileSelectionBar widget (selection actions)
  - Re-exports from `file_toolbar.dart` for backward compatibility
- **Split `local_file_service.dart`** (866 lines) into:
  - `local_file_service.dart` — abstract interface + factory (conditional import)
  - `local_file_service_native.dart` — MacosFileService, DesktopFileService, MobileFileService
  - `local_file_service_web.dart` — WebFileService (virtual filesystem)

### 2.3 S3 Multipart Upload
- **Updated `lib/services/s3_client_adapter.dart`**:
  - Files >5MB automatically use multipart upload
  - `_initiateMultipartUpload()`: POST with `?uploads` query
  - `_uploadPart()`: PUT each part with partNumber + uploadId
  - `_completeMultipartUpload()`: POST XML with part ETags
  - `_abortMultipartUpload()`: cleanup on failure
  - `_multipartUpload()`: orchestrator with per-part progress reporting
  - Default part size: 8MB, minimum: 5MB (S3 requirement)
  - Added `Log` service integration

### 3.2 Nextcloud Provider
- **Created `lib/services/nextcloud_client_adapter.dart`** (~380 lines):
  - WebDAV at `/remote.php/dav/files/{username}/` for all file operations
  - OCS API for sharing (`POST /ocs/v2.php/apps/files_sharing/api/v1/shares`)
  - DAV versions API for version history and restore
  - Login format: `username@https://nextcloud.example.com`
  - Capabilities: versioning, sharing, search, trash all true
  - `restoreCredentials()` for auto-login
- **Created `lib/services/nextcloud_config_service.dart`**: SecureStorage CRUD
- **Updated integration points**: cloud_storage_interface, auth_provider, main.dart, connection_dialog
- **Tests**: `test/nextcloud_adapter_test.dart` (~195 lines, 20+ tests)

### 3.2 pCloud Provider
- **Created `lib/services/pcloud_client_adapter.dart`** (~400 lines):
  - Pure HTTP against `api.pcloud.com` / `eapi.pcloud.com` (EU auto-detection)
  - OAuth2 browser flow via `localhost:43826`
  - Folder ID caching for path-to-ID resolution
  - EU server auto-detection via `locationid` in token response
  - Capabilities: sharing, trash
- **Created `lib/services/pcloud_config_service.dart`**: SecureStorage CRUD
- **Updated integration points**: cloud_storage_interface, auth_provider, main.dart, connection_dialog
- **Tests**: `test/pcloud_adapter_test.dart` (~170 lines)

### 4.4 Mobile Background Sync
- **Created `lib/services/background_sync_service.dart`**: platform-agnostic API
- **Created `lib/services/background_sync_mobile.dart`**: Workmanager callback, notification service
- **Created `lib/services/background_sync_stub.dart`**: no-op for web/desktop
- **Added `workmanager: ^0.5.2`** and `flutter_local_notifications: ^17.2.4` to pubspec
- **Updated `lib/providers/sync_provider.dart`**: `enableBackgroundSync()` / `disableBackgroundSync()`
- **Updated `lib/widgets/sync_dialog.dart`**: background sync toggle + interval selector
- **Updated `lib/main.dart`**: `BackgroundSyncService.initialize()` on startup
- **Updated Android manifest**: RECEIVE_BOOT_COMPLETED, FOREGROUND_SERVICE, POST_NOTIFICATIONS
- **Updated iOS Info.plist**: BGTaskSchedulerPermittedIdentifiers, UIBackgroundModes

### 3.4 Multi-Cloud Operations
- **Created `lib/services/multi_cloud_service.dart`** (~270 lines):
  - Connection registry: add/get/remove cloud connections
  - `transferBetweenClouds()`: stream-based cloud-to-cloud transfer via TransferQueue
  - `compareFiles()`: cross-provider comparison producing `FileDiff` results
  - `searchAcrossProviders()`: concurrent search across all connections
- **Created `lib/providers/multi_cloud_provider.dart`**: `MultiCloudNotifier`
- **Created `lib/widgets/multi_cloud_dialog.dart`** (~340 lines): 3-tab dialog (Connections, Transfer, Compare & Search)
- **Tests**: `test/multi_cloud_test.dart` (16 tests)

### 10.3 i18n Setup
- **Added `flutter_localizations`** and `intl` to pubspec
- **Created `l10n.yaml`** configuration
- **Created `lib/l10n/app_en.arb`** (~150+ localized keys covering all UI strings)
- **Created `lib/l10n/app_de.arb`** (German translation)
- **Updated `lib/main.dart`**: `AppLocalizations.delegate` + `supportedLocales`

### Quick Wins
- **Per-provider rate limiting**: `TransferQueue.setProviderLimit()` and `setProviderRateLimit()` for configurable concurrent limits and minimum delay per provider
- **Provider health check**: `CloudStorageClient.healthCheck()` returns latency in ms
- **Provider quota**: `CloudStorageClient.getQuota()` returns used/total/free bytes
- **Visual drop zones**: upload/download icon + file count badge on drag hover
- **Auto-save with conflict detection**: 30s auto-save timer, remote modification check before save, conflict banner with Save Anyway / Reload / Dismiss

## 2026-05-30 — Platform: macOS Native Menu Bar

### 8.1 macOS Native Menu Bar
- **Updated `lib/screens/file_browser_screen.dart`**:
  - Wrapped `Scaffold` in `PlatformMenuBar` on macOS only (platform guard)
  - CrispCloud menu: About, Preferences (Cmd+,), Quit
  - File menu: New Tab (Cmd+T), Close Tab (Cmd+W), Connect (Cmd+K), Go to Path (Cmd+G)
  - View menu: Toggle Preview, Toggle Tree Sidebar, Sync Manager, Find Duplicates, Command Palette (Cmd+Shift+P)
  - All menu items wired to existing actions via Riverpod providers
  - Imported `command_palette.dart` for palette action

## 2026-05-30 — UI: Column View + Video/Audio Preview

### 5.5 Column View (Finder-style)
- **Created `lib/widgets/file_column_view.dart`** (~200 lines):
  - `FileColumnView`: Finder-style column layout with 220px columns
  - Each folder click navigates and shows contents in the panel
  - Horizontal scrolling with animated scroll-to-new-column
  - Compact 32px row height with file icon, name, size, and chevron for folders
  - Selection, double-tap, and right-click context menu support
- **Updated `lib/providers/core_providers.dart`**: `ViewMode` enum extended with `column`
- **Updated `lib/widgets/file_panel.dart`**: `_buildFileView()` handles `ViewMode.column`
- **Updated `lib/widgets/file_toolbar.dart`**: toolbar cycles list → grid → column → list

### 5.1 Video/Audio Preview
- **Added `video_player: ^2.9.2`** to pubspec.yaml
- **Updated `lib/widgets/preview_pane.dart`**:
  - Added `PreviewType.video` and `PreviewType.audio` to classifier
  - Supported extensions: mp4/mov/avi/mkv/webm/wmv/flv/m4v (video), mp3/wav/aac/flac/ogg/m4a/wma/opus (audio)
  - `_fetchMediaPreview()`: downloads remote files to temp, plays local files directly
  - Uses file cache for remote media (avoids re-download)
  - 100MB size limit for media (vs 20MB for images)
  - Web fallback: shows metadata (can't write to temp file)
  - `_MediaPlayer` widget: full inline player with:
    - Video display with aspect ratio, or music icon for audio
    - Seek slider with custom theme
    - Play/pause button with position/duration display
    - Volume toggle (mute/unmute)
    - Auto-updates via controller listener

## 2026-05-30 — Sync: Placeholder / Cloud-Only Files

### 4.2 Placeholder Files (OneDrive Files On-Demand style)
- **Created `lib/services/placeholder_service.dart`** (~230 lines):
  - `PlaceholderMeta` model: JSON metadata stored in `.crispcloud` stub files
  - `PlaceholderService`: manages cloud-only file stubs with the sync database
  - `createPlaceholder()`: writes lightweight JSON stub with remote path, size, hash, provider
  - `hydrate()`: downloads real file, replaces stub, updates DB status from `placeholder` to `synced`
  - `dehydrate()`: converts synced file back to placeholder (free up disk space)
  - `isFilePlaceholder()`, `getPlaceholders()`: query placeholder status from DB
  - `hydrateAll()`: batch download all placeholders for a sync pair
  - Static helpers: `isPlaceholder()`, `realName()`, `placeholderName()`
- **Updated `lib/services/sync_database.dart`**:
  - Added `SyncStatus.placeholder` enum value
  - Added `usePlaceholders` boolean column to `SyncPairs` table
  - Schema version bumped to 3 with migration
- **Updated `lib/services/sync_database.g.dart`**:
  - Added `includePatterns`, `excludePatterns`, `usePlaceholders` to `$SyncPairsTable`, `SyncPair`, `SyncPairsCompanion`
- **Updated `lib/services/sync_engine.dart`**:
  - Import `PlaceholderService`; skip `.crispcloud` files during local scan
  - `SyncAction.remoteSize` field for placeholder creation
  - All download actions now carry `remoteSize`
  - `_executeAction()`: when `pair.usePlaceholders` is true and file is new, creates placeholder instead of downloading
- **Updated `lib/providers/sync_provider.dart`**:
  - `addPair()` accepts `usePlaceholders` parameter
  - `setPlaceholders()`: toggle cloud-only mode per pair
  - `hydratePlaceholder()`: download a single placeholder file
  - `dehydrateFile()`: convert synced file back to placeholder
  - `hydrateAllPlaceholders()`: batch download all placeholders for a pair
- **Updated `lib/widgets/sync_dialog.dart`**:
  - Add Pair dialog: `SwitchListTile` for "Cloud-only files" toggle with cloud icon
  - Pair tile: cloud icon badge when placeholder mode is enabled
  - "Download All Cloud-Only Files" button per pair
- **Tests**: `test/placeholder_service_test.dart` (~100 lines, 12 tests):
  - PlaceholderMeta: toJson/fromJson round-trip, encode/decode, invalid content, version field, missing fields
  - Static methods: isPlaceholder detection, realName/placeholderName conversion, round-trip
  - SyncStatus: placeholder enum presence and distinctness
  - Constants: placeholderExtension value

## 2026-05-30 — Security: Biometric Authentication

### 7.3 Biometric Unlock (FaceID / TouchID / Fingerprint)
- **Added `local_auth: ^2.3.0`** to pubspec.yaml
- **Updated `lib/services/app_lock_service.dart`**:
  - Added `LocalAuthentication` dependency (injectable for testing)
  - `isBiometricAvailable()`: checks device support via `canCheckBiometrics` + `isDeviceSupported()`
  - `getAvailableBiometrics()`: returns list of biometric types on device
  - `isBiometricEnabled()` / `setBiometricEnabled()`: user preference persisted in SecureStorage
  - `authenticateWithBiometric()`: prompts biometric auth with `stickyAuth: true`, `biometricOnly: true`
  - `getBiometricLabel()`: returns human-readable name (Face ID / Fingerprint / Biometric)
  - `disable()` now also clears biometric setting
  - Web platform guard: all biometric methods return false/empty on web
- **Updated `lib/widgets/lock_screen.dart`**:
  - `LockScreen`: auto-prompts biometric on show when enabled + available
  - Biometric unlock button with appropriate icon (face/fingerprint/security)
  - "or" divider between biometric and PIN/password entry
  - Contextual subtitle text adapts to biometric availability
  - `AppLockSetupDialog`: `SwitchListTile` for biometric toggle with icon and description
  - Loads biometric availability on init, saves setting on dialog save
- **Updated `android/app/src/main/AndroidManifest.xml`**: `USE_BIOMETRIC` permission
- **Updated `android/.../MainActivity.kt`**: changed `FlutterActivity` to `FlutterFragmentActivity`
  (required by `local_auth` for biometric prompt on Android)
- **Updated `ios/Runner/Info.plist`**: `NSFaceIDUsageDescription` for Face ID permission prompt
- **Tests**: added 4 biometric tests to `test/security_features_test.dart`:
  - Biometric not enabled by default
  - setBiometricEnabled persists true/false
  - disable() clears biometric setting
  - Biometric enabled survives new service instance

## 2026-05-30 — Infrastructure: Cert Pinning, File Cache, Delta Sync, Thumbnails

### 7.2 Certificate Pinning
- **Created `lib/services/cert_pinning_service.dart`** (~175 lines):
  - `CertPinSet` model: hostname patterns + SPKI SHA-256 pin set
  - Built-in pins for Google (GTS roots), Microsoft (DigiCert), Dropbox, Amazon S3
  - `validateCertificate()`: checks cert SPKI hash against known pins
  - `getPinnedProviders()`: returns list of pinned providers for UI
  - Opt-in via SharedPreferences, toggle in proxy settings dialog
- **Updated `lib/services/proxy_service.dart`**:
  - `ProxyHttpOverrides` now accepts `CertPinningService?`, installs `badCertificateCallback`
  - `ProxyService.setCertPinning()`: links cert service for global overrides
  - `_installOverrides()`: activates both proxy and pinning together
- **Updated `lib/widgets/proxy_settings_dialog.dart`**: cert pinning toggle checkbox
- **Updated `lib/main.dart`**: loads `CertPinningService` on startup, passes to proxy service

### 4.3 Offline File Cache (LRU)
- **Created `lib/services/file_cache_service.dart`** (~230 lines):
  - `FileCacheService`: local file cache with JSON index
  - `put()` / `get()` / `remove()` / `clear()` operations
  - LRU eviction: evicts oldest-accessed files when over `maxSizeBytes` (default 500MB)
  - Evicts down to 80% of limit to avoid thrashing
  - `CacheEntry` model with remote path, provider, size, timestamps
  - Disk cache in `<appDir>/file_cache/files/` keyed by SHA-1
- **Updated `lib/widgets/preview_pane.dart`**: remote file previews check cache first,
  then download and cache for offline access
- **Updated `lib/providers/core_providers.dart`**: `fileCacheProvider`
- **Updated `lib/main.dart`**: initializes and overrides `FileCacheService`

### 4.1 Delta Sync (Content Hash)
- **Updated `lib/services/sync_engine.dart`**:
  - `_FileInfo.contentHash`: captures provider content hashes
  - `_isRemoteModified()`: uses content hash comparison when available (overrides timestamp)
  - `SyncAction.remoteContentHash`: passes hash through to DB update
  - `_updateEntryAfterSync()`: stores `remoteHash` in DB for future comparisons
  - Remote scan captures `content_hash` and `crc32Hash` from provider responses
- **Updated `lib/services/dropbox_client_adapter.dart`**: captures `content_hash` in listPath
- **Updated `lib/services/onedrive_client_adapter.dart`**: captures `crc32Hash` and `sha1Hash` from
  `file.hashes` in listPath responses

### 5.1 Thumbnail Generation
- **Created `lib/services/thumbnail_service.dart`** (~160 lines):
  - `ThumbnailService`: generates thumbnails via `compute()` isolate
  - Disk cache in `<appDir>/thumbnails/` keyed by SHA-1
  - Memory cache (LRU, 200 entries max) for instant display
  - `isSupported()`: checks file extension (jpg/png/gif/webp/bmp/ico)
  - `generate()`: decode → resize to 120x120 → encode PNG
  - `cacheProviderThumbnail()`: for server-side thumbnails (GDrive/OneDrive/Dropbox)
- **Updated `lib/widgets/file_grid_view.dart`**: grid tiles load thumbnails for image files,
  show image preview instead of generic icon
- **Updated `lib/providers/core_providers.dart`**: `thumbnailServiceProvider`
- **Updated `lib/main.dart`**: initializes and overrides `ThumbnailService`

### Tests
- **Created `test/infrastructure_test.dart`** (~250 lines, 25+ tests):
  - CertPinSet: host matching (exact, subdomain, case insensitive, multiple patterns)
  - CertPinningService: disabled by default, enable/disable, pinned providers list
  - CacheEntry: toJson/fromJson round-trip, date serialization
  - ThumbnailService: isSupported (images vs non-images), key formats, getCached miss
  - Delta sync: hash comparison (same/different hash, hash vs timestamp precedence, fallback)

## 2026-05-30 — Security & Power User: Proxy, App Lock, Version Restore, Permissions, Diff Viewer

### 7.2 HTTP/SOCKS5 Proxy Support
- **Created `lib/services/proxy_service.dart`** (~200 lines):
  - `ProxyConfig` model: type (none/http/socks5), host, port, username, password, noProxy bypass list
  - `ProxyConfig.fromEnvironment()`: auto-detects HTTP_PROXY/HTTPS_PROXY/NO_PROXY env vars
  - `ProxyConfig.toJson()`/`fromJson()` for persistence in SharedPreferences
  - `ProxyService`: load/save/clear config, `createHttpClient()` for explicit proxy client
  - `ProxyHttpOverrides`: global `HttpOverrides` that routes ALL `http.get/post/etc.` through proxy
  - `applyGlobally()`: installs overrides so all adapters use proxy without per-adapter changes
- **Created `lib/widgets/proxy_settings_dialog.dart`** (~180 lines):
  - Proxy type dropdown (None/HTTP/SOCKS5), host+port, username/password, no-proxy bypass list
  - Save/Reset/Cancel actions, validation
- **Updated `lib/main.dart`**: loads `ProxyService` on startup, calls `applyGlobally()`
- **Updated `lib/providers/core_providers.dart`**: added `proxyServiceProvider`
- **Updated `lib/widgets/connection_dialog.dart`**: "Proxy Settings" button before encryption toggle

### 7.3 App Lock (PIN/Password)
- **Created `lib/services/app_lock_service.dart`** (~100 lines):
  - `setup(code)`: salted SHA-256 hash (10,000 rounds), stored in SecureStorage
  - `verify(code)`, `disable()`, `changeCode()`, `getTimeout()`/`setTimeout()`
  - Rejects codes shorter than 4 characters
- **Created `lib/widgets/lock_screen.dart`** (~250 lines):
  - `LockScreen`: full-screen lock overlay with PIN/password input, 5 attempt limit
  - `AppLockSetupDialog`: setup/change code with confirmation, auto-lock timeout dropdown
- **Updated `lib/main.dart`**:
  - `_AppLockGate`: wrapper widget with `WidgetsBindingObserver` for auto-lock on app pause/resume
  - `appLockServiceProvider`: Riverpod provider for lock service
- **Updated `lib/screens/file_browser_screen.dart`**: "App Lock" entry in drawer menu (enable/disable/change)

### 6.5 Version Restore
- **Updated `lib/widgets/version_history_dialog.dart`**:
  - Implemented `_restoreVersion()` with confirmation dialog
  - `_restoreGDriveVersion()`: download revision content via revisions API, re-upload via PATCH
  - `_restoreDropboxVersion()`: Dropbox `files/restore` endpoint with rev parameter
  - `_restoreOneDriveVersion()`: Microsoft Graph `restoreVersion` action
  - Loading overlay during restore, auto-refresh panel + version list after restore
  - Fixed `_getToken()` to use actual adapter `accessToken` getter
- **Updated adapters** (gdrive, dropbox, onedrive): added public `accessToken` getter

### 6.3 SFTP Permissions Editor
- **Updated `lib/services/sftp_client_adapter.dart`**:
  - `getAttributes(path)`: returns SftpFileAttrs from stat
  - `chmod(path, mode)`: executes `chmod` via SSH command
  - `chown(path, owner)`: executes `chown` via SSH command
  - `getOwnership(path)`: reads user:group via `stat -c "%U:%G"`
  - `_shellEscape()`: safe path escaping for shell commands
- **Created `lib/widgets/permissions_dialog.dart`** (~230 lines):
  - Visual rwxrwxrwx grid with per-bit checkboxes (Owner/Group/Other)
  - Live octal + symbolic display (e.g. "755 rwxr-xr-x")
  - Quick preset chips: 644, 755, 700, 600, 777
  - Owner/Group text fields with SSH chown support
  - Loads current permissions on open, applies on Save
- **Updated `lib/widgets/file_context_menu.dart`**: "Permissions" entry for SFTP connections

### 6.1 Diff Viewer
- **Created `lib/widgets/diff_viewer_dialog.dart`** (~300 lines):
  - Side-by-side file comparison with LCS-based diff algorithm
  - Downloads both files (local from disk, remote via adapter)
  - Color-coded: green for added lines, red for removed
  - Line numbers, synchronized scrolling between panels
  - Header with change count, file labels with panel side
- **Updated `lib/widgets/file_context_menu.dart`**: "Compare" entry when same-named file exists in opposite panel

### Tests
- **Created `test/security_features_test.dart`** (~300 lines, 35+ tests):
  - ProxyConfig: disabled by default, HTTP/SOCKS5 enabled, toJson/fromJson round-trip, missing fields, disabled constant
  - ProxyService: default disabled, save/load round-trip, clear, createHttpClient
  - AppLockService: not enabled by default, setup/verify/disable, wrong code, changeCode, short code rejection, timeout
  - Diff algorithm: identical files, empty, added/removed lines, mixed changes, insert/delete in middle
  - Permission parsing: 755/644/700/777/000 octal↔symbolic, round-trip mode parsing

## 2026-05-30 — Quick Wins: Tab Cycling, Recent Locations, Debounce, Regex Search, Secure Clipboard, Connection Profiles, Live Speed

### 5.2 Ctrl+Tab Tab Cycling
- **Updated `lib/providers/panel_provider.dart`**: added `nextTab()` and `previousTab()` methods
  that cycle through tabs with wrap-around.
- **Updated `lib/screens/keyboard_shortcuts.dart`**: Ctrl+Tab = next tab, Ctrl+Shift+Tab = previous tab.
  Fixed plain Tab to only trigger panel switch when Ctrl is NOT pressed.

### 5.5 Recent Locations
- **Created `lib/providers/recent_locations_provider.dart`** (~95 lines):
  - `RecentLocationsNotifier`: tracks last 20 navigated paths per panel side.
  - Persisted in SharedPreferences as JSON. Deduplicates (re-visiting moves to top).
  - `forSide()` filters by PanelSide.
- **Updated `lib/providers/panel_provider.dart`**: records navigation in `navigateToPath()`.
- **Updated `lib/widgets/tree_sidebar.dart`**: "RECENT" section showing last 8 locations
  with click-to-navigate and clear-all button.
- **Added to barrel export** in `providers.dart`.

### 2.4 Debounced Directory Refresh
- **Updated `lib/providers/panel_provider.dart`**: added `refreshDebounced()` with configurable
  delay (default 500ms) that coalesces rapid refresh calls via `Timer`.
  Added `refreshFiles()` alias for widget compatibility.

### 6.6 Regex Search in File Names
- **Updated `lib/widgets/search_dialogs.dart`**: Find dialog now has a regex toggle checkbox.
  When enabled, uses `RegExp` to filter the current panel's file listing client-side.
  Invalid regex shows error snackbar. Non-regex mode uses the existing provider find API.

### 7.3 Secure Clipboard
- **Created `lib/utils/secure_clipboard.dart`**: `SecureClipboard.copy()` sets clipboard data
  and auto-clears after 30 seconds via a `Timer`.
- **Updated `lib/widgets/key_management_dialog.dart`**: uses `SecureClipboard` for all
  key/mnemonic/bundle copy operations. Shows "(auto-clears in 30s)" in snackbar.

### 3.3 Connection Profiles
- **Created `lib/services/connection_profiles.dart`** (~85 lines):
  - `ConnectionProfile` model: name, provider, fields map.
  - `ConnectionProfileService`: CRUD operations via SecureStorage, keyed by name+provider.
- **Updated `lib/widgets/connection_dialog.dart`**:
  - Loads profiles for selected provider on init and provider switch.
  - Profile dropdown to load saved configurations into form fields.
  - "Save as Profile" button with name prompt dialog.
  - Delete profile dialog with per-profile delete buttons.
  - `_collectFields()` / `_applyProfile()` for field serialization per provider type.

### 5.7 Live Transfer Speed
- **Updated `lib/models/operation_progress.dart`**: added speed tracking fields:
  - `currentSpeed` (bytes/sec, smoothed over 500ms windows)
  - `averageSpeed` (total bytes / elapsed time)
  - `estimatedSecondsRemaining` (remaining bytes / current speed)
  - `updateProgress()` now calculates instantaneous speed.
- **Updated `lib/widgets/operations_panel.dart`**:
  - Per-operation status line shows speed + ETA (e.g. "45% • 2.3 MB / 5.1 MB • 1.2 MB/s • 2s left")
  - Panel header shows aggregate speed across all active transfers.

## 2026-05-30 — Phase 7.1+6.1+5.1+4.2+4.3+1.4: Key Management, Editor, PDF, Selective Sync, Offline Replay, Log Migration

### 7.1 Key Management (BIP39 Mnemonic Recovery)
- **Updated `lib/services/encryption_service.dart`**: added key management methods:
  - `exportKeyAsHex()` / `importKeyFromHex()` — raw 32-byte key as hex string
  - `generateMnemonic()` — BIP39 24-word mnemonic encoding the 256-bit key
  - `recoverKeyFromMnemonic()` — recover key from mnemonic phrase
  - `exportBackupBundle()` / `importBackupBundle()` — JSON bundle with mnemonic, salt, and verification token
- **Updated `lib/providers/auth_provider.dart`**: `encryptionKey`/`encryptionSalt` getters,
  `enableEncryptionWithKey()` for importing pre-existing keys.
- **Created `lib/widgets/key_management_dialog.dart`** (~300 lines):
  - Two tabs: Export/Backup and Import/Recover
  - Export: shows BIP39 mnemonic, raw hex key, and full backup bundle with copy buttons
  - Import: restore from backup bundle (recommended), mnemonic (24 words), or raw hex key
  - Validation and error feedback on import
- **Wired into app bar**: key icon appears when encryption is active.

### 6.1 Built-in Code Editor
- **Created `lib/widgets/file_editor_dialog.dart`** (~280 lines):
  - Full-screen editor with line number gutter
  - Downloads file content (remote via `downloadFileBytes`, local via `File`)
  - Editable `TextField` with monospace font
  - Ctrl+S save shortcut (uploads back to remote or writes to local)
  - Modified indicator badge, unsaved changes confirmation dialog
  - Auto-refreshes panel after save
- **Updated `lib/widgets/file_context_menu.dart`**: "Edit" option for text/code files
  (40+ extensions), appears for single non-folder files.

### 5.1 PDF Preview
- **Added `pdfx: ^2.6.0`** to pubspec.yaml.
- **Updated `lib/widgets/preview_pane.dart`**:
  - Added `PreviewType.pdf` to classification (`.pdf` extension)
  - Opens PDF via `PdfDocument.openData()` from downloaded bytes
  - Renders with `PdfView` widget (scrollable, vertical, no page snapping)
  - 20MB size limit for PDF preview (same as images)

### 4.2 Selective Sync
- **Updated `lib/services/sync_database.dart`**: added `includePatterns` and `excludePatterns`
  text columns to `SyncPairs` table. Schema version bumped to 2 with migration.
- **Updated `lib/services/sync_engine.dart`**: `passesFilter()` static method using `package:glob`
  for pattern matching. Integrated into `syncPair()` to skip paths that don't pass filters.
- **Updated `lib/widgets/sync_dialog.dart`**: include/exclude pattern fields in Add Pair dialog
  with helper text and filter icons.
- **Updated `lib/providers/sync_provider.dart`**: `addPair()` accepts `includePatterns`/`excludePatterns`.

### 4.3 Offline Replay
- **Updated `lib/providers/sync_provider.dart`**: added offline queue methods:
  - `enqueueOfflineOp()` — queue upload/download/delete/rename/move for later
  - `replayOfflineQueue()` — replays all pending ops chronologically per pair,
    marks completed ops, records errors on failures
  - `_executeOfflineOp()` — executes individual ops (upload, download, delete, rename, move)
- **Updated `lib/widgets/sync_dialog.dart`**: "Replay Offline" button in dialog actions.

### Tests for Recent Features
- **Created `test/recent_features_test.dart`** (~300 lines, 30+ tests):
  - Bookmark model: toJson/fromJson round-trip, side handling
  - BookmarksNotifier: add/remove, dedup, side separation, SharedPreferences persistence
  - Key management: hex export/import, BIP39 mnemonic round-trip, backup bundle round-trip,
    tamper detection, validation errors
  - PanelTab: label derivation, Windows paths, pin, copyWith, updateLabel
  - SyncEngine.passesFilter: include, exclude, precedence, glob **, whitespace trimming
  - Duplicate finder logic: size grouping, folder filtering, zero-size skip
  - FileItem: equality by uuid/path, sizeFormatted ranges
  - SyncResult: addition, hasChanges

### 1.4 debugPrint → Log Migration
- **Migrated 33+ files** from `debugPrint` to structured `Log` service:
  - All Riverpod providers (auth, panel, transfer, sync, bookmarks)
  - All cloud adapters (S3, FTP, SFTP, WebDAV, GDrive, OneDrive, Dropbox, Internxt, Filen)
  - All config services (9 files)
  - Core services (sync_engine, sync_watcher, transfer_queue, tray_service, cloud_storage_interface, secure_storage_service)
  - Widgets (connection_dialog, file_list_view), models (operation_progress)
  - main.dart, share_service, receive_service, webdav_filesystem
- **Remaining**: app_state.dart (legacy), local_file_service.dart (platform-specific), bookmark/macos_bookmark (platform startup), log_service.dart (correct — uses debugPrint for output)
- Stripped all emoji from log messages, used appropriate levels (info/debug/warn/error)

## 2026-05-29 — Phase 5.3+5.5+5.6: UI/UX Improvements (PLAN.md)

### 5.3 Responsive Layout
- **Created `lib/widgets/panel_splitter.dart`** (~120 lines):
  - Draggable splitter between two panels with optional third pane (preview).
  - Mouse cursor changes to resize handle on hover.
  - Double-tap handle to reset to 50/50 split.
  - Configurable min/max ratio (default 0.2–0.8).
  - Split ratio persisted via `panelSplitRatioProvider`.
- **Mobile swipe**: added horizontal swipe gesture to single-panel layout
  for switching between Local and Remote panels.
- **Updated `file_browser_screen.dart`**: replaced fixed `Expanded` + divider
  with `PanelSplitter` widget.

### 5.5 Tree View Sidebar
- **Created `lib/widgets/tree_sidebar.dart`** (~180 lines):
  - Toggleable sidebar (220px) showing folder hierarchy for active panel.
  - Header with panel type indicator and refresh button.
  - Folder nodes with indent levels, open/closed icons, click to navigate.
  - Current directory highlighted.
- **Added `showTreeSidebarProvider`** (StateProvider<bool>) to core_providers.
- **App bar toggle**: tree icon button to show/hide sidebar.
- **Only shown on wide layouts** (>800px).

### 5.5 Grid/Gallery View
- **Created `lib/widgets/file_grid_view.dart`** (~120 lines):
  - `GridView.builder` with `SliverGridDelegateWithMaxCrossAxisExtent` (140px cards).
  - Icon cards with file name (2-line truncation) and size underneath.
  - Selection highlight with primary border.
  - Same interactions as list view: tap, double-tap, right-click context menu.
- **Added `localViewModeProvider` / `remoteViewModeProvider`** (StateProvider<ViewMode>).
- **Toolbar toggle**: list/grid icon button in `FileToolbar`.
- **FilePanel**: `_buildFileView()` switches between `FileListView` and `FileGridView`.

### 5.6 Drag & Drop Between Panels
- **`PanelDragData`** class carries source side + file list during drag.
- **`FileListTile`**: wrapped in `LongPressDraggable<PanelDragData>` with Material feedback
  chip showing file icon + name. Original tile shows at 30% opacity while dragging.
- **`FilePanel`**: wrapped content in `DragTarget<PanelDragData>` that accepts drops
  from the opposite panel only. Triggers `uploadFiles` or `downloadFiles` on accept.
  Visual blue border highlight when a valid drop hovers.

## 2026-05-29 — Phase 4 continued: Filesystem Watcher + Background Sync

### 4.1 Filesystem Watcher
- **Added `watcher: ^1.1.0`** to pubspec.yaml.
- **Created `lib/services/sync_watcher.dart`** (~100 lines):
  - `SyncWatcherService`: manages `DirectoryWatcher` instances per sync pair.
  - Debounced event handling (5s default) — avoids syncing on every keystroke.
  - `watchPair()`, `unwatchPair()`, `unwatchAll()`, `watchedPairIds`.
  - `PollingWatcherService` fallback for web/mobile (configurable interval).
- **Integrated into `SyncProvider`**: `enableWatch()` / `disableWatch()` methods.
  Auto-starts watchers for enabled pairs on load. Stops watchers for disabled pairs.
- **Sync dialog**: eye icon toggle for auto-sync (watch enable/disable).

### 4.4 Background Sync — System Tray
- **Added `system_tray: ^2.0.3`** to pubspec.yaml.
- **Created `lib/services/tray_service.dart`** (~100 lines):
  - System tray icon with context menu: Show CrispCloud, Sync All, Quit.
  - Tooltip updates with sync status (syncing, pair count, last result).
  - Left-click shows app, right-click opens menu.
  - Platform guard: only macOS/Windows/Linux.
- **Integrated into `SyncProvider`**: `initTray()` method, `_updateTray()` called
  on every sync state change. Tray disposed with provider.

## 2026-05-29 — Phase 4.1: Sync Engine (PLAN.md)

### 4.1 Two-Way Sync Engine
- **Added `drift: ^2.22.1`** and `sqlite3_flutter_libs: ^0.5.28` to pubspec.yaml.
  Added `drift_dev` + `build_runner` to dev_dependencies.
- **Created `lib/services/sync_database.dart`** + `.g.dart` (~700 lines total):
  - 3 drift tables: `SyncPairs`, `SyncEntries`, `OfflineQueue`.
  - `SyncPairs`: name, localPath, remotePath, provider, conflictPolicy (5 policies),
    direction (twoWay/uploadOnly/downloadOnly), enabled, lastSyncAt.
  - `SyncEntries`: per-file state with localHash, remoteHash, localModified,
    remoteModified, localSize, remoteSize, status (7 states), error, isFolder.
    Unique constraint on (pairId, relativePath).
  - `OfflineQueue`: queued operations for offline mode (replay on reconnect).
  - CRUD methods: getAllPairs, getEnabledPairs, upsertEntry, getConflicts,
    getPendingEntries, enqueueOffline, markOfflineCompleted.
  - Uses `NativeDatabase.createInBackground` for non-blocking I/O.
  - `SyncDatabase.forTesting(NativeDatabase.memory())` for tests.
- **Created `lib/services/sync_engine.dart`** (~400 lines):
  - `SyncEngine.syncPair(pair, client)` — full two-way sync:
    1. Recursive local filesystem scan → `Map<relativePath, _FileInfo>`.
    2. Recursive remote scan via `CloudStorageClient.listPath()`.
    3. Compare both against last-known state in DB.
    4. Produce `SyncAction` list (upload/download/deleteLocal/deleteRemote/
       createFolder/conflict/skip).
    5. Apply conflict policy (newestWins, localWins, remoteWins, keepBoth, manual).
    6. Execute actions: uploads, downloads, folder creation, deletes.
    7. Update DB entries after each successful action.
    8. Update pair lastSyncAt.
  - `SyncDirection` support: twoWay, uploadOnly, downloadOnly.
  - Change detection: compares modified time (1s tolerance) + file size.
  - Handles edge cases: file deleted on one side while modified on other,
    new files on both sides, folder creation before file upload.
  - `SyncResult` with counts: uploaded, downloaded, deletedLocal, deletedRemote,
    conflicts, errors, errorMessages.
- **Created `lib/providers/sync_provider.dart`** (~140 lines):
  - `SyncNotifier` (ChangeNotifierProvider): manages sync pairs CRUD,
    `syncAll()`, `syncOne(pairId)`, conflict resolution.
  - Exposes `isSyncing`, `currentPairName`, `lastResult`, `pairs` to UI.
  - Added to barrel export in `providers.dart`.
- **Created `lib/widgets/sync_dialog.dart`** (~230 lines):
  - Sync Manager dialog with pair list, sync-all button, last result banner.
  - Add Pair dialog: name, local path, remote path, conflict policy dropdown
    (5 options), direction dropdown (3 options).
  - Per-pair controls: enable/disable toggle, sync now button, delete button.
  - Relative time display for last sync ("5m ago", "2h ago").
- **Updated `status_bar.dart`**: sync status indicator (spinning when syncing,
  pair count when idle).
- **Updated `file_browser_screen.dart`**: sync icon button in app bar opens
  Sync Manager dialog.
- **Tests**: `test/sync_engine_test.dart` — 20 tests covering:
  - SyncPair CRUD (insert, getEnabled, delete)
  - SyncEntry CRUD (upsert, getEntry, getConflicts, getPending, deleteForPair)
  - OfflineQueue (enqueue, markCompleted, clearCompleted)
  - SyncResult arithmetic and hasChanges
  - Enum completeness (ConflictPolicy, SyncStatus, SyncDirection)
  - SyncAction toString and folder flag

## 2026-05-29 — Phase 3.1: Dropbox Provider (PLAN.md)

### 3.1 Dropbox Provider
- **Created `lib/services/dropbox_client_adapter.dart`** (~400 lines):
  - Full `CloudStorageClient` implementation using pure HTTP + Dropbox API v2.
  - No Dropbox SDK dependency — uses `package:http` + `url_launcher` for OAuth2.
  - OAuth2 browser flow: redirect to localhost:43825, `token_access_type: offline`
    to request refresh tokens.
  - `listPath` via `POST /files/list_folder` with cursor-based pagination (`has_more`).
  - `uploadFile` via `POST /files/upload` with `Dropbox-API-Arg` header (overwrite mode).
  - `downloadFileBytes` via `POST /files/download` with `Dropbox-API-Arg` header.
  - `createFolderPath` via `POST /files/create_folder_v2` (409 conflict = exists = OK).
  - `deletePath` via `POST /files/delete_v2`.
  - `movePath` / `renamePath` via `POST /files/move_v2`.
  - Dropbox uses "" for root path, `/` prefix for all other paths.
  - Capability flags: versioning, sharing, search, thumbnails, trash all true.
  - Token revocation on logout via `/auth/token/revoke`.
  - Auto-refresh tokens, `restoreCredentials()` for auto-login.
- **Created `lib/services/dropbox_config_service.dart`**: Credential CRUD via `SecureStorage`.
- **Added `CloudProvider.dropbox`** to enum and factory.
- **Updated all integration points**: `auth_provider.dart`, `main.dart`, `app_state.dart`,
  `connection_dialog.dart` (App Key + optional Secret fields, OAuth2 info banner),
  `secure_storage_service.dart` migration list.
- **Refactored connection dialog 2FA skip**: replaced individual provider checks with
  `skipTwoFa` boolean and `isOAuth` flag for password field hiding.
- **Tests**: `test/dropbox_adapter_test.dart` — 16 tests covering capability flags,
  login validation, config CRUD, restoreCredentials, factory, logout.

## 2026-05-29 — Phase 3.1: OneDrive Provider (PLAN.md)

### 3.1 OneDrive / SharePoint Provider
- **Created `lib/services/onedrive_client_adapter.dart`** (~380 lines):
  - Full `CloudStorageClient` implementation using pure HTTP + Microsoft Graph API v1.0.
  - No MSAL dependency — uses `package:http` + `url_launcher` for OAuth2 browser flow.
  - Path-based addressing via Graph API (`/me/drive/root:/{path}:/children`) —
    no ID-resolution caching needed (simpler than GDrive).
  - OAuth2 via Azure AD common endpoint: browser → localhost:43824 redirect → token exchange.
  - Auto-refresh tokens, `restoreCredentials()` for auto-login.
  - `listPath` with `@odata.nextLink` pagination, `$top=200`.
  - `uploadFile` via `PUT .../content` (simple upload, works up to ~4MB per Graph docs;
    larger files should use upload sessions — TODO).
  - `downloadFileBytes` via `@microsoft.graph.downloadUrl` redirect.
  - `createFolderPath` with recursive creation, `conflictBehavior: fail` (409 = exists = OK).
  - `deletePath`, `movePath` (via PATCH parentReference), `renamePath` (via PATCH name).
  - Capability flags: `supportsVersioning`, `supportsSharing`, `supportsSearch`,
    `supportsThumbnails`, `supportsTrash` all true.
  - Fetches user email via `/me?$select=userPrincipalName,mail`.
- **Created `lib/services/onedrive_config_service.dart`**: Credential CRUD via `SecureStorage`.
- **Added `CloudProvider.onedrive`** to enum and factory.
- **Updated all integration points**: `auth_provider.dart`, `main.dart`, `app_state.dart`,
  `connection_dialog.dart` (Azure App ID + optional Client Secret fields, OAuth2 info banner),
  `secure_storage_service.dart` migration list.
- **Tests**: `test/onedrive_adapter_test.dart` — 16 tests covering capability flags,
  login validation, config CRUD, restoreCredentials, factory, logout.

## 2026-05-29 — Phase 3.1: Google Drive Provider (PLAN.md)

### 3.1 Google Drive Provider
- **Created `lib/services/gdrive_client_adapter.dart`** (~450 lines):
  - Full `CloudStorageClient` implementation using pure HTTP + Drive REST API v3.
  - No `googleapis` or `google_sign_in` SDK dependency — uses `package:http` directly.
  - OAuth2 browser flow: opens system browser → Google auth → localhost redirect on
    port 43823 → exchanges auth code for access + refresh tokens.
  - Auto-refresh: detects token expiry, refreshes via stored refresh_token.
  - `restoreCredentials()` for auto-login on app restart (like S3 adapter).
  - Path-to-ID resolution with caching (`_pathToId` map) — Google Drive uses file IDs
    internally, adapter translates `/path/segments` to folder IDs by walking the tree.
  - `listPath` with pagination via `nextPageToken`, returns folders + files.
  - `uploadFile` with multipart upload; detects existing files and updates instead of creating duplicates.
  - `downloadFileBytes` via `?alt=media` parameter.
  - `createFolderPath` creates intermediate folders recursively.
  - `deletePath`, `movePath` (via add/remove parents), `renamePath` (via PATCH name).
  - Capability flags: `supportsVersioning`, `supportsSharing`, `supportsSearch`,
    `supportsThumbnails`, `supportsTrash` all true.
  - Fetches user email via userinfo endpoint for display.
- **Created `lib/services/gdrive_config_service.dart`**: Credential CRUD via `SecureStorage`,
  same pattern as S3ConfigService.
- **Added `CloudProvider.gdrive`** to enum and factory in `cloud_storage_interface.dart`.
- **Updated all integration points**:
  - `auth_provider.dart`: `_createConfigForProvider`, `ensureAuthenticated`,
    `_attemptAutoLogin` (uses `restoreCredentials()`), `_clearCredentials`.
  - `main.dart`: `_getDefaultProvider`, `_createConfigService`.
  - `app_state.dart`: `switchProvider` switch statement, config service creation (backward compat).
  - `connection_dialog.dart`: Google Drive dropdown option, Client ID + Client Secret fields,
    OAuth2 info banner, password field hidden for GDrive, 2FA check skipped.
  - `secure_storage_service.dart`: `gdrive_credentials` added to migration key list.
- **Tests**: `test/gdrive_adapter_test.dart` — 18 tests covering capability flags,
  provider name, login format validation, config service CRUD, restoreCredentials edge cases,
  factory creation, logout.
- **Tests**: `test/gdrive_live_test.dart` — gated E2E tests (GDRIVE_CLIENT_ID + GDRIVE_REFRESH_TOKEN)
  for restore, listPath, folder CRUD, upload/download round-trip.

## 2026-05-29 — Phase 1.2: Riverpod State Management Migration (PLAN.md)

### 1.2 State Management Overhaul — Riverpod 2
- **Added `flutter_riverpod: ^2.5.1`** to pubspec.yaml; kept `provider` for ThemeService bridge.
- **Created `lib/providers/` directory** with 7 files:
  - `core_providers.dart` — `secureStorageProvider`, `configPathProvider`, `localFileServiceProvider`,
    `activePanelProvider`, `showPreviewProvider` (simple state providers).
  - `error_provider.dart` — `ErrorNotifier` (`ChangeNotifierProvider`): error queue with
    `addError()`, `clearErrors()`, `clearLastError()`.
  - `auth_provider.dart` — `AuthNotifier` (~250 lines): login/logout, provider switching,
    auto-login on startup, encryption toggle, `ensureAuthenticated()`.
    Overridden in `ProviderScope` with startup config from `main()`.
  - `panel_provider.dart` — `PanelNotifier` (~400 lines, family keyed by `PanelSide`):
    file listing, selection (toggle/shift/ctrl/selectAll/clear), sort (name/size/date/ext),
    navigation (up/into/toPath), tabs (add/close/select/pin), local file loading,
    remote file loading, file operations (delete/rename/create/move/copy).
  - `transfer_provider.dart` — `TransferNotifier` (~260 lines): wraps `TransferQueue`,
    tracks `OperationProgress` list, `uploadFiles()`/`downloadFiles()` with batch support,
    pause/resume/cancel per operation.
  - `search_provider.dart` — `SearchNotifier`: `searchFiles()`, `findFiles()`, `isSearching`.
  - `providers.dart` — barrel export.
- **Updated `main.dart`**: `ProviderScope` wraps entire app with overrides for
  `secureStorageProvider`, `configPathProvider`, and `authProvider`. `MyApp` is now a
  `ConsumerWidget`. ThemeService exposed via both `ChangeNotifierProvider` (Riverpod)
  and legacy `Provider` bridge for `ThemePickerDialog`.
- **Migrated all widgets** to `ConsumerWidget` / `ConsumerStatefulWidget`:
  - `file_browser_screen.dart` — reads `authProvider`, `activePanelProvider`,
    `showPreviewProvider`, `panelProvider(side)`, `transferProvider`.
  - `file_panel.dart` — reads `panelProvider(side)`, `errorProvider`, `authProvider`.
  - `file_toolbar.dart` — `FileToolbar`, `FileBreadcrumbs`, `FileSelectionBar` all
    converted to `ConsumerWidget`; removed `AppState appState` parameter.
  - `file_list_view.dart` — `FileListView` now `ConsumerWidget`.
  - `status_bar.dart` — reads `authProvider`, `activePanelProvider`, `panelProvider`,
    `transferProvider`.
  - `operations_panel.dart` — reads `transferProvider`; `_OperationTile` receives
    `onPause`/`onResume` callbacks instead of reading AppState directly.
  - `connection_dialog.dart` — `ConsumerStatefulWidget`; reads `authProvider`,
    refreshes remote panel after login.
  - `keyboard_shortcuts.dart` — `handleKeyEvent` takes `WidgetRef ref` instead of `AppState`.
  - `screen_dialogs.dart` — all dialog helpers take `WidgetRef ref` instead of `AppState`.
  - `file_context_menu.dart` — all functions take `WidgetRef ref`.
  - `search_dialogs.dart` — takes `WidgetRef ref`.
  - `command_palette.dart` — `ConsumerStatefulWidget`.
  - `preview_pane.dart` — `ConsumerStatefulWidget`; removed `appState` parameter.
  - `batch_rename_dialog.dart` — `ConsumerStatefulWidget`.
- **Created `test/providers_test.dart`** — 35+ tests covering `ErrorNotifier`,
  `activePanelProvider`, `showPreviewProvider`, `AuthNotifier`, `PanelNotifier`
  (selection, sort, tabs, independence between panels), `TransferNotifier`, `SearchNotifier`.
  Uses `ProviderContainer` with overrides — no Flutter widget tree needed.
- **Fixed `AppState` compile errors**: added missing `_secureStorage` field and
  `_transferQueue` field, added `secureStorage` to constructor.
- **Old `AppState` kept** for backward compatibility (non-migrated test file);
  will be deleted once all tests are ported.

## 2026-05-29 — Phase 1: Foundation Hardening (PLAN.md)

### 1.5 Centralized Formatters
- **Created `lib/utils/formatters.dart`**: `formatBytes`, `formatDate`, `formatDateFull`,
  `formatDuration`, `formatSpeed` — all with test-friendly `now` parameter.
- **Consolidated 5 duplicate `_formatBytes`** from `app_state.dart`, `file_list_view.dart`,
  `operations_panel.dart` (x2), `operation_progress.dart`.
- **Consolidated `formatDate`, `formatDateFull`** from `file_list_view.dart`.
- **Added TB support** and negative-input guards.
- **Tests**: `test/formatters_test.dart` — 19 tests covering all functions, edge cases.

### 1.1 Secure Credential Storage
- **Added `flutter_secure_storage: ^9.2.4`** to pubspec.yaml.
- **Created `lib/services/secure_storage_service.dart`**:
  - `SecureStorage` abstract interface with `readMap`/`writeMap` convenience methods.
  - `PlatformSecureStorage` — production impl using flutter_secure_storage
    (Keychain, Keystore, libsecret, DPAPI per platform).
  - `InMemorySecureStorage` — test double.
  - `CredentialMigration.migrateIfNeeded()` — one-shot migration from plaintext
    SharedPreferences to SecureStorage, idempotent.
- **Updated all 3 config services** to accept `SecureStorage` parameter:
  - `filen_config_service.dart`, `sftp_config_service.dart`, `webdav_config_service.dart`
  - Credential ops use SecureStorage; batch state / preferences stay in SharedPreferences.
- **Updated `main.dart`**: creates `PlatformSecureStorage`, runs migration, threads it through.
- **Updated `app_state.dart`**: holds `_secureStorage`, passes it in `switchProvider`.
- **Updated adapter fallbacks**: `sftp_client_adapter.dart`, `webdav_client_adapter.dart`.
- **Updated all 8 test files** to pass `secureStorage: InMemorySecureStorage()`.
- **Tests**: `test/secure_storage_test.dart` — 13 tests covering CRUD, readMap, migration,
  idempotency, edge cases.

### 1.4 Structured Logging Service
- **Created `lib/services/log_service.dart`**:
  - `Log` class — named logger with trace/debug/info/warn/error methods.
  - `LogConfig` — global min-level, ring buffer (configurable size), `export()` for bug reports.
  - `LogEntry` — structured entry with timestamp, level, logger, message, data, error, stack.
- **Tests**: `test/log_service_test.dart` — 14 tests covering all levels, filtering, buffer
  eviction, export.

### 1.3 File Browser Screen Decomposition
- **Split `file_browser_screen.dart`** (1,331 → 459 lines):
  - `screens/keyboard_shortcuts.dart` (112 lines) — `handleKeyEvent()` function.
  - `screens/screen_dialogs.dart` (478 lines) — all dialog functions as top-level.
  - `screens/about_dialog.dart` (158 lines) — `AboutAppDialog` widget.
- **Removed dead code**: `_buildFAB` (commented out), `_showUserMenu` (unused).
- **Split `file_context_menu.dart`** (662 → 523 lines):
  - `widgets/search_dialogs.dart` (159 lines) — search/find dialogs extracted.

## 2026-05-29 — Phase 2: Performance & Streaming (PLAN.md)

### 2.1 Streaming Interface
- **Added capability flags** to `CloudStorageClient`:
  `supportsStreaming`, `supportsMultipart`, `supportsVersioning`, `supportsSharing`,
  `supportsSearch`, `supportsThumbnails`, `supportsTrash`.
- **Added `uploadStream` method** — `Stream<List<int>>` upload with default buffer fallback.
- **Added `downloadStream` method** — yields `List<int>` chunks with default single-chunk fallback.
- **SFTP adapter**: overrides `supportsStreaming => true`, implements true streaming upload
  (32KB chunks via SFTP write) and download (32KB reads yielded as stream).
- **Tests**: `test/cloud_storage_streaming_test.dart` — 3 tests for default streaming behaviour
  and capability flags using MockCloudClient.

### 2.2 Transfer Queue
- **Created `lib/services/transfer_queue.dart`**:
  - `TransferQueue` — manages concurrent transfers with configurable `maxConcurrent` (default 3).
  - `TransferTask` — wraps an `OperationProgress` + execute closure.
  - Exponential backoff retry for transient errors (timeout, connection, 429, 503).
  - Non-transient errors (permission denied, not found) fail immediately.
  - `cancelAll()`, `clearCompleted()`, priority scheduling.
  - Extends `ChangeNotifier` for UI integration.
- **Tests**: `test/transfer_queue_test.dart` — 6 tests covering concurrency limits,
  cancellation, retry, non-retry, and cleanup.

### 2.4 Virtual Scrolling
- **`ListView.builder` already in use** (was correct from prior work).
- **Added `itemExtent: 64`** to `FileListView` for consistent height + skip off-screen layout.
  This gives O(1) scroll-to-index and smooth scrolling with 10K+ items.

### 2.2b TransferQueue wired into AppState
- **Replaced inline sequential upload/download loops** in `AppState` with `TransferQueue`.
- Each file in a batch becomes a `TransferTask` — queue manages concurrency (3 parallel),
  retry with exponential backoff, and cancellation.
- `_runUploadInBackground` / `_runDownloadInBackground` removed (~250 lines deleted).
- New `_ensureAuthenticated()` helper replaces duplicated credential-loading blocks.
- New `_finalizeBatchOperation()` handles completion/failure status of batch operations.
- `TransferTask.onDone` callback added — queue no longer auto-calls `operation.complete()`.
- Pause/Resume/Cancel buttons were already wired in `OperationsPanel` (confirmed working).

## 2026-05-29 — Phase 3: Provider Ecosystem (PLAN.md)

### 3.1 S3-Compatible Storage Provider
- **Created `lib/services/s3_client_adapter.dart`** (715 lines):
  - Full `CloudStorageClient` implementation for AWS S3 and all S3-compatible services
    (MinIO, Backblaze B2, Wasabi, DigitalOcean Spaces, Cloudflare R2).
  - Pure Dart AWS Signature V4 signing using `package:crypto` — no AWS SDK needed.
  - Auto-detects virtual-hosted-style (`bucket.s3.amazonaws.com`) vs path-style
    (`endpoint/bucket`) based on endpoint URL.
  - Login identity parsing: `accessKey@endpoint/bucket?region=us-east-1`.
  - XML response parsing for `ListObjectsV2` via RegExp (no XML library needed).
  - Supports pagination (`ContinuationToken`), `movePath` via COPY+DELETE,
    folder creation via empty object with trailing `/`.
  - Capability flags: `supportsMultipart`, `supportsStreaming`.
  - `restoreCredentials()` for auto-login on app restart.
- **Created `lib/services/s3_config_service.dart`** (37 lines):
  Credential CRUD via `SecureStorage`, same pattern as other config services.
- **Added `CloudProvider.s3`** to enum and factory in `cloud_storage_interface.dart`.
- **Updated `app_state.dart`**: S3 cases in `switchProvider`, `_attemptAutoLogin`, `login`,
  `logout`, `_ensureAuthenticated`, config path extraction.
- **Updated `main.dart`**: S3 cases in `_getDefaultProvider` and `_createConfigService`.
- **Updated `connection_dialog.dart`**: S3 form fields (Endpoint, Region, Bucket,
  Access Key, Secret Key), login format assembly.
- **Updated `secure_storage_service.dart`**: `s3_credentials` added to migration list.
- **Tests**: `test/s3_adapter_test.dart` (375 lines) — capability flags, login parsing,
  SigV4 signing, XML parsing, credential lifecycle, error handling.
- **Tests**: `test/s3_config_service_test.dart` (105 lines) — CRUD with InMemorySecureStorage.

## 2026-05-29 — Phase 5: UI/UX Improvements (PLAN.md)

### 5.7 Status Bar
- **Created `lib/widgets/status_bar.dart`**: bottom bar showing connection status,
  provider name, item count, selection count + size, active transfer progress,
  active panel indicator.
- Wired into `file_browser_screen.dart` below OperationsPanel.

### 5.1 File Preview Pane
- **Created `lib/widgets/preview_pane.dart`** (280 lines):
  - Toggleable via eye icon in app bar or Space key.
  - Image preview: inline viewer with `InteractiveViewer` (zoom/pan), up to 20MB.
  - Text/code preview: monospace read-only viewer for 40+ file extensions, up to 5MB.
  - Metadata view: file icon, type badge, size, modified date, path, UUID.
  - Shows for single-selected file in active panel.
  - Remote files fetched via `downloadFileBytes`; local via file path.
- **Added `_showPreview` toggle** to `AppState` with `togglePreview()`.
- **Added Space key** shortcut to toggle preview.
- **Preview pane** appears as 280px right sidebar in two-panel layout.
- Updated keyboard shortcuts help dialog.

### 5.5 Breadcrumb Path Bar + Selection Bar
- Already existed in `file_toolbar.dart` (FileBreadcrumbs + FileSelectionBar).
  Verified: clickable path segments, home button, sandbox warning, item count,
  size display, action buttons. No work needed.

## 2026-05-29 — Phase 5+6 continued: Quick Wins Batch

### 5.5 Editable Address Bar + Go-to-Path
- **Editable address bar** in `file_panel.dart`: click edit icon next to breadcrumbs to type
  a path directly. Submit with Enter, cancel with X button.
- **Go-to-path dialog** (Ctrl+G): `showGoToDialog()` in `screen_dialogs.dart`.
  Pre-filled with current path, navigates on submit.
- **Command palette** updated with "Go to Path" action.

### 6.3 Folder Size + Checksum
- **Folder size calculation**: "Calculate Size" in context menu for local folders.
  Shows dialog with progress, recursive size with `formatBytes`.
- **Checksum service**: `lib/services/checksum_service.dart` with `md5Hash`, `sha256Hash`,
  `md5File`, `sha256File`.
- **Checksum dialog**: "Checksum" in context menu for local files. Shows MD5 + SHA-256
  with copy buttons.
- **Tests**: `test/checksum_service_test.dart`.

## 2026-05-29 — Phase 5 continued: Tabs + Command Palette

### 5.2 Tabbed Interface
- **Created `lib/models/panel_tab.dart`**: `PanelTab` model with id, path, label (auto-derived
  from path), selection, pin state.
- **Created `lib/widgets/panel_tab_bar.dart`**: tab bar widget with close, pin, context menu
  (close others, duplicate), new-tab button. Auto-hides when only 1 tab.
- **Added tab management to `AppState`**: `_localTabs`/`_remoteTabs`, `addTab()`, `closeTab()`,
  `selectTab()`, `toggleTabPin()`, `_syncTabPath()` on navigation.
- **Keyboard shortcuts**: Ctrl+T (new tab), Ctrl+W (close tab).
- **Tab bar integrated** into `FilePanel` above the toolbar.
- **Tests**: `test/panel_tab_test.dart` — 8 tests (label derivation, Windows paths, pin, copy).

### 6.2 Command Palette
- **Created `lib/widgets/command_palette.dart`** (220 lines):
  - Ctrl+Shift+P to open (like VS Code).
  - Lists all available actions with icons and keyboard shortcuts.
  - Type-to-filter, arrow keys to navigate, Enter to execute.
  - Context-aware: only shows upload when local files selected, etc.
  - Actions: navigation, selection, tabs, transfers, preview, sorting, connection.
- **Keyboard shortcut**: Ctrl+Shift+P wired into `keyboard_shortcuts.dart`.

### 6.3b Archive Support
- **Added `archive: ^3.6.1`** to pubspec.yaml.
- **Created `lib/services/archive_service.dart`**: `extractZip()`, `extractZipBytes()`,
  `createZip()`, `createZipFromDirectory()`, `isArchive()`.
- **Context menu integration**: "Extract Here" for .zip files, "Create Zip" for selected files.
  Local panel only, not available on Web.

### 7.1b Encryption wired into UI
- **Connection dialog**: encryption toggle checkbox + passphrase field.
- **AppState**: `enableEncryption()` wraps current client with `EncryptedStorageWrapper`,
  `disableEncryption()` unwraps, `isEncryptionEnabled` getter.
- **Status bar**: shows encryption status via provider name "(Encrypted)" suffix.

## 2026-05-29 — Phase 5 continued: Theming + Batch Rename

### 5.4 Theme System
- **Created `lib/services/theme_service.dart`**: `ThemeService` ChangeNotifier with:
  - 6 built-in themes: System, Light, Dark, OLED Black, Nord, Dracula
  - Custom accent color picker (11 preset colors + default)
  - Persistence via SharedPreferences
  - Reactive — `MaterialApp` rebuilds on theme change
- **Created `lib/widgets/theme_picker.dart`**: dialog with theme swatches + accent color dots.
- **Updated `main.dart`**: `MultiProvider` with `ThemeService`, reactive `MaterialApp`.
- **Added palette icon** to app bar for theme selection.
- **Tests**: `test/theme_service_test.dart` — 8 tests covering mode switching, accent colors,
  ThemeData generation, OLED black scaffold color.

### 6.3 Batch Rename
- **Created `lib/widgets/batch_rename_dialog.dart`** (260 lines):
  - 4 rename modes: Find/Replace (text or regex), Numbering, Prefix/Suffix, Extension change.
  - Live preview showing original → renamed for all files.
  - Segmented button mode selector, regex toggle.
  - Executes renames sequentially via `appState.renameFile`.
- **Added to context menu**: "Batch Rename (N)" appears when multiple files are selected.
- **Tests**: `test/batch_rename_test.dart` — 14 tests covering all 4 modes: text replace,
  regex with capture groups, sequential numbering, prefix/suffix, extension change.

## 2026-05-29 — Phase 7: Security & Privacy (PLAN.md)

### 7.1 Client-Side Encryption Layer
- **Created `lib/services/encryption_service.dart`**: stateless encryption utility:
  - `deriveKey()` — PBKDF2 with HMAC-SHA256, 100K iterations, 256-bit output
  - `encrypt()` / `decrypt()` — AES-256-GCM (nonce + ciphertext + tag)
  - `encryptFilename()` / `decryptFilename()` — base64url-safe
  - `generateSalt()` (16 bytes), `generateNonce()` (12 bytes)
  - Uses `package:pointycastle` (already in pubspec)
- **Created `lib/services/encrypted_storage_wrapper.dart`**: wraps any `CloudStorageClient`:
  - Transparently encrypts before upload, decrypts after download
  - Optional filename encryption (`encryptFilenames: true`)
  - Forces `supportsSharing`, `supportsSearch`, `supportsThumbnails` to false
  - Streams buffer to memory first (GCM needs full plaintext)
  - Provider name shows "(Encrypted)" suffix
  - No existing files modified — opt-in wrapper
- **Tests**: `test/encryption_service_test.dart` — 13 tests (round-trip, wrong key, 1MB data,
  empty data, determinism, filename safety).
- **Tests**: `test/encrypted_storage_wrapper_test.dart` — 15 tests (capability flags, upload
  encryption verification, download decryption, round-trip, stream methods, pass-through).

## 2026-05-29 — Phase 3 continued: FTP/FTPS Provider

### 3.2 FTP/FTPS Provider
- **Created `lib/services/ftp_client_adapter.dart`**: Full `CloudStorageClient` implementation
  using `ftpconnect` package. Supports FTP and FTPS (TLS toggle), login format `user@host:port`,
  stateful connection with `_ensureConnection()`, temp file approach for upload/download.
  Web platform guard (FTP cannot work in browsers). `supportsTrash => false`.
- **Created `lib/services/ftp_config_service.dart`**: Credential CRUD via `SecureStorage`.
- **Added `ftpconnect: ^2.0.5`** to pubspec.yaml.
- **Added `CloudProvider.ftp`** to enum and factory.
- **Updated all integration points**: `app_state.dart`, `main.dart`, `connection_dialog.dart`,
  `secure_storage_service.dart`.
- **Tests**: `test/ftp_adapter_test.dart`, `test/ftp_config_service_test.dart`.

## 2026-05-29 — Full Audit & Hardening

### Critical Security Fixes
- **SFTP default port was Telnet (23)**: `sftp_client_adapter.dart:24` had
  `_port = 23` instead of `22`. Fixed to `22`.
- **WebSocket defaulted to ws:// (unencrypted)**: `sftp_client_adapter.dart:73`
  used `ws://` for SFTP proxy connections. Fixed to `wss://`.
- **TFA bypass placeholder**: `filen_client_adapter.dart:41` fell back to
  `"XXXXXX"` when no 2FA code provided, which Filen treats as "skip 2FA".
  Changed to empty string.
- **Credentials logged to console**: `filen_config_service.dart:43` printed
  the user's email after saving credentials. Removed.
- **Dead placeholder file**: `internxt_client_placeholder.dart` threw
  `UnsupportedError` for all operations. Deleted since published
  `internxt_client` package is used.

### Architecture Cleanup
- **Circular import fixed**: `app_state.dart` imported
  `file_browser_screen.dart` just for the `PanelSide` enum. Extracted enum
  to `lib/models/panel_side.dart`. Three files updated.
- **Dead code removed**: 15-line commented-out permission dialog block
  in `file_browser_screen.dart:47-58`.
- **Empty catch blocks**: 9 instances across `app_state.dart`,
  `webdav_filesystem.dart`, `local_file_service.dart` where exceptions were
  silently swallowed. All now log via `debugPrint` with context.

### Input Validation
- **SFTP port validation**: Connection dialog now validates port is 1-65535.
- **WebDAV URL validation**: Connection dialog now requires `http://` or
  `https://` prefix and valid URI structure.

### Filen Library Migration
- **Embedded copy removed**: 4,497-line `lib/services/filen.dart` replaced
  with `filen_dart` git dependency (same pattern as `internxt_client`).
- **Adapter updated**: `filen_client_adapter.dart` and
  `webdav_filesystem.dart` now import `package:filen_dart/filen_client.dart`.

### Testing
- Added 8 test files:
  - `config_services_test.dart` — all 3 config services
  - `cloud_storage_interface_test.dart` — factory and enum
  - `operation_progress_test.dart` — progress tracking model
  - `file_item_test.dart` — file model equality and formatting
  - `filen_live_test.dart` — Filen E2E (gated by env vars)
  - `sftp_live_test.dart` — SFTP E2E (gated by env vars)
  - `webdav_live_test.dart` — WebDAV E2E (gated by env vars)
- Updated CI to run all unit tests (was only running 2 specific files).

### Linting
- Enabled `avoid_print`, `prefer_final_locals`, `prefer_const_constructors`,
  `avoid_empty_else`, `avoid_relative_lib_imports`, and other rules
  in `analysis_options.yaml`.

## Pre-audit state

### Known issues that existed before the audit
- **243 print() statements**: Used throughout for debug output instead of
  proper logging framework. `avoid_print` lint rule was disabled.
- **SharedPreferences for credentials**: All providers store passwords in
  plaintext in SharedPreferences. No encryption layer.
- **No secure storage**: Missing `flutter_secure_storage` or platform-specific
  keychain integration.
- **Race conditions in AppState**: Concurrent `refreshPanel`,
  `switchProvider`, and `_attemptAutoLogin` calls are not serialized.
- **file_panel.dart is 1,711 lines**: Monolithic widget handling UI, business
  logic, context menus, and drag-drop. Should be split.
- **File sorting not implemented**: TODO at `file_panel.dart:764`.
- **Cancel/pause buttons not in UI**: `OperationProgress` model supports
  cancel/pause but `operations_panel.dart` doesn't expose the controls.
