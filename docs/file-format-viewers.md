# Saved email, Word variants and keyboard profiles

F3 and the preview pane recognize the formats below. The table describes the
full F3 viewer; the compact pane shows an email view, extracted Office text, or
keyboard-profile XML source. F4 uses the existing captured-source editor/save
coordinator; opening a file never sends a message, executes a macro, or changes
its original bytes.

| Extensions | Viewer | Editor |
| --- | --- | --- |
| `.eml` | Decoded subject, sender, recipients, date, plain text or safe HTML, attachments | MIME source in the text/code editor |
| `.msg` | Outlook compound-message headers, plain text or safe HTML, ordinary attachments | Existing explicit hex editor; no structured Outlook writer |
| `.doc`, `.dot` | Main-document text from unencrypted Word 97–2007 binary files | View-only as a Word document; convert to DOCX in Word/LibreOffice for rich editing |
| `.docm`, `.dotm`, `.dotx` | Existing formatted Word view, text and page rendering | Rich Word editor with macro/template preservation checks before saving |
| `.kbdx` | XML tree and source for Autodesk keyboard-shortcut profiles | XML source in the text/code editor |

`.kbdx` is the Autodesk extension named in its
[custom-interface documentation](https://help.autodesk.com/cloudhelp/2016/ENU/3DSMax/files/GUID-41CA005E-8B79-4823-A586-C27ABDDD1B2B.htm).
KeePass password databases use a different extension, `.kdbx`; this change does
not add a password-vault reader or treat those databases as editable XML.

## Email

The viewer decodes MIME multipart messages, Base64 and quoted-printable content,
encoded headers, and extended attachment filenames. Outlook MSG parsing reads
the message's own compound-file storage instead of accidentally treating an
embedded message's properties as its parent's headers.

The formatted view keeps basic document formatting and removes active content,
links, external images, CSS and resource attributes. It performs no remote
content fetch. Plain-text view remains available. Ctrl+F in the F3 Email view
searches a decoded text representation of headers, body and attachment names;
closing search restores the formatted message. The ordinary Text/Hex modes
remain available for inspecting the original file bytes.

Decoded-search data is built only when a nonempty query is submitted. A limit
of 200,000 lines or 8 MiB of decoded UTF-8 text is checked before allocating the
search index. If the limit is exceeded, the formatted view remains available
and a localized explanation is shown. Single-file compressed messages, such as
`.msg.gz`, use the decompressed filename to select the correct parser.

Selecting an ordinary attachment opens its exact bytes in the existing viewer.
That nested viewer has no writable original-file target. Embedded Outlook
messages and MSG files whose only body is compressed RTF are explicitly
identified as limitations. Unknown character encodings are approximated with a
visible warning; recoverable text/header decoding issues and incomplete MIME
boundaries also produce warnings. Invalid Base64 and unsupported transfer
encodings fail the preview. Unicode, UTF-8, Latin-1, Windows-1252 and common ASCII
aliases are handled directly. This is a saved-message viewer, not an email client.

F4 on an EML opens its **MIME source**. Existing text-editor encoding and newline
metadata preserve untouched encoded attachment text and CRLF line endings.
Changing source does not automatically rewrite MIME boundaries, re-encode a
body, or update message signatures. The normal dirty-state, save-conflict and
recovery behavior applies.

Resource limits include 32 MiB input in F3 (the compact preview pane retains its
20 MiB input limit), 8 MiB per body, 16 MiB per attachment,
128 attachments, 512 MIME parts, 20 nested MIME levels and 512 MSG recipients.
Compound-file allocation tables and directory graphs are validated before use;
duplicate ownership, cycles, invalid pointers and oversized streams are rejected.
Direct-child lookups are cached to avoid repeated traversal of malicious graphs.

## Word documents and templates

Binary DOC/DOT extraction follows Microsoft's
[documented FIB/CLX text-retrieval algorithm](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/01d5d8c4-cf9c-4ef9-80fd-439e763cfe01).
It reads text in logical piece-table order, including compressed and UTF-16
pieces, and excludes unreferenced stream bytes. The preview does not reconstruct
formatting, images, headers, notes or tracked-change semantics. Encrypted files,
older pre-Word-97 variants and malformed structures produce a clear failure.
The main story is capped at 4 × 1024 × 1024 UTF-16 code units.

Macro-enabled documents and templates use the already-vendored Word editor.
Before editing, the package's main content type must match its extension.
Before every upload, the preservation guard checks the original main-part path
and content type, opaque binary/VBA/custom-UI payload hashes, and VBA
relationships. A failed check leaves the original untouched and the editor
dirty. Macros are retained as opaque data and never run.

Compact previews and page rendering follow the package's main-document
relationship, including valid macro-enabled Word packages whose main part is
outside the conventional `word/` directory.

Package-level XML digital signatures prevent editing, because editing document
content would invalidate them. The guard preserves opaque VBA signature bytes;
that byte-preservation check is not an independent Microsoft Word signature
validation. Existing Office fidelity limits still apply; see
[Office formatting support](office-formatting-support.md).

## Dependencies and licensing

No new dependency was introduced. Compound-file parsing reuses
`CfbfFile` from the existing MIT-licensed
[`quds_office_engine`](../packages/quds_office_engine/LICENSE). MIME parsing,
resource checks and format routing are CrispCloud code. HTML parsing/rendering
uses existing dependencies. This avoids adding a native-only mail parser or a
new dependency with a different license merely to recognize these extensions.

## Verification

Focused regression suites include:

- `test/email_message_service_test.dart`: MIME/MSG decoding, mixed body sections,
  attachment naming, code pages, sanitization, and adversarial CFB graphs.
- `test/widget/email_message_view_test.dart`: headers, attachments, safe HTML and
  translated controls.
- `test/widget/extended_format_viewer_test.dart`: F3 routing, decoded-email
  search, read-only attachment handoff, keyboard XML, and source byte retention.
- `test/legacy_word_document_test.dart`: piece order, main-story clipping, field
  results, encryption, malformed input and Office-view integration.
- `test/word_template_preservation_test.dart`: actual asynchronous editor saves,
  a second round trip, macro bytes/relationships, failure guards and DOTM UI.
- `test/word_format_strings_test.dart`, `test/file_editability_test.dart` and
  `test/internal_viewer_test.dart`: localization, editor routing and MIME types.

Macro fixtures contain synthetic opaque payloads. They establish preservation
and failure behavior, not macro execution or a Microsoft Word certification.

The development validation run passed 283 tests across 20 focused parser,
archive, favorites, viewer, preview and editor suites. A separate JavaScript
compilation and execution smoke check passed Unicode EML, MSG/CFB and legacy DOC
parsing. A full Flutter web release build was not run locally because the cached
SDK lacks the Flutter web target artifacts; the JavaScript parser check does not
replace that application build or platform acceptance testing.
