import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/internal_viewer_views.dart';
import 'package:crisp_cloud/widgets/pdf_renderer_view.dart';
import 'package:crisp_cloud/services/pdf_open_preferences.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:pdfx/pdfx.dart';

import '../support/pdf_editor_fixture.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Windows compatibility uses the image-based PDF viewer', (
    tester,
  ) async {
    final controller = PdfController(document: Completer<PdfDocument>().future);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PdfPagePanel(controller: controller)),
        ),
      );
      expect(find.byType(PdfView), findsOneWidget);
      expect(find.byType(PdfViewPinch), findsNothing);
      final view = tester.widget<PdfView>(find.byType(PdfView));
      expect(
        (view.builders.options as DefaultBuilderOptions).loaderSwitchDuration,
        Duration.zero,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
