# Bundled VeraCrypt and TrueCrypt browsing

Implementation date: 15 November 2026. The bundled reader now opens supported
encrypted file containers, lists their filesystem and reads individual files.
It does not require a separately installed VeraCrypt executable. The existing
desktop mount service remains a separate integration.

## Open a container

Select a `.vc`, `.hc` or `.tc` file and press **F3**. The encrypted-container
dialog accepts the password, format, KDF, PIM, keyfiles and header location.
`.tc` selects TrueCrypt initially; the format can be changed explicitly. These
extensions are hints: encrypted containers have no public identifying magic.

Choose **Argon2id** explicitly for an Argon2id VeraCrypt container. **Automatic
(PBKDF2)** tries only the supported PBKDF2 PRFs. It does not allocate Argon2's
large working set for every incorrect PBKDF2 password. A blank PIM means the
format's default. TrueCrypt has no PIM. Passwords retain their exact UTF-8 bytes,
including leading and trailing spaces, with a 128-byte VeraCrypt or 64-byte
TrueCrypt limit. An empty password is permitted when keyfiles are selected.

After unlocking, the existing archive viewer shows the filesystem members and
can preview their bounded contents. **Lock container**, closing the view or
switching away releases its session. **Unlock container** starts a new attempt.
No credentials or unlocked keys are saved in panel preferences. Reopening a
serialized panel source requires unlocking again.

## Supported profile

| Feature | Support |
| --- | --- |
| Container cipher | AES-256-XTS |
| VeraCrypt headers | Version 5, required program version through 1.26, fully encrypted non-system file volumes |
| VeraCrypt PBKDF2 | SHA-512, SHA-256, Whirlpool and historical RIPEMD-160 |
| VeraCrypt Argon2id | Native Dart/Flutter applications; version 1.3, one lane, format-compatible PIM parameters |
| Native TrueCrypt | `TRUE` version 4/5 XTS headers from the 6.x–7.1a profile; SHA-512, Whirlpool and RIPEMD-160 |
| PIM | Default and custom values within explicit resource budgets; never silently reduced |
| Keyfiles | Up to 64 regular file prefixes; at most the first 1 MiB of each file; keyfile-only credentials supported |
| Header locations | Primary, primary backup, hidden and hidden backup, selected explicitly |
| Logical sector size | 512 or 4096 bytes; version-4 TrueCrypt uses 512 |
| Filesystems | Existing bounded FAT12/16/32, NTFS and ext2/3/4 reader profiles |
| Operations | Read-only listing, bounded file reads and streaming through the service API |

The inherited filesystem restrictions remain in
[FAT](archive-fat-profile.md), [NTFS](archive-ntfs-profile.md) and
[ext](archive-ext-profile.md). A successfully unlocked header with an unsupported
filesystem produces an explicit error, rather than an empty listing.

Not implemented: Serpent/Twofish/Camellia/Kuznyechik or cipher cascades;
BLAKE2s-256/Streebog PBKDF2; exFAT or other filesystems; pre-XTS TrueCrypt;
system/in-place/partially encrypted volumes; hardware token keyfiles; container
creation, resizing or writes. Hidden volume reads do not grant any write or
hidden-volume-protection capability. Backup headers are not silently substituted
for a damaged or differently protected primary header.

## Compatibility details

For non-system VeraCrypt PBKDF2, nonzero PIM selects
`15000 + 1000 * PIM` iterations. PIM zero selects the PRF's default: 500,000
iterations for SHA-512/SHA-256/Whirlpool and 655,331 for the historical RIPEMD-160
profile. TrueCrypt uses its fixed counts: 1,000 for SHA-512/Whirlpool and 2,000
for RIPEMD-160.

Argon2id derives **192 bytes**, then AES-XTS consumes the first 64. Deriving
only 64 bytes would produce a different key. PIM zero means 12: 416 MiB and six
passes. For nonzero PIM, memory is `min(64 + (PIM - 1) * 32, 1024)` MiB;
passes are `3 + (PIM - 1) ~/ 3` through PIM 31 and `13 + PIM - 31` thereafter.
The default native policy permits at most 1 GiB and 64 passes (custom PIM 1–82).
Explicit callers can lower the budget or raise the pass budget as far as the
1,024-pass hard ceiling; exceeding the selected budget is a resource error,
not a wrong-password result. PBKDF2 is separately bounded, with a five-million-iteration default
per candidate and a twenty-million native ceiling. Browser PBKDF2 has a
one-million-iteration ceiling. Higher PIMs are refused before derivation.
These PBKDF2 limits admit custom PIMs through 4,985 by default, 19,985 with an
explicit native budget and 985 in the browser.

The browser Argon2 path is deliberately unavailable. PointyCastle 4.0.0's web
implementation represents each 64-bit word with a `Register64` object; VeraCrypt's
default would create more than 54 million such objects before wrapper overhead.
It also runs on the browser thread. Native Argon2 uses typed memory in a worker
isolate. A bounded worker/Wasm backend is needed before enabling browser Argon2.

Keyfiles use the raw reflected CRC32 accumulator, add its big-endian bytes to
the pool modulo 256 and add that pool to the password modulo 256. VeraCrypt uses
a 64-byte pool up to 64 UTF-8 password bytes and a 128-byte pool above that;
TrueCrypt retains its 64-byte password limit. Empty keyfiles are rejected. The
implementation does not normalize passwords or substitute XOR for addition.

Every encrypted header uses XTS data-unit number zero, regardless of its slot.
Payload decryption instead uses the absolute container offset divided by 512.
Those XTS units remain 512 bytes even for a filesystem with 4096-byte logical
sectors. The parser checks both CRCs, exact integer representation, versions,
flags, alignment and the complete extent before any filesystem is opened.

## Reader and session ownership

`openVeraCryptArchive` owns its `koni.ByteSource` on success and failure and
returns a `ViewerArchive`. It decrypts aligned windows of at most 64 KiB into
bounded per-request buffers. Filesystem metadata traversal and member-size
limits remain enforced by the existing readers. It does not create a decrypted
image file. Optional source-revision checks run before and after every input
window. The F3 adapter uses the original captured source and viewer generation;
the native panel file adapter holds its own access grant and checks file stat
identity around reads.

Native header derivation is serialized through a cancellable worker queue.
Cancellation stops queued work or terminates the active isolate, so repeated
close/reopen attempts cannot accumulate large Argon2 workers. A late result
cannot replace a newer pane source. After adoption, navigating within the
container retains the same live session. Pane swaps transfer ownership before
cleanup; disposing the former owner does not revoke the new owner's reads.
Exiting or disposing the owning pane locks the session.

`PanelSourceService.enterContainer` is now asynchronous. Local native files
can be opened by path; remote/browser/nested callers supply an owned captured
byte source. `listFiles`, `readContainerFile`, `openContainerFile` and
`lockContainer` use that real session. They do not download an unbounded remote
object or reconstruct a key owner from JSON.

Owned password-derived and master-key byte buffers are overwritten when their
owners finish. Dart strings, VM copies and expanded cipher schedules cannot be
promised to disappear immediately from managed memory. XTS does not authenticate
payload contents, and the format's CRCs are not cryptographic authentication.

## Dependency decision and licensing

No application dependency was added or upgraded; the existing lockfile is
unchanged. The implementation uses the already resolved MIT PointyCastle 4.0.0,
MIT archive CRC helper and CrispCloud's explicitly MIT-licensed filesystem
readers. No VeraCrypt/TrueCrypt implementation source is copied or linked, and
this feature introduces no third-party GPL/LGPL dependency.

CrispCloud's top-level [project license](../LICENSE.txt) is already AGPL-3.0.
New reader, worker and dialog files bearing MIT SPDX declarations are original
MIT components; modifications to existing files retain their existing licensing.
The dependency decision here does not relicense the surrounding application or
claim that the complete repository has a permissive license.

| Evaluated option | License | Decision |
| --- | --- | --- |
| [PointyCastle](https://github.com/bcgit/pc-dart) | MIT | Existing portable primitives cover the requested AES credential profiles. Retained for this change. |
| [Botan](https://botan.randombit.net/) | BSD-2-Clause | Suitable native primitives and C FFI. It would still need the container/parser/filesystem layer plus per-platform packaging. |
| [VaultPonyCore](https://github.com/norsehorse-dev/VaultPonyCore/tree/f746a3af6448636eba837ea62de2e432d3f0e6a5) | Apache-2.0 | Useful independent compatibility reference and a candidate for broader cipher/exFAT coverage. Current Kotlin/Swift UniFFI integration would need a Dart adapter and reviewed native build/dependency graph. Not vendored. |

Format sources:

- [VeraCrypt volume format](https://veracrypt.io/en/VeraCrypt%20Volume%20Format%20Specification.html)
- [Header key derivation](https://veracrypt.io/en/Header%20Key%20Derivation.html)
- [PIM parameters](https://veracrypt.io/en/Personal%20Iterations%20Multiplier%20(PIM).html)
- [Encryption scheme](https://veracrypt.io/en/Encryption%20Scheme.html)
- [VaultPonyCore KDF interoperability](https://github.com/norsehorse-dev/VaultPonyCore/blob/f746a3af6448636eba837ea62de2e432d3f0e6a5/core/vc-crypto/src/kdf.rs)
- [VaultPonyCore keyfile interoperability](https://github.com/norsehorse-dev/VaultPonyCore/blob/f746a3af6448636eba837ea62de2e432d3f0e6a5/core/vc-crypto/src/keyfile.rs)

## Validation

Fixtures are generated independently with Python `cryptography`/OpenSSL,
`hashlib.pbkdf2_hmac` and `zlib.crc32`; they do not call the application encryptor
or KDF. They include production-cost Argon2id/PIM 1, custom PBKDF2 PIM, all three
TrueCrypt PRFs, long and keyfile-only credentials, malformed CRC/geometry and
complete encrypted FAT images. The images exercise listing, nested file reads,
unaligned XTS windows, all four header locations, explicit backup recovery,
wrong credentials, cancellation, source changes and locking.

These are independently assembled format fixtures. No binary fixture produced
by an upstream VeraCrypt or TrueCrypt executable was tested in this
qualification. VaultPonyCore was reviewed as a source reference; its external
real-application fixture corpus was not available in the reviewed repository.

The reproducible validation command and final source/test receipt are recorded
in `docs/evidence/veracrypt-20261115/`. Native Apple/Android packaging and live
user-created-container/device acceptance are separate from these Linux and
compiled-JavaScript regressions. GitHub Actions is not a completion dependency
for this work.
