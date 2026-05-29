# History

Audit trail of bugs found, issues discovered, and fixes applied.

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
