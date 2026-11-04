import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  group('OfficeIsolateOpen', () {
    test('opens a Word package and reports progress', () async {
      final WmlDocument document = WmlDocument.empty(text: 'فتح معزول');
      final Uint8List bytes = WordSerializer().writeBytes(document);
      final List<String> stages = <String>[];
      final WordOpenPayload opened = await OfficeIsolateOpen.word(
        bytes,
        onProgress: (OfficeOpenProgress progress) {
          stages.add(progress.stage);
          expect(progress.value, inInclusiveRange(0, 1));
        },
      );
      final String text = opened.document.paragraphs.first.inlines
          .whereType<WmlRun>()
          .map((WmlRun run) => run.text)
          .join();
      expect(text, contains('فتح معزول'));
      expect(opened.laidOut.pages, isNotEmpty);
      expect(stages, contains('archive'));
      expect(stages, contains('document'));
      expect(stages, contains('layout'));
    });

    test('opens a workbook package and keeps cell values', () async {
      final SmlWorkbook workbook = SmlWorkbook();
      workbook.firstSheet.cellA1('A1').value = 11;
      workbook.firstSheet.cellA1('B1').value = 4;
      workbook.firstSheet.cellA1('C1')
        ..type = SmlCellType.formula
        ..formula = '=A1+B1';
      final Uint8List bytes = SheetSerializer().writeBytes(workbook);
      final SmlWorkbook opened = await OfficeIsolateOpen.workbook(bytes);
      expect(opened.firstSheet.cellA1('A1').value, 11);
      expect(opened.firstSheet.cellA1('B1').value, 4);
      expect(opened.firstSheet.cellA1('C1').value, 15);
    });

    test('opens a presentation package and keeps slide text', () async {
      final PmlPresentation presentation = PmlPresentation(
        slides: <PmlSlide>[
          PmlSlide(
            id: 256,
            shapes: <PmlShape>[
              PmlShape(id: 2, name: 'Title', text: 'شريحة معزولة'),
            ],
          ),
        ],
      );
      final Uint8List bytes = SlideSerializer().writeBytes(presentation);
      final PmlPresentation opened = await OfficeIsolateOpen.presentation(
        bytes,
      );
      expect(opened.slides, isNotEmpty);
      expect(
        opened.slides.first.shapes.any(
          (PmlShape shape) => shape.text.contains('شريحة معزولة'),
        ),
        isTrue,
      );
    });

    test('treats large byte payloads as heavy', () {
      expect(OfficeIsolateOpen.isHeavyBytes(Uint8List(16)), isFalse);
      expect(
        OfficeIsolateOpen.isHeavyBytes(
          Uint8List(OfficeSaveCost.isolateThresholdBytes),
        ),
        isTrue,
      );
    });
  });
}
