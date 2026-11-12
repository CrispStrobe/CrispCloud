# Authored binary PowerPoint fixture

`current-slides.ppt.gz` is a gzip-compressed copy of a real PowerPoint 97–2003
binary file exported by installed LibreOfficeDev 26.8.0.0.alpha0. Its slide text
and notes were authored for CrispCloud; it contains no user document content,
executable macros, or external links.

The file contains two slides, title and body placeholders, an independent text
box with accented text, Unicode text, and speaker notes that the portable
preview must omit. The generated PPT is stored verbatim inside gzip; no streams
or metadata were removed to make the parser pass.

- Expanded PPT size: 651,264 bytes.
- Expanded PPT SHA-256:
  `53f5385ce4281e395aa21dfb951207acfe25a64fafffdb0bdcb93ddd9584ad9b`.
- Compressed size: 26,320 bytes.
- Regression: `test/legacy_powerpoint_document_test.dart`.

`test/support/create_legacy_powerpoint_fixture.py` recreates the content using
an already-installed `python-pptx` package and LibreOffice executable. It does
not download either dependency. Different LibreOffice versions and metadata
timestamps may change binary hashes while leaving the tested content intact.
