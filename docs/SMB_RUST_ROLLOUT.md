# Rust SMB transport — default, with no LGPL fallback

Decision: reuse `smb2` 0.43.0 through an independent `crisp_smb` Rust crate and
flutter_rust_bridge 2.11.1. Do not reimplement the protocol in Dart or add Go's
runtime. CrispCloud and CrisperPlayer share one Dart facade; CrispSorter can
consume the core directly while retaining OS-mounted SMB. For the current
Dart/Rust split and proposed Filen/Internxt integration, see
[STORAGE_ENGINE_ARCHITECTURE.md](STORAGE_ENGINE_ARCHITECTURE.md).

## Backend policy

`SmbSession` preserves its API. Rust is the default and sole shipped native
transport. Existing saved `libsmb2`/`auto` selections migrate to Rust. Missing
native code fails explicitly; no alternate SMB library is bundled. Unknown
profile values are rejected. The legacy enum values remain source-compatible.

Selection happens before passing credentials or connecting. Authentication,
network, signing, encryption, protocol and transfer failures NEVER trigger
fallback. Unknown mode values are rejected. `effectiveBackend` is diagnostic
only; do not include credentials or remote paths in telemetry.

The Rust backend requires signing. Encryption remains required by default. Rust
rejects guest sessions and disables DFS and automatic mutation replay. URL
confinement is not a server-side filesystem sandbox: configure share permissions
and do not expose symlink/reparse-point ancestors outside the intended root.

## Run the native prototype

From `packages/crisp_storage`, run `dart pub get`, then
`dart run bin/build_smb.dart`. This builds the host dynamic library with Cargo.
The tool prints its absolute `CRISP_SMB_LIBRARY` path. For a desktop developer
build, pass `--dart-define=CRISP_SMB_BACKEND=rust` and
`--dart-define=CRISP_SMB_LIBRARY=/absolute/path/to/library` to Flutter.
This path is for local qualification, not a distributable application.

Dart tests also accept `CRISP_SMB_LIBRARY` as an environment variable. Set
`CRISPER_SMB_PYTHON` to a Python containing `impacket==0.13.0` and run
`dart test test/rust_smb_test.dart test/smb_transfer_test.dart`. The fixture is
loopback-only, authenticates a disposable test account, and offers SMB2 only.
It normalizes Impacket's malformed error/CREATE replies without relaxing client
validation. It cannot establish SMB3 encryption interoperability.

Regenerate the bridge with `flutter_rust_bridge_codegen` 2.11.1:

```
flutter_rust_bridge_codegen generate --rust-root rust --rust-input crate::api --dart-output lib/src/rust --dart-root . --no-deps-check --no-auto-upgrade-dependency --type-64bit-int --no-dart-fix
```

## Bundled app builds (native-asset hook)

An app can ship the bridge without `CRISP_SMB_LIBRARY` by opting in from its
own pubspec:

```yaml
hooks:
  user_defines:
    crisp_storage:
      rust_smb: true
```

`packages/crisp_storage/hook/build.dart` then runs `cargo build --release
--locked --target <triple>` for each Flutter build target and bundles the
cdylib as the code asset `package:crisp_storage/crisp_smb_bridge`. Flutter
embeds and signs it (`crisp_smb_bridge.framework` on iOS/macOS). Supported target
mappings include iOS device/simulator, macOS, Linux, Windows and Android.
Android uses the installed NDK; platform binary acceptance remains separate. Install the matching rustup targets
(`aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`,
`aarch64-apple-darwin`, `x86_64-apple-darwin`). The hook finds `cargo` via
`$CARGO`, `PATH` or `~/.cargo/bin` (Xcode phases have a reduced PATH) and
sets `SDKROOT` with `xcrun`. `rust_smb_library: <path>` bundles a prebuilt
library instead. App and CLI pubspecs enable the bridge by default. A Rust toolchain is required
unless an explicitly reviewed prebuilt bridge is provided.

At runtime `RustSmbSession.initialize` tries, in order: `CRISP_SMB_LIBRARY`
(define or environment), the app-bundled locations from
`bundledRustLibraryCandidates`, then FRB's developer default.
`rustSmbLibraryLocation` reports which one loaded (diagnostic only).

The native session holds at most eight open read/write handles. The Dart
adapter now queues further streams/uploads for a free slot instead of failing
with `TooManyHandles`, matching libsmb2's behavior under concurrent use.

## Transfer semantics

Rust-to-disk downloads keep file bytes native, cap reads at 256 KiB and use four
read-ahead requests. Native writes complete before progress advances; cancellation
cannot leave a background file write racing a new resume. Progress is coalesced
at 100 ms with a final value; fast reads may coalesce the initial offset. A callback exception cancels the native session. The shared facade retires it
after the failed operation completes; a later explicit resume opens a new
native session. It never automatically replays the failed operation. There is one download per session and eight file handles
maximum. Stream consumers receive bounded typed byte buffers and backpressure.

Resume validates source, size, timestamps and file identity when the server can
prove it. A missing/incompatible marker restarts the staging file. Rust and
libsmb2 markers are deliberately incompatible; switching backends never appends
bytes under another backend's validator. The app publishes the staging file only
after success. Uploads retain existing create/truncate semantics and are neither
resumable nor atomic. No transparent write replay is enabled.

## Qualification limits

| Gate | Current evidence / next check |
| --- | --- |
| Wrapper + bridge | Linux build, pure Dart analysis and local fixture tests |
| Protocol | CRUD, bounded streams, resume/revision restart, cancellation, wrong-password and required-encryption refusal on SMB2 fixture |
| Required SMB3 security | Pending Samba, Windows Server, Synology/QNAP: signing-required and encryption-required success; tamper/refusal tests |
| Reliability | Pending real reconnects, suspend/resume, quota/disk full, same-length remote edits, multi-GB stress and handle/RSS measurements |
| Performance | Pending comparable libsmb2/Rust throughput, CPU/RSS, first audio and seek measurements on the same NAS/network |
| Desktop | CI compiles host libraries; app embedding, signing, sandbox/network entitlements and final binaries remain to qualify |
| Mobile | CI compiles iOS arm64/device + simulator libraries; Android NDK ABI builds, XCFramework/plugin integration and physical-device tests remain to qualify |
| Distribution | Cargo grants and exact source license evidence recorded; final native notices, packaged binary closure and store review remain required |

`licensing/rust_dependencies.json` covers the entire resolved bridge Cargo graph,
including target-specific/build dependencies. `tool/check_rust_licenses.py`
rejects unknown license expressions or changed evidence. MIT alternatives are
selected where dual/triple licensing also offers copyleft. `unicode-ident` also
requires Unicode-3.0 notices. `allo-isolate` uses an Apache-2.0 license file.
The FRB crates omit license files in their archives; the upstream v2.11.1 MIT
license is recorded separately. `r-efi` publishes its SPDX grant and author list;
the complete reviewed notices are packaged in `crisp_storage/NOTICES`.
The libsmb2 dependency has been removed. The surrounding app/package license is not
changed by the permissively licensed independent Rust crates.

## GUI and CLI settings

The installed GUI's connection dialog shows **Rust SMB**. Existing libsmb2/auto
profiles are migrated and newly saved credentials use `smbBackend: rust`.
Credentials remain in the existing secure store. Browser builds still cannot open SMB sockets.

The CLI now provides the same shared SMB session through `SmbCliAdapter`:

```
crisp connect smb 'DOMAIN\reader@smb://nas/Books/' --name nas --smb-backend rust
crisp config smb-backend nas rust
crisp config smb-backend nas
crisp ls / --provider nas --json
crisp upload chapter.mp3 / --provider nas
crisp download /chapter.mp3 ./chapter.mp3 --provider nas
```

Omit `--secret` to use the password prompt/stdin. Encryption is required by
default; `--no-require-encryption` is explicit SMB2 opt-in. Invalid backend names
fail without changing the saved setting. `providers --json` reports the configured
backend without credentials. `upload` and `sync` stream local files for SMB;
downloads publish a `.part` staging file only after success. Byte-buffer consumers
have explicit size limits. Public share links are unsupported by SMB.

CLI profiles remain in the CLI's private configuration file; GUI profiles remain
in the GUI store. These are separate existing stores, with the same backend
values and security rules. A session override wins over its saved profile; legacy
profiles without a choice use the build default (normally libsmb2). Changing a
profile affects new sessions, not an already-running transfer.

Tests cover profile round trips, legacy defaults, invalid input, override order,
CLI configuration commands, GUI selector callbacks/localization, and adapter CRUD
and bounded transfers for libsmb2, Rust and Auto. The GUI integration tests use
the same authenticated fixture as the CLI. Run the GUI tests with Flutter;
run `dart test test/smb_adapter_test.dart test/cli_runner_test.dart` from `cli/`.
The `surfaces` CI job runs both. Live SMB tests require the two fixture environment
variables described above. These fixture tests do not replace real SMB3/device
qualification.

## Release acceptance

The historical prototype checks do not certify a new combined release. Current
local loopback tests exercise authentication, CRUD, bounded transfers, resume,
cancellation and refusal of an SMB2-only server when encryption is required.
They do not establish SMB3 encryption interoperability on every NAS, Windows
server or physical mobile device. Final app embedding/signing, per-platform
builds and actual NAS qualification remain separate gates.

The CI workflow builds the Rust bridge on Linux, Windows, macOS and iOS targets.
Default builds never download a libsmb2 binary. Source licence evidence and
final artifact guards run separately; see the current distribution audit.
