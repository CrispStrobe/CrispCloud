import 'dart:io';

import 'dart:typed_data';

import 'package:quds_office_engine/pdf_widgets.dart' as pw;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../example/pdf_widgets_invoice.dart' as invoice;
import '../example/pdf_widgets_proposal.dart' as proposal;
import '../example/pdf_widgets_report.dart' as report;

void main() {
  final SfntFont? font = _tryFont();

  test('Row softWrap Text keeps intrinsic width so Expanded gets space', () {
    final pw.Document doc = pw.Document(font: font);
    late double labelW;
    late double amountW;
    late double titleW;
    doc.addPage(
      pw.Page(
        pageFormat: pw.PdfPageFormat.a4,
        build: (pw.Context context) {
          final pw.Widget money = pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Text(
                  'Subtotal',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.Text(
                '1,076',
                softWrap: false,
                style: const pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          );
          final pw.PwBox moneyBox = money.layout(
            context,
            const pw.BoxConstraints(maxWidth: 200, maxHeight: 40),
          );
          // Probe children via a second layout with known structure.
          final pw.Text label = pw.Text(
            'Subtotal',
            style: const pw.TextStyle(fontSize: 8),
          );
          final pw.Text amount = pw.Text(
            '1,076',
            softWrap: false,
            style: const pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          );
          amountW = amount
              .layout(
                context,
                const pw.BoxConstraints(maxWidth: 200, maxHeight: 40),
              )
              .size
              .width;
          labelW = label
              .layout(
                context,
                pw.BoxConstraints(
                  minWidth: 200 - amountW,
                  maxWidth: 200 - amountW,
                  maxHeight: 40,
                ),
              )
              .size
              .width;
          final pw.Widget header = pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Text(
                  'Sales order',
                  style: const pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Text(
                'Order SO-88',
                softWrap: false,
                textAlign: pw.TextAlign.end,
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          );
          final pw.PwBox headerBox = header.layout(
            context,
            const pw.BoxConstraints(maxWidth: 400, maxHeight: 80),
          );
          titleW = headerBox.size.width;
          expect(moneyBox.size.width, closeTo(200, 0.5));
          return pw.Column(children: <pw.Widget>[header, money]);
        },
      ),
    );
    doc.save();
    expect(amountW, lessThan(80));
    expect(labelW, greaterThan(40));
    expect(titleW, closeTo(400, 0.5));
  });

  test('Document.save emits a readable multi-page PDF', () {
    final pw.Document doc = pw.Document(title: 'Widget test', font: font);
    doc.addPage(
      pw.MultiPage(
        pageFormat: pw.PdfPageFormat.a4,
        build: (pw.Context context) => <pw.Widget>[
          pw.Header(level: 1, text: 'Alpha heading'),
          pw.Paragraph(text: 'Hello from constraint layout.'),
          const pw.TableOfContent(title: 'Contents'),
          pw.Header(level: 1, text: 'Beta heading'),
          const pw.NewPage(),
          pw.Paragraph(text: 'Second page body.'),
          pw.Table.fromTextArray(
            headers: const <String>['A', 'B'],
            data: const <List<String>>[
              ['one', 'two'],
            ],
          ),
        ],
      ),
    );
    final bytes = doc.save();
    expect(bytes.length, greaterThan(200));
    final PdfFile file = PdfFile.open(bytes);
    expect(file.pageCount, greaterThanOrEqualTo(2));
    final String text =
        PdfExtract.pageText(file, 0) + PdfExtract.pageText(file, 1);
    expect(text.contains('Hello'), isTrue);
    expect(text.contains('Alpha'), isTrue);
    expect(text.contains('Beta'), isTrue);
  });

  test('MultiPage Align shrink-wraps (invoice stays compact)', () {
    final pw.Document doc = pw.Document(font: font);
    doc.addPage(
      pw.MultiPage(
        pageFormat: pw.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) => <pw.Widget>[
          pw.Text('Title'),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(
            headers: const <String>['A', 'B'],
            data: const <List<String>>[
              <String>['1', '2'],
            ],
          ),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Total'),
          ),
        ],
      ),
    );
    final bytes = doc.save();
    expect(PdfFile.open(bytes).pageCount, 1);
  });

  test('table cells expand fill to full column width and row height', () {
    final pw.Document doc = pw.Document(font: font);
    late pw.PwSize tableSize;
    late pw.PwSize firstCellSize;
    doc.addPage(
      pw.Page(
        pageFormat: pw.PdfPageFormat.a4,
        build: (pw.Context context) {
          final pw.Table table = pw.Table.fromTextArray(
            headers: const <String>['A', 'B'],
            data: const <List<String>>[
              <String>['x', 'yy'],
            ],
            columnWidths: const <double>[2, 1],
          );
          final pw.PwBox box = table.layout(
            context,
            const pw.BoxConstraints(maxWidth: 300, maxHeight: 400),
          );
          tableSize = box.size;
          final pw.Container probe = pw.Container(
            color: 'FF0000',
            alignment: pw.Alignment.center,
            child: const pw.Text('x'),
          );
          firstCellSize = probe
              .layout(
                context,
                pw.BoxConstraints.tight(const pw.PwSize(200, 30)),
              )
              .size;
          return table;
        },
      ),
    );
    doc.save();
    expect(tableSize.width, closeTo(300, 0.1));
    expect(firstCellSize.width, closeTo(200, 0.1));
    expect(firstCellSize.height, closeTo(30, 0.1));
  });

  test('RTL fromTextArray pins cell text to the start edge', () {
    late double ltrDx;
    late double rtlDx;
    final pw.Document doc = pw.Document(font: font);
    doc.addPage(
      pw.Page(
        pageFormat: pw.PdfPageFormat.a4,
        textDirection: pw.TextDirection.ltr,
        build: (pw.Context context) {
          final pw.Container cell = pw.Container(
            width: 200,
            height: 30,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            alignment: pw.AlignmentDirectional.topStart,
            child: const pw.Text('x', softWrap: false),
          );
          final pw.ProxyBox box =
              cell.layout(context, const pw.BoxConstraints()) as pw.ProxyBox;
          ltrDx = box.childOffset.dx;
          return cell;
        },
      ),
    );
    doc.addPage(
      pw.Page(
        pageFormat: pw.PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          final pw.Container cell = pw.Container(
            width: 200,
            height: 30,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            alignment: pw.AlignmentDirectional.topStart,
            child: const pw.Text('x', softWrap: false),
          );
          final pw.ProxyBox box =
              cell.layout(context, const pw.BoxConstraints()) as pw.ProxyBox;
          rtlDx = box.childOffset.dx;
          return cell;
        },
      ),
    );
    doc.save();
    expect(ltrDx, lessThan(20));
    expect(rtlDx, greaterThan(150));
  });

  test('Row and Column honor flex and produce a non-empty box', () {
    final pw.Document doc = pw.Document(font: font);
    late pw.PwSize size;
    doc.addPage(
      pw.Page(
        pageFormat: pw.PdfPageFormat.a4,
        build: (pw.Context context) {
          final pw.Widget tree = pw.Column(
            children: const <pw.Widget>[
              pw.Text('Title'),
              pw.Row(
                children: <pw.Widget>[
                  pw.Expanded(child: pw.Text('L')),
                  pw.Expanded(child: pw.Text('R')),
                ],
              ),
            ],
          );
          final pw.PwBox box = tree.layout(
            context,
            const pw.BoxConstraints(maxWidth: 400, maxHeight: 200),
          );
          size = box.size;
          return tree;
        },
      ),
    );
    final bytes = doc.save();
    expect(bytes.length, greaterThan(100));
    expect(size.width, greaterThan(10));
    expect(size.height, greaterThan(10));
  });

  test('invoice / report / proposal examples open in PdfFile', () {
    final List<({String name, Uint8List bytes, int pages, String needle})>
    samples = <({String name, Uint8List bytes, int pages, String needle})>[
      (
        name: 'invoice',
        bytes: invoice.buildInvoice(font: font),
        pages: 1,
        needle: 'INV-2026',
      ),
      (
        name: 'report',
        bytes: report.buildQuarterlyReport(font: font),
        pages: 3,
        needle: 'Confidential',
      ),
      (
        name: 'proposal',
        bytes: proposal.buildProposal(font: font),
        pages: 1,
        needle: 'quds_office_engine',
      ),
    ];
    for (final sample in samples) {
      final PdfFile file = PdfFile.open(sample.bytes);
      expect(
        file.pageCount,
        greaterThanOrEqualTo(sample.pages),
        reason: sample.name,
      );
      final StringBuffer all = StringBuffer();
      for (int i = 0; i < file.pageCount; i++) {
        all.write(PdfExtract.pageText(file, i));
      }
      expect(all.toString(), contains(sample.needle), reason: sample.name);
    }
  });

  test('RTL widget text embeds joining forms without holes', () {
    final File cairo = File(
      '../quds_office_editor/example/fonts/Cairo-Regular.ttf',
    );
    final File naskh = File(
      '../quds_office_editor/fonts/NotoNaskhArabic-Regular.ttf',
    );
    final File faceFile = cairo.existsSync() ? cairo : naskh;
    expect(faceFile.existsSync(), isTrue, reason: faceFile.path);
    final SfntFont face = SfntFont.parse(faceFile.readAsBytesSync());
    const String phrase = 'تقرير ربع سنوي';
    final pw.Document doc = pw.Document(title: phrase, font: face);
    doc.addPage(
      pw.Page(
        pageFormat: pw.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[pw.Text(phrase)],
        ),
      ),
    );
    final PdfDisplayList list = PdfFile.open(doc.save()).displayList(0);
    final List<PdfDrawText> letters = <PdfDrawText>[
      for (final PdfPaintOp op in list.ops)
        if (op is PdfDrawText && op.text.trim().isNotEmpty) op,
    ];
    expect(letters.length, phrase.runes.where((int cp) => cp != 0x20).length);
    var maxGap = 0.0;
    for (int i = 1; i < letters.length; i++) {
      final double gap = letters[i].x - letters[i - 1].x;
      if (gap > maxGap) {
        maxGap = gap;
      }
    }
    expect(maxGap, lessThan(40));
    expect(letters.first.x, greaterThan(200));
    expect(letters.last.x, greaterThan(500));
  });

  test('RTL tashkeel paints on the base letter not a neighbour', () {
    final File cairo = File(
      '../quds_office_editor/example/fonts/Cairo-Regular.ttf',
    );
    final File naskh = File(
      '../quds_office_editor/fonts/NotoNaskhArabic-Regular.ttf',
    );
    final File faceFile = cairo.existsSync() ? cairo : naskh;
    expect(faceFile.existsSync(), isTrue, reason: faceFile.path);
    final SfntFont face = SfntFont.parse(faceFile.readAsBytesSync());
    const String word = 'أُنشئت';
    final pw.Document doc = pw.Document(font: face);
    doc.addPage(
      pw.Page(
        pageFormat: pw.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) => pw.Paragraph(
          text: word,
          textAlign: pw.TextAlign.start,
        ),
      ),
    );
    final PdfDisplayList list = PdfFile.open(doc.save()).displayList(0);
    final List<PdfDrawText> glyphs = <PdfDrawText>[
      for (final PdfPaintOp op in list.ops)
        if (op is PdfDrawText && op.text.isNotEmpty) op,
    ];
    PdfDrawText? damma;
    PdfDrawText? alef;
    PdfDrawText? sheen;
    for (final PdfDrawText g in glyphs) {
      final int cp = g.text.runes.first;
      if (cp == 0x064F) {
        damma = g;
      } else if (cp == 0x0623 || cp == 0xFE83 || cp == 0xFE84 || cp == 0xFE87) {
        alef = g;
      } else if (cp == 0x0634 || cp == 0xFEB7 || cp == 0xFEB8) {
        sheen = g;
      }
    }
    expect(damma, isNotNull);
    expect(alef, isNotNull);
    expect(sheen, isNotNull);
    final double toAlef = (damma!.x - alef!.x).abs();
    final double toSheen = (damma.x - sheen!.x).abs();
    expect(toAlef, lessThan(toSheen));
    expect(toAlef, lessThan(6));
  });

  test('RTL MultiPage short line starts on the right', () {
    final File cairo = File(
      '../quds_office_editor/example/fonts/Cairo-Regular.ttf',
    );
    final File naskh = File(
      '../quds_office_editor/fonts/NotoNaskhArabic-Regular.ttf',
    );
    final File faceFile = cairo.existsSync() ? cairo : naskh;
    expect(faceFile.existsSync(), isTrue, reason: faceFile.path);
    final SfntFont face = SfntFont.parse(faceFile.readAsBytesSync());
    const String title = 'تقرير ربع سنوي';
    const String body =
        'يلخص هذا التقرير تقدم برامج التعافي في حي التحرير خلال '
        'الربع الثالث من عام 2026. ارتفع الوصول إلى المياه إلى 73 بالمئة، '
        'واستقرت الملاجئ المتضررة جزئيا، بينما بقيت ملفات مفتوحة بانتظار '
        'التحقق الميداني في منتصف أيلول.';
    final pw.Document doc = pw.Document(title: title, font: face);
    doc.addPage(
      pw.MultiPage(
        pageFormat: pw.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) => <pw.Widget>[
          pw.Text(
            title,
            textAlign: pw.TextAlign.start,
            style: const pw.TextStyle(fontSize: 28),
          ),
          pw.Text(body, style: const pw.TextStyle(fontSize: 12, height: 1.55)),
        ],
      ),
    );
    final PdfDisplayList list = PdfFile.open(doc.save()).displayList(0);
    final List<PdfDrawText> titleGlyphs = <PdfDrawText>[
      for (final PdfPaintOp op in list.ops)
        if (op is PdfDrawText && op.size > 20 && op.text.trim().isNotEmpty) op,
    ];
    expect(titleGlyphs, isNotEmpty);
    final double titleLeft = titleGlyphs
        .map((PdfDrawText op) => op.x)
        .reduce((double a, double b) => a < b ? a : b);
    expect(titleLeft, greaterThan(280));
    final List<PdfDrawText> bodyGlyphs = <PdfDrawText>[
      for (final PdfPaintOp op in list.ops)
        if (op is PdfDrawText && op.size < 16 && op.text.trim().isNotEmpty) op,
    ];
    expect(bodyGlyphs.length, greaterThan(8));
    var lastY = 0.0;
    for (final PdfDrawText op in bodyGlyphs) {
      if (op.y > lastY) {
        lastY = op.y;
      }
    }
    final List<PdfDrawText> lastLine = <PdfDrawText>[
      for (final PdfDrawText op in bodyGlyphs)
        if ((op.y - lastY).abs() < 1) op,
    ];
    final double lastLeft = lastLine
        .map((PdfDrawText op) => op.x)
        .reduce((double a, double b) => a < b ? a : b);
    expect(lastLeft, greaterThan(200));
  });

  test('RTL text inside an LTR page keeps visual order', () {
    final File cairo = File(
      '../quds_office_editor/example/fonts/Cairo-Regular.ttf',
    );
    final File naskh = File(
      '../quds_office_editor/fonts/NotoNaskhArabic-Regular.ttf',
    );
    final File faceFile = cairo.existsSync() ? cairo : naskh;
    expect(faceFile.existsSync(), isTrue, reason: faceFile.path);
    final SfntFont face = SfntFont.parse(faceFile.readAsBytesSync());
    final pw.Document doc = pw.Document(title: 'bidi', font: face);
    doc.addPage(
      pw.MultiPage(
        pageFormat: pw.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        textDirection: pw.TextDirection.ltr,
        build: (pw.Context context) => <pw.Widget>[
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Text(
              'ما اتُفق عليه',
              textAlign: pw.TextAlign.start,
              style: const pw.TextStyle(fontSize: 22),
            ),
          ),
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Table.fromTextArray(
              headers: const <String>['البند', 'القرار'],
              data: const <List<String>>[
                <String>['المياه', 'الإبقاء'],
              ],
            ),
          ),
        ],
      ),
    );
    final PdfDisplayList list = PdfFile.open(doc.save()).displayList(0);
    final List<PdfDrawText> title = <PdfDrawText>[
      for (final PdfPaintOp op in list.ops)
        if (op is PdfDrawText && op.size > 16 && op.text.trim().isNotEmpty) op,
    ];
    expect(title, isNotEmpty);
    title.sort((PdfDrawText a, PdfDrawText b) => a.x.compareTo(b.x));
    expect(title.last.x, greaterThan(400));
    expect(_isMeem(title.last.text), isTrue, reason: title.last.text);
    final List<PdfDrawText> headers = <PdfDrawText>[
      for (final PdfPaintOp op in list.ops)
        if (op is PdfDrawText && op.size < 16 && op.text.trim().isNotEmpty) op,
    ];
    expect(headers, isNotEmpty);
    var bandX = 0.0;
    var decisionX = 0.0;
    for (final PdfDrawText op in headers) {
      if (_hasArabic(op.text, 0x0628, 0xFE8F, 0xFE92) && op.x > bandX) {
        bandX = op.x;
      }
      if (_hasArabic(op.text, 0x0642, 0xFED5, 0xFED8) && op.x > decisionX) {
        decisionX = op.x;
      }
    }
    expect(bandX, greaterThan(0));
    expect(decisionX, greaterThan(0));
    expect(bandX, greaterThan(decisionX));
  });

  test('TableOfContent rows are internal links to later headings', () {
    final pw.Document doc = pw.Document(title: 'TOC', font: font);
    doc.addPage(
      pw.MultiPage(
        pageFormat: pw.PdfPageFormat.a4,
        build: (pw.Context context) => <pw.Widget>[
          const pw.TableOfContent(title: 'Contents'),
          const pw.NewPage(),
          pw.Header(level: 1, text: 'Water points'),
          pw.Paragraph(text: 'Standpipes on the east lane.'),
          const pw.NewPage(),
          pw.Header(level: 1, text: 'Clinic hours'),
          pw.Paragraph(text: 'Walk-ins until 16:00.'),
        ],
      ),
    );
    final PdfFile file = PdfFile.open(doc.save());
    expect(file.pageCount, greaterThan(1));
    final List<PdfAnnot> links = file
        .annotsOn(0)
        .where((PdfAnnot annot) => annot.goToPage != null)
        .toList();
    expect(links.length, greaterThanOrEqualTo(2));
    expect(
      links.map((PdfAnnot annot) => annot.goToPage).toSet(),
      containsAll(<int>[1, 2]),
    );
    expect(links.every((PdfAnnot annot) => annot.goToY != null), isTrue);
    final PdfAnnot later = links.firstWhere(
      (PdfAnnot annot) => annot.goToPage == 1,
    );
    expect(later.goToY!, lessThan(file.pageAt(1).height - 8));
  });

  test('UrlLink survives save as a URI hotspot', () {
    final pw.Document doc = pw.Document(title: 'Link');
    doc.addPage(
      pw.Page(
        build: (pw.Context context) => pw.UrlLink(
          destination: 'https://quds.office/samples/widgets',
          child: pw.Container(width: 160, height: 18),
        ),
      ),
    );
    final PdfFile file = PdfFile.open(doc.save());
    expect(file.annotsOn(0), hasLength(1));
    expect(file.annotsOn(0).single.uri, 'https://quds.office/samples/widgets');
    expect(
      file.displayList(0).hotspots.single.action.uri,
      'https://quds.office/samples/widgets',
    );
  });

  test('MultiPage splits a long table and repeats the header', () {
    final pw.Document doc = pw.Document(
      title: 'Span',
      font: font,
      fontBold: _tryBoldFont(),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: const pw.PdfPageFormat(300, 220, marginAll: 24),
        build: (pw.Context context) => <pw.Widget>[
          pw.Column(
            children: <pw.Widget>[
              pw.Table.fromTextArray(
                headers: const <String>['Item', 'Qty'],
                cellHeight: 22,
                data: <List<String>>[
                  for (int i = 1; i <= 12; i++) <String>['Row $i', '$i'],
                ],
              ),
            ],
          ),
        ],
      ),
    );
    final PdfFile file = PdfFile.open(doc.save());
    expect(file.pageCount, greaterThan(1));
    final String page1 = PdfExtract.pageText(file, 0);
    final String last = PdfExtract.pageText(file, file.pageCount - 1);
    expect(page1.contains('Item'), isTrue);
    expect(page1.contains('Row 1'), isTrue);
    expect(PdfExtract.pageText(file, 1).contains('Item'), isTrue);
    expect(last.contains('Row 12'), isTrue);
    expect(page1.contains('Row 12'), isFalse);
  });

  test('gradient fill and chart values land in the PDF stream', () {
    final pw.Document doc = pw.Document(
      title: 'Visual',
      font: font,
      fontBold: _tryBoldFont(),
    );
    doc.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          children: <pw.Widget>[
            pw.Container(
              width: 180,
              height: 36,
              decoration: const pw.BoxDecoration(
                gradient: pw.LinearGradient(
                  colors: <String>['1A237E', '00ACC1'],
                ),
              ),
            ),
            pw.Chart(
              title: 'Caseload',
              points: const <ChartPoint>[
                ChartPoint(label: 'WASH', value: 12, color: '1565C0'),
                ChartPoint(label: 'Shelter', value: 7, color: '00897B'),
              ],
            ),
          ],
        ),
      ),
    );
    final Uint8List bytes = doc.save();
    final PdfFile file = PdfFile.open(bytes);
    final String text = PdfExtract.pageText(file, 0);
    expect(text.contains('Caseload'), isTrue);
    expect(text.contains('WASH'), isTrue);
    expect(text.contains('12'), isTrue);
    final int fills = file.displayList(0).ops.whereType<PdfFillPath>().length;
    expect(fills, greaterThan(20));
  });

  test('watermark is one rotated string, not a letter per operator', () {
    PdfFile stamp(String word) {
      final pw.Document doc = pw.Document(title: 'Stamp', font: font);
      doc.addPage(
        pw.MultiPage(
          build: (pw.Context context) => <pw.Widget>[
            pw.Watermark.text(word),
            const pw.Text('Body'),
          ],
        ),
      );
      return PdfFile.open(doc.save());
    }

    List<PdfDrawText> marks(PdfFile file) {
      return file
          .displayList(0)
          .ops
          .whereType<PdfDrawText>()
          .where((PdfDrawText op) => op.angle.abs() > 0.02)
          .toList();
    }

    final List<PdfDrawText> latin = marks(stamp('ATLAS'));
    expect(latin, hasLength(1));
    expect(latin.single.text, 'ATLAS');

    final List<PdfDrawText> arabic = marks(stamp('ملاحظة'));
    expect(arabic, hasLength(1));
    expect(arabic.single.text, 'ملاحظة');
  });

  test('directional insets and alignments flip with reading direction', () {
    expect(
      const pw.EdgeInsetsDirectional.fromSTEB(8, 1, 2, 3)
          .resolve(pw.TextDirection.ltr)
          .left,
      8,
    );
    expect(
      const pw.EdgeInsetsDirectional.fromSTEB(8, 1, 2, 3)
          .resolve(pw.TextDirection.rtl)
          .left,
      2,
    );
    expect(
      pw.AlignmentDirectional.centerStart.resolve(pw.TextDirection.ltr).x,
      -1,
    );
    expect(
      pw.AlignmentDirectional.centerStart.resolve(pw.TextDirection.rtl).x,
      1,
    );
  });

  test('flutter twins save and ellipsize a narrow line', () {
    final pw.Document doc = pw.Document(title: 'Twins', font: font);
    doc.addPage(
      pw.Page(
        pageFormat: pw.PdfPageFormat.a4,
        build: (pw.Context context) => pw.Column(
          children: <pw.Widget>[
            pw.SizedBox(
              width: 80,
              child: pw.Text(
                'Harbour close is a long line',
                maxLines: 1,
                overflow: pw.TextOverflow.ellipsis,
                style: const pw.TextStyle(fontSize: 12),
              ),
            ),
            pw.ListTile(
              leading: const pw.Icon(0x51),
              title: pw.Text('List title'),
              subtitle: pw.Text('slot row'),
              trailing: const pw.Radio(value: true),
            ),
            pw.Row(
              children: <pw.Widget>[
                const pw.Switch(value: true),
                const pw.VerticalDivider(),
                pw.RotatedBox(quarterTurns: 1, child: pw.Text('SIDE')),
              ],
            ),
            pw.ClipOval(
              child: pw.Container(
                width: 20,
                height: 20,
                color: '0F766E',
              ),
            ),
            pw.Transform.rotate(
              angle: -0.2,
              child: pw.Text('draft'),
            ),
          ],
        ),
      ),
    );
    final bytes = doc.save();
    expect(bytes.length, greaterThan(200));
    final String text = PdfExtract.pageText(PdfFile.open(bytes), 0);
    expect(text.contains('List title'), isTrue);
    if (font != null) {
      expect(text.contains('\u2026') || text.contains('...'), isTrue);
    }
  });
}

bool _isMeem(String text) {
  return _hasArabic(text, 0x0645, 0xFEE1, 0xFEE4);
}

bool _hasArabic(String text, int nominal, int form0, int form1) {
  for (final int cp in text.runes) {
    if (cp == nominal || (cp >= form0 && cp <= form1)) {
      return true;
    }
  }
  return false;
}

SfntFont? _tryFont() {
  for (final (String regular, String _) in _fontPairs) {
    final File file = File(regular);
    if (file.existsSync()) {
      return SfntFont.parse(file.readAsBytesSync());
    }
  }
  return null;
}

SfntFont? _tryBoldFont() {
  for (final (String regular, String bold) in _fontPairs) {
    if (!File(regular).existsSync() || !File(bold).existsSync()) {
      continue;
    }
    return SfntFont.parse(File(bold).readAsBytesSync());
  }
  return null;
}

const List<(String, String)> _fontPairs = <(String, String)>[
  (
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  ),
  (
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
  ),
];
