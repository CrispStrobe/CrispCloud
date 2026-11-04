import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// 1×1 transparent PNG.
final Uint8List _png = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

void main() {
  test('XlsxWorkbookBuilder writes RTL, freeze, merge, styles and reopens', () {
    final XlsxWorkbookBuilder book = XlsxWorkbookBuilder();
    final int header = book.style(
      bold: true,
      fillRgb: '1F4E79',
      color: 'FFFFFF',
      border: true,
    );
    final XlsxSheetBuilder sheet = book.addSheet('تقرير');
    sheet
      ..rightToLeft = true
      ..freezeRows = 1
      ..autoFilterRef = 'A1:C2'
      ..addRow(<Object?>['الاسم', 'العدد', 'نشط'], style: header)
      ..addRow(<Object?>['أ', 12, true])
      ..merge(0, 0, 0, 0)
      ..colWidth(0, 18)
      ..fitColumnWidths(fromRow: 0, toRow: 1, colCount: 3);
    final Uint8List bytes = book.build();
    expect(OpcPackage.openBytes(bytes).kind, OpcPackageKind.sheet);

    final List<XlsxNamedSheet> sheets = XlsxGridReader.readAll(bytes);
    expect(sheets, hasLength(1));
    expect(sheets.first.name, 'تقرير');
    expect(sheets.first.rows.first, <String>['الاسم', 'العدد', 'نشط']);
    expect(sheets.first.rows[1][1], '12');
    expect(sheets.first.rows[1][2], 'TRUE');

    final List<Map<String, String>> maps = XlsxGridReader.readHeaderMaps(bytes);
    expect(maps, hasLength(1));
    expect(maps.first['الاسم'], 'أ');
    expect(maps.first['العدد'], '12');

    final String xml = OpcPackage.openBytes(
      bytes,
    ).getPart('/xl/worksheets/sheet1.xml')!.readText();
    expect(xml, contains('rightToLeft="1"'));
    expect(xml, contains('state="frozen"'));
    expect(xml, contains('autoFilter'));
  });

  test(
    'DocxDocumentBuilder writes RTL table, list, image, chart and comments',
    () {
      final DocxDocumentBuilder doc = DocxDocumentBuilder(rtl: true)
        ..heading('تقرير')
        ..paragraph('مقدمة', comments: <String>['مصدر 1'])
        ..bulletList(<String>['بند أ', 'بند ب'])
        ..numberedList(<String>['واحد'])
        ..table(<List<String>>[
          <String>['حقل', 'قيمة'],
          <String>['عدد', '3'],
        ])
        ..horizontalRule()
        ..image(_png, widthPx: 16, heightPx: 16)
        ..pieChart(
          title: 'توزيع',
          series: const <ChartPoint>[
            ChartPoint(label: 'أ', value: 2, color: '2E75B6'),
            ChartPoint(label: 'ب', value: 1, color: '548235'),
          ],
        )
        ..pageBreak()
        ..paragraph('نهاية');
      final Uint8List bytes = doc.build();
      expect(OpcPackage.openBytes(bytes).kind, OpcPackageKind.word);
      expect(
        OpcPackage.openBytes(
          bytes,
        ).partNames.any((String n) => n.contains('media')),
        isTrue,
      );
      expect(
        OpcPackage.openBytes(
          bytes,
        ).partNames.any((String n) => n.contains('charts')),
        isTrue,
      );
      expect(
        OpcPackage.openBytes(bytes).getPart('/word/comments.xml'),
        isNotNull,
      );

      final extracted = DocxPlainReader.read(bytes);
      expect(extracted.paragraphs.join(' '), contains('تقرير'));
      expect(extracted.tables, isNotEmpty);
      expect(extracted.tables.first.first, contains('حقل'));
    },
  );

  test('PptxDeckBuilder writes title, table, image and chart slides', () {
    final PptxDeckBuilder deck = PptxDeckBuilder(rtl: true)
      ..addTitleSlide(title: 'عرض', subtitle: 'ملخص')
      ..addTitleBodySlide(title: 'نقاط', bullets: <String>['أ', 'ب'])
      ..addTwoColumnSlide(
        title: 'عمودان',
        left: <String>['1'],
        right: <String>['2'],
      )
      ..addTableSlide(
        title: 'جدول',
        rows: <List<String>>[
          <String>['س', 'ص'],
          <String>['1', '2'],
        ],
      )
      ..addImageSlide(title: 'صورة', pngBytes: _png, caption: 'تعليق')
      ..addBarChartSlide(
        title: 'أعمدة',
        series: const <ChartPoint>[
          ChartPoint(label: 'س', value: 4),
          ChartPoint(label: 'ص', value: 2),
        ],
      );
    final Uint8List bytes = deck.build();
    final OpcPackage pkg = OpcPackage.openBytes(bytes);
    expect(pkg.kind, OpcPackageKind.slide);
    expect(pkg.getPart('/ppt/slides/slide1.xml'), isNotNull);
    expect(pkg.getPart('/ppt/slides/slide6.xml'), isNotNull);
    expect(pkg.partNames.any((String n) => n.contains('media')), isTrue);
    expect(pkg.partNames.any((String n) => n.contains('charts')), isTrue);
    expect(pkg.getPart('/ppt/slides/slide1.xml')!.readText(), contains('عرض'));
  });
}
