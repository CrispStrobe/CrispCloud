import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _tableNs = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';

Uint8List _native(String body) {
  final zip = ZipWriter();
  zip.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content xmlns:office="$_officeNs" '
      'xmlns:text="$_textNs" xmlns:table="$_tableNs" xmlns:foreign="urn:foreign">'
      '<office:body><office:text>$body</office:text></office:body>'
      '</office:document-content>',
    ),
  );
  return zip.close();
}

Uint8List _word(List<WmlParagraph> paragraphs) => OdtDocumentWriter.writeBytes(
  WmlDocument(sections: [WmlSection(blocks: paragraphs)]),
);

String _part(Uint8List bytes, String path) =>
    OpcPackage.openBytes(bytes).getPart('/$path')!.readText();

void _saveFixture(String name, Uint8List bytes) {
  final output = Platform.environment['QUDS_ODF_FIXTURE_OUTPUT'];
  if (output == null || output.isEmpty) return;
  Directory(output).createSync(recursive: true);
  File('$output/$name').writeAsBytesSync(bytes);
}

Iterable<XmlElement> _elements(XmlElement node, String name) sync* {
  if (node.localName == name && node.namespaceUri == _textNs) yield node;
  for (final child in node.childElements) {
    yield* _elements(child, name);
  }
}

void main() {
  test(
    'ODT preserves authored spaces tabs and breaks in explicit ODF markup',
    () {
      const source = '  A\tB  C\nD ';
      final bytes = _word([
        WmlParagraph(inlines: [WmlRun(text: source)]),
      ]);
      _saveFixture('word-text.odt', bytes);
      final root = XmlDocument.parse(_part(bytes, 'content.xml')).root!;
      expect(_elements(root, 's').map((e) => e.getAttribute('c') ?? '1'), [
        '2',
        '2',
        '1',
      ]);
      expect(_elements(root, 'tab'), hasLength(1));
      expect(_elements(root, 'line-break'), hasLength(1));
      expect(OfficeTextExtractor.extract(bytes, name: 'text.odt').paragraphs, [
        source,
      ]);
    },
  );

  test(
    'mixed runs and hyperlinks preserve boundaries without injected spaces',
    () async {
      final bytes = _word([
        WmlParagraph(
          inlines: [
            WmlRun(text: 'co'),
            WmlRun(text: 'operate', properties: WmlRunProps(bold: true)),
            WmlRun(
              text: '  again ',
              hyperlink: WmlHyperlink(url: 'https://example.test/'),
            ),
          ],
        ),
        WmlParagraph(inlines: [WmlRun(text: 'next')]),
      ]);
      expect(OfficeTextExtractor.extract(bytes, name: 'runs.odt').paragraphs, [
        'cooperate  again ',
        'next',
      ]);
      expect(
        await officeSearchText(bytes, 'runs.odt', 65536),
        'cooperate  again \nnext',
      );
    },
  );

  test(
    'ODT exports preserved whitespace in headers footers and frame text',
    () {
      final bytes = OdtDocumentWriter.writeBytes(
        WmlDocument(
          sections: [
            WmlSection(
              header: [
                WmlParagraph(inlines: [WmlRun(text: ' H\tH ')]),
              ],
              footer: [
                WmlParagraph(inlines: [WmlRun(text: ' F\nF ')]),
              ],
              blocks: [
                WmlFrame(
                  blocks: [
                    WmlParagraph(inlines: [WmlRun(text: '  Frame\tend ')]),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      final styles = XmlDocument.parse(_part(bytes, 'styles.xml')).root!;
      expect(_elements(styles, 's'), hasLength(4));
      expect(_elements(styles, 'tab'), hasLength(1));
      expect(_elements(styles, 'line-break'), hasLength(1));
      expect(OfficeTextExtractor.extract(bytes, name: 'frame.odt').paragraphs, [
        '  Frame\tend ',
      ]);
    },
  );

  test('ODT normalizes CRLF and CR to one authored line break each', () {
    final bytes = _word([
      WmlParagraph(inlines: [WmlRun(text: 'A\r\nB\rC\nD')]),
    ]);
    expect(OfficeTextExtractor.extract(bytes, name: 'eol.odt').paragraphs, [
      'A\nB\nC\nD',
    ]);
    final root = XmlDocument.parse(_part(bytes, 'content.xml')).root!;
    expect(_elements(root, 'line-break'), hasLength(3));
  });

  test(
    'ODP preserves shape table and notes whitespace and blank paragraphs',
    () async {
      final bytes = OdpPresentationWriter.writeBytes(
        PmlPresentation(
          slides: [
            PmlSlide(
              id: 1,
              notes: '  Note\tend ',
              shapes: [
                PmlShape(id: 2, name: 'Text', text: ' Head\tA  B \n\nTail '),
                PmlShape(
                  id: 3,
                  name: 'Table',
                  table: PmlTable(
                    rows: [
                      [PmlTableCell(text: '  Cell\tend ')],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      _saveFixture('slide-text.odp', bytes);
      final extract = OfficeTextExtractor.extract(bytes, name: 'text.odp');
      expect(extract.slides.single.title, ' Head\tA  B ');
      expect(extract.slides.single.body, ['', 'Tail ', '  Note\tend ']);
      expect(extract.slides.single.tables, [
        [
          ['  Cell\tend '],
        ],
      ]);
      expect(
        await officeSearchText(bytes, 'text.odp', 65536),
        ' Head\tA  B \n\nTail \n  Cell\tend \n  Note\tend ',
      );
      final root = XmlDocument.parse(_part(bytes, 'content.xml')).root!;
      expect(_elements(root, 'tab'), hasLength(3));
      expect(_elements(root, 's'), isNotEmpty);
    },
  );

  test('ODP handles CRLF and lone CR as paragraph breaks', () {
    final bytes = OdpPresentationWriter.writeBytes(
      PmlPresentation(
        slides: [
          PmlSlide(
            id: 1,
            shapes: [PmlShape(id: 2, name: 'Text', text: 'A\r\nB\rC\n')],
          ),
        ],
      ),
    );
    final slide = OfficeTextExtractor.extract(
      bytes,
      name: 'eol.odp',
    ).slides.single;
    expect(slide.title, 'A');
    expect(slide.body, ['B', 'C', '']);
  });

  test(
    'native styled spans collapse literal XML whitespace across run boundaries',
    () async {
      final bytes = _native(
        '<text:p> \n alpha <text:span text:style-name="Bold"> beta\t  gamma </text:span> delta \r\n </text:p>',
      );
      expect(
        OfficeTextExtractor.extract(bytes, name: 'native.odt').paragraphs,
        ['alpha beta gamma delta'],
      );
      expect(
        await officeSearchText(bytes, 'native.odt', 65536),
        'alpha beta gamma delta',
      );
    },
  );

  test(
    'native explicit whitespace is preserved at edges and between styled runs',
    () async {
      final bytes = _native(
        '<text:p><text:s text:c="2"/>A<text:span>B</text:span><text:tab/>C<text:line-break/><text:s/>D<text:s text:c="3"/></text:p>',
      );
      const expected = '  AB\tC\n D   ';
      expect(
        OfficeTextExtractor.extract(bytes, name: 'native.odt').paragraphs,
        [expected],
      );
      expect(await officeSearchText(bytes, 'native.odt', 65536), expected);
    },
  );

  test(
    'namespace aliases CDATA Unicode and zero-count spaces are decoded',
    () async {
      final bytes = _native(
        '<text:p xmlns:t="$_textNs"><![CDATA[  A  ]]><t:s t:c="0"/><text:span><![CDATA[ B\tC ]]></text:span><t:s t:c="2"/>\u00a0مرحبا😀 &amp; &lt;</text:p>',
      );
      const expected = 'A  B C   \u00a0مرحبا😀 & <';
      expect(
        OfficeTextExtractor.extract(bytes, name: 'native.odt').paragraphs,
        [expected],
      );
      expect(await officeSearchText(bytes, 'native.odt', 65536), expected);
    },
  );

  test(
    'nonnegative space counts accept signed zero and padded values',
    () async {
      final bytes = _native(
        '<text:p>A<text:s text:c="-0"/><text:s text:c=" +0002 "/>B</text:p>',
      );
      expect(
        OfficeTextExtractor.extract(bytes, name: 'counts.odt').paragraphs,
        ['A  B'],
      );
      expect(await officeSearchText(bytes, 'counts.odt', 65536), 'A  B');
    },
  );

  test('non-ODF whitespace lookalikes do not inject spaces or tabs', () async {
    final bytes = _native(
      '<text:p>A<foreign:s foreign:c="99"/><foreign:tab/><foreign:line-break/>B</text:p>',
    );
    expect(OfficeTextExtractor.extract(bytes, name: 'native.odt').paragraphs, [
      'AB',
    ]);
    expect(await officeSearchText(bytes, 'native.odt', 65536), 'AB');
  });

  test(
    'ODF table paragraphs stay in cells with explicit paragraph separators',
    () async {
      final bytes = _native(
        '<text:p>Before</text:p><table:table><table:table-row><table:table-cell><text:p> A </text:p><text:p/><text:p>B<text:tab/>C</text:p></table:table-cell></table:table-row></table:table><text:p>After</text:p>',
      );
      final extract = OfficeTextExtractor.extract(bytes, name: 'table.odt');
      expect(extract.paragraphs, ['Before', 'After']);
      expect(extract.tables, [
        [
          ['A\n\nB\tC'],
        ],
      ]);
      expect(
        await officeSearchText(bytes, 'table.odt', 65536),
        'Before\nA\n\nB\tC\nAfter',
      );
    },
  );

  test('empty and whitespace-only ODT paragraphs remain distinct', () async {
    final bytes = _word([
      WmlParagraph(inlines: [WmlRun(text: '  \t')]),
      WmlParagraph(),
      WmlParagraph(inlines: [WmlRun(text: 'end')]),
    ]);
    expect(OfficeTextExtractor.extract(bytes, name: 'blank.odt').paragraphs, [
      '  \t',
      '',
      'end',
    ]);
    expect(await officeSearchText(bytes, 'blank.odt', 65536), '  \t\n\nend');
  });

  for (final count in ['-1', '1.5', 'letters']) {
    test('native text:s rejects invalid count $count', () async {
      final bytes = _native('<text:p>A<text:s text:c="$count"/>B</text:p>');
      expect(
        () => OfficeTextExtractor.extract(bytes, name: 'bad.odt'),
        throwsFormatException,
      );
      await expectLater(
        officeSearchText(bytes, 'bad.odt', 65536),
        throwsFormatException,
      );
    });
  }

  for (final count in ['1000000000', '999999999999999999999999999999999999']) {
    test(
      'native text:s rejects excessive count $count before expansion',
      () async {
        final bytes = _native('<text:p>A<text:s text:c="$count"/>B</text:p>');
        expect(
          () => OfficeTextExtractor.extract(bytes, name: 'huge.odt'),
          throwsFormatException,
        );
        await expectLater(
          officeSearchText(bytes, 'huge.odt', 4096),
          throwsA(isA<OfficeSearchLimitException>()),
        );
      },
    );
  }

  test('search charges repeated spaces and UTF-8 bytes cumulatively', () async {
    final bytes = _native('<text:p>😀<text:s text:c="4092"/></text:p>');
    expect((await officeSearchText(bytes, 'limit.odt', 4096)).length, 4094);
    await expectLater(
      officeSearchText(bytes, 'limit.odt', 4095),
      throwsA(isA<OfficeSearchLimitException>()),
    );
    final two = _native(
      '<text:p><text:s text:c="2048"/></text:p><text:p><text:s text:c="2048"/></text:p>',
    );
    await expectLater(
      officeSearchText(two, 'limit.odt', 4096),
      throwsA(isA<OfficeSearchLimitException>()),
    );
  });
}
