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
SmlWorkbook _openChart(
  String sheetData, {
  required String cat,
  String? val,
  String end = '',
  String extent = 'cx="3600000" cy="2160000"',
  String? chartXml,
}) {
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
      'xmlns:c="${OfficeNamespaces.c}"><xdr:twoCellAnchor editAs="oneCell">'
      '<xdr:from><xdr:col>3</xdr:col><xdr:colOff>0</xdr:colOff>'
      '<xdr:row>1</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
      '$end<xdr:graphicFrame><xdr:nvGraphicFramePr>'
      '<xdr:cNvPr id="2" name="Chart 1"/></xdr:nvGraphicFramePr>'
      '<xdr:xfrm><a:off x="0" y="0"/><a:ext $extent/>'
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
      chartXml ??
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
  test('two-cell chart bounds override zero transform and survive saving', () {
    final book = _openChart(
      '',
      cat: r'Sheet1!$A$1:$A$3',
      extent: 'cx="0" cy="0"',
      end:
          '<xdr:to><xdr:col>7</xdr:col><xdr:colOff>127000</xdr:colOff>'
          '<xdr:row>20</xdr:row><xdr:rowOff>254000</xdr:rowOff></xdr:to>',
    );
    final sheet = book.firstSheet;
    final drawing = sheet.drawings.single;
    final expectedWidth =
        (sheet.columnLeft(7) - sheet.columnLeft(3)) * .75 + 10;
    final expectedHeight = (sheet.rowTop(20) - sheet.rowTop(1)) * .75 + 20;
    expect(drawing.visual.width, closeTo(expectedWidth, .001));
    expect(drawing.visual.height, closeTo(expectedHeight, .001));

    SmlDrawing roundtrip(SmlWorkbook source) => SheetDeserializer()
        .readBytes(SheetSerializer().writeBytes(source))
        .firstSheet
        .drawings
        .single;
    final saved = roundtrip(book);
    expect(saved.twoCellEnd, (col: 7, row: 20, colEmu: 127000, rowEmu: 254000));
    expect(saved.twoCellEditAs, 'oneCell');
    expect(saved.visual.width, closeTo(expectedWidth, .001));
    expect(saved.visual.height, closeTo(expectedHeight, .001));

    drawing.visual.width += 30;
    final resized = roundtrip(book);
    expect(resized.twoCellEnd, isNull);
    expect(resized.visual.width, closeTo(expectedWidth + 30, .001));
  });

  test(
    'native XLSX line chart previews multiple series and retains sparse values',
    () {
      final book = _openChart(
        '',
        cat: '',
        chartXml:
            '''
<c:chartSpace xmlns:c="${OfficeNamespaces.c}" xmlns:a="${OfficeNamespaces.a}">
<c:lang val="de-DE"/>
<c:chart><c:title><c:tx><c:rich><a:p><a:r><a:rPr sz="1800" b="1"><a:latin typeface="Calibri"/></a:rPr><a:t>Trading results</a:t></a:r></a:p></c:rich></c:tx></c:title>
<c:plotArea><c:lineChart><c:grouping val="standard"/>
<c:ser><c:idx val="0"/><c:order val="0"/><c:tx><c:v>Retail</c:v></c:tx>
<c:spPr><a:ln><a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></a:ln></c:spPr>
<c:cat><c:strLit><c:ptCount val="3"/><c:pt idx="0"><c:v>April</c:v></c:pt><c:pt idx="1"><c:v>May</c:v></c:pt><c:pt idx="2"><c:v>June</c:v></c:pt></c:strLit></c:cat>
<c:val><c:numLit><c:ptCount val="3"/><c:pt idx="2"><c:v>20</c:v></c:pt><c:pt idx="0"><c:v>-10</c:v></c:pt></c:numLit></c:val></c:ser>
<c:ser><c:idx val="1"/><c:order val="1"/><c:tx><c:v>Services</c:v></c:tx><c:dLbls><c:showVal val="1"/></c:dLbls>
<c:spPr><a:ln><a:solidFill><a:srgbClr val="0000FF"/></a:solidFill></a:ln></c:spPr>
<c:val><c:numLit><c:ptCount val="3"/><c:pt idx="0"><c:v>3</c:v></c:pt><c:pt idx="1"><c:v>12</c:v></c:pt><c:pt idx="2"><c:v>7</c:v></c:pt></c:numLit></c:val></c:ser>
</c:lineChart><c:catAx><c:title><c:tx><c:rich><a:p><a:r><a:t>Month</a:t></a:r></a:p></c:rich></c:tx></c:title></c:catAx>
<c:valAx><c:majorGridlines/><c:crossBetween val="between"/></c:valAx></c:plotArea><c:legend/><c:dispBlanksAs val="gap"/></c:chart>
</c:chartSpace>''',
      );
      final reopened = SheetDeserializer().readBytes(
        SheetSerializer().writeBytes(book),
      );
      for (final version in [book, reopened]) {
        final visual = version.firstSheet.drawings.single.visual;
        final line = visual.importedLineChart!;
        expect(visual.title, 'Trading results');
        expect(visual.chart.titleSize, 18);
        expect(visual.chart.titleBold, isTrue);
        expect(visual.chart.titleFamily, 'Calibri');
        expect(line.categoryFraction(0), closeTo(1 / 6, 1e-9));
        expect(line.categoryFraction(2), closeTo(5 / 6, 1e-9));
        expect(line.pointLabel(0, 1234), isEmpty);
        expect(line.pointLabel(1, 1234), '1.234');
        expect(line.axisTicks.first, lessThanOrEqualTo(-10));
        expect(line.axisTicks.last, greaterThanOrEqualTo(20));
        expect(visual.chart.categoryTitle, 'Month');
        expect(line.categories, ['April', 'May', 'June']);
        expect(line.series.map((series) => series.name), [
          'Retail',
          'Services',
        ]);
        expect(line.series.map((series) => series.color), ['FF0000', '0000FF']);
        expect(line.series.first.points.map((point) => point.x), [0, 2]);
        expect(line.series.first.points.map((point) => point.value), [-10, 20]);
        expect(line.limits, (min: -10.0, max: 20.0));
        expect(line.connectGaps, isFalse);
      }
      final pdf = PdfFile.open(OfficePrint.workbook(reopened));
      final outs = [
        for (var i = 0; i < pdf.pageCount; i++)
          String.fromCharCodes(
            pdf.store.streamBytes(pdf.pageDict(i)['Contents'])!,
          ),
      ].join();
      expect(outs, contains('1 0 0 RG'));
      expect(outs, contains('0 0 1 RG'));
      expect(outs, contains('Retail'));
      expect(outs, contains('Services'));

      final sheet = reopened.firstSheet;
      final drawing = sheet.drawings.single
        ..sourceFromA1 = 'B1'
        ..sourceToA1 = 'B3'
        ..labelsFromA1 = 'A1'
        ..labelsToA1 = 'A3';
      sheet.cellA1('B1').value = -25;
      sheet.cellA1('B3').value = 50;
      SheetChartData.refreshDrawing(reopened, sheet, drawing);
      final updated = drawing.visual.importedLineChart!;
      expect(updated.series.first.points.map((point) => point.x), [0, 2]);
      expect(updated.series.first.points.map((point) => point.value), [
        -25,
        50,
      ]);
      expect(updated.series.last.points.map((point) => point.value), [
        3,
        12,
        7,
      ]);
    },
  );

  test('XLSX pie charts keep indexed fills, percentages and bottom legend', () {
    final book = _openChart(
      '',
      cat: '',
      chartXml:
          '''
<c:chartSpace xmlns:c="${OfficeNamespaces.c}" xmlns:a="${OfficeNamespaces.a}">
<c:chart><c:plotArea><c:pieChart><c:ser>
<c:dPt><c:idx val="1"/><c:spPr><a:solidFill><a:srgbClr val="112233"/></a:solidFill></c:spPr></c:dPt>
<c:dLbls><c:showPercent val="1"/></c:dLbls>
<c:cat><c:strLit><c:pt idx="0"><c:v>Retail</c:v></c:pt><c:pt idx="1"><c:v>Parts</c:v></c:pt></c:strLit></c:cat>
<c:val><c:numLit><c:pt idx="0"><c:v>25</c:v></c:pt><c:pt idx="1"><c:v>75</c:v></c:pt></c:numLit></c:val>
</c:ser><c:firstSliceAng val="90"/></c:pieChart></c:plotArea>
<c:legend><c:legendPos val="b"/></c:legend></c:chart></c:chartSpace>''',
    );
    final reopened = SheetDeserializer().readBytes(
      SheetSerializer().writeBytes(book),
    );
    final visual = reopened.firstSheet.drawings.single.visual;
    final layout = OfficePieLayout(visual, 300, 200);
    expect(layout.slices.map((slice) => slice.label), ['25%', '75%']);
    expect(layout.slices.first.start, 0);
    expect(layout.slices.first.point.color, isNot('112233'));
    expect(layout.slices.last.point.color, '112233');
    expect(layout.legend, hasLength(2));
    expect(layout.legend.first.y, greaterThan(layout.cy + layout.radius));

    final pdf = PdfFile.open(OfficePrint.workbook(reopened));
    final content = [
      for (var i = 0; i < pdf.pageCount; i++)
        String.fromCharCodes(
          pdf.store.streamBytes(pdf.pageDict(i)['Contents'])!,
        ),
    ].join();
    expect(content, contains('25%'));
    expect(content, contains('75%'));
  });

  test(
    'pie labels preserve zero and allocate whole percentages to total 100',
    () {
      final visual = OfficeVisual(
        kind: OfficeVisualKind.chartPie,
        chart: ChartDisplay(showPercent: true),
        points: [
          for (final (index, value) in [56.4673, 31.3724, 12.1603, 0.0].indexed)
            ChartPoint(label: 'Category ${index + 1}', value: value),
        ],
      );
      final layout = OfficePieLayout(visual, 400, 300);
      expect(layout.slices.map((slice) => slice.label), [
        '57%',
        '31%',
        '12%',
        '0%',
      ]);
      expect(layout.slices.last.sweep, 0);
      expect(layout.legend, hasLength(4));
    },
  );

  test('measured chart titles and narrow legends retain their contents', () {
    final chart = OfficeVisual(
      kind: OfficeVisualKind.chartPie,
      title: 'Wider region has a continuous title',
      chart: ChartDisplay(
        titleSize: 18,
        titleFamily: 'Calibri',
        legendSize: 10,
      ),
      points: [
        for (final name in [
          'Meetings',
          'Technology',
          'Payroll',
          'Vehicles',
          'Advertising and representation',
          'Other expenses',
        ])
          ChartPoint(label: name, value: 1),
      ],
    );
    double measure(String value, double size, bool bold, String? family) =>
        value.length * size * .44;
    final title = chart.chartTitleLines(308, 18, measure: measure);
    expect(title, [chart.title]);
    final compact = OfficePieLayout(chart, 218, 170, measure: measure);
    expect(
      compact.legend.map((entry) => entry.point.label),
      chart.points.map((point) => point.label),
    );
    expect(
      compact.legend.map((entry) => entry.y).toSet().length,
      greaterThan(1),
    );
  });

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

    test('print pictures use their VML slots and worksheet scale', () {
      const sheetPath = '/xl/worksheets/sheet1.xml';
      const drawingPath = '/xl/drawings/headerPictures.vml';
      final package = _package(
        '<row r="1"><c r="A1"><v>1</v></c></row>',
        drawing:
            '<pageMargins left="0.5" right="0.75" top="1" bottom="1" '
            'header="0.25" footer="0.5"/>'
            '<pageSetup paperSize="9" scale="50"/>'
            '<headerFooter><oddHeader>&amp;L&amp;&amp;G&amp;R&amp;G</oddHeader>'
            '<oddFooter>&amp;C&amp;G</oddFooter></headerFooter>'
            '<legacyDrawingHF r:id="rIdHeaderPictures"/>',
      );
      package
          .relationshipsFor(sheetPath)
          .add(
            type: '${OfficeNamespaces.r}/vmlDrawing',
            target: '../drawings/headerPictures.vml',
            id: 'rIdHeaderPictures',
          );
      package.createPart(
        drawingPath,
        'application/vnd.openxmlformats-officedocument.vmlDrawing',
        utf8.encode(
          '<xml xmlns:v="${OfficeNamespaces.v}" xmlns:o="${OfficeNamespaces.o}">'
          '<v:shape id="RH" style="width:100pt;height:40pt">'
          '<v:imagedata o:relid="rIdLogo"/></v:shape>'
          '<v:shape id="CF" style="width:2in;height:30pt">'
          '<v:imagedata o:relid="rIdLogo"/></v:shape>'
          '<v:shape id="LH" style="width:100pt;height:40pt">'
          '<v:imagedata o:relid="rIdLogo"/></v:shape></xml>',
        ),
      );
      package
          .relationshipsFor(drawingPath)
          .add(
            type: RelationshipTypes.image,
            target: '../media/logo.png',
            id: 'rIdLogo',
          );
      package.createPart(
        '/xl/media/logo.png',
        'image/png',
        PngBytes.studioCard(width: 8, height: 8),
      );

      final book = SheetDeserializer().read(package);
      final output = PdfFile.open(OfficePrint.workbook(book));
      final page = output.pageAt(0);
      final pictures = output.displayList(0).ops.whereType<PdfDrawImage>();
      expect(pictures, hasLength(2));
      final header = pictures.first;
      expect(header.placeholder, isFalse);
      expect(header.x, closeTo(page.width - 54 - 50, .01));
      expect(header.y, closeTo(18, .01));
      expect(header.width, closeTo(50, .01));
      expect(header.height, closeTo(20, .01));
      final footer = pictures.last;
      expect(footer.placeholder, isFalse);
      expect(footer.x, closeTo((36 + page.width - 54 - 72) / 2, .01));
      expect(footer.y, closeTo(page.height - 36 - 15, .01));
      expect(footer.width, closeTo(72, .01));

      final sheet = book.firstSheet
        ..printArea = SmlRange.parse('A1:B1')
        ..printTitleCols = SmlRange.parse('A1:A1')
        ..setColumnWidth(0, 400)
        ..setColumnWidth(1, 400);
      sheet.pageSetup!.fitToPage = true;
      sheet.pageSetup!.fitToWidth = 1;
      final fitted = PdfFile.open(OfficePrint.workbook(book));
      final fittedHeader = fitted
          .displayList(0)
          .ops
          .whereType<PdfDrawImage>()
          .first;
      // The title strip adds a third 300pt column to the fit calculation.
      // At 56%, it would leave less than two points inside the page margins.
      expect(fittedHeader.width, closeTo(55, .01));
      expect(fitted.pageCount, 1);
      sheet.pageSetup!.marginRightIn -= 1 / 72;
      final wider = PdfFile.open(OfficePrint.workbook(book));
      expect(
        wider.displayList(0).ops.whereType<PdfDrawImage>().first.width,
        closeTo(56, .01),
      );
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
    test(
      'moves only the relative axis of whole-row and whole-column ranges',
      () {
        expect(
          FormulaRefShift.shift(r"SUM('Data'!$A:B,2:$4)", rows: 1, columns: 2),
          r"SUM('Data'!$A:D,3:$4)",
        );
        expect(
          FormulaRefShift.shift('SUM(A:A,1:1)', rows: -1, columns: -1),
          'SUM(#REF!,#REF!)',
        );
        final references = FormulaRefScanner.scan('=SUM(E:E,3:3)');
        expect(references.map((span) => span.lexeme), ['E:E', '3:3']);
        expect(references.first.range.maxRow, SmlWorksheet.excelRowCount - 1);
        expect(references.last.range.maxCol, SmlWorksheet.excelColumnCount - 1);
      },
    );
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
