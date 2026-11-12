# Ebook scope extension — 2026-11-12

## Starting point

Continue from `82e328afa3822fe6065e0aa6aa7f7515ec1c6557` on
`feature/ebook-reader-editor`, draft PR #53. Preserve the existing package
editor, enhanced reader, Linux chapter reader and legacy text fallback.
Continue saving coherent remote checkpoints throughout the work.

The user requested a broader scope. The staged implementation covers:

1. Formatting-preserving correction inside EPUB paragraphs: edit text runs
   without flattening emphasis, links, identifiers, publisher spans or embedded
   objects. Reject stale or partially invalid edit batches atomically.
2. Better portable Linux EPUB reading: bounded whole-book search, bookmarks,
   persisted appearance and same/cross-chapter anchor navigation, using the
   existing renderer and annotation store.
3. Expanded Kindle metadata editing with explicit keep/set/clear behavior and
   existing native cover support. Prototype a bundled metadata-only Wasm worker
   using the same reviewed byte engine, with independent per-operation
   capabilities and real native/browser parity tests.

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
