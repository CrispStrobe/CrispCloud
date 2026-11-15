import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/document_conversion.dart';
import 'package:pdf_document/pdf_document.dart' show PdfBlankDocument;
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'PDF conversion is detected by content and scan limitations are retained',
    () async {
      final blank = PdfBlankDocument.create(pageCount: 2);
      expect(
        documentConversionFormats('unknown.bin', blank),
        containsAll(['docx', 'xlsx', 'pptx', 'txt']),
      );
      for (final extension in ['docx', 'xlsx', 'pptx']) {
        final result = await convertDocument(
          blank,
          sourceName: 'unknown.bin',
          extension: extension,
        );
        expect(result.pages, 2);
        expect(result.notices.join(' '), contains('OCR'));
        switch (extension) {
          case 'docx':
            final c = WordEditorController.fromBytes(result.bytes);
            expect(c.document.sections.length, greaterThanOrEqualTo(2));
            c.dispose();
          case 'xlsx':
            final c = SheetEditorController.fromBytes(result.bytes);
            expect(c.sheet.name, 'Text');
            c.dispose();
          case 'pptx':
            final c = SlideEditorController.fromBytes(result.bytes);
            expect(c.presentation.slides, hasLength(2));
            c.dispose();
        }
      }
    },
  );
  test(
    'text becomes real paragraphs and CSV formulas remain literal data',
    () async {
      final text = await convertDocument(
        Uint8List.fromList(utf8.encode('Hello\nمرحبا\nThird')),
        sourceName: 'notes.txt',
        extension: 'docx',
      );
      final word = WordEditorController.fromBytes(text.bytes);
      expect(word.document.paragraphs.length, 3);
      word.dispose();
      final csv = await convertDocument(
        Uint8List.fromList(utf8.encode('name,value\n"A,B",=1+1\n')),
        sourceName: 'table.csv',
        extension: 'xlsx',
      );
      final sheet = SheetEditorController.fromBytes(csv.bytes);
      expect(sheet.sheet.cellA1('A2').value, 'A,B');
      expect(sheet.sheet.cellA1('B2').value, '=1+1');
      expect(sheet.sheet.cellA1('B2').formula, isNull);
      sheet.dispose();
    },
  );
  test(
    'a real text PDF produces Office copies and keeps the source unchanged',
    () async {
      final source = File('test/fixtures/pdf_editor/form_rotated.pdf');
      final before = await source.readAsBytes();
      final result = await convertDocument(
        before,
        sourceName: 'form.pdf',
        extension: 'docx',
      );
      final controller = WordEditorController.fromBytes(result.bytes);
      expect(controller.document.paragraphs, isNotEmpty);
      controller.dispose();
      expect(await source.readAsBytes(), orderedEquals(before));
    },
  );
  test('unsupported routes fail before output', () async {
    await expectLater(
      convertDocument(
        Uint8List.fromList([1, 2]),
        sourceName: 'binary.exe',
        extension: 'docx',
      ),
      throwsFormatException,
    );
  });
}
