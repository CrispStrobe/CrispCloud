# SMB storage review — 11 November 2026

## Current implementation
CrispCloud GUI and CLI use `packages/crisp_storage`. It offers `libsmb2`, `rust`
and `auto` per connection, with libsmb2 still the default. Auto falls back only
when the Rust library cannot load before authentication; authentication, network
and security failures never trigger an engine switch. Signing and required SMB3
encryption remain the defaults. Settings and CLI examples are in
[SMB_RUST_ROLLOUT.md](SMB_RUST_ROLLOUT.md).

The shared Dart API calls a permissively licensed Rust SMB core through FFI.
CrispSorter consumes that same core directly; CrisperPlayer pins the shared Dart
package at an immutable commit. We do not maintain a Dart SMB protocol port.

The fallback is dart_smb2 0.2.5+crisp.1 (BSD wrapper) over LGPL-2.1-or-later libsmb2
r10. The Apple recipe is rebuilt with install-name padding; other targets use
checksum-verified release binaries. See the [packaging patch](../packages/dart_smb2/CRISP_PATCHES.md).
Keeping this fallback does not remove LGPL distribution requirements.

## Implemented protections
Downloads use bounded, awaited disk writes and validated staging/resume metadata.
Failed initial opens can retry without leaking parallel sessions. Rust validates
paths, caps chunks and handles, propagates cancellation and redacts remote errors.
The CLI uses the same adapter contract for streaming uploads, downloads and
mutations; the GUI exposes the same backend choices.

## Validation and remaining qualification
Shared transport and complete CLI tests pass with a local authenticated SMB2
fixture. CI covers Flutter controls/adapters, native host builds and Apple
packaging. The source archive hash and all vendored patches are validated.
A fixture does not establish SMB3 encrypted interoperability, performance,
physical-device support or final signed-app license compliance. Those remain
release qualification gates; do not switch the default on fixture results alone.

## Wider provider architecture

The Dart/Rust responsibility split, proposed Filen/Internxt reuse, their current
CLI gap, constrained fallback policy, browser boundaries and license differences
are documented in [STORAGE_ENGINE_ARCHITECTURE.md](STORAGE_ENGINE_ARCHITECTURE.md).
SMB selection is implemented; the proposed Filen/Internxt bridge is not.
