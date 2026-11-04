# Maintained PDF core

Based on Apache-2.0 `ben-milanko/dart-pdf` 14.0.0, commit
`87adaa022c5ed6b22ca3232b6cae4a03e8389e98`. Original copyright and license
remain in place. This source snapshot keeps application and CLI builds on the
same reviewed implementation. The workspace-only pub resolution marker is
removed for standalone resolution.

A separate CrispStrobe fork was requested. Its creation is pending authenticated
GitHub website access; the GitHub connector cannot create repositories or forks.
Until it exists, all changes are checkpointed in CrispCloud's
`feature/pdf-editor-integration` branch. This file does not claim that the fork
has been created. The engine patch and the new Apache-2.0 `pdf_operations`
package can be transferred onto the pinned upstream commit without depending
on unpublished registry releases.

The extension adds selected-page preservation and Unicode OCR support. See
`docs/pdf-operations.md` for the current integration and verification status.

## Reproducible source patch

`UPSTREAM.patch` contains every runtime and packaging change relative to the
pin above. `tool/update_pdf_vendor_patches.py --upstream PATH --write` rebuilds
both PDF runtime patches, applies them to isolated original snapshots and
verifies every resulting byte. Core regression tests are in `test/crisp_*.dart`.

Extraction retains selected AcroForm branches/defaults/calculation order,
bookmarks, named destinations, layers and output intents where supported.
Links to omitted pages are removed; unrelated document JavaScript, attachments
and prior revision bytes are not copied. Shared resources may still contain
unused data, so extraction is not a secure-erasure operation.

`injectTextLayer(embeddedFont: ...)` writes a Unicode Type0 font with its
program and ToUnicode mapping. Missing glyphs are rejected before changing the
page. Existing embedded-font form styling is reused without changing its API.
