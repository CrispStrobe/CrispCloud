# CrispCloud image editor integration

Feature branch: `feature/f4-pro-image-editor`.

## Ownership and maintenance

CrispCloud owns F4 routing, native menus, the toolbar, keyboard commands,
localization, file identity, permissions, persistence, and save confirmation.
The pinned `pro_image_editor` fork under `packages/` owns image operations and
rendering. Its upstream version, license, source checksum, and local patches
are recorded in the package's `UPSTREAM.md`.

## Save contract

- Initial overwrite support is deliberately limited to static PNG and JPEG.
  Validate the bytes against the filename before opening; do not interpret
  unsupported binary files as text.
- Preserve the input encoding and image resolution. Do not inherit the
  editor's JPEG / 2000-pixel export defaults.
- Reject animated images, invalid images, extension/signature mismatches,
  and inputs beyond explicit byte/dimension/pixel budgets.
- Capture the originating file and storage account when opening. Verify
  the original before overwriting and invalidate stale preview caches.
- A session becomes clean only after persistence of its captured revision.
  Failed writes and browser downloads leave the original unsaved.
- Block overlapping save/export requests and edits during image capture.
  Undo followed by a new edit must not reuse the saved revision identity.
- Existing generic storage adapters do not provide conditional writes. Their
  fresh-content conflict checks reduce conflicts but cannot make the
  check/write interval atomic.

## Localization and host UI

All newly introduced visible text, tooltips, semantic labels, native menus,
dialogs, progress labels, and editor-provided tool strings must have explicit
translations for every CrispCloud locale: en, de, fr, es, pt, zh, ja, ko, ar.
Avoid raw provider exceptions in visible error messages. Arabic retains RTL
layout. Material UI's separate localization/theme scope must match the host.

## Verification gates

1. Format and input validation, immutable revisions, failed/concurrent saves,
   undo/redo save points, and truthful browser save outcomes.
2. Real local-file edits and independent image decoding of saved outputs;
   outside modifications and account switches must reject overwrites.
3. F4 routing, native-menu dispatch/enablement, host toolbar, shortcuts,
   save/discard/cancel, and failed-save retention.
4. Real editor load/edit/export/reopen on the Flutter test runtime and browser.
5. Localization key coverage and upstream string coverage, including tools
   and accessibility text; package regression tests for local fork changes.

Push small, reviewable checkpoints throughout implementation. Validation
results and any environment limitations are recorded here before completion.

## Implemented integration

`showFileEditorDialog` dispatches `.png`, `.jpg`, and `.jpeg` to
`ImageEditorDialog`. The same capability predicate enables the viewer's Edit
button and the context-menu action. Unknown binary formats cannot fall through
to the text editor. PNG animation chunks and JPEG multi-picture/trailing data
are rejected after reading, even if the extension looks editable.

The host toolbar and macOS File/Edit/Image menus share
`ImageEditorMenuActions`. They expose Save, Close, Undo/Redo, Crop and rotate,
Draw, Text, Adjust, Filters, and Blur. Subeditors stay within the image surface;
the host offers Apply and Cancel, and disables main-image commands until the
tool closes. Ctrl/Cmd+S saves; Ctrl/Cmd+Z and redo shortcuts act on the main
image when no tool owns input. Escape closes a tool first, then uses the host's
Save/Discard/Cancel prompt. Native commands are disabled behind popup routes
and throughout capture/persistence.

`ImageEditorSurface` adapts the engine to CrispCloud's colors and locale. It
uses the host's own Flutter Material layer context menu. The maintained engine
has explicit host-owned navigation so a system Back event cannot open two
unsaved-change prompts. Root-level engine sheets preserve their localization
scope when presented on the host navigator.

### Persistence and image limits

`ImageEditSession` tracks weak, immutable history tokens rather than indexes.
Undo/redo can return to a saved revision; a new branch at a reused index stays
dirty. Layer gestures and mouse-wheel edits create observable revisions.
The UI blocks edits while exporting, and the session rejects a capture whose
revision changed before it completed.

`ImageFileStore` shares the existing editor storage machinery, with 32 MiB
input and 64 MiB output limits. The image parser also enforces a maximum of
40 million pixels and 16384 pixels in either dimension. The host captures the
origin before loading; changing the active pane/account cannot redirect an
existing editor's save. Failed source verification blocks overwriting.

Export explicitly selects the original PNG/JPEG encoding. A square bound
based on the original longest side preserves full resolution after a quarter
turn. PNG uses straight RGBA capture to preserve transparency. Edited output
is a flattened raster; metadata, color-profile information, and high-bit-depth
source data may not survive rendering. The UI discloses the flattening and
metadata behavior. Unsupported formats currently remain viewable through F3.

### Localization contract

`lib/l10n/image_editor_strings.dart` maps every reachable engine string field
to `image_editor_translations.dart`. All nine app languages have complete
catalogs. Named filter styles are explicitly treated as invariant names;
descriptive filter names are translated. Numbers and slider accessibility
values use the active locale. Standard system controls use their corresponding
Flutter/Material UI localization delegates.

The Python gate detects missing language keys, newly introduced engine fields,
unmapped filter names, dynamic host messages, and hardcoded visible labels in
the enabled engine surfaces. It intentionally excludes disabled emoji,
sticker, audio, and video tools and unrelated pre-existing app screens.

## Reproducing verification

Use the SDK pinned by `.fvmrc` (Flutter 3.47.8):

```bash
flutter pub get
python3 tool/check_image_editor_i18n.py
flutter test --concurrency=2 \
  test/image_edit_session_test.dart test/image_file_store_test.dart \
  test/image_editor_live_test.dart test/image_editor_menu_test.dart \
  test/image_editor_strings_test.dart test/file_editability_test.dart \
  test/pdf_file_store_test.dart test/widget/image_editor_menus_test.dart \
  test/widget/image_editor_routing_test.dart
flutter test --concurrency=1 test/widget/image_editor_dialog_test.dart
flutter test --platform chrome --concurrency=1 \
  test/widget/image_editor_menus_test.dart \
  test/widget/image_editor_routing_test.dart \
  test/widget/image_editor_dialog_test.dart
```

Run the maintained engine's regression tests separately:

```bash
cd packages/pro_image_editor
flutter pub get
flutter test test/crispcloud
```

The real-file tests are part of normal CI and require no provider credentials.
They use actual temporary files and Flutter's independent decoder. The widget
suite substitutes only storage: real codecs, editor commands, rendering, image
capture, and encoding run in both the VM and Chrome. Its browser-only case also
uses the production web-worker generation path. Existing credential-dependent
provider tests remain separately opt-in.

The `Image editor` workflow runs these gates on this feature branch, relevant
main pushes, and pull requests. It records the exact formatting/dependency
patch produced by the pinned toolchain as a review artifact; those changes
must be incorporated before completing the branch.
