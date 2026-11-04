# Test font

`CrispPdfTestSans.ttf` is a renamed, reduced test fixture derived from the
upstream `pdf_document/test/fonts/DejaVuSans.ttf`. It contains printable ASCII
and selected Latin, Greek, Cyrillic, and Hebrew glyphs needed by the tests.
It deliberately lacks other glyphs used in negative coverage tests.

- Original font SHA-256: `ae7b7855e115a5966d8b1b3f80f254ccc117ec86f9965e202ee2940453837280`
- Fixture SHA-256: `523a819ce26b5854632baec8a3be0c52d82f4d926475d51f8ca927050d5df8b0`
- Generator: `tool/make_test_font.py`, fontTools 4.61.1
- Original copyright/license text is retained verbatim in the adjacent
  `DejaVu-LICENSE.txt` and `DejaVuSans-font-metadata-LICENSE.txt` notices.

The test font is not shipped as an application font. Do not infer general
language coverage from this intentionally limited test fixture.
