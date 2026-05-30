# History

Audit trail of bugs found, issues discovered, and fixes applied.

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
