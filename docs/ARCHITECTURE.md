# Application architecture

## Direction

Riverpod is the canonical state-management boundary. New UI reads state through
providers and delegates work to focused notifiers/services. `AppState` and the
legacy `provider` package remain compatibility surfaces while features are
migrated; new behavior must not be added to them when an equivalent Riverpod
notifier exists.

## Main boundaries

- `CloudStorageClient` is the provider-neutral storage API.
- `CloudCapabilities` is the provider feature contract. UI and orchestration
  code should use it instead of checking concrete adapter types.
- `AuthNotifier`, `PanelNotifier`, and `TransferNotifier` own authentication,
  browsing, and transfers respectively.
- `TransferQueue` owns concurrency, retry, provider limits, and cancellation;
  it does not own UI state.
- Platform integrations live behind services and must have headless tests or a
  release smoke check.
- Crash diagnostics are injected through Riverpod so the same initialized,
  opt-in service is used by the bootstrap code and settings UI.

## Migration rules

1. Move one responsibility at a time out of `AppState` with characterization
   tests first.
2. Keep provider-specific behavior in adapters and describe differences through
   capabilities.
3. Do not create private `ProviderContainer` instances inside application
   providers; dependencies must be injected by Riverpod.
4. Keep live-provider, benchmark, deployment, and golden tests tagged so the
   deterministic suite never depends on credentials, network, timing, or a GUI.
5. Treat analyzer warnings as tracked debt; new and changed files should be
   warning-free.

## Terminal

The terminal backend is platform- and distribution-aware: a real PTY-backed
shell on desktop, a sandboxed shell with security-scoped folder grants on the
macOS App Store build, an unsandboxed shell for Developer ID builds, and a
built-in command layer on iOS. See [terminal.md](terminal.md).

## Storage engines across apps

Flutter/Dart owns application state, account settings, queues and UI. SMB uses
`packages/crisp_storage`: the default Dart wrapper calls C libsmb2, while the
optional Rust path uses the shared `crisp_smb` core through FFI. Filen/Internxt
currently use Dart clients in the GUI and have no standalone CLI adapters.

The next design reuses Sorter's existing Rust Filen/Internxt clients through a
common contract and bridge, retaining Dart during qualification. Source reuse,
credential ownership, worker/stream boundaries, fallback rules, browser limits,
MPL/LGPL evidence and the test/rollout sequence are recorded in
[STORAGE_ENGINE_ARCHITECTURE.md](STORAGE_ENGINE_ARCHITECTURE.md). Its proposed
provider settings must not be presented as already implemented.
