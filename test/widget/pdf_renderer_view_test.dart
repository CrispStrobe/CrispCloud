import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/widgets/pdf_renderer_view.dart';
import 'package:crisp_cloud/services/pdf_open_preferences.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart' as editor;
import 'package:quds_office_editor/quds_office_editor.dart' as office;

import '../support/pdf_editor_fixture.dart';

void main() {
  for (final backend in [
    PdfViewerBackend.pdfEditor,
    PdfViewerBackend.crispOffice,
  ]) {
    testWidgets(
      '$backend is read-only and zoom commands affect its actual viewport',
      (tester) async {
        final key = GlobalKey<PdfRendererViewState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PdfRendererView(
                key: key,
                bytes: buildPdfEditorFixture(),
                backend: backend,
                onCompatibility: () {},
                autoRenderWorker: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = key.currentState!.zoom;
        key.currentState!.zoomBy(1.2);
        await tester.pumpAndSettle();
        expect(key.currentState!.zoom, greaterThan(before));
        if (backend == PdfViewerBackend.pdfEditor) {
          final view = tester.widget<editor.PdfViewer>(
            find.byType(editor.PdfViewer),
          );
          expect(view.editing, isNull);
          expect(view.interactiveForms, isFalse);
          expect(view.textSelectionEditing, isFalse);
        } else {
          expect(
            tester
                .widget<office.QudsPdfViewer>(find.byType(office.QudsPdfViewer))
                .controller
                .config
                .allowsMutation,
            isFalse,
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'switching engine replaces the loaded model without writing the source',
    (tester) async {
      final key = GlobalKey<PdfRendererViewState>();
      final bytes = buildPdfEditorFixture();
      Future<void> open(PdfViewerBackend backend) async {
        await tester.pumpWidget(
          MaterialApp(
            home: PdfRendererView(
              key: key,
              bytes: bytes,
              backend: backend,
              onCompatibility: () {},
              autoRenderWorker: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await open(PdfViewerBackend.pdfEditor);
      expect(find.byType(editor.PdfViewer), findsOneWidget);
      await open(PdfViewerBackend.crispOffice);
      expect(find.byType(office.QudsPdfViewer), findsOneWidget);
      expect(find.byType(editor.PdfViewer), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'CrispOffice Escape reaches the host when there is no selection',
    (tester) async {
      var escaped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  escaped = true,
            },
            child: PdfRendererView(
              bytes: buildPdfEditorFixture(),
              backend: PdfViewerBackend.crispOffice,
              onCompatibility: () {},
              autoRenderWorker: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(escaped, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
