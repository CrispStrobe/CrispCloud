# Structured DOCX and DOCM conversion

The conversion API creates an independent Word package from the bounded parsed
model. It does not modify the source, launch an application, evaluate fields,
resolve external links, run macros, or activate embedded objects during
conversion. The package writer uses `archive`; it has no Flutter, Quds, browser,
or installed-office dependency.

```dart
import 'dart:typed_data';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';

LegacyWordStructuredConversion docxCopy(Uint8List source) =>
    convertLegacyWordToStructuredDocx(source);

LegacyWordStructuredConversion docmCopy(Uint8List source) =>
    convertLegacyWord(source, format: LegacyWordOutputFormat.docm);

LegacyWordStructuredConversion convertParsed(LegacyWordDocument document) =>
    convertLegacyWordDocument(document);
```

`convertLegacyWordToStructuredDocx` retains the original macro-free entry point.
`convertLegacyWord` defaults to DOCX; DOCM requires the explicit format argument.
`convertLegacyWordDocument` serializes an already parsed model with the same
bounds and preservation rules. `convertLegacyWordToDocx` remains the separate,
explicit text-only converter.

The result contains independent, immutable `bytes`, `limitations`,
`preservedCounts`, `format`, `extension`, and `signatureEvidenceParts` values.
`signatureValidityClaimed` is always false. Counts describe content emitted into
the converted package, including relevant auxiliary parts; they do not measure
complete fidelity to the original file.

## Emitted document structure

| Source content | Converted representation | Remaining qualifications |
| --- | --- | --- |
| Main paragraphs and runs | Editable WordprocessingML with resolved paragraph and character properties | Unsupported formatting is reported; no complete layout claim |
| Insertions and deletions | `w:ins`, `w:del`, and deleted text nodes with available author/date metadata | Source wall-clock dates have no invented time zone |
| Hidden text | `w:vanish` on retained runs | Private field results are excluded from ordinary display content |
| Basic tables | Table grids, widths, cells, supported merges, and header rows | Unsupported nested structures remain a declared limitation |
| Sections | Source section boundaries, page dimensions, margins, columns, and supported break types | Exact pagination is not certified |
| Headers and footers | Separate parts and section relationships, including first/even/default variants | First/even activation follows the source flags, not merely the presence of stored content |
| Footnotes and endnotes | Reference markers, note parts, and available separator stories | Hidden/private anchors produce inert story evidence instead of active notes |
| Comments | Anchors/ranges and a comments part with text, author, initials, and available date | Reply/ink metadata is retained in evidence; threaded/ink markup is not reconstructed |
| Bookmarks | Actual range markers with names and available table-column bounds | A boundary inside field instructions/private results stays inert |
| Numbering | Numbering definitions, formats, marker text/styles, start/restart rules, and paragraph references | Cross-instance sequence continuation remains limited when the parser reports it |
| Reference, TOC, page, and other supported fields | Locked complex fields, original instruction syntax, and stored results | No update or evaluation is performed; automatic field updating is disabled |
| Nested fields | Typed nested field markup in instructions, with bounded cached-result reconstruction | Unsupported nested instructions keep the containing field inert |
| External or unsupported active fields | Stored display results plus original field metadata in evidence | DDE, external include/link instructions, and other unsupported field types are not activated |
| Referenced PNG, JPEG, TIFF | Exact image bytes, part relationships, inline/anchored DrawingML, source size and crop where available | Arbitrary shape effects, rotations, polygons, and geometry are not reconstructed |
| Textboxes | Editable VML textboxes at validated anchors; linked chains use actual shape links and retain the story once | Exact text reflow, OfficeArt shape styling, and wrap geometry remain partial |
| Verified embedded OLE | Reconstructed compound storage in an embedded-object part, with exact stream bytes and preserved directory metadata | Only positively identified, nonlinked, eligible objects are active; icon/preview layout is approximate |
| Complete VBA project | Active VBA part only for explicit DOCM and one structurally complete project | Structural completeness is not compilation, trust, or execution validation |
| Source signatures | Inert binary evidence and manifest entries | No signature relation is activated and no validity is claimed |

Stored picture names are descriptive metadata. A valid referenced, stored image
can be used without fetching the name or URL. Opaque and unreferenced assets are
retained as evidence. OfficeArt shapes marked deleted stay inactive, separately
from the tracked insertion/deletion state of a character run.

The converter preserves hidden and tracked-change presentation on eligible
media and reference markers. An image, object, note, comment, or textbox anchored
inside field instructions or a private cached result is not made into ordinary
visible content. Notes and comments with hidden/private anchors remain available
only through inert evidence parts.

## VBA and signatures

DOCX output has a macro-free main content type and no active VBA project
relationship. Original VBA bytes can remain in an inert binary evidence part.
For explicit DOCM, one project with the required project streams can be copied
to `word/vbaProject.bin`. Incomplete or ambiguous projects remain inert.

Reconstructed CFB objects and VBA projects preserve stream content and storage
metadata. CFB allocation and directory layout change, so a reconstructed CFB is
not described as the original complete container byte sequence.

Original document and VBA signatures do not authenticate a converted package.
The writer never creates active OPC digital-signature or VBA-signature
relationships from those source payloads. `signatureEvidenceParts` identifies
the retained inert bytes. Keep the original document and verify or sign the new
copy separately when signatures matter.

## Evidence and limitations

When needed, `word/evidence/manifest.json` describes retained artifacts, source
stream references, unsupported field metadata, inactive content, and signature
scope. Generic library-specific evidence relationships make these parts
reachable without giving them executable or signature semantics. Package paths
are generated by the writer; source names never become ZIP paths. Relationships
are internal and their targets are checked before encoding.

Every structured result includes `partialFormatting`. Additional categories
describe unresolved or inactive images, objects, stories, revision metadata,
macros/signatures, and fields/lists. Successfully emitted headers, notes, or
images do not automatically receive the former blanket omission warning.
Residual parser warnings and occurrence-specific media notices remain relevant.
Callers should show the limitations and require an explicit review before
saving a converted copy. The package API itself does not select a destination
or overwrite a source.

## Bounds and verification

Generated XML is capped at 16 MiB across document and package metadata parts.
Evidence JSON is encoded incrementally with a 16 MiB bound. Total uncompressed
package payload and the final ZIP are each capped at 64 MiB. Parts,
relationships, inline events, nesting, and structural expansion have additional
limits. Exceeding a conversion limit throws `LegacyWordConversionException`
with `LegacyWordConversionIssue.tooComplex`; malformed source/model references
are rejected rather than silently moved to a different location.

The focused conversion tests cover:

- A real authored DOC fixture with resolved formatting, tables, a referenced
  image, a header, and a footnote.
- Source-byte preservation, deterministic ZIP output, immutable results,
  Unicode/XML escaping, section placement, and bounded expansion.
- Declared content types, parsable XML, resolving internal relationships, and
  the absence of external package relationships.
- Actual header/note/comment/numbering/bookmark/field/media/textbox structures,
  including hidden/private and tracked-change cases.
- Exact stored image and reconstructed OLE/VBA bytes, DOCX versus explicit DOCM,
  and signatures retained solely as inert evidence.

Structural verification is not a claim of pixel-identical rendering in Word or
another office application. Review the converted copy in the application that
will be used for editing or publication.

## Source files and format references

The implementation is in `lib/src/conversion.dart`,
`legacy_word_structured_conversion.dart`, `word_story_writer.dart`,
`word_media_writer.dart`, and `opc_package_writer.dart`. Tests are in
`test/legacy_word_structured_conversion_test.dart` and
`test/extended_conversion_test.dart`. Media parsing details and source-format
references are documented in [media-preservation.md](media-preservation.md).

The WordprocessingML and package structures follow the Open XML formats:

- [ECMA-376 Office Open XML file formats](https://ecma-international.org/publications-and-standards/standards/ecma-376/)
- [Microsoft MS-DOC specification](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/ccd7b486-7881-484c-a137-51170af7cc22)
- [Microsoft OfficeArt specification](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/8560795e-7759-4745-838f-f7f2ef2f1872)
