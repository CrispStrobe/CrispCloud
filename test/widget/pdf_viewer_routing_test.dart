import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:file_viewer_documents/file_viewer_documents.dart';
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
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/local_file_service_native.dart';
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

  testWidgets('F3 reads linked PDFs and XLSX files through their targets', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('crisp-linked-preview-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final service = DesktopFileService()..currentPath = temp.path;
    final container = ProviderContainer(
      overrides: [localFileServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final origin = container
        .read(panelProvider(PanelSide.local))
        .captureLocalClipboardOrigin(temp.path);
    final worksheet = office.SmlWorksheet(name: 'Sheet1', sheetId: 1);
    worksheet.cellA1('A1').value = 'Linked worksheet';
    final files = <(String, Uint8List, Type)>[
      ('linked.pdf', buildPdfEditorFixture(), PdfRendererView),
      (
        'linked.xlsx',
        office.SheetSerializer().writeBytes(
          office.SmlWorkbook(sheets: [worksheet]),
        ),
        DocumentPreview,
      ),
    ];
    for (final (name, bytes, view) in files) {
      final target = File('${temp.path}/target-$name')..writeAsBytesSync(bytes);
      final link = Link('${temp.path}/$name')..createSync(target.path);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: InternalViewerDialog(
              key: ValueKey(name),
              file: FileItem(
                name: name,
                path: link.path,
                isFolder: false,
                isSymlink: true,
              ),
              side: PanelSide.local,
              origin: origin,
            ),
          ),
        ),
      );
      for (
        var tick = 0;
        tick < 60 && find.byType(view).evaluate().isEmpty;
        tick++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(view), findsOneWidget);
      expect(target.readAsBytesSync(), bytes);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  }, skip: Platform.isWindows);

  testWidgets(
    'a PDF engine failure tries the alternate engine and keeps the chooser',
    (tester) async {
      await const PdfOpenPreferences(
        viewer: PdfViewerBackend.native,
        secondaryViewer: PdfViewerBackend.crispOffice,
      ).save();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: InternalViewerDialog(
              file: FileItem(name: 'sample.pdf', isFolder: false),
              side: PanelSide.local,
              bytesOverride: buildPdfEditorFixture(),
            ),
          ),
        ),
      );
      // Native PDF rendering is not registered in this widget test.
      await tester.pumpAndSettle();
      expect(
        tester.widget<PdfRendererView>(find.byType(PdfRendererView)).backend,
        PdfViewerBackend.crispOffice,
      );
      final chooser = find.byKey(const ValueKey('pdf-viewer-backend'));
      await tester.tap(chooser);
      await tester.pumpAndSettle();
      expect(find.text('CrispCloud PDF viewer'), findsOneWidget);
      expect(find.text('Native compatibility viewer'), findsOneWidget);
      await tester.tap(find.text('CrispCloud PDF viewer'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PdfRendererView>(find.byType(PdfRendererView)).backend,
        PdfViewerBackend.pdfEditor,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

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
