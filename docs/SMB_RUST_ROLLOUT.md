# Experimental Rust SMB qualification

## Current state

The [experimental crate](../packages/crisp_storage/native/crisp_smb/README.md)
provides a standalone Rust API. The Flutter application continues to use the
existing `SmbSession` and `dart_smb2` / libsmb2 backend. There is no generated
application bridge, backend selector, platform build hook or packaged runtime
integration for this crate in the current tree. Adding its source files does
not enable it in an application connection.

The crate pins `smb2` to `0.43.0` and commits its Rust dependency lockfile. Its
wrapper requests named authentication, signing and configured encryption;
automatic mutation replay is disabled. The current source bounds individual
read/write chunks to 256 KiB and open handles to eight. Those implementation
choices are starting points for qualification, not proof of interoperability,
resource limits under every failure path or platform readiness.

The existing production SMB optimization is separate: Dart downloads now await
bounded disk writes, and a later operation can retry a failed initial pool
connection. Its local SMB2 fixture and CI step exercise that production backend.
They do not exercise or qualify this Rust crate, SMB3 encryption, or real-server
performance. See the [storage review](SMB_STORAGE_REVIEW.md).

## Acceptance required before application integration

Record the exact application revision, crate revision, dependency lockfile,
target, server configuration and result for each gate. A unit-test command or a
successful compile does not complete a server or device acceptance row.

| Gate | Required evidence | Current boundary |
| --- | --- | --- |
| Dart bridge and source ownership | Contract tests for source/account/grant identity, handle ownership, translated errors, exact byte counts and cancellation across the bridge. A reviewed operation must retain its original endpoints. | The bridge and application adapter are absent. |
| Authentication and transport policy | Supported-server tests for successful and rejected authentication, required signing, required encryption, downgrade rejection, unavailable encryption, guest rejection and connection loss. Preserve explicit connection choices and secret redaction. | Wrapper checks exist; these server-policy combinations have not been qualified here. |
| Paths and object identity | Tests for configured-root confinement, literal Unicode and percent characters, reserved names, separators, traversal, parent reparse/symlink components, object replacement and missing-versus-denied results. Review the underlying server/open semantics, not just string validation. | The wrapper rejects some malformed paths and leaf links; full parent-object confinement is not established. |
| Browsing and metadata | Validate complete directory results, timestamps, object/version identity, hidden files, capability reporting and large-directory paging with bounded resources. | The current listing checks its 10,000-row limit after obtaining the complete directory result. That is not a bounded paging implementation. |
| Reads and downloads | Cover empty files, exact chunk boundaries, short reads, size changes, handle identity changes, interrupted writes, incompatible resume markers, local I/O failures and final source revalidation. Retain caller-owned staging and explicit publication. | Direct downloads currently reject zero-byte files. Resume and failure behavior require broader contract and server coverage. |
| Writes and mutations | Match reviewed create-only/overwrite choices, collision outcomes, expected-revision checks, rename/delete semantics and metadata behavior. Test partial writes and ambiguous cancellation outcomes without automatic replay. | The wrapper exposes mutation primitives; application operation-review and conflict contracts are not integrated. |
| Resource lifetime and progress | Verify disconnect, failed connect, cancellation during every operation, handle cleanup, bounded memory, concurrent callers and progress ownership. Confirm an interrupted mutation is never reported as rolled back without evidence. | Session serialization and cancellation exist; the progress counter is shared and concurrent request behavior needs qualification. |
| Native targets and packaging | Reproducible builds and runtime tests for each supported target/architecture, native loading, sandbox access, distribution signing, installation and removal. Unsupported targets must retain an explicit supported route. | There are no application build hooks or packaged libraries for this engine. |
| Performance | Reproducible comparison of latency, throughput, memory and cancellation on representative local and remote servers, directory sizes and target devices. | No throughput, memory improvement or device-performance claim is established here. |
| Dependency, license and crypto evidence | Review exact locked dependency sources and notices, native packaging obligations, cryptographic inventory and artifact evidence. Retain existing application notices until the actual distributed dependency graph changes. | The crate's declared wrapper license and lockfile are not a completed dependency or application-distribution review. |

## Test and evidence scope

From `packages/crisp_storage/native/crisp_smb`, run:

```sh
cargo test --locked
```

The current source contains two unit tests: malformed-path rejection and the
format of a credential-free wrapper error. They do not connect to a server or
exercise downloads, writes, session cancellation, encryption or a Flutter
bridge. Record any execution result separately from this description of the
test source. Add the missing contract and integration cases before expanding
the engine's application role.

Keep qualification fixtures isolated from user credentials and shares. Require
deliberate fixture configuration for servers used by integration tests. An SMB2
fixture's encryption opt-out must remain limited to that fixture and must not
change production defaults.

## License and dependency review

The wrapper manifest declares `MIT OR Apache-2.0`, and the corresponding license
texts are included with the crate. That declaration applies to the wrapper; it
does not establish the license of every locked dependency. The lockfile includes
cryptographic packages, so a future native artifact also needs a review of the
exact linked sources and the application's existing crypto evidence rules.

Before packaging, produce the resolved dependency inventory from the locked
build, inspect the applicable license texts and source/provenance records, and
record the required notices for every distributed target. Review the resulting
binary and its actual dependencies. Retain the current libsmb2 notices while
the application continues to use that backend. This document makes no claim
that bringing in this experimental source changes the shipped license or
encryption scope.

## Enabling and reverting

Application adoption is a separate implementation change after the relevant
gates pass. It must make backend selection explicit, preserve current provider
capability checks and operation review, and support returning to the existing
backend without silently reusing incompatible partial-download markers. Enable
only qualified targets; record unsupported operations and platform limits in
the adapter. Do not change default connection behavior merely because this
crate compiles or its source is present.
