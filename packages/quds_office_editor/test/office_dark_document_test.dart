import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _boundary = ValueKey('dark-document');

class _Raster {
  _Raster(this.width, this.height, this.bytes);

  final int width;
  final int height;
  final List<int> bytes;

  int count(ui.Rect area, int rgb, {int tolerance = 3}) {
    var found = 0;
    for (
      var y = area.top.floor().clamp(0, height);
      y < area.bottom.ceil().clamp(0, height);
      y++
    ) {
      for (
        var x = area.left.floor().clamp(0, width);
        x < area.right.ceil().clamp(0, width);
        x++
      ) {
        final offset = (y * width + x) * 4;
        if ((bytes[offset] - ((rgb >> 16) & 255)).abs() <= tolerance &&
            (bytes[offset + 1] - ((rgb >> 8) & 255)).abs() <= tolerance &&
            (bytes[offset + 2] - (rgb & 255)).abs() <= tolerance) {
          found++;
        }
      }
    }
    return found;
  }
}

Future<_Raster> _paint(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _boundary,
          child: SizedBox(width: 700, height: 550, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return _Raster(image.width, image.height, data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

WmlParagraph _paragraph(
  String text, {
  String? fill,
  String? highlight,
  String color = '000000',
}) => WmlParagraph(
  properties: WmlParagraphProps(shadingFill: fill, spacingAfter: 12),
  inlines: <WmlInline>[
    WmlRun(
      text: text,
      properties: WmlRunProps(
        color: color,
        highlight: highlight,
        fontSizeHalfPoints: 40,
      ),
    ),
  ],
);

double _contrast(ui.Color ink, ui.Color background) {
  final a = ui.Color.alphaBlend(ink, background).computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  test('dark ink policy preserves light backgrounds and readable colors', () {
    const theme = OfficeTheme.dark;
    const black = ui.Color(0xFF000000);
    const blue = ui.Color(0xFF0563C1);
    const white = ui.Color(0xFFFFFFFF);
    expect(theme.resolveDocumentColor(black), theme.documentText);
    expect(theme.resolveDocumentColor(black, background: white), black);
    expect(theme.resolveDocumentColor(white), white);
    expect(OfficeTheme.light.resolveDocumentColor(black), black);
    expect(
      theme.copyWith(adaptDocumentColors: false).resolveDocumentColor(black),
      black,
    );
    final displayBlue = theme.resolveDocumentColor(blue);
    expect(
      _contrast(displayBlue, theme.pageBackground),
      greaterThanOrEqualTo(4.5),
    );
    expect(displayBlue.b, greaterThan(displayBlue.r));
    expect(theme.resolveDocumentColor(blue, background: white), blue);
    final translucent = theme.resolveDocumentColor(
      black.withValues(alpha: 0.8),
    );
    expect(translucent.a, 0.8);
  });

  testWidgets('Word dark paper respects fills, highlights and exported ink', (
    tester,
  ) async {
    final plain = _paragraph('Readable on dark paper');
    final shaded = _paragraph('Black on pale shading', fill: 'FFF3CD');
    final highlighted = _paragraph(
      'Highlighted black ink',
      highlight: 'yellow',
    );
    final cell = _paragraph('Black table text');
    final framed = _paragraph('Black frame text');
    final explicitWhite = _paragraph('White on dark fill', color: 'FFFFFF');
    final document = WmlDocument.empty();
    document.sections.first.blocks = <WmlBlock>[
      plain,
      shaded,
      highlighted,
      WmlTable(
        grid: <double>[468],
        rows: <WmlTableRow>[
          WmlTableRow(
            cells: <WmlTableCell>[
              WmlTableCell(fillColor: 'FFFFFF', blocks: <WmlBlock>[cell]),
            ],
          ),
          WmlTableRow(
            cells: <WmlTableCell>[
              WmlTableCell(
                fillColor: '17365D',
                blocks: <WmlBlock>[explicitWhite],
              ),
            ],
          ),
        ],
      ),
      WmlFrame(
        x: 72,
        y: 370,
        width: 330,
        height: 65,
        fillColor: 'FFFFFF',
        blocks: <WmlBlock>[framed],
      ),
    ];
    final authored = document.paragraphs
        .expand((p) => p.inlines.whereType<WmlRun>())
        .map((run) => run.properties.color)
        .toList();
    final layout = WordLayoutEngine(font: null).layout(document);
    final raster = await _paint(
      tester,
      WordCanvas(
        document: document,
        laidOut: layout,
        caret: CaretEngine(),
        compact: true,
        config: const OfficeSurfaceConfig(
          theme: OfficeTheme.dark,
          mode: OfficeInteractionMode.viewing,
          showRulers: false,
        ),
      ),
    );
    ui.Rect textArea(WmlParagraph paragraph) {
      final line = layout.pages.first.lines.firstWhere(
        (line) => identical(line.sourceParagraph, paragraph),
      );
      return ui.Rect.fromLTWH(line.x, line.y, line.width, line.height);
    }

    expect(raster.count(textArea(plain), 0xF2F2F2), greaterThan(25));
    for (final paragraph in <WmlParagraph>[shaded, highlighted, cell, framed]) {
      expect(
        raster.count(textArea(paragraph), 0x000000),
        greaterThan(25),
        reason: '${paragraph.text} must remain dark on its light backing',
      );
    }
    expect(raster.count(textArea(explicitWhite), 0xFFFFFF), greaterThan(25));
    expect(
      document.paragraphs
          .expand((p) => p.inlines.whereType<WmlRun>())
          .map((run) => run.properties.color),
      authored,
    );
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    expect(
      reopened.paragraphs
          .expand((p) => p.inlines.whereType<WmlRun>())
          .map((run) => run.properties.color),
      authored,
    );
  });

  testWidgets('Sheet dark ink follows explicit and conditional cell backing', (
    tester,
  ) async {
    final sheet = SmlWorksheet(
      name: 'Contrast',
      sheetId: 1,
      columnWidths: <int, double>{0: 160, 1: 160, 2: 160, 3: 160},
      rowHeights: <int, double>{0: 40, 1: 40},
    );
    for (final address in <String>['A1', 'B1', 'C1', 'D1', 'A2']) {
      sheet.cellA1(address)
        ..value = 'Readable'
        ..fontSize = 20;
    }
    sheet.cellA1('A1').fontRgb = '000000';
    sheet.cellA1('B1')
      ..fontRgb = '000000'
      ..fillRgb = 'FFFF99';
    sheet.cellA1('C1')
      ..fontRgb = 'FFFFFF'
      ..fillRgb = '17365D';
    sheet.cellA1('A2').fillRgb = 'FFFFFF';
    sheet.conditionalFormats.add(
      SmlConditionalRule(
        range: SmlRange.parse('D1'),
        kind: SmlConditionalKind.expression,
        formula: 'TRUE',
        fillRgb: 'DDFFDD',
        fontRgb: '000000',
      ),
    );
    final conditionalState = sheet.conditionalFormatState();
    final raster = await _paint(
      tester,
      SheetGrid(
        sheet: sheet,
        selection: SelectionMatrix(),
        config: const OfficeSurfaceConfig(
          theme: OfficeTheme.dark,
          mode: OfficeInteractionMode.viewing,
          showFormulaBar: false,
          showGridHeaders: false,
          showGridlines: false,
        ),
      ),
    );
    expect(
      raster.count(const ui.Rect.fromLTWH(1, 1, 158, 38), 0xF2F2F2),
      greaterThan(15),
    );
    expect(
      raster.count(const ui.Rect.fromLTWH(161, 1, 158, 38), 0x000000),
      greaterThan(15),
    );
    expect(
      raster.count(const ui.Rect.fromLTWH(321, 1, 158, 38), 0xFFFFFF),
      greaterThan(15),
    );
    expect(
      raster.count(const ui.Rect.fromLTWH(481, 1, 158, 38), 0x000000),
      greaterThan(15),
    );
    expect(
      raster.count(const ui.Rect.fromLTWH(1, 41, 158, 38), 0x222222),
      greaterThan(15),
    );
    expect(sheet.cellA1('A1').fontRgb, '000000');
    expect(sheet.cellA1('C1').fontRgb, 'FFFFFF');
    expect(sheet.cellA1('A2').fontRgb, isEmpty);
    expect(sheet.conditionalFormatState(), conditionalState);
  });
}
