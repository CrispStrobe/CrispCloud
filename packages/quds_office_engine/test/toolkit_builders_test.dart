import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// 1×1 transparent PNG.
final Uint8List _png = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

/// 4×2 PNG header (rest padded) so contain-fit can read IHDR.
final Uint8List _widePng = () {
  final Uint8List bytes = Uint8List.fromList(_png);
  bytes[16] = 0;
  bytes[17] = 0;
  bytes[18] = 0;
  bytes[19] = 4;
  bytes[20] = 0;
  bytes[21] = 0;
  bytes[22] = 0;
  bytes[23] = 2;
  return bytes;
}();

void main() {
  test('OfficeDocumentTheme factories and color cycle', () {
    final OfficeDocumentTheme light = OfficeDocumentTheme.light();
    final OfficeDocumentTheme dark = OfficeDocumentTheme.dark(rtl: true);
    final OfficeDocumentTheme custom = OfficeDocumentTheme.custom(
      palette: const OfficePalette(primary: '112233'),
      rtl: true,
    );
    expect(light.palette.primary, '2E75B6');
    expect(dark.rtl, isTrue);
    expect(custom.palette.primary, '112233');
    expect(light.colorAt(0), light.palette.primary);
    expect(light.page.widthPoints, greaterThan(0));
    expect(OfficeColors.red, 'FF0000');
    expect(OfficeColors.parse('red'), OfficeColors.red);
    expect(OfficeColors.parse('antique-gold'), OfficeColors.antiqueGold);
    expect(OfficeColors.parse('#2b579a'), '2B579A');
    const OfficePalette named = OfficePalette(
      primary: OfficeColors.wordBlue,
      accent: OfficeColors.antiqueGold,
    );
    expect(named.primary, '2B579A');
    expect(named.accent, 'C9A227');
  });

  test('theme colors appear in Word, PPTX, and XLSX packages', () {
    const OfficeDocumentTheme theme = OfficeDocumentTheme(
      palette: OfficePalette(primary: 'AB1234', tableHeader: 'AB1234'),
    );
    final Uint8List docx = (DocxDocumentBuilder(
      theme: theme,
    )..heading('Title')).build();
    expect(
      OpcPackage.openBytes(docx).getPart('/word/document.xml')!.readText(),
      contains('AB1234'),
    );

    final Uint8List pptx = (PptxDeckBuilder(
      theme: theme,
    )..addCoverSlide(title: 'Title')).build();
    expect(
      OpcPackage.openBytes(pptx).getPart('/ppt/slides/slide1.xml')!.readText(),
      contains('AB1234'),
    );

    final XlsxWorkbookBuilder book = XlsxWorkbookBuilder(theme: theme);
    book.addSheet('S').addRow(<Object?>['A']);
    final Uint8List xlsx = book.build();
    expect(
      OpcPackage.openBytes(xlsx).getPart('/xl/styles.xml')!.readText(),
      contains(theme.fontFamily),
    );
  });

  test('PptxDeckBuilder writes geometric layouts, notes, and line chart', () {
    final PptxDeckBuilder deck =
        PptxDeckBuilder(rtl: true, showSlideNumber: true, footerBar: 'Footer')
          ..addCoverSlide(
            title: 'Title',
            kicker: 'Kicker',
            subtitle: 'Sub',
            accentRail: true,
          )
          ..addSectionSlide(title: 'Section', kicker: '01')
          ..addQuoteSlide(quote: 'Quote', attribution: 'Author', title: 'Q')
          ..addKpiSlide(
            title: 'KPI',
            cards: <({String label, String value})>[
              (label: 'Item A', value: '42'),
              (label: 'Item B', value: '7'),
            ],
          )
          ..addSplitMediaSlide(
            title: 'Media',
            bullets: <String>['A'],
            imageBytes: _png,
          )
          ..addSplitChartSlide(
            title: 'Split',
            bullets: <String>['A'],
            kind: ChartKind.pie,
            points: const <ChartPoint>[
              ChartPoint(label: 'A', value: 2),
              ChartPoint(label: 'B', value: 1),
            ],
          )
          ..addTwoColumnTextSlide(
            title: 'Cols',
            leftTitle: 'L',
            rightTitle: 'R',
            left: <String>['1'],
            right: <String>['2'],
          )
          ..addImageSlide(title: 'Image', pngBytes: _widePng, caption: 'Cap')
          ..addClosingSlide(title: 'End', notes: 'Say goodbye')
          ..addLineChartSlide(
            title: 'Trend',
            series: const <ChartSeries>[
              ChartSeries(
                name: 'S1',
                points: <ChartPoint>[
                  ChartPoint(label: 'A', value: 1),
                  ChartPoint(label: 'B', value: 3),
                ],
              ),
            ],
          );
    final Uint8List bytes = deck.build();
    final OpcPackage pkg = OpcPackage.openBytes(bytes);
    expect(pkg.kind, OpcPackageKind.slide);
    expect(pkg.getPart('/ppt/slides/slide10.xml'), isNotNull);
    expect(pkg.getPart('/ppt/notesSlides/notesSlide9.xml'), isNotNull);
    expect(
      pkg.getPart('/ppt/notesSlides/notesSlide9.xml')!.readText(),
      contains('Say goodbye'),
    );
    expect(
      pkg.getPart('/ppt/charts/chart2.xml')!.readText(),
      contains('<c:lineChart'),
    );
    expect(
      pkg.getPart('/ppt/slides/slide1.xml')!.readText(),
      contains('Kicker'),
    );
    expect(pkg.getPart('/ppt/slides/slide4.xml')!.readText(), contains('42'));
  });

  test('image contain-fit uses IHDR aspect', () {
    final ImageSize? size = ImageFit.readPngSize(_widePng);
    expect(size, isNotNull);
    expect(size!.widthPx / size.heightPx, 2);
    final ({int cx, int cy}) box = ImageFit.containEmu(
      srcWidthPx: 4,
      srcHeightPx: 2,
      maxCx: 1000000,
      maxCy: 1000000,
    );
    expect(box.cx / box.cy, closeTo(2, 0.01));
    expect(box.cx, lessThanOrEqualTo(1000000));
    expect(box.cy, lessThanOrEqualTo(1000000));

    final Uint8List pptx =
        (PptxDeckBuilder()..addImageSlide(title: 'Fit', pngBytes: _widePng))
            .build();
    final String xml = OpcPackage.openBytes(
      pptx,
    ).getPart('/ppt/slides/slide1.xml')!.readText();
    expect(xml, contains('<p:pic>'));
    final RegExp ext = RegExp(r'<a:ext cx="(\d+)" cy="(\d+)"/>');
    final Iterable<RegExpMatch> matches = ext.allMatches(xml);
    expect(matches, isNotEmpty);
    final RegExpMatch pic = matches.last;
    final int cx = int.parse(pic.group(1)!);
    final int cy = int.parse(pic.group(2)!);
    expect(cx / cy, closeTo(2, 0.05));
  });

  test(
    'DocxDocumentBuilder chrome: note, hyperlink, header, bookmark, list start',
    () {
      final DocxDocumentBuilder doc = DocxDocumentBuilder(rtl: true)
        ..heading('Title')
        ..note('Note text')
        ..caption('Figure 1')
        ..spacer()
        ..hyperlink('Site', 'https://example.com')
        ..bookmark('intro')
        ..header(left: 'Left', pageNumber: false)
        ..footer(pageNumber: true)
        ..numberedList(<String>['One', 'Two'], start: 4)
        ..image(_png, maxWidthPx: 64, caption: 'Tiny')
        ..lineChart(
          title: 'Trend',
          series: const <ChartSeries>[
            ChartSeries(
              name: 'S',
              points: <ChartPoint>[
                ChartPoint(label: 'A', value: 2),
                ChartPoint(label: 'B', value: 4),
              ],
            ),
          ],
        );
      final Uint8List bytes = doc.build();
      final OpcPackage pkg = OpcPackage.openBytes(bytes);
      expect(pkg.getPart('/word/header1.xml')!.readText(), contains('Left'));
      expect(pkg.getPart('/word/footer1.xml')!.readText(), contains('PAGE'));
      expect(
        pkg.getPart('/word/document.xml')!.readText(),
        contains('bookmarkStart'),
      );
      expect(
        pkg.getPart('/word/document.xml')!.readText(),
        contains('rIdLink1'),
      );
      expect(
        pkg.getPart('/word/numbering.xml')!.readText(),
        contains('w:val="4"'),
      );
      expect(
        pkg.getPart('/word/charts/chart1.xml')!.readText(),
        contains('<c:lineChart'),
      );
      final extracted = DocxPlainReader.read(bytes);
      expect(extracted.hyperlinks, isNotEmpty);
      expect(extracted.hyperlinks.first.url, 'https://example.com');
    },
  );

  test('OfficeTextExtractor reads PPTX notes and ODT text', () {
    final Uint8List pptx =
        (PptxDeckBuilder()..addTitleBodySlide(
              title: 'Title',
              bullets: <String>['Item A'],
              notes: 'Speak this',
            ))
            .build();
    final OfficeTextExtract slide = OfficeTextExtractor.extract(
      pptx,
      name: 'deck.pptx',
    );
    expect(slide.kind, OfficeExtractKind.slide);
    expect(slide.slides, isNotEmpty);
    expect(slide.slides.first.title, contains('Title'));
    expect(slide.plainString, contains('Speak this'));

    final ZipWriter zip = ZipWriter();
    zip.addFile(
      'mimetype',
      utf8.encode('application/vnd.oasis.opendocument.text'),
      store: true,
    );
    zip.addFile(
      'content.xml',
      utf8.encode(
        '<?xml version="1.0"?>'
        '<office:document-content xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">'
        '<text:h>Title</text:h><text:p>Item A</text:p>'
        '</office:document-content>',
      ),
    );
    final OfficeTextExtract odt = OfficeTextExtractor.extract(
      zip.close(),
      name: 'note.odt',
    );
    expect(odt.kind, OfficeExtractKind.opendocumentText);
    expect(odt.paragraphs.join(' '), contains('Title'));
    expect(odt.paragraphs.join(' '), contains('Item A'));
  });

  test('fitColumnWidths skips a merged banner row', () {
    final XlsxWorkbookBuilder book = XlsxWorkbookBuilder();
    final int dateStyle = book.style(numFmt: 'yyyy-mm-dd');
    final XlsxSheetBuilder sheet = book.addSheet('Data');
    sheet
      ..addRow(<Object?>['VERY LONG BANNER TITLE FOR THE SHEET'])
      ..merge(0, 0, 0, 2)
      ..addRow(<Object?>['A', 'BB', 'CCC'])
      ..setCell(2, 0, 44927, style: dateStyle)
      ..fitColumnWidths(fromRow: 0, toRow: 1, colCount: 3);
    expect(sheet.columnWidths, isNotEmpty);
    final double first = sheet.columnWidths.first.width;
    expect(first, lessThan(20));
    final Uint8List bytes = book.build();
    expect(XlsxGridReader.listSheets(bytes), <String>['Data']);
    expect(XlsxGridReader.listSheets(bytes)[0], isNot(equals(1)));
    final String styles = OpcPackage.openBytes(
      bytes,
    ).getPart('/xl/styles.xml')!.readText();
    expect(styles, contains('yyyy-mm-dd'));
    expect(XlsxGridReader.parseCell('12').number, 12);
    expect(XlsxGridReader.excelSerialToDateTime(44927).year, 2023);
  });

  test('PdfReportBuilder writes image, header/footer, and table', () {
    final Uint8List pdf =
        (PdfReportBuilder(
                theme: OfficeDocumentTheme.light(),
                header: 'Header',
                footer: 'Footer',
                title: 'Report',
              )
              ..titleText('Title')
              ..body('Item A')
              ..table(<List<String>>[
                <String>['H1', 'H2'],
                <String>['1', '42'],
              ])
              ..kpiRow(<({String label, String value})>[
                (label: 'K', value: '42'),
              ])
              ..image(_png)
              ..barChart(const <ChartPoint>[
                ChartPoint(label: 'A', value: 3),
                ChartPoint(label: 'B', value: 1),
              ])
              ..pageBreak()
              ..heading('Next'))
            .build();
    expect(
      ascii.decode(pdf.take(8).toList(), allowInvalid: true),
      contains('%PDF'),
    );
    final String latin = ascii.decode(pdf, allowInvalid: true);
    expect(latin, contains('/Subtype /Image'));
    expect(latin, contains('/Count 2'));
    expect(latin, contains('(Report)'));
    final String content = _inflateFirstStream(pdf);
    expect(content, contains('Header'));
    expect(content, contains('1 / 2'));
    expect(content, contains('Title'));
  });
}

String _inflateFirstStream(Uint8List pdf) {
  final String asciiPdf = ascii.decode(pdf, allowInvalid: true);
  final int start = asciiPdf.indexOf('stream\n');
  final int end = asciiPdf.indexOf('\nendstream', start);
  final Uint8List zlib = pdf.sublist(start + 7, end);
  return utf8.decode(
    RawDeflate.inflate(zlib.sublist(2, zlib.length - 4)),
    allowMalformed: true,
  );
}
