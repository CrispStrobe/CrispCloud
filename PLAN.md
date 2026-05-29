# CrispCloud Hardening Plan

Full audit completed 2026-05-29. This plan addresses every issue found,
ordered by severity. Each item has a checkbox for tracking.

---

## Phase 1: Critical Security Fixes

- [x] **1.1 Fix SFTP default port**: `sftp_client_adapter.dart:24` — changed `_port = 23` to `_port = 22`
- [x] **1.2 Fix WebSocket default scheme**: `sftp_client_adapter.dart:73` — changed `ws://` to `wss://`
- [x] **1.3 Remove TFA bypass placeholder**: `filen_client_adapter.dart:41` — changed `?? "XXXXXX"` to `?? ""`
- [x] **1.4 Stop logging credentials**: `filen_config_service.dart:43` — removed credential logging
- [x] **1.5 Delete placeholder files**: Removed `internxt_client_placeholder.dart`
- [x] **1.6 Input validation in connection dialog**: Added port validation (1-65535), WebDAV URL validation (http/https + valid URI)

## Phase 2: Architecture Cleanup

- [x] **2.1 Fix circular import**: Moved `PanelSide` enum to `lib/models/panel_side.dart`; updated 3 files
- [x] **2.2 Remove dead code**: Deleted commented-out permission dialog block in `file_browser_screen.dart`
- [x] **2.3 Fix empty catch blocks**: Added `debugPrint` logging to all 9 empty catch blocks
- [ ] **2.4 Replace print() with debugPrint**: 243 instances across codebase (enabled `avoid_print` lint rule — will surface them as warnings)

## Phase 3: Error Handling Hardening

- [ ] **3.1 Fix filen_client_adapter error swallowing**: `resolvePath` and `listPath` should propagate errors, not return null/empty
- [ ] **3.2 Fix AppState race conditions**: Add mutex/lock for `switchProvider`, `refreshPanel`, `_attemptAutoLogin`
- [ ] **3.3 Add error queue**: Replace single `_lastError` with a list
- [ ] **3.4 Add retry logic**: Wrap remote operations with exponential backoff

## Phase 4: Unit Tests

- [x] **4.1 `test/config_services_test.dart`**: Tests all 3 config services
- [x] **4.2 `test/cloud_storage_interface_test.dart`**: Tests factory and enum
- [x] **4.3 `test/operation_progress_test.dart`**: Tests progress tracking model
- [x] **4.4 `test/file_item_test.dart`**: Tests file model equality and formatting
- [ ] **4.5 `test/filen_adapter_test.dart`**: Mock-based adapter tests
- [ ] **4.6 `test/app_state_test.dart`**: State transition tests
- [ ] **4.7 `test/local_file_service_test.dart`**: File listing and sorting tests

## Phase 5: Live Integration Tests

- [x] **5.1 `test/filen_live_test.dart`**: Login → list → upload → download → resolve (gated by FILEN_EMAIL/PASSWORD)
- [x] **5.2 `test/sftp_live_test.dart`**: Connect → list → upload → download → rename → delete (gated by SFTP env vars)
- [x] **5.3 `test/webdav_live_test.dart`**: Connect → list → upload → download → delete (gated by WEBDAV env vars)

## Phase 6: CI Pipeline

- [x] **6.1 Updated `.github/workflows/ci.yml`**: Now runs all tests (was only running 2 specific files)
- [x] **6.2 Enable strict analysis**: Updated `analysis_options.yaml` with `avoid_print` and 10+ lint rules

## Phase 7: UI Improvements (Future)

- [ ] **7.1 Implement file sorting** (`file_panel.dart:764` TODO)
- [ ] **7.2 Expose cancel/pause in operations panel**
- [ ] **7.3 Split file_panel.dart** (1,711 lines → multiple <600-line components)

---

## Issue Counts by Severity

| Severity | Total | Fixed | Remaining |
|----------|-------|-------|-----------|
| CRITICAL | 4 | 4 | 0 |
| HIGH | 12 | 9 | 3 |
| MEDIUM | 8 | 6 | 2 |
| LOW | 3 | 1 | 2 |
