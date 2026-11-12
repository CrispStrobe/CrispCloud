# Ebook scope extension — 2026-11-12

## Starting point

Continue from `82e328afa3822fe6065e0aa6aa7f7515ec1c6557` on
`feature/ebook-reader-editor`, draft PR #53. Preserve the existing package
editor, enhanced reader, Linux chapter reader and legacy text fallback.
Continue saving coherent remote checkpoints throughout the work.

The user requested a broader scope. The implementation now covers:

1. Formatting-preserving correction inside EPUB paragraphs: edit text runs
   without flattening emphasis, links, identifiers, publisher spans or embedded
   objects. Reject stale or partially invalid edit batches atomically.
2. Better portable Linux EPUB reading: bounded whole-book search, bookmarks,
   persisted appearance and same/cross-chapter anchor navigation, using the
   existing renderer and annotation store.
3. Expanded Kindle metadata editing with explicit keep/set/clear behavior and
   existing native cover support. A bundled metadata-only Wasm worker uses the
   same reviewed byte engine, with independent per-operation capabilities and
   real native/Wasm parity tests.

Full Linux browser packaging and full EPUB-to-Kindle browser export are separate
engineering efforts; do not silently advertise them through capability flags.
The portable-reader increment does not add a CEF dependency. No content is sent
to a conversion service.

## Hosted verification of the starting point

Run 43184353306 completed: application integration/web build, EPUB preservation,
and macOS/Windows native conversion jobs passed. The Linux native/parser/import
steps passed; its actual Chromium step failed before browser startup because
the repository-relative temporary directory made the Unix socket path too long.
Use the platform temporary directory with a short prefix for that probe.

Keep the original verified fixtures and assertions. An unavailable local browser
runtime does not count as a rendering pass; use the hosted browser job.

## Integration constraints

- Keep all edits to the original ebook reversible through the existing session.
- Preserve invalid drafts and original input bytes on failure or cancellation.
- Keep annotation identities separated by source, content version and renderer.
- Keep native and browser conversion capabilities explicit per operation.
- Add focused preservation and interaction tests; retain independent EPUBCheck
  and Foliate checks for edited/rewritten output.

## Incremental progress

- `ec8f8a1`: saved the scope, synchronized the feature branch with current main,
  and shortened the Chromium probe's temporary path.
- `e5a5c12`: saved the first structured-prose core implementation and its 42
  passing tests. Subsequent guarded plain-text authoring and bounds checks bring
  the core suite to 46 tests.
- `3905746`: saved the bundled browser metadata Wasm engine, worker adapter,
  per-operation capabilities and native/Wasm verification.
- `7530c2`: saved the application integration and workflow updates, including
  the expanded editing/reader/metadata UI. The final focused application run
  passes all 102 tests; temporary local test hooks were removed afterward.
- `47e83b0`: saved the shared native/browser metadata corrections for
  Windows-1252, EXTH insertion and title clearing, together with the rebuilt
  Wasm asset and refreshed source provenance.

## Completed extension behavior

### Formatting-preserving prose correction

`EpubStructuredProseEditing` in `packages/crisp_ebook/lib/src/prose.dart`
discovers supported innermost XHTML paragraphs and exposes immutable text
segments. Corrections update the original XML text nodes, retaining nested
emphasis, hyperlink destinations, identifiers, publisher spans, namespaces and
unknown attributes. Embedded images, ruby, MathML/SVG, foreign/unknown markup,
comments, CDATA and structured line breaks remain protected.

`readStructuredProse(path)` returns blocks with a complete resource fingerprint.
`updateStructuredProseBlock(block, replacements)` validates the complete batch
and resource fingerprint before publishing. `updateStructuredProseText` provides
the same guard for plain paragraphs, retaining the existing newline-to-`br`
authoring behavior. It bounds line-break expansion before allocating nodes and
validates the resulting XML size/node/depth limits. Empty/no-op applications
retain clean state and original package bytes. Fixed-layout content remains
source-only; the structured surface is capped at 1,024 segments per paragraph.

`EbookProseEditorDialog` uses the existing session's atomic mutation/undo path.
It displays recognized formatting and protected segments, offers a single
multiline field for plain paragraphs, and retains entered text after stale or
failed applications. The legacy source editor and text fallback remain intact.

### Portable Linux reading

`EbookChapterReaderController` now supports case-insensitive literal search,
same/cross-chapter anchors, bookmarks, local progress and appearance. Search
anchors are added only to a display copy. Portable locators encode chapter,
fragment and approximate scroll progress in their own namespace; annotation
storage adds a renderer identity instead of mixing them with Foliate CFIs.

The shared reader UI supplies search results, bookmark controls and persisted
font size/family, line spacing and light/sepia/dark themes. Portable reading
stays continuously scrolled. It does not add enhanced-reader pagination, saved
highlights/notes, full CSS/fixed-layout fidelity, or non-EPUB import on Linux.

Search defaults to 200 hits and allows a 1,000-character literal query. It
examines at most 2,000 chapters / 32 MiB of chapter data, skips chapters over
2 MiB and reports skipped/bounded work. Display parsing retains the 8 MiB text
limit and bounds complexity to 25,000 nodes / depth 128. Prepared chapter data
uses an 8 MiB bounded cache. A newer query or document revision invalidates
older pending results.

### Kindle metadata and browser runtime

The application now exposes all ten supported metadata fields: title, authors,
publisher, description, language, ISBN, ASIN, publication date, subjects and
identifier. Every field defaults to Keep; Set and Clear are explicit. Missing
reader metadata cannot silently erase stored fields. Authors and subjects are
multivalue inputs, and the app bounds the selected metadata JSON to 120 KiB.
Failed/canceled operations or exports retain the dialog draft for retry.

Native builds can also replace an existing cover. Full EPUB-to-AZW3/MOBI export
and Kindle cover replacement remain native operations, reported by separate
capability flags.

The browser metadata adapter is implemented with the checked-in Wasm asset and
a fresh same-origin module worker per request. It executes the same metadata
byte engine as native builds for unencrypted AZW3, dual MOBI and legacy MOBI.
It returns a separate copy; no conversion service receives book content.
Capabilities remain unavailable if the bundled worker or Wasm cannot load.
Timeout/cancellation terminates the worker and discards partial output.

The browser's default ceilings are 64 MiB input, 128 MiB output, 128 KiB metadata
JSON and 384 MiB Wasm memory; browser/device limits may be lower. Ordinary app
builds use the checked-in asset. The conversion package's README documents the
deliberate rebuild, hash/provenance checks and real worker probes.

An independent final review found three cases missing from the original
UTF-8 fixtures. The shared engine now encodes new text losslessly for each
section's existing UTF-8 or Windows-1252 declaration, sets the EXTH-present
flag when adding a metadata block, and reconciles the header title, EXTH 503
and EXTH 542 independently. Unsupported encoding/character combinations fail
without output; no unchanged body text is relabeled. Title Clear also works
when EXTH 503 is missing or empty. The primary and KF8 halves of dual MOBI
can retain different encodings.

The new native/Wasm parity cases use actual converter output with ASCII body
text and independent header/metadata decoders. They cover 11 additional edge
cases and eight explicit rejection cases, including source and payload-record
preservation, EXTH visibility, encoded title hashes and idempotence. The final
Wasm is 884,408 bytes, SHA-256
`0066f950a5d127fcad27fc11a08a587c5c3d7e245f3ecb1b140cadd94f84e3b6`.

## Verification status

| Gate | Current result |
| --- | --- |
| EPUB core | 46 tests pass; analyzer clean |
| New prose dialog | 7 widget tests pass; targeted analyzer clean |
| Native converter | 27 Dart/native-assets tests pass; analyzer clean |
| Rust bridge | 4 tests pass |
| Embedded reader Flutter controller | 3 tests pass |
| Production browser adapter with actual Wasm | 24 assertions through 11 Node workers pass; includes cancellation/timeout and source preservation |
| Native/Wasm metadata parity | Three original format fixtures, 11 added edge cases and eight explicit encoding rejections pass |
| Core EPUBCheck 5.4.0 | Four fixtures, including formatted-text-edit.epub: zero fatal errors, errors or warnings |
| Complete Kindle-to-EPUB import chain | Previously verified source plus three imported EPUBs remain part of the regression gate; all four reports were clean |
| Expanded app/service/widget suite | All 102 tests pass in one final run; exit 0 and root pubspec restored |
| Current extension web release | Run the final application JavaScript release build after the extension's assets and integration are complete |
| Actual browser and platform checks | Pending hosted rerun; local Chromium launch is blocked by socket EPERM before test startup |
| Reviewed source evidence | Source check passes; 41 evidence tests complete with two existing platform skips, and all 37 Apple preflight tests pass |
| Scope formatting | All 64 changed Dart files pass the formatter without changes |

The compiled Dart adapter tests execute the bundled Wasm through actual Node
workers. They establish runtime/bridge behavior and metadata preservation, not
successful browser asset loading or browser layout. The authored fixtures are
integration samples rather than a publisher compatibility corpus. Keep these
distinctions explicit in PR and release claims.

The initial prose widget failures were test sequencing/lazy-list lookup issues:
tests now pump the enabled-state frame before Apply, assert that the button is
enabled, and scroll until lazy fields are built. Their assertions were retained;
the focused seven-test rerun passed without product changes. The temporary root
pubspec hooks used for local app testing were restored afterward. The complete
102-test run then passed; no failing app-test assertion remains in this gate.

For the final app gate, use the established wrapper/environment and the full
focused suite, including the new prose, portable-reader/controller and Kindle
metadata-dialog tests. The JavaScript release build command is:

```sh
flutter build web --release --no-pub --no-wasm-dry-run
```

The existing core fixture generator now emits four EPUBs, so the workflow's
wildcard EPUBCheck step includes formatted-text preservation automatically.
Core reports are reproducible with `tool/generate_fixtures.dart`; conversion
and actual worker commands are in
[the converter README](../../packages/crisp_ebook_conversion/README.md).

User-facing controls, platform capabilities and limits are documented in
[the ebook guide](../ebooks.md). Update this status after the final integration,
web-build and hosted checks; do not turn a queued or blocked gate into a pass.

The [dated source review](../crypto-source-review-2026-11-12.md) records the
177-path technical inventory and root dependency delta. Existing encryption,
documentation and distribution decisions retain their prior values; only the
review date and exact input fingerprints are refreshed. No release approval or
live store verification is implied by the passing source check.
