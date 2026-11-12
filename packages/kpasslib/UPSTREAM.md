# KPassLib provenance and CrispCloud changes

- Upstream: <https://github.com/vladimir-skorokhodov/kpasslib>
- Version: 1.1.2
- Pinned commit: `81d51d9f3575f72136441ea5a271f6748e3ca77c`
- License: MIT; the upstream notice is preserved in `LICENSE`.
- Imported scope: Dart runtime, package manifest, README, changelog, and license.
  No native shared libraries or build scripts are bundled.

The upstream implementation identifies itself as a Dart port of the MIT-licensed
[KdbxWeb library](https://github.com/keeweb/kdbxweb). Its additional copyright
notice is retained in `LICENSE.kdbxweb` and appended to the main `LICENSE` for
Flutter's dependency license collection (upstream license blob
`9615fea17af6996b1dcada8c59005d787e204d3d`).

Runtime dependencies are permissive: archive and xml use MIT licenses;
collection, convert, crypto, and ffi use Dart's BSD 3-Clause license.
PointyCastle's distributed license is the Bouncy Castle MIT-style permission
grant. These notices are included by Flutter's normal dependency license
collection. The application already used these dependencies before this feature.

## Local adaptations

The default Argon2 implementation delegates to the application's existing
PointyCastle 4 implementation. PointyCastle selects its portable register-based
implementation for JavaScript and its native integer implementation on native
Dart. This avoids the upstream implementation's native-only 64-bit arithmetic.

The remaining local changes are format, portability, and lifecycle adapters:

- The FFI export is conditional on `dart.library.ffi`; no native library is
  loaded. AES KDF work uses native isolates or cooperative browser chunks.
- The byte reader rejects truncated fields. Portable 64-bit encoding uses
  32-bit halves, retaining the all-ones header-HMAC index through an explicit
  `-1` sentinel. Integers outside JavaScript's exact integer range are rejected.
- Header parsing rejects unknown, duplicate, or malformed fields; it preserves
  the optional outer comment and public custom data. Variant dictionaries reject
  duplicate keys, missing terminators, and trailing data.
- KDBX4 validates the final zero-length HMAC block as well as data blocks.
  KDBX3 verifies block sequence, the final zero hash, and its encrypted header
  hash. Both reject trailing bytes and excessive block counts.
- Gzip expansion is bounded and checked. XML has event-count and depth limits;
  document-type declarations are rejected. Saves apply the same XML limits so
  the application cannot emit a database that its own reader refuses to reopen.
- Inner binary references remain positional, including identical payloads.
  The protection flag uses the specified low bit instead of the upstream
  inverted test. Their count is capped before allocation or writing; otherwise
  a small compressed file could expand into millions of empty binary objects.
- `KdbxRawDocument` retains the full XML tree, including unknown nodes,
  attributes, custom fields, history, and plugin metadata. It uses the upstream
  KDBX encryption envelope while avoiding the object-model serializer, which
  drops fields it does not recognize. Protected leaf values are kept separately
  in memory and re-encrypted in document order. Unsupported structured protected
  values are rejected before editing.
- Protected values and credential components have explicit best-effort disposal;
  mutable buffers are zeroed before release. Dart cannot guarantee erasure of
  immutable strings or garbage-collected copies. The service does not write
  plaintext, keys, backups, or logs.

The standard save path retains the database version, cipher, KDF, and KDF costs;
fresh seeds, stream keys, salts, and IVs come from the upstream `Random.secure`
implementation. The application validates KDF budgets before invoking it.
No cryptographic primitive is authored in these adaptations.

On 2026-11-12 the vendored Dart files were formatted with the repository's Dart
3.13.7 toolchain to satisfy the existing whole-PR formatting gate. This changes
layout only; upstream copyright/license notices and algorithm behavior remain
intact. The source evidence fingerprint includes these exact formatted bytes.

## Verification

`test/keepass_service_test.dart` uses public KeePass-authored interoperability
fixtures with provenance in `test/fixtures/keepass/README.md`. It covers KDBX3,
KDBX4 and KDBX4.1, password/key-file combinations, XML v1/v2 keys, raw and hex
keys, wrong credentials, KDF limits, terminal integrity checks, fresh encryption,
custom metadata, unknown protected values, history, positional binaries and
session disposal. Tests also read edited output through the independent upstream
object-model reader.

`tool/verify_keepass_database.dart` deliberately imports neither Flutter nor
`dart:io`. Its public fixtures exercise open/edit/save/reopen on both the Dart VM
and compiled JavaScript: AES-KDF/AES, Argon2id/AES, and Argon2d/ChaCha20. It checks
Unicode passwords, unknown protected values, history, and fresh salts. Argon2
known-answer tests are separate from these full-database round trips.

The app-facing supported subset and concrete resource budgets are documented in
`docs/keepass.md`. Hardware challenge-response providers, Windows account keys,
changing the master key and direct attachment editing are outside that subset.
Group management, protected custom fields and complete entry-history restoration
are implemented by the app service using the retained raw XML; the upstream
object-model writer is not substituted for that preservation path.
Unsupported features are never silently converted or
discarded to make a file writable.
