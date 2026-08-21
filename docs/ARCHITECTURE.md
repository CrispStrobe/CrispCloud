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
