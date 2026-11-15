# legacy_doc_parser

A portable Dart library for reading supported Word 97–2003 binary `.doc` and `.dot` files,
producing a structured document model and safe previews, and converting a
separate copy to DOCX or explicitly requested DOCM. The package runs on the Dart
VM and in JavaScript builds without Flutter, installed Office or a network
service.

The codebase currently supports:

- Content-based identification of legacy Word, RTF and other supported container
  signatures, independent of the filename; accepted Word 98 Mac version markers.
- Word 6.0/95 main-text import and opt-in text recovery from damaged compound
  directories. These paths are deliberately text-only: they do not claim the
  rich formatting, stories or layout of the structured Word 97+ importer.

- Main text, sections, headers, footers, footnotes, endnotes, comments and
  bookmarks, with original UTF-16 character positions retained in the model.
- Supported character and paragraph styles, independent script font slots,
  tabs, borders, shading, numbering,
  list continuation, section/gutter direction and explicit manual-break
  justification compatibility settings.
- Nested tables, supported cell merges and conditional table styles, row
  properties, and modeled floating-table anchors. Source note endings are
  preserved without adding layout-changing paragraphs after final tables.
- Supported tracked insertions/deletions and formatting histories. Field
  instructions and stored results are preserved, including bounded internal
  hyperlink fields; fields are not evaluated.
- Supported raster images, bounded EMF/WMF preservation and vector previews,
  basic editable OfficeArt shapes and paths, explicit drawing wrap clearances,
  and corroborated textbox chains and independent header/footer instances.
  Explicit simple textbox borders retain their source anchors while bounded
  DOCX frame conversion accounts for their outer border extent; see the
  [frame contract](doc/textbox-frame-borders.md). Qualified textbox paint includes
  source-valued opacity, dashes, simple shadows, scaled gradients and embedded
  picture/texture/monochrome-pattern fills.
- Bounded nonempty ISF stroke inspection with original packet coordinates,
  source transforms, pressure ranges and pen attributes, independently checked
  against actual Windows WPF. Raw ink remains retained; Word-native ink
  placement, rendering and editing are not inferred from decoded packets. See
  [supported ink inspection and limits](doc/ink-decoding.md).
- Structured DOCX conversion, safe HTML and plain-text extraction, and explicit
  DOCM output that can retain one structurally complete VBA project. Embedded
  objects, macros and signature evidence are retained only within the documented
  conversion contracts; the library never executes them.
- Canonical built-in style names in generated DOCX, independent of source UI language.
- Opt-in recovery for damaged auxiliary features, including contradictory comments
  or bookmarks, with explicit diagnostics for
  degraded output; strict parsing remains the default.
- Explicit warnings, conversion limitations and preservation counts, so callers
  can distinguish supported output, recovered structures and retained evidence.

The library is under active development. These areas remain incomplete or need
further qualification:

- Exact Word pagination and rendering across fonts, shaping engines, table and
  floating-object layouts, wrapping, and compatibility settings. Valid OOXML
  and matching extracted text do not establish identical native layout.
- Arbitrary drawing groups, presets, transforms, effects, GDI text/bitmap/clipping
  operations, and unmodeled metafile records. Unsupported preview operations do
  not silently disappear into a claimed complete rendering.
- Every revision, move, table-topology and cross-story combination; resolved
  comment state and editable ink; general field evaluation and broader style
  semantics. Unsupported or ambiguous cases remain diagnosed or rejected.
- Lossless preservation of every legacy binary feature through conversion.
  Conversion produces a new package, not a binary `.doc` round trip. A binary
  DOC writer and encrypted/password-protected DOC input are not supported.
- Signature validation or preservation of signature validity after conversion.
  `signatureValidityClaimed` is always false.

Remaining work prioritizes independently checked native layout, broader bounded
format coverage, revision and drawing semantics, and a stable published API.
The [fidelity status](doc/fidelity-status.md) gives the supported contracts and
open gaps; the [oracle guide](doc/fidelity-oracles.md) explains how schema,
semantic and native-rendering checks differ.
Current property and ownership contracts include bounded section geometry, cell
shading, embedded-object operands, heading levels, bookmark/story boundaries,
and textbox identities and chains. The [current audit](doc/parser-audit-20261114-followup.md)
and [external corpus coverage](doc/external-property-compatibility-20261114.md)
record independent evidence and remaining compatibility gaps. Passing semantic
or schema checks does not establish identical native Word rendering.

Use Dart 3.8 or later. `archive` is the runtime package dependency. A development
Git dependency can be configured as follows; pin a reviewed full commit SHA
instead of `main` for reproducible consumer builds and retain the lockfile.

```yaml
dependencies:
  legacy_doc_parser:
    git:
      url: https://github.com/CrispStrobe/legacy-doc-parser
      ref: main
```

```dart
import 'dart:typed_data';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';

void inspectAndConvert(Uint8List source) {
  final document = parseLegacyWordDocument(source);
  print(document.plainText);
  print(document.warnings);

  final copy = convertLegacyWordToStructuredDocx(source);
  print(copy.limitations);
  // Save copy.bytes to a new .docx file; the source bytes are never modified.
}
```

`convertLegacyWordDocument` accepts an already parsed document. For explicit
macro-capable output, use
`convertLegacyWord(source, format: LegacyWordOutputFormat.docm)` and inspect the
reported limitations. `extractLegacyWordText` and `convertLegacyWordToDocx` are
text-only APIs; they do not provide structured conversion fidelity.

The [CLI example](example/legacy_doc_parser_example.dart) prints a summary or
writes a separate output, refusing to overwrite an existing destination:

```sh
dart run example/legacy_doc_parser_example.dart input.doc
dart run example/legacy_doc_parser_example.dart input.doc new-copy.docx
dart run example/legacy_doc_parser_example.dart input.doc new-copy.docm
```

Run the portable acceptance checks with:

```sh
dart pub get
dart format --output=none --set-exit-if-changed lib test tool example
dart analyze
dart test
python3 tool/verify_web.py
python3 -m unittest discover -s tool/fidelity -p 'test_*.py'
```

CI also runs a source-built independent Open XML SDK validator with an exact
corpus and positive/negative controls. Native rendering needs an installed
Office application and its own retained evidence. Consumer pins are maintained
by [Quds](https://github.com/CrispStrobe/quds_office_suite) and
[CrispCloud](https://github.com/CrispStrobe/CrispCloud).

License: [Mozilla Public License 2.0](LICENSE). Third-party components and
fixtures retain their applicable MIT, 0BSD and other notices; see
[NOTICE](NOTICE) and [third_party](third_party/).

## Bounded text recovery

`convertLegacyWord(source, recover: true)` may return a text-only DOCX when
structured conversion fails but an independently bounded main-body piece table
or supported Word 6/95 text profile can still be read. Check
`recoveredTextOnly` and present all reported limitations before saving a copy.
This fallback does not preserve formatting, pictures, auxiliary stories,
macros or signatures; DOCM and template conversion still require structured
parsing. Encrypted/obfuscated Word97+ input remains refused.

`recoverLegacyWordText` admits at most 64 MiB of input, a 32 MiB referenced
stream extent, a 16 MiB CLX and 4 Mi main-body UTF-16 units. Across candidate
attempts it admits at most 4096 candidates, 64 MiB of chain/CLX work and 8 Mi
declared character units, including rejected candidates. Contradictory
positive `cbMac` bounds are refused. A null result can mean unrecoverable
structure or exhausted recovery limits; it is not proof that no text exists.

Word 98 Mac uses the Word97 layout and is recognized by structured, plain-text
and damaged-container readers. Word6/95 text-only import supports `fExtChar`
UTF-16 with scalar validation, Mac Roman, and Windows1252 for ANSI charset
with an unspecified/legacy locale or explicit en-US locale. Other 8-bit
charset/locale declarations are refused explicitly. Full Word6/95 formatting
and additional legacy code-page decoders remain outside this profile.

Opt-in comment recovery drops only the contradictory comment feature; valid
bookmarks and fields at the start of the following story remain owned by that
story. Real-format classification remains available for mislabeled non-CFB
input through `sniffLegacyWordFile` and `LegacyWordNotCompoundException`.
