import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_cos/pdf_cos.dart' show CosPasswordException;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import 'support/test_pdf.dart';

void main() {
  Future<PdfEditingController> openInsert(
    WidgetTester tester,
    PdfInsertFile file,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final preferences = PdfEditingPreferences(store: PdfMemoryPreferencesStore());
    addTearDown(preferences.dispose);
    final controller = PdfEditingController(
      buildTestPdf(),
      preferences: preferences,
      formSecretStore: InMemoryFormSecretStore(),
    );
    addTearDown(controller.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (context) => TextButton(
        onPressed: () => pdfInsertPagesInteractively(
          context,
          controller: controller,
          pickFiles: () async => const [],
          initialFiles: [file],
        ),
        child: const Text('Open insertion'),
      ),
    )));
    await tester.tap(find.text('Open insertion'));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('host password opens protected insertion source without rewriting it', (tester) async {
    final bytes = buildEncryptedPdf(revision: 6, userPassword: 'source-password');
    final controller = await openInsert(tester,
        PdfInsertFile('protected.pdf', bytes, password: 'source-password'));
    expect(find.byKey(const ValueKey('pdf-insert-pages-failed')), findsNothing);
    expect(find.text('source-password'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pdf-insert-pages-confirm')));
    await tester.pumpAndSettle();
    expect(controller.document.pageCount, 2);
    // The destination is unencrypted; the host owns consent for that policy.
    expect(controller.document.cos.isEncrypted, isFalse);
    expect(() => PdfDocument.open(bytes), throwsA(isA<CosPasswordException>()));
    expect(PdfDocument.open(bytes, password: 'source-password').pageCount, 1);
    controller.undo();
    expect(controller.document.pageCount, 1);
  });

  testWidgets('incorrect insertion password reports only source name and leaves target unchanged', (tester) async {
    final bytes = buildEncryptedPdf(revision: 6, userPassword: 'source-password');
    final controller = await openInsert(tester,
        PdfInsertFile('protected.pdf', bytes, password: 'incorrect-secret'));
    expect(find.byKey(const ValueKey('pdf-insert-pages-failed')), findsOneWidget);
    expect(find.text('incorrect-secret'), findsNothing);
    expect(tester.widget<FilledButton>(
      find.byKey(const ValueKey('pdf-insert-pages-confirm')),
    ).onPressed, isNull);
    expect(controller.document.pageCount, 1);
    expect(controller.canUndo, isFalse);
  });
}
