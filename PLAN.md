# CrispCloud Hardening Plan

Full audit completed 2026-05-29. All items resolved.

---

## Phase 1: Critical Security Fixes

- [x] **1.1 Fix SFTP default port**: Changed `_port = 23` to `_port = 22`
- [x] **1.2 Fix WebSocket default scheme**: Changed `ws://` to `wss://`
- [x] **1.3 Remove TFA bypass placeholder**: Changed `?? "XXXXXX"` to `?? ""`
- [x] **1.4 Stop logging credentials**: Removed credential logging
- [x] **1.5 Delete placeholder files**: Removed `internxt_client_placeholder.dart`
- [x] **1.6 Input validation in connection dialog**: Port validation (1-65535), WebDAV URL validation

## Phase 2: Architecture Cleanup

- [x] **2.1 Fix circular import**: Extracted `PanelSide` enum to `lib/models/panel_side.dart`
- [x] **2.2 Remove dead code**: Deleted commented-out permission dialog block
- [x] **2.3 Fix empty catch blocks**: Added `debugPrint` logging to all 9 instances
- [x] **2.4 Replace print() with debugPrint**: Migrated all 243 instances across 16 files

## Phase 3: Error Handling Hardening

- [x] **3.1 Fix AppState race conditions**: `_AsyncLock` mutex with 3 independent locks
- [x] **3.2 Add error queue**: Replaced `_lastError` string with `AppError` list (message + timestamp + context)
- [x] **3.3 Error queue API**: `errors`, `hasErrors`, `clearErrors()`, `clearLastError()` — backward-compatible `lastError` getter

## Phase 4: Unit Tests

- [x] **4.1 `test/config_services_test.dart`**: All 3 config services
- [x] **4.2 `test/cloud_storage_interface_test.dart`**: Factory and enum
- [x] **4.3 `test/operation_progress_test.dart`**: Progress tracking model
- [x] **4.4 `test/file_item_test.dart`**: File model equality and formatting
- [x] **4.5 `test/filen_adapter_test.dart`**: Adapter public interface (11 tests)
- [x] **4.6 `test/app_state_test.dart`**: State transitions, sorting, selection, notifications (34 tests)
- [x] **4.7 `test/local_file_service_test.dart`**: Construction, path ops, file I/O (13 tests)

## Phase 5: Live Integration Tests

- [x] **5.1 `test/filen_live_test.dart`**: Login → list → upload → download → resolve
- [x] **5.2 `test/sftp_live_test.dart`**: Connect → list → upload → download → rename → delete
- [x] **5.3 `test/webdav_live_test.dart`**: Connect → list → upload → download → delete

## Phase 6: CI Pipeline

- [x] **6.1 Updated CI**: Now runs all tests
- [x] **6.2 Strict analysis**: `avoid_print` + 10 lint rules enabled

## Phase 7: UI / Features

- [x] **7.1 Implement file sorting**: Connected sort menu to `AppState.setSortBy()`
- [x] **7.2 Cancel/pause UI**: Already existed (confirmed during audit)
- [x] **7.3 Split file_panel.dart**: 1,711 → 211 lines (orchestrator) + 3 components (260 + 660 + 580)

---

## Final Summary

| Severity | Total | Fixed |
|----------|-------|-------|
| CRITICAL | 4 | 4 |
| HIGH | 12 | 12 |
| MEDIUM | 8 | 8 |
| LOW | 3 | 3 |

**All items resolved.** 14 test files, ~58 unit tests + 3 live E2E test suites.
