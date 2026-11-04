import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('page numbers increment on each laid-out page', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          footer: <WmlParagraph>[
            WmlParagraph(
              properties: WmlParagraphProps(
                justification: WmlJustification.center,
                pageNumberField: true,
              ),
            ),
          ],
          blocks: <WmlBlock>[
            for (int i = 0; i < 3; i++)
              WmlParagraph(
                properties: WmlParagraphProps(pageBreakBefore: i > 0),
                inlines: <WmlInline>[WmlRun(text: 'Body $i')],
              ),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    expect(laid.pages.length, 3);
    expect(
      laid.pages.map((LaidOutPage p) => p.footer.single.overlayText).toList(),
      <String>['1', '2', '3'],
    );
  });

  test('footer PAGE field keeps the title suffix', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          footer: <WmlParagraph>[
            WmlParagraph(
              properties: WmlParagraphProps(pageNumberField: true),
              inlines: <WmlInline>[
                WmlRun(text: '1  |  Al Tahreer Neighborhood Profile'),
              ],
            ),
          ],
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Body')]),
          ],
        ),
      ],
    );
    final Uint8List bytes = WordSerializer().writeBytes(doc);
    final String footer = OpcPackage.openBytes(bytes)
        .getPart('/word/footer1.xml')!
        .readText();
    expect(footer.contains('PAGE'), isTrue);
    expect(footer.contains('Al Tahreer Neighborhood Profile'), isTrue);
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    expect(
      laid.pages.first.footer.single.overlayText,
      '1  |  Al Tahreer Neighborhood Profile',
    );
  });

  test('named Word highlights map to RGB', () {
    expect(WmlHighlight.toRgb('yellow'), 'FFFF00');
    expect(WmlHighlight.toRgb('green'), '00FF00');
    expect(WmlHighlight.toRgb('none'), isNull);
    expect(WmlHighlight.toRgb('A1B2C3'), 'A1B2C3');
  });

  test('layout stores highlight RGB and list markers', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
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
              properties: WmlParagraphProps(listLabel: '• '),
              inlines: <WmlInline>[
                WmlRun(
                  text: 'Phase one',
                  properties: WmlRunProps(highlight: 'yellow'),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    expect(laid.pages, isNotEmpty);
    expect(laid.pages.first.footer, isNotEmpty);
    expect(laid.pages.first.footer.first.overlayText, '1');
    expect(laid.pages.first.lines, isNotEmpty);
    expect(laid.pages.first.lines.first.listLabel, '• ');
    expect(laid.pages.first.lines.first.glyphs.first.highlight, 'FFFF00');
  });

  test('deserializer reads lists, footer PAGE field, and skips instrText', () {
    final Uint8List bytes =
        (DocxDocumentBuilder()
              ..paragraph('Intro')
              ..bulletList(<String>['Alpha', 'Beta'])
              ..numberedList(<String>['First', 'Second'])
              ..footer(pageNumber: true))
            .build();

    final WmlDocument doc = WordDeserializer().readBytes(bytes);
    expect(doc.sections.first.footer, isNotEmpty);
    expect(
      doc.sections.first.footer.any(
        (WmlParagraph p) => p.properties.pageNumberField,
      ),
      isTrue,
    );
    expect(
      doc.sections.first.footer.any(
        (WmlParagraph p) => p.text.contains('PAGE'),
      ),
      isFalse,
    );

    final List<WmlParagraph> listed = doc.paragraphs
        .where((WmlParagraph p) => p.properties.numId != null)
        .toList();
    expect(listed.length, 4);
    expect(listed[0].properties.listLabel, '• ');
    expect(listed[1].properties.listLabel, '• ');
    expect(listed[2].properties.listLabel, '1. ');
    expect(listed[3].properties.listLabel, '2. ');

    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    expect(laid.pages.first.footer, isNotEmpty);
    expect(
      laid.pages.first.footer.any(
        (LaidOutLine line) => line.overlayText == '1',
      ),
      isTrue,
    );
  });

  test('deserializer keeps only w:t and maps cell shade + highlight', () {
    const String ns = OfficeNamespaces.w;
    const String rns = OfficeNamespaces.r;
    final OpcPackage package = OpcPackage.create(OpcPackageKind.word);
    package
        .getPart('/word/document.xml')!
        .writeText(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document xmlns:w="$ns" xmlns:r="$rns">'
          '<w:body>'
          '<w:p><w:r><w:rPr><w:highlight w:val="yellow"/></w:rPr>'
          '<w:t>Marked</w:t></w:r></w:p>'
          '<w:tbl><w:tblGrid><w:gridCol w:w="1440"/></w:tblGrid>'
          '<w:tr><w:tc><w:tcPr><w:shd w:fill="1F4E79"/></w:tcPr>'
          '<w:p><w:r><w:t>Cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
          '<w:sectPr>'
          '<w:pgSz w:w="12240" w:h="15840"/>'
          '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>'
          '<w:footerReference w:type="default" r:id="rIdFtr"/>'
          '</w:sectPr>'
          '</w:body></w:document>',
        );
    package.createPart(
      '/word/footer1.xml',
      OfficeContentTypes.wordFooter,
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:ftr xmlns:w="$ns">'
        '<w:sdt><w:sdtContent>'
        '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
        '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
        '<w:r><w:instrText xml:space="preserve"> PAGE \\* MERGEFORMAT </w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
        '<w:r><w:t>2</w:t></w:r>'
        '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
        '</w:p></w:sdtContent></w:sdt></w:ftr>',
      ),
    );
    package
        .relationshipsFor('/word/document.xml')
        .add(
          type: RelationshipTypes.footer,
          target: 'footer1.xml',
          id: 'rIdFtr',
        );

    final WmlDocument doc = WordDeserializer().read(package);
    expect(
      doc.paragraphs.first.inlines
          .whereType<WmlRun>()
          .first
          .properties
          .highlight,
      'yellow',
    );
    final WmlTable table = doc.sections.first.blocks
        .whereType<WmlTable>()
        .single;
    expect(table.rows.first.cells.first.fillColor, '1F4E79');
    expect(doc.sections.first.footer, isNotEmpty);
    expect(doc.sections.first.footer.first.properties.pageNumberField, isTrue);
    expect(doc.sections.first.footer.first.text.contains('PAGE'), isFalse);
    expect(doc.sections.first.footer.first.text.trim(), isEmpty);

    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    expect(laid.pages.first.lines.first.glyphs.first.highlight, 'FFFF00');
    expect(laid.pages.first.frames.first.fillColor, '1F4E79');
    expect(laid.pages.first.footer.first.overlayText, '1');
  });

  test('run edit extracts and inserts formatted spans', () {
    final WmlParagraph para = WmlParagraph(
      inlines: <WmlInline>[
        WmlRun(text: 'Hello ', properties: WmlRunProps(bold: true)),
        WmlRun(text: 'world', properties: WmlRunProps(italic: true)),
      ],
    );
    final List<WmlRun> mid = WmlRunEdit.extractRuns(para, 2, 8);
    expect(mid.map((WmlRun r) => r.text).join(), 'llo wo');
    expect(mid.first.properties.bold, isTrue);
    expect(mid.last.properties.italic, isTrue);
    WmlRunEdit.insertRuns(para, 6, <WmlRun>[
      WmlRun(
        text: 'X',
        properties: WmlRunProps(underline: WmlUnderline.single),
      ),
    ]);
    expect(para.text, 'Hello Xworld');
  });

  test('Word pictures round-trip as DrawingML, not placeholder text', () {
    final Uint8List png = PngBytes.studioCard();
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Caption')]),
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                title: 'Studio card',
                imageBytes: png,
                width: 200,
                height: 110,
              ),
            ),
          ],
        ),
      ],
    );
    final Uint8List bytes = WordSerializer().writeBytes(doc);
    final OpcPackage package = OpcPackage.openBytes(bytes);
    final String xml = package.getPart('/word/document.xml')!.readText();
    expect(xml.contains('[picture]'), isFalse);
    expect(xml.contains('<w:drawing>'), isTrue);
    expect(xml.contains('<a:blip'), isTrue);
    expect(xml.contains('r:embed='), isTrue);
    expect(package.getPart('/word/media/image1.png'), isNotNull);

    final WmlDocument copy = WordDeserializer().readBytes(bytes);
    expect(copy.visuals, isNotEmpty);
    expect(copy.visuals.first.visual.isPicture, isTrue);
    expect(copy.visuals.first.visual.imageBytes, isNotEmpty);
    expect(copy.visuals.first.visual.title, 'Studio card');
    expect(xml.contains('</w:drawing></w:r></w:p>'), isTrue);
    expect(RegExp(r'</w:drawing></w:r><w:p>').hasMatch(xml), isFalse);
  });

  test('Word charts write DrawingML chart parts, not placeholder text', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.chartColumn,
                title: 'Quarterly mix',
                points: OfficeVisual.sampleSeries(),
                width: 420,
                height: 170,
              ),
            ),
          ],
        ),
      ],
    );
    final Uint8List bytes = WordSerializer().writeBytes(doc);
    final OpcPackage package = OpcPackage.openBytes(bytes);
    final String xml = package.getPart('/word/document.xml')!.readText();
    expect(xml.contains('[chartColumn]'), isFalse);
    expect(xml.contains('<w:drawing>'), isTrue);
    expect(xml.contains('<c:chart'), isTrue);
    expect(package.getPart('/word/charts/chart1.xml'), isNotNull);

    final WmlDocument copy = WordDeserializer().readBytes(bytes);
    expect(copy.visuals, isNotEmpty);
    expect(copy.visuals.first.visual.isChart, isTrue);
    expect(copy.visuals.first.visual.title, 'Quarterly mix');
    expect(copy.visuals.first.visual.points, isNotEmpty);
    expect(xml.contains('</w:drawing></w:r></w:p>'), isTrue);
  });

  test('Word picture properties round-trip through DrawingML', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                title: 'Card',
                imageBytes: PngBytes.studioCard(),
                width: 180,
                height: 90,
                offsetX: 24,
                picture: PictureAdjust(
                  cropLeft: 0.1,
                  cropTop: 0.05,
                  cropRight: 0.08,
                  cropBottom: 0.04,
                  rotationDeg: 90,
                  brightness: 0.2,
                  contrast: 1.3,
                  transparency: 0.25,
                  borderColor: '2B579A',
                  borderWidth: 3,
                  flipH: true,
                  lockAspect: false,
                  wrap: PictureWrap.square,
                  shadow: true,
                  altTitle: 'Alt title',
                  altDescription: 'Alt description',
                ),
              ),
            ),
          ],
        ),
      ],
    );
    final Uint8List bytes = WordSerializer().writeBytes(doc);
    final String xml = OpcPackage.openBytes(
      bytes,
    ).getPart('/word/document.xml')!.readText();
    expect(xml.contains('<wp:anchor'), isTrue);
    expect(xml.contains('<wp:wrapSquare'), isTrue);
    expect(xml.contains('<a:lum'), isTrue);
    expect(xml.contains('<a:alphaModFix'), isTrue);
    expect(xml.contains('flipH="1"'), isTrue);
    expect(xml.contains('<a:outerShdw'), isTrue);
    expect(xml.contains('<a:ln'), isTrue);

    final OfficeVisual copy = WordDeserializer()
        .readBytes(bytes)
        .visuals
        .first
        .visual;
    expect(copy.picture.cropLeft, closeTo(0.1, 0.01));
    expect(copy.picture.rotationDeg, closeTo(90, 0.2));
    expect(copy.picture.brightness, closeTo(0.2, 0.02));
    expect(copy.picture.contrast, closeTo(1.3, 0.02));
    expect(copy.picture.transparency, closeTo(0.25, 0.02));
    expect(copy.picture.flipH, isTrue);
    expect(copy.picture.shadow, isTrue);
    expect(copy.picture.wrap, PictureWrap.square);
    expect(copy.picture.borderWidth, greaterThan(0));
    expect(copy.picture.altTitle, 'Alt title');
  });

  test('Word chart display flags persist in the chart part', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.chartColumn,
                title: 'Budget',
                points: OfficeVisual.sampleSeries(),
                chart: ChartDisplay(
                  showLegend: true,
                  showDataLabels: true,
                  showAxes: true,
                  showGridlines: false,
                  legendPos: ChartLegendPos.right,
                  gapWidth: 80,
                ),
              ),
            ),
          ],
        ),
      ],
    );
    final Uint8List bytes = WordSerializer().writeBytes(doc);
    final String chart = OpcPackage.openBytes(
      bytes,
    ).getPart('/word/charts/chart1.xml')!.readText();
    expect(chart.contains('<c:legend>'), isTrue);
    expect(chart.contains('legendPos val="r"'), isTrue);
    expect(chart.contains('showVal val="1"'), isTrue);
    expect(chart.contains('<c:majorGridlines/>'), isFalse);
    expect(chart.contains('gapWidth val="80"'), isTrue);

    final OfficeVisual copy = WordDeserializer()
        .readBytes(bytes)
        .visuals
        .first
        .visual;
    expect(copy.chart.showLegend, isTrue);
    expect(copy.chart.showDataLabels, isTrue);
    expect(copy.chart.legendPos, ChartLegendPos.right);
    expect(copy.chart.showGridlines, isFalse);
    expect(copy.points.first.color, isNotEmpty);
  });

  test('Excel drawings write pictures and charts and read them back', () {
    final SmlWorkbook book = SmlWorkbook(
      sheets: <SmlWorksheet>[
        SmlWorksheet(
          name: 'Sheet1',
          sheetId: 1,
          drawings: <SmlDrawing>[
            SmlDrawing(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                title: 'Logo',
                imageBytes: PngBytes.studioCard(),
                width: 120,
                height: 60,
                picture: PictureAdjust(
                  rotationDeg: 15,
                  borderColor: '217346',
                  borderWidth: 2,
                ),
              ),
              col: 2,
              row: 3,
              offsetX: 8,
              offsetY: 4,
            ),
            SmlDrawing(
              visual: OfficeVisual(
                kind: OfficeVisualKind.chartPie,
                title: 'Share',
                points: OfficeVisual.sampleSeries(),
                chart: ChartDisplay(showLegend: true, showPercent: true),
              ),
              col: 6,
              row: 1,
            ),
          ],
        ),
      ],
    );
    final Uint8List bytes = SheetSerializer().writeBytes(book);
    final OpcPackage package = OpcPackage.openBytes(bytes);
    expect(package.getPart('/xl/drawings/drawing1.xml'), isNotNull);
    expect(package.getPart('/xl/charts/chart1.xml'), isNotNull);
    expect(
      package
          .getPart('/xl/worksheets/sheet1.xml')!
          .readText()
          .contains('<drawing'),
      isTrue,
    );

    final SmlWorkbook copy = SheetDeserializer().readBytes(bytes);
    expect(copy.sheets.first.drawings, hasLength(2));
    expect(copy.sheets.first.drawings.first.visual.isPicture, isTrue);
    expect(copy.sheets.first.drawings.first.col, 2);
    expect(
      copy.sheets.first.drawings.first.visual.picture.rotationDeg,
      closeTo(15, 0.2),
    );
    expect(copy.sheets.first.drawings.last.visual.isChart, isTrue);
    expect(copy.sheets.first.drawings.last.visual.points, isNotEmpty);
  });

  test('PowerPoint pictures and charts persist on save', () {
    final PmlPresentation pres = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          shapes: <PmlShape>[
            PmlShape(
              id: 2,
              name: 'Picture',
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                title: 'Shot',
                imageBytes: PngBytes.studioCard(),
                picture: PictureAdjust(flipV: true, brightness: -0.1),
              ),
              transform: const PmlTransform(
                x: 100000,
                y: 100000,
                cx: 2000000,
                cy: 1200000,
              ),
            ),
            PmlShape(
              id: 3,
              name: 'Chart',
              visual: OfficeVisual(
                kind: OfficeVisualKind.chartLine,
                title: 'Trend',
                points: OfficeVisual.sampleSeries(),
                chart: ChartDisplay(showLegend: false, showAxes: true),
              ),
              transform: const PmlTransform(
                x: 300000,
                y: 2000000,
                cx: 4000000,
                cy: 2000000,
              ),
            ),
          ],
        ),
      ],
    );
    final Uint8List bytes = SlideSerializer().writeBytes(pres);
    final OpcPackage package = OpcPackage.openBytes(bytes);
    final String slide = package.getPart('/ppt/slides/slide1.xml')!.readText();
    expect(slide.contains('<p:pic>'), isTrue);
    expect(slide.contains('<p:graphicFrame>'), isTrue);
    expect(package.getPart('/ppt/media/image1.png'), isNotNull);
    expect(package.getPart('/ppt/charts/chart1.xml'), isNotNull);

    final PmlPresentation copy = SlideDeserializer().readBytes(bytes);
    expect(
      copy.slides.first.shapes.where((PmlShape s) => s.visual != null),
      hasLength(2),
    );
    final OfficeVisual? picture = copy.slides.first.shapes
        .map((PmlShape s) => s.visual)
        .firstWhere((OfficeVisual? v) => v?.isPicture ?? false);
    expect(picture!.picture.flipV, isTrue);
    expect(copy.slides.first.shapes.last.visual!.isChart, isTrue);
  });

  test('Docx builder images deserialize as Word visuals', () {
    final Uint8List bytes =
        (DocxDocumentBuilder()
              ..paragraph('Intro')
              ..image(PngBytes.studioCard(), name: 'card.png'))
            .build();
    final WmlDocument doc = WordDeserializer().readBytes(bytes);
    expect(doc.visuals, isNotEmpty);
    expect(doc.visuals.first.visual.imageBytes, isNotEmpty);
  });

  test('Word columns and frames round-trip through document.xml', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          columnCount: 2,
          columnSpace: 24,
          columnSep: true,
          blocks: <WmlBlock>[
            WmlFrame(
              x: 40,
              y: 60,
              width: 160,
              height: 70,
              fillColor: '1F4E79',
              strokeColor: '000000',
              blocks: <WmlBlock>[
                WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Boxed')]),
              ],
            ),
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Left')]),
            WmlParagraph(
              properties: WmlParagraphProps(columnBreakBefore: true),
              inlines: <WmlInline>[WmlRun(text: 'Right')],
            ),
          ],
        ),
      ],
    );
    final Uint8List bytes = WordSerializer().writeBytes(doc);
    final String xml = OpcPackage.openBytes(bytes)
        .getPart('/word/document.xml')!
        .readText();
    expect(xml.contains('wps:wsp'), isTrue);
    expect(xml.contains('v:rect'), isTrue);
    expect(xml.contains('qudsFrame:'), isFalse);
    final WmlDocument copy = WordDeserializer().readBytes(bytes);
    expect(copy.sections.first.columnCount, 2);
    expect(copy.sections.first.columnSpace, 24);
    expect(copy.sections.first.columnSep, isTrue);
    final WmlFrame frame = copy.sections.first.blocks
        .whereType<WmlFrame>()
        .single;
    expect(frame.x, 40);
    expect(frame.y, 60);
    expect(frame.fillColor, '1F4E79');
    expect(frame.blocks.whereType<WmlParagraph>().first.text, 'Boxed');
    expect(frame.width, 160);
    expect(
      copy.paragraphs.any(
        (WmlParagraph p) => p.properties.columnBreakBefore || p.text == 'Right',
      ),
      isTrue,
    );
  });

  test('Word serializer keeps multiple sections', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          margins: const WmlPageMargins(
            top: 48,
            bottom: 48,
            left: 48,
            right: 48,
          ),
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Section A')]),
          ],
        ),
        WmlSection(
          columnCount: 2,
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Section B')]),
          ],
        ),
      ],
    );
    final Uint8List bytes = WordSerializer().writeBytes(doc);
    final String xml = OpcPackage.openBytes(
      bytes,
    ).getPart('/word/document.xml')!.readText();
    final int firstSect = xml.indexOf('<w:sectPr');
    final int firstPPr = xml.lastIndexOf('<w:pPr>', firstSect);
    expect(firstPPr, greaterThan(-1));
    expect(xml.substring(firstPPr, firstSect).contains('</w:p>'), isFalse);
    expect(xml.split('<w:sectPr').length - 1, 2);
    expect(
      xml.contains('<w:cols w:num="1"') || xml.contains("w:num=\"1\""),
      isTrue,
    );
    final WmlDocument copy = WordDeserializer().readBytes(bytes);
    expect(copy.sections.length, 2);
    expect(copy.sections.first.margins.top, 48);
    expect(copy.sections.first.columnCount, 1);
    expect(copy.sections.last.columnCount, 2);
    expect(copy.paragraphs.map((WmlParagraph p) => p.text).toList(), <String>[
      'Section A',
      'Section B',
    ]);
  });

  test('Word columns stay on their own section after a single-column page', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Cover')]),
          ],
        ),
        WmlSection(
          columnCount: 2,
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Disclaimer')]),
          ],
        ),
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Back')]),
          ],
        ),
      ],
    );
    final WmlDocument copy = WordDeserializer().readBytes(
      WordSerializer().writeBytes(doc),
    );
    expect(copy.sections, hasLength(3));
    expect(copy.sections[0].columnCount, 1);
    expect(copy.sections[1].columnCount, 2);
    expect(copy.sections[2].columnCount, 1);
  });

  test('inline tabs serialize as w:tab and round-trip', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'A\tB')]),
          ],
        ),
      ],
    );
    final OpcPackage package = WordSerializer().write(doc);
    final String xml = package.getPart('/word/document.xml')!.readText();
    expect(xml, contains('<w:tab'));
    expect(xml.contains('A\tB'), isFalse);
    final WmlDocument copy = WordDeserializer().read(package);
    expect(copy.paragraphs.first.text, 'A\tB');
  });

  test('round-trips paragraph w:bidi and justification', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(
              properties: WmlParagraphProps(
                rightToLeft: true,
                justification: WmlJustification.right,
              ),
              inlines: <WmlInline>[WmlRun(text: 'بطاقة جديدة')],
            ),
            WmlParagraph(
              properties: WmlParagraphProps(rightToLeft: false),
              inlines: <WmlInline>[WmlRun(text: 'Hello')],
            ),
          ],
        ),
      ],
    );
    final Uint8List bytes = WordSerializer().writeBytes(doc);
    final WmlDocument copy = WordDeserializer().readBytes(bytes);
    expect(copy.paragraphs.first.properties.rightToLeft, isTrue);
    expect(
      copy.paragraphs.first.properties.justification,
      WmlJustification.right,
    );
    expect(copy.paragraphs.last.properties.rightToLeft, isFalse);
  });
}
