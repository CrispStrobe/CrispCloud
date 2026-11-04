# Optional PDF editor secure stores

This local Apache-2.0 companion preserves `SecureIdentityStore` and
`SecureFormSecretStore` from `dart_pdf_editor` 14.0.0. Hosts that want persistent
signing identities or password form values can opt in explicitly. CrispCloud's
PDF editor uses the core package's in-memory form store and does not depend on
this companion.

The adapter uses `flutter_secure_storage ^9.2.4`, matching CrispCloud's existing
credential-storage plugin. It makes no changes to the host's credentials and
uses the upstream `pdf_signing_identity.` and `pdf_form_secret.` namespaces.
Applications can also provide a configured `FlutterSecureStorage` instance or
their own key prefixes.

```yaml
dependencies:
  dart_pdf_editor_secure_storage:
    path: packages/dart_pdf_editor_secure_storage
```

```dart
import 'package:dart_pdf_editor_secure_storage/dart_pdf_editor_secure_storage.dart';

final identities = SecureIdentityStore();
final formSecrets = SecureFormSecretStore();
```

Pass these stores to the matching editor/controller APIs explicitly. Use
`InMemoryFormSecretStore` from the core package when secrets should last only
for the editing session, including the web application. A saved PDF should
never need to contain the clear-text value of a password form field.

See [UPSTREAM.md](UPSTREAM.md) for provenance and [LICENSE](LICENSE) for the
unmodified upstream license. Run `flutter pub get`, `flutter analyze`, and
`flutter test` in this directory to check the adapter against the supported
plugin major version.
