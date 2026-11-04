import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

Uint8List _twoPagePdf() {
  final PdfDocument doc = PdfDocument(title: 'Options');
  for (int i = 0; i < 2; i++) {
    final PdfCanvas canvas = PdfCanvas(300, 400)
      ..rect(10.0 + i, 10, 40, 20)
      ..fill();
    doc.addPage(PdfPage(width: 300, height: 400, content: canvas.toStream()));
  }
  return doc.save();
}

void main() {
  test('applyOptions clamps zoom to min/max', () {
    final PdfViewerController controller = PdfViewerController.fromBytes(
      _twoPagePdf(),
    );
    controller.applyOptions(const PdfViewerOptions(minZoom: 0.5, maxZoom: 2.0));
    controller.viewport.extent = const Size(400, 600);
    controller.setScale(0.1, animate: false);
    expect(controller.viewport.scale, 0.5);
    controller.setScale(9, animate: false);
    expect(controller.viewport.scale, 2.0);
    controller.dispose();
  });

  test('preventLinkNavigation skips onOpenUri', () {
    final PdfViewerController controller = PdfViewerController.fromBytes(
      _twoPagePdf(),
    );
    var opened = 0;
    controller.onOpenUri = (_) => opened++;
    controller.applyOptions(
      const PdfViewerOptions(preventLinkNavigation: true),
    );
    controller.followLink(const PdfLinkAction(uri: 'https://example.com/doc'));
    expect(opened, 0);

    controller.applyOptions(
      const PdfViewerOptions(preventLinkNavigation: false),
    );
    controller.followLink(const PdfLinkAction(uri: 'https://example.com/doc'));
    expect(opened, 1);
    controller.dispose();
  });

  test('horizontal layout metrics and goToPage', () {
    final PdfViewerController controller = PdfViewerController.fromBytes(
      _twoPagePdf(),
    );
    controller.applyOptions(const PdfViewerOptions(swipeHorizontal: true));
    controller.viewport.extent = const Size(400, 600);
    final Size content = PdfPageLayout.contentSize(
      controller.lists,
      controller.viewport.scale,
      horizontal: true,
    );
    expect(content.width, greaterThan(content.height));
    controller.goToPage(1);
    expect(controller.pageIndex, 1);
    expect(controller.viewport.origin.dx, greaterThan(0));
    controller.dispose();
  });

  test('snapToNearestPage aligns when pageSnap is on', () {
    final PdfViewerController controller = PdfViewerController.fromBytes(
      _twoPagePdf(),
    );
    controller.applyOptions(const PdfViewerOptions(pageSnap: true));
    controller.viewport.extent = const Size(400, 500);
    controller.goToPage(0);
    final double page1Top = PdfPageLayout.stackTop(
      controller.lists,
      1,
      controller.viewport.scale,
    );
    controller.viewport.origin = Offset(0, page1Top - 8);
    controller.snapToNearestPage();
    expect(controller.pageIndex, 1);
    expect(controller.viewport.origin.dy, closeTo(page1Top, 1));
    controller.dispose();
  });

  testWidgets('onPageChanged fires when goToPage updates', (
    WidgetTester tester,
  ) async {
    final PdfViewerController controller = PdfViewerController.fromBytes(
      _twoPagePdf(),
    );
    final List<int> pages = <int>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 480,
          height: 640,
          child: QudsPdfViewer(
            controller: controller,
            options: const PdfViewerOptions(fitPolicy: PdfFitPolicy.none),
            onPageChanged: (int page, int total) {
              pages.add(page);
              expect(total, 2);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    controller.goToPage(1);
    await tester.pump();
    expect(pages, contains(1));
    controller.dispose();
  });

  testWidgets('onViewCreated and onLoadComplete fire once', (
    WidgetTester tester,
  ) async {
    final PdfViewerController controller = PdfViewerController.fromBytes(
      _twoPagePdf(),
    );
    var created = 0;
    var loaded = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 480,
          height: 640,
          child: QudsPdfViewer(
            controller: controller,
            onViewCreated: (_) => created++,
            onLoadComplete: (int count) {
              loaded++;
              expect(count, 2);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(created, 1);
    expect(loaded, 1);
    controller.dispose();
  });
}
