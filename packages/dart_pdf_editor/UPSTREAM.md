# Vendored dart_pdf_editor

## Source and license

This is the runtime package from
[ben-milanko/dart-pdf](https://github.com/ben-milanko/dart-pdf), licensed under
Apache-2.0. The unmodified upstream license is in [LICENSE](LICENSE).

- Package: `dart_pdf_editor`, version `14.0.0`.
- Release tag: `dart_pdf_editor-v14.0.0`.
- Source commit: `87adaa022c5ed6b22ca3232b6cae4a03e8389e98`.
- Tag object: `900dc64c4cc1a1dac071593097a885008dabe12a`.
- Import path: `packages/dart_pdf_editor` in the upstream monorepo.

Copied from that commit: all 230 files in `lib/` (including generated
localizations and their ARB sources), all three shaders, and `LICENSE`,
`README.md`, `CHANGELOG.md`, `pubspec.yaml`, `l10n.yaml`, and
`analysis_options.yaml`. The upstream examples, binary fixtures, performance
corpora, and monorepo development tools are intentionally outside this copy.
The core `pdf_cos`, `pdf_document`, and `pdf_graphics` packages resolve from
pub.dev at exact version 14.0.0.

## Why this local patch exists

Upstream 14.0.0 depends on `flutter_secure_storage ^11.2.0` solely for two
optional store implementations. CrispCloud already uses
`flutter_secure_storage ^9.2.4` for account credentials. A dependency override
would falsely claim compatibility with the upstream constraint and could
change credential storage behavior during an unrelated PDF integration.

The editor therefore retains the `PdfIdentityStore` and `PdfFormSecretStore`
interfaces and their in-memory implementations without depending on a
platform storage plugin. The optional sibling package
[`dart_pdf_editor_secure_storage`](../dart_pdf_editor_secure_storage/README.md)
preserves the original secure-store classes and uses version 9.2.4 of the
host plugin. CrispCloud's PDF screen only needs the core package and supplies
`InMemoryFormSecretStore` explicitly. This keeps password form values out of
saved PDF bytes while retaining them for the lifetime of the editor session.
The upstream controller's optional-store default is unchanged; other hosts
must also opt in to a store if they want values withheld from PDFs.

## Patch inventory

[UPSTREAM.patch](UPSTREAM.patch) captures every change to imported files and
the new worker files, relative to the pinned upstream commit. Files that were
modified contain a local change notice or an entry here.

| Path | Local change |
| --- | --- |
| `pubspec.yaml` | Remove workspace resolution; set `publish_to: none`; remove the mandatory secure-storage plugin; pin the three PDF core dependencies to 14.0.0; keep only the dev dependencies needed by local tests. |
| `lib/src/editing/signing_identity_store.dart` | Retain interface and memory implementation; move the concrete secure store and its imports to the sibling package. |
| `lib/src/editing/form_secret_store.dart` | Retain interface, document-key helper, and memory implementation; move the concrete secure store and its imports to the sibling package. |
| `lib/src/retained_scene.dart` | Replace direct `dart:isolate` use with conditional worker dispatch and decline optional retries on unsupported platforms. |
| `lib/src/overprint_rerecord_worker.dart` | Select native dispatch only when `dart.library.io` is available. |
| `lib/src/overprint_rerecord_worker_native.dart` | Preserve the upstream transferable-byte handoff, pure Dart rendering, populated-range handling, image decoding ratio, and result serialization. |
| `lib/src/overprint_rerecord_worker_stub.dart` | Report unsupported and return `null` for optional retries on the browser. |
| `README.md`, `CHANGELOG.md` | Identify this copy and describe local changes above the retained upstream documentation. |

The web change affects only the optional denser overprint re-recording path
requested by a tile backend. Normal page rendering, annotation rendering, and
the existing web render worker are unchanged. No synchronous replacement for
an expensive native isolate task is introduced on the browser UI thread.

New CrispCloud-maintained files outside the upstream patch are this provenance
document and focused tests in `test/`. The tiny PDF fixtures are generated in
test code; the upstream workspace is not needed to run them.
The optional adapter has its own provenance document and tests.

## Reproduce the imported runtime

From a temporary directory, fetch the pinned upstream source. The following
commands reconstruct just the imported files and then apply this patch.
`CRISPCLOUD_CHECKOUT` must be an absolute path to this repository checkout.

```sh
git clone https://github.com/ben-milanko/dart-pdf.git upstream
git -C upstream checkout --detach 87adaa022c5ed6b22ca3232b6cae4a03e8389e98
mkdir rebuilt
git -C upstream archive HEAD \
  packages/dart_pdf_editor/lib \
  packages/dart_pdf_editor/shaders \
  packages/dart_pdf_editor/LICENSE \
  packages/dart_pdf_editor/README.md \
  packages/dart_pdf_editor/CHANGELOG.md \
  packages/dart_pdf_editor/pubspec.yaml \
  packages/dart_pdf_editor/l10n.yaml \
  packages/dart_pdf_editor/analysis_options.yaml | tar -x -C rebuilt
cd rebuilt
git apply "$CRISPCLOUD_CHECKOUT/packages/dart_pdf_editor/UPSTREAM.patch"
```

The reconstruction omits this document, the patch file itself, and local
tests. Compare its `lib/`, `shaders/`, and copied metadata with this directory
when auditing the vendor import. The companion store source consists of the
two extracted classes, unchanged apart from imports and documentation links.

## Validation and upgrades

Use Flutter 3.47.8 / Dart 3.13.7 (the root project toolchain). Standalone checks
from this directory:

```sh
flutter pub get
flutter analyze
flutter test
```

Run the sibling adapter's tests separately with its own `flutter pub get` and
`flutter test`; its `flutter_secure_storage` dependency must resolve to 9.x.
The app's root lockfile is the dependency record for the shipped application.
Do not commit package-local lockfiles or generated `.dart_tool`/build folders.

The core tests cover session/document isolation, keeping password-field values
out of saved PDFs, identity round trips without a platform plugin, the browser
worker fallback, and native re-recording of a retained scene. The adapter tests
exercise the plugin's official mock storage and verify that deletion preserves
unrelated host credentials. They do not replace device-level Keychain/Keystore
testing, whole-editor visual testing, or the upstream rendering corpus.

For an upstream upgrade, review that release's migration notes, import its
runtime package, rebase the documented patch, update core package pins and
the optional editor-assets dependency together, and run both package suites
plus CrispCloud's PDF integration tests and web build. Preserve existing
credential-storage behavior unless a separate migration is deliberately
implemented. Format local edits with `dart format --language-version=3.5` to
match this upstream version without rewriting all of its sources.
