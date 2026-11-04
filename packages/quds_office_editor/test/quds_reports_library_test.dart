import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_reports.dart';
import 'package:quds_office_engine/quds_reports.dart' as engine_reports;
import 'package:quds_reports/quds_reports.dart' as quds_reports;

const String _xml = '''
<QudsReport name="Order" pageSize="A4" defaultFontSize="10">
  <Bands>
    <Detail dataSource="Data.items" height="8mm">
      <Text x="0mm" y="1mm" width="80mm" height="6mm">{{item.name}}</Text>
    </Detail>
  </Bands>
</QudsReport>
''';

void main() {
  test('the designer library is the report engine plus the designer', () async {
    final quds_reports.QudsReportEngine fromPackage =
        quds_reports.QudsReportEngine.fromXml(_xml);
    final engine_reports.QudsReportEngine fromEngine = fromPackage;
    final QudsReportEngine fromDesigner = fromEngine;
    final Uint8List pdf = await fromDesigner.exportToPdf(<String, Object?>{
      'items': <Map<String, Object?>>[
        <String, Object?>{'name': 'Pen', 'qty': 1, 'price': 2},
      ],
    });
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');

    final ReportDesignerController controller =
        ReportDesignerController.fromXml(_xml);
    final QudsReportDesigner designer = QudsReportDesigner(
      controller: controller,
      theme: OfficeTheme.light,
    );
    expect(designer.controller.template.name, 'Order');
    controller.dispose();
  });
}
