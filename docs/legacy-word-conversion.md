# Legacy Word viewing and conversion

Research and implementation review: 2026-11-12.

## Convert and review a separate copy

F4 on a binary `.doc`/`.dot`, or **Convert to DOCX** in F3, opens a conversion
dialog. It offers supported installed applications when their discovery probe
succeeds, **Structured DOCX (built in)** and an explicit **Text only (built in)**
choice. It never installs
an office suite or silently substitutes text-only output after a native failure.

For an installed converter, choose **Convert and review**, inspect the detected
content and any potential losses, then **Save copy**. If document-level VBA is
detected, DOCM is the default when supported by the selected engine. DOCX cannot
contain VBA. A filename such as `report (converted).docm` is proposed; saving
with reported losses requires explicit acknowledgement.

**Preview pages** renders the prepared DOCX/DOCM with the same installed engine
and opens the resulting PDF in a detached read-only viewer. No destination file
is created during preview, and the prepared Word bytes remain unchanged for
**Save copy**. A failed preview leaves that reviewed copy available for retry or
saving. The output-format selector remains DOCX/DOCM; PDF is a review surface.

This preview helps inspect page breaks, fonts, tables, images, headers and
footnotes as rendered by the selected engine. It does not verify editable-object
behavior, VBA, signatures, or equivalence to the original layout. Installed
fonts and engine settings affect the result. Word's PDF export includes markup;
LibreOffice renders using its imported document state and isolated profile.

The exact converter output bytes are saved as a new sibling on the original
captured storage account. The original and existing files are never replaced.
A collision or provider error leaves the dialog open for a new name/retry;
changing the invoking pane's directory cannot redirect the write. A native
converted copy opens in the **F3 viewer first**. **F4/Edit** is a separate action
that opens the rich editor with that new file's captured save target. Viewing
does not deserialize and rewrite the converter's package.

Archive members and detached attachments remain view-only: extract them to a
writable location before converting. No remote conversion service receives
document content; an installed engine receives only a temporary input copy.

## Built-in structured conversion

**Structured DOCX (built in)** reads supported binary Word structure in Dart
and creates a separate, editable DOCX without an installed office application.
It uses the same captured source and create-only save target as the existing
conversion flow. The original DOC/DOT is not rewritten.

Choose **Convert and review** to inspect the generated package counts and
source-feature losses. The structured path always requires acknowledgement of
its partial support before **Save copy**, even when no detector-specific loss
is present. A save collision permits a new filename and retry with the exact
same prepared bytes. The copy opens in the F3 viewer before optional editing.
PDF page preview remains available for installed engines only.

Supported main-story data is emitted as WordprocessingML rather than flattened
into text:

- resolved character formatting: bold, italic, underline, strike/double-strike,
  case effects, hidden state, font name/size, color/highlight, vertical position
  and character spacing;
- paragraph style names, outline levels, alignment, indents, before/after and
  line spacing, keep settings and page-break-before;
- basic table rows/cells, widths, horizontal/vertical merge markers and explicit
  header-row flags;
- page size/orientation, margins, gutter, header/footer distances, columns and
  supported section-break positions;
- tabs, manual line breaks and page breaks as distinct elements;
- supported tracked insertions/deletions as `w:ins`/`w:del` with deleted text
  stored in `w:delText`, retaining available author/time metadata. These changes
  are not automatically accepted. DOC timestamps have no timezone; emitted dates
  retain the recorded wall-clock fields without inventing a UTC offset.

The parser follows logical CLX character positions through the selected text
pieces, then resolves paragraph/character formatting pages, stylesheet
inheritance and piece properties. It does not assume that physical text order
is document order. Built-in DOC/DOT previews use generated escaped HTML from
the same model, hide hidden runs and visibly mark supported insertions/deletions.

This is partial preservation. Images, floating drawings, embedded objects,
text boxes, headers/footers, notes, comments, VBA and signatures are not imported
into this DOCX. Numbering definitions, complex/nested tables, borders/shading,
some script-specific formatting and full revision semantics remain incomplete.
Fields use stored results without copying executable instructions. The review
lists the relevant detected categories, and the source inspector independently
reports missing source features. Neither the absence of a detector warning nor
an emitted property proves identical pagination or visual appearance.

The existing 4 Mi UTF-16-code-unit body limit applies. Structured serialization
bounds XML expansion while writing (16 MiB across document/style XML) and limits
paragraphs, table structure, tabs and breaks before unbounded allocation.
Malformed supported structures fail explicitly; there is no automatic retry
through text-only conversion or raw-byte recovery.

See the [pinned parser-source review](legacy-word-parser-research-2026-11-12.md)
for `legacy-doc-recover`, `wps2md` and `JSDoc`, their permissive licenses, useful
algorithms and the shortcuts deliberately excluded from ordinary conversion.

## Built-in text-only conversion

`convertLegacyWordToDocx` creates a new DOCX from the existing bounded binary
Word text extractor. It does not modify the source DOC/DOT and does not import
its compound-file streams into the output package. The result contains ordinary
WordprocessingML paragraphs, text and tab elements, and can be edited with the
existing rich Word editor.

The explicit text-only choice says **Create text-only DOCX**, proposes a separate
`<name> (text).docx` filename, and describes the losses before conversion. This
copy opens directly in the rich editor after saving. Its
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
DOCX. This built-in path calls no macro interpreter, external process or remote
conversion service.

## Review of the suggested projects

The repository licenses and actual implementation files were read through the
GitHub connector, not inferred from their feature lists.

| Project | Reviewed revision | Actual legacy DOC implementation | Decision |
| --- | --- | --- | --- |
| `Destiny-Ed/doc_text_extractor` | `a129b73cd8a65e89d8a96908415c79ca0d5f6c41` | Loops over every input byte, retaining ASCII values 32–126 and some newlines; the isolate follows the same algorithm | Retain CrispCloud's structured Word parser; no dependency added |
| `cosmojg/doc2docx` | `448d7349c14358ab40899768f004f657c4262789` | Uses Windows COM or macOS JXA to ask an installed Microsoft Word application to open and save the document | Reference for the installed-engine approach; CrispCloud implements its own constrained adapter, not a port of a portable DOC parser |

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

Neither inspected open path explicitly disables macro execution. CrispCloud's
separate Windows adapter sets and checks
[`AutomationSecurity` to `msoAutomationSecurityForceDisable`](https://learn.microsoft.com/en-us/office/vba/api/word.application.automationsecurity)
before opening documents and restores application settings during cleanup. The
inspected wrapper was not copied into CrispCloud.

## Installed-application conversion

The implemented adapters let an installed office engine attempt to preserve
formatting, layout and non-body content. Availability and preservation depend
on the installation, operating system and document; a successful probe is not
proof that a sandbox will permit conversion.

| Route | Platforms offered | Implementation boundary |
| --- | --- | --- |
| Microsoft Word | Windows, after a `Word.Application` registration probe | COM automation of an isolated new Word instance; close existing Word instances before conversion. Windows Word acceptance has not been run in this development environment. |
| LibreOffice 7 or later | Windows, Linux and macOS, when the executable/version probe succeeds | Discovers PATH/common installation locations and uses headless conversion with a fresh private profile. macOS sandbox restrictions may still prevent launch or conversion. |
| Structured DOCX | Desktop, web, Android and iOS | Uses the bounded Dart structured parser and OOXML writer with mandatory partial-preservation review. Web/mobile have no installed-engine adapter. |
| Text only | Desktop, web, Android and iOS | Uses the bounded Dart parser and OOXML writer with the explicit losses above. Web/mobile have no installed-engine adapter. |

Word for macOS is deliberately not offered: this implementation has no verified
per-open macro-control and sandbox-automation path for it. Installing Word on a
Mac does not enable the Windows COM adapter.

LibreOffice documents
[headless conversion and isolated user-profile parameters](https://help.libreoffice.org/latest/en-GB/text/shared/guide/start_parameters.html).
The adapter also supplies an isolated security profile: macro execution is
disabled, links/fields/charts are not refreshed, and imported VBA storage is
retained opaquely rather than translated into executable LibreOffice Basic.
The reviewed settings come from LibreOffice's
[Common schema](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/officecfg/registry/schema/org/openoffice/Office/Common.xcs)
and [Writer schema](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/officecfg/registry/schema/org/openoffice/Office/Writer.xcs).
Headless mode alone would not establish those settings. This implementation uses
the documented [command-line conversion filters](https://help.libreoffice.org/latest/en-US/text/shared/guide/convertfilters.html)
and profile, not a per-open UNO client.

Word automation sets `AutomationSecurity` before `Documents.Open`, disables
automatic link updates and uses a read-only input copy. It refuses an existing
Word process or uncertain automation ownership. Microsoft documents Word's
[separate-instance COM behavior](https://learn.microsoft.com/en-us/previous-versions/office/troubleshoot/office-developer/use-visual-c-automate-run-program-instance);
the adapter also checks ownership before opening the source. An activation timeout before
the new process can be identified can leave an empty Word instance untouched;
the adapter reports failure and has not opened the source at that stage.

Both adapters use an owned temporary workspace and a two-minute default
conversion timeout. Linux/macOS run the converter in a dedicated process group
and stop its descendants on timeout or launcher exit. Temporary data is removed
on completion/failure; cleanup failure is reported. These controls are not an
operating-system sandbox or proof that every external application's behavior is
contained. Process arguments and request files keep document names out of
executable script text.

PDF review uses LibreOffice's documented
[`writer_pdf_Export` filter](https://help.libreoffice.org/latest/en-GB/text/shared/guide/pdf_params.html)
or Word's [`ExportAsFixedFormat`](https://learn.microsoft.com/en-us/office/vba/api/word.document.exportasfixedformat).
Word receives `wdExportDocumentWithMarkup` and retains the IRM/label option;
export never opens the result in another external app. The same macro/link
policy, process ownership, timeout, size limits and cleanup apply. PDF input
is restricted to validated binary DOC/DOT or inspected DOCX/DOCM packages.

LibreOffice is available under [MPL 2.0 with additional component licenses](https://www.libreoffice.org/licenses/).
No third-party converter is bundled or downloaded. Microsoft Word remains the
user's separately installed/licensed application, and invoking LibreOffice does
not relicense its engine as a permissive Dart library. CrispCloud's adapter code
adds no Office-engine package dependency.

## Package checks and preservation evidence

Before saving, the inspector checks a real DOCX/DOCM Word main-part content type,
strict/transitional namespaces, ZIP member CRCs and sizes, and internal
relationship targets/owners. It rejects malformed, dangling or escaping
relationships and XML DTDs. External relationships remain in the package; the
inspector does not fetch their targets. It does not sanitize or normalize the
converter's output bytes.

The review lists emitted paragraphs, sections, tables/cells, images, OLE parts,
headers/footers, notes, comments, revision records, VBA and signature markers.
Source Word story tables identify selected features; header detection excludes
the first six separator stories in `PlcfHdd`. Document VBA is compared with the
main document's linked VBA project, not an embedded object's project. Missing
source features or changed VBA streams produce warnings that must be accepted
before saving. The absence of a warning is **not** a fidelity certificate:
counts do not establish identical text, layout, rendering or object behavior.

Conversion changes the document. Keep the original and verify or re-sign any
converted copy in the appropriate application. Preserved signature bytes or
signature markers do not prove that a signature remains valid. Further F4
editing uses the existing [Word preservation guards](file-format-viewers.md#word-documents-and-templates)
and [Office support limits](office-formatting-support.md).

| Native conversion/inspection limit | Value |
| --- | --- |
| Source / returned output | 64 MiB each |
| Total expanded package | 128 MiB |
| Package entries | 4,096 |
| Individual parsed XML part | 16 MiB |
| XML events / nesting depth | 800,000 across parsed parts / 128 |
| Default conversion timeout | 2 minutes |

The built-in text-only limits remain separate, as described above.

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

Before the installed-engine addition, the combined run passed 360 tests across
28 suites. Its text-only F4 workflow
test changes the invoking pane's directory while the conversion dialog is open,
then verifies that the original DOC is unchanged, the new DOCX is beside that
original, and the new file opens in `QudsWordEditor` with its captured save target.

The installed-engine work adds process/error/cleanup tests in
`test/installed_office_converter_test.dart`, 21 passing inspection regressions in
`test/word_conversion_inspection_test.dart`, localized controls, and native-review
UI tests in `test/widget/installed_office_conversion_dialog_test.dart`. These
checks include malformed packages, source/VBA scope and exact-byte copy saving;
the follow-up validation passed 72 unique tests across nine suites in separate
focused runs. This was not a single combined test run. The PR records the
regression results and platform acceptance limits.

The opt-in `tool/verify_installed_office_converter.dart` acceptance run passed
with **LibreOfficeDev 26.8.0.0.alpha0** for both DOCX and DOCM. Its
[authored fixture](../test/fixtures/word_native/README.md) was exported to binary
DOC by LibreOffice and contains Unicode text, bold/italic formatting, a table,
an image, a header, a footer and a footnote. The production converter and
inspector retained those tested structures/text and left the source hash
unchanged. This fixture contains no VBA, signatures, OLE objects or tracked
changes, so the run establishes no preservation result for those features and
no visual/pagination equivalence. Windows Word and sandboxed macOS conversions
still need platform acceptance testing.

The page-preview follow-up passed 26 tests across the native backend, conversion
dialogs and nine-language controls. It additionally ran the acceptance tool
with `--verify-pdf-tools` against that installed LibreOffice: both DOCX and DOCM
produced accepted PDF previews; independent `pdfinfo`/`pdftotext` checks found
pages, table text, header, footer and footnote. The Word package hashes remained
unchanged by preview. These checks establish valid readable previews of the
fixture, not pixel or pagination equivalence for arbitrary documents.

The separate [document-viewer evaluation](document-viewer-evaluation.md) retains
the source/license findings for other suggested packages; those viewers were
not imported to implement this conversion path.

### Structured DOC parser and DOCX follow-up

The 2026-11-12 structured-parser work passed a focused **56-test** run covering
independently constructed binary DOC fixtures, property inheritance and ordering,
resource bounds, escaped preview rendering, structured DOCX serialization and
the existing text-only converter. The final converter-only run passed **9 tests**
after adding blank-document and timezone-free revision-date cases; it overlaps
the earlier run. A mixed UI/localization/regression run passed **38 tests**,
including mandatory partial-support acknowledgement, immutable-byte save retries,
nine-language controls and formatted DOC/DOT routing. The final extended-viewer
suite passed **11 tests**, including hidden-text exclusion from preview search.
These counts describe focused, overlapping development runs, not one whole-app
test run.

Final static checks passed for all 26 Dart files touched by this DOC extension;
all 157 changed Dart files on the feature branch passed the formatting check.
Hosted CI results are reported separately on the PR.

`tool/verify_legacy_word_structured.dart` converted the authored binary DOC with
the production built-in converter, inspected the emitted package independently,
and asked installed LibreOffice to open the resulting DOCX and render a PDF.
All **12 acceptance checks** passed: table/cell structure, bold, font size/color,
page dimensions, explicit image/header/note omissions, independent `pdfinfo` and
`pdftotext` results, and unchanged source/prepared-package hashes. The output
contained nine paragraphs, one section, one table and four cells. This fixture
contains no tracked changes, so revision coverage comes from the independent
binary fixtures and emitted-XML checks; the acceptance run is not a universal
visual, pagination or Microsoft Word interoperability guarantee.

The same authored DOC also passed the production parser compiled to JavaScript
and executed under Node through `tool/verify_portable_office_web.py`, checking
Unicode, formatting, tables and sections alongside the existing RTF/PPT/MSG
cases. A full Flutter web/browser run, Windows Word acceptance and full Open XML
schema validation remain separate checks. The converted DOCX is never described
as preserving omitted objects, macro code or valid signatures.
