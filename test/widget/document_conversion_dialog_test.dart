import 'package:crisp_cloud/widgets/document_conversion_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart' show PdfBlankDocument;

void main() {
  testWidgets('PDF warnings must be reviewed before saving a separate copy', (
    tester,
  ) async {
    var saved = 0;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentConversionDialog(
              directory: '/tmp',
              sourceName: 'scan.pdf',
              readSource: () async => PdfBlankDocument.create(),
              onSave: (result, name) async {
                saved++;
                throw StateError('A file already exists');
              },
            ),
          ),
        ),
      );
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find.text('scan.pdf').evaluate().isNotEmpty) break;
      }
      await tester.tap(find.byKey(const ValueKey('conversion-prepare')));
      for (var i = 0; i < 150; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find
            .byKey(const ValueKey('conversion-review'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(find.textContaining('OCR'), findsWidgets);
      final save = find.byKey(const ValueKey('conversion-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('conversion-review')),
      );
      await tester.tap(find.byKey(const ValueKey('conversion-review')));
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pump();
      expect(saved, 1);
      expect(find.textContaining('A file already exists'), findsOneWidget);
    });
  });
}
