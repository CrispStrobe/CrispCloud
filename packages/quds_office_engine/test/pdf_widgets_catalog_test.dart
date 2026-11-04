import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/pdf_widgets.dart' as pw;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  final SfntFont? font = _tryFont();

  test('PageNumber reads Context page and count', () {
    final pw.Document doc = pw.Document(font: font, title: 'pages');
    doc.addPage(
      pw.MultiPage(
        pageFormat: pw.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        footer: (pw.Context context) =>
            const pw.PageNumber(template: 'P{page}/{count}'),
        build: (pw.Context context) => <pw.Widget>[
          for (int i = 0; i < 40; i++)
            pw.Paragraph(
              text: 'Line $i — flowing content to force multiple pages.',
            ),
        ],
      ),
    );
    final Uint8List bytes = doc.save();
    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes), contains('%PDF'));
  });

  test('HeaderFooter SignatureLine KeepTogether compose', () {
    final pw.Document doc = pw.Document(font: font);
    doc.addPage(
      pw.Page(
        pageFormat: pw.PdfPageFormat.a4,
        build: (pw.Context context) => const pw.Column(
          children: <pw.Widget>[
            pw.HeaderFooter(
              leading: pw.Text('QUDS', style: pw.TextStyle(fontSize: 9)),
              title: pw.Text('Chrome', style: pw.TextStyle(fontSize: 9)),
              divider: true,
            ),
            pw.SizedBox(height: 20),
            pw.KeepTogether(
              child: pw.SignatureLine(
                label: 'Authorized signature',
                showDateLine: true,
              ),
            ),
          ],
        ),
      ),
    );
    expect(doc.save().length, greaterThan(400));
  });

  test('Badge Callout Steps DataGrid layout', () {
    final pw.Document doc = pw.Document(font: font);
    doc.addPage(
      pw.Page(
        pageFormat: pw.PdfPageFormat.a4,
        build: (pw.Context context) => const pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Badge('Ready', tone: pw.BadgeTone.success),
            pw.SizedBox(height: 8),
            pw.Callout(
              title: 'Note',
              body: 'Callout body text for the catalog.',
              tone: pw.BadgeTone.info,
            ),
            pw.SizedBox(height: 12),
            pw.Steps(
              direction: pw.Axis.vertical,
              items: <pw.StepItem>[
                pw.StepItem(title: 'Draft', done: true),
                pw.StepItem(title: 'Review', active: true),
                pw.StepItem(title: 'Publish'),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.DataGrid(
              columns: <pw.DataColumn>[
                pw.DataColumn('Item', flex: 3),
                pw.DataColumn('Qty', numeric: true),
                pw.DataColumn('Total', numeric: true),
              ],
              rows: <pw.DataRow>[
                pw.DataRow(<String>['Paper', '2', '40']),
                pw.DataRow(<String>['Ink', '1', '25']),
              ],
            ),
          ],
        ),
      ),
    );
    expect(doc.save().length, greaterThan(500));
  });

  test('Code128 encodes INV-2026', () {
    final List<bool> modules = const pw.Code128Encoder().encode('INV-2026');
    expect(modules.length, greaterThan(40));
    expect(modules.where((bool b) => b).length, greaterThan(10));
  });

  test('Barcode and QrCode widgets save', () {
    final pw.Document doc = pw.Document(font: font);
    doc.addPage(
      pw.Page(
        pageFormat: pw.PdfPageFormat.a4,
        build: (pw.Context context) => const pw.Row(
          children: <pw.Widget>[
            pw.Barcode('ABC-12345', width: 160, height: 44),
            pw.SizedBox(width: 16),
            pw.QrCode('https://quds.office/demo', size: 72),
          ],
        ),
      ),
    );
    expect(doc.save().length, greaterThan(600));
  });

  test('QrEncoder produces matrix with finders', () {
    final List<List<bool>> matrix = const pw.QrEncoder().encode('hello');
    expect(matrix.length, greaterThanOrEqualTo(21));
    expect(matrix.length, matrix.first.length);
    expect(matrix[0][0], isTrue);
    expect(matrix[0][6], isTrue);
    expect(matrix[6][0], isTrue);
  });

  test('SvgImage path subset paints', () {
    final pw.Document doc = pw.Document(font: font);
    doc.addPage(
      pw.Page(
        pageFormat: pw.PdfPageFormat.a4,
        build: (pw.Context context) => const pw.SvgImage(
          '''
<svg viewBox="0 0 100 60">
  <rect x="4" y="4" width="40" height="24" fill="#1A237E"/>
  <circle cx="72" cy="28" r="16" stroke="#3949AB" fill="none"/>
  <path d="M10 50 L50 50 L30 30 Z" fill="#43A047"/>
</svg>
''',
          width: 160,
          height: 96,
        ),
      ),
    );
    expect(doc.save().length, greaterThan(400));
  });
}

SfntFont? _tryFont() {
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
