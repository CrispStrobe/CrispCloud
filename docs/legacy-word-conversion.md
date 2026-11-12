# Legacy Word viewing and conversion

Research and implementation review: 2026-11-12.

## Implemented conversion

`convertLegacyWordToDocx` creates a new DOCX from the existing bounded binary
Word text extractor. It does not modify the source DOC/DOT and does not import
its compound-file streams into the output package. The result contains ordinary
WordprocessingML paragraphs, text and tab elements, and can be edited with the
existing rich Word editor.

The conversion dialog says **Create text-only DOCX**, proposes a separate
`<name> (text).docx` filename, and describes the losses before conversion. Its
optional host save callback keeps the dialog open after a filename collision or
provider error, allowing a different name and retry. The host owns the captured
storage source and create-new save operation. The converter never chooses a
destination from the active pane or accepts user-supplied directory paths.

Preserved from the extracted main story:

- Unicode text, including surrogate pairs and XML-sensitive characters;
- paragraph boundaries, interior blank paragraphs and tabs;
- field result text already selected by the binary Word text parser.

Not reconstructed: original formatting, page layout, images, embedded objects,
headers/footers, footnotes/endnotes, comments, tracked-change state, macros or
signatures. Table cells become tab-separated text. Paragraph, line and page
break distinctions have already been normalized by the text extractor. The
conversion is not an assertion that tracked changes have been accepted or that
text hidden by Word formatting is excluded.

The existing parser reads Word 97–2007 binary FIB/CLX piece tables, including
Word 97–2003 `.doc` files. It reads logical character positions rather than
scanning every stream for printable bytes. It rejects encrypted input and
unsupported older binary variants. See Microsoft's
[text-retrieval algorithm](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/01d5d8c4-cf9c-4ef9-80fd-439e763cfe01).

The parser's 4 Mi UTF-16-code-unit main-story limit still applies. Conversion
also checks the estimated XML byte budget (16 MiB) and a combined limit of
100,000 paragraph/tab breaks before splitting text or allocating XML structures.
Illegal XML Unicode characters fail conversion rather than creating a corrupt
DOCX. No macro interpreter, external process or remote conversion service is
called.

## Review of the suggested projects

The repository licenses and actual implementation files were read through the
GitHub connector, not inferred from their feature lists.

| Project | Reviewed revision | Actual legacy DOC implementation | Decision |
| --- | --- | --- | --- |
| `Destiny-Ed/doc_text_extractor` | `a129b73cd8a65e89d8a96908415c79ca0d5f6c41` | Loops over every input byte, retaining ASCII values 32–126 and some newlines; the isolate follows the same algorithm | Retain CrispCloud's structured Word parser; no dependency added |
| `cosmojg/doc2docx` | `448d7349c14358ab40899768f004f657c4262789` | Uses Windows COM or macOS JXA to ask an installed Microsoft Word application to open and save the document | A useful model for an optional desktop adapter, not a portable DOC parser to translate into Dart or Rust |

### `doc_text_extractor`

The repository's [license is MIT](https://github.com/Destiny-Ed/doc_text_extractor/blob/a129b73cd8a65e89d8a96908415c79ca0d5f6c41/LICENSE).
Its [DOC parser](https://github.com/Destiny-Ed/doc_text_extractor/blob/a129b73cd8a65e89d8a96908415c79ca0d5f6c41/lib/src/text_parsers/doc_parser.dart)
and [isolate implementation](https://github.com/Destiny-Ed/doc_text_extractor/blob/a129b73cd8a65e89d8a96908415c79ca0d5f6c41/lib/src/isolates/doc_isolate.dart)
do not interpret CFB storage, the Word FIB or the piece table. Consequently,
non-ASCII characters cannot be decoded correctly. Our assessment from the code
is that scanning the entire file can also include printable metadata, stale
text and unrelated embedded-object bytes, and does not establish the logical
order of the main story.

The package's [dependency list](https://github.com/Destiny-Ed/doc_text_extractor/blob/a129b73cd8a65e89d8a96908415c79ca0d5f6c41/pubspec.yaml)
includes `syncfusion_flutter_pdf`. That dependency has a separate
[commercial/community license](https://pub.dev/packages/syncfusion_flutter_pdf/license),
not an MIT/Apache/BSD license. An MIT wrapper does not change its dependencies'
terms. Neither this dependency nor source from the suggested extractor was
incorporated.

### `doc2docx`

The [MIT license](https://github.com/cosmojg/doc2docx/blob/448d7349c14358ab40899768f004f657c4262789/LICENSE)
permits reuse with the required notices. The
[Python implementation](https://github.com/cosmojg/doc2docx/blob/448d7349c14358ab40899768f004f657c4262789/doc2docx/__init__.py)
dispatches to `Word.Application` COM automation on Windows and invokes
`/usr/bin/osascript` on macOS. The
[JXA script](https://github.com/cosmojg/doc2docx/blob/448d7349c14358ab40899768f004f657c4262789/doc2docx/convert.jxa)
opens Microsoft Word documents and calls `saveAs`. The Linux branch explicitly
raises an unsupported-operation error.

A Dart or Rust port of that wrapper would still require Microsoft Word, its
platform automation interface and the user's installation/license. It would not
make DOC conversion run in a browser, on Android/iOS, or on Linux. A standalone
format-preserving binary DOC importer would be a separate format implementation,
including styles, lists, tables, section layout, images, objects and revisions;
the repository does not supply those algorithms.

Neither inspected open path explicitly disables macro execution. A future
Word automation adapter must set
[`AutomationSecurity` to `msoAutomationSecurityForceDisable`](https://learn.microsoft.com/en-us/office/vba/api/word.application.automationsecurity)
before opening documents, then restore application settings. The existing
wrapper was not copied into CrispCloud.

## Optional installed-application conversion

For documents where layout and non-body content matter, an installed Word or
LibreOffice converter is the practical next step. This remains a proposed
desktop capability; no native automation adapter is included in this change.

| Route | Practical availability | Implementation boundary |
| --- | --- | --- |
| Word automation | Installed Microsoft Word on Windows/macOS | Resolve the application through COM/OS automation; do not assume a fixed executable path. Requires platform acceptance testing and explicit macro-disable handling. |
| LibreOffice | A separately installed desktop `soffice` executable | Resolve a configured/PATH executable or a validated application installation. Run against a temporary copy with an isolated profile; import with macros and external updates disabled; create a new output file. |
| Portable text conversion | Every CrispCloud platform supported by the existing Dart parser and OOXML writer | The implemented route. No installed office suite, network call or extra library is required; formatting losses are explicit. |

LibreOffice documents
[headless conversion and isolated user-profile parameters](https://help.libreoffice.org/latest/en-GB/text/shared/guide/start_parameters.html).
Headless mode alone is not a macro-security policy. An adapter should use the
document-load API's
[`MacroExecMode.NEVER_EXECUTE`](https://api.libreoffice.org/docs/idl/ref/namespacecom_1_1sun_1_1star_1_1document_1_1MacroExecMode.html),
disable link updates, use a bounded timeout, validate the output package and
clean up temporary input/output data. It must never overwrite the original or
silently fall back from a requested layout-preserving conversion to text-only.

LibreOffice is available under [MPL 2.0 with additional component licenses](https://www.libreoffice.org/licenses/).
Bundling it would be a separate packaging and license decision; invoking a
user-installed executable does not make its engine a new permissively licensed
Dart library. The development environment exposes a `soffice` launcher, but
that says nothing about its availability on an end user's device. No Word
automation or LibreOffice conversion acceptance run was performed for this
feature.

## Verification

`test/legacy_word_conversion_test.dart` covers Unicode and XML escaping, blank
paragraphs, tabs, editing and reopening the generated DOCX, absence of original
opaque/macro streams, unchanged input bytes, encrypted/malformed/invalid-text
rejection, structural expansion limits, names and all nine UI languages.

`test/widget/legacy_word_conversion_dialog_test.dart` covers the loss disclosure,
filename validation, conversion result, translated cancellation and host save
failure followed by a renamed retry. These suites passed together with the
captured create-only target tests, which verify sibling placement, retention of
the original, collision rejection, path validation and disconnected-source
rejection. Broader viewer/editor integration results are recorded in the PR.

The final combined run passed 360 tests across 28 suites. Its real F4 workflow
test changes the invoking pane's directory while the conversion dialog is open,
then verifies that the original DOC is unchanged, the new DOCX is beside that
original, and the new file opens in `QudsWordEditor` with its captured save target.
