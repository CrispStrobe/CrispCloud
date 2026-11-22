import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _boundaryKey = ValueKey('page-text-picture-image');
const _retainedKey = ValueKey('retained-page-text-picture');
const _config = OfficeSurfaceConfig(
  theme: OfficeTheme.dark,
  mode: OfficeInteractionMode.selecting,
  showRulers: false,
);

WmlParagraph _paragraph(String text) => WmlParagraph(
  inlines: [
    WmlRun(
      text: text,
      properties: WmlRunProps(color: '0563C1', fontSizeHalfPoints: 28),
    ),
  ],
);

final class _Fixture {
  _Fixture() {
    table = WmlTable(
      grid: [130, 130],
      rows: [
        for (var row = 0; row < 2; row++)
          WmlTableRow(
            cells: [
              for (var column = 0; column < 2; column++)
                WmlTableCell(
                  width: 130,
                  blocks: [_paragraph('Cell $row $column')],
                ),
            ],
          ),
      ],
    );
    document = WmlDocument(
      sections: [
        WmlSection(
          pageSize: const WmlPageSize(width: 320, height: 280),
          margins: const WmlPageMargins(
            top: 35,
            bottom: 35,
            left: 20,
            right: 20,
          ),
          header: [_paragraph('Header')],
          footer: [_paragraph('Footer')],
          blocks: [_paragraph('Body accent'), table],
        ),
      ],
    );
    layout = WordLayoutEngine(font: null).layout(document);
  }

  late final WmlTable table;
  late final WmlDocument document;
  late final LaidOutDocument layout;
  final caret = CaretEngine();
  var selectedTable = false;
  var selectedBand = false;
  var editingHeader = false;
  var editingFooter = false;

  Future<RenderWordCanvas> mount(WidgetTester tester, Key key) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: _boundaryKey,
          child: WordCanvas(
            key: key,
            document: document,
            laidOut: layout,
            caret: caret,
            config: _config,
            selectedTable: selectedTable ? table : null,
            selectedTableBand: selectedBand
                ? (table: table, column: false, from: 0, to: 0)
                : null,
            editingHeader: editingHeader,
            editingFooter: editingFooter,
            storyParagraphs: editingHeader
                ? document.sections.single.header
                : editingFooter
                ? document.sections.single.footer
                : null,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    return tester.renderObject<RenderWordCanvas>(find.byType(WordCanvas));
  }
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return Uint8List.fromList(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  for (final transition in [
    'table band',
    'whole table',
    'mutable cross-cell selection',
    'header editing',
    'footer editing',
  ]) {
    testWidgets('cached dark page matches fresh after $transition', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(520, 460);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fixture = _Fixture();
      final retained = await fixture.mount(tester, _retainedKey);
      final initial = await _pixels(tester);
      switch (transition) {
        case 'table band':
          fixture.selectedBand = true;
        case 'whole table':
          fixture.selectedTable = true;
        case 'mutable cross-cell selection':
          fixture.caret
            ..selectionAnchorParagraph = 1
            ..selectionAnchor = 0
            ..paragraphIndex = 2
            ..logicalIndex = 5;
        case 'header editing':
          fixture.editingHeader = true;
        case 'footer editing':
          fixture.editingFooter = true;
      }
      if (transition == 'mutable cross-cell selection') {
        // Pointer-driven selections mutate the existing caret and repaint
        // without replacing the widget, layout or caret object.
        retained.markNeedsPaint();
        await tester.pump();
      } else {
        expect(await fixture.mount(tester, _retainedKey), same(retained));
      }
      final cached = await _pixels(tester);
      final freshKey = UniqueKey();
      final freshCanvas = await fixture.mount(tester, freshKey);
      final fresh = await _pixels(tester);
      expect(fresh, isNot(orderedEquals(initial)));
      expect(
        cached,
        orderedEquals(fresh),
        reason: 'The retained full-page text layer must use current ink.',
      );

      fixture
        ..selectedTable = false
        ..selectedBand = false
        ..editingHeader = false
        ..editingFooter = false;
      fixture.caret
        ..paragraphIndex = 0
        ..logicalIndex = 0
        ..collapseSelection();
      if (transition == 'mutable cross-cell selection') {
        freshCanvas.markNeedsPaint();
        await tester.pump();
      } else {
        expect(await fixture.mount(tester, freshKey), same(freshCanvas));
      }
      final restored = await _pixels(tester);
      await fixture.mount(tester, UniqueKey());
      expect(
        restored,
        orderedEquals(await _pixels(tester)),
        reason: 'Leaving the selection or story must restore current ink.',
      );
    });
  }
}
