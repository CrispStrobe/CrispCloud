import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

/// A small generated PDF keeps the compatibility tests independent of the
/// upstream monorepo's fixture package and binary assets.
Uint8List buildTestPdf({bool passwordField = false}) {
  final builder = CosDocumentBuilder();
  final catalog = CosDictionary({'Type': const CosName('Catalog')});
  final catalogRef = builder.add(catalog);
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final pagesRef = builder.add(pages);
  final content = Uint8List.fromList('0.2 0.4 0.6 rg 20 30 60 70 re f'.codeUnits);
  final page = CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'MediaBox': CosArray(const [
      CosInteger(0),
      CosInteger(0),
      CosInteger(612),
      CosInteger(792),
    ]),
    'Contents': builder.add(CosStream(
      CosDictionary({'Length': CosInteger(content.length)}),
      content,
    )),
  });
  final pageRef = builder.add(page);
  pages['Kids'] = CosArray([pageRef]);
  pages['Count'] = const CosInteger(1);
  catalog['Pages'] = pagesRef;

  if (passwordField) {
    final fontRef = builder.add(CosDictionary({
      'Type': const CosName('Font'),
      'Subtype': const CosName('Type1'),
      'BaseFont': const CosName('Helvetica'),
      'Encoding': const CosName('WinAnsiEncoding'),
    }));
    final fieldRef = builder.add(CosDictionary({
      'Type': const CosName('Annot'),
      'Subtype': const CosName('Widget'),
      'FT': const CosName('Tx'),
      'T': CosString.fromText('password'),
      'Ff': const CosInteger(PdfFormField.passwordFlag),
      'P': pageRef,
      'Rect': CosArray(const [
        CosInteger(72),
        CosInteger(700),
        CosInteger(300),
        CosInteger(724),
      ]),
      'DA': CosString.fromText('/Helv 12 Tf 0 g'),
    }));
    page['Annots'] = CosArray([fieldRef]);
    catalog['AcroForm'] = CosDictionary({
      'Fields': CosArray([fieldRef]),
      'DA': CosString.fromText('/Helv 12 Tf 0 g'),
      'DR': CosDictionary({
        'Font': CosDictionary({'Helv': fontRef}),
      }),
    });
  }
  return builder.build(root: catalogRef);
}
