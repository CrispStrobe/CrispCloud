# Saved email, Word variants and KeePass databases

F3 and the preview pane recognize the formats below. The table describes the
full F3 viewer; the compact pane shows an email view, formatted RTF, extracted Office text, or
keyboard-profile XML source. KeePass previews stay locked until explicitly
opened. F4 uses the existing captured-source editor/save
coordinator; opening a file never sends a message, executes a macro, or changes
its original bytes.

| Extensions | Viewer | Editor |
| --- | --- | --- |
| `.eml` | Decoded subject, sender, recipients, date, plain text or safe HTML, attachments | MIME source in the text/code editor |
| `.msg` | Outlook compound-message headers, plain text, safe HTML or decoded compressed RTF, ordinary attachments | Existing explicit hex editor; no structured Outlook writer |
| `.rtf` | Basic formatted runs, paragraph alignment, explicit list markers and flat tables | Existing RTF source editor; no rich RTF writer |
| `.ppt`, `.pps`, `.pot` | Text from the current slide list and referenced current drawings, in slide order | Existing explicit hex editor; no binary PowerPoint writer |
| `.doc`, `.dot` | Main-document text from unencrypted Word 97–2007 binary files | Converts a separate DOCX/DOCM copy through supported installed Word/LibreOffice, or an explicitly selected text-only DOCX |
| `.docm`, `.dotm`, `.dotx` | Existing formatted Word view, text and page rendering | Rich Word editor with macro/template preservation checks before saving |
| `.kdbx` | Password/key-file unlock, groups, standard/custom fields, entry history and search | Group management, entry moves, protected custom fields, history restoration and encrypted saves preserving other database data |
| `.kbdx` | XML tree and source for Autodesk keyboard-shortcut profiles | XML source in the text/code editor |

`.kbdx` is the Autodesk extension named in its
[custom-interface documentation](https://help.autodesk.com/cloudhelp/2016/ENU/3DSMax/files/GUID-41CA005E-8B79-4823-A586-C27ABDDD1B2B.htm).
KeePass password databases use a different extension, `.kdbx`; they open in the
dedicated database viewer/editor, never as XML source. See
[KeePass support and limits](keepass.md).

## Email

The viewer decodes MIME multipart messages, Base64 and quoted-printable content,
encoded headers, and extended attachment filenames. Outlook MSG parsing reads
the message's own compound-file storage instead of accidentally treating an
embedded message's properties as its parent's headers.

HTML message bodies retain basic formatting while removing active content,
links, external images, source CSS and resource attributes. It performs no remote
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
messages remain an identified limitation. MSG bodies stored in
`PidTagRtfCompressed` are decoded when no readable plain-text or HTML body exists.
The bounded decoder handles LZFu's initialized 4 KiB dictionary, overlapping
copies, wraparound, termination and CRC, plus MELA's uncompressed form. It follows
Microsoft's [MS-OXRTFCP specification](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxrtfcp/)
and feeds the same RTF reader used for standalone files. Corrupt or unsupported
RTF produces a localized explanation; resource violations fail the preview.
Existing readable plain/HTML bodies remain preferred. Unknown character encodings are approximated with a
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
Compressed RTF contents and decoded RTF bytes are capped at 8 MiB; the RTF
reader's separate 4 Mi UTF-16-code-unit text budget also applies.

## RTF and binary PowerPoint previews

The authored RTF reader preserves basic bold, italic, underline and strikeout
runs, paragraph alignment, explicit list markers and flat tables. Its formatted
HTML contains escaped document text and fixed formatting tags. It does not
execute fields, render embedded objects, load images or resolve external
resources. Headers/footers, page layout and other advanced RTF structures are
outside this preview. The source remains available through the existing text
editor. Bounds include 8 MiB input, 4 Mi UTF-16 text units, 128 group levels and
250,000 group/control tokens; unsupported code pages and malformed structures produce
typed, localized failures.

The binary PowerPoint reader follows `Current User`, the current edit/persist
directory, the document's current slide references and their drawing text. It
does not scan arbitrary compound-file bytes: older saves, removed slides,
masters, notes and embedded documents are excluded. This is a searchable text
preview, without slide layout, images, animation, notes or a binary-format
editor. Encrypted, unsupported and malformed inputs are rejected. Both new
readers use the existing bounded compound/archive infrastructure where needed
and add no package dependency. Details and authored compatibility fixtures are
recorded in [portable Office previews](portable-office-previews.md).

## Word documents and templates

Binary DOC/DOT extraction follows Microsoft's
[documented FIB/CLX text-retrieval algorithm](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/01d5d8c4-cf9c-4ef9-80fd-439e763cfe01).
It reads text in logical piece-table order, including compressed and UTF-16
pieces, and excludes unreferenced stream bytes. The preview does not reconstruct
formatting, images, headers, notes or tracked-change semantics. Encrypted files,
older pre-Word-97 variants and malformed structures produce a clear failure.
The main story is capped at 4 × 1024 × 1024 UTF-16 code units.

F4 on DOC/DOT, or **Convert to DOCX** in F3, offers detected Microsoft Word on
Windows or LibreOffice 7+ on Windows/Linux/macOS. Availability depends on the
installation and sandbox. **Text only (built in)** is an explicit choice on all
platforms and the only route on web/mobile. CrispCloud never installs an office
suite, silently falls back after a native failure, or sends content to a remote
conversion service.

Native conversion checks the resulting Word package, shows content counts and
potential losses, and requires acknowledgement of reported losses. DOCM is the
default when document VBA is detected; DOCX cannot contain it. These checks do
not certify formatting, object or signature fidelity. **Save copy** writes the
exact converter bytes as a new sibling on the captured original account, rejects
collisions, and opens the copy in F3; F4 editing is a separate action. Text-only
conversion instead creates `report (text).docx` and opens it in the rich editor,
omitting formatting, layout, images, objects, headers, notes, tracked-change
state, macros and signatures. Both routes preserve the original file and save
destination even if the pane navigates elsewhere. See
[legacy Word conversion](legacy-word-conversion.md) for platform limits, source
review, preservation warnings and acceptance evidence.

The review also offers **Preview pages** when the selected installed application
supports PDF export. It renders the prepared DOCX/DOCM with that same engine,
opens detached read-only PDF bytes, and leaves the prepared Word package intact.
This visual check supplements the package counts; editable objects, macros and
signature validity still need separate verification.

Word documents and templates use the already-vendored Word editor.
Before editing, the package's main content type must match its extension.
Before every upload, the preservation guard checks the original main-part path
and content type, opaque binary/VBA/custom-UI payload hashes, and protected VBA/OLE
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

KeePass uses a pinned, MIT-licensed vendored
[`KPassLib`](../packages/kpasslib/UPSTREAM.md), adapted to preserve the raw XML
tree and use the existing PointyCastle Argon2 implementation on native and
JavaScript targets. No native cryptography binaries are bundled.

The email, RTF, binary PowerPoint and Word additions require no new package. Compound-file parsing reuses
`CfbfFile` from the existing MIT-licensed
[`quds_office_engine`](../packages/quds_office_engine/LICENSE). MIME parsing,
resource checks and format routing are CrispCloud code. HTML parsing/rendering
uses existing dependencies. This avoids adding a native-only mail parser or a
new dependency with a different license merely to recognize these extensions.
The optional installed-application conversion adapters add no Office-engine
package dependency and bundle no third-party converter. The user's separately
installed Word/LibreOffice remains subject to its own license; see the
[conversion guide](legacy-word-conversion.md#installed-application-conversion).

## Verification

Focused regression suites include:

- `test/email_message_service_test.dart`: MIME/MSG decoding, mixed body sections,
  attachment naming, code pages, sanitization, and adversarial CFB graphs.
- `test/outlook_rtf_compression_test.dart`: Microsoft's published overlap/CRC
  vector, MELA rules, dictionary wrap, padding, corruption and expansion limits.
- `test/rtf_document_test.dart` and `test/legacy_powerpoint_document_test.dart`:
  bounded formatted RTF, active-slide references, stale/deleted content exclusion
  and malformed/encrypted structures.
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
- `test/keepass_service_test.dart`, `test/keepass_crypto_test.dart`,
  `test/widget/keepass_editor_dialog_test.dart` and
  `test/keepass_strings_test.dart`: interoperable encrypted database editing,
  lock/save behavior and localized controls.
- `test/legacy_word_conversion_test.dart`, `test/legacy_word_copy_target_test.dart`,
  `test/widget/legacy_word_conversion_dialog_test.dart` and
  `test/widget/keepass_word_routing_test.dart`: create-only conversion,
  source identity and the actual viewer/editor handoffs.
- `test/installed_office_converter_test.dart`,
  `test/word_conversion_inspection_test.dart`,
  `test/installed_office_strings_test.dart` and
  `test/widget/installed_office_conversion_dialog_test.dart`: native-process
  failure/cleanup, bounded package checks, source/VBA scope, localized controls,
  loss acknowledgement and exact-byte copy saving. The opt-in installed-engine
  fixture run and its limits are recorded in the conversion guide.

Macro fixtures contain synthetic opaque payloads. They establish preservation
and failure behavior, not macro execution or a Microsoft Word certification.

Before the installed-engine addition, the combined development validation run
passed 360 tests across 28 focused parser, archive, favorites, viewer, preview,
conversion and editor suites. A separate JavaScript
compilation and execution smoke check passed Unicode EML, MSG/CFB and legacy DOC
parsing. A full Flutter web release build was not run locally because the cached
SDK lacks the Flutter web target artifacts; the JavaScript parser check does not
replace that application build or platform acceptance testing. KeePass also
passes a separate JavaScript open/edit/save/reopen smoke run against public
KeePass-generated KDBX3/AES, KDBX4/Argon2id/AES and KDBX4/Argon2d/ChaCha20 fixtures.
The installed-conversion follow-up passed 72 unique tests across nine suites in
separate focused runs; the PR records the regression results and remaining
platform acceptance limits.
The last inner-header resource guard was followed by a passing 18-test KeePass
backend/crypto rerun, including excessive-attachment rejection.
