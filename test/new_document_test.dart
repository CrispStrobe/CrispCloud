import 'dart:io';

import 'package:crisp_cloud/services/new_document.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:pdf_document/pdf_document.dart' as pdf;
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'every offered document is accepted by its real editor parser',
    () async {
      for (final kind in NewDocumentKind.values) {
        final bytes = await newDocumentBytes(kind, title: 'A & B');
        switch (kind) {
          case NewDocumentKind.word:
            final c = WordEditorController.fromBytes(bytes);
            expect(c.document.paragraphs, isNotEmpty);
            c.dispose();
          case NewDocumentKind.spreadsheet:
            final c = SheetEditorController.fromBytes(bytes);
            expect(c.workbook.sheets, hasLength(1));
            c.dispose();
          case NewDocumentKind.presentation:
            final c = SlideEditorController.fromBytes(bytes);
            expect(c.presentation.slides, hasLength(1));
            c.dispose();
          case NewDocumentKind.pdf:
            expect(pdf.PdfDocument.open(bytes).pageCount, 1);
          case NewDocumentKind.picture:
            final decoded = image.decodePng(bytes)!;
            expect(decoded.width, 1024);
            expect(decoded.getPixel(0, 0).r, 255);
          case NewDocumentKind.ebook:
            expect(EpubDocument.open(bytes).canEdit, isTrue);
          case NewDocumentKind.text:
          case NewDocumentKind.csv:
            expect(bytes, isEmpty);
          case NewDocumentKind.markdown:
            expect(String.fromCharCodes(bytes), contains('# A & B'));
        }
      }
    },
  );
  test(
    'native create is read-back verified, refuses collision and traversal',
    () async {
      final dir = await Directory.systemTemp.createTemp('crisp-new-doc-');
      addTearDown(() => dir.delete(recursive: true));
      var current = true;
      final backend = LocalOperationBackend(
        LocalFileService(),
        isCurrent: () => current,
      );
      final created = await createNewDocument(
        backend: backend,
        directory: dir.path,
        name: 'sample',
        kind: NewDocumentKind.word,
      );
      expect(created.name, 'sample.docx');
      final saved = await File(created.path!).readAsBytes();
      await expectLater(
        createNewDocument(
          backend: backend,
          directory: dir.path,
          name: 'sample.docx',
          kind: NewDocumentKind.word,
        ),
        throwsStateError,
      );
      expect(await File(created.path!).readAsBytes(), orderedEquals(saved));
      await expectLater(
        createNewDocument(
          backend: backend,
          directory: dir.path,
          name: '../outside',
          kind: NewDocumentKind.text,
        ),
        throwsFormatException,
      );
      current = false;
      await expectLater(
        createNewDocument(
          backend: backend,
          directory: dir.path,
          name: 'stale',
          kind: NewDocumentKind.text,
        ),
        throwsA(anything),
      );
      expect(await File('${dir.path}/stale.txt').exists(), isFalse);
    },
  );
  test('portable names keep text/code extensions and reject mismatched rich formats', () {
    expect(
      validateNewDocumentName('hello.dart', NewDocumentKind.text),
      'hello.dart',
    );
    expect(validateNewDocumentName('book', NewDocumentKind.ebook), 'book.epub');
    for (final name in [
      'CON.txt',
      'a/../b',
      'a\\b',
      'NUL',
      'report.pdf',
      'wrong.',
    ]) {
      expect(
        () => validateNewDocumentName(name, NewDocumentKind.word),
        throwsFormatException,
      );
    }
  });
}
