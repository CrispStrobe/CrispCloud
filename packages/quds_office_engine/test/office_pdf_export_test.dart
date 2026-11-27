import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  final SfntFont? font = _tryFont();

  test('printing places a vector PDF on landscape paper with margins', () {
    final canvas = PdfCanvas(200, 300)..fillRect(0, 0, 200, 300, 'FFFFFF');
    final source = PdfFile.open(
      (PdfDocument()..addPage(
            PdfPage(
              width: 200,
              height: 300,
              content: canvas.toStream(),
              links: const [
                PdfLinkAnnot(
                  x: 0,
                  y: 0,
                  width: 20,
                  height: 20,
                  uri: 'https://example.com',
                ),
              ],
            ),
          ))
          .save(),
    );
    final output = PdfFile.open(
      source.placePagesOnPaper(
        [0],
        const PdfPaperPlacement(
          paper: (width: 300, height: 500),
          landscape: true,
          margin: 50,
          border: true,
        ),
      ),
    );
    final page = output.pageAt(0);
    expect((page.width, page.height), (500, 300));
    expect(output.displayList(0).error, isNull);
    final link = output.annotsOn(0).single;
    expect(link.uri, 'https://example.com');
    expect(link.rect.x, closeTo(183.3333, 0.001));
    expect(link.rect.y, closeTo(50, 0.001));
    expect(link.rect.width, closeTo(13.3333, 0.001));
    expect(source.pageAt(0).width, 200);
    final content = output.store.asArray(output.pageDict(0)['Contents'])!;
    final border = output.store.streamBytes(content.items.last)!;
    expect(
      String.fromCharCodes(border),
      contains('400.000000 200.000000 re S'),
    );
  });

  test(
    'sheet overrides repaginate while retaining the worksheet print area',
    () {
      final sheet =
          SmlWorksheet(
              name: 'Wide',
              sheetId: 1,
              pageSetup: SmlPageSetup(orientation: SmlPageOrientation.portrait),
            )
            ..printArea = const SmlRange(SmlCellRef(0, 0), SmlCellRef(8, 0))
            ..cellA1('A1').value = 'First'
            ..cellA1('I1').value = 'Last'
            ..cellA1('J1').value = 'Excluded';
      for (var col = 0; col < 10; col++) {
        sheet.setColumnWidth(col, 300);
      }
      final book = SmlWorkbook(sheets: [sheet]);
      final pdf = PdfFile.open(
        OfficePdfExport.workbook(
          book,
          options: const PdfSheetPrintOptions(
            useWorksheetPageSetup: true,
            paperOverride: (width: 612, height: 792),
            landscapeOverride: true,
            marginOverride: 18,
            fitOverride: true,
            fitWidthOnly: true,
            pageBorder: true,
          ),
        ),
      );
      expect(pdf.pageCount, 1);
      expect((pdf.pageAt(0).width, pdf.pageAt(0).height), (792, 612));
      final text = pdf.displayList(0).runs.map((run) => run.text).join(' ');
      expect(text, contains('First'));
      expect(text, contains('Last'));
      expect(text, isNot(contains('Excluded')));
      expect(sheet.pageSetup!.orientation, SmlPageOrientation.portrait);
    },
  );

  for (final bool cropped in <bool>[false, true]) {
    test('PPT PDF draws the authored picture border after crop=$cropped', () {
      final OfficeVisual picture = OfficeVisual(
        kind: OfficeVisualKind.picture,
        imageBytes: PngBytes.studioCard(width: 8, height: 8),
      );
      picture.picture
        ..cropLeft = cropped ? 0.25 : 0
        ..cropBottom = cropped ? 0.1 : 0
        ..borderColor = 'CC3300'
        ..borderWidth = 2.5;
      final PmlPresentation deck = PmlPresentation(
        slides: <PmlSlide>[
          PmlSlide(
            id: 256,
            shapes: <PmlShape>[
              PmlShape(
                id: 2,
                name: 'Bordered picture',
                transform: const PmlTransform(
                  x: 10 * 12700,
                  y: 20 * 12700,
                  cx: 100 * 12700,
                  cy: 50 * 12700,
                ),
                visual: picture,
              ),
            ],
          ),
        ],
      );
      final String content = _inflated(
        OfficePdfExport.presentation(deck),
      ).join();
      final int image = content.indexOf('/Im1 Do');
      final List<RegExpMatch> borders = RegExp(r'([0-9.]+) w\n')
          .allMatches(content)
          .where((match) => double.parse(match.group(1)!) == 2.5)
          .toList();
      expect(image, greaterThanOrEqualTo(0));
      expect(borders, hasLength(1));
      final int border = borders.single.start;
      expect(border, greaterThan(image));
      expect(content.substring(border), contains('0.800 0.200 0 RG'));
      expect(
        content.substring(border),
        matches(RegExp(r'10 20 100 50 re\s+S')),
      );
      if (cropped) {
        // The border follows restoration of the crop clip, so it outlines
        // the visible picture frame rather than the full expanded image.
        expect(
          RegExp(
            r'^Q$',
            multiLine: true,
          ).allMatches(content.substring(image, border)),
          hasLength(2),
        );
      }
      picture.picture.borderWidth = 0;
      final String borderless = _inflated(
        OfficePdfExport.presentation(deck),
      ).join();
      expect(borderless, contains('/Im1 Do'));
      expect(borderless, isNot(contains('0.800 0.200 0 RG')));
    });
  }

  test(
    'PPT PDF inherits the master background and honors a slide override',
    () {
      final PmlPresentation deck = PmlPresentation(
        slides: <PmlSlide>[
          PmlSlide(id: 256),
          PmlSlide(id: 257, background: '445566'),
        ],
      )..master.background = '112233';
      final List<String> streams = _inflated(
        OfficePdfExport.presentation(deck),
      );
      expect(streams.first, contains('0.067 0.133 0.200 rg'));
      expect(streams.last, contains('0.267 0.333 0.400 rg'));
      expect(streams.last, isNot(contains('0.067 0.133 0.200 rg')));
    },
  );

  test(
    'PPT rich-text PDF reflects scalar edits and later text replacement',
    () {
      final PmlShape shape = PmlShape(
        id: 2,
        name: 'Imported text',
        text: 'Original',
        fontSizePt: 18,
        textColor: '112233',
        fillColor: '',
        transform: const PmlTransform(cx: 5080000, cy: 1270000),
        textSource: const PmlTextSource(
          xml: '',
          text: 'Original',
          fontSizePt: 18,
          textColor: '112233',
          textAlign: PmlTextAlign.left,
          rightToLeft: null,
        ),
        richText: <PmlTextParagraph>[
          PmlTextParagraph(
            runs: <PmlTextRun>[
              PmlTextRun(text: 'Original', fontSizePt: 18, color: '112233'),
            ],
          ),
        ],
      );
      final PmlPresentation deck = PmlPresentation(
        slides: <PmlSlide>[
          PmlSlide(id: 256, shapes: <PmlShape>[shape]),
        ],
      );
      shape
        ..fontSizePt = 30
        ..textColor = 'CC3300';
      final String edited = _inflated(
        OfficePdfExport.presentation(deck),
      ).join();
      expect(edited, contains('/F2 30 Tf'));
      expect(edited, contains('0.800 0.200 0 rg'));
      expect(edited, isNot(contains('/F2 18 Tf')));
      expect(shape.richText.single.runs.single.fontSizePt, 18);
      expect(shape.richText.single.runs.single.color, '112233');

      shape.text = 'Replacement';
      final String replaced = _inflated(
        OfficePdfExport.presentation(deck),
      ).join();
      expect(replaced, contains('(Replacement) Tj'));
      expect(replaced, isNot(contains('(Original) Tj')));
    },
  );

  test('PPT rich-text PDF uses paragraph font defaults for unstyled runs', () {
    final PmlPresentation deck = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          shapes: <PmlShape>[
            PmlShape(
              id: 2,
              name: 'Paragraph default',
              text: 'Default size',
              fillColor: '',
              transform: const PmlTransform(cx: 5080000, cy: 1270000),
              richText: <PmlTextParagraph>[
                PmlTextParagraph(
                  defaultFontSizePt: 11,
                  runs: <PmlTextRun>[PmlTextRun(text: 'Default size')],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final String stream = _inflated(OfficePdfExport.presentation(deck)).join();
    expect(stream, contains('/F2 11 Tf'));
  });

  test('PPT heading fit scales explicit and inherited run sizes once', () {
    final PmlShape shape = PmlShape(
      id: 2,
      name: 'Heading',
      text: 'An unusually long heading',
      fontSizePt: 20,
      fillColor: '',
      transform: const PmlTransform(cx: 60 * 12700, cy: 30 * 12700),
      richText: <PmlTextParagraph>[
        PmlTextParagraph(
          defaultFontSizePt: 20,
          runs: <PmlTextRun>[
            PmlTextRun(text: 'An unusually '),
            PmlTextRun(text: 'long heading', fontSizePt: 20),
          ],
        ),
      ],
    );
    final PmlPresentation deck = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(id: 256, shapes: <PmlShape>[shape]),
      ],
    );
    final String stream = _inflated(OfficePdfExport.presentation(deck)).join();
    final Set<double> sizes = RegExp(
      r'/\S+ ([0-9.]+) Tf',
    ).allMatches(stream).map((match) => double.parse(match.group(1)!)).toSet();
    expect(sizes, <double>{15});
    expect(shape.richText.single.runs.first.fontSizePt, 0);
    expect(shape.richText.single.runs.last.fontSizePt, 20);
  });

  test('PPT numeric-only text remains in authored left-to-right order', () {
    const String text = '1 2 3 4';
    final PmlPresentation deck = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          shapes: <PmlShape>[
            PmlShape(
              id: 2,
              name: 'Numbers',
              text: text,
              fillColor: '',
              transform: const PmlTransform(cx: 400 * 12700, cy: 100 * 12700),
              richText: <PmlTextParagraph>[
                PmlTextParagraph(
                  runs: <PmlTextRun>[PmlTextRun(text: text, fontSizePt: 20)],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final String stream = _inflated(OfficePdfExport.presentation(deck)).join();
    final List<RegExpMatch> glyphs = RegExp(
      r'1 0 0 -1 ([0-9.]+) [0-9.]+ Tm\n\(([^()]*)\) Tj',
    ).allMatches(stream).toList();
    expect(glyphs.map((match) => match.group(2)!).join(), text);
    final List<double> positions = glyphs
        .map((match) => double.parse(match.group(1)!))
        .toList();
    expect(positions, orderedEquals(<double>[...positions]..sort()));
  });

  test(
    'PPT autofit measures and paints numeric and blank line advances equally',
    () {
      final SfntFont exactFont = SfntFont.parse(
        File(
          '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
        ).readAsBytesSync(),
      );
      final double natural =
          10 *
          (exactFont.ascender - exactFont.descender + exactFont.lineGap) /
          exactFont.unitsPerEm;
      final double advance = natural * 1.3; // 150% paragraph leading minus 20%.
      final PmlShape shape = PmlShape(
        id: 2,
        name: 'Fitted',
        text: '11\n22\n\n33',
        fontSizePt: 20,
        textScale: 0.5,
        lineSpacingReduction: 0.2,
        textAnchor: PmlTextAnchor.center,
        fillColor: '',
        rightToLeft: false,
        transform: const PmlTransform(cx: 200 * 12700, cy: 200 * 12700),
        richText: [
          PmlTextParagraph(
            lineSpacing: 1.5,
            runs: [PmlTextRun(text: '11\n22', fontSizePt: 20)],
          ),
          PmlTextParagraph(lineSpacing: 1.5, defaultFontSizePt: 20),
          PmlTextParagraph(
            lineSpacing: 1.5,
            runs: [PmlTextRun(text: '33', fontSizePt: 20)],
          ),
        ],
      );
      final List<double> baselines = _autofitBaselines(shape, exactFont);
      final double first = (200 - 4 * advance) / 2 + 10;
      expect(baselines, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(baselines[i], closeTo(first + [0, 1, 3][i] * advance, 0.01));
      }
    },
  );

  test(
    'PPT autofit uses the same advance inside wrapped text and between paragraphs',
    () {
      final SfntFont exactFont = SfntFont.parse(
        File(
          '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
        ).readAsBytesSync(),
      );
      final double advance =
          10 *
          (exactFont.ascender - exactFont.descender + exactFont.lineGap) /
          exactFont.unitsPerEm *
          0.8;
      final PmlShape shape = PmlShape(
        id: 2,
        name: 'Fitted',
        text: 'Alpha Beta Gamma\nEnd',
        fontSizePt: 20,
        textScale: 0.5,
        lineSpacingReduction: 0.2,
        fillColor: '',
        rightToLeft: false,
        transform: const PmlTransform(cx: 45 * 12700, cy: 200 * 12700),
        richText: [
          PmlTextParagraph(
            runs: [PmlTextRun(text: 'Alpha Beta Gamma', fontSizePt: 20)],
          ),
          PmlTextParagraph(runs: [PmlTextRun(text: 'End', fontSizePt: 20)]),
        ],
      );
      final List<double> baselines = _autofitBaselines(shape, exactFont);
      expect(baselines, hasLength(4));
      for (var i = 0; i < baselines.length; i++) {
        expect(baselines[i], closeTo(13.6 + i * advance, 0.01));
      }
    },
  );

  test(
    'PPT autofit mixed runs honor metrics while fixed leading ignores reduction',
    () {
      final SfntFont exactFont = SfntFont.parse(
        File(
          '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
        ).readAsBytesSync(),
      );
      final PmlShape shape = PmlShape(
        id: 2,
        name: 'Fitted',
        text: '11\n22',
        fontSizePt: 20,
        textScale: 0.5,
        lineSpacingReduction: 0.5,
        textAnchor: PmlTextAnchor.center,
        fillColor: '',
        rightToLeft: false,
        transform: const PmlTransform(cx: 200 * 12700, cy: 200 * 12700),
        richText: [
          PmlTextParagraph(
            lineSpacingPt: 30,
            runs: [
              PmlTextRun(text: '11\n', fontSizePt: 20),
              PmlTextRun(text: '22', fontSizePt: 40),
            ],
          ),
        ],
      );
      final List<double> baselines = _autofitBaselines(shape, exactFont);
      expect(baselines, hasLength(2));
      expect(baselines[0], closeTo(80, 0.01));
      expect(baselines[1], closeTo(120, 0.01));
      shape.lineSpacingReduction = 0;
      expect(_autofitBaselines(shape, exactFont), baselines);
    },
  );

  test('PPT resolved empty decorations do not revive the global master', () {
    final PmlShape master = PmlShape(
      id: 2,
      name: 'Global decoration',
      text: 'Global marker',
      fillColor: 'CC3300',
      hyperlinkUrl: 'https://example.org/global',
      transform: const PmlTransform(cx: 100 * 12700, cy: 100 * 12700),
    );
    final PmlPresentation deck = PmlPresentation(
      slides: <PmlSlide>[PmlSlide(id: 256, backgroundShapes: <PmlShape>[])],
      master: PmlMaster(
        name: 'Global',
        background: '112233',
        shapes: <PmlShape>[master],
      ),
    );
    for (final int perPage in <int>[1, 2]) {
      final Uint8List resolved = OfficePdfExport.presentation(
        deck,
        slidesPerPage: perPage,
      );
      final String stream = _inflated(resolved).join();
      expect(stream, contains('0.067 0.133 0.200 rg'));
      expect(stream, isNot(contains('(Global) Tj')));
      expect(stream, isNot(contains('(marker) Tj')));
      expect(_ascii(resolved), isNot(contains('https://example.org/global')));
    }
    deck.slides[0] = PmlSlide(id: 256);
    final Uint8List authored = OfficePdfExport.presentation(deck);
    expect(_inflated(authored).join(), contains('(Global) Tj'));
    expect(_inflated(authored).join(), contains('(marker) Tj'));
    expect(_ascii(authored), contains('https://example.org/global'));
    deck.slides.single.showMasterShapes = false;
    final Uint8List suppressed = OfficePdfExport.presentation(deck);
    expect(_inflated(suppressed).join(), isNot(contains('(Global) Tj')));
    expect(_ascii(suppressed), isNot(contains('https://example.org/global')));
  });

  test('Word PDF keeps pages, headers, tables, lists, and pictures', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          header: <WmlParagraph>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Quds header')]),
          ],
          footer: <WmlParagraph>[
            WmlParagraph(
              properties: WmlParagraphProps(
                justification: WmlJustification.center,
                pageNumberField: true,
              ),
            ),
          ],
          blocks: <WmlBlock>[
            WmlParagraph(
              properties: WmlParagraphProps(listLabel: '1. '),
              inlines: <WmlInline>[
                WmlRun(
                  text: 'Phase one',
                  properties: WmlRunProps(
                    bold: true,
                    underline: WmlUnderline.double,
                    highlight: 'yellow',
                    strike: true,
                  ),
                ),
              ],
            ),
            WmlTable(
              grid: <double>[160, 160],
              rows: <WmlTableRow>[
                WmlTableRow(
                  cells: <WmlTableCell>[
                    WmlTableCell(
                      fillColor: '2B579A',
                      blocks: <WmlBlock>[
                        WmlParagraph(
                          inlines: <WmlInline>[WmlRun(text: 'Alpha')],
                        ),
                      ],
                    ),
                    WmlTableCell(
                      blocks: <WmlBlock>[
                        WmlParagraph(
                          inlines: <WmlInline>[WmlRun(text: 'Beta')],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                imageBytes: PngBytes.studioCard(width: 48, height: 28),
                width: 160,
                height: 80,
              ),
            ),
            WmlParagraph(
              properties: WmlParagraphProps(pageBreakBefore: true),
              inlines: <WmlInline>[WmlRun(text: 'Second page')],
            ),
          ],
        ),
      ],
    );

    final Uint8List pdf = OfficePdfExport.word(
      doc,
      font: font,
      title: 'Word PDF',
    );
    expect(_header(pdf), '%PDF-1.7');
    expect(_pageCount(pdf), 2);
    expect(_ascii(pdf).contains('/Im1'), isTrue);
    expect(_inflated(pdf).join(), contains('re'));
  });

  test('Excel PDF evaluates formulas and paginates every sheet', () {
    final SmlWorkbook book = SmlWorkbook(
      sheets: <SmlWorksheet>[
        SmlWorksheet(name: 'Data', sheetId: 1),
        SmlWorksheet(name: 'Calc', sheetId: 2),
      ],
      styles: SmlStyleSheet(cellXfsNumFmt: <int>[0, 2]),
    );
    book.sheets[0].cellA1('A1').value = 10;
    book.sheets[0].cellA1('A2').value = 20;
    book.sheets[0].cellA1('A3').value = 30;
    book.sheets[1].cellA1('A1').formula = '=SUM(Data!A1:A3)';
    book.sheets[1].cellA1('B1').value = 12.3;
    book.sheets[1].cellA1('B1').styleIndex = 1;
    book.sheets[1].drawings.add(
      SmlDrawing(
        visual: OfficeVisual(
          kind: OfficeVisualKind.chartColumn,
          title: 'Mix',
          points: OfficeVisual.sampleSeries(),
        ),
        col: 3,
        row: 1,
      ),
    );

    expect(
      FormulaEvaluator.evaluateCell(
        book,
        book.sheets[1],
        book.sheets[1].cellA1('A1'),
      ),
      60,
    );
    expect(book.styles!.format(12.3, 1), '12.30');

    final Uint8List pdf = OfficePdfExport.workbook(
      book,
      font: font,
      title: 'Sheet PDF',
    );
    expect(_header(pdf), '%PDF-1.7');
    expect(_pageCount(pdf), 2);
    if (font == null) {
      final String body = _inflated(pdf).join();
      expect(body, contains('Data'));
      expect(body, contains('60'));
      expect(body, contains('12.30'));
    } else {
      expect(_ascii(pdf), contains('/CIDFont'));
    }

    final Uint8List landscape = OfficePdfExport.workbook(
      book,
      options: PdfSheetPrintOptions.a4Landscape(),
    );
    expect(_ascii(landscape), contains('/MediaBox [0 0 841.890 595.280]'));
  });

  test('worksheet charts at either printable edge are clipped safely', () {
    final sheet = SmlWorksheet(name: 'Charts', sheetId: 1)
      ..printArea = const SmlRange(SmlCellRef(0, 0), SmlCellRef(1, 1))
      ..setColumnWidth(0, 164)
      ..setColumnWidth(1, 40)
      ..setRowHeight(0, 140)
      ..setRowHeight(1, 24);
    for (final (col, row, title) in [
      (1, 0, 'Right edge'),
      (0, 1, 'Bottom edge'),
    ]) {
      sheet.drawings.add(
        SmlDrawing(
          visual: OfficeVisual(
            kind: OfficeVisualKind.chartColumn,
            title: title,
            points: OfficeVisual.sampleSeries(),
          ),
          col: col,
          row: row,
        ),
      );
    }

    final bytes = OfficePdfExport.workbook(
      SmlWorkbook(sheets: [sheet]),
      options: const PdfSheetPrintOptions(
        pageWidth: 200,
        pageHeight: 200,
        margin: 20,
        showGridlines: false,
        showHeadings: false,
      ),
    );
    expect(_pageCount(bytes), 1);
    final body = _inflated(bytes).join();
    expect(body, contains('Right edge'));
    expect(body, contains('Bottom edge'));
    expect(RegExp(r'W n').allMatches(body), hasLength(2));
    expect(PdfFile.open(bytes).displayList(0).error, isNull);
  });

  test('automatic fit includes visible unwrapped text past the last cell', () {
    final sheet =
        SmlWorksheet(
            name: 'Notes',
            sheetId: 1,
            pageSetup: SmlPageSetup(
              paperWidthIn: 2.5,
              paperHeightIn: 2,
              marginLeftIn: 0,
              marginRightIn: 0,
              marginTopIn: 0,
              marginBottomIn: 0,
              fitToPage: true,
              fitToHeight: 0,
            ),
          )
          ..setRowHeight(0, 110)
          ..setRowHeight(1, 110)
          ..cellA1('A2').value = 'Second row';
    final note = sheet.cellA1('A1')
      ..value = 'A long unwrapped worksheet label with a visible ending';
    final book = SmlWorkbook(sheets: [sheet]);
    Uint8List printSheet() => OfficePrint.workbook(book);

    final overflow = printSheet();
    expect(_pageCount(overflow), 1);
    expect(_inflated(overflow).join(), contains('a visible ending'));

    note.wrapText = true;
    expect(_pageCount(printSheet()), 2);
    note.wrapText = false;
    sheet.cellA1('B1').value = 'Stop';
    expect(_pageCount(printSheet()), 2);
    sheet.cellA1('B1').value = null;
    sheet.printArea = SmlRange.parse('A1:A2');
    expect(_pageCount(printSheet()), 2);
  });

  test('fit to page tolerates floating-point width accumulation', () {
    final sheet = SmlWorksheet(
      name: 'Exact width',
      sheetId: 1,
      printArea: SmlRange.parse('A1:F1'),
    );
    for (var col = 0; col < 6; col++) {
      sheet.setColumnWidth(col, 40);
    }
    sheet.cellA1('F1').value = 'Last column';
    final bytes = OfficePdfExport.workbook(
      SmlWorkbook(sheets: [sheet]),
      options: const PdfSheetPrintOptions(
        pageWidth: 100,
        pageHeight: 200,
        margin: 0,
        showHeadings: false,
        fitToPage: true,
      ),
    );
    expect(_pageCount(bytes), 1);
    expect(_inflated(bytes).join(), contains('Last column'));
  });

  test('a native two-cell drawing continues across both page breaks', () {
    final sheet =
        SmlWorksheet(name: 'Drawing', sheetId: 1, pageSetup: SmlPageSetup())
          ..setColumnWidth(0, 120)
          ..setRowHeight(0, 120)
          ..importManualPageBreak(1, rows: false)
          ..importManualPageBreak(1, rows: true);
    sheet.drawings.add(
      SmlDrawing(
        col: 0,
        row: 0,
        offsetX: 16,
        offsetY: 20,
        importedEndMarker: (col: 1, row: 1, colEmu: 508000, rowEmu: 508000),
        visual: OfficeVisual(
          kind: OfficeVisualKind.chartColumn,
          title: 'Across pages',
          points: OfficeVisual.sampleSeries(),
        ),
      ),
    );

    final bytes = OfficePrint.workbook(SmlWorkbook(sheets: [sheet]));
    final pdf = PdfFile.open(bytes);
    expect(pdf.pageCount, 4);
    for (var index = 0; index < pdf.pageCount; index++) {
      final content = pdf.store.streamBytes(pdf.pageDict(index)['Contents'])!;
      expect(String.fromCharCodes(content), contains('W n'));
      expect(pdf.displayList(index).error, isNull);
    }
  });

  test('workbook print respects imported landscape paper and fit to page', () {
    final sheet = SmlWorksheet(
      name: 'Worksheet',
      sheetId: 1,
      pageSetup: SmlPageSetup(
        orientation: SmlPageOrientation.landscape,
        paperSize: 8,
        paperWidthIn: 11.69,
        paperHeightIn: 16.54,
        fitToPage: true,
      ),
    );
    sheet.cellA1('A1').value = 'Title';
    sheet.cellA1('Q45').value = 'End';
    final blank = SmlWorksheet(name: 'Blank', sheetId: 2);
    final book = SmlWorkbook(sheets: [sheet, blank]);

    final pdf = OfficePrint.workbook(book);

    expect(_ascii(pdf), contains('/MediaBox [0 0 1190.880 841.680]'));
    expect(_pageCount(pdf), 1);
    expect(_inflated(pdf).join(), contains('End'));
  });

  test(
    'workbook print projects native columns using the supplied Normal face',
    () {
      final book = SheetDeserializer().readBytes(
        File(
          'test/fixtures/fidelity/sheet-normal-font-native.xlsx',
        ).readAsBytesSync(),
      );
      final sheet = book.firstSheet;
      sheet
        ..printArea = SmlRange.parse('A1:B1')
        ..pageSetup = SmlPageSetup(
          paperWidthIn: 2.5,
          marginLeftIn: 0,
          marginRightIn: 0,
        );
      sheet.importColumnWidth(0, 10);
      sheet.importColumnWidth(1, 10);
      final normal = SfntFont.parse(
        File(
          '../quds_office_editor/fonts/LiberationMono-Regular.ttf',
        ).readAsBytesSync(),
      );

      expect(_pageCount(OfficePrint.workbook(book)), 1);
      expect(_pageCount(OfficePrint.workbook(book, font: normal)), 2);
      expect(book.columnMetrics, isNull);
      expect(sheet.columnWidth(0), 70);
      expect(sheet.exportColumnWidth(0), 10);

      sheet.setColumnWidth(1, 40);
      expect(_pageCount(OfficePrint.workbook(book, font: normal)), 1);
      expect(sheet.columnWidth(1), 40);
    },
  );

  test('XLSX print uses the Normal digit rounded in points', () {
    final source = OpcPackage.openBytes(
      File(
        'test/fixtures/fidelity/sheet-normal-font-native.xlsx',
      ).readAsBytesSync(),
    );
    final styles = source.getPart('/xl/styles.xml')!;
    styles.writeText(
      styles.readText().replaceFirst(
        '<sz val="24"/><name val="Liberation Mono"/>',
        '<sz val="10"/><name val="Liberation Sans"/>',
      ),
    );
    final book = SheetDeserializer().read(source);
    final sheet = book.firstSheet;
    sheet
      ..printArea = SmlRange.parse('A1:B1')
      ..pageSetup = SmlPageSetup(
        paperWidthIn: 3.2,
        marginLeftIn: 0,
        marginRightIn: 0,
      );
    sheet.importColumnWidth(0, 20);
    sheet.importColumnWidth(1, 20);
    final normal = SfntFont.parse(
      File(
        '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
      ).readAsBytesSync(),
    );

    // At 72 dpi the digit rounds to 6 pt and the two columns need 240 pt.
    // Rounding first at 96 dpi would incorrectly fit them on this 230.4 pt page.
    expect(_pageCount(OfficePrint.workbook(book, font: normal)), 2);
    expect(sheet.columnWidth(0), 140);
    sheet.setColumnWidth(1, 100);
    expect(_pageCount(OfficePrint.workbook(book, font: normal)), 1);
  });

  test('XLSX manual page breaks survive saving and guide print pagination', () {
    final sheet = SmlWorksheet(
      name: 'Breaks',
      sheetId: 1,
      pageSetup: SmlPageSetup(),
      printArea: SmlRange.parse('B2:E6'),
    );
    sheet
      ..cellA1('B2').value = 'TopLeft'
      ..cellA1('E2').value = 'TopRight'
      ..cellA1('B6').value = 'BottomLeft'
      ..cellA1('E6').value = 'BottomRight';
    final book = SmlWorkbook(sheets: [sheet]);
    final package = OpcPackage.openBytes(SheetSerializer().writeBytes(book));
    final part = package.getPart('/xl/worksheets/sheet1.xml')!;
    part.writeText(
      part.readText().replaceFirst('</worksheet>', '''
<rowBreaks count="3" manualBreakCount="2">
  <brk id="1" max="4" man="1"/>
  <brk id="4" max="4" man="true"/>
  <brk id="5" max="4"/>
</rowBreaks>
<colBreaks count="1" manualBreakCount="1">
  <brk id="3" min="1" max="5" man="1"/>
</colBreaks></worksheet>'''),
    );
    final imported = SheetDeserializer().readBytes(package.save());
    final reopened = SheetDeserializer().readBytes(
      SheetSerializer().writeBytes(imported),
    );

    final pdf = PdfFile.open(OfficePrint.workbook(reopened));
    expect(pdf.pageCount, 4);
    for (final (index, label) in [
      'TopLeft',
      'BottomLeft',
      'TopRight',
      'BottomRight',
    ].indexed) {
      expect(pdf.displayList(index).runs.map((run) => run.text), [label]);
    }
    final fit = OfficePrint.workbook(
      reopened,
      options: const PdfSheetPrintOptions(
        useWorksheetPageSetup: true,
        fitOverride: true,
      ),
    );
    expect(_pageCount(fit), 1);
  });

  test('sheet PDF paints a merged cell across a horizontal page boundary', () {
    final sheet = SmlWorksheet(
      name: 'Merged',
      sheetId: 1,
      pageSetup: SmlPageSetup(
        paperWidthIn: 1.5,
        marginLeftIn: 10 / 72,
        marginRightIn: 10 / 72,
      ),
    );
    sheet
      ..setColumnWidth(0, 100)
      ..setColumnWidth(1, 100)
      ..cellA1('A1').value = 'Merged label across pages'
      ..mergeAndCenter(SmlRange.parse('A1:B1'));
    final bytes = OfficePrint.workbook(SmlWorkbook(sheets: [sheet]));
    expect(_pageCount(bytes), 2);

    final pages = _inflated(
      bytes,
    ).where((stream) => stream.contains('Merged label across pages'));
    expect(pages, hasLength(2));
    for (final page in pages) {
      expect(
        page,
        contains(RegExp(r'10(?:\.0+)? [\d.]+ 75(?:\.0+)? [\d.]+ re\s+W n')),
      );
    }
  });

  test('workbook print respects the authored order of page bands', () {
    final setup = SmlPageSetup(paperWidthIn: 3, paperHeightIn: 3);
    final sheet = SmlWorksheet(
      name: 'Page order',
      sheetId: 1,
      pageSetup: setup,
    );
    sheet.columnWidths
      ..[0] = 110
      ..[1] = 110;
    sheet.rowHeights
      ..[0] = 110
      ..[1] = 110;
    sheet.cellA1('A1').value = 'TopLeft';
    sheet.cellA1('B1').value = 'TopRight';
    sheet.cellA1('A2').value = 'BottomLeft';
    sheet.cellA1('B2').value = 'BottomRight';
    final book = SmlWorkbook(sheets: [sheet]);

    List<String> labelsInPageOrder() {
      final bytes = OfficePrint.workbook(book);
      expect(_pageCount(bytes), 4);
      return RegExp(r'TopLeft|TopRight|BottomLeft|BottomRight')
          .allMatches(_inflated(bytes).join())
          .map((match) => match.group(0)!)
          .toList();
    }

    expect(labelsInPageOrder(), [
      'TopLeft',
      'BottomLeft',
      'TopRight',
      'BottomRight',
    ]);
    setup.printAcrossThenDown = true;
    expect(labelsInPageOrder(), [
      'TopLeft',
      'TopRight',
      'BottomLeft',
      'BottomRight',
    ]);
  });

  test('PowerPoint PDF emits one page per slide including rotation', () {
    final PmlPresentation deck = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          shapes: <PmlShape>[
            PmlShape(
              id: 2,
              name: 'Title',
              text: 'مرحبا Office',
              fillColor: '2B579A',
              transform: const PmlTransform(
                x: 200000,
                y: 200000,
                cx: 4000000,
                cy: 800000,
                rot: 30 * 60000,
              ),
            ),
            PmlShape(
              id: 3,
              name: 'Chart',
              visual: OfficeVisual(
                kind: OfficeVisualKind.chartPie,
                title: 'Share',
                points: OfficeVisual.sampleSeries(),
              ),
              transform: const PmlTransform(
                x: 800000,
                y: 1600000,
                cx: 5000000,
                cy: 2800000,
              ),
            ),
          ],
          notes: 'Speaker notes for slide one',
        ),
        PmlSlide(
          id: 257,
          shapes: <PmlShape>[
            PmlShape(
              id: 4,
              name: 'Oval',
              preset: PmlShapePreset.ellipse,
              text: 'Round',
              fillColor: '217346',
            ),
          ],
        ),
      ],
    );

    final Uint8List slides = OfficePdfExport.presentation(
      deck,
      font: font,
      title: 'Deck PDF',
    );
    expect(_header(slides), '%PDF-1.7');
    expect(_pageCount(slides), 2);
    final String slideStream = _inflated(slides).join();
    expect(slideStream, contains('cm'));
    expect(slideStream, contains('0 -1'));
    if (font != null) {
      for (final Match m in RegExp(
        r'\[<([0-9a-fA-F]+)>\] TJ',
      ).allMatches(slideStream)) {
        expect(
          int.parse(m.group(1)!, radix: 16),
          lessThan(512),
          reason: 'PDF must address the subset font, not source glyph ids',
        );
      }
    }

    final Uint8List notes = OfficePdfExport.presentation(
      deck,
      mode: PdfSlideExportMode.notesPages,
    );
    expect(_pageCount(notes), 2);
    expect(_ascii(notes), contains('595.28'));
    if (font == null) {
      expect(_inflated(notes).join(), contains('Speaker notes'));
    }

    final Uint8List paired = OfficePdfExport.presentation(
      deck,
      slidesPerPage: 2,
    );
    expect(_pageCount(paired), 1);
    expect(_ascii(paired), contains('595.28'));
  });

  test(
    'PPT PDF uses changed master paper and preserves explicit slide fills',
    () {
      final PmlPresentation deck = PmlPresentation(
        slides: <PmlSlide>[
          PmlSlide(id: 256),
          PmlSlide(id: 257, background: '0000FF'),
          PmlSlide(id: 258)
            ..setInheritedBackground('00FFFF', masterBackground: 'FF0000'),
        ],
      );
      for (final int perPage in <int>[1, 2]) {
        deck.master.background = 'FF0000';
        final String red = _inflated(
          OfficePdfExport.presentation(deck, slidesPerPage: perPage),
        ).join();
        expect(red, contains('1 0 0 rg'));
        expect(red, contains('0 0 1 rg'));
        expect(red, contains('0 1 1 rg'));
        deck.master.background = '00FF00';
        final String green = _inflated(
          OfficePdfExport.presentation(deck, slidesPerPage: perPage),
        ).join();
        expect(green, contains('0 1 0 rg'));
        expect(green, contains('0 0 1 rg'));
        expect(green, isNot(contains('1 0 0 rg')));
        expect(green, isNot(contains('0 1 1 rg')));
      }
    },
  );

  test('PPT PDF applies scalar font edits to imported rich runs', () {
    final PmlShape shape = PmlShape(
      id: 2,
      name: 'Rich',
      text: 'Edited font',
      fontSizePt: 18,
      textColor: '000000',
      fillColor: '',
      transform: const PmlTransform(cx: 4572000, cy: 1270000),
      textSource: const PmlTextSource(
        xml: '',
        text: 'Edited font',
        fontSizePt: 18,
        textColor: '000000',
        textAlign: PmlTextAlign.left,
        rightToLeft: null,
      ),
      richText: <PmlTextParagraph>[
        PmlTextParagraph(
          runs: <PmlTextRun>[
            PmlTextRun(text: 'Edited font', fontSizePt: 18, color: '000000'),
          ],
        ),
      ],
    );
    final PmlPresentation deck = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(id: 256, shapes: <PmlShape>[shape]),
      ],
    );
    final String before = _inflated(OfficePdfExport.presentation(deck)).join();
    expect(before, contains(RegExp(r'/\S+ 18 Tf')));
    shape
      ..fontSizePt = 32
      ..textColor = 'FF0000';
    final String after = _inflated(OfficePdfExport.presentation(deck)).join();
    expect(after, contains(RegExp(r'/\S+ 32 Tf')));
    expect(after, isNot(contains(RegExp(r'/\S+ 18 Tf'))));
    expect(after, contains('1 0 0 rg'));
    expect(shape.richText.single.runs.single.fontSizePt, 18);
  });

  test('fromBytes dispatches Word, Excel, and PowerPoint packages', () {
    final Uint8List docx = WordSerializer().writeBytes(
      WmlDocument.empty(text: 'Export me'),
    );
    final SmlWorkbook book = SmlWorkbook();
    book.firstSheet.cellA1('A1').value = 7;
    final Uint8List xlsx = SheetSerializer().writeBytes(book);
    final Uint8List pptx = SlideSerializer().writeBytes(
      PmlPresentation(
        slides: <PmlSlide>[
          PmlSlide(
            id: 256,
            shapes: <PmlShape>[PmlShape(id: 2, name: 'T', text: 'Deck')],
          ),
        ],
      ),
    );

    expect(_header(OfficePdfExport.fromBytes(docx)), '%PDF-1.7');
    expect(_header(OfficePdfExport.fromBytes(xlsx)), '%PDF-1.7');
    expect(_header(PdfDocument.fromPptx(pptx)), '%PDF-1.7');
    expect(_pageCount(PdfDocument.fromWorkbook(book)), 1);
  });

  test('transparent PNG pictures emit a DeviceGray SMask', () {
    final Uint8List png = PngBytes.rgba(
      width: 8,
      height: 6,
      plot: (int x, int y, List<int> rgba) {
        rgba[0] = 255;
        rgba[1] = 255;
        rgba[2] = 255;
        rgba[3] = (x < 3 || y < 2) ? 0 : 255;
      },
    );
    final PdfRaster? raster = PdfImageCodec.decode(png);
    expect(raster, isNotNull);
    expect(raster!.alpha, isNotNull);
    expect(raster.alpha!.first, 0);
    expect(raster.alpha!.last, 255);

    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                imageBytes: png,
                width: 80,
                height: 60,
              ),
            ),
          ],
        ),
      ],
    );
    final Uint8List pdf = OfficePdfExport.word(doc, font: font, title: 'Alpha');
    final String ascii = _ascii(pdf);
    expect(ascii, contains('/SMask'));
    expect(ascii, contains('/ColorSpace /DeviceGray'));
  });

  test('keeps a distinct image XObject for each picture', () {
    final Uint8List red = PngBytes.rgb(
      width: 24,
      height: 16,
      plot: (int x, int y, List<int> rgb) {
        rgb[0] = 200;
        rgb[1] = 10;
        rgb[2] = 10;
      },
    );
    final Uint8List blue = PngBytes.rgb(
      width: 32,
      height: 20,
      plot: (int x, int y, List<int> rgb) {
        rgb[0] = 10;
        rgb[1] = 20;
        rgb[2] = 210;
      },
    );
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                imageBytes: red,
                width: 120,
                height: 80,
              ),
            ),
            WmlParagraph(
              properties: WmlParagraphProps(pageBreakBefore: true),
              inlines: <WmlInline>[WmlRun(text: 'Next')],
            ),
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                imageBytes: blue,
                width: 140,
                height: 90,
              ),
            ),
          ],
        ),
      ],
    );
    final Uint8List pdf = OfficePdfExport.word(doc, font: font, title: 'Pics');
    final String ascii = _ascii(pdf);
    expect(ascii, contains('/Im1'));
    expect(ascii, contains('/Im2'));
    expect(ascii, contains('/Width 24'));
    expect(ascii, contains('/Width 32'));
    final String body = _inflated(pdf).join();
    expect(body, contains('/Im1 Do'));
    expect(body, contains('/Im2 Do'));
  });

  test('Excel PDF uses Helvetica for Latin when the CID face lacks it', () {
    final SfntFont? noto = _tryNoto();
    if (noto == null) {
      return;
    }
    final SmlWorkbook book = SmlWorkbook();
    book.firstSheet.cellA1('A1').value = 'عنوان';
    book.firstSheet.cellA1('B1').value = 4200;
    final Uint8List pdf = OfficePdfExport.workbook(
      book,
      font: noto,
      title: 'Mixed',
    );
    expect(_ascii(pdf), contains('/Length1'));
    final String body = _inflated(pdf).join();
    expect(body, contains('(A)'));
    expect(body, contains('(B)'));
    expect(RegExp(r'\[<[0-9a-fA-F]+>\] TJ').hasMatch(body), isTrue);
    expect(body.contains('[<0000>] TJ'), isFalse);
  });

  test('Word PDF writes TOC and web link annotations', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlToc(title: 'Contents', minLevel: 1, maxLevel: 2),
            WmlParagraph(
              inlines: <WmlInline>[
                WordLink.linkedRun(
                  'Site',
                  const WmlHyperlink(url: 'https://example.com/docs'),
                ),
              ],
            ),
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Intro heading')])
              ..properties.headingLevel = 1
              ..properties.styleId = 'Heading1'
              ..properties.bookmarkName = '_Heading1_Intro',
            WmlParagraph(
              properties: WmlParagraphProps(pageBreakBefore: true),
              inlines: <WmlInline>[WmlRun(text: 'After the break')],
            ),
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Second heading')])
              ..properties.headingLevel = 2
              ..properties.styleId = 'Heading2'
              ..properties.bookmarkName = '_Heading2_Second',
          ],
        ),
      ],
    );
    WordToc.applyHeading(doc.paragraphs.elementAt(2), 1);
    WordToc.applyHeading(doc.paragraphs.elementAt(4), 2);
    WordToc.refreshAll(doc);
    final Uint8List pdf = OfficePdfExport.word(doc, font: font, title: 'Links');
    final String ascii = _ascii(pdf);
    expect(ascii, contains('/Annot'));
    expect(ascii, contains('/GoTo'));
    expect(ascii, contains('/URI'));
    expect(ascii, contains('https://example.com/docs'));
    expect(ascii, contains('/Link'));
    expect(ascii, contains('/Outlines'));

    final Uint8List slice = OfficePdfExport.word(
      doc,
      font: font,
      title: 'Slice',
      pageFrom: 2,
      pageTo: 2,
    );
    expect(_pageCount(slice), 1);
  });

  test('Excel PDF honors column widths, merges, and print area', () {
    final SmlWorkbook book = SmlWorkbook();
    final SmlWorksheet sheet = book.firstSheet;
    sheet.setColumnWidth(0, 120);
    sheet.setColumnWidth(1, 40);
    sheet.setRowHeight(0, 40);
    sheet.cellA1('A1').value = 'Wide';
    sheet.cellA1('B1').value = 'Narrow';
    sheet.cellA1('A2').value = 'Merged';
    sheet.mergeAndCenter(SmlRange.parse('A2:B2'));
    sheet.printArea = SmlRange.parse('A1:B2');
    final Uint8List pdf = OfficePdfExport.workbook(
      book,
      font: font,
      title: 'Geometry',
    );
    expect(_header(pdf), startsWith('%PDF-1.7'));
    expect(_pageCount(pdf), greaterThanOrEqualTo(1));
    expect(_ascii(pdf), contains('/Outlines'));
    expect(_ascii(pdf), contains(sheet.name));
  });

  test('OfficePrint forwards sheet and slide ranges', () {
    final SmlWorkbook book = SmlWorkbook();
    book.firstSheet.cellA1('A1').value = 'First';
    final SmlWorksheet second = SmlWorksheet(name: 'Second', sheetId: 2);
    second.cellA1('A1').value = 'Only second';
    book.sheets.add(second);
    final Uint8List sheets = OfficePrint.workbook(
      book,
      settings: const OfficePrintSettings(pageFrom: 2, pageTo: 2, title: 'S'),
      font: font,
    );
    expect(_pageCount(sheets), 1);
    expect(_ascii(sheets), contains('Second'));

    final PmlPresentation deck = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 1,
          shapes: <PmlShape>[
            PmlShape(
              id: 1,
              name: 't1',
              transform: const PmlTransform(cx: 2000000, cy: 500000),
              text: 'Alpha',
            ),
          ],
        ),
        PmlSlide(
          id: 2,
          shapes: <PmlShape>[
            PmlShape(
              id: 2,
              name: 't2',
              transform: const PmlTransform(cx: 2000000, cy: 500000),
              text: 'Beta',
            ),
          ],
        ),
      ],
    );
    final Uint8List slides = OfficePrint.presentation(
      deck,
      settings: const OfficePrintSettings(pageFrom: 2, pageTo: 2, title: 'P'),
      font: font,
    );
    expect(_pageCount(slides), 1);
    expect(_ascii(slides), contains('/Outlines'));
  });

  test('PdfReportBuilder remaps subset glyph ids', () {
    if (font == null) {
      return;
    }
    final Uint8List pdf =
        (PdfReportBuilder(font: font, title: 'Report')
              ..titleText('Hello')
              ..body('World'))
            .build();
    expect(_ascii(pdf), contains('/Length1'));
    final String body = _inflated(pdf).join();
    expect(RegExp(r'\[<[0-9a-fA-F]+>\] TJ').hasMatch(body), isTrue);
    expect(body.contains('[<0000>] TJ'), isFalse);
  });

  test('XLSX prints its base filename and scales authored header runs', () {
    final book = SmlWorkbook();
    final sheet = book.firstSheet
      ..pageSetup = SmlPageSetup(scale: 50)
      ..headerFooter = SmlHeaderFooter(
        headerLeft: '&20&A\n&10&F',
        footerRight: '&KFF0000Page &P / &N',
      );
    sheet.cellA1('A1').value = 'Body';
    PdfDisplayList render(SmlWorkbook input) => PdfFile.open(
      OfficePdfExport.workbook(
        input,
        workbookFileName: r'C:\private\budget.xlsx',
        options: const PdfSheetPrintOptions(useWorksheetPageSetup: true),
      ),
    ).displayList(0);

    final scaled = render(book);
    final filename = scaled.runs.singleWhere(
      (run) => run.text == 'budget.xlsx',
    );
    final sheetName = scaled.runs.singleWhere((run) => run.text == sheet.name);
    expect(filename.y, greaterThan(sheetName.y));
    expect(filename.height, lessThan(sheetName.height));
    expect(scaled.runs.any((run) => run.text.contains('private')), isFalse);
    expect(scaled.runs.any((run) => run.text == 'Page 1 / 1'), isTrue);

    sheet.headerFooter!.scaleWithDocument = false;
    final reopened = SheetDeserializer().read(SheetSerializer().write(book));
    expect(reopened.firstSheet.headerFooter!.scaleWithDocument, isFalse);
    final actual = render(
      reopened,
    ).runs.singleWhere((run) => run.text == 'budget.xlsx');
    expect(actual.height, closeTo(filename.height * 2, .01));
  });

  test('Excel PDF paints cell borders and header tokens', () {
    final SmlWorkbook book = SmlWorkbook();
    final SmlWorksheet sheet = book.firstSheet;
    sheet.cellA1('A1')
      ..value = 'Title'
      ..borderRgb = '000000'
      ..borderWidth = 1;
    sheet.cellA1('A2').value = 'Body';
    sheet.printTitleRows = SmlRange.parse('A1:A1');
    sheet.headerFooter = SmlHeaderFooter(
      headerCenter: '&A page &P of &N',
      footerLeft: 'Confidential',
    );
    final Uint8List pdf = OfficePdfExport.workbook(
      book,
      font: font,
      title: 'Borders',
      options: const PdfSheetPrintOptions(showGridlines: false),
    );
    expect(_header(pdf), startsWith('%PDF-1.7'));
    expect(_pageCount(pdf), 1);
    final String body = _inflated(pdf).join();
    // True border stroke when showGridlines is false (width 1 from borderWidth).
    expect(RegExp(r'(^|\s)1(\.0)?\s+w\b').hasMatch(body), isTrue);
    expect(
      RegExp(r'0(\.0+)?\s+0(\.0+)?\s+0(\.0+)?\s+RG').hasMatch(body),
      isTrue,
    );
    final SmlWorkbook opened = SheetDeserializer().read(
      SheetSerializer().write(book),
    );
    expect(opened.firstSheet.headerFooter?.footerLeft, 'Confidential');
    expect(opened.firstSheet.printTitleRows?.minRow, 0);
  });

  test('print quantizes imported row heights before packing a page', () {
    final sheet = SmlWorksheet(name: 'Rows', sheetId: 1)
      ..printArea = SmlRange.parse('A1:A3')
      ..pageSetup = SmlPageSetup();
    for (var row = 0; row < 3; row++) {
      sheet.rowHeights[row] = SmlWorksheet.rowHeightFromExcel(20.75);
      sheet.cell(SmlCellRef(0, row)).value = row;
    }
    final book = SheetDeserializer().readBytes(
      SheetSerializer().writeBytes(SmlWorkbook(sheets: [sheet])),
    );
    final pdf = OfficePrint.workbook(
      book,
      options: const PdfSheetPrintOptions(
        useWorksheetPageSetup: true,
        paperOverride: (width: 55, height: 81),
        marginOverride: 10,
      ),
    );
    expect(_pageCount(pdf), 1);
    expect(
      SmlWorksheet.rowHeightToExcel(book.firstSheet.rowHeightAt(0)),
      closeTo(20.75, 0.001),
    );
  });

  test(
    'XLSX print preserves an explicitly sized worksheet-wide row height',
    () {
      final sheet = SmlWorksheet(name: 'Rows', sheetId: 1)
        ..printArea = SmlRange.parse('A1:A3')
        ..pageSetup = SmlPageSetup(scale: 90)
        ..importedDefaultRowHeightPx = SmlWorksheet.rowHeightFromExcel(20.75)
        ..importedDefaultRowHeightIsCustom = true;
      for (var row = 0; row < 3; row++) {
        sheet.rowHeights[row] = SmlWorksheet.rowHeightFromExcel(20.75);
        sheet.cell(SmlCellRef(0, row)).value = row;
      }
      final book = SheetDeserializer().readBytes(
        SheetSerializer().writeBytes(SmlWorkbook(sheets: [sheet])),
      );
      expect(book.firstSheet.importedDefaultRowHeightIsCustom, isTrue);
      final pdf = OfficePrint.workbook(
        book,
        options: const PdfSheetPrintOptions(
          useWorksheetPageSetup: true,
          paperOverride: (width: 55, height: 75),
          marginOverride: 10,
        ),
      );
      // Three 20.75pt rows at 90% need 56.025pt. Flooring the rows first
      // would fit all three within 55pt and lose the continuation page.
      expect(_pageCount(pdf), 2);
    },
  );

  test('native vertical alignment positions PDF cell text', () {
    final styles = SmlStyleSheet.parse('''
<styleSheet xmlns="${OfficeNamespaces.x}">
  <cellStyleXfs count="1"><xf><alignment vertical="top"/></xf></cellStyleXfs>
  <cellXfs count="3">
    <xf xfId="0" applyAlignment="0"><alignment vertical="bottom"/></xf>
    <xf><alignment vertical="center"/></xf>
    <xf><alignment vertical="bottom"/></xf>
  </cellXfs>
</styleSheet>''');
    final sheet = SmlWorksheet(
      name: 'Aligned',
      sheetId: 1,
      pageSetup: SmlPageSetup(),
    );
    sheet.rowHeights[0] = SmlWorksheet.rowHeightFromExcel(60);
    for (final (column, label) in ['T', 'C', 'B'].indexed) {
      sheet.cell(SmlCellRef(column, 0))
        ..styleIndex = column
        ..value = label;
    }
    final book = SmlWorkbook(sheets: [sheet], styles: styles);
    final pdf = PdfFile.open(OfficePrint.workbook(book));
    final runs = pdf.displayList(0).runs;
    double y(String text) => runs.singleWhere((run) => run.text == text).y;
    expect(y('C') - y('T'), closeTo(23.5, 0.5));
    expect(y('B') - y('C'), closeTo(23.5, 0.5));

    final derived = styles.xfFor(align: SmlHAlign.center, baseStyleIndex: 0);
    expect(styles.verticalAlignAt(derived), SmlVAlign.top);
    final reopened = SmlStyleSheet.parse(styles.toXml());
    expect(reopened.verticalAlignAt(derived), SmlVAlign.top);
  });

  test('worksheet page tokens count the selected print job', () {
    final first = SmlWorksheet(
      name: 'First',
      sheetId: 1,
      pageSetup: SmlPageSetup(firstPageNumber: 3, useFirstPageNumber: true),
      headerFooter: SmlHeaderFooter(footerCenter: 'Page &P of &N'),
    );
    first
      ..cellA1('A1').value = 'First page'
      ..cellA1('A2').value = 'Second page'
      ..importManualPageBreak(1, rows: true);
    final blank = SmlWorksheet(name: 'Blank', sheetId: 2);
    final last = SmlWorksheet(
      name: 'Last',
      sheetId: 3,
      pageSetup: SmlPageSetup(firstPageNumber: 7, useFirstPageNumber: true),
      headerFooter: SmlHeaderFooter(footerCenter: 'Page &P of &N'),
    )..cellA1('A1').value = 'Last page';
    final book = SmlWorkbook(sheets: [first, blank, last]);

    final all = PdfFile.open(OfficePrint.workbook(book));
    expect(all.pageCount, 3);
    for (var i = 0; i < all.pageCount; i++) {
      expect(
        all.displayList(i).runs.map((run) => run.text),
        contains('Page ${i + 3} of 3'),
      );
    }
    final selected = PdfFile.open(
      OfficePrint.workbook(
        book,
        settings: const OfficePrintSettings(pageFrom: 3, pageTo: 3),
      ),
    );
    expect(selected.pageCount, 1);
    expect(
      selected.displayList(0).runs.map((run) => run.text),
      contains('Page 7 of 1'),
    );
  });

  test(
    'sheet print includes empty fills and borders within the print area',
    () {
      final sheet = SmlWorksheet(
        name: 'Template',
        sheetId: 1,
        pageSetup: SmlPageSetup(
          paperWidthIn: 2.5,
          marginLeftIn: 15 / 72,
          marginRightIn: 15 / 72,
        ),
      );
      sheet
        ..cellA1('A1').value = 'Form'
        ..cellA1('B1').fillRgb = 'FFFF00'
        ..cellA1('C1').borderRgb = '000000'
        ..cellA1('D1').fontBold = true;
      for (var col = 0; col < 4; col++) {
        sheet.setColumnWidth(col, 120);
      }
      final book = SmlWorkbook(sheets: [sheet]);
      expect(_pageCount(OfficePrint.workbook(book)), 3);

      sheet.printArea = SmlRange.parse('A1:B1');
      expect(_pageCount(OfficePrint.workbook(book)), 2);
    },
  );

  test('implicit print columns use Normal digits and print padding', () {
    final book = SheetDeserializer().readBytes(
      File(
        'test/fixtures/fidelity/sheet-normal-font-native.xlsx',
      ).readAsBytesSync(),
    );
    final sheet = book.firstSheet;
    sheet
      ..pageSetup = SmlPageSetup()
      ..printArea = SmlRange.parse('A1:B1')
      ..importDefaultColumnWidth();
    sheet.columnWidths.clear();
    sheet.importColumnWidth(0, 7);
    final normal = SfntFont.parse(
      File(
        '../quds_office_editor/fonts/LiberationMono-Regular.ttf',
      ).readAsBytesSync(),
    );
    const options = PdfSheetPrintOptions(
      useWorksheetPageSetup: true,
      paperOverride: (width: 220, height: 300),
      marginOverride: 10,
    );
    expect(
      _pageCount(OfficePrint.workbook(book, font: normal, options: options)),
      2,
    );
    sheet.setColumnWidth(1, 40);
    expect(
      _pageCount(OfficePrint.workbook(book, font: normal, options: options)),
      1,
    );
  });

  test('trailing blank print pages are omitted from an inferred range', () {
    final sheet = SmlWorksheet(name: 'Form', sheetId: 1)
      ..pageSetup = SmlPageSetup()
      ..setColumnWidth(0, 100)
      ..setColumnWidth(1, 100)
      ..cellA1('A1').value = 'First'
      ..cellA1('A3').value = 'Third'
      ..cellA1('B1').borderRgb = '000000'
      ..cellA1('B2').fillRgb = 'FFFFFF'
      ..cellA1('B3').fillRgb = 'FFFFFF';
    for (var row = 0; row < 3; row++) {
      sheet.setRowHeight(row, 100);
    }
    const options = PdfSheetPrintOptions(
      useWorksheetPageSetup: true,
      paperOverride: (width: 140, height: 120),
      marginOverride: 10,
    );
    final book = SmlWorkbook(sheets: [sheet]);
    expect(_pageCount(OfficePrint.workbook(book, options: options)), 4);

    sheet.printArea = SmlRange.parse('A1:B3');
    expect(_pageCount(OfficePrint.workbook(book, options: options)), 6);
  });

  test(
    'XLSX line feeds survive round-trip and appear on separate PDF lines',
    () {
      final sheet = SmlWorksheet(name: 'Line feeds', sheetId: 1);
      final book = SmlWorkbook(sheets: [sheet]);
      FormulaEvaluator.applyInput(book, sheet, sheet.cellA1('A1'), '12\n');
      expect(sheet.cellA1('A1').value, '12\n');
      FormulaEvaluator.applyInput(
        book,
        sheet,
        sheet.cellA1('A2'),
        'First\nSecond',
      );
      final reopened = SheetDeserializer().readBytes(
        SheetSerializer().writeBytes(book),
      );
      expect(reopened.firstSheet.cellA1('A2').asString, 'First\nSecond');
      expect(
        reopened.firstSheet.rowHeightAt(1),
        greaterThan(SmlWorksheet.defaultRowHeightPx),
      );
      final content = _inflated(OfficePrint.workbook(reopened)).join();
      final starts = RegExp(
        r'1 0 0 -1 ([\d.]+) ([\d.]+) Tm\n\(([FS])\) Tj',
      ).allMatches(content).toList();
      expect(starts.map((match) => match.group(3)), ['F', 'S']);
      expect(starts.first.group(1), starts.last.group(1));
      expect(
        double.parse(starts.last.group(2)!),
        greaterThan(double.parse(starts.first.group(2)!)),
      );
    },
  );

  test('Excel PDF extends an unwrapped label through an empty cell', () {
    final book = SmlWorkbook();
    final sheet = book.firstSheet;
    sheet.printArea = SmlRange.parse('A1:B2');
    sheet.columnWidths[0] = 64;
    sheet.columnWidths[1] = 64;
    sheet.cellA1('A1').value = 'A long overflowing heading';
    sheet.cellA1('A2').value = 'This label must stop at B2';
    sheet.cellA1('B2').value = 'Occupied';
    final body = _inflated(OfficePdfExport.workbook(book)).join();

    expect(body, matches(RegExp(r'94(?:\.0+)? [0-9.]+ re\s+W n')));
    expect(body, matches(RegExp(r'46(?:\.0+)? [0-9.]+ re\s+W n')));
  });

  test(
    'XLSX prints unwrapped labels over adjacent empty cells of the same fill',
    () {
      final book = SmlWorkbook();
      final sheet = book.firstSheet..printArea = SmlRange.parse('A1:C1');
      for (var column = 0; column < 3; column++) {
        sheet.columnWidths[column] = 64;
      }
      sheet.cellA1('A1')
        ..value = 'Unwrapped heading'
        ..fillRgb = 'FFFF00';
      sheet.cellA1('B1').fillRgb = 'FFFF00';
      sheet.cellA1('C1').fillRgb = '00FF00';
      final reopened = SheetDeserializer().readBytes(
        SheetSerializer().writeBytes(book),
      );
      final bytes = OfficePrint.workbook(reopened);
      final content = _inflated(bytes).join();
      expect(content, matches(RegExp(r'94(?:\.0+)? [0-9.]+ re\s+W n')));
      final text = PdfFile.open(bytes).displayList(0).runs;
      expect(text.any((run) => run.text == 'Unwrapped heading'), isTrue);
      expect(content, contains('0 1 0 rg'));
      expect(
        content.indexOf('0 1 0 rg'),
        lessThan(content.indexOf('Unwrapped heading')),
      );
    },
  );

  test('PPT PDF strokes shapes and emits URI link annots', () {
    final PmlPresentation deck = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 1,
          shapes: <PmlShape>[
            PmlShape(
              id: 2,
              name: 'LinkBox',
              transform: const PmlTransform(
                x: 914400,
                y: 914400,
                cx: 2000000,
                cy: 800000,
              ),
              fillColor: '4472C4',
              strokeColor: 'C00000',
              strokeWidth: 1.5,
              hyperlinkUrl: 'https://example.com/docs',
              text: 'Docs',
            ),
          ],
        ),
      ],
    );
    final Uint8List pdf = OfficePdfExport.presentation(
      deck,
      font: font,
      title: 'Links',
    );
    expect(_ascii(pdf), contains('/URI'));
    expect(_ascii(pdf), contains('https://example.com/docs'));
  });

  test('chart serializers honor ChartDisplay.rtl', () {
    final OfficeVisual visual = OfficeVisual(
      kind: OfficeVisualKind.chartBar,
      title: 'RTL',
      points: OfficeVisual.sampleSeries(),
      chart: ChartDisplay(rtl: true),
    );
    final PmlPresentation deck = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 1,
          shapes: <PmlShape>[
            PmlShape(
              id: 2,
              name: 'Chart',
              transform: const PmlTransform(cx: 3000000, cy: 2000000),
              visual: visual,
            ),
          ],
        ),
      ],
    );
    final OpcPackage package = SlideSerializer().write(deck);
    final PackagePart? chart = package.getPart('/ppt/charts/slide1_chart1.xml');
    expect(chart, isNotNull);
    expect(chart!.readText(), contains('rtl="1"'));
  });
}

SfntFont? _tryFont() {
  for (final String path in <String>[
    r'C:\Windows\Fonts\calibri.ttf',
    r'C:\Windows\Fonts\arial.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ]) {
    final SfntFont? font = _tryPath(path);
    if (font != null) {
      return font;
    }
  }
  return null;
}

SfntFont? _tryNoto() {
  for (final String path in <String>[
    '/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf',
    r'C:\Windows\Fonts\NotoNaskhArabic-Regular.ttf',
  ]) {
    final SfntFont? font = _tryPath(path);
    if (font != null) {
      return font;
    }
  }
  return null;
}

SfntFont? _tryPath(String path) {
  if (!File(path).existsSync()) {
    return null;
  }
  return SfntFont.parse(File(path).readAsBytesSync());
}

String _header(Uint8List pdf) => String.fromCharCodes(pdf.take(8));

String _ascii(Uint8List pdf) => String.fromCharCodes(pdf);

int _pageCount(Uint8List pdf) {
  final Match? match = RegExp(r'/Count (\d+)').firstMatch(_ascii(pdf));
  expect(match, isNotNull);
  return int.parse(match!.group(1)!);
}

List<String> _inflated(Uint8List pdf) {
  final List<String> out = <String>[];
  final List<int> mark = 'stream\n'.codeUnits;
  var i = 0;
  while (i < pdf.length - mark.length) {
    var hit = true;
    for (int k = 0; k < mark.length; k++) {
      if (pdf[i + k] != mark[k]) {
        hit = false;
        break;
      }
    }
    if (!hit) {
      i++;
      continue;
    }
    final int start = i + mark.length;
    final int end = _indexOf(pdf, 'endstream', start);
    if (end < 0) {
      break;
    }
    var payload = Uint8List.sublistView(pdf, start, end);
    if (payload.isNotEmpty && payload.last == 0x0A) {
      payload = Uint8List.sublistView(payload, 0, payload.length - 1);
    }
    if (payload.length >= 2 && payload[0] == 0x78) {
      try {
        out.add(String.fromCharCodes(PdfFlate.decompress(payload)));
      } catch (_) {}
    }
    i = end + 9;
  }
  return out;
}

int _indexOf(Uint8List data, String token, int from) {
  final List<int> needle = token.codeUnits;
  for (int i = from; i <= data.length - needle.length; i++) {
    var ok = true;
    for (int k = 0; k < needle.length; k++) {
      if (data[i + k] != needle[k]) {
        ok = false;
        break;
      }
    }
    if (ok) {
      return i;
    }
  }
  return -1;
}

List<double> _autofitBaselines(PmlShape shape, SfntFont font) {
  final String content = _inflated(
    OfficePdfExport.presentation(
      PmlPresentation(
        slides: [
          PmlSlide(id: 256, shapes: [shape]),
        ],
      ),
      font: font,
    ),
  ).join();
  return RegExp(r'1 0 0 -1 [-0-9.]+ ([-0-9.]+) Tm')
      .allMatches(content)
      .map((match) => double.parse(match.group(1)!))
      .toSet()
      .toList()
    ..sort();
}
