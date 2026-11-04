import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const String _x = OfficeNamespaces.x;

OpcPackage _package(String sheetData, {String drawing = ''}) {
  final OpcPackage package = OpcPackage.create(OpcPackageKind.sheet);
  package
      .getPart('/xl/worksheets/sheet1.xml')!
      .writeText(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="$_x" xmlns:r="${OfficeNamespaces.r}">'
        '<sheetData>$sheetData</sheetData>$drawing</worksheet>',
      );
  return package;
}

SmlWorkbook _open(String sheetData) =>
    SheetDeserializer().read(_package(sheetData));

SmlCell _cell(SmlWorkbook book, String a1) =>
    book.sheets.first.cell(SmlCellRef.parse(a1));

/// A sheet with one chart whose series has `c:f` references but no caches.
SmlWorkbook _openChart(String sheetData, {required String cat, String? val}) {
  final OpcPackage package = _package(
    sheetData,
    drawing: '<drawing r:id="rIdDrawing"/>',
  );
  package
      .relationshipsFor('/xl/worksheets/sheet1.xml')
      .add(
        type: RelationshipTypes.drawing,
        target: '../drawings/drawing1.xml',
        id: 'rIdDrawing',
      );
  package.createPart(
    '/xl/drawings/drawing1.xml',
    OfficeContentTypes.spreadsheetDrawing,
    utf8.encode(
      '<xdr:wsDr xmlns:xdr="${OfficeNamespaces.xdr}" '
      'xmlns:a="${OfficeNamespaces.a}" xmlns:r="${OfficeNamespaces.r}" '
      'xmlns:c="${OfficeNamespaces.c}"><xdr:twoCellAnchor>'
      '<xdr:from><xdr:col>3</xdr:col><xdr:colOff>0</xdr:colOff>'
      '<xdr:row>1</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
      '<xdr:graphicFrame><xdr:nvGraphicFramePr>'
      '<xdr:cNvPr id="2" name="Chart 1"/></xdr:nvGraphicFramePr>'
      '<xdr:xfrm><a:off x="0" y="0"/><a:ext cx="3600000" cy="2160000"/>'
      '</xdr:xfrm><a:graphic><a:graphicData>'
      '<c:chart r:id="rIdChart"/></a:graphicData></a:graphic>'
      '</xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor></xdr:wsDr>',
    ),
  );
  package
      .relationshipsFor('/xl/drawings/drawing1.xml')
      .add(
        type: RelationshipTypes.chart,
        target: '../charts/chart1.xml',
        id: 'rIdChart',
      );
  package.createPart(
    '/xl/charts/chart1.xml',
    OfficeContentTypes.drawingChart,
    utf8.encode(
      '<c:chartSpace xmlns:c="${OfficeNamespaces.c}"><c:chart><c:plotArea>'
      '<c:barChart><c:ser><c:idx val="0"/>'
      '<c:cat><c:strRef><c:f>$cat</c:f></c:strRef></c:cat>'
      '<c:val><c:numRef><c:f>${val ?? r"Sheet1!$B$1:$B$3"}</c:f>'
      '</c:numRef></c:val></c:ser></c:barChart></c:plotArea></c:chart>'
      '</c:chartSpace>',
    ),
  );
  final SmlWorkbook book = SheetDeserializer().read(package);
  FormulaEvaluator.recalculate(book);
  SheetChartData.refreshWorkbook(book);
  return book;
}

void main() {
  group('headers and footers', () {
    test('font codes stay inside their section', () {
      final SmlWorkbook book = SheetDeserializer().read(
        _package(
          '',
          drawing:
              '<headerFooter><oddHeader>&amp;L&amp;"Arial,Bold"&amp;14Q3 '
              '&amp;&amp; Q4&amp;C&amp;"Times New Roman,Regular"&amp;12&amp;A'
              '</oddHeader><oddFooter>&amp;RPage &amp;P of &amp;N'
              '</oddFooter></headerFooter>',
        ),
      );
      final SmlHeaderFooter hf = book.sheets.first.headerFooter!;
      expect(hf.headerLeft, '&"Arial,Bold"&14Q3 && Q4');
      expect(hf.headerCenter, '&"Times New Roman,Regular"&12&A');
      expect(hf.headerRight, isEmpty);
      expect(hf.footerRight, 'Page &P of &N');

      final SmlHeaderFooter again = SheetDeserializer()
          .read(SheetSerializer().write(book))
          .sheets
          .first
          .headerFooter!;
      expect(again.headerLeft, hf.headerLeft);
      expect(again.headerCenter, hf.headerCenter);
      expect(again.footerRight, hf.footerRight);
    });

    test('text without a section code is centered', () {
      final SmlWorkbook book = SheetDeserializer().read(
        _package(
          '',
          drawing: '<headerFooter><oddHeader>Budget</oddHeader></headerFooter>',
        ),
      );
      expect(book.sheets.first.headerFooter!.headerCenter, 'Budget');
    });
  });

  group('cell import', () {
    test(
      'inlineStr cells keep their text, rich runs joined, phonetics off',
      () {
        final SmlWorkbook book = _open(
          '<row r="1">'
          '<c r="A1" t="inlineStr"><is><t>Region</t></is></c>'
          '<c r="B1" t="inlineStr"><is><r><t>Gross </t></r><r><rPr><b/></rPr>'
          '<t>margin</t></r><rPh sb="0" eb="1"><t>X</t></rPh></is></c>'
          '</row>',
        );
        expect(_cell(book, 'A1').type, SmlCellType.string);
        expect(_cell(book, 'A1').asString, 'Region');
        expect(_cell(book, 'B1').asString, 'Gross margin');
      },
    );

    test('shared formulas expand from the master to every follower', () {
      final SmlWorkbook book = _open(
        '<row r="1"><c r="A1"><v>1</v></c><c r="B1"><v>1</v></c>'
        '<c r="C1"><f t="shared" ref="C1:C4" si="0">A1*B1+1</f><v>2</v></c>'
        '</row>'
        '<row r="2"><c r="A2"><v>3</v></c><c r="B2"><v>3</v></c>'
        '<c r="C2"><f t="shared" si="0"/><v>10</v></c></row>'
        '<row r="3"><c r="A3"><v>5</v></c><c r="B3"><v>5</v></c>'
        '<c r="C3"><f t="shared" si="0"/><v>26</v></c></row>'
        '<row r="4"><c r="A4"><v>6</v></c><c r="B4"><v>7</v></c>'
        '<c r="C4"><f t="shared" si="0"/><v>43</v></c></row>',
      );
      expect(_cell(book, 'C2').formula, 'A2*B2+1');
      expect(_cell(book, 'C4').formula, 'A4*B4+1');
      FormulaEvaluator.recalculate(book);
      expect(
        <Object?>[
          for (final String a1 in <String>['C1', 'C2', 'C3', 'C4'])
            _cell(book, a1).value,
        ],
        <Object?>[2, 10, 26, 43],
      );
    });

    test('a follower without its master keeps the cached value', () {
      final SmlWorkbook book = _open(
        '<row r="2"><c r="C2"><f t="shared" si="7"/><v>12</v></c></row>',
      );
      expect(_cell(book, 'C2').formula, isNull);
      FormulaEvaluator.recalculate(book);
      expect(_cell(book, 'C2').asNumber, 12);
    });

    test('recalc skips empty formulas and keeps cached values it cannot '
        'compute', () {
      final SmlWorkbook book = _open(
        '<row r="1"><c r="A1"><f></f><v>5</v></c>'
        '<c r="B1"><f>NOSUCHFUNCTION(1)</f><v>42</v></c>'
        '<c r="C1" t="str"><f>_xlfn.CONCAT("Item ","A")</f><v>stale</v></c>'
        '</row>',
      );
      FormulaEvaluator.recalculate(book);
      expect(_cell(book, 'A1').asNumber, 5);
      expect(_cell(book, 'B1').asNumber, 42);
      expect(_cell(book, 'C1').asString, 'Item A');
      expect(_cell(book, 'C1').formula, '_xlfn.CONCAT("Item ","A")');
    });
  });

  group('FormulaRefShift', () {
    test('moves relative parts and keeps absolute ones', () {
      expect(
        FormulaRefShift.shift(r'SUM(A1:B2)+$C$1+C$1+$D2', rows: 2, columns: 1),
        r'SUM(B3:C4)+$C$1+D$1+$D4',
      );
    });

    test('leaves function names and strings alone, #REF! off the grid', () {
      expect(
        FormulaRefShift.shift('LOG10(A2)&"A1"', rows: 1),
        'LOG10(A3)&"A1"',
      );
      expect(FormulaRefShift.shift('A1+1', rows: -1), '#REF!+1');
    });
  });

  group('charts without a value cache', () {
    const String data =
        '<row r="1"><c r="A1" t="inlineStr"><is><t>North</t></is></c>'
        '<c r="B1"><v>10</v></c></row>'
        '<row r="2"><c r="A2" t="inlineStr"><is><t>South</t></is></c>'
        '<c r="B2"><f>B1*2</f></c></row>'
        '<row r="3"><c r="A3"><v>2026</v></c><c r="B3"><v>5</v></c></row>';

    test('points come from the c:val range with c:cat labels', () {
      final SmlWorkbook book = _openChart(data, cat: r'Sheet1!$A$1:$A$3');
      final SmlDrawing drawing = book.sheets.first.drawings.single;
      expect(drawing.sourceFromA1, 'B1');
      expect(drawing.sourceToA1, 'B3');
      expect(drawing.labelsFromA1, 'A1');
      final List<ChartPoint> points = drawing.visual.points;
      expect(
        <String>[for (final ChartPoint p in points) p.label],
        <String>['North', 'South', '2026'],
      );
      expect(
        <double>[for (final ChartPoint p in points) p.value],
        <double>[10, 20, 5],
      );
    });

    test('quoted sheet names resolve; a missing sheet leaves points as-is', () {
      final SmlWorkbook book = _openChart(
        data,
        cat: r"'Sheet1'!$A$1:$A$3",
        val: r"'Sheet1'!$B$1:$B$3",
      );
      expect(book.sheets.first.drawings.single.visual.points, hasLength(3));

      final SmlWorkbook missing = _openChart(
        data,
        cat: r'Other!$A$1:$A$3',
        val: r'Other!$B$1:$B$3',
      );
      expect(missing.sheets.first.drawings.single.visual.points, isEmpty);
    });
  });
}
