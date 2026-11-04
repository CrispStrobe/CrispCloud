# Shared PDF operations: implementation checkpoints

The new Apache-2.0 `packages/pdf_operations` layer is shared by the CrispCloud
GUI and standalone CLI. It implements inspection, text/search, merge, extraction,
rotation, reordering, page deletion, PNG/JPEG insertion, text/logo watermarks,
strict named AcroForm filling, and import of externally recognized OCR spans.

The GUI exposes operations from the file context menu and command palette.
The CLI exposes `crisp pdf`; see `cli/README.md` for commands and storage rules.

## Checkpoint status

This is an implementation checkpoint, not a claim that the new code has passed
validation. Hosted Dart/Flutter tests, independent PDF verification and builds
will be recorded here as they complete. The previously validated PDF editor
integration remains the base. Core extraction and OCR changes are being
completed in the pinned upstream source and synchronized into this repository.

## Repository status

A dedicated CrispStrobe fork of `ben-milanko/dart-pdf` was requested. The current
GitHub connector supports feature-branch pushes but not fork creation. Browser
sign-in was cancelled. Engine and application source are therefore preserved
in incremental CrispCloud feature-branch commits until the fork is available.
No work is being committed to the original author's repository.

## Limits to retain

- XFA editing and redaction remain disabled; a source signature does not certify
  a modified document. Outputs are new files, with explicit separate-output
  overwrite controls where available.
- Extraction creates an unencrypted file; protected sources require explicit
  acknowledgement. Merge inherits the first whole source's encryption policy.
- Page deletion uses incremental saves, so old content can remain in history.
- Batch form filling refuses password fields and rejects invalid mappings before
  output; missing font glyphs must produce errors rather than lost characters.
- OCR import writes supplied recognition only. It does not bundle or launch a
  model. Complex script shaping remains dependent on the writer's capabilities.
- Generic cloud writes have preflight checks, not atomic conditional writes.
