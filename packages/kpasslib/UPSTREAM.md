# KPassLib provenance and CrispCloud changes

- Upstream: <https://github.com/vladimir-skorokhodov/kpasslib>
- Version: 1.1.2
- Pinned commit: `81d51d9f3575f72136441ea5a271f6748e3ca77c`
- License: MIT; the upstream notice is preserved in `LICENSE`.
- Imported scope: Dart runtime, package manifest, README, changelog, and license.
  No native shared libraries or build scripts are bundled.

The upstream implementation is a Dart port of the MIT-licensed KdbxWeb library.
The existing runtime dependencies are permissive: archive (MIT), collection,
convert, crypto, ffi, xml, and PointyCastle (BSD-style licenses).

## Local adaptations

The default Argon2 implementation delegates to the application's existing
PointyCastle 4 implementation. PointyCastle selects its portable register-based
implementation for JavaScript and its native integer implementation on native
Dart. This avoids the upstream implementation's native-only 64-bit arithmetic.

Further format hardening and the lossless raw-document editing API are being
implemented in this branch. Their final scope and verification will be recorded
here before the KeePass feature is enabled.
