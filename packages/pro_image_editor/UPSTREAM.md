# CrispCloud's pro_image_editor fork

## Provenance

- Upstream: <https://github.com/hm21/pro_image_editor>.
- Published package: `pro_image_editor` **14.24.0**.
- Archive: <https://pub.dev/api/archives/pro_image_editor-14.24.0.tar.gz>.
- Archive SHA-256: `de1d0a5eaee1f80871b09a6ea03c2341cb86f00b590181f14ab4d6485ab978bb`.
- Corresponding upstream commit:
  `548591a6854691a8c31cbfb5637794e9bc6ded34` (4 November 2026).
- License: BSD-3-Clause. The original `LICENSE` and the third-party `NOTICES`
  are retained without modification.

This is an in-repository maintained fork, following CrispCloud's Quds Office
and PDF editor package layout. The application resolves this source through a
local path so its fixes and the application integration can be reviewed and
versioned together. There is no dependency on a moving upstream branch.

## Imported files

The verified published archive supplies all of `lib/`, including its bundled
third-party sources, shaders, and compiled browser workers; the icon font in
`assets/fonts/`; the Android plugin sources and Gradle files; the shared Darwin
plugin, podspec and Swift package; `test/`; and `LICENSE`, `NOTICES`, `README.md`,
`CHANGELOG.md`, `pubspec.yaml`, and `analysis_options.yaml`.

The archive includes the upstream Flutter regression tests (136 files including
fixtures and generated mocks), so they do not need to be reconstructed from a
different revision. Examples, showcase images, generated example plugin
registrants, and contributor tooling are omitted. The retained runtime and
upstream tests comprise 822 files before local changes.

## Local changes

| File | Change |
| --- | --- |
| `pubspec.yaml` | Set `publish_to: none` and remove metadata for omitted showcase images. |
| `lib/features/main_editor/main_editor.dart` | Route capture and Escape through the nested navigator; prevent repeated close calls from popping the host; include blur in `closeSubEditor`. |
| `lib/core/mixins/standalone_editor.dart` | Close embedded sub-editor routes without invoking the main host's close callback. |
| `lib/core/services/keyboard_service.dart` | Recognize both physical Command keys with Flutter's `isMetaPressed` modifier state. |
| `lib/core/models/i18n/i18n_text_editor.dart` | Expose the overflow Cancel label and the font-style sample text. |
| `lib/shared/widgets/platform/platform_popup_menu.dart` | Accept a translated Cancel label, with a localized Cupertino fallback. |
| `lib/features/paint_editor/widgets/paint_editor_appbar.dart` | Supply the configured paint-editor Cancel label. |
| `lib/features/text_editor/widgets/text_editor_appbar.dart` | Supply the configured text-editor Cancel label. |
| `lib/features/text_editor/widgets/text_editor_bottom_bar.dart` | Use the configured script sample in font-style buttons. |
| `README.md`, `CHANGELOG.md` | Identify the maintained copy and document the changes above. |

`UPSTREAM.patch` records changes to the imported files. New tests in
`test/crispcloud/` cover nested cancellation, Escape, capture without losing the
host route, apply/undo/redo, Command-key recognition, and translated overflow
and font-style controls. The application owns its editor menus, save workflow,
file-format checks, and translations; they do not belong in upstream defaults.

Capture retains upstream's behavior of discarding a pending sub-editor's
unapplied changes. A host should finish applying the active tool, or disable
Save until the user applies or cancels it, before capturing the main image.

## Reproduce and validate

Download the archive above and verify its SHA-256 before extraction. Copy the
listed files and directories, then reapply the changes documented in this
file. Preserve all license notices, the generated web workers, both shader
assets, the icon font, and the native plugin metadata on upgrades.

Use the application's Flutter toolchain (Flutter 3.47.8 / Dart 3.13.7):

```sh
cd packages/pro_image_editor
flutter pub get
flutter analyze
flutter test test/crispcloud
flutter test
```

Package-local lockfiles and generated `.dart_tool/` or `build/` directories are
not committed. The application's root lockfile records the shipped dependency
resolution. Run CrispCloud's image edit session, widget, and live integration
tests in addition to the focused package regressions whenever this fork changes.

The runtime patch uses paths relative to the upstream package. From the
CrispCloud repository root, apply it with:

```sh
git apply --directory=packages/pro_image_editor \
  packages/pro_image_editor/UPSTREAM.patch
```

The new provenance document and local tests are maintained separately from
that patch. No browser-worker code is changed, so the shipped workers remain
byte-identical to the verified archive.
