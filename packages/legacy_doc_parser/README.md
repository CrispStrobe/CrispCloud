# legacy_doc_parser

Portable Dart parsing of Word 97–2003 binary `.doc`/`.dot` files, with a typed
document model, safe formatted previews and conversion to a separate Word Open
XML copy. No Flutter, installed Office application, JavaScript runtime or network
service is required by the package.

This package is being extracted from CrispCloud and extended before its first
pub.dev release. The intended GitHub repository is
`CrispStrobe/legacy-doc-parser`; the pub.dev package name is `legacy_doc_parser`.
An unreleased version is not a claim of complete MS-DOC fidelity.

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

## Preservation contract

Support is recorded per feature as parsed, rendered, converted or retained as
opaque evidence. Retaining an object's bytes is not a claim that it is editable
or executable in the output. The library never executes macros, fields or
embedded objects and never retrieves linked external resources.

Conversion creates a new document. It cannot transfer the original document's
signature validity to that new document. Signature artifacts, when retained,
must be treated as evidence associated with the original file.

## Development

```sh
dart pub get
dart analyze
dart test
dart format --output=none --set-exit-if-changed .
dart pub publish --dry-run
```

Publishing is a separate release action. Keep the application pinned to a tested
Git revision until a compatible pub.dev release is deliberately adopted.

## License

New package source is licensed under **MPL-2.0**. See [LICENSE](LICENSE) and
[NOTICE](NOTICE). The small vendored compound-file implementation retains its
MIT license, and adapted JSDoc source retains the accompanying 0BSD notice.

This Source Code Form is subject to the terms of the Mozilla Public License,
v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at https://mozilla.org/MPL/2.0/.
