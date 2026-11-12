# Rust Filen/Internxt engines (experimental)

CrispCloud can run Filen and Internxt through the vendored Rust clients
(`crisp-filen`, `crisp-internxt`, pinned from CrispSorter `45c748d4`, see
[UPSTREAM-CLOUD.md](../packages/crisp_storage/native/UPSTREAM-CLOUD.md))
instead of the Dart clients. Dart remains the default; both engines stay
supported. Design rules: [STORAGE_ENGINE_ARCHITECTURE.md](STORAGE_ENGINE_ARCHITECTURE.md).

## Choosing an engine

| Where | How |
| --- | --- |
| GUI, per connection | Connection dialog → Filen/Internxt → **Storage engine**: Dart (default), Rust (experimental), Auto. Saved with the connection profile as the non-secret `engine` field. |
| Build default | `--dart-define=CRISP_FILEN_BACKEND=dart|rust|auto`, `--dart-define=CRISP_INTERNXT_BACKEND=dart|rust|auto` (unknown values fail fast). |
| Native library | `--dart-define=CRISP_CLOUD_LIBRARY=/abs/path` or the `CRISP_CLOUD_LIBRARY` environment variable; otherwise a library bundled next to the app (macOS `Contents/Frameworks/libcrisp_cloud_bridge.dylib`, Linux `<exe>/lib/`, Windows next to the exe). |

Selection happens before any credential leaves the adapter:

* **Dart** never loads Rust.
* **Rust** is strict: a missing/incompatible native library is reported as
  "The Rust storage engine is not available in this build" — no fallback.
* **Auto** uses Rust when the library loads and Dart otherwise. Sign-in,
  2FA, network, crypto and transfer failures never switch engines, and a
  started mutation is never replayed through the other engine.

A successful Rust sign-in stores `{email, engine: "rust", rustSession}` in the
provider's existing secure credential entry. `rustSession` is a versioned
envelope (`format: crisp-cloud-rust-session`, `version: 1`, `provider`,
`account`, opaque provider session). Restoring such credentials requires the
Rust engine; legacy Dart credentials keep restoring through Dart. Dart and Rust
sessions are not converted into each other: switching engines means signing in
again. Internxt token renewals bump a session revision; the adapter persists
the renewed envelope after the operation.

## What the Rust engine implements

Login (incl. 2FA code; the Rust engine reports `TwoFactorRequired` from
sign-in, which opens the 2FA field), restore/export of the versioned session,
list (cached or fresh), stat/resolve, recursive mkdir, rename, move into a
folder, trash, upload from a local file and download to a local file with
coalesced progress (100 ms polling) and cooperative cancellation. Uploads from
memory/streams and stream/byte downloads are spooled through a private temp
file, so memory stays bounded; downloads are published through the app's
existing staging/atomic-replace path. Search/find stay Dart-only and are
refused explicitly in Rust mode. Errors are normalized codes
(`AuthFailed`, `NotFound`, `RateLimited`, `Integrity`, …) without paths,
e-mail addresses or raw gateway text.

Blocking `reqwest` clients run on dedicated, named worker threads (max 32
concurrent; excess calls fail fast with retryable `Busy`), never on the Flutter
UI thread or inside a Tokio task. Internxt renews an expired token once
(single-flight) and replays only single-request operations that the gateway
rejected; uploads/downloads report a retryable `SessionExpired` instead.

## Build and test

```sh
cd packages/crisp_storage
dart run bin/build_cloud.dart            # prints CRISP_CLOUD_LIBRARY=...
cargo test --manifest-path rust_cloud/Cargo.toml --locked
CRISP_CLOUD_LIBRARY=... dart test test/rust_cloud_native_test.dart test/cloud_engine_test.dart
python3 tool/check_rust_licenses.py --bridge cloud
# macOS app with both Rust engines embedded (developer path):
tool/bundle_rust_engines_macos.sh build/macos/Build/Products/Release/CrispCloud.app
```

Regenerate the bridge with flutter_rust_bridge_codegen 2.11.1:

```sh
flutter_rust_bridge_codegen generate --rust-root rust_cloud --rust-input crate::api \
  --dart-output lib/src/rust_cloud --dart-root . --no-deps-check \
  --no-auto-upgrade-dependency --type-64bit-int --no-dart-fix \
  --dart-entrypoint-class-name CloudRustLib
```

Live tests are opt-in and use a uniquely named scratch folder that they trash
afterwards. They read `CRISP_LIVE_FILEN_EMAIL/_PASSWORD` and
`CRISP_LIVE_INTERNXT_EMAIL/_PASSWORD` (use a dedicated test account):

```sh
cargo test --manifest-path packages/crisp_storage/rust_cloud/Cargo.toml --test live -- --nocapture
CRISP_CLOUD_LIBRARY=... flutter test test/rust_cloud_live_test.dart   # Dart + Rust engines
```

## Not yet qualified

Bundling in release/store builds (macOS signing/notarization, iOS
XCFramework, Android ABIs), browser support (unavailable by design),
resumable transfers across restarts, Internxt search in Rust mode, and the
measured performance comparison required before any default change.
