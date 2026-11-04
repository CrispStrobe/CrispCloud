import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  setUp(WordStyles.extras.clear);

  group('OfficeIsolateSave', () {
    test('word isolate bytes match the UI-isolate serializer', () async {
      final WmlDocument document = WmlDocument.empty(text: 'حفظ معزول');
      final Uint8List expected = WordSerializer().writeBytes(document);
      document.package = null;
      final Uint8List actual = await OfficeIsolateSave.word(document);
      _expectSameOfficeParts(actual, expected);
    });

    test('workbook isolate bytes match the UI-isolate serializer', () async {
      final SmlWorkbook workbook = SmlWorkbook();
      workbook.firstSheet.cellA1('A1').value = 7;
      final Uint8List expected = SheetSerializer().writeBytes(workbook);
      workbook.package = null;
      final Uint8List actual = await OfficeIsolateSave.workbook(workbook);
      _expectSameOfficeParts(actual, expected);
    });

    test('treats a long Word document as heavy', () {
      final WmlDocument document = WmlDocument(
        sections: <WmlSection>[
          WmlSection(
            blocks: <WmlBlock>[
              for (int i = 0; i < 60; i++)
                WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'فقرة $i')]),
            ],
          ),
        ],
      );
      expect(OfficeSaveCost.isHeavyWord(document), isTrue);
      expect(OfficeSaveCost.isHeavyWord(WmlDocument.empty()), isFalse);
    });

    test('treats a picture-heavy Word document as heavy', () {
      final WmlDocument document = WmlDocument(
        sections: <WmlSection>[
          WmlSection(
            blocks: <WmlBlock>[
              WmlVisual(
                visual: OfficeVisual(
                  kind: OfficeVisualKind.picture,
                  imageBytes: Uint8List(OfficeSaveCost.isolateThresholdBytes),
                ),
              ),
            ],
          ),
        ],
      );
      expect(OfficeSaveCost.isHeavyWord(document), isTrue);
    });
  });
}

void _expectSameOfficeParts(Uint8List actual, Uint8List expected) {
  final OpcPackage a = OpcPackage.openBytes(actual);
  final OpcPackage b = OpcPackage.openBytes(expected);
  final Set<String> uris = <String>{...a.partNames, ...b.partNames};
  for (final String uri in uris) {
    if (uri.endsWith('/docProps/core.xml') || uri == '/docProps/core.xml') {
      continue;
    }
    expect(a.getPart(uri)?.readText(), b.getPart(uri)?.readText(), reason: uri);
  }
}
