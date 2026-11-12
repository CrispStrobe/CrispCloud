# Portable RTF and binary PowerPoint previews

CrispCloud's built-in F3 viewer and side preview can read RTF and binary
PowerPoint 97–2003 files without installing Office, running a conversion tool,
opening a WebView, executing macros, or fetching document resources. These are
read-only previews; the original bytes remain available to the existing source
and hexadecimal views.

## RTF

`lib/services/rtf_document.dart` reads RTF 1 documents into readable plain text,
Markdown, and HTML generated from escaped text and a fixed set of formatting
tags. The UI uses that generated HTML for the formatted preview. It never
passes original RTF text through as HTML.

The supported subset includes paragraphs, line breaks, tabs, bold, italic,
underline, strike-through, paragraph alignment, explicit numbered/bullet list
labels, and flat table rows and cells. Grouped formatting is restored when the
group ends. Unicode escapes include signed UTF-16 values, surrogate pairs,
scoped fallback counts, and the Unicode alternative of `\upr` groups.

Legacy text decoding supports Windows code pages 1250–1258, DOS 437/850/866,
Thai 874, Mac Roman, Latin-1, and UTF-8. Font-table character-set and code-page
overrides are honored. Unicode RTF remains readable even when its legacy
fallback code page is unsupported. Actual unsupported multibyte legacy text
returns an explicit encoding error; it is not silently decoded as Latin-1.
Symbol-font support is limited to the conventional bullet and ASCII fallback.

The parser omits font resources, pictures, embedded objects, unknown starred
destinations, metadata, headers, footers, notes and hidden text. Fields display
their stored results; instructions and links are not executed. It does not
reproduce pagination, font metrics, image placement, automatic list numbering,
or nested tables. Nested tables produce an explicit unsupported-formatting
message. The preview's limitation note is available in all nine UI languages.

Limits are 8 MiB of input, 4 Mi UTF-16 units of preview text, 128 group levels,
250,000 group/control tokens, 256 cells in a row, 10,000 rows in a table, and
bounded generated markup. Binary payloads are skipped by their declared length,
so braces inside a picture or object cannot alter parser nesting. Truncated
binary data, malformed groups and invalid Unicode produce typed errors.

`parseRtfDocument(Uint8List)` returns an `RtfDocument` with `plainText`,
`markdown`, and `html`. Its fixed failure contract is
`RtfDocumentException` with `malformed`, `unsupportedCodePage`,
`unsupportedFeature`, or `resourceLimit`. The Outlook MSG reader reuses its
plain-text and generated safe HTML results after separately bounded MS-OXRTFCP
decompression.

## PowerPoint 97–2003

`lib/services/legacy_powerpoint_document.dart` reads `.ppt`, `.pps`, and `.pot`
compound files through the existing bounded CFB reader. It reconstructs the
active document in this order:

1. Read the root `Current User` stream's `CurrentUserAtom`.
2. Follow the newest `UserEditAtom` and its previous-edit chain.
3. Merge persist-directory entries newest first, retaining older mappings only
   for objects that were not updated in the latest save.
4. Read the active document's slide list, preserving its slide order.
5. Resolve each referenced slide's drawing shapes. Read local text boxes or
   follow `OutlineTextRefAtom` references to that slide's placeholder text.

This avoids the common error of scanning every text-looking record in the
compound file. Superseded save generations, deleted slides, master-slide and
speaker-note lists, unrelated embedded documents, and private client data do
not become current slide text. Shapes marked deleted are omitted, including
the descendants of a deleted group. Unreferenced outline text is omitted too.

Both UTF-16 `TextCharsAtom` records and `TextBytesAtom` records are supported.
The latter store the low byte of each UTF-16 character, as specified by MS-PPT;
they are not decoded using Windows-1252. Paragraph and soft-line breaks become
newlines. Slide headings are generated separately from document content so UI
translation cannot accidentally change an author's text such as “Slide 1”.

This is a text preview, not slide rendering. Masters, speaker notes, images,
charts, media, animation, drawing positions and page layout are not reproduced.
No Office application, VBA project or embedded object is launched. Encrypted
presentations, unsupported older formats, invalid references and excessive
complexity produce explicit localized messages.

Limits are 64 MiB of input and compound-stream reads, 4 Mi UTF-16 units of
decoded text, 4,096 edit generations, 100,000 persist entries, 250,000 records,
10,000 slides, and 64 drawing nesting levels. Record extents, edit ordering,
duplicate references, Unicode and placeholder indices are checked before use.

`extractLegacyPowerPoint(Uint8List)` returns a
`LegacyPowerPointDocument` containing `slides` (`slideId`, `text`) and
`plainText`. Its fixed failure contract is `LegacyPowerPointException` with
`malformed`, `unsupportedVersion`, `encrypted`, or `resourceLimit`.

## Verification and provenance

The parser tests include hand-built compound files containing two save
generations, an unchanged slide inherited from an older save, superseded text,
deleted slides, deleted shapes, master text, notes, encrypted-file markers,
missing references, duplicate persist entries, cycles, and invalid record
lengths. RTF tests cover group-scoped formatting, fallback encodings, Unicode,
lists, tables, skipped destinations, escaped markup, and size/depth limits.

The independently generated fixture
`test/fixtures/legacy_powerpoint/current-slides.ppt.gz` contains the exact bytes
of a real binary PPT exported by installed LibreOfficeDev 26.8.0.0.alpha0 from
CrispCloud-authored content. Gzip only reduces repository size. Its regression
checks two current slides, title/body text, a separate text box, Unicode and
accented characters, and exclusion of speaker notes. See the fixture's README
for its hash and reproduction script. This sample is compatibility evidence,
not a claim that every PowerPoint feature is supported.

Focused tests:

```sh
flutter test test/rtf_document_test.dart \
  test/legacy_powerpoint_document_test.dart \
  test/office_document_service_test.dart \
  test/office_preview_strings_test.dart \
  test/outlook_rtf_compression_test.dart \
  test/email_message_service_test.dart \
  test/widget/extended_format_viewer_test.dart
```

`tool/verify_portable_office_web.py --dart /path/to/dart --node /path/to/node`
compiles the production parsers directly to JavaScript and runs the same PPT
fixture, RTF Unicode/formatting, and an Outlook compressed-RTF golden vector
under Node.js. It uses the existing package configuration and deletes its
temporary outputs. This checks browser-compatible parser code without requiring
a full Flutter web build; it is not a browser UI rendering test.

## Primary format references and licensing

The parsers are authored from the format specifications; no Microsoft sample
parser implementation or new document-viewer dependency was copied. Code-page
tables contain mapping data generated through Python's standard codecs. The
existing compound-file implementation is the project's MIT-licensed Quds
engine, accessed through its bounded wrapper.

- [Microsoft RTF 1.9.1 specification](https://officeprotocoldoc.z19.web.core.windows.net/files/Archive_References/%5BMSFT-RTF%5D.pdf)
- [MS-PPT CurrentUserAtom](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ppt/940d5700-e4d7-4fc0-ab48-fed5dbc48bc1)
- [MS-PPT UserEditAtom](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ppt/3ffb3fab-95de-4873-98aa-d508fbbac981)
- [MS-PPT PersistDirectoryAtom](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ppt/d10a093d-860f-409c-b065-aeb24b830505)
- [MS-PPT SlideListWithTextContainer](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ppt/307e6d12-7304-47a8-acbd-3e7b8041ad3c)
- [MS-PPT TextHeaderAtom](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ppt/08d31a66-0750-4009-b416-49f2871cd178)
- [MS-PPT TextBytesAtom](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ppt/80aae34b-2699-43fa-9e6a-c560ae790cd7)
- [MS-PPT OfficeArtClientTextbox](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ppt/f50070dd-a4dc-4edd-a446-c4fcc5c80ace)
- [MS-ODRAW OfficeArtFSP, including deleted-shape flags](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/8a7e7be3-0582-4461-9400-29d7eda8497d)
