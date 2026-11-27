import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('serializes escaped run text and Word controls in source order', () {
    final document = WmlDocument.empty(text: ' A<&😀\tB\r\nC\u00adD\u2011 E ');
    final xml = WordSerializer()
        .write(document)
        .getPart('/word/document.xml')!
        .readText();
    expect(
      xml,
      contains(
        '<w:t xml:space="preserve"> A&lt;&amp;😀</w:t><w:tab/>'
        '<w:t xml:space="preserve">B</w:t><w:br/>'
        '<w:t xml:space="preserve">C</w:t><w:softHyphen/>'
        '<w:t xml:space="preserve">D</w:t><w:noBreakHyphen/>'
        '<w:t xml:space="preserve"> E </w:t>',
      ),
    );
  });

  test('compacts inherited namespaces only for ordinary run formatting', () {
    final package = OpcPackage.openBytes(
      (DocxDocumentBuilder()..paragraph('Placeholder')).build(),
    );
    final part = package.getPart('/word/document.xml')!;
    part.writeText(
      '<w:document xmlns:w="${OfficeNamespaces.w}" '
      'xmlns:ext="urn:fixture:extension" xmlns:kind="urn:fixture:types">'
      '<w:body><w:p>'
      '<w:r><w:rPr><w:b/><w:rFonts w:ascii="Test Font"/>'
      '<w:lang w:val="de-DE"/></w:rPr><w:t>Plain</w:t></w:r>'
      '<w:r><w:rPr><w:b ext:type="kind:Choice"/></w:rPr>'
      '<w:t>Extension</w:t></w:r>'
      '<w:r><w:rPr xmlns:local="urn:fixture:local"><w:b/></w:rPr>'
      '<w:t>Explicit</w:t></w:r>'
      '</w:p></w:body></w:document>',
    );
    final document = WordDeserializer().readBytes(package.save());
    final runs = document.paragraphs.single.inlines
        .whereType<WmlRun>()
        .toList();
    expect(
      runs[0].properties.sourcePropertiesXml,
      isNot(contains('xmlns:ext')),
    );
    expect(
      runs[0].properties.sourcePropertiesXml,
      isNot(contains('xmlns:kind')),
    );
    expect(runs[0].properties.proofingLanguage, 'de-DE');
    expect(runs[0].properties.asciiFont, 'Test Font');
    expect(runs[0].properties.bold, isTrue);
    runs[0].properties.proofingLanguage = 'de-AT';

    final saved = WordSerializer().write(document);
    final output = saved.getPart('/word/document.xml')!.readText();
    expect(output, contains('xmlns:kind="urn:fixture:types"'));
    expect(output, contains('ext:type="kind:Choice"'));
    expect(output, contains('xmlns:local="urn:fixture:local"'));
    final reopened = WordDeserializer().readBytes(saved.save());
    final plain = reopened.paragraphs.single.inlines.whereType<WmlRun>().first;
    expect(plain.text, 'Plain');
    expect(plain.properties.proofingLanguage, 'de-AT');
    expect(plain.properties.asciiFont, 'Test Font');
    expect(plain.properties.bold, isTrue);
  });

  test(
    'compacts plain field and bookmark markers with inherited namespaces',
    () {
      final package = OpcPackage.create(OpcPackageKind.word);
      package
          .getPart('/word/document.xml')!
          .writeText(
            '<w:document xmlns:w="${OfficeNamespaces.w}" '
            'xmlns:ext="urn:fixture:ext" xmlns:kind="urn:fixture:kind">'
            '<w:body><w:p><w:bookmarkStart w:id="1" w:name="Target"/>'
            '<w:r><w:t>See </w:t></w:r>'
            '<w:r><w:fldChar w:fldCharType="begin" w:fldLock="1"/></w:r>'
            '<w:r><w:instrText> PAGEREF Target </w:instrText></w:r>'
            '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
            '<w:r><w:t>4</w:t></w:r>'
            '<w:r><w:fldChar w:fldCharType="end" ext:type="kind:Choice"/></w:r>'
            '<w:bookmarkEnd w:id="1" ext:type="kind:Choice"/>'
            '</w:p></w:body></w:document>',
          );

      void verify(WmlDocument document) {
        final paragraph = document.paragraphs.single;
        expect(paragraph.text, 'See 4');
        final fields = paragraph.inlines.whereType<WmlFieldBoundary>().toList();
        expect(fields.first.sourceXml, contains('w:fldLock="1"'));
        expect(fields.first.sourceXml, isNot(contains('xmlns:kind')));
        expect(
          fields.last.sourceXml,
          contains('xmlns:kind="urn:fixture:kind"'),
        );
        expect(fields.last.sourceXml, contains('ext:type="kind:Choice"'));
        final bookmarks = paragraph.inlines.whereType<WmlBookmarkBoundary>();
        expect(bookmarks.first.sourceXml, isNot(contains('xmlns:kind')));
        expect(
          bookmarks.last.sourceXml,
          contains('xmlns:kind="urn:fixture:kind"'),
        );
        expect(bookmarks.last.sourceXml, contains('ext:type="kind:Choice"'));
      }

      final document = WordDeserializer().read(package);
      verify(document);
      verify(
        WordDeserializer().readBytes(WordSerializer().write(document).save()),
      );
    },
  );

  test('footer text flows upward from the bottom margin', () {
    WmlParagraph paragraph(String text, int halfPoints, double lineHeight) =>
        WmlParagraph(
          inlines: [
            WmlRun(
              text: text,
              properties: WmlRunProps(fontSizeHalfPoints: halfPoints),
            ),
          ],
          properties: WmlParagraphProps(
            spacingAfter: 0,
            lineSpacingRule: WmlLineSpacingRule.exact,
            lineSpacing: lineHeight,
          ),
        );
    final document = WmlDocument(
      sections: [
        WmlSection(
          pageSize: WmlPageSize(width: 612, height: 792),
          margins: WmlPageMargins(footer: 36),
          blocks: [paragraph('Body', 24, 18)],
          footer: [
            paragraph('273840', 24, 18),
            paragraph('Tall', 40, 24),
            paragraph('Section\t481602', 24, 18),
          ],
        ),
      ],
    );
    final page = WordLayoutEngine(font: null).layout(document).pages.single;
    final footer = page.footer;
    expect(footer.map((line) => line.text), [
      '273840',
      'Tall',
      'Section',
      '481602',
    ]);
    expect(footer.map((line) => line.y), [696, 714, 738, 738]);
    expect(footer[1].overlaySize, 20);
    expect(footer[1].overlayBaseline, closeTo(19.2, 1e-8));
    expect(footer.first.proofingOffsetAt(0), 0);
    expect(footer.last.proofingOffsetAt(0), 8);

    final story = document.sections.single.footer;
    story[0].properties
      ..spacingBefore = 3
      ..spacingAfter = 9;
    story[1].properties
      ..spacingBefore = 6
      ..spacingAfter = 4;
    story[2].properties
      ..spacingBefore = 2
      ..spacingAfter = 8;
    final spaced = WordLayoutEngine(font: null).layout(document).pages.single;
    expect(spaced.footer.map((line) => line.y), [675, 702, 730, 730]);
  });

  test('positioned footer paragraphs share a frame and leave ordinary flow', () {
    const marginFrame =
        '<w:framePr w:w="3600" w:h="720" w:hRule="exact" '
        'w:hAnchor="margin" w:vAnchor="margin" w:x="2400" w:y="12000"/>';
    const rightFrame =
        '<w:framePr w:hAnchor="margin" w:vAnchor="text" w:xAlign="right" w:y="1"/>';
    String paragraph(String content, [String frame = '']) =>
        '<w:p><w:pPr>$frame<w:spacing w:before="0" w:after="0" '
        'w:line="360" w:lineRule="exact"/></w:pPr>$content</w:p>';
    String run(String text) =>
        '<w:r><w:rPr><w:sz w:val="24"/></w:rPr><w:t>$text</w:t></w:r>';
    String marker(String kind) =>
        '<w:r><w:fldChar w:fldCharType="$kind"/></w:r>';
    final builder = DocxDocumentBuilder()
      ..paragraph('Body')
      ..footer(left: 'Placeholder', pageNumber: false);
    final package = OpcPackage.openBytes(builder.build());
    final body = package.getPart('/word/document.xml')!;
    body.writeText(
      body.readText().replaceFirst(
        RegExp(r'<w:pgMar\b[^>]*/>'),
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1800" '
        'w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>',
      ),
    );
    final footer = package.getPart('/word/footer1.xml')!;
    footer.writeText(
      '<w:ftr xmlns:w="${OfficeNamespaces.w}">'
      '${paragraph('${marker('begin')}<w:r><w:instrText> IF 1 = 1 "Frame A" "" </w:instrText></w:r>', marginFrame)}'
      '${paragraph('${marker('separate')}${run('Frame A')}${marker('end')}', marginFrame)}'
      '${paragraph(run('Frame B'), marginFrame)}'
      '${paragraph(run('Frame right'), rightFrame)}'
      '${paragraph(run('Ordinary'))}${paragraph(run('Last'))}</w:ftr>',
    );

    void verify(WmlDocument document) {
      final page = WordLayoutEngine(font: null).layout(document).pages.single;
      final lines = page.footer;
      expect(lines.map((line) => line.text), [
        'Frame A',
        'Frame B',
        'Frame right',
        'Ordinary',
        'Last',
      ]);
      expect(lines[0].x, 192);
      expect(lines[1].x, 192);
      expect(lines[0].y, 672);
      expect(lines[1].y, 690);
      expect(lines[2].x + lines[2].width, closeTo(page.width - 72, 1e-8));
      expect(lines[2].y, closeTo(lines[3].y + .05, 1e-8));
      expect(lines[4].y + lines[4].height, page.height - 36);
    }

    final document = WordDeserializer().read(package);
    verify(document);
    final reopened = WordSerializer().writeBytes(document);
    verify(WordDeserializer().readBytes(reopened));
    final savedFooter = OpcPackage.openBytes(
      reopened,
    ).getPart('/word/footer1.xml')!.readText();
    expect(RegExp('w:framePr').allMatches(savedFooter), hasLength(4));
    expect(savedFooter, contains('w:x="2400"'));
    expect(savedFooter, contains('w:xAlign="right"'));
  });

  test(
    'positioned PAGE displays the current page without changing its cache',
    () {
      WmlParagraph field({required bool locked}) => WmlParagraph(
        properties: WmlParagraphProps()
          ..sourcePropertiesXml =
              '<w:pPr xmlns:w="${OfficeNamespaces.w}">'
              '<w:framePr w:hAnchor="margin" w:vAnchor="text" w:xAlign="right"/>'
              '</w:pPr>',
        inlines: [
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.begin,
            sourceXml: locked
                ? '<w:fldChar xmlns:w="${OfficeNamespaces.w}" '
                      'w:fldCharType="begin" w:fldLock="true"/>'
                : null,
          ),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: ' PAGE ',
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          WmlRun(text: '9'),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
        ],
      );
      final live = field(locked: false);
      final locked = field(locked: true);
      final doc = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlParagraph(inlines: [WmlRun(text: 'One')]),
              WmlParagraph(
                properties: WmlParagraphProps(pageBreakBefore: true),
                inlines: [WmlRun(text: 'Two')],
              ),
            ],
            footer: [live, locked],
          ),
        ],
      );
      final laid = WordLayoutEngine(font: null).layout(doc);
      expect(
        laid.pages.map((p) => p.footer.map((line) => line.text).toList()),
        [
          ['1', '9'],
          ['2', '9'],
        ],
      );
      expect(live.text, '9');
      expect(laid.pages.last.footer.first.proofingOffsetAt(0), isNull);
    },
  );

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
    final String footer = OpcPackage.openBytes(
      bytes,
    ).getPart('/word/footer1.xml')!.readText();
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

    final footerXml = OpcPackage.openBytes(
      bytes,
    ).getPart('/word/footer1.xml')!.readText();
    expect(footerXml, contains('w:fldCharType="separate"'));
    final WmlDocument doc = WordDeserializer().readBytes(bytes);
    expect(doc.sections.first.footer, isNotEmpty);
    expect(
      doc.sections.first.footer.last.inlines
          .whereType<WmlRun>()
          .first
          .properties
          .fontSizePoints,
      8,
    );
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
      'FFFF00',
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
    expect(package.getPart('/xl/drawings/sheet1_drawing.xml'), isNotNull);
    expect(package.getPart('/xl/charts/sheet1_chart1.xml'), isNotNull);
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
    expect(package.getPart('/ppt/media/slide1_image1.png'), isNotNull);
    expect(package.getPart('/ppt/charts/slide1_chart1.xml'), isNotNull);

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
    final String xml = OpcPackage.openBytes(
      bytes,
    ).getPart('/word/document.xml')!.readText();
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
