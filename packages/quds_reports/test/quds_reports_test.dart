import 'dart:typed_data';

import 'package:quds_reports/quds_reports.dart';
import 'package:test/test.dart';

const String _template = '''
<QudsReport name="Order" pageSize="A4" defaultFontSize="10">
  <Bands>
    <Detail dataSource="Data.items" height="8mm">
      <Text name="line" x="0mm" y="1mm" width="120mm" height="6mm">{{item.name}}</Text>
      <Text x="120mm" y="1mm" width="50mm" height="6mm" alignment="right">{{item.qty * item.price | n2}}</Text>
    </Detail>
    <ReportSummary height="10mm">
      <Text x="120mm" y="2mm" width="50mm" height="6mm" alignment="right">{{SUM(item.qty * item.price) | n2}}</Text>
    </ReportSummary>
  </Bands>
</QudsReport>
''';

void main() {
  const Map<String, Object?> data = <String, Object?>{
    'items': <Map<String, Object?>>[
      <String, Object?>{'name': 'Pen', 'qty': 4, 'price': 1.5},
      <String, Object?>{'name': 'Notebook', 'qty': 2, 'price': 3.25},
    ],
  };

  test('fromXml exports PDF, Excel, and Word', () {
    final QudsReportEngine engine = QudsReportEngine.fromXml(_template);
    expect(engine.validate(), isEmpty);
    final Uint8List pdf = engine.exportToPdfSync(
      data,
      options: const PdfSaveOptions(tagged: true),
    );
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
    expect(engine.exportToExcelSync(data), isNotEmpty);
    expect(engine.exportToWordSync(data), isNotEmpty);
    expect(engine.elementAs<ReportTextElement>('line').name, 'line');
  });

  test('package round-trip keeps the layout', () {
    final QudsReportEngine engine = QudsReportEngine.fromXml(_template);
    final Uint8List bytes = engine.toPackage();
    final QudsReportEngine opened = QudsReportEngine.fromPackage(bytes);
    expect(opened.template.name, 'Order');
    expect(opened.toXml(), contains('{{SUM(item.qty * item.price) | n2}}'));
    expect(
      String.fromCharCodes(opened.exportToPdfSync(data).sublist(0, 5)),
      '%PDF-',
    );
  });

  test('layout lines and font faces are part of this library', () {
    final QudsReportEngine engine = QudsReportEngine.fromXml(_template);
    final ReportDocumentLayout laid = engine.layout(data);
    final ReportTextPrimitive text = laid.pages.first.primitives
        .whereType<ReportTextPrimitive>()
        .first;
    final BrokenLine line = text.shaped.lines.first.broken;
    final ShapedGlyph glyph = line.glyphs.first;
    expect(glyph.codePoint, greaterThan(0));
    expect(ReportFontRegistry().allFaces.whereType<SfntFont>(), isEmpty);
  });
}
