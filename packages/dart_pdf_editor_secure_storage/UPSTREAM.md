# Secure-store extraction provenance

The two classes in `lib/src/` come from Apache-2.0
[`ben-milanko/dart-pdf`](https://github.com/ben-milanko/dart-pdf), release
`dart_pdf_editor-v14.0.0`, commit
`87adaa022c5ed6b22ca3232b6cae4a03e8389e98`.

- `SecureIdentityStore` was extracted from
  `packages/dart_pdf_editor/lib/src/editing/signing_identity_store.dart`.
- `SecureFormSecretStore` was extracted from
  `packages/dart_pdf_editor/lib/src/editing/form_secret_store.dart`.

The method implementations, key prefixes, index format, JSON/PEM encoding, and
constructor defaults are preserved. Imports now obtain interfaces from the
sibling `dart_pdf_editor` package, and one documentation reference is plain
code because its target is in another library. The original Apache-2.0 license
is retained in `LICENSE`. This is a local package with `publish_to: none`.

Its plugin constraint is `flutter_secure_storage ^9.2.4`, matching the host
application. Core editor use has no dependency on this adapter or the plugin.
This separation avoids silently forcing an account-credential plugin upgrade
when adding a PDF editor. No credential migration is performed.

Tests use the plugin's official mock initial values and cover both stores'
round trips and deletion boundaries. Device/platform protection still depends
on the host's plugin configuration. Use the core memory stores when persistent
secrets are unnecessary, particularly in a browser.
