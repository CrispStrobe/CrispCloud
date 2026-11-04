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
