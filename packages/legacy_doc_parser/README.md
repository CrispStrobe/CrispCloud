# legacy_doc_parser

Portable Dart parsing of Word 97–2003 binary `.doc`/`.dot` files, with a typed
document model, safe formatted previews and conversion to a separate Word Open
XML copy. No Flutter, installed Office application, JavaScript runtime or network
service is required by the package.

Source: [CrispStrobe/legacy-doc-parser](https://github.com/CrispStrobe/legacy-doc-parser).
The package was extracted from CrispCloud and is under active development at
version `0.1.0-dev.1`. Supported features and remaining limitations are explicit;
this is not a claim of complete MS-DOC fidelity or identical pagination.

## Consumers and source ownership

The parser is maintained in this repository. The [Quds fork](https://github.com/CrispStrobe/quds_office_suite) exposes its public parsing and conversion API through engine compatibility exports. [CrispCloud](https://github.com/CrispStrobe/CrispCloud) uses it for legacy Word previews and reviewed DOCX/DOCM copies. Consumers retain an exact source pin and the MPL-2.0 notices; a consumer update does not imply complete format fidelity or identical native pagination.

Run `dart analyze`, `dart test`, and `python3 tool/verify_web.py` when updating a consumer pin. The web check compiles and executes the portable parser and converter with JavaScript; it is separate from native Word rendering acceptance.

## Use the development package

Requires Dart 3.8 or later. The only runtime package dependency is `archive`.
For a Git dependency:

```yaml
dependencies:
  legacy_doc_parser:
    git:
      url: https://github.com/CrispStrobe/legacy-doc-parser
      ref: 77b6b1d6b3edc52e314b64043fc2e6d7585fe4d7
```

The example pins a tested development checkpoint. When updating, choose a
reviewed commit for `ref` and retain the lockfile. Publishing a pub.dev release
is a separate action.

## Parse a document

```dart
import 'dart:typed_data';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';

void inspectDocument(Uint8List bytes) {
  final document = parseLegacyWordDocument(bytes);
  print(document.plainText);
  print(document.sections.length);
  print(document.warnings);
}
```

`blocks`, `plainText` and `safeHtml` describe the main story. Original character
positions use UTF-16 code units and exclusive range ends. Hidden runs and tracked
changes remain in the typed model; hidden text is excluded from ordinary preview
text. The original input is never modified. Encrypted DOC files are rejected.

The existing text-only API, `extractLegacyWordText`, remains available for callers
that intentionally need only the main story.

## Convert a separate copy

```dart
import 'dart:typed_data';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';

LegacyWordStructuredConversion createDocx(Uint8List source) =>
    convertLegacyWordToStructuredDocx(source);

LegacyWordStructuredConversion createDocm(Uint8List source) =>
    convertLegacyWord(source, format: LegacyWordOutputFormat.docm);
```

`convertLegacyWord` defaults to DOCX. DOCM requires an explicit choice and can
retain one structurally complete VBA project. DOCX never has an active VBA
relationship. The library never executes either macros or embedded objects.
`convertLegacyWordDocument` converts an already parsed `LegacyWordDocument`;
`convertLegacyWordToDocx` remains the explicit text-only converter.

The result contains immutable output `bytes`, `format`, `extension`,
`limitations`, `preservedCounts`, and `signatureEvidenceParts`.
`signatureValidityClaimed` is always false. Show the limitations and review the
converted copy before using it for editing, publication, or a signed workflow.

The [command-line example](example/legacy_doc_parser_example.dart) prints a
structural summary and optionally creates a new output file. It refuses an
existing destination:

```sh
dart run example/legacy_doc_parser_example.dart input.doc
dart run example/legacy_doc_parser_example.dart input.doc new-copy.docx
dart run example/legacy_doc_parser_example.dart input.doc new-copy.docm
```

## Current support

| Feature | Current behavior |
| --- | --- |
| Body text and formatting | Referenced Unicode text, resolved character/paragraph styles, underline variants, basic tables, sections, and tracked insertions/deletions |
| Tabs, borders and shading | Custom/default tab stops, supported paragraph borders and paragraph/cell shading; unsupported exact patterns are disclosed |
| Headers, footers and notes | Referenced stories and actual Word output parts; source first/even-header activation is retained |
| Comments, bookmarks and fields | Comment text/ranges/authors, bookmark ranges, safe locked field syntax and cached results; no field evaluation |
| Lists | Typed numbering definitions and Word numbering output; supported preview labels with explicit approximation metadata |
| Images and textboxes | Referenced PNG/JPEG/TIFF, supported inline/floating placement and crop, editable textboxes and validated chains |
| OLE and VBA | Exact stored stream content with reconstructed CFB metadata; eligibility checks for active embedded objects and explicit DOCM VBA |
| Signatures and opaque content | Inert source evidence with a manifest; no copied-signature validity claim |

See the detailed contracts:

- [Structured conversion](doc/conversion.md)
- [HTML preview](doc/html-preview.md)
- [Stories, fields and lists](doc/stories-fields-lists.md)
- [Media and opaque preservation](doc/media-preservation.md)
- [JSDoc comparison and attribution](doc/jsdoc-parity.md)

## Preservation contract

Support is recorded per feature as parsed, rendered, converted or retained as
opaque evidence. Retaining an object's bytes is not a claim that it is editable
or executable in the output. The library never executes macros, fields or
embedded objects and never retrieves linked external resources.

Ordinary previews exclude hidden text and private cached field content. Hidden
or deleted media retains its presentation state, and deleted OfficeArt shapes
remain inactive. In conversion, notes/comments anchored in hidden or private
content remain inert evidence. All package relationships are internal.

Conversion creates a new document. It cannot transfer the original document's
signature validity to that new document. Signature artifacts, when retained,
must be treated as evidence associated with the original file.

## Development

```sh
dart pub get
dart analyze
dart test
python3 tool/verify_web.py
dart format --output=none --set-exit-if-changed .
dart pub publish --dry-run
```

The JavaScript acceptance check requires an already installed Dart SDK and
Node.js and an existing package configuration. Optional `--dart` and `--node`
arguments select those executables. The script performs no package resolution,
downloads, Flutter build, or network requests. It compiles the package to
JavaScript and executes it under Node against the authored DOC fixture and
synthetic OLE/VBA fixtures. Checks include Unicode, real Word parts and image
bytes, unchanged source, internal relationships, and exact reconstructed CFB
CLSID/state/raw FILETIME metadata. Temporary generated files are removed.

These checks establish structural and JavaScript-runtime compatibility. Native
office rendering and exact layout fidelity require separate acceptance and
review. `dart pub publish --dry-run` checks package contents without publishing.

## License

New package source is licensed under **MPL-2.0**. See [LICENSE](LICENSE) and
[NOTICE](NOTICE). The small vendored compound-file implementation retains its
MIT license, and adapted JSDoc source retains the accompanying 0BSD notice.

This Source Code Form is subject to the terms of the Mozilla Public License,
v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at https://mozilla.org/MPL/2.0/.

The preservation work includes nested and conditional tables, preferred cell
widths, list continuation, bounded EMF/WMF media, packed OfficeArt paths,
paragraph and note layout, linked textbox reflow, comment threads and supported
revision histories. Supported row height, splitting and header revisions retain
editable previous properties with independently checked accept/reject
projections. Header history that can change conditional table formatting remains
diagnosed evidence because restoring the header flag alone cannot restore all
previous cell and text formatting. Bounded picture-frame flips, floating quarter
turns, direct outlines and simple offset shadows have separate authored native
rendering controls.
See the [eight-area fidelity ledger](doc/fidelity-status.md) and
[oracle guide](doc/fidelity-oracles.md) for the supported contracts and remaining
losses. Versioned evidence retains complete native results, including failures;
matching pixels, valid packages and preserved semantics are separate checks.

CI runs the portable Dart and JavaScript tests, Python structural/mutation
oracles, and a freshly built independent Open XML SDK validation gate. The SDK
corpus has an exact, deterministic inventory and positive/negative controls.
Native rendering additionally requires an installed Office application and
records its version, fonts, source hashes and successive round trips.
[The clean 8060ac1 receipt](doc/evidence/8060ac1/README.md) is a reproducible
historical checkpoint; later fixes do not overwrite its original findings.

The current preservation increment also retains supported Word compatibility flags and OfficeArt text-box layout and supplies bounded vector previews. Unsupported drawing records remain explicit retained evidence; the parser does not claim exact native layout for every legacy drawing.
