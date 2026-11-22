import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  testWidgets('table-band repaint matches a fresh selection canvas', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 300);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final table = WmlTable(
      grid: [120, 120],
      rows: [
        WmlTableRow(
          cells: [
            for (final text in ['First cell', 'Second cell'])
              WmlTableCell(
                width: 120,
                blocks: [
                  WmlParagraph(inlines: [WmlRun(text: text)]),
                ],
              ),
          ],
        ),
      ],
    );
    final document = WmlDocument(
      sections: [
        WmlSection(
          pageSize: const WmlPageSize(width: 300, height: 220),
          margins: const WmlPageMargins(
            top: 20,
            bottom: 20,
            left: 20,
            right: 20,
          ),
          blocks: [table],
        ),
      ],
    );
    final layout = WordLayoutEngine(font: null).layout(document);
    final caret = CaretEngine()
      ..selectionAnchorParagraph = 0
      ..selectionAnchor = 1
      ..paragraphIndex = 0
      ..logicalIndex = 5;
    const boundaryKey = ValueKey('selection-cache-image');
    const retainedKey = ValueKey('retained-selection-canvas');
    final band = (table: table, column: false, from: 0, to: 0);

    Future<void> mount(Key key, {bool tableBand = false}) async {
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
              selectedTableBand: tableBand ? band : null,
              config: const OfficeSurfaceConfig(
                mode: OfficeInteractionMode.selecting,
                showRulers: false,
              ),
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

    await mount(retainedKey);
    final retained = tester.renderObject<RenderWordCanvas>(
      find.byType(WordCanvas),
    );
    await mount(retainedKey, tableBand: true);
    expect(
      tester.renderObject<RenderWordCanvas>(find.byType(WordCanvas)),
      same(retained),
    );
    final cachedPixels = await pixels();
    await mount(UniqueKey(), tableBand: true);
    final freshPixels = await pixels();
    expect(
      cachedPixels,
      orderedEquals(freshPixels),
      reason: 'Switching to a table band must not reuse the old text fill.',
    );
  });
}
