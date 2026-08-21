Vendored from `filen_client` 0.2.2.

CrispCloud disables OpenSSL probing on macOS because a signed App Store or
TestFlight sandbox aborts when Dart attempts to load Homebrew's libcrypto from
outside the application bundle. The package falls back to
`package:cryptography`, which CrispCloud configures to use Apple CryptoKit.
