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
