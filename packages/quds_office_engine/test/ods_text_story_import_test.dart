import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';

Uint8List _ods(String cell) {
  final zip = ZipWriter();
  zip.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content xmlns:office="$_office" xmlns:table="$_table" '
      'xmlns:text="$_text" xmlns:draw="$_draw" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<office:body><office:spreadsheet><table:table table:name="Stories">'
      '<table:table-row><table:table-cell>$cell</table:table-cell>'
      '</table:table-row></table:table></office:spreadsheet></office:body>'
      '</office:document-content>',
    ),
  );
  return zip.close();
}

String _frame(String contents) =>
    '<draw:frame><draw:text-box>$contents</draw:text-box></draw:frame>';

void main() {
  test(
    'ODS anchored text boxes import each story once and survive XLSX save',
    () async {
      final bytes = _ods(
        '<text:p>Cell${_frame('<text:p><text:s text:c="2"/>Box<text:tab/>'
        'end<text:s/></text:p><text:p/>')}tail</text:p>'
        '<text:p>Last</text:p>',
      );
      final raw = utf8.decode(ZipReader.fromBytes(bytes).read('content.xml'));
      const expected = 'Celltail\n  Box\tend \n\nLast';
      final book = OdsSheetReader.readBytes(bytes);
      expect(book.firstSheet.cellA1('A1').value, expected);
      expect(
        OfficeTextExtractor.extract(
          bytes,
          name: 'stories.ods',
        ).sheets.single.rows,
        [
          [expected],
        ],
      );
      expect(await officeSearchText(bytes, 'stories.ods', 65536), expected);
      final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
      expect(
        SheetDeserializer().readBytes(saved).firstSheet.cellA1('A1').value,
        expected,
      );
      expect(utf8.decode(ZipReader.fromBytes(bytes).read('content.xml')), raw);
    },
  );

  test(
    'ODS nested frame paragraphs keep their own order without duplication',
    () {
      final bytes = _ods(
        '<text:p>Root${_frame('<text:p>Outer${_frame('<text:p>Inner</text:p>')}tail</text:p>'
        '<text:p>Last box</text:p>')}end</text:p>',
      );
      expect(
        OdsSheetReader.readBytes(bytes).firstSheet.cellA1('A1').value,
        'Rootend\nOutertail\nInner\nLast box',
      );
    },
  );

  test(
    'ODS annotation text boxes retain their own story and cell ownership',
    () {
      final bytes = _ods(
        '<text:p>Current cell</text:p>'
        '<office:annotation><dc:creator>Éva</dc:creator>'
        '<text:p>Comment${_frame('<text:p>Box</text:p>')}tail</text:p>'
        '</office:annotation>',
      );
      final book = OdsSheetReader.readBytes(bytes);
      expect(book.firstSheet.cellA1('A1').value, 'Current cell');
      expect(book.firstSheet.comments.single.text, 'Commenttail\nBox');
      expect(book.firstSheet.comments.single.author, 'Éva');
      expect(book.firstSheet.comments.single.ref.a1, 'A1');
    },
  );

  test(
    'ODS cells preserve current ruby text without note or pronunciation payload',
    () {
      final bytes = _ods(
        '<text:p>A<text:note text:id="n1" text:note-class="footnote">'
        '<text:note-citation>1</text:note-citation><text:note-body>'
        '<text:p>HIDDEN NOTE</text:p></text:note-body></text:note>B'
        '<text:ruby><text:ruby-base>漢字</text:ruby-base>'
        '<text:ruby-text>HIDDEN PRONUNCIATION</text:ruby-text></text:ruby>C</text:p>',
      );
      expect(
        OdsSheetReader.readBytes(bytes).firstSheet.cellA1('A1').value,
        'AB漢字C',
      );
    },
  );

  test(
    'ODS comments still reject ambiguous ownership after story decoding',
    () {
      final bytes = _ods(
        '<text:p>A<office:annotation><text:p>Nested comment</text:p>'
        '</office:annotation>B</text:p>',
      );
      expect(
        () => OdsSheetReader.readBytes(bytes),
        throwsA(isA<OdsSheetFormatException>()),
      );
    },
  );

  test(
    'ODS text keeps the established character limit for non-ASCII cells',
    () {
      final text = '漢' * (1024 * 1024);
      final bytes = _ods('<text:p>$text</text:p>');
      expect(
        OdsSheetReader.readBytes(bytes).firstSheet.cellA1('A1').value,
        text,
      );
      expect(
        () => OdsSheetReader.readBytes(_ods('<text:p>${text}A</text:p>')),
        throwsA(isA<OdsSheetFormatException>()),
      );
    },
  );
}
