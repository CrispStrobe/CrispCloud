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
| `pubspec.yaml` | Set `publish_to: none`, remove metadata for omitted showcase images, and declare `intl` for visible and spoken numeric formatting. |
| `lib/features/main_editor/main_editor.dart` | Keep capture, Escape, and repeated closes inside the nested navigator; include blur in `closeSubEditor`; delegate host navigation; record effective wheel edits on copied layers; localize paint-property popup routes. |
| `lib/core/models/editor_configs/main_editor_configs.dart`, `lib/shared/widgets/extended/extended_pop_scope.dart` | Add opt-in `hostOwnsNavigation` without registering an engine pop handler on the host route. |
| `lib/core/mixins/standalone_editor.dart`, paint/filter/blur/tune editor entrypoints | Return awaitable completion futures, reject overlapping Apply calls, propagate capture/write errors, restore retry after failure, and keep embedded Cancel inside its own route. |
| `lib/features/main_editor/services/desktop_interaction_manager.dart` | Report effective wheel transforms without mutating prior history; ignore no-op and canvas-zoom events. |
| `lib/core/models/custom_widgets/layer_interaction_widgets.dart`, layer widget/context-menu service | Expose an optional typed host context-menu builder; preserve enabled actions, dismiss/error cleanup, and the upstream fallback. |
| `lib/shared/widgets/overlays/editor_bottom_sheet.dart` | Preserve the scoped editor localizations around the complete popup route, including its sheet chrome, while retaining host navigator ownership. |
| Image converter/render service and recorder controller | Preserve transparent image borders and source resolution when capturing image bounds; retain explicit drawing/layer crop overrides. The worker receives the corrected crop flag before conversion. |
| `lib/shared/services/content_recorder/utils/web_worker_utils.dart` | Send exactly the offset/length of a Uint8List view, avoiding unused encoder-buffer capacity in PNG/JPEG responses. The compiled worker and map are regenerated separately. |
| Browser worker manager/thread and shared task manager | Reject pending work on script, execution, or message errors so the existing main-thread encoder can recover; clean failed tasks, count each task once, and inspect existing workers without creating leaked probes. The manager accepts an optional script URL while retaining the published default. |
| `lib/core/services/keyboard_service.dart` and crop/paint desktop managers | Recognize both physical Command keys; read live Control/Meta/Shift state so a host-blocked key press or release cannot leave stale shortcut modifiers after an overlay closes. |
| `lib/core/models/i18n/i18n_text_editor.dart` | Expose overflow Cancel, font-style sample, and font-size Reset labels. |
| `lib/shared/widgets/platform/platform_popup_menu.dart` and paint/text appbars | Supply translated overflow Cancel labels, with a localized Cupertino fallback. |
| Text bottom bar and text editor | Use the configured script sample and Reset label. |
| `lib/shared/utils/format_editor_number.dart`, slider sheet, bottom-sheet header, paint-property editor, and tune bottom bar | Format decimal/scale values and slider semantics for the active locale; localize Reset and Close tooltips. |
| `README.md`, `CHANGELOG.md` | Identify this maintained copy and document the changes above. |

`UPSTREAM.patch` records changes to imported source files and the two new
runtime helpers required by them. Generated worker JavaScript and its source
map are committed at their normal paths rather than duplicated in the patch;
they must be regenerated using the command below after applying source changes. New tests in `test/crispcloud/` cover nested
cancellation, Escape, capture without losing the host route, repeated Apply,
awaited completion failure and retry, apply/undo/redo, wheel history and
branching, host navigation and menu contracts, scoped popup localization,
Command-key recognition, live modifiers across host-blocked key events,
translated overflow/font controls, and localized
visible and spoken numbers, transparent image-border preservation, intentional
drawing-only trimming, and the request passed to a worker. Browser-only
regressions use real workers to verify recovery from script execution errors,
malformed responses, and a missing worker asset without leaving Save pending.
Direct browser regressions also check byte-view offset/length preservation
and successful PNG and JPEG encodes in the production worker, including exact
IEND/EOI boundaries, with no fallback or leaked active tasks.

The application owns its editor menus, save workflow, file-format checks,
and translations; they do not belong in upstream defaults. Its real-renderer
widget suite additionally captures PNG/JPEG edits, preserves PNG alpha and
resolution beyond the upstream 2000-pixel default, saves twice, reopens saved
bytes, exercises keyboard commands and nested tools, and checks failed and
pending writes. A browser-only case uses the production worker path.

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
flutter test --platform chrome test/crispcloud/web_worker_failure_test.dart
flutter test
```

Package-local lockfiles and generated `.dart_tool/` or `build/` directories are
not committed. The application's root lockfile records the shipped dependency
resolution. Run CrispCloud's image edit session, widget, and live integration
tests in addition to the focused package regressions whenever this fork
changes. The browser widget harness serves a byte-for-byte copy of the
committed worker at its normal relative asset URL because Flutter's
browser test server does not serve a production `build/web/assets` tree.

The source patch uses paths relative to the upstream package. From the
CrispCloud repository root, apply it with:

```sh
git apply --directory=packages/pro_image_editor \
  packages/pro_image_editor/UPSTREAM.patch
```

The new provenance document and local tests are maintained separately from
that source patch. The new runtime helpers are included. Rebuild the worker
before using the patched package; source and generated assets must ship
together.

## Regenerate the browser worker

Use Flutter **3.47.8** / Dart **3.13.7** and the application's checked-in root
`pubspec.lock`, without upgrading dependencies. Run the first command from the
CrispCloud repository root. The explicit package configuration prevents the
standalone package's development dependency resolution from changing the
shipped worker.

```sh
flutter pub get
python3 tool/build_image_editor_worker.py --check
```

The wrapper rebuilds both outputs with the root package configuration and fails
if they differ from their committed bytes. It runs this compiler command from
`packages/pro_image_editor`:

```sh
dart compile js --packages=../../.dart_tool/package_config.json \
  -o lib/web/web_worker.dart.js lib/web/web_worker.dart
```

For intentional worker changes, run the wrapper with `--emit-review` instead
of `--check`, review and commit both generated outputs, and update the hashes
below. CI verifies reproducibility before browser tests. The main-thread
byte-view helper and the bundled worker must pass the same subview and strict
PNG/JPEG boundary regressions.

These outputs were regenerated by [CI run 41995733980](https://github.com/CrispStrobe/CrispCloud/actions/runs/41995733980)
from source commit `159229b4ea1bab4d6ded65729d4a484a639e568f` and imported from
artifact `13399568292`.

| Committed generated output | SHA-256 |
| --- | --- |
| `lib/web/web_worker.dart.js` | `4c4babba03f5bd2a26e1e90d6933230e493ba3a00dbeeb8a6dc86ecacdb22682` |
| `lib/web/web_worker.dart.js.map` | `818430180e560a78406c486fad251f70dabc6aa571374abc92bd15950eb8ddda` |
