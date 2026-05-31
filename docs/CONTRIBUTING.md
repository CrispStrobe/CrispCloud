# Contributing to CrispCloud

CrispCloud is open-source (AGPL-3.0). Contributions are welcome — bug fixes, new providers, UI improvements, and test coverage are all valuable.

---

## Table of Contents

1. [Development Setup](#development-setup)
2. [Project Structure](#project-structure)
3. [How to Add a New Provider](#how-to-add-a-new-provider)
4. [Code Style](#code-style)
5. [Testing Conventions](#testing-conventions)
6. [Pull Request Process](#pull-request-process)

---

## Development Setup

### Prerequisites

- **Flutter SDK** 3.22 or later (`flutter --version`)
- **Dart SDK** 3.4 or later (bundled with Flutter)
- macOS, Windows, or Linux host for desktop development

### Clone and Run

```bash
git clone https://github.com/your-org/CrispCloud.git
cd CrispCloud
flutter pub get
flutter run
```

To run on a specific platform:

```bash
flutter run -d macos
flutter run -d windows
flutter run -d linux
flutter run -d chrome          # Web (PWA)
flutter run -d <device-id>     # Android / iOS
```

List available devices with `flutter devices`.

### Running Tests

```bash
flutter test                   # all unit tests
flutter test test/sftp_adapter_test.dart  # single file
flutter test --coverage        # generate lcov coverage
```

Integration (E2E) tests require real credentials and are gated behind environment variables. See `dart_test.yaml` for the `@Tags(['live'])` configuration.

### CLI Companion

```bash
cd cli
dart pub get
dart run bin/crisp.dart --help
dart test
```

---

## Project Structure

```
lib/
  main.dart                  # App entry point, ProviderScope setup
  services/                  # Business logic and provider adapters
    cloud_storage_interface.dart   # CloudStorageClient abstract class + factory
    *_client_adapter.dart          # One file per provider
    *_config_service.dart          # Credential load/save per provider
    encryption_service.dart        # AES-256-GCM + PBKDF2
    encrypted_storage_wrapper.dart # Transparent encryption adapter
    sync_engine.dart               # Two-way sync logic
    transfer_queue.dart            # Concurrent transfer queue
    log_service.dart               # Structured logging
    ...
  providers/                 # Riverpod state providers
    auth_provider.dart        # Login state, provider switching
    panel_provider.dart       # File listing, tabs, selection (family)
    transfer_provider.dart    # Transfer queue state
    search_provider.dart      # Search query and results
    sync_provider.dart        # Sync engine state
    ...
  screens/                   # Full-screen views
    file_browser_screen.dart  # Main two-panel screen
    keyboard_shortcuts.dart   # Global shortcut handler
    screen_dialogs.dart       # Connection, settings dialogs
  widgets/                   # Reusable UI components
    file_list_view.dart
    file_grid_view.dart
    file_panel.dart
    file_toolbar.dart
    command_palette.dart
    preview_pane.dart
    ...
  models/                    # Data classes (FileItem, SyncPair, etc.)
  utils/                     # Shared utilities (formatters, etc.)

test/                        # Unit tests (mirrors lib/ structure)
cli/                         # Standalone Dart CLI (crisp command)
  bin/crisp.dart
  lib/
    cli_app.dart
    commands/                # One file per CLI command
    adapters/                # Shared S3/SFTP/WebDAV adapters for CLI
```

---

## How to Add a New Provider

Adding a provider requires six steps. Use an existing adapter as reference — `lib/services/s3_client_adapter.dart` (complex, with SigV4 signing) or `lib/services/ftp_client_adapter.dart` (simple, third-party package) are good starting points.

### Step 1: Implement `CloudStorageClient`

Create `lib/services/yourprovider_client_adapter.dart`.

```dart
import 'dart:typed_data';
import 'cloud_storage_interface.dart';
import 'log_service.dart';
import 'yourprovider_config_service.dart';

class YourProviderClientAdapter extends CloudStorageClient {
  static final _log = Log('YourProviderAdapter');
  final YourProviderConfig config;

  YourProviderClientAdapter({required this.config});

  // --- Required overrides ---

  @override
  Future<void> login(String email, String password, {String? twoFactorCode}) async {
    // Authenticate and store tokens in [config] or instance fields
  }

  @override
  Future<bool> is2faNeeded(String email) async => false;

  @override
  Future<void> logout() async { /* clear tokens */ }

  @override
  bool get isAuthenticated => /* check token */ false;

  @override
  String? get userId => config.userId;

  @override
  String? get bucketId => null; // only relevant for Filen

  @override
  String get providerName => 'YourProvider';

  @override
  String get rootPath => '/';

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    // Return null if path doesn't exist, or a map with 'uuid'/'id' if it does
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    // Return {'files': [...], 'folders': [...]}
    // Each entry: {'name': str, 'size': int, 'lastModified': str, 'isDirectory': bool}
  }

  @override
  Future<void> uploadFile(List<int> fileData, String fileName, String targetPath,
      {Function(int, int)? onProgress}) async { ... }

  @override
  Future<void> downloadFileByPath(String remotePath, String localPath,
      {Function(int, int)? onProgress}) async { ... }

  @override
  Future<Uint8List> downloadFileBytes(String remotePath,
      {Function(int, int)? onProgress}) async { ... }

  @override
  Future<void> createFolderPath(String path) async { ... }

  @override
  Future<void> deletePath(String path) async { ... }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async { ... }

  @override
  Future<void> renamePath(String path, String newName) async { ... }

  // --- Optional capability overrides ---

  @override
  bool get supportsStreaming => false; // set true if you implement uploadStream/downloadStream

  @override
  bool get supportsVersioning => false;

  @override
  bool get supportsSharing => false;
}
```

All `onProgress` callbacks receive `(bytesTransferred, totalBytes)`. Call them at regular intervals during transfer so the UI shows accurate progress.

### Step 2: Create a Config Service

Create `lib/services/yourprovider_config_service.dart` to load and save credentials using `SecureStorage`.

```dart
import 'secure_storage.dart';

class YourProviderConfig {
  final String serverUrl;
  final String username;
  String? accessToken; // stored after successful login

  YourProviderConfig({required this.serverUrl, required this.username});
}

class YourProviderConfigService {
  static const _keyPrefix = 'yourprovider_';

  static Future<void> saveConfig(SecureStorage storage, YourProviderConfig config) async {
    await storage.write(key: '${_keyPrefix}url', value: config.serverUrl);
    await storage.write(key: '${_keyPrefix}username', value: config.username);
  }

  static Future<YourProviderConfig?> loadConfig(SecureStorage storage) async {
    final url = await storage.read(key: '${_keyPrefix}url');
    final username = await storage.read(key: '${_keyPrefix}username');
    if (url == null || username == null) return null;
    return YourProviderConfig(serverUrl: url, username: username);
  }

  static Future<void> clearConfig(SecureStorage storage) async {
    await storage.delete(key: '${_keyPrefix}url');
    await storage.delete(key: '${_keyPrefix}username');
  }
}
```

Never use `SharedPreferences` for credentials. Always use the `SecureStorage` abstraction.

### Step 3: Add to the Provider Enum and Factory

In `lib/services/cloud_storage_interface.dart`:

1. Add a value to the `CloudProvider` enum:
   ```dart
   enum CloudProvider {
     dropbox, filen, ftp, gdrive, internxt,
     nextcloud, onedrive, pcloud, s3, sftp, webdav,
     yourprovider,  // add here
   }
   ```

2. Add a case to `CloudStorageFactory.create()`:
   ```dart
   case CloudProvider.yourprovider:
     return YourProviderClientAdapter(config: config);
   ```

3. Add the import at the top of the file:
   ```dart
   import 'yourprovider_client_adapter.dart';
   ```

### Step 4: Create the Connection Dialog Fields

In `lib/widgets/connection_dialog.dart`, add a new branch for your provider in the `_buildProviderFields()` method:

```dart
case CloudProvider.yourprovider:
  return Column(children: [
    TextFormField(
      controller: _serverUrlController,
      decoration: const InputDecoration(labelText: 'Server URL'),
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
    ),
    TextFormField(
      controller: _usernameController,
      decoration: const InputDecoration(labelText: 'Username'),
    ),
    TextFormField(
      controller: _passwordController,
      obscureText: true,
      decoration: const InputDecoration(labelText: 'Password'),
    ),
  ]);
```

Also add your provider to the dropdown list in the same dialog and handle config construction in the `_connect()` method.

### Step 5: Write Tests

Create `test/yourprovider_adapter_test.dart`. Mock the HTTP layer or use a local test server. Use `InMemorySecureStorage` for all credential operations.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:crispcloud/services/yourprovider_client_adapter.dart';
import 'package:crispcloud/services/yourprovider_config_service.dart';
import 'helpers/in_memory_secure_storage.dart';

void main() {
  late YourProviderConfig config;
  late YourProviderClientAdapter adapter;

  setUp(() {
    config = YourProviderConfig(serverUrl: 'https://test.example.com', username: 'testuser');
    adapter = YourProviderClientAdapter(config: config);
  });

  test('providerName returns correct value', () {
    expect(adapter.providerName, 'YourProvider');
  });

  test('isAuthenticated is false before login', () {
    expect(adapter.isAuthenticated, isFalse);
  });

  test('listPath returns files and folders', () async {
    // ... mock HTTP and test listing
  });

  test('config service saves and loads credentials', () async {
    final storage = InMemorySecureStorage();
    await YourProviderConfigService.saveConfig(storage, config);
    final loaded = await YourProviderConfigService.loadConfig(storage);
    expect(loaded?.serverUrl, config.serverUrl);
    expect(loaded?.username, config.username);
  });

  // Round-trip upload/download test
  test('upload and download round-trip', () async {
    // ... mock HTTP, upload bytes, download bytes, compare
  });
}
```

Aim for at minimum: auth state tests, config service save/load/clear, listing, upload round-trip, download, delete, and any capability-specific features (versioning, sharing).

### Step 6: Override Capability Flags

Review all capability flags in `CloudStorageClient` and override the ones your provider supports. Each flag affects what the UI offers for that connection:

| Flag | Effect when `true` |
|------|--------------------|
| `supportsStreaming` | Uses `uploadStream`/`downloadStream`; implement both methods |
| `supportsMultipart` | Signals that large files use chunked upload |
| `supportsVersioning` | Enables Version History dialog |
| `supportsSharing` | Enables Share Link dialog; implement `createShareLink()` |
| `supportsSearch` | Enables provider-side search; override `fullTextSearch()` |
| `supportsThumbnails` | Provider-native thumbnails; override `getThumbnail()` |
| `supportsServerSideCopy` | Override `copyPath()` to avoid download+reupload |
| `supportsNativeShare` | Provider has its own share-link API |
| `supportsFullTextSearch` | Full-text (content) search supported server-side |

---

## Code Style

### Logging

Always use `Log` instead of `debugPrint` or `print`:

```dart
static final _log = Log('MyService');

_log.info('Connected to $providerName');
_log.warn('Retrying after timeout', error);
_log.error('Upload failed', error, stackTrace);
```

Log levels: `trace`, `debug`, `info`, `warn`, `error`. The `Log` service writes to a ring buffer that can be exported by the user for support.

### Secure Storage in Tests

Never use `flutter_secure_storage` directly in tests. Use `InMemorySecureStorage`:

```dart
import '../helpers/in_memory_secure_storage.dart';

final storage = InMemorySecureStorage();
```

This avoids platform channel calls and makes tests fast and hermetic.

### Conditional Imports for Web

Services that use `dart:io` must use conditional imports to compile on the Web:

```dart
// local_file_service.dart
import 'local_file_service_native.dart'
    if (dart.library.html) 'local_file_service_web.dart';
```

The web stub must implement the same interface but throw `UnsupportedError` for operations unavailable on web, or provide a web-specific implementation.

### Provider HTTP Clients

Use `dart:io` `HttpClient` or the `http` package. Do not add heavyweight provider SDKs unless the SDK is small and well-maintained. The S3 adapter implements SigV4 signing in pure Dart as a reference for protocol-level implementation.

### Riverpod Providers

Add state for your provider in `lib/providers/auth_provider.dart` (for connection state) or a new focused provider file. Keep providers small and independently testable. Use `ref.watch` in widgets and `ref.read` in callbacks.

---

## Testing Conventions

- **Test file naming**: `test/yourprovider_adapter_test.dart` mirrors `lib/services/yourprovider_client_adapter.dart`.
- **Group related tests**: use `group('description', () { ... })`.
- **Mock HTTP**: use `mockito` or inline `HttpOverrides` for HTTP-dependent tests.
- **Live tests**: tag with `@Tags(['live'])` and gate on environment variables. Live tests are excluded from the default `flutter test` run.
- **`InMemorySecureStorage`**: always for config service tests.
- **No `debugPrint` in tests**: tests should be silent. Assert on behavior, not log output.
- **Test capability flags**: include a test that verifies each `supports*` flag your provider claims is actually implemented.

The project currently has 55+ test files and ~1,227 unit tests. New providers must include a test file before the PR will be merged.

---

## Pull Request Process

1. **Fork** the repository and create a feature branch: `git checkout -b feat/your-provider`.
2. **Implement** all six steps above for a new provider, or make your targeted change.
3. **Run tests**: `flutter test` must pass with no failures.
4. **Run analysis**: `flutter analyze` must produce no errors or warnings.
5. **Run the CLI tests** if your change touches shared services: `cd cli && dart test`.
6. **Open a PR** against the `main` branch. Fill in the PR template:
   - What does this change do?
   - What providers / services does it affect?
   - Have you added tests? What is the coverage for the new code?
   - Any known limitations?
7. **CI checks**: the pipeline runs `flutter analyze`, `flutter test`, `build-web`, and `build-macos`. All must pass.
8. **Review**: at least one maintainer review is required before merge.

### Commit Style

Use conventional commits:
- `feat: add YourProvider adapter`
- `fix: handle SFTP timeout on large uploads`
- `test: add 24 tests for s3 multipart upload`
- `refactor: extract breadcrumb widget from file_browser_screen`
- `docs: add provider setup guide for Nextcloud`

### What We Won't Merge

- Providers that use `debugPrint` instead of `Log`.
- Providers with no tests.
- Credentials stored in `SharedPreferences` instead of `SecureStorage`.
- Dependencies on large, heavyweight SDKs when a thin REST client suffices.
- Breaking changes to `CloudStorageClient` interface without updating all 11 existing adapters.
