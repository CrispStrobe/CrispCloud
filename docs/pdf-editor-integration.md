# PDF editor integration plan

Status: compatibility planning; the PDF editor is not integrated yet.

The target editor is a Flutter 3.47+ package. These are the integration gates
that must be resolved before adding it to CrispCloud.

## 1. One toolchain everywhere

Target: **Flutter 3.47.8 / Dart 3.13.7**, pinned in `.fvmrc`.

The following must all use the same version:

- `.fvmrc`
- `CLAUDE.md` and `README.md`
- `pubspec.yaml` (`sdk` and `flutter` floors)
- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`
- `.github/workflows/nightly.yml`
- `.github/workflows/deploy-web.yml`
- `.github/workflows/deploy-pages.yml`
- Firebase App Distribution, Google Play, iOS and macOS release jobs

Do not validate the PDF integration only on a developer machine. A local pass
against a different Flutter version does not establish that the shipped builds
resolve and run.

## 2. Secure storage is a compatibility decision, not a version bump

CrispCloud currently declares:

```yaml
flutter_secure_storage: ^9.2.4
```

The current PDF editor declares:

```yaml
flutter_secure_storage: ^11.2.0
```

There is no constraint overlap. Do **not** blindly upgrade or override the
application dependency: the storage package's 11.0 changelog says data using
removed legacy features can become unusable, and applications on pre-10
versions must migrate through version 10 first.

Preferred route:

1. Fork the editor and make its concrete secure-storage implementations
   optional around `PdfIdentityStore` and `PdfFormSecretStore`.
2. Let CrispCloud supply its existing `SecureStorageService` implementation.
3. Keep editor persistence separate from the application credential migration.
4. Validate reads of existing identities/secrets on upgrade, not just fresh
   installs.

Fallback route:

- Perform a separately tested application-wide credential migration from
  secure storage 9 → 10 → 11, including users who skip intermediate releases.

Hiding signature UI or supplying an in-memory store does not remove the
declared Pub dependency.

## 3. Web must be verified on the exact package version

The editor project supports web, but its current pub.dev analysis flags web as
incompatible because an import chain reaches `dart:isolate`; the upstream demo
web deployment is evidence that the project can build for web, not proof that
our dependency graph and hosting configuration work.

Verify with CrispCloud's actual release build:

- open, edit and save DOCX/PDF-derived documents;
- fonts and form fields;
- worker and WASM asset loading;
- dynamic chunks, CSP and hosting headers;
- offline reload / cache behavior;
- the exact package version we would ship.

## 4. Keep the Material boundary at the editor edge

The current editor uses `material_ui` and `cupertino_ui` and includes a bridge
for hosts still using `MaterialApp`. Colors, typography, icon themes and some
other theme values carry over; legacy component themes and `ThemeExtension`s do
not.

CrispCloud should keep its existing application UI and style the editor through
its own theme configuration. A whole-application UI migration is not required
to embed the editor.

## 5. Integration gates

1. Toolchain CI is green on Linux, macOS and Windows.
2. Secure-storage dependency is resolved without forcing an untested credential
   migration.
3. Web build and runtime pass on the exact version.
4. macOS and iOS builds open, edit and save local documents through
   CrispCloud's authorized file access.
5. App Store-compatible, offline, self-contained assets.
6. The Material boundary is limited to the editor surface.

Only after these gates should the PDF editor become a product dependency.
