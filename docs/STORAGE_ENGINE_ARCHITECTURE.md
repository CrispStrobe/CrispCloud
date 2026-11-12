# Dart and Rust storage engines

Decision recorded on 11 November 2026 for CrispCloud, CrisperPlayer and
CrispSorter. This describes SMB, Filen and Internxt storage, not the language
composition of the entire applications. The tables describe responsibilities;
line counts would mix application code, generated bridges and vendored libraries.

SMB engine selection is implemented. CrispCloud's GUI now also offers the
vendored Rust Filen/Internxt clients as an experimental, per-connection engine
(Dart remains the default); see [RUST_CLOUD_ENGINES.md](RUST_CLOUD_ENGINES.md).
The standalone CLI, CrisperPlayer and release packaging are not migrated yet.

## Current implementation

| App / surface | Application layer | SMB engine | Filen / Internxt engine |
| --- | --- | --- | --- |
| CrispCloud installed GUI | Flutter/Dart; provider adapters, credentials and transfer queue | Shared Dart facade; libsmb2 C library by default, optional Rust through FFI | Dart clients by default; optional Rust (`crisp_cloud_bridge`) per connection |
| CrispCloud standalone CLI | Dart VM; independent CLI configuration | The same shared SMB facade and choices as the GUI | Not yet supported by the CLI adapter factory |
| CrisperPlayer installed GUI and desktop control | Flutter/Dart; remote libraries, download queue, imports and playback | Same shared facade, pinned to an immutable CrispCloud commit | Dart clients in its remote adapter |
| CrispSorter GUI and standalone CLI | Svelte/TypeScript GUI; Rust/Tauri application backend | Explicit OS mount or direct Rust | Native Rust clients when the provider features are enabled |

The default Flutter SMB route is **Dart → dart_smb2 → C libsmb2**. The optional
route is **Dart → flutter_rust_bridge → crisp_smb → Rust smb2**. There is no pure
Dart SMB protocol implementation. Sorter calls the Rust core directly and does
not load Dart or the Flutter bridge.

In this repository, the current boundaries are:

- [`packages/crisp_storage`](../packages/crisp_storage/README.md): shared Dart
  transports, profiles, scheduling primitives, SMB selection and generated bridge.
- [`crisp_smb`](../packages/crisp_storage/native/crisp_smb/README.md): independent
  Rust SMB protocol/session core; the adjacent `rust/` crate exposes the bridge.
- [`FilenClientAdapter`](../lib/services/filen_client_adapter.dart) and
  [`InternxtClientAdapter`](../lib/services/internxt_client_adapter.dart): current
  Dart provider integration. Their bounded transfer helpers remain app-owned.
- [`cli_adapter_factory.dart`](../cli/lib/adapters/cli_adapter_factory.dart):
  currently accepts S3, SFTP, SMB and WebDAV. A GUI provider does not automatically
  become a standalone CLI provider.

Sorter already has reusable `crisp-filen` and `crisp-internxt` Rust libraries,
each with its own CLI and application adapter. Their current sources live at
`crates/crisp-filen-native` and `crates/crisp-internxt-native` in CrispSorter.
`internxt-core` is a test-only reference there, not its production client.

## Target responsibilities

Reuse one versioned Rust implementation per native provider across all three
applications. Extend the established Dart bridge approach instead of maintaining
another protocol port. This does not require moving existing HTTP/WebDAV/SFTP
clients or Flutter application state into Rust.

| Host application owns | Shared provider engine owns |
| --- | --- |
| UI, per-account settings, secure-store selection and account lifecycle | Protocol login/renewal, metadata decoding and provider crypto |
| Persistent job queue, scheduling, user cancellation and conflict decisions | Bounded chunk processing, backpressure, transport operations and cancellation hooks |
| Staging/publication policy, imports, local library and playback | Validated range/resume primitives and provider-specific checkpoints |
| User-facing progress, errors and logs | Typed capabilities, normalized errors and aggregate progress events |

The host queue owns job-level retries and concurrency. A provider may own bounded
chunk retries/concurrency, but limits and cancellation must compose; nested
unbounded retries must not multiply requests. A capability is advertised only
when that engine and adapter can implement it safely.

For native Flutter transfers, prefer session/transfer handles and native-to-file
operations. Keep large file bodies in Rust where the platform permits it. Expose
bounded byte streams when a Dart consumer needs bytes; honor backpressure and
avoid whole-file JSON/base64 messages. Progress should be coalesced while
cancellation and terminal states remain prompt.

The existing Filen/Internxt Rust clients use blocking HTTP. Run them on dedicated
storage workers or a suitable blocking executor; do not call them on the Flutter
UI thread or directly inside a Tokio async task. Bridge packaging, worker
lifetime, teardown and error mapping still need implementation and tests.

Keep secrets in the host's established store, pass them only to a scoped session,
and version serialized sessions. Do not assume Dart and Rust session JSON is
interchangeable. Migration must verify provider/account identity and key material
or require reconnection. This design does not share credentials across apps.
CrispCloud GUI uses secure storage; its standalone CLI currently uses a private
YAML configuration, not the GUI Keychain/profile store.

## Selection and fallback

The current SMB settings are documented in [SMB_RUST_ROLLOUT.md](SMB_RUST_ROLLOUT.md).
Flutter supports `libsmb2` (default), strict `rust`, and `auto`; Auto falls back
only if the native Rust library/bridge cannot initialize before credentials or
network activity. Sorter supports explicit `mounted` or `rust`, with no Auto.

For Filen/Internxt, retain the existing Dart and Rust clients as supported,
selectable engines. Both run behind one provider contract and must pass the
same tests. Keeping both is an intentional compatibility option, not merely a
promise to remove Dart after the first Rust rollout.

The planned settings are:

| Scope / value | Behavior |
| --- | --- |
| App default per provider | Filen and Internxt each initially use `dart`; defaults can change independently after qualification |
| Account: app default | An absent override inherits that provider's default |
| Account: `dart` | Strict Dart selection |
| Account: `rust` | Strict Rust selection; unavailable native support is an error |
| Account: `auto` | Prefer Rust, with Dart fallback only when locally unavailable before authentication/work |

CrispCloud's GUI implements the account-level values (dart, rust, auto) per
connection profile plus the build defaults `CRISP_FILEN_BACKEND` /
`CRISP_INTERNXT_BACKEND`; the CLI flags are still planned.
A later default flip to `auto` enables Rust-preferred operation with the bounded
fallback policy. It affects new sessions/jobs on inheriting accounts. Explicit
Dart/Rust overrides remain intact, and active transfers retain their original
engine. A paused job needs checkpoint validation or a safe restart before using
a different engine. GUI and CLI must expose the configured policy and effective
engine, and allow a manual override for a problematic account/provider.

Sorter continues to consume Rust directly. Keeping both language packages does
not itself make Dart callable from a Rust application: a Sorter Dart option
would require an explicit worker/runtime, packaging and platform tests. Treat
that as a separate desktop compatibility feature if needed, while retaining
both Dart/Rust choices in the Flutter consumers.

| Event | Required behavior |
| --- | --- |
| Strictly selected engine unavailable | Return an actionable error; do not silently substitute another engine |
| Auto detects unavailable Rust before creating/authenticating a session | May select the existing Dart engine and report the effective engine |
| Known unsupported capability discovered locally before work | May select an eligible engine only if the account's Auto policy permits it and the same security policy is preserved |
| Login, token renewal, network, crypto, integrity or protocol failure | Report the error; do not trigger an engine switch |
| Upload, delete, move or another mutation has started | Never replay it through another engine; a timeout may leave the remote result unknown |
| Transfer already running | Keep the selected engine fixed for that transfer |
| Engine changed before resuming a paused transfer | Validate engine/version/provider/account/object identity and validators; reject or safely restart incompatible state |

GUI and CLI must use the same selection logic, validation and capability rules.
Preserve legacy profiles, validate unknown values, and prevent a settings change
from changing an active transfer. Document which stores are shared: Player's CLI
controls the running app, Cloud's CLI has separate profiles, and Sorter's CLI uses
the same data directory/vault as its GUI.

Logs should report requested/effective engine, operation outcome, duration and
aggregate bytes. Exclude credentials, keys, session JSON, private remote paths
and raw upstream errors. Sorter's SMB logging is implemented; equivalent
cross-engine Filen/Internxt diagnostics are part of the proposed integration.

## Browser and platform boundaries

Native support does not establish browser support. SMB sockets are unavailable
in these browser surfaces. The Filen Dart entry point currently imports
`dart:io`, and the Rust clients' blocking HTTP API is unavailable for browser
WebAssembly. Neither is a drop-in browser fallback.

Retain and test existing browser-specific paths separately. Any future browser
provider support needs browser-compatible HTTP/crypto, CORS or an explicitly
configured gateway, and browser tests. A Rust/WASM build is a separate project,
not a consequence of adding the native bridge. Player's Pages local-file player
is separate from its Flutter native application and does not gain remote imports.

Desktop, Android and iOS require target-specific native builds, bundling,
signing/sandbox checks and physical-device tests before a default-engine change.
Filen's Dart crypto already has platform/native backends, so using Rust alone is
not evidence of a performance improvement. Compare identical files, accounts,
networks, cache state and security policies; measure throughput, CPU, peak memory,
cancellation latency and Player's time to first audio/seek behavior.

## Licensing

| Component | Current declared license / evidence boundary |
| --- | --- |
| Independent `crisp_smb` core and bridge | MIT OR Apache-2.0; exact third-party Cargo evidence is recorded separately |
| `dart_smb2` wrapper | BSD-3-Clause |
| Bundled libsmb2 | LGPL-2.1-or-later, including the retained fallback |
| Existing Dart Filen and Internxt clients | MPL-2.0 |
| Rust `crisp-filen` and `crisp-internxt` | MPL-2.0 in their manifests and license files |
| Sorter's independent `internxt-core` reference | MIT; test-only, not its production Internxt engine |

MPL-2.0 is file-level copyleft, not an MIT/Apache/BSD-style permissive grant; see
the [Mozilla FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/). Changing the language
does not change a component's license. If distribution requires a strictly
permissive graph, review provenance and any available grants separately.
Authority to dual-license original code does not relicense third-party code.
Retain existing notices and record exact source, dependencies, build inputs and
final native artifacts when adopting an engine. The libsmb2 fallback continues
to require its LGPL distribution materials.

## Delivery order and acceptance

1. Define a common provider contract, capabilities, errors, session ownership and
   a contract suite reusable by both Dart and Rust adapters.
2. Add Filen/Internxt adapters to Cloud's standalone CLI; keep current Dart
   behavior while establishing GUI/CLI parity and secure credential handling.
3. Expose the existing Rust Filen client to both Flutter apps, beginning with
   browse/download/range reads, then writes. Pin the reusable source rather than
   copying another implementation into each application.
4. Integrate Rust Internxt with shared login/2FA and session-renewal tests. Player
   currently has its own renewal adapter; consolidate behavior through tests,
   rather than discarding that compatibility fix.
5. Offer app defaults, per-account overrides and constrained Auto after platform
   and compatibility gates pass. Keep both engines supported and tested. Flip
   each provider's native default only on measured evidence; retiring an engine
   would be a separate decision, not an assumed outcome of this migration.

Required coverage before promotion:

| Area | Required checks |
| --- | --- |
| Wire compatibility | Dart upload → Rust download and reverse; supported Filen metadata/crypto versions; Internxt key/metadata formats |
| Authentication | Correct/incorrect credentials, 2FA, revoked sessions, single-flight Internxt renewal, account change during an operation |
| Transfers | Empty/large files, range/seek, bounded memory, backpressure, cancellation, process restart and validated resume |
| Failures | Corrupt/truncated data, changed source, disk full, short writes, quota/rate limit, interrupted/ambiguous mutations without cross-engine replay |
| Settings | Save/reload, legacy inheritance, invalid values, requested/effective engine, default flips preserving explicit overrides and active jobs, and both GUI/CLI paths |
| Runtime | Native-library absence, bridge initialization, worker lifecycle and no UI/async-runtime blocking |
| Platforms | Linux/macOS/Windows and supported mobile ABIs/devices; browser checks as a separate target |
| Distribution and performance | Exact source/license/native evidence; comparable throughput/CPU/memory/first-audio measurements |

Use hermetic fixtures and independent crypto vectors for ordinary tests. Live
provider interoperability requires explicit test-account credentials and bounded
temporary resources. Existing SMB fixture/CI results do not qualify the proposed
Filen/Internxt bridge. Local test instructions and existing SMB surface coverage
remain in [the rollout guide](SMB_RUST_ROLLOUT.md) and [CLI README](../cli/README.md).


## Executable Dart / Rust package conformance

`.github/workflows/provider-conformance.yml` runs the shared, pinned
[provider conformance harness](https://github.com/CrispStrobe/crisp-cloud-rs/tree/6c1f351dbe0cb9efe2ecf19b009603907bf5cf2e/conformance).
It tests this app’s vendored Filen SDK and published Internxt 0.2.3 against
the standalone Rust packages. It uses the app dependency pair, PointyCastle
4.0.0 / dart_pg 2.1.0, without changing runtime dependencies.

The same independent fixtures run through real package APIs and compiled Dart
CLI probes with software and native AES backends. Checks include password/key
derivation, metadata, empty and boundary-sized chunks, CTR streaming and ranges,
wrong keys, damaged data, Unicode, pagination, cache reuse, HTTP failures,
read retry and create/rename/move/trash payloads. Each engine decrypts the other
engines’ exports. Loopback mocks validate authentication and wire requests;
mutations denied with 403 must not be replayed. No live account is used.

Both GUI and CLI use these package formats. Package parity does not qualify an
app bridge, GUI settings, session migration, active-job engine selection, native
mobile packaging or every transfer/resume/cancellation path. Keep the existing
surface and provider tests, and the rollout gates above, before changing defaults.

CI publishes `report.md`, `report.json`, wire traces and resolved probe lockfiles.
Unexpected differences fail. Exact reviewed gaps remain visible and set
`promotion_ready` to false, even when both implementations share a permissive
parse bug. `--strict` fails on those gaps too. A green regression baseline is
not permission to switch defaults. Legacy text-secret encoding requires a
compatibility decision before any format change.

Reproduce from a checkout of the pinned harness, with Python 3.12+, stable Rust
and Dart 3.13.7. From this app repository’s root:

```sh
python -m pip install cryptography==50.0.0
python ../crisp-cloud-rs/conformance/run.py --pointycastle 4.0.0 --dart-pg 2.1.0 --dart-filen packages/filen_client --published-internxt 0.2.3
# Add --strict for the default-promotion gate.
```

Keep this harness commit pinned and advance it deliberately with the compatibility
report. Retain both language implementations and explicit engine choices.


The first completed shared run exercised 131 cases and 363 cross-decryptions
with zero unexpected failures. Ten exact diagnostic cases remain promotion
blockers: empty CBC encryption, CBC envelope validation, two legacy secret
encoding directions, two negative CTR offsets, odd-length password salt hex,
unreadable Filen metadata, missing Internxt listing collections and listing
GET retry behavior. These are SDK compatibility findings, not live-account or
GUI qualification. Dart retries an Internxt listing 503; Rust currently returns
the error. Rejection is compared at the API boundary; exception classes/messages
are language-specific. See each CI run’s report for its actual source results.
