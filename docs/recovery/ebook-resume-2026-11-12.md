# Ebook implementation continuation — 2026-11-12

## Recovery point

The interrupted session's implementation was recovered from remote branch
`feature/ebook-reader-editor`, commit
`e6f98d33c3064a0ba0af778da2b269855a7e8cf9`, based on main
`f8dd29db4a00607513b7f687b21e4dc16e075735`.

The user approved all four proposed stages: package-preserving EPUB editing,
the foliate-js reader, structural and bounded prose editing, and conversion
with evaluation of Kindling export. MPL dependencies are explicitly allowed.
The legacy EPUB text viewer must remain accessible. Save coherent checkpoints
to the remote feature branch throughout implementation; do not wait for final
validation. No merge to main is requested.

## Continuation checkpoint 1

- Preserve contextual OPF, XHTML and NCX namespace prefixes during mutations;
  keep foreign/structured line breaks out of bounded prose editing.
- Preserve valid bundled CSS imports in the reader and normalized EPUB copies.
- Add regression fixtures for prefixed XML and chained imported stylesheets.
- Reader parser smoke suite passes. Full Chromium smoke launch is currently
  blocked by the executor's socket permission restriction, before test startup.
- Dart/Flutter verification is pending SDK setup. These are implementation
  checkpoints, not a declaration that all platforms have passed validation.

## Work in progress

- Restore a visible legacy EPUB text fallback, including editor-load failures.
- Audit editor save/copy/close behavior and app routing; run focused tests.
- Verify native Kindle conversion and build hooks; retain useful MPL components.
- Record pinned vendor provenance and meaningful validation results.
- Add a focused ebook CI gate and assess native/browser platform coverage.

The existing Linux path is a Flutter chapter reader plus EPUB editing. The
embedded foliate WebView is currently available on Android, iOS, macOS,
Windows and web. Keep this capability distinction explicit.
