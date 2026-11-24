import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/internal_viewer_views.dart';
import 'package:crisp_cloud/widgets/pdf_renderer_view.dart';
import 'package:crisp_cloud/widgets/pdf_review_status.dart';
import 'package:crisp_cloud/services/pdf_open_preferences.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:pdfx/pdfx.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart' as editor;
import 'package:quds_office_editor/quds_office_editor.dart' as office;

import '../support/pdf_editor_fixture.dart';

class _RecordingPdf extends PdfDocument {
  _RecordingPdf() : super(sourceName: 'fixture', id: 'fixture', pagesCount: 2);

  final requests = <(int, double, double)>[];

  @override
  Future<void> close() async {}

  @override
  Future<PdfPage> getPage(
    int pageNumber, {
    bool autoCloseAndroid = false,
  }) async => _RecordingPage(this, pageNumber);
}

class _RecordingPage extends PdfPage {
  _RecordingPage(_RecordingPdf pdf, int number)
    : super(
        document: pdf,
        id: 'page-$number',
        pageNumber: number,
        width: 600,
        height: 800,
        autoCloseAndroid: false,
      );

  @override
  Future<void> close() async {}

  @override
  Future<PdfPageTexture> createTexture() =>
      throw UnsupportedError('Bitmap test');

  @override
  Future<PdfPageImage?> render({
    required double width,
    required double height,
    PdfPageImageFormat format = PdfPageImageFormat.jpeg,
    String? backgroundColor,
    Rect? cropRect,
    int quality = 100,
    bool forPrint = false,
    bool removeTempFile = true,
  }) async {
    (document as _RecordingPdf).requests.add((pageNumber, width, height));
    expect(format, PdfPageImageFormat.png);
    return _FixtureRaster(pageNumber);
  }
}

class _FixtureRaster extends PdfPageImage {
  _FixtureRaster(int page)
    : super(
        id: 'image-$page',
        pageNumber: page,
        width: 1,
        height: 1,
        bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
          'AAAAC0lEQVR42mP8/x8AAwMCAO+aN1sAAAAASUVORK5CYII=',
        ),
        format: PdfPageImageFormat.png,
        quality: 100,
      );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Windows PDF zoom requests a sharper PDFium bitmap', (
    tester,
  ) async {
    final document = _RecordingPdf();
    final controller = PdfController(document: Future.value(document));
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfPagePanel(controller: controller, document: document),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PdfViewPinch), findsNothing);
      final initialWidth = document.requests.single.$2;
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      expect(document.requests.last.$2, greaterThan(initialWidth));
      expect(find.text('120%'), findsOneWidget);
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pumpAndSettle();
      expect(document.requests.last.$2, closeTo(initialWidth, 1));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('PDF review shows render damage and an unverified signature', (
    tester,
  ) async {
    final file = office.PdfFile.open(buildPdfEditorFixture(signed: true));
    file.pageDict(0)['Contents'] = office.PdfCosStream(
      office.PdfCosDict({'Filter': const office.PdfCosName('UnknownFilter')}),
      Uint8List(0),
    );
    final controller = office.PdfViewerController(file: file);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PdfReviewStatus(controller: controller)),
      ),
    );
    expect(find.byKey(const ValueKey('pdf-page-incomplete')), findsOneWidget);
    await tester.tap(find.text('PDF signature information'));
    await tester.pumpAndSettle();
    expect(find.text('Existing signature'), findsOneWidget);
    expect(find.text('Signature verification unavailable'), findsOneWidget);
    expect(find.text('Trusted signer'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  for (final secondary in [false, true]) {
    testWidgets(
      'F3 PDF routes to the persisted ${secondary ? 'secondary' : 'default'} engine',
      (tester) async {
        await const PdfOpenPreferences(
          viewer: PdfViewerBackend.pdfEditor,
          secondaryViewer: PdfViewerBackend.crispOffice,
        ).save();
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: InternalViewerDialog(
                file: FileItem(name: 'sample.pdf', isFolder: false),
                side: PanelSide.local,
                bytesOverride: buildPdfEditorFixture(),
                secondaryPdfViewer: secondary,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final view = tester.widget<PdfRendererView>(
          find.byType(PdfRendererView),
        );
        expect(
          view.backend,
          secondary ? PdfViewerBackend.crispOffice : PdfViewerBackend.pdfEditor,
        );
        expect(
          find.byKey(const ValueKey('pdf-viewer-backend')),
          findsOneWidget,
        );
        expect(find.byTooltip('Open secondary PDF viewer'), findsNothing);
        final double Function() offset;
        if (secondary) {
          final controller = tester
              .widget<office.QudsPdfViewer>(find.byType(office.QudsPdfViewer))
              .controller;
          offset = () => controller.viewport.origin.dy;
        } else {
          final controller = tester
              .widget<editor.PdfViewer>(find.byType(editor.PdfViewer))
              .controller!;
          offset = () => controller.scrollMetrics!.pixels;
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
        await tester.pump();
        expect(offset(), closeTo(0, 1));
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pump();
        expect(offset(), greaterThan(0));
        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
        await tester.pump();
        expect(offset(), closeTo(0, 1));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
