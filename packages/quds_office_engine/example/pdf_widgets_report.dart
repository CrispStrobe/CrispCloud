import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/pdf_widgets.dart' as pw;
import 'package:quds_office_engine/quds_office_engine.dart' show ChartPoint, PngBytes, SfntFont;

/// Multi-section quarterly report: cover, TOC, KPIs, charts, landscape appendix.
void main(List<String> args) {
  final Directory out = Directory(
    args.isEmpty ? 'example/out/pdf_widgets' : args.first,
  )..createSync(recursive: true);
  final Uint8List bytes = buildQuarterlyReport(font: _loadFont());
  File('${out.path}/quarterly_report.pdf').writeAsBytesSync(bytes);
  stdout.writeln(
    'Wrote ${out.path}/quarterly_report.pdf  (${bytes.length} bytes)',
  );
}

/// buildQuarterlyReport API.
Uint8List buildQuarterlyReport({SfntFont? font}) {
  final pw.Document doc = pw.Document(
    title: 'Quds Office — Q3 2026 performance',
    author: 'Office of the CTO',
    font: font,
    fontBold: _loadBoldFont(),
  );

  doc.addPage(
    pw.Page(
      pageFormat: pw.PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (pw.Context context) => pw.Stack(
        fit: pw.StackFit.expand,
        children: <pw.Widget>[
          pw.Container(color: '0D1B2A'),
          pw.Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 18,
            child: pw.Container(color: 'C9A227'),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(56, 72, 48, 56),
            child: pw.Column(
              children: <pw.Widget>[
                pw.Image(pw.MemoryImage(_mark()), width: 72, height: 72),
                const pw.SizedBox(height: 28),
                const pw.Text(
                  'QUARTERLY REVIEW',
                  style: pw.TextStyle(
                    color: 'C9A227',
                    fontSize: 11,
                    letterSpacing: 2.4,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                const pw.SizedBox(height: 12),
                const pw.Text(
                  'Performance\nof the suite',
                  style: pw.TextStyle(
                    color: 'FFFFFF',
                    fontSize: 32,
                    fontWeight: pw.FontWeight.bold,
                    lineSpacing: 1.15,
                  ),
                ),
                const pw.SizedBox(height: 16),
                const pw.Divider(color: 'C9A227', thickness: 1.2),
                const pw.SizedBox(height: 16),
                const pw.Text(
                  'Third quarter  2026  ·  Word, Excel, PowerPoint, PDF',
                  style: pw.TextStyle(color: 'B0BEC5', fontSize: 11),
                ),
                const pw.Spacer(),
                const pw.Text(
                  'Prepared by the Office of the CTO  ·  Confidential',
                  style: pw.TextStyle(color: '78909C', fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: pw.PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 50, 48, 48),
      header: (pw.Context context) => const pw.Text(
        'Quds Office  ·  Q3 2026',
        style: pw.TextStyle(fontSize: 8, color: '90A4AE'),
      ),
      footer: (pw.Context context) => pw.Footer(
        leading: const pw.Text(
          'Confidential',
          style: pw.TextStyle(fontSize: 8, color: '90A4AE'),
        ),
      ),
      build: (pw.Context context) => <pw.Widget>[
        pw.Watermark.text('INTERNAL'),
        const pw.TableOfContent(title: 'Contents', maxLevel: 2),
        pw.Header(level: 1, text: 'Executive summary'),
        pw.Paragraph(
          text:
              'The suite closed the quarter with a complete PDF-as-a-file stack, '
              'a constraint-layout PDF writer, and stable OOXML round-trip. '
              'This report is itself a widget tree: MultiPage flow, a two-pass '
              'table of contents, flex KPI tiles, and vector charts — all in '
              'pure Dart, painted onto PdfCanvas.',
        ),
        pw.Row(
          children: <pw.Widget>[
            _kpi('Documents', '172', '+16%'),
            _kpi('Slides', '55', '+34%'),
            _kpi('Workbooks', '110', '+15%'),
            _kpi('PDF files', '64', 'new'),
          ],
        ),
        const pw.SizedBox(height: 8),
        pw.Header(level: 1, text: 'Delivery'),
        pw.Header(level: 2, text: 'What landed'),
        const pw.Bullet(text: 'PdfFile open, display list, annotate, incremental save.'),
        const pw.Bullet(text: 'QudsPdfViewer and QudsPdfEditor on custom RenderBoxes.'),
        const pw.Bullet(
          text: 'pdf_widgets.dart — Flutter-shaped layout without dart:ui.',
        ),
        pw.Header(level: 2, text: 'Volume'),
        pw.Chart(
          type: pw.ChartType.bar,
          title: 'Published packages per quarter',
          width: 480,
          height: 168,
          points: const <ChartPoint>[
            ChartPoint(label: 'Q1', value: 120, color: '1A237E'),
            ChartPoint(label: 'Q2', value: 148, color: '283593'),
            ChartPoint(label: 'Q3', value: 172, color: '00897B'),
          ],
        ),
        pw.Header(level: 1, text: 'Mix by format'),
        pw.Row(
          children: <pw.Widget>[
            pw.Expanded(
              child: pw.Chart(
                type: pw.ChartType.pie,
                title: 'Share of generated files',
                height: 170,
                points: const <ChartPoint>[
                  ChartPoint(label: 'DOCX', value: 42, color: '1A237E'),
                  ChartPoint(label: 'XLSX', value: 28, color: '00897B'),
                  ChartPoint(label: 'PPTX', value: 18, color: 'F9A825'),
                  ChartPoint(label: 'PDF', value: 12, color: 'C62828'),
                ],
              ),
            ),
            const pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Chart(
                type: pw.ChartType.line,
                title: 'Support tickets closed',
                height: 170,
                points: const <ChartPoint>[
                  ChartPoint(label: 'Jul', value: 21, color: '00897B'),
                  ChartPoint(label: 'Aug', value: 18, color: '00897B'),
                  ChartPoint(label: 'Sep', value: 27, color: '1A237E'),
                ],
              ),
            ),
          ],
        ),
        pw.Header(level: 1, text: 'Regional scorecard'),
        pw.Table.fromTextArray(
          headers: const <String>['Region', 'Docs', 'Sheets', 'Decks', 'NPS'],
          data: const <List<String>>[
            ['Levant', '48', '22', '11', '71'],
            ['Gulf', '61', '30', '19', '74'],
            ['Europe', '39', '28', '14', '68'],
            ['Americas', '24', '30', '11', '70'],
          ],
        ),
        pw.Paragraph(
          text:
              'NPS is a trailing ninety-day figure. Europe includes the '
              'Edinburgh design-partner cohort billed on INV-2026-0914.',
        ),
      ],
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: pw.PdfPageFormat.a4,
      orientation: pw.PageOrientation.landscape,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
      header: (pw.Context context) => const pw.Text(
        'Appendix A  ·  landscape grid',
        style: pw.TextStyle(fontSize: 8, color: '90A4AE'),
      ),
      footer: (pw.Context context) => pw.Footer(),
      build: (pw.Context context) => <pw.Widget>[
        pw.Header(level: 1, text: 'Capability matrix'),
        pw.Table.fromTextArray(
          headers: const <String>[
            'Surface',
            'Open',
            'Edit',
            'Export PDF',
            'RTL',
            'Widgets',
          ],
          data: const <List<String>>[
            ['Word', 'Yes', 'WmlDocument', 'Layout replay', 'Yes', 'Builder'],
            ['Excel', 'Yes', 'SmlWorkbook', 'Print geometry', 'Yes', 'Builder'],
            ['PowerPoint', 'Yes', 'PmlPresentation', 'Slide pages', 'Yes', 'Builder'],
            ['PDF file', 'PdfFile', 'Annotate', 'Incremental', 'Paint', 'Viewer'],
            ['PDF write', '—', 'PdfCanvas', 'Native 1.7', 'Yes', 'pdf_widgets'],
          ],
        ),
        const pw.SizedBox(height: 12),
        pw.Paragraph(
          text:
              'Word no longer pretends to be a constraint layout. Flow belongs '
              'to WML; exact boxes belong to PDF.',
        ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _kpi(String label, String value, String delta) {
  return pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.all(4),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: 'F5F7FA',
        borderRadius: 4,
        border: pw.Border.all(color: 'E0E6ED', width: 0.6),
      ),
      child: pw.Column(
        children: <pw.Widget>[
          pw.Text(
            value,
            style: const pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: '1A237E',
            ),
          ),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: '607D8B')),
          pw.Text(
            delta,
            style: const pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: '00897B',
            ),
          ),
        ],
      ),
    ),
  );
}

Uint8List _mark() {
  return PngBytes.rgb(
    width: 96,
    height: 96,
    plot: (int x, int y, List<int> rgb) {
      rgb[0] = 0x0D;
      rgb[1] = 0x1B;
      rgb[2] = 0x2A;
      final int cx = x - 48;
      final int cy = y - 48;
      if (cx * cx + cy * cy < 1600) {
        rgb[0] = 0xC9;
        rgb[1] = 0xA2;
        rgb[2] = 0x27;
      }
      if (cx * cx + cy * cy < 700) {
        rgb[0] = 0x0D;
        rgb[1] = 0x1B;
        rgb[2] = 0x2A;
      }
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
