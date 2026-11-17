import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _boundaryKey = ValueKey('conditional-grid');
const _config = OfficeSurfaceConfig(
  mode: OfficeInteractionMode.viewing,
  showFormulaBar: false,
  showGridHeaders: false,
  showGridlines: false,
);

int _pixelsOf(Uint8List pixels, int rgb) {
  var count = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    if ((pixels[i] << 16 | pixels[i + 1] << 8 | pixels[i + 2]) == rgb &&
        pixels[i + 3] == 255) {
      count++;
    }
  }
  return count;
}

Future<Uint8List> _paint(
  WidgetTester tester,
  SmlWorksheet sheet, {
  SmlWorkbook? workbook,
  bool frozen = false,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _boundaryKey,
          child: SizedBox(
            width: 256,
            height: 100,
            child: SheetGrid(
              sheet: sheet,
              workbook: workbook,
              selection: SelectionMatrix(
                anchor: const SmlCellRef(8, 8),
                focus: const SmlCellRef(8, 8),
              ),
              config: _config,
              frozenRows: frozen ? 1 : 0,
              frozenCols: frozen ? 1 : 0,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
}

SmlWorksheet _sheet({
  String text = 'sample',
  String fill = '',
  String font = '',
}) {
  final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
  sheet.cellA1('A1')
    ..value = text
    ..fillRgb = fill
    ..fontRgb = font;
  return sheet;
}

SmlConditionalRule _rule({
  required int priority,
  String fill = '',
  String font = '',
  String formula = 'TRUE',
  bool stop = false,
  String range = 'A1',
}) => SmlConditionalRule(
  range: SmlRange.parse(range),
  kind: SmlConditionalKind.expression,
  priority: priority,
  formula: formula,
  fillRgb: fill,
  fontRgb: font,
  stopIfTrue: stop,
);

void main() {
  testWidgets('grid paints priority and independent property cascade', (
    tester,
  ) async {
    final actual = _sheet();
    actual.conditionalFormats.addAll([
      _rule(priority: 8, fill: '0000FF', font: '008800'),
      _rule(priority: 1, fill: 'FF0000'),
    ]);
    final before = actual.conditionalFormatState();
    final pixels = await _paint(tester, actual);
    final reference = await _paint(
      tester,
      _sheet(fill: 'FF0000', font: '008800'),
    );
    expect(listEquals(pixels, reference), isTrue);
    expect(_pixelsOf(pixels, 0xff0000), greaterThan(100));
    expect(_pixelsOf(pixels, 0x008800), greaterThan(0));
    expect(actual.conditionalFormatState(), before);
    expect(actual.allCells, hasLength(1));
  });

  testWidgets('font-only rule retains ordinary cell fill', (tester) async {
    final actual = _sheet(fill: 'FFCC00', font: 'FF0000');
    actual.conditionalFormats.add(_rule(priority: 1, font: '008800'));
    final pixels = await _paint(tester, actual);
    final reference = await _paint(
      tester,
      _sheet(fill: 'FFCC00', font: '008800'),
    );
    expect(listEquals(pixels, reference), isTrue);
  });

  testWidgets('unstyled stopping rule keeps ordinary fill and font', (
    tester,
  ) async {
    final actual = _sheet(fill: 'FFCC00', font: '008800');
    actual.conditionalFormats.addAll([
      _rule(priority: 1, stop: true),
      _rule(priority: 2, fill: 'FF0000', font: '0000FF'),
    ]);
    final pixels = await _paint(tester, actual);
    final reference = await _paint(
      tester,
      _sheet(fill: 'FFCC00', font: '008800'),
    );
    expect(listEquals(pixels, reference), isTrue);
  });

  testWidgets(
    'cross-sheet expression colors absent cells without creating them',
    (tester) async {
      final actual = SmlWorksheet(name: 'Data', sheetId: 1);
      final other = SmlWorksheet(name: 'Control', sheetId: 2)
        ..cellA1('B1').value = 7;
      final book = SmlWorkbook(sheets: [actual, other]);
      actual.conditionalFormats.add(
        _rule(priority: 1, fill: '12AB34', formula: r'Control!$B$1=7'),
      );
      final pixels = await _paint(tester, actual, workbook: book);
      final reference = await _paint(tester, _sheet(text: '', fill: '12AB34'));
      expect(listEquals(pixels, reference), isTrue);
      expect(_pixelsOf(pixels, 0x12ab34), greaterThan(100));
      expect(actual.rows, isEmpty);
      expect(other.allCells, hasLength(1));
    },
  );

  testWidgets('grid refresh observes later referenced cell edits', (
    tester,
  ) async {
    final actual = _sheet();
    actual.cellA1('B1').value = 2;
    actual.conditionalFormats.add(
      _rule(priority: 1, fill: '12AB34', formula: 'B1>5'),
    );
    final initial = await _paint(tester, actual);
    actual.cellA1('B1').value = 9;
    final after = await _paint(tester, actual);
    final reference = _sheet(fill: '12AB34')..cellA1('B1').value = 9;
    expect(listEquals(after, await _paint(tester, reference)), isTrue);
    expect(listEquals(initial, after), isFalse);
  });

  testWidgets('merged frozen cells use their anchor conditional style', (
    tester,
  ) async {
    final actual = _sheet()..merges.add(SmlMerge(c0: 0, r0: 0, c1: 1, r1: 1));
    actual.conditionalFormats.add(
      _rule(priority: 1, fill: '12AB34', font: '880000'),
    );
    final reference = _sheet(fill: '12AB34', font: '880000')
      ..merges.add(SmlMerge(c0: 0, r0: 0, c1: 1, r1: 1));
    final pixels = await _paint(tester, actual, frozen: true);
    expect(
      listEquals(pixels, await _paint(tester, reference, frozen: true)),
      isTrue,
    );
    expect(actual.allCells, hasLength(1));
  });

  testWidgets('editor supplies workbook scope to the rendered sheet', (
    tester,
  ) async {
    final book = SmlWorkbook(
      sheets: [
        _sheet(),
        SmlWorksheet(name: 'Other', sheetId: 2),
      ],
    );
    final controller = SheetEditorController(workbook: book, config: _config);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: QudsSheetEditor(controller: controller),
      ),
    );
    final grid = tester.widget<SheetGrid>(find.byType(SheetGrid));
    expect(grid.workbook, same(book));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
