import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  testWidgets('QudsPdfViewer opens writer bytes', (WidgetTester tester) async {
    final PdfDocument doc = PdfDocument(title: 'Viewer');
    final PdfCanvas canvas = PdfCanvas(300, 400)
      ..rect(10, 10, 40, 20)
      ..fill();
    doc.addPage(PdfPage(width: 300, height: 400, content: canvas.toStream()));
    final PdfViewerController controller = PdfViewerController.fromBytes(
      doc.save(),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: QudsPdfViewer(controller: controller),
      ),
    );
    expect(controller.pageCount, 1);
    expect(find.byType(PdfCanvasView), findsOneWidget);
    controller.dispose();
  });

  test('editor highlight then save grows the package', () {
    final PdfDocument doc = PdfDocument();
    final PdfCanvas canvas = PdfCanvas(300, 400)
      ..rect(10, 10, 40, 20)
      ..fill();
    doc.addPage(PdfPage(width: 300, height: 400, content: canvas.toStream()));
    final PdfEditorController editor = PdfEditorController.fromBytes(
      doc.save(),
    );
    editor.setSelection(
      PdfTextSelection.run(
        0,
        0,
        const PdfTextRun(text: 'Hi', x: 10, y: 10, width: 20, height: 12),
      ),
    );
    editor.highlightSelection();
    final int before = editor.file!.originalBytes.length;
    expect(editor.saveBytes().length, greaterThan(before));
    editor.undo();
    expect(editor.file!.annotsOn(0), isEmpty);
    editor.dispose();
  });

  test('setScale zooms about the view center and clamps', () {
    final PdfDocument doc = PdfDocument();
    final PdfCanvas canvas = PdfCanvas(300, 400)
      ..rect(10, 10, 40, 20)
      ..fill();
    doc.addPage(PdfPage(width: 300, height: 400, content: canvas.toStream()));
    final PdfEditorController editor = PdfEditorController.fromBytes(
      doc.save(),
    );
    editor.viewport.extent = const Size(400, 300);
    editor.viewport.origin = const Offset(0, 200);
    editor.setScale(2, animate: false);
    expect(editor.viewport.scale, 2);
    expect(editor.viewport.origin.dy, greaterThan(200));
    editor.setScale(0.1, animate: false);
    expect(editor.viewport.scale, VirtualViewport.minScale);
    editor.setScale(10, animate: false);
    expect(editor.viewport.scale, VirtualViewport.maxScale);
    editor.zoomBy(1, animate: false);
    expect(editor.viewport.scale, VirtualViewport.maxScale);
    editor.dispose();
  });

  testWidgets('viewer canvas picks up controller scale', (
    WidgetTester tester,
  ) async {
    final PdfDocument doc = PdfDocument();
    final PdfCanvas canvas = PdfCanvas(300, 400)
      ..rect(10, 10, 40, 20)
      ..fill();
    doc.addPage(PdfPage(width: 300, height: 400, content: canvas.toStream()));
    final PdfViewerController controller = PdfViewerController.fromBytes(
      doc.save(),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: QudsPdfViewer(controller: controller),
      ),
    );
    controller.setScale(2, animate: false);
    await tester.pump();
    final PdfCanvasView view = tester.widget(find.byType(PdfCanvasView));
    expect(view.scale, 2);
    expect(controller.viewport.scale, 2);
    controller.dispose();
  });

  testWidgets('clicking a URI link asks the host to open it', (
    WidgetTester tester,
  ) async {
    final PdfDocument doc = PdfDocument();
    final PdfCanvas canvas = PdfCanvas(300, 400)
      ..rect(10, 10, 40, 20)
      ..fill();
    canvas.showLatin(
      x: 40,
      y: 66,
      fontSize: 12,
      text: 'Sample notes',
      color: '1565C0',
    );
    canvas.endText();
    doc.addPage(
      PdfPage(
        width: 300,
        height: 400,
        content: canvas.toStream(),
        links: const <PdfLinkAnnot>[
          PdfLinkAnnot(
            x: 40,
            y: 50,
            width: 140,
            height: 24,
            uri: 'https://quds.office/samples/widgets',
          ),
        ],
      ),
    );
    final PdfViewerController controller = PdfViewerController.fromBytes(
      doc.save(),
    );
    String? opened;
    controller.onOpenUri = (String uri) => opened = uri;
    expect(controller.lists.single.runs, isNotEmpty);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 420,
          height: 640,
          child: QudsPdfViewer(controller: controller),
        ),
      ),
    );
    await tester.pump();
    final Finder viewFinder = find.byType(PdfCanvasView);
    final Offset origin = tester.getTopLeft(viewFinder);
    final Size view = tester.getSize(viewFinder);
    const double scale = 96 / 72;
    const double pageW = 300 * scale;
    final double viewW = view.width - 14;
    final double left = viewW > pageW + 72 ? (viewW - pageW) / 2 : 36;
    await tester.tapAt(origin + Offset(left + 110 * scale, 24 + 62 * scale));
    await tester.pump();
    expect(opened, 'https://quds.office/samples/widgets');
    controller.dispose();
  });

  test('PDF context menu splits viewer and editor commands', () {
    final PdfDocument doc = PdfDocument();
    final PdfCanvas canvas = PdfCanvas(300, 400);
    canvas.showLatin(
      x: 40,
      y: 66,
      fontSize: 12,
      text: 'Notes',
      color: '000000',
    );
    canvas.endText();
    doc.addPage(PdfPage(width: 300, height: 400, content: canvas.toStream()));
    final bytes = doc.save();
    final PdfViewerController viewer = PdfViewerController.fromBytes(bytes);
    final List<String> viewIds = OfficeContextMenu.pdf(
      controller: viewer,
      hit: const PdfContextHit(globalPosition: Offset.zero, pageIndex: 0),
    ).map((OfficeContextAction action) => action.id).toList();
    expect(
      viewIds,
      containsAll(<String>['copy', 'zoomIn', 'fitPage', 'nextPage']),
    );
    expect(viewIds, isNot(contains('highlight')));
    viewer.dispose();

    final PdfEditorController editor = PdfEditorController.fromBytes(bytes);
    final List<String> editIds = OfficeContextMenu.pdf(
      controller: editor,
      hit: const PdfContextHit(globalPosition: Offset.zero, pageIndex: 0),
    ).map((OfficeContextAction action) => action.id).toList();
    expect(
      editIds,
      containsAll(<String>['highlight', 'strikethrough', 'rotatePage', 'undo']),
    );
    editor.dispose();
  });

  testWidgets('right-click on a PDF page opens the context menu', (
    WidgetTester tester,
  ) async {
    final PdfDocument doc = PdfDocument();
    final PdfCanvas canvas = PdfCanvas(300, 400)
      ..rect(10, 10, 40, 20)
      ..fill();
    doc.addPage(PdfPage(width: 300, height: 400, content: canvas.toStream()));
    final PdfViewerController controller = PdfViewerController.fromBytes(
      doc.save(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: QudsPdfViewer(controller: controller),
        ),
      ),
    );
    await tester.pump();
    final Finder viewFinder = find.byType(PdfCanvasView);
    final Offset origin = tester.getTopLeft(viewFinder);
    await tester.tapAt(
      origin + const Offset(80, 80),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    expect(find.text('Zoom in'), findsOneWidget);
    expect(find.text('Fit page'), findsOneWidget);
    expect(find.text('Highlight'), findsNothing);
    controller.dispose();
  });

  test('goToPage scrolls the stack and thumbs can be hit', () {
    final PdfDocument doc = PdfDocument();
    for (int i = 0; i < 3; i++) {
      final PdfCanvas canvas = PdfCanvas(300, 400)
        ..rect(10, 10, 40, 20)
        ..fill();
      doc.addPage(PdfPage(width: 300, height: 400, content: canvas.toStream()));
    }
    final PdfEditorController editor = PdfEditorController.fromBytes(
      doc.save(),
    );
    editor.viewport.extent = const Size(400, 300);
    editor.goToPage(2);
    expect(editor.pageIndex, 2);
    expect(editor.viewport.origin.dy, greaterThan(400));
    editor.viewport.origin = Offset.zero;
    editor.viewport.extent = const Size(400, 200);
    editor.adoptVisiblePage();
    expect(editor.pageIndex, 0);
    editor.dispose();
  });

  test('text selection copies a run slice and word bounds', () {
    const PdfTextRun run = PdfTextRun(
      text: 'Hello PDF',
      x: 10,
      y: 20,
      width: 90,
      height: 12,
    );
    final PdfDisplayList list = PdfDisplayList(
      page: const PdfPageInfo(
        index: 0,
        mediaBox: PdfBox(llx: 0, lly: 0, urx: 300, ury: 400),
        cropBox: PdfBox(llx: 0, lly: 0, urx: 300, ury: 400),
      ),
      runs: <PdfTextRun>[run],
    );
    final PdfTextSelection range = PdfTextSelection(
      anchor: const PdfTextHit(page: 0, run: 0, offset: 0),
      extent: const PdfTextHit(page: 0, run: 0, offset: 5),
    );
    expect(range.plainText(<PdfDisplayList>[list]), 'Hello');
    expect(range.boxes(<PdfDisplayList>[list]), isNotEmpty);
    expect(PdfTextSelection.offsetAt(run, 10), 0);
    expect(PdfTextSelection.offsetAt(run, 100), 9);
    expect(
      PdfTextSelection.word(
        const PdfTextHit(page: 0, run: 0, offset: 7),
        run,
      ).plainText(<PdfDisplayList>[list]),
      'PDF',
    );
  });

  test('RTL selection starts at the right edge and grows left', () {
    const PdfTextRun word = PdfTextRun(
      text: 'تقرير',
      x: 10,
      y: 20,
      width: 100,
      height: 12,
    );
    expect(PdfTextSelection.offsetAt(word, 108), 0);
    expect(PdfTextSelection.offsetAt(word, 12), 5);
    final Rect head = PdfTextSelection.sliceRect(word, 0, 1);
    expect(head.right, closeTo(110, 0.01));
    expect(head.left, greaterThan(80));

    const PdfTextRun left = PdfTextRun(
      text: 'ر',
      x: 20,
      y: 20,
      width: 12,
      height: 12,
    );
    const PdfTextRun mid = PdfTextRun(
      text: 'ق',
      x: 50,
      y: 20,
      width: 12,
      height: 12,
    );
    const PdfTextRun right = PdfTextRun(
      text: 'ت',
      x: 80,
      y: 20,
      width: 12,
      height: 12,
    );
    const PdfTextRun below = PdfTextRun(
      text: 'A',
      x: 20,
      y: 48,
      width: 12,
      height: 12,
    );
    final PdfDisplayList arabic = PdfDisplayList(
      page: const PdfPageInfo(
        index: 0,
        mediaBox: PdfBox(llx: 0, lly: 0, urx: 300, ury: 400),
        cropBox: PdfBox(llx: 0, lly: 0, urx: 300, ury: 400),
      ),
      runs: <PdfTextRun>[left, mid, right, below],
    );
    final PdfTextSelection drag = PdfTextSelection(
      anchor: const PdfTextHit(page: 0, run: 2, offset: 0),
      extent: const PdfTextHit(page: 0, run: 0, offset: 1),
    );
    final List<({int page, Rect rect})> boxes = drag.boxes(<PdfDisplayList>[
      arabic,
    ]);
    expect(boxes, hasLength(3));
    expect(
      boxes.any((({int page, Rect rect}) box) => box.rect.top > 40),
      isFalse,
    );
    final double rightEdge = boxes
        .map((({int page, Rect rect}) box) => box.rect.right)
        .reduce((double a, double b) => a > b ? a : b);
    expect(rightEdge, closeTo(92, 0.01));
    const PdfTextRun nextLine = PdfTextRun(
      text: 'س',
      x: 50,
      y: 34,
      width: 12,
      height: 16,
    );
    final PdfDisplayList tight = PdfDisplayList(
      page: arabic.page,
      runs: <PdfTextRun>[left, mid, right, nextLine],
    );
    final List<({int page, Rect rect})> oneLine = drag.boxes(<PdfDisplayList>[
      tight,
    ]);
    expect(oneLine, hasLength(3));
    expect(
      oneLine.any((({int page, Rect rect}) box) => box.rect.top > 30),
      isFalse,
    );
  });

  test('select page highlights every run, not the endpoint x-band', () {
    const PdfTextRun title = PdfTextRun(
      text: 'Title',
      x: 40,
      y: 20,
      width: 40,
      height: 14,
    );
    const PdfTextRun body = PdfTextRun(
      text: 'Body text that used to be missed',
      x: 40,
      y: 48,
      width: 220,
      height: 12,
    );
    const PdfTextRun foot = PdfTextRun(
      text: 'End',
      x: 40,
      y: 80,
      width: 24,
      height: 12,
    );
    final PdfDisplayList page = PdfDisplayList(
      page: const PdfPageInfo(
        index: 0,
        mediaBox: PdfBox(llx: 0, lly: 0, urx: 300, ury: 400),
        cropBox: PdfBox(llx: 0, lly: 0, urx: 300, ury: 400),
      ),
      runs: <PdfTextRun>[title, body, foot],
    );
    final PdfTextSelection all = PdfTextSelection(
      anchor: const PdfTextHit(page: 0, run: 0, offset: 0),
      extent: PdfTextHit(page: 0, run: 2, offset: foot.text.length),
    );
    final List<({int page, Rect rect})> boxes = all.boxes(<PdfDisplayList>[
      page,
    ]);
    expect(boxes, hasLength(3));
    expect(boxes.every((({int page, Rect rect}) box) => box.page == 0), isTrue);
    expect(boxes[1].rect.width, greaterThan(200));
  });

  test('find highlights the matching span on its page only', () {
    const PdfTextRun other = PdfTextRun(
      text: 'alpha',
      x: 10,
      y: 10,
      width: 40,
      height: 12,
    );
    const PdfTextRun hello = PdfTextRun(
      text: 'Hel',
      x: 10,
      y: 30,
      width: 24,
      height: 12,
    );
    const PdfTextRun lo = PdfTextRun(
      text: 'lo world',
      x: 34,
      y: 30,
      width: 70,
      height: 12,
    );
    final PdfPageInfo info = const PdfPageInfo(
      index: 0,
      mediaBox: PdfBox(llx: 0, lly: 0, urx: 300, ury: 400),
      cropBox: PdfBox(llx: 0, lly: 0, urx: 300, ury: 400),
    );
    final List<PdfFindMark> hits = PdfFind.search(<PdfDisplayList>[
      PdfDisplayList(page: info, runs: <PdfTextRun>[other]),
      PdfDisplayList(page: info, runs: <PdfTextRun>[hello, lo]),
    ], 'hello');
    expect(hits, hasLength(1));
    expect(hits.single.page, 1);
    expect(hits.single.rects, isNotEmpty);
    expect(PdfFind.fold('الإغلاق'), PdfFind.fold('الاغلاق'));
    expect(
      PdfFind.search(<PdfDisplayList>[
        PdfDisplayList(
          page: info,
          runs: const <PdfTextRun>[
            PdfTextRun(text: 'الاغلاق', x: 10, y: 10, width: 60, height: 14),
          ],
        ),
      ], 'الإغلاق'),
      hasLength(1),
    );
  });
}
