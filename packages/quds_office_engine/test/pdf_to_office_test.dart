import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('prose lines become docx, xlsx, and pptx text', () {
    final Uint8List pdf = _page((PdfCanvas canvas) {
      canvas.showLatin(
        x: 72,
        y: 80,
        fontSize: 14,
        text: 'Hello PDF',
        color: '000000',
      );
      canvas.showLatin(
        x: 72,
        y: 110,
        fontSize: 14,
        text: 'Second line',
        color: '000000',
      );
      canvas.endText();
    });

    final OfficeTextExtract docx = OfficeTextExtractor.extract(
      PdfToOffice.toDocx(pdf),
      name: 'out.docx',
    );
    expect(docx.paragraphs.join('\n'), contains('Hello PDF'));
    expect(docx.paragraphs.join('\n'), contains('Second line'));
    final WmlDocument word = WordDeserializer().read(
      OpcPackage.openBytes(PdfToOffice.toDocx(pdf)),
    );
    final List<WmlFrame> frames = <WmlFrame>[
      for (final WmlBlock block in word.sections.single.blocks)
        if (block is WmlFrame) block,
    ];
    expect(frames, isNotEmpty);
    expect(
      frames.every((WmlFrame frame) => frame.anchor == WmlFrameAnchor.page),
      isTrue,
    );
    expect(frames.first.y, lessThan(80));

    final OfficeTextExtract xlsx = OfficeTextExtractor.extract(
      PdfToOffice.toXlsx(pdf),
      name: 'out.xlsx',
    );
    final String sheet = xlsx.sheets.single.rows
        .map((List<String> row) => row.join(' '))
        .join('\n');
    expect(sheet, contains('Hello PDF'));
    expect(sheet, contains('Second line'));

    final OfficeTextExtract pptx = OfficeTextExtractor.extract(
      PdfToOffice.toPptx(pdf),
      name: 'out.pptx',
    );
    final OfficeExtractSlide slide = pptx.slides.single;
    final String slideText = '${slide.title}\n${slide.body.join('\n')}';
    expect(slideText, contains('Hello PDF'));
    expect(slideText, contains('Second line'));
  });

  test('a ruled 2x2 grid becomes an xlsx table', () {
    final Uint8List pdf = _page((PdfCanvas canvas) {
      const double left = 72;
      const double top = 160;
      const double col = 120;
      const double row = 28;
      for (var r = 0; r < 2; r++) {
        for (var c = 0; c < 2; c++) {
          canvas.strokeRect(left + c * col, top + r * row, col, row, '000000');
        }
      }
      const List<String> cells = <String>['Name', 'Qty', 'Pen', '4'];
      for (var i = 0; i < cells.length; i++) {
        canvas.showLatin(
          x: left + (i % 2) * col + 8,
          y: top + (i ~/ 2) * row + 18,
          fontSize: 12,
          text: cells[i],
          color: '000000',
        );
      }
      canvas.endText();
    });

    final PdfOfficeRecovery recovery = PdfToOffice.recover(PdfFile.open(pdf));
    expect(recovery.pages.single.tables, hasLength(1));
    expect(recovery.pages.single.tables.single.rows, <List<String>>[
      <String>['Name', 'Qty'],
      <String>['Pen', '4'],
    ]);

    final OfficeTextExtract xlsx = OfficeTextExtractor.extract(
      PdfToOffice.toXlsx(pdf),
      name: 'table.xlsx',
    );
    final OfficeExtractSheet sheet = xlsx.sheets.firstWhere(
      (OfficeExtractSheet s) => s.name.startsWith('Table'),
    );
    expect(sheet.rows[0], containsAll(<String>['Name', 'Qty']));
    expect(sheet.rows[1], containsAll(<String>['Pen', '4']));
  });

  test('side by side lines stay in two columns', () {
    final Uint8List pdf = _page((PdfCanvas canvas) {
      canvas.showLatin(
        x: 72,
        y: 80,
        fontSize: 12,
        text: 'Left side',
        color: '000000',
      );
      canvas.showLatin(
        x: 340,
        y: 80,
        fontSize: 12,
        text: 'Right side',
        color: '000000',
      );
      canvas.showLatin(
        x: 72,
        y: 100,
        fontSize: 12,
        text: 'Left next',
        color: '000000',
      );
      canvas.showLatin(
        x: 340,
        y: 100,
        fontSize: 12,
        text: 'Right next',
        color: '000000',
      );
      canvas.endText();
    });
    final List<String> lines = PdfToOffice.recover(
      PdfFile.open(pdf),
    ).pages.single.lines.map((PdfOfficeLine line) => line.text).toList();
    expect(lines, <String>[
      'Left side',
      'Left next',
      'Right side',
      'Right next',
    ]);
  });

  test('a page-sized ruled frame is not a table', () {
    final Uint8List pdf = _page((PdfCanvas canvas) {
      canvas.strokeRect(36, 36, 250, 760, '000000');
      canvas.strokeRect(286, 36, 270, 760, '000000');
      canvas.moveTo(36, 400);
      canvas.lineTo(556, 400);
      canvas.stroke();
      canvas.showLatin(
        x: 48,
        y: 80,
        fontSize: 14,
        text: 'Neighbourhood profile',
        color: '000000',
      );
      canvas.endText();
    });
    final PdfOfficePage page = PdfToOffice.recover(
      PdfFile.open(pdf),
    ).pages.single;
    expect(page.tables, isEmpty);
    expect(
      page.lines.map((PdfOfficeLine line) => line.text).join('\n'),
      contains('Neighbourhood profile'),
    );
  });

  test('a raw RGB image is embedded as PNG', () {
    final PdfCanvas canvas = PdfCanvas(595.28, 841.89);
    canvas.drawImage('Im1', 40, 50, 80, 60);
    final PdfDocument doc = PdfDocument(title: 'Image');
    doc.addPage(
      PdfPage(
        width: 595.28,
        height: 841.89,
        content: canvas.toStream(),
        images: <PdfEmbeddedImage>[
          PdfEmbeddedImage(
            name: 'Im1',
            width: 2,
            height: 2,
            bytes: Uint8List.fromList(<int>[
              255,
              0,
              0,
              0,
              255,
              0,
              0,
              0,
              255,
              255,
              255,
              0,
            ]),
          ),
        ],
      ),
    );
    final PdfOfficeImage image = PdfToOffice.recover(
      PdfFile.open(doc.save()),
    ).pages.single.images.single;
    expect(image.mime, 'image/png');
    expect(image.bytes, isNotNull);
    expect(image.bytes!.take(4), <int>[137, 80, 78, 71]);
    expect(image.width, greaterThan(40));
    expect(image.height, greaterThan(40));
  });

  test('one rectangle is not a table', () {
    final Uint8List pdf = _page((PdfCanvas canvas) {
      canvas.strokeRect(72, 160, 200, 40, '000000');
      canvas.showLatin(
        x: 80,
        y: 186,
        fontSize: 12,
        text: 'Caption',
        color: '000000',
      );
      canvas.endText();
    });
    final PdfOfficeRecovery recovery = PdfToOffice.recover(PdfFile.open(pdf));
    expect(recovery.pages.single.tables, isEmpty);
    expect(
      recovery.pages.single.lines.map((PdfOfficeLine line) => line.text),
      contains('Caption'),
    );
  });

  test('a page with no text is reported and not invented', () {
    final Uint8List pdf = _page((PdfCanvas canvas) {
      canvas.fillRect(72, 72, 200, 40, '2B579A');
    });
    final PdfOfficeRecovery recovery = PdfToOffice.recover(PdfFile.open(pdf));
    expect(
      recovery.notices.map((PdfOfficeNotice n) => n.kind),
      contains(PdfOfficeNoticeKind.noExtractableText),
    );
    expect(recovery.hasExtractableText, isFalse);

    final OfficeTextExtract docx = OfficeTextExtractor.extract(
      PdfToOffice.toDocx(pdf),
      name: 'empty.docx',
    );
    expect(docx.paragraphs.join('\n'), contains(pdfOfficeNoTextMessage));
  });

  test('the export isolate reports each page and writes docx', () async {
    final Uint8List pdf = _page((PdfCanvas canvas) {
      canvas.showLatin(
        x: 72,
        y: 80,
        fontSize: 14,
        text: 'Hello PDF',
        color: '000000',
      );
      canvas.endText();
    });
    final List<String> stages = <String>[];
    final PdfOfficeExportRun run = await startPdfOfficeExport(
      bytes: pdf,
      extension: 'docx',
      onProgress: (PdfOfficeExportProgress step) {
        stages.add(step.stage);
      },
    );
    final PdfOfficeExportResult result = await run.done.timeout(
      const Duration(seconds: 20),
    );
    expect(result.error, isNull);
    expect(stages, containsAllInOrder(<String>['open', 'page', 'write']));
    final OfficeTextExtract docx = OfficeTextExtractor.extract(
      result.bytes!,
      name: 'out.docx',
    );
    expect(docx.paragraphs.join('\n'), contains('Hello PDF'));
  });

  test('ActualText is the line when the page has no glyphs', () {
    final Uint8List pdf = _page((PdfCanvas canvas) {
      canvas.showMarkedLine(
        x: 72,
        y: 90,
        fontSize: 16,
        logical: 'فاتورة',
        color: '000000',
        fontName: 'F2',
      );
    });
    final PdfOfficeRecovery recovery = PdfToOffice.recover(PdfFile.open(pdf));
    final String text = recovery.pages.single.lines
        .map((PdfOfficeLine line) => line.text)
        .join('\n');
    expect(text, contains('فاتورة'));

    final OfficeTextExtract docx = OfficeTextExtractor.extract(
      PdfToOffice.toDocx(pdf),
      name: 'ar.docx',
    );
    expect(docx.paragraphs.join('\n'), contains('فاتورة'));
  });

  test('column bars become a native chart and a sheet of values', () {
    final Uint8List pdf = _page((PdfCanvas canvas) {
      canvas.showLatin(
        x: 80,
        y: 120,
        fontSize: 12,
        text: 'Sales',
        color: '1F4E79',
      );
      canvas.fillRect(80, 200, 40, 80, '4472C4');
      canvas.fillRect(140, 140, 40, 140, 'ED7D31');
      canvas.fillRect(200, 170, 40, 110, '70AD47');
      canvas.showLatin(
        x: 80,
        y: 292,
        fontSize: 9,
        text: 'North',
        color: '000000',
      );
      canvas.showLatin(
        x: 140,
        y: 292,
        fontSize: 9,
        text: 'South',
        color: '000000',
      );
      canvas.showLatin(
        x: 200,
        y: 292,
        fontSize: 9,
        text: 'East',
        color: '000000',
      );
      canvas.endText();
    });
    final PdfOfficeChart chart = PdfToOffice.recover(
      PdfFile.open(pdf),
    ).pages.single.charts.single;
    expect(chart.kind, PdfOfficeChartKind.column);
    expect(chart.title, 'Sales');
    expect(
      chart.points.map((PdfOfficeChartPoint point) => point.label),
      <String>['North', 'South', 'East'],
    );
    expect(chart.points[1].value, greaterThan(chart.points[0].value));

    final String chartXml = OpcPackage.openBytes(
      PdfToOffice.toDocx(pdf),
    ).getPart('/word/charts/chart1.xml')!.readText();
    expect(chartXml, contains('North'));
    expect(chartXml, contains('Sales'));

    final OfficeTextExtract xlsx = OfficeTextExtractor.extract(
      PdfToOffice.toXlsx(pdf),
      name: 'bars.xlsx',
    );
    final String sheet = xlsx.sheets
        .map(
          (OfficeExtractSheet item) =>
              item.rows.map((List<String> row) => row.join(' ')).join('\n'),
        )
        .join('\n');
    expect(sheet, contains('North'));
    expect(sheet, contains('South'));
  });

  test('the PDF outline becomes a Word table of contents', () {
    final PdfDocument doc = PdfDocument(title: 'Outline');
    final PdfCanvas canvas = PdfCanvas(595.28, 841.89);
    canvas.showLatin(
      x: 72,
      y: 80,
      fontSize: 18,
      text: 'Sales',
      color: '000000',
    );
    canvas.endText();
    doc.addPage(
      PdfPage(width: 595.28, height: 841.89, content: canvas.toStream()),
    );
    doc.addOutline(const PdfOutlineItem(title: 'Sales', pageIndex: 0));
    doc.addOutline(const PdfOutlineItem(title: 'Costs', pageIndex: 0));
    final Uint8List pdf = doc.save();
    final PdfOfficeRecovery recovery = PdfToOffice.recover(PdfFile.open(pdf));
    expect(recovery.toc.map((PdfOfficeTocEntry entry) => entry.title), <String>[
      'Sales',
      'Costs',
    ]);
    expect(recovery.pages.single.lines.first.headingLevel, 1);

    final OfficeTextExtract docx = OfficeTextExtractor.extract(
      PdfToOffice.toDocx(pdf),
      name: 'toc.docx',
    );
    final String text = docx.paragraphs.join('\n');
    expect(text, contains('Contents'));
    expect(text, contains('Costs'));
  });

  test('a link annotation becomes a Word hyperlink', () {
    final PdfCanvas canvas = PdfCanvas(595.28, 841.89);
    canvas.showLatin(
      x: 72,
      y: 80,
      fontSize: 14,
      text: 'Hello PDF',
      color: '000000',
    );
    canvas.endText();
    final PdfDocument doc = PdfDocument(title: 'Link');
    doc.addPage(
      PdfPage(
        width: 595.28,
        height: 841.89,
        content: canvas.toStream(),
        links: const <PdfLinkAnnot>[
          PdfLinkAnnot(
            x: 70,
            y: 66,
            width: 90,
            height: 18,
            uri: 'https://example.com/report',
          ),
        ],
      ),
    );
    final Uint8List bytes = doc.save();
    expect(
      PdfToOffice.recover(
        PdfFile.open(bytes),
      ).pages.single.lines.single.linkUrl,
      'https://example.com/report',
    );
    final OpcPackage package = OpcPackage.openBytes(PdfToOffice.toDocx(bytes));
    expect(
      package.getPart('/word/document.xml')!.readText(),
      contains('hyperlink'),
    );
    expect(
      package
          .relationshipsFor('/word/document.xml')
          .items
          .map((PackageRelationship rel) => rel.target)
          .join('\n'),
      contains('https://example.com/report'),
    );
  });
}

Uint8List _page(void Function(PdfCanvas canvas) paint) {
  final PdfDocument doc = PdfDocument(title: 'PDF to Office');
  final PdfCanvas canvas = PdfCanvas(595.28, 841.89);
  paint(canvas);
  doc.addPage(
    PdfPage(width: 595.28, height: 841.89, content: canvas.toStream()),
  );
  return doc.save();
}
