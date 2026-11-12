// Open a `.qrep` the way a server does after Quds Report Studio saved it:
// read the file, override its variables, feed live rows, export.
//
//   dart run example/fill_qrep.dart [out-dir]
//
// The first half writes `invoice.qrep` so the example has a file to open.
// Point [fromPackage] at any `.qrep` you designed in the studio instead.
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_reports/quds_reports.dart';

const String _layout = '''
<QudsReport name="Invoice" pageSize="A4" orientation="Portrait" defaultFontSize="10">
  <Variables>
    <Var name="company" type="text" value="Design studio"/>
    <Var name="vatRate" type="number" value="0" format="percent"/>
  </Variables>
  <DataSchema>
    <Field name="customer" type="text"/>
    <Field name="invoiceNo" type="text"/>
    <Table name="items">
      <Column name="name" type="text"/>
      <Column name="qty" type="number"/>
      <Column name="price" type="number"/>
      <Column name="line" type="number" expression="qty * price" format="n2"/>
    </Table>
  </DataSchema>
  <Bands>
    <ReportHeader height="22mm">
      <Text x="0mm" y="1mm" width="120mm" height="7mm" fontSize="16" bold="true">{{Variables.company}}</Text>
      <Text x="120mm" y="1mm" width="50mm" height="7mm" alignment="right">{{Data.invoiceNo}}</Text>
      <Text x="0mm" y="10mm" width="170mm" height="6mm">{{Data.customer}}</Text>
    </ReportHeader>
    <Detail dataSource="Data.items" height="8mm">
      <Text x="0mm" y="1mm" width="90mm" height="6mm">{{item.name}}</Text>
      <Text x="90mm" y="1mm" width="20mm" height="6mm" alignment="right">{{item.qty}}</Text>
      <Text x="110mm" y="1mm" width="30mm" height="6mm" alignment="right">{{item.price | n2}}</Text>
      <Text x="140mm" y="1mm" width="30mm" height="6mm" alignment="right">{{item.line | n2}}</Text>
    </Detail>
    <ReportSummary height="16mm">
      <Text x="90mm" y="2mm" width="50mm" height="6mm" alignment="right">VAT {{Variables.vatRate | percent}}</Text>
      <Text x="140mm" y="2mm" width="30mm" height="6mm" alignment="right">{{SUM(item.line) * Variables.vatRate | n2}}</Text>
      <Text x="90mm" y="9mm" width="50mm" height="6mm" alignment="right" bold="true">Total</Text>
      <Text x="140mm" y="9mm" width="30mm" height="6mm" alignment="right" bold="true">{{SUM(item.line) * (1 + Variables.vatRate) | currency:USD}}</Text>
    </ReportSummary>
  </Bands>
</QudsReport>
''';

Future<void> main(List<String> args) async {
  final Directory out = Directory(args.isNotEmpty ? args[0] : 'report_out')
    ..createSync(recursive: true);

  // A file Quds Report Studio would have saved, including the rows it
  // previewed with. Export does not use sample data unless you pass it.
  final File qrep = File('${out.path}/invoice.qrep')
    ..writeAsBytesSync(
      ReportPackage(
        xml: _layout,
        sampleData: <String, Object?>{
          'customer': 'Preview customer',
          'invoiceNo': 'PREVIEW',
          'items': <Map<String, Object?>>[
            <String, Object?>{'name': 'Sample', 'qty': 1, 'price': 1},
          ],
        },
      ).encode(),
    );

  final QudsReportEngine engine = QudsReportEngine.fromPackage(
    qrep.readAsBytesSync(),
    variables: <String, Object?>{
      'company': 'Northwind Traders',
      'vatRate': 0.15,
    },
  );
  engine.data
    ..set('customer', 'Contoso Ltd')
    ..set('invoiceNo', 'INV-2026-014')
    ..setTable('items', <Map<String, Object?>>[
      <String, Object?>{'name': 'Laptop 14"', 'qty': 2, 'price': 1250},
      <String, Object?>{'name': 'Monitor 27" 4K', 'qty': 3, 'price': 410},
      <String, Object?>{'name': 'Docking station', 'qty': 2, 'price': 189.5},
    ]);

  for (final ReportDiagnostic diagnostic in engine.validate()) {
    stdout.writeln(
      '${diagnostic.severity.name}: ${diagnostic.path}: ${diagnostic.message}',
    );
  }

  // An empty map keeps [engine.data]. Keys in the map win over it.
  final Uint8List pdf = await engine.exportToPdf(const <String, Object?>{});
  File('${out.path}/invoice.pdf').writeAsBytesSync(pdf);
  File('${out.path}/invoice.xlsx').writeAsBytesSync(
    engine.exportToExcelSync(const <String, Object?>{}),
  );
  File('${out.path}/invoice.docx').writeAsBytesSync(
    engine.exportToWordSync(const <String, Object?>{}),
  );
  stdout.writeln(
    'Read ${qrep.path} (preview customer: ${engine.sampleData?['customer']})',
  );
  stdout.writeln('Wrote ${out.path}/invoice.pdf (${pdf.length} bytes)');
}
