import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/pdf_widgets.dart' as pw;
import 'package:quds_office_engine/quds_office_engine.dart' show SfntFont;

/// Client proposal: cover band, service grid, timeline, terms.
void main(List<String> args) {
  final Directory out = Directory(
    args.isEmpty ? 'example/out/pdf_widgets' : args.first,
  )..createSync(recursive: true);
  final Uint8List bytes = buildProposal(font: _loadFont());
  File('${out.path}/proposal.pdf').writeAsBytesSync(bytes);
  stdout.writeln('Wrote ${out.path}/proposal.pdf  (${bytes.length} bytes)');
}

/// buildProposal API.
Uint8List buildProposal({SfntFont? font}) {
  final pw.Document doc = pw.Document(
    title: 'Quds Office — platform proposal',
    author: 'Quds Office',
    font: font,
    fontBold: _loadBoldFont(),
  );

  doc.addPage(
    pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: pw.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(48, 0, 48, 48),
        buildBackground: (pw.Context context) => pw.Column(
          children: <pw.Widget>[
            pw.Container(height: 168, color: '1A237E'),
            pw.Expanded(child: pw.SizedBox.expand()),
          ],
        ),
      ),
      build: (pw.Context context) => pw.Column(
        children: <pw.Widget>[
          const pw.SizedBox(height: 36),
          const pw.Text(
            'PROPOSAL',
            style: pw.TextStyle(
              color: '9FA8DA',
              fontSize: 10,
              letterSpacing: 3,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          const pw.SizedBox(height: 8),
          const pw.Text(
            'A Dart-native Office suite\nfor your product',
            style: pw.TextStyle(
              color: 'FFFFFF',
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              lineSpacing: 1.15,
            ),
          ),
          const pw.SizedBox(height: 36),
          const pw.SizedBox(height: 28),
          pw.Header(level: 1, text: 'Scope'),
          pw.Paragraph(
            text:
                'We propose embedding quds_office_engine on the server and '
                'quds_office_editor in the Flutter client. Generation, '
                'round-trip, and PDF viewing stay on one model — no Word '
                'automation, no Chromium print path.',
          ),
          pw.GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 2.1,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: const <pw.Widget>[
              _Card(
                title: 'Word',
                body: 'DocxDocumentBuilder + WmlDocument. Real sections, fields, TOC.',
              ),
              _Card(
                title: 'Excel',
                body: 'Formulas, styles, print titles. PDF from sheet geometry.',
              ),
              _Card(
                title: 'PowerPoint',
                body: 'Slides, Morph, reverse playback. Notes pages in PDF.',
              ),
              _Card(
                title: 'PDF',
                body: 'PdfFile to open. pdf_widgets.dart to compose. Annotate in-place.',
              ),
            ],
          ),
          pw.Header(level: 1, text: 'Timeline'),
          pw.Table.fromTextArray(
            headers: const <String>['Phase', 'Weeks', 'Outcome'],
            headerDecoration: '1A237E',
            data: const <List<String>>[
              ['1  Foundations', '2', 'OPC open/save, branded builders'],
              ['2  Editors', '3', 'Word / sheet / slide RenderBoxes'],
              ['3  PDF', '2', 'Viewer, markup, widget generation'],
              ['4  Hardening', '2', 'Isolates, passwords, fixtures'],
            ],
          ),
          pw.Header(level: 1, text: 'Commercials'),
          pw.Row(
            children: <pw.Widget>[
              pw.Expanded(child: _term('Investment', 'Fixed 9-week engagement')),
              pw.Expanded(child: _term('License', 'MIT — packages on pub.dev')),
              pw.Expanded(child: _term('Support', 'Slack + monthly review')),
            ],
          ),
          const pw.SizedBox(height: 14),
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.UrlLink(
              destination: 'https://pub.dev/packages/quds_office_engine',
              child: const pw.Text(
                'pub.dev/packages/quds_office_engine  →',
                style: pw.TextStyle(
                  color: '1565C0',
                  decoration: pw.TextDecoration.underline,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}

class _Card extends pw.Widget {
  const _Card({required this.title, required this.body});

  final String title;
  final String body;

  @override
  pw.PwBox layout(pw.Context context, pw.BoxConstraints constraints) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: 'F5F7FA',
        borderRadius: 4,
        border: pw.Border.all(color: 'E8EEF4', width: 0.6),
      ),
      child: pw.Column(
        children: <pw.Widget>[
          pw.Text(
            title,
            style: const pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: '1A237E',
              fontSize: 12,
            ),
          ),
          const pw.SizedBox(height: 4),
          pw.Text(body, style: const pw.TextStyle(fontSize: 9, color: '455A64')),
        ],
      ),
    ).layout(context, constraints);
  }
}

pw.Widget _term(String k, String v) {
  return pw.Container(
    margin: const pw.EdgeInsets.all(3),
    padding: const pw.EdgeInsets.all(8),
    decoration: const pw.BoxDecoration(color: 'E8EAF6', borderRadius: 4),
    child: pw.Column(
      children: <pw.Widget>[
        pw.Text(
          k.toUpperCase(),
          style: const pw.TextStyle(fontSize: 7, color: '5C6BC0'),
        ),
        pw.Text(
          v,
          style: const pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: '1A237E',
          ),
        ),
      ],
    ),
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
