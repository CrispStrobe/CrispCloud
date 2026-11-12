// Band report: a template string and a data map → PDF, XLSX, and DOCX.
//
//   dart run example/report_quickstart.dart [out-dir]
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_reports/quds_reports.dart';

const String _template = '''
<QudsReport name="Order summary" pageSize="A4" orientation="Portrait" defaultFontSize="10">
  <Variables>
    <Var name="vatRate" type="number" value="0.15" format="percent"/>
  </Variables>
  <Bands>
    <ReportHeader height="18mm">
      <Text x="0mm" y="2mm" width="170mm" height="8mm" fontSize="16" bold="true">Order summary</Text>
      <Text x="0mm" y="11mm" width="170mm" height="5mm">{{Data.customer}}</Text>
    </ReportHeader>
    <Detail dataSource="Data.items" height="8mm">
      <Text x="0mm" y="1mm" width="110mm" height="6mm">{{item.name}}</Text>
      <Text x="110mm" y="1mm" width="20mm" height="6mm" alignment="right">{{item.qty}}</Text>
      <Text x="130mm" y="1mm" width="40mm" height="6mm" alignment="right">{{item.qty * item.price | n2}}</Text>
    </Detail>
    <ReportSummary height="16mm">
      <Text x="90mm" y="2mm" width="40mm" height="6mm" alignment="right">VAT {{Variables.vatRate | percent}}</Text>
      <Text x="130mm" y="2mm" width="40mm" height="6mm" alignment="right">{{SUM(item.qty * item.price) * Variables.vatRate | n2}}</Text>
      <Text x="90mm" y="9mm" width="40mm" height="6mm" alignment="right" bold="true">Total</Text>
      <Text x="130mm" y="9mm" width="40mm" height="6mm" alignment="right" bold="true">{{SUM(item.qty * item.price) * (1 + Variables.vatRate) | currency:USD}}</Text>
    </ReportSummary>
  </Bands>
</QudsReport>
''';

Future<void> main(List<String> args) async {
  final Directory out = Directory(args.isNotEmpty ? args[0] : 'report_out')
    ..createSync(recursive: true);
  final QudsReportEngine engine = QudsReportEngine.fromXml(_template);
  final Map<String, Object?> data = <String, Object?>{
    'customer': 'Northwind Traders',
    'items': <Map<String, Object?>>[
      <String, Object?>{'name': 'Laptop 14"', 'qty': 2, 'price': 1250.0},
      <String, Object?>{'name': 'Monitor 27" 4K', 'qty': 3, 'price': 410.0},
      <String, Object?>{'name': 'Docking station', 'qty': 2, 'price': 189.5},
    ],
  };
  for (final ReportDiagnostic diagnostic in engine.validate()) {
    stdout.writeln(
      '${diagnostic.severity.name}: ${diagnostic.path}: ${diagnostic.message}',
    );
  }
  final Uint8List pdf = await engine.exportToPdf(
    data,
    options: const PdfSaveOptions(),
  );
  File('${out.path}/order.pdf').writeAsBytesSync(pdf);
  File('${out.path}/order.xlsx').writeAsBytesSync(engine.exportToExcelSync(data));
  File('${out.path}/order.docx').writeAsBytesSync(engine.exportToWordSync(data));
  File('${out.path}/order.qrep').writeAsBytesSync(engine.toPackage());
  stdout.writeln('Wrote ${out.path}/order.pdf (${pdf.length} bytes)');
}
