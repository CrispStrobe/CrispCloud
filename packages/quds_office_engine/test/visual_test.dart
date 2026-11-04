import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('PngBytes writes a valid PNG signature', () {
    final bytes = PngBytes.studioCard(width: 32, height: 20);
    expect(bytes.length, greaterThan(40));
    expect(bytes[0], 137);
    expect(bytes[1], 80);
    expect(bytes[2], 78);
    expect(bytes[3], 71);
  });

  test('Word layout reserves frames for picture and chart', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Above')]),
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                imageBytes: PngBytes.studioCard(),
                width: 200,
                height: 100,
              ),
            ),
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.chartColumn,
                title: 'Mix',
                points: OfficeVisual.sampleSeries(),
                width: 220,
                height: 120,
              ),
            ),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    expect(laid.pages, isNotEmpty);
    final List<LaidOutBox> visuals = laid.pages
        .expand((LaidOutPage p) => p.frames)
        .where((LaidOutBox b) => b.kind != LaidOutBoxKind.tableCell)
        .toList();
    expect(visuals.length, 2);
    expect(visuals.first.kind, LaidOutBoxKind.picture);
    expect(visuals.last.kind, LaidOutBoxKind.chart);
    expect(visuals.last.height, greaterThan(80));
  });

  test('chart and picture edits stay typed and copyable', () {
    final OfficeVisual chart = OfficeVisual(
      kind: OfficeVisualKind.chartColumn,
      title: 'Sales',
      points: OfficeVisual.sampleSeries(),
    );
    chart
      ..addSamplePoint(arabic: false)
      ..bumpPointValue(0, 10)
      ..chart.showDataLabels = true;
    expect(chart.points, hasLength(5));
    expect(chart.points.first.value, 52);
    final OfficeVisual snap = chart.copy();
    chart.removeLastPoint();
    expect(chart.points, hasLength(4));
    chart.restoreFrom(snap);
    expect(chart.points, hasLength(5));

    final OfficeVisual picture = OfficeVisual(
      kind: OfficeVisualKind.picture,
      imageBytes: PngBytes.studioCard(),
    );
    picture
      ..cropBy(0.1)
      ..rotateBy(90)
      ..bumpBrightness(0.2)
      ..cycleBorder();
    expect(picture.picture.cropLeft, closeTo(0.1, 0.001));
    expect(picture.picture.rotationDeg, 90);
    expect(picture.picture.borderWidth, greaterThan(0));
    final OfficeVisual clone = picture.copy();
    picture.resetPicture();
    expect(picture.picture.rotationDeg, 0);
    expect(clone.picture.rotationDeg, 90);
  });

  test('sheet chart data reads formulas and keeps a zero bar', () {
    final SmlWorkbook book = SmlWorkbook(
      sheets: <SmlWorksheet>[SmlWorksheet(name: 'S', sheetId: 1)],
    );
    final SmlWorksheet sheet = book.sheets.first;
    sheet.cell(const SmlCellRef(0, 0)).type = SmlCellType.string;
    sheet.cell(const SmlCellRef(0, 0)).value = 'Q1';
    sheet.cell(const SmlCellRef(1, 0)).type = SmlCellType.string;
    sheet.cell(const SmlCellRef(1, 0)).value = 'Q2';
    sheet.cell(const SmlCellRef(0, 1)).value = 4;
    sheet.cell(const SmlCellRef(1, 1)).type = SmlCellType.formula;
    sheet.cell(const SmlCellRef(1, 1)).formula = '=A2-A2';
    final List<ChartPoint> points = SheetChartData.fromRange(
      book: book,
      sheet: sheet,
      from: const SmlCellRef(0, 1),
      to: const SmlCellRef(1, 1),
    );
    expect(points.length, 2);
    expect(points[0].label, 'Q1');
    expect(points[0].value, 4);
    expect(points[1].label, 'Q2');
    expect(points[1].value, 0);
  });
}
