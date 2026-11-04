# Local fork notes

This is a vendored copy of `quds_office_engine` 1.5.0 (MIT), used through
`dependency_overrides` in the app's `pubspec.yaml`.

Changes made in this fork:

- `lib/src/word/serial/word_deserializer.dart`: imported DOCX footnote and
  endnote references now set `WmlRunProps.vertAlign` to `superscript`. Word
  stores that formatting in the `FootnoteReference` character style, which the
  importer does not resolve, so the marks previously rendered as ordinary
  baseline digits (`Madness?1` instead of `Madness?¹`).
- `lib/src/word/layout/word_layout.dart`: footnote notes are attached to the
  page that actually contains the reference glyph, rather than every page that
  contains any line of the paragraph. This stops a note from being repeated on
  both pages when its paragraph crosses a page break.

See `test/office_footnote_test.dart` and `test/fixtures/footnote.docx`.
