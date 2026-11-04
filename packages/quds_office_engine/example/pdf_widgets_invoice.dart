import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/pdf_widgets.dart' as pw;
import 'package:quds_office_engine/quds_office_engine.dart' show PngBytes, SfntFont;

/// Professional invoice generated with constraint-layout PDF widgets.
void main(List<String> args) {
  final Directory out = Directory(
    args.isEmpty ? 'example/out/pdf_widgets' : args.first,
  )..createSync(recursive: true);
  final Uint8List bytes = buildInvoice(font: _loadFont());
  File('${out.path}/invoice.pdf').writeAsBytesSync(bytes);
  stdout.writeln('Wrote ${out.path}/invoice.pdf  (${bytes.length} bytes)');
}

/// buildInvoice API.
Uint8List buildInvoice({SfntFont? font}) {
  final pw.Document doc = pw.Document(
    title: 'Invoice INV-2026-0914',
    author: 'Quds Office',
    font: font,
    fontBold: _loadBoldFont(),
    theme: const pw.ThemeData(
      defaultTextStyle: pw.TextStyle(fontSize: 10, color: '263238'),
    ),
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: pw.PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 44, 48, 44),
      header: (pw.Context context) => pw.Row(
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Column(
              children: <pw.Widget>[
                pw.Text(
                  'QUDS OFFICE',
                  style: const pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: '1A237E',
                    letterSpacing: 1.2,
                  ),
                ),
                pw.Text(
                  'Document systems  ·  invoice@quds.office',
                  style: const pw.TextStyle(fontSize: 8, color: '607D8B'),
                ),
              ],
            ),
          ),
          pw.Text(
            'INVOICE',
            style: const pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: '1A237E',
            ),
          ),
        ],
      ),
      footer: (pw.Context context) => pw.Footer(
        leading: const pw.Text(
          'Payable within 14 days',
          style: pw.TextStyle(fontSize: 8, color: '78909C'),
        ),
        trailing: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: '78909C'),
        ),
      ),
      build: (pw.Context context) => <pw.Widget>[
        pw.Image(pw.MemoryImage(_banner()), width: 500, height: 36),
        const pw.SizedBox(height: 16),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Expanded(
              child: pw.Column(
                children: <pw.Widget>[
                  const pw.Text(
                    'BILL TO',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: '78909C',
                      letterSpacing: 0.8,
                    ),
                  ),
                  const pw.SizedBox(height: 4),
                  const pw.Text(
                    'Northwind Analytics Ltd.',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  const pw.Text('14 Harbour Walk, Suite 8'),
                  const pw.Text('Edinburgh  ·  EH6 6DN'),
                  pw.UrlLink(
                    destination: 'mailto:accounts@northwind.example',
                    child: const pw.Text(
                      'accounts@northwind.example',
                      style: pw.TextStyle(
                        color: '1565C0',
                        decoration: pw.TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.Container(
              width: 200,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: 'F3F6FB',
                borderRadius: 4,
                border: pw.Border.all(color: 'C5CAE9', width: 0.6),
              ),
              child: pw.Column(
                children: <pw.Widget>[
                  _meta('Invoice', 'INV-2026-0914'),
                  _meta('Issued', '9 September 2026'),
                  _meta('Due', '23 September 2026'),
                  _meta('Terms', 'Net 14'),
                ],
              ),
            ),
          ],
        ),
        const pw.SizedBox(height: 18),
        pw.Table.fromTextArray(
          headers: const <String>['Description', 'Qty', 'Rate', 'Amount'],
          columnWidths: const <double>[3.4, 0.7, 0.9, 1.0],
          headerDecoration: '1A237E',
          oddRowDecoration: 'F5F7FA',
          cellPadding: const pw.EdgeInsets.fromLTRB(6, 7, 6, 7),
          data: const <List<String>>[
            ['Platform license — Quds Office Engine (annual)', '1', '2,400.00', '2,400.00'],
            ['Editor seats (RenderBox surfaces)', '8', '180.00', '1,440.00'],
            ['PDF file stack — annotate + incremental save', '1', '950.00', '950.00'],
            ['Priority support, September–November', '1', '420.00', '420.00'],
          ],
        ),
        const pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 220,
            child: pw.Column(
              children: <pw.Widget>[
                _totalLine('Subtotal', '5,210.00'),
                _totalLine('VAT 20%', '1,042.00'),
                const pw.Divider(height: 10, color: '1A237E'),
                _totalLine('Amount due', '6,252.00', emphasize: true),
              ],
            ),
          ),
        ),
        const pw.SizedBox(height: 22),
        pw.Header(level: 2, text: 'Payment'),
        const pw.Bullet(text: 'Bank transfer to GB29 NWBK 6016 1331 9268 19 (Quds Office Ltd).'),
        const pw.Bullet(text: 'Reference INV-2026-0914 on the payment.'),
        const pw.Bullet(text: 'Late invoices accrue 1.5% per month after the due date.'),
        const pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: const pw.BoxDecoration(
            color: 'FFF8E1',
            border: pw.Border(
              left: pw.BorderSide(color: 'F9A825', width: 3),
            ),
          ),
          child: const pw.Text(
            'Thank you for building with a Dart-native Office stack. '
            'This PDF was composed with pdf_widgets.dart — Row, Table, '
            'UrlLink, and MultiPage headers — without Flutter.',
            style: pw.TextStyle(fontSize: 9, color: '5D4037'),
          ),
        ),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _meta(String k, String v) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      children: <pw.Widget>[
        pw.SizedBox(
          width: 62,
          child: pw.Text(
            k.toUpperCase(),
            style: const pw.TextStyle(fontSize: 8, color: '78909C'),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            v,
            style: const pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _totalLine(String k, String v, {bool emphasize = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: <pw.Widget>[
        pw.Expanded(
          child: pw.Text(
            k,
            style: pw.TextStyle(
              fontSize: emphasize ? 11 : 9,
              fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: emphasize ? '1A237E' : '546E7A',
            ),
          ),
        ),
        pw.Text(
          v,
          style: pw.TextStyle(
            fontSize: emphasize ? 12 : 10,
            fontWeight: pw.FontWeight.bold,
            color: emphasize ? '1A237E' : '263238',
          ),
        ),
      ],
    ),
  );
}

Uint8List _banner() {
  return PngBytes.rgb(
    width: 640,
    height: 48,
    plot: (int x, int y, List<int> rgb) {
      final double t = x / 639;
      rgb[0] = (0x1A + ((0x00 - 0x1A) * t)).round();
      rgb[1] = (0x23 + ((0x89 - 0x23) * t)).round();
      rgb[2] = (0x7E + ((0x7B - 0x7E) * t)).round();
    },
  );
}

SfntFont? _loadBoldFont() {
  const List<String> paths = <String>[
    '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  ];
  for (final String path in paths) {
    final File file = File(path);
    if (file.existsSync()) {
      return SfntFont.parse(file.readAsBytesSync());
    }
  }
  return null;
}

SfntFont? _loadFont() {
  const List<String> paths = <String>[
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
  ];
  for (final String path in paths) {
    final File file = File(path);
    if (file.existsSync()) {
      return SfntFont.parse(file.readAsBytesSync());
    }
  }
  return null;
}
