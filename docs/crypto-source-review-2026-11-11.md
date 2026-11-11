# Workspace source and dependency review — 11 November 2026

This technical review refreshes the source bindings in
[apple-export-policy.json](apple-export-policy.json) after the workspace UX
changes. The reviewed application revision is
[`6a8e24c917479d83cc468e072d47405eda8d86a1`](https://github.com/CrispStrobe/CrispCloud/commit/6a8e24c917479d83cc468e072d47405eda8d86a1),
compared with main at
[`92078b5d7db04c2f1c211cff62c08eceaf9ddf8a`](https://github.com/CrispStrobe/CrispCloud/commit/92078b5d7db04c2f1c211cff62c08eceaf9ddf8a).

The updated `reviewed_on` date records this engineering reassessment. The
policy's encryption declaration, documentation decision, application identity,
France history/availability references and TestFlight audience references retain
their existing values and their previously recorded evidence. No live store or
distribution review, legal classification, upload or deployment was performed
for this refresh. Artifact verification and live distribution checks remain
separate release requirements described in
[export-compliance.md](export-compliance.md).

## Reviewed changes

The [inventory](crypto-inventory.json) lists 81 source files. Comparing their
exact Git blob identities found changes in only the three UI files below. The
other 78 inventoried files and the inventory itself match the baseline.

| Input | Reviewed change | Effect on the recorded crypto scope |
| --- | --- | --- |
| [`lib/widgets/settings_dialog.dart`](../lib/widgets/settings_dialog.dart) | Adds the entry that opens keyboard-shortcut settings and its localization import. | Credential storage selection, setup and App Lock controls retain their existing logic. |
| [`lib/screens/screen_dialogs.dart`](../lib/screens/screen_dialogs.dart) | Shows current shortcut bindings, adds customization access and corrects shortcut descriptions; reformats the existing logout dialog. | Logout and credential-deletion retry/error behavior retain the same control flow. No encryption implementation or credential storage backend changes. |
| [`lib/widgets/command_palette.dart`](../lib/widgets/command_palette.dart) | Adds navigation/reopen commands, ranked command discovery, live bindings, enabled-state checks and dispatch through existing workspace command handlers. | Existing encryption, key-management and account handlers remain in use. The changes add no cryptographic algorithms, key formats or provider protocols. |
| [`pubspec.yaml`](../pubspec.yaml) and [`pubspec.lock`](../pubspec.lock) | Add the pinned `cupertino_icons` 2.0.0 package for the adaptive control font. | The exact published archive contains font/image/documentation assets and test code, with no production Dart library, native implementation or runtime dependency additions. No existing locked package entry changes. |

### Exact icon-package verification

The [published package](https://pub.dev/packages/cupertino_icons/versions/2.0.0)
identifies the package as icon assets for Flutter's adaptive widgets. The review
downloaded the [2.0.0 archive](https://pub.dev/api/archives/cupertino_icons-2.0.0.tar.gz)
without executing its contents and checked its SHA-256 against both the package
metadata and the committed lockfile:

```text
b7cc2390aac296c083bea762859413eb1cf5b630c70e0c7e4d831018f762a8b2
```

The archive is 2,602,507 bytes and contains 77 regular files. Its three Dart
files are all under `test/`; its manifest declares the
`assets/CupertinoIcons.ttf` font and development dependencies only. The review
found no native implementation files. This establishes the scope of this
dependency addition; it is not a font-parser security audit or a binary scan of
the finished application.

## Refreshed bindings

These values were computed with the repository's existing
[`apple_export_preflight.py`](../tool/apple_export_preflight.py) hashing rules:

```json
{
  "inventory_sha256": "db7392a4c6f94305bece8f17e5d629091073583ca81fec0d264e914ec377c3f0",
  "pubspec_lock_sha256": "20ea99fe42a831b47a4a71092923d7f766b09c77b25ffd2e6d62762430e8038c",
  "reviewed_source_sha256": "a20f74f2a93ed5f6c1d3a79e2aa1bbd9089c2154cbb8b9bc27a5718cc4999eae"
}
```

The source digest hashes the exact bytes of all 81 inventory-listed files in
sorted path order. The lockfile digest covers its complete bytes. Only the
review date, lockfile digest and reviewed-source digest change in the policy.
The validators and their failure-path tests are unchanged.

## Validation context

Hosted [CI run 42930629411](https://github.com/CrispStrobe/CrispCloud/actions/runs/42930629411)
tested the reviewed application revision. Its
[Linux analysis/test job](https://github.com/CrispStrobe/CrispCloud/actions/runs/42930629411/job/130228172217)
reported 7,644 tests passed and 35 skipped. All 18 Unix socket protocol fixtures
passed on that runner. The iOS, macOS and Android build commands succeeded;
their evidence-recording steps and the standalone evidence job rejected the
stale lockfile binding. This refresh preserves that rejection mechanism and
records the reassessed inputs instead of bypassing it.

Local validation of the refreshed bindings used the existing Python suites:

- `python3 -m unittest discover -s tool -p test_crypto_release_evidence.py`:
  41 tests completed, with the two existing platform-dependent skips.
- `python3 -m unittest discover -s tool -p test_apple_export_preflight.py`:
  all 37 tests passed.
- `python3 tool/crypto_release_evidence.py --check`: passed against these
  source inputs.

Any further edit to the inventory, lockfile or an inventory-listed source file
requires another delta review before its fingerprint is updated. A passing
source check does not validate a later binary or establish current store state.

## Integration review: startup recovery and keychain access

The workspace branch subsequently integrated main at
[`05de9cfaa1d3727e7e4fd53b51ec63c5c39438cc`](https://github.com/CrispStrobe/CrispCloud/commit/05de9cfaa1d3727e7e4fd53b51ec63c5c39438cc).
Relative to workspace checkpoint `2d641b6664f343b18cbbccb3ef16491d802a7eb2`,
exact inventory-file comparison identifies two additional changed inputs:

- `lib/main.dart`: adds a confirmed startup action to choose another credential
  store. It persists the explicit selection and retries ordinary initialization;
  an existing file vault still uses its password gate. This is an intentional
  recovery-policy change, not an automatic fallback or credential migration.
- `lib/widgets/credential_storage_setup.dart`: adds immediate-application labels
  and probes an explicitly selected keychain. A locked keychain has a specific
  outcome; an access failure can request a native picker grant and retry the
  selected path. Cancellation remains an error and no default keychain is
  substituted silently.

These changes are the upstream implementations from PRs #41 and #42, preserved
without modifications during integration. Their startup, setup and grant
regressions remain enabled. They change recovery and access orchestration, not
the cryptographic primitives, vault formats, KDF parameters or dependency graph.
The other 79 inventory-listed inputs match the preceding workspace checkpoint.
The icon-package lockfile is unchanged, and the source version retains main's
`1.1.0+12` update.

Neither parent's source fingerprint describes the combined tree. The policy
therefore records the reviewed combined-source digest:

```text
4b75a080f497a07e8110b313702b380c7452f5c9107e384fa5e51d6776f02900
```

The inventory and lockfile hashes remain the values recorded above. Only the
reviewed-source fingerprint changes from the preceding workspace policy; the
existing declaration, store/distribution assertions and validators are retained.
This integration review does not claim a new binary, live-store or legal review.

## Integration review: optional SMB runtime and backend selection

This engineering delta covers upstream SMB snapshot
[`4b44dc4d44ef05a18d2da2579d2e3b866b245643`](https://github.com/CrispStrobe/CrispCloud/commit/4b44dc4d44ef05a18d2da2579d2e3b866b245643)
and the integration fixes described below. It adds an optional Rust transport,
native bridge, and GUI/CLI backend selection. The earlier fingerprints and
validation results in this document describe their recorded revisions; they do
not bind or establish acceptance for this expanded source tree.

The [inventory](crypto-inventory.json) now retains the original 81 reviewed paths
and adds exactly 46, for 127 unique files. Its review date is 11 November 2026.
The additions cover 19 shared runtime and bridge files, 14 GUI/CLI orchestration
files, and 13 manifest, build and committed dependency-evidence inputs. Existing
entries such as `lib/widgets/connection_dialog.dart`,
`lib/providers/auth_provider.dart` and the GUI credential-store implementation
remain in the source binding. The application `pubspec.lock` retains its
separate complete-file fingerprint; the CLI lockfile and both Cargo lockfiles
are included in the reviewed-source inventory.

| Input group | Reviewed behavior and binding purpose |
| --- | --- |
| Shared SMB facade, backend selector, URL paths and connection/profile models | Bind session override order, default selection, endpoint confinement, saved non-secret settings and the web rejection path. |
| libsmb2 and Rust session adapters | Bind credential handoff, signing/encryption requirements, error translation, transfer state and the boundary that permits backend fallback. |
| Generated Dart/Rust bridge and native core | Bind native loading, serialization, session registry, dispatch and the independent Rust implementation, including generated code that participates at runtime. |
| GUI and CLI adapters, selectors, configuration and transfer commands | Bind explicit user choices, credential persistence, profile validation, default diagnostics and the entry points that make the optional transport reachable. |
| Manifests, lockfiles and build/evidence inputs | Bind the exact requested and resolved graphs, optional library build commands and committed dependency evidence/checker. The independent core and bridge are separate Cargo workspaces and both lockfiles are retained. |

### Selection and security orchestration

[`SmbSession`](../packages/crisp_storage/lib/src/smb_session.dart) selects an
explicit constructor override first, then a saved `RemoteConnection.smbBackend`,
then compile-time `CRISP_SMB_BACKEND`. The build default remains `libsmb2`.
New GUI and CLI connection surfaces explicitly start with libsmb2 and persist
the chosen setting; changing a saved choice affects newly constructed sessions.
Unknown mode values are rejected. Browser builds continue to reject SMB socket
operations.

The [selector](../packages/crisp_storage/lib/src/smb_backend.dart) does not load
Rust when libsmb2 is requested. Strict Rust selection propagates unavailable
library errors. Auto catches only native loading/bridge initialization
unavailability, before constructing the selected transport session. Session
construction and subsequent handshakes occur outside that fallback block.
Authentication, network, signing, encryption and transfer failures therefore do
not initiate a login through another backend.

`RemoteConnection.requireEncryption` remains true by default. The GUI and CLI
retain an explicit choice to relax that requirement. The libsmb2 wrapper passes
`signing: true`, binds sealing to the configured encryption requirement and
selects SMB3 when encryption is required. The Rust wrapper rejects empty/guest
usernames before connecting, checks the resulting session's signing state and
checks encryption when required before opening the share. It disables automatic
reconnect, DFS and compression. These are source-level policy observations;
they do not establish every negotiated algorithm or behavior on every server,
device or platform.

Shared URL validation binds the endpoint, port and configured share/root.
Native path validation also rejects absolute and traversal components. These
checks confine application requests; they do not establish a server-side
filesystem sandbox or resolve server-side link/ancestor behavior.

### Credential persistence and integration fixes

GUI SMB credentials continue through
[`SmbConfigService`](../lib/services/smb_config_service.dart) into the configured
`SecureStorage` backend. Login verifies the connection before persisting the
credential map, and a persistence failure closes the newly created session.
Saved connection profiles carry backend and encryption settings through the
existing profile store. The optional native wrapper adds no credential store.

The CLI continues to use its separate plaintext YAML configuration. Its
[configuration writer](../cli/lib/config/cli_config.dart) applies mode `0600`
before writing on non-Windows platforms; Windows uses its existing filesystem
access controls. This storage is distinct from the GUI credential vault.
Credentials pass into the bridge as a configuration JSON string and remain in
the native session configuration. This review does not establish zeroization of
those copies. Native operational errors are reduced to a stable error code and
retryability flag before presentation.

Three integration corrections preserve the intended saved-choice behavior:

- An invalid saved GUI backend is rejected before any profile fields are
  applied. The existing form remains intact and the user receives a handled
  configuration error.
- Legacy CLI profiles without `smbBackend` report **build default**. Diagnostics
  no longer imply an explicit libsmb2 choice when compile-time selection may
  supply another backend.
- CLI YAML string values use JSON quoting, preserving their string type and
  contents when read back. Passwords and settings such as `true`, `null` or
  `12345` no longer change type through YAML scalar coercion. This changes
  serialization, not the configuration file's storage protection.

### Dependency and runtime boundaries

The Dart graph adds `flutter_rust_bridge` pinned to `2.11.1` and its resolved
`build_cli_annotations 2.1.1` dependency. The independent Rust core pins
`smb2 0.43.0`; the bridge pins `flutter_rust_bridge 2.11.1` and references that
core by path. Both Cargo graphs and their generated bindings are source-bound.
The optional host build helper uses `cargo build --release --locked`. Committed
dependency evidence and its checker are included as exact reviewed inputs;
their inclusion does not add a new interpretation of the recorded declarations.

`CRISP_SMB_LIBRARY` remains an explicit external-library selection mechanism,
using a compile-time value or process environment. Without it, the generated
loader uses its configured library stem and location. Source fingerprints bind
that loading policy and the reviewed source graph, not the bytes of an arbitrary
library selected at runtime. Final application embedding and actual loaded
artifact identity require their own recorded evidence.

The existing policy declaration and distribution assertions retain their
recorded values. This engineering delta changes inventory scope and review
documentation. Final source/dependency fingerprints and measured validation
results must refer to the formatted combined tree; this section records no new
artifact, live-store or platform qualification.

### Combined source binding

The formatted integration retains the existing declarations and distribution
assertions. Its 127 reviewed paths and resolved application lockfile produce
the following input fingerprints under the unchanged verifier:

```json
{
  "inventory_sha256": "fbcfb3b91097052ade593d018df60cebd2276bfd38222cb2e4e71d647eaa6952",
  "pubspec_lock_sha256": "490f6b9238de9a8e51292dc8831844e7b502b8f186cc6e2d426bf2fb25f88853",
  "reviewed_source_sha256": "9b884cf643c23fad85bcbb66d862cb365be5c86ce4545973f8fa34cba04dcf40"
}
```

The optional build helper now records Cargo's actual emitted dynamic library
path and verifies that it exists, including builds with a custom target
directory. This improves build reporting; runtime binary identity still needs
the separate artifact checks described above.


### Follow-up incoming workflow review

Incoming SMB commit
[`087b2d9d38797bd96eda64962e1998b1f8731c1f`](https://github.com/CrispStrobe/CrispCloud/commit/087b2d9d38797bd96eda64962e1998b1f8731c1f)
adds a non-cancelling host matrix and authenticates the surface job's private
Git source dependencies using its existing GitHub Actions secret/token context.
The credential is consumed by the runner's Git URL rewrite, not application
code or packaged settings. This workflow is the only changed inventory-listed
input since the combined binding above. The application runtime, both Cargo
lockfiles, application dependency lockfile and inventory are unchanged.

The incoming saved-backend assertion and explicitly historical rollout notes
are also retained. CLI diagnostics preserve the integrated `build default`
label in both text and JSON without writing an explicit backend into old
profiles. The current reviewed-source binding is:

```text
c3f94d46fa8055fe092d2e65c5a14ca17439c34b4d6ccb05260f4524ae491cca
```

Only the source fingerprint changes in the policy. Its inventory/lockfile
fingerprints and all declarations and distribution assertions are preserved.
This records the reviewed CI setup; it does not establish a successful hosted
workflow, native packaging, live store state or actual loaded-binary identity.


### macOS package-test path review

The follow-up host test wrapper
[`run_package_tests.py`](../packages/crisp_storage/tool/run_package_tests.py)
addresses the install-name expansion failure recorded in the
[upstream macOS job](https://github.com/CrispStrobe/CrispCloud/actions/runs/42992765040/job/130429384351).
The wrapper is the 128th inventory-listed input. The host workflow is the only
previously inventoried file changed by this follow-up; application, credential,
transport and native bridge sources and dependency lockfiles remain unchanged.

On macOS the wrapper makes a physical package copy under `/private/tmp`, excludes
caches/build outputs, bounds the native-asset install path, and checks the copied
resolved lockfile before and after offline locked dependency resolution. It runs
the same Dart tests with the supplied arguments, preserves the exit status, and
cleans up the temporary copy. The workflow continues to run Dart directly on
other hosts. No binary, dependency, build hook, assertion or skip condition is
replaced. Local flow checks are separate from macOS execution; the latter remains
a hosted acceptance gate. This test-path adjustment does not establish signed
application packaging or live SMB3 qualification.

The unchanged verifier computes these current source bindings:

```json
{
  "inventory_sha256": "2f716200d7249f094dd491174929a355d87958150c4edeaebd464b61da13e0bd",
  "pubspec_lock_sha256": "490f6b9238de9a8e51292dc8831844e7b502b8f186cc6e2d426bf2fb25f88853",
  "reviewed_source_sha256": "214bc8ffeb3d682c2fd44820319625c172b8a425280283b021bf8f17d11a61f4"
}
```

The policy changes only its inventory and reviewed-source fingerprints for this
reviewed delta. Its lockfile fingerprint, declarations and distribution assertions
retain their values. Binary and live-store evidence remain separate requirements.
