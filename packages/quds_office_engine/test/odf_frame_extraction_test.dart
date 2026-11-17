import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/odf/odf_text.dart';
import 'package:test/test.dart';

const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';

String _document(String body) =>
    '<office:document-content xmlns:office="$_office" '
    'xmlns:draw="$_draw" xmlns:table="$_table" xmlns:text="$_text" '
    'xmlns:foreign="urn:foreign">'
    '<office:body><office:text>$body</office:text></office:body>'
    '</office:document-content>';

Uint8List _archive(String xml) {
  final writer = ZipWriter();
  writer.addFile('content.xml', utf8.encode(xml));
  return writer.close();
}

String _frame(String blocks) =>
    '<draw:frame><draw:text-box>$blocks</draw:text-box></draw:frame>';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

void main() {
  test(
    'section-owning frame keeps each authored paragraph without an extra anchor',
    () async {
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [_paragraph('Before')]),
          WmlSection(
            blocks: [
              WmlFrame(
                blocks: [
                  _paragraph('  Frame\tend '),
                  WmlParagraph(),
                  _paragraph('Tail\nline'),
                ],
              ),
              _paragraph('After'),
            ],
          ),
        ],
      );
      final bytes = OdtDocumentWriter.writeBytes(document);
      final content = XmlDocument.parse(
        OpcPackage.openBytes(bytes).getPart('/content.xml')!.readText(),
      ).root!;
      final body = content
          .firstChild('body', namespaceUri: _office)!
          .firstChild('text', namespaceUri: _office)!;
      final anchor = body.childElements.elementAt(1);
      expect(anchor.localName, 'p');
      expect(anchor.getAttribute('style-name', namespaceUri: _text), isNotNull);
      expect(anchor.firstChild('frame', namespaceUri: _draw), isNotNull);
      expect(
        OfficeTextExtractor.extract(bytes, name: 'section.odt').paragraphs,
        ['Before', '  Frame\tend ', '', 'Tail\nline', 'After'],
      );
      expect(
        await officeSearchText(bytes, 'section.odt', 65536),
        'Before\n  Frame\tend \n\nTail\nline\nAfter',
      );
      expect(document.sections.last.blocks, hasLength(2));
    },
  );

  test(
    'mixed inline text stays together before separate nested frame stories',
    () async {
      final bytes = _archive(
        _document(
          '<text:p>Before<text:s/>${_frame('<text:p>One</text:p>')}'
          '<text:span>After</text:span>'
          '${_frame('<text:p>Two${_frame('<text:p>Nested</text:p>')}</text:p>')}'
          '</text:p><text:p>Last</text:p>',
        ),
      );
      expect(OfficeTextExtractor.extract(bytes, name: 'mixed.odt').paragraphs, [
        'Before After',
        'One',
        'Two',
        'Nested',
        'Last',
      ]);
      expect(
        await officeSearchText(bytes, 'mixed.odt', 65536),
        'Before After\nOne\nTwo\nNested\nLast',
      );
    },
  );

  test(
    'frame tables keep cell structure and do not become body paragraphs',
    () async {
      final bytes = _archive(
        _document(
          '<text:p>${_frame('<text:p>Frame lead</text:p>'
          '<table:table><table:table-row><table:table-cell>'
          '<text:p>Cell<text:tab/>A</text:p><text:p/>'
          '<text:p>${_frame('<text:p>Cell frame</text:p>')}</text:p>'
          '</table:table-cell><table:covered-table-cell>'
          '<text:p>HIDDEN CELL</text:p></table:covered-table-cell>'
          '<table:table-cell><text:p>B</text:p></table:table-cell>'
          '</table:table-row></table:table><text:p>Frame tail</text:p>')}</text:p>'
          '<text:p>After</text:p>',
        ),
      );
      final result = OfficeTextExtractor.extract(
        bytes,
        name: 'table-frame.odt',
      );
      expect(result.paragraphs, ['Frame lead', 'Frame tail', 'After']);
      expect(result.tables, [
        [
          ['Cell\tA\n\nCell frame', 'B'],
        ],
      ]);
      expect(
        await officeSearchText(bytes, 'table-frame.odt', 65536),
        'Frame lead\nCell\tA\n\nCell frame\nB\nFrame tail\nAfter',
      );
    },
  );

  for (final empty in [false, true]) {
    test(
      'linked table-only frame has no synthetic paragraph: empty=$empty',
      () async {
        final table = empty
            ? '<table:table/>'
            : '<table:table><table:table-row><table:table-cell>'
                  '<text:p>Cell</text:p></table:table-cell>'
                  '</table:table-row></table:table>';
        final xml = _document(
          '<text:p>Before</text:p><text:p><draw:a>${_frame(table)}</draw:a>'
          '</text:p><text:p>After</text:p>',
        );
        final bytes = _archive(xml);
        final result = OfficeTextExtractor.extract(
          bytes,
          name: 'linked-table.odt',
        );
        expect(result.paragraphs, ['Before', 'After']);
        expect(result.tables, [
          if (empty)
            <List<String>>[]
          else
            [
              ['Cell'],
            ],
        ]);
        final expected = empty ? 'Before\nAfter' : 'Before\nCell\nAfter';
        expect(
          await officeSearchText(bytes, 'linked-table.odt', 65536),
          expected,
        );
        final budget = OdfTextBudget(utf8.encode(expected).length);
        expect(readOdfText(XmlDocument.parse(xml).root!, budget), expected);
        expect(budget.remaining, 0);
        expect(
          utf8.decode(ZipReader.fromBytes(bytes).read('content.xml')),
          xml,
        );
      },
    );
  }

  test(
    'linked frame metadata and page-break wrappers cannot spend text budget',
    () async {
      final hidden = _frame(
        '<text:p><text:s text:c="999999999999999999999999"/>Hidden</text:p>',
      );
      final xml = _document(
        '<text:p>A<draw:a><draw:frame><draw:image>$hidden</draw:image>'
        '</draw:frame></draw:a><text:soft-page-break>$hidden</text:soft-page-break>'
        '<draw:a>${_frame('<text:p>B</text:p>')}</draw:a></text:p>',
      );
      final bytes = _archive(xml);
      expect(
        OfficeTextExtractor.extract(
          bytes,
          name: 'linked-hidden.odt',
        ).paragraphs,
        ['A', 'B'],
      );
      expect(await officeSearchText(bytes, 'linked-hidden.odt', 65536), 'A\nB');
      final budget = OdfTextBudget(3);
      expect(readOdfText(XmlDocument.parse(xml).root!, budget), 'A\nB');
      expect(budget.remaining, 0);
    },
  );

  test(
    'hidden inline stories cannot expose frames or spend the text budget',
    () async {
      final hidden = _frame(
        '<text:p><text:s text:c="999999999999999999999999999999"/>'
        '<text:s text:c="-1"/>HIDDEN</text:p>',
      );
      final xml = _document(
        '<text:p><office:annotation>$hidden</office:annotation>'
        '<text:note><text:note-body>$hidden</text:note-body></text:note>'
        '<table:covered-table-cell>$hidden</table:covered-table-cell>'
        '<text:ruby><text:ruby-base>A</text:ruby-base>'
        '<text:ruby-text>$hidden</text:ruby-text></text:ruby>'
        '${_frame('<office:annotation>$hidden</office:annotation>'
        '<text:note><text:note-body>$hidden</text:note-body></text:note>'
        '<table:covered-table-cell>$hidden</table:covered-table-cell>'
        '<text:p>B</text:p>')}</text:p>',
      );
      final bytes = _archive(xml);
      expect(
        OfficeTextExtractor.extract(bytes, name: 'hidden.odt').paragraphs,
        ['A', 'B'],
      );
      expect(await officeSearchText(bytes, 'hidden.odt', 65536), 'A\nB');
      final root = XmlDocument.parse(xml).root!;
      final before = XmlDocument(root: root).toXmlString();
      expect(readOdfText(root, OdfTextBudget(3)), 'A\nB');
      expect(XmlDocument(root: root).toXmlString(), before);
    },
  );

  test(
    'drawing namespace aliases work while foreign inline frames stay hidden',
    () async {
      final bytes = _archive(
        _document(
          '<text:p><d:frame xmlns:d="$_draw"><d:text-box>'
          '<text:p>Visible</text:p></d:text-box></d:frame>'
          '<draw:frame xmlns:draw="urn:foreign"><draw:text-box>'
          '<text:p>HIDDEN SHADOW</text:p></draw:text-box></draw:frame>'
          '<foreign:frame><foreign:text-box><text:p>HIDDEN FOREIGN</text:p>'
          '</foreign:text-box></foreign:frame></text:p>',
        ),
      );
      expect(
        OfficeTextExtractor.extract(bytes, name: 'namespaces.odt').paragraphs,
        ['Visible'],
      );
      expect(await officeSearchText(bytes, 'namespaces.odt', 65536), 'Visible');
    },
  );

  test(
    'authored blanks survive while empty text-box anchors add no paragraph',
    () async {
      final bytes = _archive(
        _document(
          '<text:p/><text:p>${_frame('')}</text:p>'
          '<text:p>${_frame('<text:p/>')}</text:p>'
          '<text:p><text:s/><text:tab/>${_frame('<text:p>X</text:p>')}</text:p>'
          '<text:p><draw:frame><draw:image/></draw:frame></text:p>',
        ),
      );
      expect(OfficeTextExtractor.extract(bytes, name: 'blank.odt').paragraphs, [
        '',
        '',
        ' \t',
        'X',
        '',
      ]);
      expect(await officeSearchText(bytes, 'blank.odt', 65536), '\n\n \t\nX\n');
    },
  );

  for (final count in ['-1', '1000000000']) {
    test(
      'visible textbox space count $count retains expansion validation',
      () async {
        final bytes = _archive(
          _document(
            '<text:p>${_frame('<text:p><text:s text:c="$count"/></text:p>')}</text:p>',
          ),
        );
        expect(
          () => OfficeTextExtractor.extract(bytes, name: 'invalid.odt'),
          throwsFormatException,
        );
        await expectLater(
          officeSearchText(bytes, 'invalid.odt', 65536),
          count == '-1'
              ? throwsFormatException
              : throwsA(isA<OfficeSearchLimitException>()),
        );
      },
    );
  }

  test('frame paragraphs share the cumulative UTF-8 and separator budget', () {
    final root = XmlDocument.parse(
      _document(
        '<text:p>${_frame('<text:p>😀</text:p><text:p>B</text:p>')}</text:p>',
      ),
    ).root!;
    final exact = OdfTextBudget(6);
    expect(readOdfText(root, exact), '😀\nB');
    expect(exact.remaining, 0);
    expect(
      () => readOdfText(root, OdfTextBudget(5)),
      throwsA(isA<OdfTextLimitException>()),
    );
  });
}
