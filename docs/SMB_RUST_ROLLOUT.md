# Rust SMB rollout — experimental, libsmb2 remains default

Decision: reuse `smb2` 0.43.0 through an independent `crisp_smb` Rust crate and
flutter_rust_bridge 2.11.1. Do not reimplement the protocol in Dart or add Go's
runtime. CrispCloud and CrisperPlayer share one Dart facade; CrispSorter can
consume the core directly while retaining OS-mounted SMB. For the current
Dart/Rust split and proposed Filen/Internxt integration, see
[STORAGE_ENGINE_ARCHITECTURE.md](STORAGE_ENGINE_ARCHITECTURE.md).

## Backend policy

`SmbSession` preserves its API. Optional `backend: SmbBackend.rust` selects Rust
per session. Otherwise the compile-time `CRISP_SMB_BACKEND` chooses:

| Value | Behavior |
| --- | --- |
| `libsmb2` (default) | Existing worker-isolate implementation; never loads Rust |
| `rust` | Strict Rust; missing native library is an error |
| `auto` | Rust preferred; fallback only if native loading/bridge initialization fails |

Selection happens before passing credentials or connecting. Authentication,
network, signing, encryption, protocol and transfer failures NEVER trigger
fallback. Unknown mode values are rejected. `effectiveBackend` is diagnostic
only; do not include credentials or remote paths in telemetry.

Both backends require signing. Encryption remains required by default. Rust
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

## Transfer semantics

Rust-to-disk downloads keep file bytes native, cap reads at 256 KiB and use four
read-ahead requests. Native writes complete before progress advances; cancellation
cannot leave a background file write racing a new resume. Progress is coalesced
at 100 ms with a final value. A callback exception cancels the session; create a
new session to resume. There is one download per session and eight file handles
maximum. Stream consumers receive bounded typed byte buffers and backpressure.

Resume validates source, size, timestamps and file identity when the server can
prove it. A missing/incompatible marker restarts the staging file. Rust and
libsmb2 markers are deliberately incompatible; switching backends never appends
bytes under another backend's validator. The app publishes the staging file only
after success. Uploads retain existing create/truncate semantics and are neither
resumable nor atomic. No transparent write replay is enabled.

## Qualification gates before changing the default

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
complete notice assembly is still a packaging gate. Existing libsmb2 LGPL
obligations remain while it ships. The surrounding app/package license is not
changed by the permissively licensed independent Rust crates.

## GUI and CLI settings

The installed GUI's connection dialog offers **SMB transport**: libsmb2, Rust or
Auto. Save it with a connection profile or reconnect to apply it. The choice is
stored as `smbBackend` beside `requireEncryption`; credentials remain in the
existing secure store. Browser builds still cannot open SMB sockets.

The CLI now provides the same shared SMB session through `SmbCliAdapter`:

```
crisp connect smb 'DOMAIN\reader@smb://nas/Books/' --name nas --smb-backend libsmb2
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

## Surface validation checkpoint — 11 November 2026

Local checks covered 24 shared Dart tests (23 transport tests plus notice
consistency), the complete 109-test CLI suite and 8 native core unit tests.
The loopback SMB fixture was enabled for transport tests. These are recorded
checks, not a guarantee for every future revision or provider.

[The workflow at `13ca681`](https://github.com/CrispStrobe/CrispCloud/actions/runs/43012455534)
passed Linux, macOS, iOS compilation/Apple padding checks, and the GUI/CLI
`surfaces` job. The Windows job stopped in recipe integrity verification because
Git converted the pinned LF files to CRLF. Package-specific Git attributes preserve the original bytes. The subsequent
Windows run passed recipe verification, then found CRLF/LF differences between
the distributed notice and Dart's runtime string. The notice now also retains
LF; recipe integrity and notice consistency were verified locally after export
with `core.autocrlf=true`. A full Windows rerun must still confirm both fixes.

The earlier macOS prebuilt-library install-name failure is addressed by the
source recipe below and passed the subsequent macOS/iOS CI checks. Final app
embedding/signing, physical-device and real signing/encryption NAS qualification
remain separate gates.

CLI settings/listing output labels old profiles without an explicit choice as
`build default`, matching the shared adapter's compile-time default behavior.

## Apple fallback packaging

GUI and standalone CLI resolve the same `packages/dart_smb2` fork (0.2.5+crisp.1).
The libsmb2 backend remains available and remains the default. Apple builds now
compile the pinned r10 source with install-name header padding, so long checkout
paths work with Dart and Flutter native assets. Xcode command-line tools, Python 3,
curl and zip are required. Other platforms use checksum-verified r10 binaries.
See [recipe provenance and licensing](../packages/dart_smb2/CRISP_PATCHES.md).
This fixes packaging without changing backend selection or fallback policy.

CI runs shared tests on Linux, Windows and macOS, GUI/CLI fixture tests on Linux,
and iOS device/simulator compilation. Both Apple recipes are checked by rewriting
a compiled binary's install name to a long path and re-signing it. SMB3 encryption
against production servers and physical-device testing remain qualification gates.
