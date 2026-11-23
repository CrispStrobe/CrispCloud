import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
        expect(
          find.text('${(key.currentState!.zoom * 100).round()}%'),
          findsOneWidget,
        );
        await tester.tap(find.text('Fit page'));
        await tester.pumpAndSettle();
        expect(
          find.text('${(key.currentState!.zoom * 100).round()}%'),
          findsOneWidget,
        );
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
  testWidgets('CrispOffice only interprets page contents when needed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 260,
            child: PdfRendererView(
              bytes: buildPdfEditorFixture(),
              backend: PdfViewerBackend.crispOffice,
              onCompatibility: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final controller = tester
        .widget<office.QudsPdfViewer>(find.byType(office.QudsPdfViewer))
        .controller;
    expect(controller.pageCount, 2);
    expect(controller.lists[1].page.height, 400);
    final content = Uint8List.fromList('1 0 0 rg 10 10 40 20 re f'.codeUnits);
    controller.file!.pageDict(1)['Contents'] = office.PdfCosStream(
      office.PdfCosDict(),
      content,
    );
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(
      controller.lists[1].ops.whereType<office.PdfFillPath>(),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('CrispOffice paints a fax scan without a text layer', (
    tester,
  ) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundaryKey,
          child: PdfRendererView(
            bytes: buildPdfEditorFixture(faxScan: true),
            backend: PdfViewerBackend.crispOffice,
            onCompatibility: () =>
                fail('The scan should render in CrispOffice'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final viewer = tester.widget<office.QudsPdfViewer>(
      find.byType(office.QudsPdfViewer),
    );
    expect(viewer.controller.lists.first.runs, isEmpty);
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    var darkest = 255;
    for (var attempt = 0; attempt < 20 && darkest > 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 16));
      final level = await tester.runAsync(() async {
        if (boundary.debugNeedsPaint) return null;
        final image = await boundary.toImage();
        try {
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          return pixels.getUint8((250 * image.width + 400) * 4);
        } finally {
          image.dispose();
        }
      });
      if (level != null && level < darkest) darkest = level;
    }
    expect(darkest, lessThan(20));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fit width accounts for page rotation', (tester) async {
    final key = GlobalKey<PdfRendererViewState>();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfRendererView(
          key: key,
          bytes: buildPdfEditorFixture(rotation: 90),
          backend: PdfViewerBackend.pdfEditor,
          onCompatibility: () {},
          autoRenderWorker: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fit width'));
    await tester.pumpAndSettle();
    expect(key.currentState!.zoom, closeTo((800 - 32) / 400, .001));
    await tester.pumpWidget(const SizedBox());
  });
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
