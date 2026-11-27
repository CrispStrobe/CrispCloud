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
  double zoom = 1,
  bool editing = false,
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
                anchor: editing
                    ? const SmlCellRef(0, 0)
                    : const SmlCellRef(8, 8),
                focus: editing
                    ? const SmlCellRef(0, 0)
                    : const SmlCellRef(8, 8),
              ),
              config: _config,
              viewport: VirtualViewport(scale: zoom),
              editing: editing,
              editText: editing ? sheet.cellA1('A1').asString : '',
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
  testWidgets('native cell borders remain visible with gridlines off', (
    tester,
  ) async {
    final sheet = _sheet(text: '');
    sheet.cellA1('A1').styleIndex = 1;
    final book = SmlWorkbook(
      sheets: [sheet],
      styles: SmlStyleSheet.parse(
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<borders count="2"><border/><border>'
        '<right style="medium"><color rgb="FF8833CC"/></right>'
        '<bottom style="thin"><color rgb="FF22AA55"/></bottom>'
        '</border></borders><cellXfs count="2">'
        '<xf borderId="0"/><xf borderId="1"/></cellXfs></styleSheet>',
      ),
    );
    final pixels = await _paint(tester, sheet, workbook: book);
    expect(_pixelsOf(pixels, 0x8833CC), greaterThan(10));
    expect(_pixelsOf(pixels, 0x22AA55), greaterThan(10));
  });

  testWidgets('general numbers align right while explicit left wins', (
    tester,
  ) async {
    final sheet = _sheet(text: '', font: 'E03060');
    final cell = sheet.cellA1('A1')..value = 123;
    double meanInkX(Uint8List pixels) {
      var sum = 0;
      var count = 0;
      for (var i = 0; i < pixels.length; i += 4) {
        if (pixels[i] == 0xE0 &&
            pixels[i + 1] == 0x30 &&
            pixels[i + 2] == 0x60) {
          sum += (i ~/ 4) % 256;
          count++;
        }
      }
      expect(count, greaterThan(0));
      return sum / count;
    }

    final general = meanInkX(await _paint(tester, sheet));
    cell.horizontalAlign = SmlHAlign.left;
    final left = meanInkX(await _paint(tester, sheet));
    expect(general, greaterThan(left + 8));
  });

  testWidgets(
    'worksheet zoom scales cell text in both edit and display modes',
    (tester) async {
      final sheet = _sheet(text: 'MM', font: 'E03060');
      for (final editing in [false, true]) {
        final small = _pixelsOf(
          await _paint(tester, sheet, zoom: 0.60, editing: editing),
          0xE03060,
        );
        final large = _pixelsOf(
          await _paint(tester, sheet, zoom: 1.74, editing: editing),
          0xE03060,
        );
        expect(small, greaterThan(0));
        expect(large, greaterThan(small * 3), reason: 'editing=$editing');
      }
    },
  );

  testWidgets('icon sets visibly paint without mutating values or rules', (
    tester,
  ) async {
    final sheet = _sheet(text: '');
    sheet.cellA1('A1').value = 1;
    final before = await _paint(tester, sheet);
    sheet.conditionalFormats.add(
      SmlConditionalRule(
        range: SmlRange.parse('A1'),
        kind: SmlConditionalKind.iconSet,
        colorScaleStops: const [
          SmlColorScaleStop(type: 'num', value: 0, colorRgb: 'F8696B'),
          SmlColorScaleStop(type: 'num', value: 50, colorRgb: 'FFEB84'),
          SmlColorScaleStop(type: 'num', value: 100, colorRgb: '63BE7B'),
        ],
      ),
    );
    final state = sheet.conditionalFormatState();
    final after = await _paint(tester, sheet);
    var changedPixels = 0;
    for (var i = 0; i < before.length; i += 4) {
      if (before[i] != after[i] ||
          before[i + 1] != after[i + 1] ||
          before[i + 2] != after[i + 2]) {
        changedPixels++;
      }
    }
    expect(changedPixels, greaterThan(20));
    expect(sheet.cellA1('A1').value, 1);
    expect(sheet.conditionalFormatState(), state);
  });

  testWidgets('data bars visibly paint without changing cell values', (
    tester,
  ) async {
    final sheet = _sheet(text: '');
    sheet.cellA1('A1').value = 1;
    sheet.cellA1('B1').value = 5;
    sheet.cellA1('C1').value = 10;
    final before = await _paint(tester, sheet);
    sheet.conditionalFormats.add(
      SmlConditionalRule(
        range: SmlRange.parse('A1:C1'),
        kind: SmlConditionalKind.dataBar,
        dataBarColor: '008800',
        colorScaleStops: const [
          SmlColorScaleStop(type: 'min', colorRgb: '008800'),
          SmlColorScaleStop(type: 'max', colorRgb: '008800'),
        ],
      ),
    );
    final state = sheet.conditionalFormatState();
    final after = await _paint(tester, sheet);
    var changedPixels = 0;
    for (var i = 0; i < before.length; i += 4) {
      if (before[i] != after[i] ||
          before[i + 1] != after[i + 1] ||
          before[i + 2] != after[i + 2] ||
          before[i + 3] != after[i + 3]) {
        changedPixels++;
      }
    }
    expect(changedPixels, greaterThan(100));
    expect(sheet.cellA1('A1').value, 1);
    expect(sheet.cellA1('B1').value, 5);
    expect(sheet.cellA1('C1').value, 10);
    expect(sheet.conditionalFormatState(), state);
  });

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
