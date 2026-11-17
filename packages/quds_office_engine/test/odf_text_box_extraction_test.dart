import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/odf/odf_text.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';

String _document(String body, {String kind = 'text'}) =>
    '<office:document-content xmlns:office="$_office" '
    'xmlns:text="$_text" xmlns:draw="$_draw" xmlns:table="$_table" '
    'xmlns:foreign="urn:foreign">'
    '<office:body><office:$kind>$body</office:$kind></office:body>'
    '</office:document-content>';

String _frame(String body) =>
    '<draw:frame text:anchor-type="paragraph"><draw:text-box>'
    '$body</draw:text-box></draw:frame>';

Uint8List _archive(String xml) {
  final writer = ZipWriter();
  writer.addFile('content.xml', utf8.encode(xml));
  return writer.close();
}

Future<void> _expectBody(String body, List<String> expected) async {
  final xml = _document(body);
  final bytes = _archive(xml);
  expect(
    OfficeTextExtractor.extract(bytes, name: 'native.odt').paragraphs,
    expected,
  );
  expect(
    await officeSearchText(bytes, 'native.odt', 65536),
    expected.join('\n'),
  );
  final root = XmlDocument.parse(xml).root!;
  final before = XmlDocument(root: root).toXmlString();
  expect(readOdfText(root, OdfTextBudget()), expected.join('\n'));
  expect(XmlDocument(root: root).toXmlString(), before);
  expect(utf8.decode(ZipReader.fromBytes(bytes).read('content.xml')), xml);
}

void main() {
  for (final (extension, kind) in [('odt', 'text'), ('odp', 'presentation')]) {
    test('$extension paragraph anchors preserve text-box paragraphs', () async {
      final xml = _document(
        '<text:p>Lead</text:p><text:p>'
        '${_frame('<text:p><text:s text:c="2"/>First<text:tab/>end<text:s/>'
        '</text:p><text:p/><text:h>Last<text:line-break/>line</text:h>')}'
        '</text:p><text:p>Tail</text:p>',
        kind: kind,
      );
      final bytes = _archive(xml);
      final expected = ['Lead', '  First\tend ', '', 'Last\nline', 'Tail'];
      final result = OfficeTextExtractor.extract(
        bytes,
        name: 'native.$extension',
      );
      if (extension == 'odt') {
        expect(result.paragraphs, expected);
      } else {
        expect(result.slides.single.title, expected.first);
        expect(result.slides.single.body, expected.sublist(1));
      }
      expect(
        await officeSearchText(bytes, 'native.$extension', 65536),
        expected.join('\n'),
      );
    });
  }

  test(
    'inline text stays together before anchored stories without duplicates',
    () async {
      await _expectBody(
        '<text:p>co<text:span>op'
        '${_frame('<text:p>First box</text:p>')}erate</text:span>'
        '<text:s/>end<draw:a>${_frame('<text:p>Linked box</text:p>')}</draw:a>'
        '</text:p><text:p>Tail</text:p>',
        ['cooperate end', 'First box', 'Linked box', 'Tail'],
      );
    },
  );

  test(
    'literal whitespace spans a frame without adding a word break',
    () async {
      await _expectBody(
        '<text:p> before \n${_frame('<text:p>Box</text:p>')} '
        '<text:span> after </text:span></text:p>',
        ['before after', 'Box'],
      );
    },
  );

  test('nested text boxes each emit their own story once', () async {
    final inner = _frame('<text:p>Inner<text:tab/>end</text:p>');
    final outer = _frame(
      '<text:p>Outer<text:s/>${inner}tail</text:p>'
      '<text:p>${_frame('<text:p>Deep</text:p>')}</text:p>'
      '<text:p>Last outer</text:p>',
    );
    await _expectBody('<text:p>Root${outer}end</text:p>', [
      'Rootend',
      'Outer tail',
      'Inner\tend',
      'Deep',
      'Last outer',
    ]);
  });

  test(
    'empty authored paragraphs and explicit anchor whitespace are retained',
    () async {
      await _expectBody(
        '<text:p/><text:p> \n${_frame('<text:p/><text:p>A</text:p>')} </text:p>'
        '<text:p><text:s text:c="2"/><text:tab/>'
        '${_frame('<text:p>B</text:p>')}</text:p><text:p/>',
        ['', '', 'A', '  \t', 'B', ''],
      );
    },
  );

  for (final (extension, kind) in [('odt', 'text'), ('ods', 'spreadsheet')]) {
    test(
      '$extension text-box stories stay in their enclosing table cell',
      () async {
        final bytes = _archive(
          _document(
            '<table:table><table:table-row><table:table-cell>'
            '<text:p>Cell${_frame('<text:p>Box</text:p><text:p/>')}end</text:p>'
            '<text:p>Tail</text:p></table:table-cell>'
            '<table:covered-table-cell><text:p>'
            '${_frame('<text:p><text:s text:c="-1"/>Hidden</text:p>')}'
            '</text:p></table:covered-table-cell></table:table-row></table:table>',
            kind: kind,
          ),
        );
        final result = OfficeTextExtractor.extract(
          bytes,
          name: 'cell.$extension',
        );
        expect(result.tables, [
          [
            ['Cellend\nBox\n\nTail'],
          ],
        ]);
        expect(result.paragraphs, isEmpty);
        if (extension == 'ods') {
          expect(result.sheets.single.rows, result.tables.single);
        }
        expect(
          await officeSearchText(bytes, 'cell.$extension', 65536),
          'Cellend\nBox\n\nTail',
        );
      },
    );
  }

  test('frame and text-box recognition use namespace identity', () async {
    await _expectBody(
      '<text:p>A<d:frame xmlns:d="$_draw"><d:text-box>'
      '<text:p>Alias</text:p></d:text-box></d:frame>'
      '<draw:frame xmlns:draw="urn:foreign"><d:text-box xmlns:d="$_draw">'
      '<text:p>Hidden frame namespace</text:p></d:text-box></draw:frame>'
      '<draw:frame><foreign:text-box><text:p>Hidden box namespace</text:p>'
      '</foreign:text-box></draw:frame>'
      '<foreign:span>${_frame('<text:p>Hidden foreign wrapper</text:p>')}'
      '</foreign:span>B</text:p>',
      ['AB', 'Alias'],
    );
  });

  test('image metadata is not mistaken for text-box text', () async {
    await _expectBody(
      '<text:p>A<draw:frame><draw:image><text:p>Hidden image text</text:p>'
      '</draw:image><foreign:desc><text:p>Hidden description</text:p>'
      '</foreign:desc></draw:frame>B</text:p>',
      ['AB'],
    );
  });

  test('annotations and covered cells suppress all nested frame content', () async {
    final hidden = _frame(
      '<text:p><text:s text:c="999999999999999999999999"/>Hidden</text:p>',
    );
    await _expectBody(
      '<text:p>A<office:annotation><text:p>$hidden</text:p>'
      '</office:annotation><table:covered-table-cell><text:p>$hidden</text:p>'
      '</table:covered-table-cell>B'
      '${_frame('<office:annotation><text:p>$hidden</text:p></office:annotation>'
      '<table:table><table:table-row><table:table-cell><text:p>Visible</text:p>'
      '</table:table-cell><table:covered-table-cell><text:p>$hidden</text:p>'
      '</table:covered-table-cell></table:table-row></table:table>')}'
      '</text:p>',
      ['AB', 'Visible'],
    );
  });

  test(
    'inline notes and ruby annotations do not leak their anchored stories',
    () async {
      final hidden = _frame('<text:p>Hidden</text:p>');
      await _expectBody(
        '<text:p>A<text:note><text:note-citation>1</text:note-citation>'
        '<text:note-body><text:p>$hidden</text:p></text:note-body></text:note>B'
        '<text:ruby><text:ruby-base>R${_frame('<text:p>Ruby base box</text:p>')}'
        '</text:ruby-base><text:ruby-text>$hidden</text:ruby-text></text:ruby>C'
        '<text:soft-page-break>$hidden</text:soft-page-break></text:p>',
        ['ABRC', 'Ruby base box'],
      );
    },
  );

  test(
    'empty and annotation-only text boxes do not trigger raw fallback',
    () async {
      await _expectBody(
        '<text:p>${_frame('')}</text:p>'
        '<text:p>${_frame('<office:annotation><text:p>Hidden</text:p>'
        '</office:annotation>')}</text:p>',
        [],
      );
    },
  );

  test(
    'text-box whitespace and separators share the cumulative UTF-8 budget',
    () async {
      final xml = _document(
        '<text:p>${_frame('<text:p>é<text:s text:c="2"/>😀</text:p>'
        '<text:p/><text:p>B</text:p>')}</text:p>',
      );
      const expected = 'é  😀\n\nB';
      final size = utf8.encode(expected).length;
      expect(
        readOdfText(XmlDocument.parse(xml).root!, OdfTextBudget(size)),
        expected,
      );
      expect(
        () =>
            readOdfText(XmlDocument.parse(xml).root!, OdfTextBudget(size - 1)),
        throwsA(isA<OdfTextLimitException>()),
      );
      final bytes = _archive(
        _document(
          '<text:p>${_frame('<text:p><text:s text:c="65536"/></text:p>'
          '<text:p/>')}'
          '</text:p>',
        ),
      );
      await expectLater(
        officeSearchText(bytes, 'budget.odt', 65536),
        throwsA(isA<OfficeSearchLimitException>()),
      );
    },
  );

  for (final count in ['-1', 'letters', '999999999999999999999999']) {
    test('visible text-box whitespace rejects invalid count $count', () async {
      final bytes = _archive(
        _document(
          '<text:p>${_frame('<text:p><text:s text:c="$count"/>'
          '</text:p>')}</text:p>',
        ),
      );
      expect(
        () => OfficeTextExtractor.extract(bytes, name: 'invalid.odt'),
        throwsFormatException,
      );
      await expectLater(
        officeSearchText(bytes, 'invalid.odt', 65536),
        throwsFormatException,
      );
    });
  }

  test('exported leading frames keep their paragraphs searchable', () async {
    final bytes = OdtDocumentWriter.writeBytes(
      WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlFrame(
                blocks: [
                  WmlParagraph(inlines: [WmlRun(text: '  Frame\tend ')]),
                  WmlParagraph(),
                  WmlParagraph(inlines: [WmlRun(text: 'Last')]),
                ],
              ),
              WmlParagraph(inlines: [WmlRun(text: 'Following')]),
            ],
          ),
        ],
      ),
    );
    final expected = ['  Frame\tend ', '', 'Last', 'Following'];
    expect(
      OfficeTextExtractor.extract(bytes, name: 'export.odt').paragraphs,
      expected,
    );
    expect(
      await officeSearchText(bytes, 'export.odt', 65536),
      expected.join('\n'),
    );
  });
}
