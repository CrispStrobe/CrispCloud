# Cryptographic dependency and native source provenance

Reviewed on 2026-11-07. The initial application baseline was
`c1dc32161ed5a429c356c06e930966954faa4fbf`; the review also includes the embedded
iOS shell merged in `c4847d284665ad04b253ce925dbf387ff7123402`. This is an
engineering source inventory, not an export classification, a complete security
audit of every dependency, or a scan of a signed release binary. The release's
Git commit, resolved dependency evidence, native manifests and actual packaged
libraries must agree. See [the main audit](crypto-audit.md) for findings and
[the machine-readable inventory](crypto-inventory.json) for application scope.

## Required provider source

The published package archives below were downloaded and their SHA-256 digests
checked against the application lockfile, except Filen, which is a local fork
and was compared directly with its published upstream archive. A Git repository
URL alone does not identify the exact package source used by a release.

| Component | Exact source | SHA-256 / commit | License and integration |
| --- | --- | --- | --- |
| Filen SDK | [filen_client 0.2.2 archive](https://pub.dev/api/archives/filen_client-0.2.2.tar.gz); [CrispStrobe/filen-dart](https://github.com/CrispStrobe/filen-dart) | `89823f6add3a86aeafee8bc942de43544431ed21faa6cc851a4d6758a0473b05` | MPL-2.0. Vendored local fork; exact changed files and history are in [UPSTREAM.md](../packages/filen_client/UPSTREAM.md). |
| Internxt SDK | [internxt_client 0.2.3 archive](https://pub.dev/api/archives/internxt_client-0.2.3.tar.gz); [CrispStrobe/internxt-dart](https://github.com/CrispStrobe/internxt-dart) | `c730aeb1779104bd42b27c6215bcf1b62b73c2979e9d570a5e61ed187b760469` | MPL-2.0. Hosted package, with application storage and transfer adapters. |
| OpenPGP dependency | [dart_pg 2.1.0 archive](https://pub.dev/api/archives/dart_pg-2.1.0.tar.gz); [web-of-trust/dart-pg](https://github.com/web-of-trust/dart-pg) | `9f4f5a41c8282ac5f6a32e816a1fe4a5f2d54ec6527b57ce11d1f328140eda0c` | BSD-3-Clause text in the archive. Internxt's active key-generation path uses this implementation. |
| SMB Dart wrapper | [dart_smb2 0.2.1 archive](https://pub.dev/api/archives/dart_smb2-0.2.1.tar.gz); [ales-drnz/dart_smb2](https://github.com/ales-drnz/dart_smb2) | `ba54193d234f49a92e54222e5300bc4c901063457e8af2abfb4ac3153ac923eb` | BSD-3-Clause wrapper; separate LGPL native library, detailed below. |
| SSH/SFTP | [dartssh2 4.1.0 archive](https://pub.dev/api/archives/dartssh2-4.1.0.tar.gz); [vicajilau/dartssh2](https://github.com/vicajilau/dartssh2) | `39359aceafcf5940b868249e3c9c6d86e4e0f989eec7417d033c943157c84c51` | MIT. Pure Dart protocol using PointyCastle and PineNaCl. |
| Local database | [CrispStrobe/libdbm](https://github.com/CrispStrobe/libdbm/tree/547b5bfce1d3cd663810a3ceae35336857956139), version 0.2.1 | Git `547b5bfce1d3cd663810a3ceae35336857956139` | Apache-2.0. Pure Dart database; no native assets or cryptographic package dependencies at this revision. |

`libdbm` is declared with a moving `main` override in `pubspec.yaml`, but the
reviewed `pubspec.lock` resolves the commit shown above. A release must enforce
that lockfile and record the resolved Git source. A fresh resolution of `main`
is a new dependency input requiring review.

### Filen's reachable cryptography

The application reaches the vendored SDK through
[`FilenClientAdapter`](../lib/services/filen_client_adapter.dart),
[`FilenConfigService`](../lib/services/filen_config_service.dart) and
[`FilenStreamTransfer`](../lib/services/filen_stream_transfer.dart).
[`crypto.dart`](../packages/filen_client/lib/crypto.dart) implements:

- AES-256-GCM for metadata and file chunks, including PointyCastle metadata
  operations independent of the accelerated chunk backend.
- PBKDF2-HMAC-SHA512 for login, with 200,000 iterations in the reviewed path.
  The separate one-iteration metadata derivation consumes a high-entropy master
  key; it is not the password login derivation.
- HMAC-SHA256 filename hashes and SHA-512 file hashes.

[`aes_gcm_backend.dart`](../packages/filen_client/lib/aes_gcm_backend.dart)
selects available OpenSSL/Windows CNG/`cryptography` implementations for chunks.
The application enables `FlutterCryptography` on native platforms. These
optimizations do not remove Dart implementations or convert all metadata and
key derivation into operating-system encryption calls. Filen credentials use
the application's `SecureStorage`; the SDK's CLI credential writer is not the
app's persistence path.

### Internxt's reachable cryptography and remaining limitations

The exact 0.2.3 archive's `lib/crypto.dart`, `lib/auth.dart` and
`dart_pg`'s `lib/src/key/private_key.dart` are the source for this inventory.
The app's [adapter](../lib/services/internxt_client_adapter.dart) and
[bounded transfer implementation](../lib/services/internxt_streaming_transfer.dart)
retain those provider formats:

- AES-256-CTR file encryption, using BIP39 seed material and SHA-512 bucket/file
  key derivation. The server-provided SHA-256 file checksum is an unkeyed
  integrity check, not an AEAD tag or proof against a malicious server.
- PBKDF2-HMAC-SHA1 login derivation with 10,000 iterations.
- Legacy text AES-256-CBC/PKCS7 and OpenSSL-compatible EVP_BytesToKey/MD5
  derivation. These are compatibility constructions, not recommendations for
  a new password format.
- AES-256-GCM private-key wrapping with PBKDF2-HMAC-SHA512, 2,145 iterations.
- OpenPGP key generation through `dart_pg`, using an Ed25519 legacy signing key
  and Curve25519 ECDH subkey. The returned `kyber` fields in this SDK are null
  placeholders; they are not evidence of active post-quantum encryption.

**Unresolved provider-format risk:** `generateKeys(password)` encrypts a newly
generated OpenPGP private key using constant `appMagicIv` and `appMagicSalt`.
Repeated generation with the same password repeats the GCM key and nonce for
different plaintexts. The SDK comments identify these as protocol constants;
changing them silently in the application would risk interoperability. This
needs an upstream, versioned protocol correction with provider integration
tests. The current audit does not establish an exploit against the hosted
service, and does not treat the wrapper as safe merely because AES-GCM is a
standard primitive.

The app now supplies
[`InternxtSecureConfigStorage`](../lib/services/internxt_flutter/secure_config_storage.dart)
to every production configuration factory. This avoids the SDK's default
credential file wrapper, whose fallback encryption key is public, and uses
the existing native Keychain/Keystore or unlocked encrypted web store. Migration
reads old files/preferences only when no secure entry exists, verifies a secure
write before deleting the old copy, and retains a tombstone after logout so
failed cleanup cannot resurrect an obsolete session. The migration preserves
old ciphertext when its required environment key is unavailable. These changes
do not modify provider wire encryption or restore authenticated encryption to
the CTR file format.

## Other resolved crypto implementations

The reviewed application lockfile resolves `pointycastle` 4.0.0, `crypto` 3.0.7,
`cryptography` 2.9.0, `cryptography_flutter` 2.3.4, `bip39` 1.0.6,
`dartssh2` 4.1.0, `pinenacl` 0.6.0, `sign_dart` 1.0.0 and
`flutter_secure_storage` 9.2.4. Their exact hosted archive hashes and source
locations belong in each release's dependency evidence. Additional document,
archive, backup and vault code is covered by the main inventory; this provider
list is not the complete application crypto bill of materials.

The native OpenSSL probe is disabled on macOS in the vendored Filen fork;
Apple acceleration can use `cryptography_flutter`. Windows CNG and Linux
OpenSSL are desktop-specific backends. The application still bundles portable
crypto on App Store/Android paths. An assertion that the finished mobile app
uses *only* the operating system's encryption would not match this source.

The app's [SSH client factory](../packages/crisp_storage/lib/src/host_keys.dart)
uses the verified `dartssh2` archive's default `SSHAlgorithms` rather than
supplying a compatibility override. The offered key exchanges are Curve25519,
ECDH over NIST P-256/P-384/P-521, and SHA-256 Diffie-Hellman group exchange/group
14. Host signatures use Ed25519, RSA-SHA256/SHA512, and ECDSA over those NIST
curves. Offered ciphers are AES-256/128-GCM, OpenSSH ChaCha20-Poly1305 and
AES-256/128-CTR; separate MAC choices include HMAC-SHA256/SHA512 (with
encrypt-then-MAC preferred) and HMAC-SHA1. The actual negotiated suite depends
on the peer. Implemented legacy compatibility algorithms in the dependency
are not all enabled by these defaults. The application verifies server keys
before authentication through its endpoint-scoped known-hosts flow.

## Archive password compatibility

The archive viewer and editable workspace reach password cryptography in the
resolved `koni_archive` 0.9.0 family. These public package archives were
downloaded and their SHA-256 digests verified against `pubspec.lock`:

| Package | Exact published archive | SHA-256 |
| --- | --- | --- |
| `koni_archive` | [0.9.0](https://pub.dev/api/archives/koni_archive-0.9.0.tar.gz) | `fc63ef9271f6d5ab5f6e866b8fb41e63ffa35786f0c9cf201537f04cb8091335` |
| `koni_archive_core` | [0.9.0](https://pub.dev/api/archives/koni_archive_core-0.9.0.tar.gz) | `f323296866d6224725839e2b8ef25dfeba5e0c2476877fa7726f4b966a4c7a84` |
| `koni_codecs` | [0.9.0](https://pub.dev/api/archives/koni_codecs-0.9.0.tar.gz) | `0a0ffa23f62f627bc50db6de79e88a6a41e019d3a21c6a455ac5ae7c1677a8bd` |
| `koni_zip` | [0.9.0](https://pub.dev/api/archives/koni_zip-0.9.0.tar.gz) | `a0b234fd56678a2a277e0fc52987396a1ded52a04224de49bf5257ffca29700f` |
| `koni_sevenz` | [0.9.0](https://pub.dev/api/archives/koni_sevenz-0.9.0.tar.gz) | `058428e9328361849aea9f4b1f75803473248b33dbdc434ffbcc205c83c82d4b` |
| `koni_rar` | [0.9.0](https://pub.dev/api/archives/koni_rar-0.9.0.tar.gz) | `c8f1a5b2f1b9d8f6cfd981c67e8c34298f722806f7288f06faabb40004362f56` |
| `archive` | [4.6.0](https://pub.dev/api/archives/archive-4.6.0.tar.gz) | `de5ac590b8155e4e676088d714bd41ea620449a6adc0f7950c5073874b287ddb` |

Each listed Koni archive includes an MIT `LICENSE`, copyright 2026 the
`koni_archive` authors, and identifies
[zenbaku/koni_archive](https://github.com/zenbaku/koni_archive) as its repository.
The separate `archive` package includes an MIT `LICENSE`, copyright 2013–2021
Brendan Duncan, and identifies
[brendan-duncan/archive](https://github.com/brendan-duncan/archive). Preserve
those notices and use the exact archives above for release-source provenance.

[`archive_viewer_service.dart`](../lib/services/archive_viewer_service.dart)
passes the user's password through `ArchiveReadOptions` to
`koni.builtInFormats.openReader`, then reads members through the selected
reader. [`archive_service.dart`](../lib/services/archive_service.dart),
[`archive_viewer_file_io.dart`](../lib/services/archive_viewer_file_io.dart),
[`archive_workspace.dart`](../lib/services/archive_workspace.dart) and the
[archive workspace dialog](../lib/widgets/archive_workspace_dialog.dart)
connect that path to extraction, file viewing and editing. Workspace repacking
selects `ZipWriteFormat` or `SevenZWriteFormat`, retaining the password when the
archive is encrypted and enabling encrypted 7z headers. These are portable
Dart paths, including mobile, rather than desktop-only external utilities.

The source paths below are inside the corresponding exact package archives:

| Active format path | Algorithms and direction | Reviewed dependency source |
| --- | --- | --- |
| Traditional ZIP encryption | **ZipCrypto reading**: the published legacy PKWARE stream cipher with three 32-bit state words and CRC-32-based updates. It is a distinct cipher, not AES with ZIP framing. The writer does not emit ZipCrypto. | `koni_zip/lib/src/zip_reader.dart` (`_decryptedContent`, `_zipCryptoContent`), `lib/src/zip_crypto.dart` (`ZipCryptoCipher`). |
| WinZip AES ZIP | **Reading AES-128/192/256; writing AES-256 AE-2**. AES-CTR with the format's little-endian counter, PBKDF2-HMAC-SHA1 with 1,000 iterations, and a 10-byte truncated HMAC-SHA1 over ciphertext. | `koni_zip/lib/src/zip_crypto.dart`, `lib/src/zip_writer.dart`. |
| 7z encrypted data and headers | **Reading and writing AES-256-CBC**, with the published 7z SHA-256 KDF, not PBKDF2: one hash context absorbs salt, UTF-16LE password and a little-endian counter for `2^numCyclesPower` rounds. The writer uses power 19. | `koni_sevenz/lib/src/sevenz_crypto.dart`, `lib/src/sevenz_reader.dart`, `lib/src/sevenz_writer.dart`. |
| RAR3/4 encrypted data and headers | **Reading AES-128-CBC**, with the published format-specific SHA-1 password KDF, not PBKDF2: 262,144 rounds and intermediate digest bytes for the IV. | `koni_rar/lib/src/rar_crypto.dart` (`Rar4Keys`), `lib/src/rar_reader.dart`, `lib/src/rar4_container.dart`. |
| RAR5 encrypted data and headers | **Reading AES-256-CBC**, with an HMAC-SHA256 PBKDF2-style chain producing the AES key at `2^lg2Count` iterations and checksum/password-check material at subsequent milestones. | `koni_rar/lib/src/rar_crypto.dart` (`Rar5Keys`), `lib/src/rar_reader.dart`, `lib/src/rar5_container.dart`. |

`koni_rar`'s encrypted-entry dispatch accepts the salted RAR3/4 AES path and
RAR5 AES-256 records; older RAR1.x/2.x proprietary ciphers were not found in
this implementation. Its RAR2 decompressor is not an encryption algorithm.
The separate `archive` 4.6.0 source also contains traditional ZIP and AES code
in `lib/src/codecs/zip/zip_file.dart` and an AES writer in
`lib/src/codecs/zip_encoder.dart`; the direct application `ZipEncoder` calls
reviewed do not supply passwords. The password-capable viewer/workspace path
above is sufficient to establish active ZipCrypto and AES compatibility.

**Classification precision:** published legacy algorithms and internationally
standardized algorithms are different claims. The active ZipCrypto reader
precludes describing all archive encryption as AES, while the published 7z/RAR
KDFs and format framing should not be mistaken for undisclosed block ciphers.
This inventory records source and reachability; it does not itself determine
an Apple/BIS classification or an automatic CCATS requirement. Archive
compatibility is preserved. The resolved Koni API has no built-in legacy-cipher
allowlist or `allowZipCrypto` switch; any future policy change needs an explicit
implementation and interoperability review.

## Native SMB library

`dart_smb2` 0.2.1's `hook/build.dart` downloads **libsmb2-r9** from the public
[release](https://github.com/ales-drnz/dart_smb2/releases/tag/libsmb2-r9) and
verifies a fixed SHA-256 for each native artifact. The existing
[NOTICE-LIBSMB2.txt](../packages/crisp_storage/NOTICE-LIBSMB2.txt) identifies the
LGPL-2.1-or-later library and corresponding build-source commit.

- Build recipes: [ales-drnz/libsmb2-scripts at
  `f2695f24c0db8984cd0593738b72004ab48cfe1b`](https://github.com/ales-drnz/libsmb2-scripts/tree/f2695f24c0db8984cd0593738b72004ab48cfe1b).
- Those recipes pin [sahlberg/libsmb2 at
  `e94eee9465d55ed094ace2c038a8705b4822dada`](https://github.com/sahlberg/libsmb2/tree/e94eee9465d55ed094ace2c038a8705b4822dada).
- The source archive hash in `scripts/shared/_versions.sh` is
  `7f347c08c8cb66a94e42d1cac4686e71a093a7022e7e77cb5cc9325b8369b0ce`;
  the downloaded native source archive was checked against this digest.
- These recipes compile the public native source, excluding `krb5-wrapper.c`;
  they do not enable the GSSAPI/Kerberos wrapper. SMB signing and SMB3 encryption
  remain in scope. The app's
  [SMB session](../packages/crisp_storage/lib/src/smb_session.dart) requests
  signing and defaults to required encryption.

At that upstream commit, `lib/smb3-seal.c` implements AES-128-CCM sealing;
`lib/smb2-signing.c` selects AES-128-CMAC for SMB3 and HMAC-SHA256 for SMB2.
`lib/libsmb2.c` uses HMAC-SHA256 key derivation and SHA-512 preauthentication
hashes. `lib/ntlmssp.c` uses MD4 and HMAC-MD5 for NTLMv2 authentication. These
are additional application crypto, even on Apple: the conditional
`lib/aes_apple.c` backend accelerates the AES block through CommonCrypto, while
the library supplies the CCM/CMAC composition and protocol implementation.

The reviewed hook's store-platform artifact hashes are:

| Artifact | SHA-256 |
| --- | --- |
| Android arm64 | `d9af2446788f5eb298065312fcb21b11ebd7af83510bbfb0c09d8a6075bb2cf2` |
| Android armv7 | `54d3e5c85fe824f426da21028500a825d1ee4ae7dd46a2cfc8e74f2e4e603d36` |
| Android x86_64 | `e740406fb7e97c2b6aa1eb65864b348a9b720b07c1ff90b75e6e5be12beee205` |
| iOS XCFramework | `a1f0b15bf0f173165e36abcfcea3b944f469fc2c7e3bd2b6d3d16df7a6c38f63` |
| macOS XCFramework | `922defa3509e550d32d66d7e8f84ef95ddf53fb9bb96a8ff85e01537765129e6` |

The hook accepts `hooks.user_defines.dart_smb2.libsmb2` as a custom local library
override. That path bypasses the published artifact selection and its digest
checks. A release using an override needs separate source, build and artifact
evidence; the table above must not be claimed to cover it. The same caution
applies to any unrecorded native library replacement during packaging. A source
link and permissive availability are distinct from fulfilling each dependency's
license conditions.

**Conditional desktop hardening issue:** the pinned
[`smb2_random_bytes`](https://github.com/sahlberg/libsmb2/blob/e94eee9465d55ed094ace2c038a8705b4822dada/lib/init.c)
returns an error after falling back to `random()` when strong sources fail, but
[`smb3_encrypt_pdu`](https://github.com/sahlberg/libsmb2/blob/e94eee9465d55ed094ace2c038a8705b4822dada/lib/smb3-seal.c)
ignores that status when generating the 11-byte CCM nonce. The pinned build
[configuration](https://github.com/ales-drnz/libsmb2-scripts/blob/f2695f24c0db8984cd0593738b72004ab48cfe1b/scripts/shared/config/config.h)
uses `arc4random_buf` on Apple/Android and compiles out this fallback there.
Linux requires both `getrandom` and `/dev/urandom` to fail; the Windows
[CSPRNG patch](https://github.com/ales-drnz/libsmb2-scripts/blob/f2695f24c0db8984cd0593738b72004ab48cfe1b/patches/libsmb2/windows/patch_windows_csprng.py)
also permits fallback after BCrypt failure. CCM requires unique nonces per
key, so the concern is repetition risk from weak/resettable PRNG state, not
predictability alone. Propagate failure and stop encryption upstream. This
review did not demonstrate a remote trigger or run native fault-injection tests.

## Embedded iOS shell

The iOS shell introduced in main's PR #23 adds native source, including checksum
utilities, so it must be included in release provenance. It is not accurate to
inventory every target in its upstream monorepository as part of the app.

[`tool/sources.json`](../packages/crisp_ios_shell/tool/sources.json) pins:

| Input | Commit | Archive SHA-256 |
| --- | --- | --- |
| [holzschu/ios_system](https://github.com/holzschu/ios_system/tree/77e13cbd0f05e45c50d5f7cc8594eed1d00f574b) | `77e13cbd0f05e45c50d5f7cc8594eed1d00f574b` | `b5d60598688e0c61a4cec2760609a0f9571b464ca8743ff6dd87cb6ef22e3820` |
| [holzschu/dash_iOS](https://github.com/holzschu/dash_iOS/tree/c95f39a9ac177a8964b91cd7474e972884376b76) | `c95f39a9ac177a8964b91cd7474e972884376b76` | `4977c6b7fb3ff075fc93aec272059355f9bb4b7e46591a2ce0ee2b9b810c0500` |

The selected native targets are `ios_system`, `files`, `text`, `shell`, `awk`,
`tar`, and the six Dash interpreter variants. The command manifest includes
`md5` and checksum utilities; the selected `text` target compiles CommonCrypto
checksum helpers. The selected target framework phases do not link an OpenSSL
framework, and the old libarchive configuration used by `tar` leaves the
OpenSSL digest feature macros undefined. The upstream repository also contains
SSH and other network-tool targets that are not selected by this package.

The bundled [command manifest](../packages/crisp_ios_shell/ios/Resources/commands.plist)
has no `ssh`, `sshd`, `curl` or `openssl` command.
[`CISShellSession`](../packages/crisp_ios_shell/ios/Classes/CISShellSession.m)
sets `sideLoading = false`, loads its immutable manifest from the app bundle,
and validates framework paths against the signed app's Frameworks directory.
The Flutter bridge exposes shell-session input/output and lifecycle methods,
not an interface for selecting cryptographic providers or uploading native
algorithms. Shell scripts can compose the bundled commands; that fact alone
does not establish a cryptographic customization interface.

The package [UPSTREAM.md](../packages/crisp_ios_shell/UPSTREAM.md) documents its
mixed native licensing, including Dash's GPL-2.0-or-later portion, and local
patches. Preparation verifies source digests and generates
`ios/Resources/BuildProvenance.json` with build inputs and artifact hashes.
Preserve that generated file with the release's source and binary evidence, and
run the package's packaging check against the actual `.app`. This source review
does not substitute for those Xcode/native checks.

## Application interfaces reviewed

[`PluginContext`](../lib/services/plugin_service.dart) exposes settings,
temporary-directory access and logging. The reviewed production registration
surface does not supply keys, crypto-provider objects or runtime algorithm
loading. Compiled Dart callback types and editable open-source classes are not,
by themselves, evidence of a shipped interface for replacing cryptography.
[`LocalApiService`](../lib/services/local_api_service.dart) declares application
status, provider, file, sync and transfer routes, with no route to upload an
algorithm, replace a cipher or export a cryptographic development API. Several
file operations are placeholders rather than a cryptographic toolkit.

These are call-graph observations for the reviewed source, not a legal ruling
about an "open cryptographic interface." Reassess when adding executable
plugins, algorithm selection, new native commands or new key-management APIs.
