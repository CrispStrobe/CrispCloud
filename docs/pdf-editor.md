# PDF editing

CrispCloud embeds the Apache-2.0 `dart_pdf_editor` 14.0.0 runtime for editing
existing PDFs. The `pdfx` preview remains available for reading. Open the editor
with F4, the file context menu's Edit action, or Edit in the PDF preview.
PDFs are routed to this editor before the plain-text editor.
For selected-file actions and matching CLI commands, see
[PDF operations](pdf-operations.md).

## Features and limits

The editor offers annotations, notes, drawing, standard AcroForm fields,
page-content tools, page reordering/rotation, insertion, extraction and
splitting. CrispCloud supplies file picking, persistence and export callbacks.
Rendering and content-editing fidelity depend on the input PDF and available
fonts; the small integration corpus does not establish compatibility with
every PDF producer or complex layout.

Password-protected documents prompt for a password. Normal edits preserve
the document's encryption; extraction and splitting create separate outputs
and have their own export notices. New password-field values entered in this
session use an in-memory secret store and are withheld from PDF serialization.
This does not sanitize secrets already embedded in the original document or
its incremental revision history.
The PDF editor does not migrate or otherwise change account credential storage.

XFA forms are rejected with an explanatory message. For existing signed
documents, the editor's Save and Save copy actions require a separate file
to preserve the signed original. Editing that copy can invalidate its signatures.
Device exports follow the user-selected destination and overwrite confirmation,
or the browser's download handling; choose a separate destination to preserve
the original. Certificate signing is not enabled; a drawn signature is an
ordinary visual mark.

**Redaction is disabled.** Upstream can retain partially covered images and
Form XObjects beneath the visible fill. Hiding sensitive content with a shape
does not remove it from a PDF. The host tool restriction also suppresses the
redaction shortcut, text-menu and touch-chip actions, find-to-redact controls,
and Apply action. Existing `/Redact` annotations remain visible as unapplied
marks, with a warning that their content has not been removed.

Source PDFs are limited to 64 MiB, with a 128 MiB output/verification limit.
The editor holds bytes, parsed structures and undo history in memory; these
byte limits are not a guarantee of low memory use for complex documents.
Extract archive/container entries before editing. Files from search, flat
views or an unverifiable cached listing must be reopened from a fresh normal
directory listing so their storage origin can be established.

## Save behavior

The host owns asynchronous saves rather than treating the editor's callback
as a completed write. A save snapshots the current bytes. Only a successfully
completed overwrite marks that snapshot clean. Upload failures preserve edits
for retry, and edits made while a save is running remain unsaved afterward.
Repeated concurrent saves are rejected. Closing an unsaved session requires
an explicit choice; creating a copy does not mark the original saved.

The source is the client and account that actually produced the selected file
listing. It is captured when the document opens and does not follow later pane
or account changes. Account disconnection invalidates writes to that account.
Exporting to the device remains available to recover edits independently of
the original cloud connection.

Loading bypasses preview caches. Before overwrite, a fresh read and available
revision metadata are compared with the opened/saved baseline. A mismatch or
unreadable original produces a conflict instead of a blind overwrite. A
successful upload invalidates the preview cache.

These are **preflight checks, not atomic conditional writes**. The shared
cloud API has no ETag-conditioned overwrite or create-only operation, so
another writer can change a file between verification and upload. Save copy
also has a check/create race. Use unique copy names when concurrent writers
are expected; provider-specific atomic operations require a later storage
capability change. Some providers mask lookup failures, so copy creation also
requires a valid fresh parent listing that contains the original and no
matching target name. If that cannot be established, export to the device.

Native local overwrites and desktop device exports stage bytes beside the
destination before replacement. They retain supported mode bits, reject symlink
destinations, and honor macOS security scopes. Native Save copy reserves a new
filename exclusively and writes directly to that file instead of using staged
replacement. Android and iOS device exports let the native document provider
save the bytes. Replacement behavior depends on the filesystem. On Linux,
replacement can lose ownership, ACLs, and extended attributes even when mode
bits are preserved.

A browser with File System Access support can write to a granted destination;
a fallback download is reported as a downloaded copy. That means the download
was initiated, not that the browser or user confirmed the file was retained.
The original remains unsaved in that case.

## Dependency and toolchain

Flutter 3.47.8 / Dart 3.13.7 is pinned in `.fvmrc` and CI. The runtime is
vendored in `packages/dart_pdf_editor`, with its Apache-2.0 license, exact tag
and commit, and a reproducible local patch. See its
[provenance](../packages/dart_pdf_editor/UPSTREAM.md).

The optional secure-storage implementations are in the sibling
`dart_pdf_editor_secure_storage` package. The application does not depend on
that companion. The core and bundled editor-assets packages are pinned to
14.0.0. Both the application and CLI use the maintained `pdf_document` source
snapshot for extraction and Unicode OCR, and the shared `pdf_operations`
package. Their resolved dependencies are recorded in the application and CLI
lockfiles. Bundled fonts and the web worker are registered
during application startup.
Their separate OFL, Bitstream/Arev, and GUST/LPPL font licenses and provenance
are [bundled with the app](../assets/licenses/pdf_fonts/README.md) and available
through About / Licenses; the Apache-2.0 code license does not relabel the fonts.

## Verification

The dedicated PDF editor workflow runs package checks, host persistence and
widget/origin tests, a release web build, and an independent parser check.
The existing CI retains its full suite, desktop crypto gates and platform
build matrix. Nothing in this feature workflow deploys the application.

On 5 November 2026, the Chrome host tests for the PDF editor and shared PDF
operations passed locally (27 tests). The `v1.1.0` CI run produced the release
web build and uploaded it as a GitHub release asset. The same release uploaded
iOS `1.1.0 (10)` to App Store Connect; it is `VALID`, assigned to the internal
TestFlight group, and submitted for external Beta App Review. Production
hosting and a real browser file-picker flow still need to be exercised against
the deployed build; the automated tests do not substitute for that.

The footnote/Word round-trip fixes in `9536652` were verified after build 10
was uploaded, so the next TestFlight build must include them.

The independent tests start with ReportLab/pypdf-generated fixtures. Dart
edits form values, adds an annotation, reorders rotated pages, and saves both
plain and AES-256-protected inputs. Python/pypdf then checks the saved document
structure, text, embedded fonts, field values/appearances, annotation location,
page order and encryption. A simple text-redaction regression is accompanied
by an adversarial Form XObject case demonstrating why product redaction stays
disabled. See the [fixture notes](../test/fixtures/pdf_editor/README.md).

```sh
flutter pub get
python3 tool/format_pdf_editor.py
flutter test test/pdf_edit_session_test.dart test/pdf_file_store_test.dart \
  test/pdf_device_export_test.dart \
  test/panel_file_origin_test.dart test/widget/pdf_editor_dialog_test.dart \
  test/pdf_editor_round_trip_test.dart
python3 -m pip install pypdf==6.10.0 cryptography
python3 tool/verify_pdf_editor_outputs.py
```

CI uploads the generated PDFs and a verification manifest for review. These
checks do not replace an interactive browser/device smoke test, native file
picker and Apple security-scope testing, or inspection of representative
production PDFs. Test new upstream releases against those documents before
changing the pinned dependency set.
