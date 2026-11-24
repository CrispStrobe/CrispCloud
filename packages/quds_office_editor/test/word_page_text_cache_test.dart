import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

enum _InkTransition {
  selectBand('selecting a table band'),
  moveBand('moving a table band within the same table'),
  selectTable('selecting a whole table'),
  selectAcrossCells('extending the shared caret across cells'),
  enterHeader('entering header editing'),
  leaveHeader('leaving header editing'),
  enterFooter('entering footer editing'),
  leaveFooter('leaving footer editing');

  const _InkTransition(this.description);

  final String description;
}

WmlParagraph _paragraph(String text) => WmlParagraph(
  inlines: [
    WmlRun(
      text: text,
      properties: WmlRunProps(color: '0563C1', fontSizeHalfPoints: 32),
    ),
  ],
);

int _differentBytes(Uint8List actual, Uint8List expected) {
  expect(actual.length, expected.length);
  var result = 0;
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) result++;
  }
  return result;
}

void main() {
  testWidgets(
    'overlay painters are reused until their effective style changes',
    (tester) async {
      final header = _paragraph('Header text');
      final document = WmlDocument(
        sections: [
          WmlSection(
            pageSize: const WmlPageSize(width: 300, height: 300),
            header: [header],
            footer: [_paragraph('Footer text')],
            blocks: [_paragraph('Body text')],
          ),
        ],
      );
      final layout = WordLayoutEngine(font: null).layout(document);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: WordCanvas(
            document: document,
            laidOut: layout,
            caret: CaretEngine(),
            config: const OfficeSurfaceConfig(showRulers: false),
          ),
        ),
      );
      final canvas = tester.renderObject<RenderWordCanvas>(
        find.byType(WordCanvas),
      );
      final initial = canvas.debugOverlayPainterBuildCount;
      expect(initial, 2);
      for (var frame = 0; frame < 4; frame++) {
        canvas.markNeedsPaint();
        await tester.pump();
      }
      expect(canvas.debugOverlayPainterBuildCount, initial);

      // Header edit previews can change the run style before a new layout.
      header.inlines.whereType<WmlRun>().single.properties.italic = true;
      canvas.markNeedsPaint();
      await tester.pump();
      expect(canvas.debugOverlayPainterBuildCount, initial + 1);

      canvas.systemFontsDidChange();
      await tester.pump();
      expect(canvas.debugOverlayPainterBuildCount, initial + 3);
      expect(tester.takeException(), isNull);
    },
  );

  for (final transition in _InkTransition.values) {
    testWidgets(
      '${transition.description} repaints the same ink as a fresh canvas',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(500, 500);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final table = WmlTable(
          grid: [120, 120],
          rows: [
            for (var row = 0; row < 2; row++)
              WmlTableRow(
                cells: [
                  for (var column = 0; column < 2; column++)
                    WmlTableCell(
                      width: 120,
                      blocks: [_paragraph('Cell $row $column')],
                    ),
                ],
              ),
          ],
        );
        final section = WmlSection(
          pageSize: const WmlPageSize(width: 300, height: 300),
          margins: const WmlPageMargins(
            top: 60,
            bottom: 60,
            left: 20,
            right: 20,
            header: 15,
            footer: 15,
          ),
          header: [_paragraph('Header text')],
          footer: [_paragraph('Footer text')],
          blocks: [table],
        );
        final document = WmlDocument(sections: [section]);
        final layout = WordLayoutEngine(font: null).layout(document);
        final caret = CaretEngine();
        const boundaryKey = ValueKey('page-text-cache-image');
        const retainedKey = ValueKey('retained-page-text-canvas');
        const config = OfficeSurfaceConfig(
          mode: OfficeInteractionMode.selecting,
          theme: OfficeTheme.dark,
          showRulers: false,
        );

        Future<void> mount(Key key, {required bool finalState}) async {
          final header = switch (transition) {
            _InkTransition.enterHeader => finalState,
            _InkTransition.leaveHeader => !finalState,
            _ => false,
          };
          final footer = switch (transition) {
            _InkTransition.enterFooter => finalState,
            _InkTransition.leaveFooter => !finalState,
            _ => false,
          };
          final bandRow = switch (transition) {
            _InkTransition.selectBand => finalState ? 0 : null,
            _InkTransition.moveBand => finalState ? 1 : 0,
            _ => null,
          };
          if (transition == _InkTransition.selectAcrossCells && finalState) {
            // Mutate the existing object exactly as a caret-only refresh does.
            // RenderObject's previous caret reference already sees this state.
            caret
              ..selectionAnchorParagraph = 0
              ..selectionAnchor = 0
              ..paragraphIndex = 1
              ..logicalIndex = 2;
          }
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: RepaintBoundary(
                key: boundaryKey,
                child: WordCanvas(
                  key: key,
                  document: document,
                  laidOut: layout,
                  caret: caret,
                  selectedTable:
                      transition == _InkTransition.selectTable && finalState
                      ? table
                      : null,
                  selectedTableBand: bandRow == null
                      ? null
                      : (
                          table: table,
                          column: false,
                          from: bandRow,
                          to: bandRow,
                        ),
                  editingHeader: header,
                  editingFooter: footer,
                  storyParagraphs: header
                      ? section.header
                      : footer
                      ? section.footer
                      : null,
                  config: config,
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        }

        Future<Uint8List> pixels() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(boundaryKey),
          );
          final image = (await tester.runAsync(
            () => boundary.toImage(pixelRatio: 1),
          ))!;
          final data = (await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
          ))!;
          final result = Uint8List.fromList(data.buffer.asUint8List());
          image.dispose();
          return result;
        }

        await mount(retainedKey, finalState: false);
        final before = await pixels();
        final retained = tester.renderObject<RenderWordCanvas>(
          find.byType(WordCanvas),
        );
        await mount(retainedKey, finalState: true);
        expect(
          tester.renderObject<RenderWordCanvas>(find.byType(WordCanvas)),
          same(retained),
        );
        final cached = await pixels();
        await mount(UniqueKey(), finalState: true);
        final fresh = await pixels();
        expect(
          _differentBytes(before, fresh),
          greaterThan(0),
          reason: 'The transition must visibly exercise the paint context.',
        );
        expect(
          _differentBytes(cached, fresh),
          0,
          reason:
              'The retained noncompact canvas must recompute adaptive ink '
              'when the table or story background changes.',
        );
      },
    );
  }
}
