import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _number = 'urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0';

Uint8List _ods(
  String tables, {
  String styles = '',
  String? namedStyles,
  Map<String, List<int>> parts = const <String, List<int>>{},
  String extra = '',
}) {
  final zip = ZipWriter();
  const bindings =
      'xmlns:o="$_office" xmlns:t="$_table" '
      'xmlns:x="$_text" xmlns:s="$_style" xmlns:f="$_fo" xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:e="urn:test:extension" '
      'xmlns:dr="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
      'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" '
      'xmlns:xl="http://www.w3.org/1999/xlink" '
      'xmlns:cal="urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0"';
  zip.addFile(
    'content.xml',
    utf8.encode(
      '<o:document-content $bindings>'
      '<o:automatic-styles>$styles</o:automatic-styles>'
      '<o:body><o:spreadsheet>$tables$extra</o:spreadsheet></o:body>'
      '</o:document-content>',
    ),
  );
  for (final entry in parts.entries) {
    zip.addFile(entry.key, entry.value);
  }
  if (namedStyles != null) {
    zip.addFile(
      'styles.xml',
      utf8.encode(
        '<o:document-styles $bindings><o:styles>$namedStyles</o:styles>'
        '</o:document-styles>',
      ),
    );
  }
  return zip.close();
}

String _value(String value) =>
    '<t:table-cell o:value-type="string"><x:p>$value</x:p></t:table-cell>';

String _xmlAttribute(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('"', '&quot;');

Matcher get _invalidOds => throwsA(isA<OdsSheetFormatException>());

void annotationAndAuthoredDateTests() {
  test(
    'repeated annotations stay separate from cell values through save',
    () async {
      final book = OdsSheetReader.readBytes(
        _ods(
          '<t:table><t:table-row t:number-rows-repeated="2">'
          '<t:table-cell t:number-columns-repeated="2">'
          '<o:annotation><dc:creator>Éva</dc:creator>'
          '<x:p>First<x:s x:c="2"/>note</x:p><x:p>Next</x:p>'
          '</o:annotation></t:table-cell>'
          '<t:table-cell><x:p>Visible value</x:p>'
          '<o:annotation><x:p>Private note</x:p></o:annotation>'
          '</t:table-cell></t:table-row></t:table>',
        ),
      );
      void check(SmlWorkbook value) {
        final sheet = value.firstSheet;
        expect(sheet.comments.map((comment) => comment.ref.a1), [
          'A1',
          'B1',
          'C1',
          'A2',
          'B2',
          'C2',
        ]);
        for (final ref in ['A1', 'B1', 'A2', 'B2']) {
          final comment = sheet.comments.singleWhere(
            (note) => note.ref.a1 == ref,
          );
          expect(comment.text, 'First  note\nNext');
          expect(comment.author, 'Éva');
          expect(sheet.cellA1(ref).value, isNull);
        }
        for (final ref in ['C1', 'C2']) {
          expect(sheet.cellA1(ref).value, 'Visible value');
          final comment = sheet.comments.singleWhere(
            (note) => note.ref.a1 == ref,
          );
          expect(comment.text, 'Private note');
          expect(comment.author, 'Quds Office');
        }
      }

      check(book);
      check(
        SheetDeserializer().readBytes(
          await OfficeIsolateSave.workbook(book, recalculate: false),
        ),
      );
    },
  );

  test(
    'ambiguous and foreign annotations are refused without inventing a value',
    () {
      for (final contents in [
        '<o:annotation><x:p>One</x:p></o:annotation>'
            '<o:annotation><x:p>Two</x:p></o:annotation>',
        '<e:annotation><x:p>Foreign note</x:p></e:annotation>',
        '<x:p><o:annotation><x:p>Nested note</x:p></o:annotation></x:p>',
        '<o:annotation><e:creator>Wrong namespace</e:creator>'
            '<x:p>Note</x:p></o:annotation>',
        '<o:annotation><dc:creator>One</dc:creator>'
            '<dc:creator>Two</dc:creator><x:p>Note</x:p></o:annotation>',
      ]) {
        expect(
          () => OdsSheetReader.readBytes(
            _ods(
              '<t:table><t:table-row><t:table-cell>$contents</t:table-cell>'
              '</t:table-row></t:table>',
            ),
          ),
          _invalidOds,
          reason: contents,
        );
      }
    },
  );

  test(
    'repeated annotation text and author consume the expanded text budget',
    () {
      for (final note in [
        '<x:p><x:s x:c="4096"/></x:p>',
        '<dc:creator>${'a' * 4096}</dc:creator><x:p>x</x:p>',
      ]) {
        expect(
          () => OdsSheetReader.readBytes(
            _ods(
              '<t:table><t:table-row><t:table-cell t:number-columns-repeated="2048">'
              '<o:annotation>$note</o:annotation></t:table-cell>'
              '</t:table-row></t:table>',
            ),
          ),
          _invalidOds,
        );
      }
    },
  );

  test('annotation-only cells obey materialized-cell and grid bounds', () {
    for (final dimensions in [
      (rows: 51, columns: 4096),
      (rows: 1, columns: 4097),
      (rows: 100001, columns: 1),
    ]) {
      expect(
        () => OdsSheetReader.readBytes(
          _ods(
            '<t:table><t:table-row t:number-rows-repeated="${dimensions.rows}">'
            '<t:table-cell t:number-columns-repeated="${dimensions.columns}">'
            '<o:annotation/></t:table-cell></t:table-row></t:table>',
          ),
        ),
        _invalidOds,
      );
    }
  });

  test('covered cells cannot silently discard annotations', () {
    expect(
      () => OdsSheetReader.readBytes(
        _ods(
          '<t:table><t:table-row><t:table-cell t:number-columns-spanned="2"/>'
          '<t:covered-table-cell><o:annotation><x:p>Hidden note</x:p>'
          '</o:annotation></t:covered-table-cell></t:table-row></t:table>',
        ),
      ),
      _invalidOds,
    );
  });

  test('authored date literals retain spaces quotes and format-like text', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table><t:table-row><t:table-cell t:style-name="date" '
        'o:value-type="date" o:date-value="2024-03-04T13:45:00"/>'
        '</t:table-row></t:table>',
        styles:
            '<n:date-style xmlns:n="$_number" s:name="dateFormat">'
            '<e:year/><n:year n:style="long"/><n:text>-</n:text>'
            '<n:month n:style="long"/><n:text>-</n:text><n:day n:style="long"/>'
            '<n:text>   </n:text><n:hours n:style="long"/>'
            '<n:text>:</n:text><n:minutes n:style="long"/><n:text/>'
            r'<n:text> "m;\H"</n:text>'
            '</n:date-style><s:style s:name="date" s:family="table-cell" '
            's:data-style-name="dateFormat"/>',
      ),
    );
    void check(SmlWorkbook value) {
      final cell = value.firstSheet.cellA1('A1');
      expect(
        value.styles!.format(cell.value, cell.styleIndex),
        r'2024-03-04   13:45 "m;\H"',
      );
    }

    check(book);
    check(
      SheetDeserializer().readBytes(
        await OfficeIsolateSave.workbook(book, recalculate: false),
      ),
    );
  });

  test(
    'authored textual dates use namespace-aware widths and weekday names',
    () {
      final book = OdsSheetReader.readBytes(
        _ods(
          '<t:table><t:table-row><t:table-cell t:style-name="date" '
          'o:value-type="date" o:date-value="2024-01-02"/>'
          '</t:table-row></t:table>',
          styles:
              '<n:date-style xmlns:n="$_number" s:name="dateFormat">'
              '<n:day-of-week n:style="long"/><n:text>, </n:text>'
              '<n:month e:textual="false" n:textual="1" n:style="long"/>'
              '<n:text> </n:text><n:day e:style="long" n:style="short"/>'
              '<n:text>, </n:text><n:year n:style="long"/>'
              '</n:date-style><s:style s:name="date" s:family="table-cell" '
              's:data-style-name="dateFormat"/>',
        ),
      );
      final cell = book.firstSheet.cellA1('A1');
      expect(
        book.styles!.format(cell.value, cell.styleIndex),
        'Tuesday, January 2, 2024',
      );
    },
  );
}

/// Synthetic LibreOffice-generated ODS (values, formulas, styles, merge).
void main() {
  annotationAndAuthoredDateTests();
  edgeTests();
  defaultAndTimeTests();
  defaultStyleTests();
  defaultGeometryTests();
  hiddenStateTests();
  conditionalFormatTests();
  validationTests();
  metadataTests();
  // Retain the independently added external continuation's formula cases.
  for (final formula in const {
    'of:="a;b"': '"a;b"',
    'of:="literal [.A1];COM.MICROSOFT.SUM"':
        '"literal [.A1];COM.MICROSOFT.SUM"',
    'of:=IF([.A1]="a;b";"say ""[.B2];""";COM.MICROSOFT.SUM([.A1:.A2];1))':
        'IF(A1="a;b","say ""[.B2];""",SUM(A1:A2,1))',
    'of:=CONCATENATE("";"a;b";"[.A1]")': 'CONCATENATE("","a;b","[.A1]")',
    "of:=SUM(['Semi;Colon'.A1];1)": "SUM('Semi;Colon'!A1,1)",
    "of:=SUM(['COM.MICROSOFT.Data'.A1];1)": "SUM('COM.MICROSOFT.Data'!A1,1)",
  }.entries) {
    test('formula roundtrip preserves imported syntax: ${formula.key}', () async {
      final book = OdsSheetReader.readBytes(
        _ods(
          '<t:table><t:table-row><t:table-cell o:value-type="string" '
          'o:string-value="cached" t:formula="${_xmlAttribute(formula.key)}"/>'
          '</t:table-row></t:table>',
        ),
      );
      final reopened = SheetDeserializer().readBytes(
        await OfficeIsolateSave.workbook(book, recalculate: false),
      );
      for (final current in [book, reopened]) {
        expect(current.firstSheet.cellA1('A1').formula, formula.value);
        expect(current.firstSheet.cellA1('A1').value, 'cached');
      }
    });
  }

  for (final prefix in const ['COM.MICROSOFT.', 'ORG.OPENOFFICE.']) {
    test('formula namespace $prefix only changes at a token boundary', () async {
      for (final formula in {
        'of:=${prefix}SUM(1;2)': 'SUM(1,2)',
        'of:=X${prefix}SUM(1;2)': 'X${prefix}SUM(1,2)',
        'of:=S${prefix}UM(1;2)': 'S${prefix}UM(1,2)',
        'of:=_${prefix}SUM(1;2)': '_${prefix}SUM(1,2)',
        'of:=SUM(1;${prefix}SUM(2;3))': 'SUM(1,SUM(2,3))',
        'of:="X${prefix}SUM;[.A1]"': '"X${prefix}SUM;[.A1]"',
        "of:=SUM(['X${prefix}Data'.A1];1)": "SUM('X${prefix}Data'!A1,1)",
      }.entries) {
        final book = OdsSheetReader.readBytes(
          _ods(
            '<t:table><t:table-row><t:table-cell o:value-type="string" '
            'o:string-value="cached" t:formula="${_xmlAttribute(formula.key)}"/>'
            '</t:table-row></t:table>',
          ),
        );
        final reopened = SheetDeserializer().readBytes(
          await OfficeIsolateSave.workbook(book, recalculate: false),
        );
        for (final current in [book, reopened]) {
          expect(
            current.firstSheet.cellA1('A1').formula,
            formula.value,
            reason: formula.key,
          );
          expect(current.firstSheet.cellA1('A1').value, 'cached');
        }
      }
    });
  }

  test(
    'declines a stored cell where a horizontal covered token is missing',
    () {
      expect(
        () => OdsSheetReader.readBytes(
          _ods(
            '<t:table><t:table-row><t:table-cell t:number-columns-spanned="2" '
            'o:value-type="string"><x:p>Wide</x:p></t:table-cell>'
            '${_value('hidden value')}</t:table-row></t:table>',
          ),
        ),
        _invalidOds,
      );
    },
  );

  test('declines a stored cell inside an earlier vertical merged region', () {
    expect(
      () => OdsSheetReader.readBytes(
        _ods(
          '<t:table><t:table-row><t:table-cell t:number-rows-spanned="2" '
          'o:value-type="string"><x:p>Tall</x:p></t:table-cell></t:table-row>'
          '<t:table-row>${_value('hidden value')}</t:table-row></t:table>',
        ),
      ),
      _invalidOds,
    );
  });

  test(
    'annotations retain coordinates and do not leak into cell values',
    () async {
      const annotation = '<o:annotation><x:p>Review this</x:p></o:annotation>';
      final book = OdsSheetReader.readBytes(
        _ods(
          '<t:table><t:table-row t:number-rows-repeated="2">'
          '<t:table-cell o:value-type="string" t:number-columns-repeated="2">'
          '<x:p>Actual value</x:p>$annotation</t:table-cell>'
          '<t:table-cell>$annotation</t:table-cell>'
          '</t:table-row></t:table>',
        ),
      );
      for (final current in [book, await _roundTrip(book)]) {
        final sheet = current.firstSheet;
        expect(sheet.cellA1('A1').asString, 'Actual value');
        expect(sheet.cellA1('C1').asString, isEmpty);
        expect(sheet.comments.map((comment) => comment.ref.a1).toSet(), {
          'A1',
          'B1',
          'C1',
          'A2',
          'B2',
          'C2',
        });
        expect(
          sheet.comments.every((comment) => comment.text == 'Review this'),
          isTrue,
        );
      }
      expect(
        () => OdsSheetReader.readBytes(
          _ods(
            '<t:table><t:table-row t:number-rows-repeated="10001">'
            '<t:table-cell>$annotation</t:table-cell></t:table-row></t:table>',
          ),
        ),
        _invalidOds,
      );
    },
  );

  final bytes = File('test/fixtures/fidelity/legacy-sheet.ods')
      .readAsBytesSync();

  test('reads ODS values, formulas, styles and merges', () {
    final book = OdsSheetReader.readBytes(bytes);
    expect(book.sheets.map((sheet) => sheet.name), ['Data', 'Notes']);
    final data = book.sheets.first;

    expect(data.cellA1('A1').asString, 'Item');
    expect(data.cellA1('A1').fontBold, isTrue);
    expect(data.cellA1('A1').fontSize, 12);
    expect(data.cellA1('A1').fillRgb, '4472C4');
    expect(data.cellA1('A1').fontRgb, 'FFFFFF');

    expect(data.cellA1('B2').value, 2);
    expect(data.cellA1('C2').value, 3.5);
    final total = data.cellA1('D2');
    expect(total.formula, 'B2*C2');
    expect(total.value, 7);
    expect(total.type, SmlCellType.formula);
    expect(data.cellA1('D6').formula, 'SUM(D2:D4)');

    expect(data.merges.single.origin.a1, 'A8');
    expect(data.merges.single.c1, 1);
    expect(data.exportColumnWidth(0), greaterThan(data.exportColumnWidth(1)));
    expect(data.allCells.length, lessThan(100));
  });

  test('an imported ODS saves as a readable .xlsx', () async {
    final book = OdsSheetReader.readBytes(bytes);
    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final reopened = SheetDeserializer().readBytes(saved);
    expect(reopened.sheets.map((sheet) => sheet.name), ['Data', 'Notes']);
    expect(reopened.sheets.first.cellA1('A1').asString, 'Item');
    expect(reopened.sheets.first.cellA1('D2').formula, 'B2*C2');
    expect(reopened.sheets.first.cellA1('D2').value, 7);
    expect(reopened.sheets.first.cellA1('B2').value, 2);
    expect(reopened.sheets.first.merges, hasLength(1));
  });

  test('covered cells and internal repeated empty rows keep positions', () {
    const content = '''
<office:document-content
 xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
 <office:body><office:spreadsheet><table:table table:name="Budget">
  <table:table-row>
   <table:table-cell office:value-type="string" table:number-columns-spanned="2"><text:p>Heading</text:p></table:table-cell>
   <table:covered-table-cell/>
   <table:table-cell office:value-type="float" office:value="7"/>
  </table:table-row>
  <table:table-row table:number-rows-repeated="2"/>
  <table:table-row><table:table-cell office:value-type="string"><text:p>Tail</text:p></table:table-cell></table:table-row>
 </table:table></office:spreadsheet></office:body>
</office:document-content>
''';
    final zip = ZipWriter()
      ..addFile(
        'mimetype',
        utf8.encode('application/vnd.oasis.opendocument.spreadsheet'),
      )
      ..addFile('content.xml', utf8.encode(content));
    final book = OdsSheetReader.readBytes(zip.close());
    final sheet = book.sheets.single;
    expect(sheet.name, 'Budget');
    expect(sheet.cellA1('A1').asString, 'Heading');
    expect(sheet.cellA1('C1').value, 7);
    expect(sheet.cellA1('A2').asString, isEmpty);
    expect(sheet.cellA1('A3').asString, isEmpty);
    expect(sheet.cellA1('A4').asString, 'Tail');
    expect(
      sheet.merges.single.c1,
      1,
      reason: 'A1 spans A1:B1; the covered placeholder must not add columns',
    );
  });

  test('rejects a non-ODF package', () {
    expect(
      () => OdsSheetReader.readBytes(Uint8List.fromList(List.filled(64, 0))),
      throwsA(isA<OdsSheetFormatException>()),
    );
  });

  test('merged covered cells consume one coordinate and retain row spans', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Grid"><t:table-row>'
        '<t:table-cell t:number-columns-spanned="2" t:number-rows-spanned="2" '
        'o:value-type="string"><x:p>Merge</x:p></t:table-cell>'
        '<t:covered-table-cell/>${_value('C1')}</t:table-row>'
        '<t:table-row><t:covered-table-cell t:number-columns-repeated="2"/>'
        '${_value('C2')}</t:table-row></t:table>',
      ),
    );
    expect(book.firstSheet.cellA1('C1').asString, 'C1');
    expect(book.firstSheet.cellA1('C2').asString, 'C2');
    expect(book.firstSheet.merges.single.a1, 'A1:B2');
    final reopened = SheetDeserializer().readBytes(
      await OfficeIsolateSave.workbook(book, recalculate: false),
    );
    expect(reopened.firstSheet.cellA1('C1').asString, 'C1');
    expect(reopened.firstSheet.merges.single.a1, 'A1:B2');
  });

  test('repeated blank rows retain later data at exact coordinates', () {
    final sheet = OdsSheetReader.readBytes(
      _ods(
        '<t:table><t:table-row>${_value('A1')}</t:table-row>'
        '<t:table-row t:number-rows-repeated="2"><t:table-cell/></t:table-row>'
        '<t:table-row>${_value('A4')}</t:table-row></t:table>',
      ),
    ).firstSheet;
    expect(sheet.cellA1('A1').asString, 'A1');
    expect(sheet.cellA1('A4').asString, 'A4');
  });

  test('row headers and groups retain blank row coordinates', () {
    final sheet = OdsSheetReader.readBytes(
      _ods(
        '<t:table><t:table-header-rows><t:table-row>${_value('A1')}'
        '</t:table-row></t:table-header-rows>'
        '<t:table-row-group><t:table-rows>'
        '<t:table-row t:number-rows-repeated="2"><t:table-cell/></t:table-row>'
        '<t:table-row>${_value('A4')}</t:table-row>'
        '</t:table-rows></t:table-row-group></t:table>',
      ),
    ).firstSheet;
    expect(sheet.cellA1('A1').asString, 'A1');
    expect(sheet.cellA1('A4').asString, 'A4');
    expect(sheet.cellA1('A2').value, isNull);
    expect(sheet.cellA1('A3').value, isNull);
  });

  test('foreign lookalike elements and attributes cannot change sheet values', () {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<e:table><e:table-row>${_value('wrong sheet')}</e:table-row></e:table>'
        '<t:table t:name="Data"><t:table-row>'
        '<e:table-cell o:value-type="string"><x:p>wrong cell</x:p></e:table-cell>'
        '<t:table-cell e:value="999" o:value="7" o:value-type="float" '
        'e:number-columns-repeated="10"/>${_value('B1')}'
        '</t:table-row></t:table>',
      ),
    );
    expect(book.sheets.map((sheet) => sheet.name), ['Data']);
    expect(book.firstSheet.cellA1('A1').value, 7);
    expect(book.firstSheet.cellA1('B1').asString, 'B1');
  });

  test('named inherited cell wrap styles survive an XLSX roundtrip', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table><t:table-row>'
        '<t:table-cell t:style-name="wrapped" o:value-type="string">'
        '<x:p>Two<x:line-break/>lines</x:p></t:table-cell>'
        '<t:table-cell t:style-name="plain" o:value-type="string">'
        '<x:p>Plain</x:p></t:table-cell></t:table-row></t:table>',
        styles:
            '<s:style s:name="wrapped" s:family="table-cell" '
            's:parent-style-name="Base"/>'
            '<s:style s:name="plain" s:family="table-cell" '
            's:parent-style-name="Base">'
            '<s:table-cell-properties f:wrap-option="no-wrap"/></s:style>',
        namedStyles:
            '<s:style s:name="Base" s:family="table-cell">'
            '<s:table-cell-properties f:wrap-option="wrap"/>'
            '<s:text-properties f:font-weight="bold"/></s:style>'
            '<s:style s:name="Base" s:family="graphic">'
            '<s:text-properties f:font-weight="normal"/></s:style>',
      ),
    );
    expect(book.firstSheet.cellA1('A1').asString, 'Two\nlines');
    expect(book.firstSheet.cellA1('A1').fontBold, isTrue);
    expect(book.firstSheet.cellA1('A1').wrapText, isTrue);
    expect(book.firstSheet.cellA1('B1').wrapText, isFalse);
    final reopened = SheetDeserializer().readBytes(
      await OfficeIsolateSave.workbook(book, recalculate: false),
    );
    expect(
      reopened.styles!.wrapAt(reopened.firstSheet.cellA1('A1').styleIndex),
      isTrue,
    );
    expect(
      reopened.styles!.wrapAt(reopened.firstSheet.cellA1('B1').styleIndex),
      isFalse,
    );
  });

  test('column groups retain dimensions and repeated values', () {
    final sheet = OdsSheetReader.readBytes(
      _ods(
        '<t:table><t:table-column-group><t:table-columns>'
        '<t:table-column t:style-name="wide" t:number-columns-repeated="2"/>'
        '</t:table-columns></t:table-column-group><t:table-row>'
        '<t:table-cell t:number-columns-repeated="2" o:value-type="float" '
        'o:value="4"/></t:table-row></t:table>',
        styles:
            '<s:style s:name="wide" s:family="table-column">'
            '<s:table-column-properties s:column-width="1in"/></s:style>',
      ),
    ).firstSheet;
    expect(sheet.exportColumnWidth(0), closeTo(96 / 7.4, .00001));
    expect(sheet.exportColumnWidth(1), closeTo(96 / 7.4, .00001));
    expect(sheet.cellA1('A1').value, 4);
    expect(sheet.cellA1('B1').value, 4);
  });

  test(
    'blank trailing padding is skipped without truncating data silently',
    () {
      final first = '<t:table-row>${_value('A1')}</t:table-row>';
      const padding =
          '<t:table-row t:number-rows-repeated="1048575">'
          '<t:table-cell t:number-columns-repeated="16384"/></t:table-row>';
      final bytes = _ods('<t:table>$first$padding</t:table>');
      final sheet = OdsSheetReader.readBytes(bytes).firstSheet;
      expect(sheet.allCells, hasLength(1));
      expect(
        () => OdsSheetReader.readBytes(
          _ods(
            '<t:table>$first$padding<t:table-row>${_value('past limit')}'
            '</t:table-row></t:table>',
          ),
        ),
        _invalidOds,
      );
    },
  );

  test('rejects cross-product expansion before materializing repeated cells', () {
    expect(
      () => OdsSheetReader.readBytes(
        _ods(
          '<t:table><t:table-row t:number-rows-repeated="100000">'
          '<t:table-cell t:number-columns-repeated="4096" o:value-type="float" '
          'o:value="1"/></t:table-row></t:table>',
        ),
      ),
      _invalidOds,
    );
  });

  test('workbook budget is shared by multiple individually small sheets', () {
    const table =
        '<t:table><t:table-row t:number-rows-repeated="1000">'
        '<t:table-cell t:number-columns-repeated="100" o:value-type="float" '
        'o:value="1"/></t:table-row></t:table>';
    expect(
      () => OdsSheetReader.readBytes(_ods('$table$table$table')),
      _invalidOds,
    );
  });

  test('repeated text is bounded before it can expand during XLSX save', () {
    final text = 'word' * 1024;
    expect(
      () => OdsSheetReader.readBytes(
        _ods(
          '<t:table><t:table-row t:number-rows-repeated="4096">'
          '${_value(text)}</t:table-row></t:table>',
        ),
      ),
      _invalidOds,
    );
  });

  test('rejects invalid or out-of-range meaningful repeats instead of clipping', () {
    for (final repeat in ['0', '-1', 'bad', '4097']) {
      expect(
        () => OdsSheetReader.readBytes(
          _ods(
            '<t:table><t:table-row><t:table-cell '
            't:number-columns-repeated="$repeat" o:value-type="float" o:value="3"/>'
            '</t:table-row></t:table>',
          ),
        ),
        _invalidOds,
        reason: repeat,
      );
    }
  });

  test(
    'formula conversion preserves delimiters and brackets inside literals',
    () {
      final sheet = OdsSheetReader.readBytes(
        _ods(
          '<t:table><t:table-row><t:table-cell '
          't:formula="of:=CONCAT(&quot;a;b[.A1]&quot;;[.B2])" '
          'o:value-type="string" o:string-value="a;b[.A1]value"/>'
          '</t:table-row></t:table>',
        ),
      ).firstSheet;
      expect(sheet.cellA1('A1').formula, 'CONCAT("a;b[.A1]",B2)');
      expect(sheet.cellA1('A1').value, 'a;b[.A1]value');
    },
  );

  test(
    'repeated formulas decline rather than cloning incorrect references',
    () {
      expect(
        () => OdsSheetReader.readBytes(
          _ods(
            '<t:table><t:table-row t:number-rows-repeated="2"><t:table-cell '
            't:formula="of:=[.B1]" o:value-type="float" o:value="3"/>'
            '</t:table-row></t:table>',
          ),
        ),
        _invalidOds,
      );
    },
  );

  test('preserves ODF explicit spaces, tabs and paragraph boundaries', () {
    final sheet = OdsSheetReader.readBytes(
      _ods(
        '<t:table><t:table-row><t:table-cell o:value-type="string">'
        '<x:p>one<x:s x:c="2"/>two<x:tab/>three</x:p>'
        '<x:p>next</x:p></t:table-cell></t:table-row></t:table>',
      ),
    ).firstSheet;
    expect(sheet.cellA1('A1').asString, 'one  two\tthree\nnext');
  });

  test('rejects XML with spreadsheet local names in the wrong namespace', () {
    final zip = ZipWriter()
      ..addFile(
        'content.xml',
        utf8.encode(
          '<document-content><body><spreadsheet><table><table-row>'
          '<table-cell>Not an ODS</table-cell></table-row></table>'
          '</spreadsheet></body></document-content>',
        ),
      );
    expect(() => OdsSheetReader.readBytes(zip.close()), _invalidOds);
  });

  test('rejects cyclic named styles and excessive XML nesting', () {
    expect(
      () => OdsSheetReader.readBytes(
        _ods(
          '<t:table><t:table-row><t:table-cell t:style-name="A" '
          'o:value-type="float" o:value="1"/></t:table-row></t:table>',
          styles:
              '<s:style s:name="A" s:family="table-cell" s:parent-style-name="B"/>'
              '<s:style s:name="B" s:family="table-cell" s:parent-style-name="A"/>',
        ),
      ),
      _invalidOds,
    );
    expect(
      () => OdsSheetReader.readBytes(
        _ods(
          '<t:table>${'<t:table-row-group>' * 150}'
          '<t:table-row>${_value('deep')}</t:table-row>'
          '${'</t:table-row-group>' * 150}</t:table>',
        ),
      ),
      _invalidOds,
    );
  });
  test(
    'keeps internal repeated blank rows without expanding trailing padding',
    () async {
      final book = OdsSheetReader.readBytes(
        _odsRows(
          '''
      <table:table-row>
        <table:table-cell office:value-type="string"><text:p>Start</text:p></table:table-cell>
      </table:table-row>
      <table:table-row table:number-rows-repeated="2" table:style-name="tall">
        <table:table-cell table:number-columns-repeated="4096"/>
      </table:table-row>
      <table:table-row>
        <table:table-cell office:value-type="float" office:value="7"/>
        <table:table-cell office:value-type="float" office:value="14" table:formula="of:=[.A4]*2"/>
      </table:table-row>
      <table:table-row table:number-rows-repeated="1048572" table:style-name="tall">
        <table:table-cell table:number-columns-repeated="16384"/>
      </table:table-row>
      ''',
          styles: '''
      <style:style style:name="tall" style:family="table-row">
        <style:table-row-properties style:row-height="24pt"/>
      </style:style>
      ''',
        ),
      );
      for (final current in [book, await _roundTrip(book)]) {
        final sheet = current.sheets.single;
        expect(sheet.cellOrNull(SmlCellRef.parse('A4'))?.value, 7);
        expect(sheet.cellOrNull(SmlCellRef.parse('B4'))?.formula, 'A4*2');
        expect(sheet.cellOrNull(SmlCellRef.parse('B4'))?.value, 14);
        expect(sheet.cellOrNull(SmlCellRef.parse('A2')), isNull);
        expect(sheet.cellOrNull(SmlCellRef.parse('A3')), isNull);
        expect(sheet.allCells, hasLength(3));
        expect(sheet.rowHeights[1], SmlWorksheet.rowHeightFromExcel(24));
        expect(sheet.rowHeights[2], SmlWorksheet.rowHeightFromExcel(24));
        expect(sheet.rowHeights, hasLength(2));
      }
    },
  );

  test(
    'blank runs retain in-range cells and refuse later out-of-range data',
    () {
      const inside = '''
      <table:table-row table:number-rows-repeated="99999"><table:table-cell/></table:table-row>
      <table:table-row><table:table-cell office:value-type="float" office:value="7"/></table:table-row>
      ''';
      final sheet = OdsSheetReader.readBytes(_odsRows(inside)).sheets.single;
      expect(sheet.cellOrNull(const SmlCellRef(0, 99999))?.value, 7);
      expect(sheet.cellOrNull(const SmlCellRef(0, 100000)), isNull);
      expect(sheet.allCells, hasLength(1));
      expect(sheet.rows, hasLength(1));
      expect(
        () => OdsSheetReader.readBytes(
          _odsRows('''
        $inside
        <table:table-row><table:table-cell office:value-type="float" office:value="9"/></table:table-row>
        '''),
        ),
        _invalidOds,
      );
    },
  );

  for (final merge in [
    (
      name: 'explicit placeholder',
      span: 2,
      covered: '<table:covered-table-cell/>',
      nextColumn: 2,
    ),
    (
      name: 'repeated placeholders',
      span: 3,
      covered: '<table:covered-table-cell table:number-columns-repeated="2"/>',
      nextColumn: 3,
    ),
    (
      name: 'additional covered column',
      span: 2,
      covered: '<table:covered-table-cell table:number-columns-repeated="2"/>',
      nextColumn: 3,
    ),
  ]) {
    test('horizontal merge consumes ${merge.name} once', () async {
      final book = OdsSheetReader.readBytes(
        _odsRows('''
        <table:table-row>
          <table:table-cell office:value-type="string" table:number-columns-spanned="${merge.span}"><text:p>Wide</text:p></table:table-cell>
          ${merge.covered}
          <table:table-cell office:value-type="float" office:value="7"/>
        </table:table-row>
        '''),
      );
      for (final current in [book, await _roundTrip(book)]) {
        final sheet = current.sheets.single;
        expect(sheet.cellOrNull(SmlCellRef(merge.nextColumn, 0))?.value, 7);
        expect(sheet.cellOrNull(SmlCellRef(merge.nextColumn + 1, 0)), isNull);
        expect(sheet.merges.single.c0, 0);
        expect(sheet.merges.single.c1, merge.span - 1);
        expect(sheet.allCells, hasLength(2));
      }
    });
  }

  test(
    'consecutive merged origins retain explicit covered positions',
    () async {
      final book = OdsSheetReader.readBytes(
        _odsRows('''
      <table:table-row>
        <table:table-cell office:value-type="string" table:number-columns-spanned="2"><text:p>First</text:p></table:table-cell>
        <table:covered-table-cell/>
        <table:table-cell office:value-type="string" table:number-columns-spanned="2"><text:p>Second</text:p></table:table-cell>
        <table:covered-table-cell/>
        <table:table-cell office:value-type="float" office:value="7"/>
      </table:table-row>
      '''),
      );
      for (final current in [book, await _roundTrip(book)]) {
        final sheet = current.sheets.single;
        expect(sheet.cellOrNull(SmlCellRef.parse('C1'))?.asString, 'Second');
        expect(sheet.cellOrNull(SmlCellRef.parse('E1'))?.value, 7);
        expect(sheet.allCells, hasLength(3));
        expect(sheet.merges.map((merge) => merge.origin.a1), ['A1', 'C1']);
      }
    },
  );

  test('merge spans retain in-range cells and refuse column overflow', () {
    final sheet = OdsSheetReader.readBytes(
      _odsRows('''
      <table:table-row>
        <table:table-cell table:number-columns-repeated="4094"/>
        <table:table-cell office:value-type="string" table:number-columns-spanned="2"><text:p>Edge</text:p></table:table-cell>
        <table:covered-table-cell/>
      </table:table-row>
      '''),
    ).sheets.single;
    expect(sheet.merges.single.c0, 4094);
    expect(sheet.merges.single.c1, 4095);
    expect(sheet.allCells, hasLength(1));
    expect(
      () => OdsSheetReader.readBytes(
        _odsRows('''
        <table:table-row>
          <table:table-cell table:number-columns-repeated="4094"/>
          <table:table-cell office:value-type="string" table:number-columns-spanned="4096"><text:p>Edge</text:p></table:table-cell>
          <table:covered-table-cell table:number-columns-repeated="4096"/>
          <table:table-cell office:value-type="float" office:value="7"/>
        </table:table-row>
        '''),
      ),
      _invalidOds,
    );
  });

  test(
    'styled trailing row padding stays sparse within the admitted grid',
    () async {
      final book = OdsSheetReader.readBytes(
        _odsRows(
          '''
      <table:table-row><table:table-cell office:value-type="float" office:value="7"/></table:table-row>
      <table:table-row table:number-rows-repeated="1000" table:style-name="tall"><table:table-cell/></table:table-row>
      ''',
          styles: '''
      <style:style style:name="tall" style:family="table-row"><style:table-row-properties style:row-height="24pt"/></style:style>
      ''',
        ),
      );
      for (final current in [book, await _roundTrip(book)]) {
        final sheet = current.sheets.single;
        expect(sheet.cellOrNull(const SmlCellRef(0, 0))?.value, 7);
        expect(sheet.allCells, hasLength(1));
        expect(sheet.rowHeights, isEmpty);
      }
    },
  );

  for (final formula in {
    'of:=MYCOM.MICROSOFT.FUNC(1)': 'MYCOM.MICROSOFT.FUNC(1)',
    'of:="a;b"': '"a;b"',
    'of:="literal [.A1];COM.MICROSOFT.SUM"':
        '"literal [.A1];COM.MICROSOFT.SUM"',
    'of:=IF([.A1]="a;b";"say ""[.B2];""";COM.MICROSOFT.SUM([.A1:.A2];1))':
        'IF(A1="a;b","say ""[.B2];""",SUM(A1:A2,1))',
    'of:=CONCATENATE("";"a;b";"[.A1]")': 'CONCATENATE("","a;b","[.A1]")',
    "of:=SUM(['Semi;Colon'.A1];1)": "SUM('Semi;Colon'!A1,1)",
    "of:=SUM(['COM.MICROSOFT.Data'.A1];1)": "SUM('COM.MICROSOFT.Data'!A1,1)",
    r'of:=[$Sheet2.A1]+[.$A$1]': r'Sheet2!A1+$A$1',
    r"of:=[$'Semi;Colon'.$A$1]": r"'Semi;Colon'!$A$1",
  }.entries) {
    test('formula translation preserves literals in ${formula.key}', () async {
      final book = OdsSheetReader.readBytes(
        _odsRows('''
        <table:table-row>
          <table:table-cell office:value-type="string" office:string-value="cached" table:formula="${_xmlAttribute(formula.key)}"/>
        </table:table-row>
        '''),
      );
      for (final current in [book, await _roundTrip(book)]) {
        expect(current.sheets.single.cellA1('A1').formula, formula.value);
      }
    });
  }
}

void defaultAndTimeTests() {
  test('currency symbols survive namespaced import and XLSX saves', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table><t:table-row>'
        '<t:table-cell t:style-name="usd" o:value-type="currency" '
        'o:value="1234.5"/>'
        '<t:table-cell t:style-name="usd" o:value-type="currency" '
        'o:value="-1234.5"/>'
        '<t:table-cell t:style-name="eur" o:value-type="currency" '
        'o:value="5"/>'
        '</t:table-row></t:table>',
        styles:
            '<n:currency-style xmlns:n="$_number" s:name="USD">'
            '<e:currency-symbol>wrong</e:currency-symbol>'
            '<n:currency-symbol>\$</n:currency-symbol>'
            '<n:number n:decimal-places="2" n:grouping="true"/>'
            '</n:currency-style>'
            '<n:currency-style xmlns:n="$_number" s:name="EUR">'
            '<n:currency-symbol>€</n:currency-symbol>'
            '<n:number n:decimal-places="2"/>'
            '</n:currency-style>'
            '<s:style s:name="usd" s:family="table-cell" '
            's:data-style-name="USD"/>'
            '<s:style s:name="eur" s:family="table-cell" '
            's:data-style-name="EUR"/>',
      ),
    );
    for (final current in [book, await _roundTrip(book)]) {
      for (final expected in {
        'A1': r'$1,234.50',
        'B1': r'-$1,234.50',
        'C1': '€5.00',
      }.entries) {
        final cell = current.firstSheet.cellA1(expected.key);
        expect(
          current.styles!.format(cell.value, cell.styleIndex),
          expected.value,
        );
      }
    }
  });

  test('inherited styled padding stays sparse while explicit blanks survive', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table><t:table-column t:default-cell-style-name="inherited" '
        't:number-columns-repeated="4096"/>'
        '<t:table-row t:default-cell-style-name="inherited" '
        't:style-name="defaultHeight" t:number-rows-repeated="4000">'
        '<t:table-cell t:number-columns-repeated="4096"/></t:table-row>'
        '<t:table-row><t:table-cell o:value-type="float" o:value="9"/>'
        '<t:table-cell t:style-name="accent"/></t:table-row></t:table>',
        styles:
            '<s:style s:name="inherited" s:family="table-cell">'
            '<s:text-properties f:font-size="14pt"/></s:style>'
            '<s:style s:name="accent" s:family="table-cell">'
            '<s:table-cell-properties f:background-color="#FF0000"/></s:style>'
            '<s:style s:name="defaultHeight" s:family="table-row">'
            '<s:table-row-properties s:row-height="14.95pt"/></s:style>',
      ),
    );
    expect(book.firstSheet.rowHeights, isEmpty);
    for (final current in [book, await _roundTrip(book)]) {
      final sheet = current.firstSheet;
      expect(sheet.allCells, hasLength(2));
      expect(sheet.cellA1('A4001').value, 9);
      expect(sheet.cellA1('A4001').fontSize, 14);
      final blank = sheet.cellA1('B4001');
      expect(current.styles!.fillAt(blank.styleIndex), 'FF0000');
    }
  });

  test('ODS native column geometry survives a new XLSX copy', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table><t:table-column t:style-name="wide"/>'
        '<t:table-column t:style-name="normal" t:number-columns-repeated="4095"/>'
        '<t:table-row>${_value('value')}</t:table-row></t:table>',
        styles:
            '<s:style s:name="wide" s:family="table-column">'
            '<s:table-column-properties s:column-width="1in"/></s:style>'
            '<s:style s:name="normal" s:family="table-column">'
            '<s:table-column-properties s:column-width="0.8898in"/></s:style>',
      ),
    );
    for (final current in [book, await _roundTrip(book)]) {
      final sheet = current.firstSheet;
      expect(sheet.columnWidths.keys, [0]);
      expect(sheet.exportColumnWidth(0), closeTo(96 / 7.4, 1e-10));
      expect(sheet.columnWidth(1), 81);
    }
  });

  test('cell then row then per-column styles survive repeated cells', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table><t:table-column t:default-cell-style-name="red"/>'
        '<t:table-column t:default-cell-style-name="blue"/>'
        '<t:table-column t:default-cell-style-name="red"/>'
        '<t:table-row><t:table-cell t:number-columns-repeated="3" '
        'o:value-type="float" o:value="7"/></t:table-row>'
        '<t:table-row t:default-cell-style-name="green">'
        '<t:table-cell t:number-columns-repeated="3" o:value-type="float" '
        'o:value="8"/></t:table-row>'
        '<t:table-row t:default-cell-style-name="green">'
        '<t:table-cell t:style-name="blue" t:number-columns-repeated="2" '
        'o:value-type="float" o:value="9"/>'
        '<t:table-cell o:value-type="float" o:value="10"/>'
        '</t:table-row></t:table>',
        styles: [('red', 'FF0000'), ('blue', '0000FF'), ('green', '00FF00')]
            .map(
              (style) =>
                  '<s:style s:name="${style.$1}" s:family="table-cell">'
                  '<s:table-cell-properties f:background-color="#${style.$2}"/>'
                  '</s:style>',
            )
            .join(),
      ),
    );
    for (final current in [book, await _roundTrip(book)]) {
      final sheet = current.firstSheet;
      expect(sheet.allCells, hasLength(9));
      for (final row in [
        (1, ['FF0000', '0000FF', 'FF0000']),
        (2, ['00FF00', '00FF00', '00FF00']),
        (3, ['0000FF', '0000FF', '00FF00']),
      ]) {
        for (var column = 0; column < 3; column++) {
          final cell = sheet.cellOrNull(SmlCellRef(column, row.$1 - 1))!;
          expect(current.styles!.fillAt(cell.styleIndex), row.$2[column]);
          expect(cell.value, row.$1 == 3 && column == 2 ? 10 : 6 + row.$1);
        }
      }
    }
  });

  test('Default column and row padding stays sparse at large repeats', () {
    final sheet = OdsSheetReader.readBytes(
      _ods(
        '<t:table><t:table-column t:default-cell-style-name="Default" '
        't:number-columns-repeated="1073741824"/>'
        '<t:table-row t:default-cell-style-name="Default" '
        't:number-rows-repeated="100000">'
        '<t:table-cell t:number-columns-repeated="1073741824"/>'
        '</t:table-row></t:table>',
      ),
    ).firstSheet;
    expect(sheet.allCells, isEmpty);
    expect(sheet.rows, isEmpty);
  });

  test('column default bookkeeping shares the workbook dimension budget', () {
    expect(
      () => OdsSheetReader.readBytes(
        _ods(
          '<t:table><t:table-column t:default-cell-style-name="Default" '
                  't:number-columns-repeated="4096"/></t:table>' *
              50,
        ),
      ),
      _invalidOds,
    );
  });

  for (final time in [
    (
      name: 'hour and minute',
      duration: 'PT12H30M',
      parts: '<n:hours/><n:minutes n:style="long"/>',
      elapsed: false,
      expected: '12:30',
    ),
    (
      name: 'minute and second',
      duration: 'PT7M05S',
      parts: '<n:minutes n:style="long"/><n:seconds n:style="long"/>',
      elapsed: false,
      expected: '07:05',
    ),
    (
      name: 'full clock',
      duration: 'PT1H02M03S',
      parts: '<n:hours/><n:minutes/><n:seconds/>',
      elapsed: false,
      expected: '1:02:03',
    ),
    (
      name: 'elapsed hours',
      duration: 'PT27H15M03S',
      parts: '<n:hours/><n:minutes/><n:seconds/>',
      elapsed: true,
      expected: '27:15:03',
    ),
    (
      name: 'elapsed minutes',
      duration: 'PT1H30M',
      parts: '<n:minutes/>',
      elapsed: true,
      expected: '90',
    ),
    (
      name: 'elapsed minutes and seconds',
      duration: 'PT1H02M03S',
      parts: '<n:minutes/><n:seconds/>',
      elapsed: true,
      expected: '62:03',
    ),
    (
      name: 'elapsed seconds',
      duration: 'PT1M05S',
      parts: '<n:seconds/>',
      elapsed: true,
      expected: '65',
    ),
  ]) {
    test('ODS ${time.name} format survives XLSX save', () async {
      final book = OdsSheetReader.readBytes(
        _ods(
          '<t:table><t:table-row><t:table-cell t:style-name="time" '
          'o:value-type="time" o:time-value="${time.duration}"/>'
          '</t:table-row></t:table>',
          styles:
              '<n:time-style xmlns:n="$_number" s:name="Time" '
              'n:truncate-on-overflow="${!time.elapsed}">${time.parts}'
              '<e:hours/></n:time-style>'
              '<s:style s:name="time" s:family="table-cell" '
              's:data-style-name="Time"/>',
        ),
      );
      for (final current in [book, await _roundTrip(book)]) {
        final cell = current.firstSheet.cellA1('A1');
        expect(
          current.styles!.format(cell.value, cell.styleIndex),
          time.expected,
        );
      }
    });
  }
}

Future<SmlWorkbook> _roundTrip(SmlWorkbook book) async => SheetDeserializer()
    .readBytes(await OfficeIsolateSave.workbook(book, recalculate: false));

Uint8List _odsRows(String rows, {String styles = ''}) {
  final zip = ZipWriter()
    ..addFile(
      'mimetype',
      utf8.encode('application/vnd.oasis.opendocument.spreadsheet'),
      store: true,
    )
    ..addFile(
      'content.xml',
      utf8.encode('''
      <office:document-content
        xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
        xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
        xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
        xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0">
        <office:automatic-styles>$styles</office:automatic-styles>
        <office:body><office:spreadsheet><table:table table:name="Data">$rows</table:table></office:spreadsheet></office:body>
      </office:document-content>
      '''),
    );
  return zip.close();
}

void edgeTests() {
  final edge = File('test/fixtures/fidelity/legacy-sheet-edge.ods')
      .readAsBytesSync();

  test('ODS keeps dates, times, booleans, formats and sheet references', () {
    final book = OdsSheetReader.readBytes(edge);
    final sheet = book.sheets.first;
    final styles = book.styles!;

    expect(sheet.cellA1('A1').value, 45293);
    expect(sheet.cellA1('A1').fontBold, isTrue);
    expect(sheet.cellA1('A1').fillRgb, 'C0FFC0');
    expect(styles.format(45293, sheet.cellA1('A1').styleIndex), '02.01.2024');

    expect(sheet.cellA1('A2').value, closeTo(0.5208333, 0.000001));
    expect(
      styles.format(sheet.cellA1('A2').value, sheet.cellA1('A2').styleIndex),
      '12:30',
    );

    expect(sheet.cellA1('A3').value, isTrue);
    expect(sheet.cellA1('B1').formula, 'Sheet2!A1+1');
    expect(sheet.cellA1('B1').value, 42);
    expect(sheet.cellA1('B2').formula, r'$A$1');
    expect(sheet.cellA1('C1').value, closeTo(0.256, 1e-9));
    expect(styles.format(0.256, sheet.cellA1('C1').styleIndex), '25.6%');
    expect(styles.format(1234.5, sheet.cellA1('C2').styleIndex), '1,234.50');

    final merge = sheet.merges.single;
    expect(merge.origin.a1, 'D1');
    expect(merge.c1, 4);
    expect(merge.r1, 1);
    expect(sheet.cellA1('D1').horizontalAlign, SmlHAlign.center);
    expect(book.sheets[1].cellA1('A1').value, 41);
    expect(sheet.comments.single.ref.a1, 'A5');
    expect(sheet.comments.single.text, 'Review this');
    expect(sheet.comments.single.author, 'Alice');
    expect(sheet.cellA1('E3').value, 'A    B');
    expect(sheet.cellA1('E4').value, 'L1\nL2');
    expect(
      styles.format(sheet.cellA1('F3').value, sheet.cellA1('F3').styleIndex),
      '2024-03-04',
    );
    expect(
      styles.format(sheet.cellA1('F4').value, sheet.cellA1('F4').styleIndex),
      '2024-03-04 13:45',
    );
  });

  test('edge ODS survives an xlsx round trip', () async {
    final saved = await OfficeIsolateSave.workbook(
      OdsSheetReader.readBytes(edge),
      recalculate: false,
    );
    final reopened = SheetDeserializer().readBytes(saved);
    expect(reopened.sheets.first.cellA1('A1').value, 45293);
    expect(reopened.sheets.first.cellA1('B1').formula, 'Sheet2!A1+1');
    expect(reopened.sheets.first.merges, hasLength(1));
    expect(reopened.sheets.first.comments.single.text, 'Review this');
    expect(
      reopened.styles!.format(
        45293,
        reopened.sheets.first.cellA1('A1').styleIndex,
      ),
      '02.01.2024',
    );
  });
}

void imageTests() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nXQAAAAASUVORK5CYII=',
  );

  test('ODS pictures become worksheet drawings and survive save', () async {
    final source = _ods(
      '<t:table t:name="Data"><t:table-row><t:table-cell>'
      '<dr:frame dr:name="Logo" svg:width="2in" svg:height="1in">'
      '<dr:image xl:href="Pictures/p.png"/></dr:frame>'
      '</t:table-cell></t:table-row></t:table>',
      parts: {'Pictures/p.png': png},
    );
    final book = OdsSheetReader.readBytes(source);
    final drawing = book.sheets.first.drawings.single;
    expect(drawing.visual.title, 'Logo');
    expect(drawing.visual.imageBytes, png);
    expect(drawing.visual.width, closeTo(144, 0.01));
    expect(drawing.visual.height, closeTo(72, 0.01));

    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final reopened = SheetDeserializer().readBytes(saved);
    final restored = reopened.sheets.first.drawings.single;
    expect(restored.visual.imageBytes, png);
    expect(restored.visual.width, closeTo(144, 0.01));
  });
}

void defaultStyleTests() {
  test('ODS document default style supplies the Normal cell font', () {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data"><t:table-row><t:table-cell>'
        '<x:p>Plain</x:p></t:table-cell></t:table-row></t:table>',
        namedStyles:
            '<s:default-style s:family="table-cell">'
            '<s:text-properties f:font-family="Liberation Sans" '
            'f:font-size="10pt"/></s:default-style>',
      ),
    );
    final cell = book.sheets.first.cellA1('A1');
    expect(cell.value, 'Plain');
    expect(cell.fontFamily, 'Liberation Sans');
    expect(cell.fontSize, 10);
  });
}

void defaultGeometryTests() {
  test('ODS document defaults supply column width and row height', () {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data"><t:table-row><t:table-cell>'
        '<x:p>Plain</x:p></t:table-cell></t:table-row></t:table>',
        namedStyles:
            '<s:default-style s:family="table-column">'
            '<s:table-column-properties s:column-width="2in"/>'
            '</s:default-style>'
            '<s:default-style s:family="table-row">'
            '<s:table-row-properties s:row-height="1in"/>'
            '</s:default-style>',
      ),
    );
    final sheet = book.sheets.first;
    expect(sheet.columnWidth(0), greaterThan(160));
    expect(sheet.rowHeightAt(0), closeTo(96, 0.01));
  });
}

void hiddenStateTests() {
  test('ODS hidden sheets survive save and reopen', () async {
    final source = _ods(
      '<t:table t:name="Visible"><t:table-row><t:table-cell>'
      '<x:p>One</x:p></t:table-cell></t:table-row></t:table>'
      '<t:table t:name="Hidden" t:style-name="taHidden">'
      '<t:table-row><t:table-cell><x:p>Two</x:p></t:table-cell>'
      '</t:table-row></t:table>',
      styles:
          '<s:style s:name="taHidden" s:family="table">'
          '<s:table-properties t:display="false"/></s:style>',
    );
    final book = OdsSheetReader.readBytes(source);
    expect(book.sheets[0].hidden, isFalse);
    expect(book.sheets[1].hidden, isTrue);

    final reopened = SheetDeserializer().readBytes(
      await OfficeIsolateSave.workbook(book, recalculate: false),
    );
    expect(reopened.sheets[1].hidden, isTrue);
    expect(reopened.sheets[1].cellA1('A1').value, 'Two');
  });

  test('ODS hidden columns and rows survive save', () async {
    final source = _ods(
      '<t:table t:name="Data">'
      '<t:table-column t:visibility="collapse"/>'
      '<t:table-column/>'
      '<t:table-row t:visibility="collapse"><t:table-cell>'
      '<x:p>Hidden</x:p></t:table-cell></t:table-row>'
      '<t:table-row><t:table-cell><x:p>Visible</x:p></t:table-cell>'
      '</t:table-row></t:table>',
    );
    final book = OdsSheetReader.readBytes(source);
    final sheet = book.sheets.first;
    expect(sheet.columnProperties[0]?['hidden'], '1');
    expect(sheet.rowHeightAt(0), 0);
    expect(sheet.hiddenRows, contains(0));
    expect(sheet.cellA1('A1').value, 'Hidden');

    final reopened = SheetDeserializer().readBytes(
      await OfficeIsolateSave.workbook(book, recalculate: false),
    );
    final saved = reopened.sheets.first;
    expect(saved.columnProperties[0]?['hidden'], '1');
    expect(saved.hiddenRows, contains(0));
    expect(saved.rowHeightAt(0), 0);
    expect(saved.cellA1('A2').value, 'Visible');
  });
}

void conditionalFormatTests() {
  test('ODS text and duplicate conditions keep their type', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data">'
        '<t:table-row><t:table-cell><x:p>apple</x:p></t:table-cell>'
        '<t:table-cell><x:p>pear</x:p></t:table-cell></t:table-row>'
        '<t:table-row><t:table-cell><x:p>apple</x:p></t:table-cell>'
        '<t:table-cell><x:p>pear</x:p></t:table-cell></t:table-row>'
        '<cal:conditional-formats>'
        '<cal:conditional-format cal:target-range-address="Data.A1:Data.A10">'
        '<cal:condition cal:apply-style-name="cf" '
        'cal:value="contains-text(&quot;app&quot;)"/>'
        '</cal:conditional-format>'
        '<cal:conditional-format cal:target-range-address="Data.B1:Data.B10">'
        '<cal:condition cal:apply-style-name="cf" cal:value="duplicate"/>'
        '</cal:conditional-format></cal:conditional-formats></t:table>',
        styles:
            '<s:style s:name="cf" s:family="table-cell">'
            '<s:table-cell-properties f:background-color="#00ff00"/>'
            '</s:style>',
      ),
    );
    final sheet = book.sheets.first;
    final rules = sheet.conditionalFormats;
    expect(rules.length, 2);
    expect(rules[0].kind, SmlConditionalKind.contains);
    expect(rules[0].formula, 'app');
    expect(rules[1].kind, SmlConditionalKind.duplicate);
    expect(rules[0].matches(sheet.cellA1('A1'), sheet), isTrue);
    expect(rules[1].matches(sheet.cellA1('B1'), sheet), isTrue);

    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final archive = ZipDecoder().decodeBytes(saved);
    final sheetXml = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(sheetXml, contains('type="containsText"'));
    expect(sheetXml, contains('text="app"'));
    expect(sheetXml, contains('type="duplicateValues"'));
  });

  test('ODS begins-with and ends-with conditions keep their text', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data"><t:table-row><t:table-cell>'
        '<x:p>apple</x:p></t:table-cell></t:table-row>'
        '<cal:conditional-formats>'
        '<cal:conditional-format cal:target-range-address="Data.A1:Data.A10">'
        '<cal:condition cal:apply-style-name="cf" '
        'cal:value="begins-with(&quot;app&quot;)"/>'
        '</cal:conditional-format>'
        '<cal:conditional-format cal:target-range-address="Data.B1:Data.B10">'
        '<cal:condition cal:apply-style-name="cf" '
        'cal:value="ends-with(&quot;ple&quot;)"/>'
        '</cal:conditional-format></cal:conditional-formats></t:table>',
        styles:
            '<s:style s:name="cf" s:family="table-cell">'
            '<s:table-cell-properties f:background-color="#00ff00"/>'
            '</s:style>',
      ),
    );
    final sheet = book.sheets.first;
    expect(sheet.conditionalFormats[0].kind, SmlConditionalKind.beginsWith);
    expect(sheet.conditionalFormats[1].kind, SmlConditionalKind.endsWith);
    expect(
      sheet.conditionalFormats[0].matches(sheet.cellA1('A1'), sheet),
      isTrue,
    );
    expect(
      sheet.conditionalFormats[1].matches(sheet.cellA1('A1'), sheet),
      isTrue,
    );
    sheet.cellA1('A1').value = 'pear';
    expect(
      sheet.conditionalFormats[0].matches(sheet.cellA1('A1'), sheet),
      isFalse,
    );

    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final archive = ZipDecoder().decodeBytes(saved);
    final sheetXml = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(sheetXml, contains('type="beginsWith"'));
    expect(sheetXml, contains('type="endsWith"'));
    expect(sheetXml, contains('text="app"'));
  });

  test('ODS between conditions keep both bounds', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data"><t:table-row><t:table-cell '
        'o:value-type="float" o:value="5"><x:p>5</x:p></t:table-cell>'
        '</t:table-row><cal:conditional-formats>'
        '<cal:conditional-format cal:target-range-address="Data.A1:Data.A10">'
        '<cal:condition cal:apply-style-name="cf" cal:value="between(1,6)"/>'
        '</cal:conditional-format>'
        '<cal:conditional-format cal:target-range-address="Data.B1:Data.B10">'
        '<cal:condition cal:apply-style-name="cf" '
        'cal:value="not-between(1,6)"/>'
        '</cal:conditional-format></cal:conditional-formats></t:table>',
        styles:
            '<s:style s:name="cf" s:family="table-cell">'
            '<s:table-cell-properties f:background-color="#00ff00"/>'
            '</s:style>',
      ),
    );
    final sheet = book.sheets.first;
    expect(sheet.conditionalFormats.length, 2);
    final between = sheet.conditionalFormats.first;
    expect(between.kind, SmlConditionalKind.between);
    expect(between.formula, '1');
    expect(between.formula2, '6');
    expect(between.matches(sheet.cellA1('A1'), sheet), isTrue);
    expect(
      sheet.conditionalFormats.last.matches(sheet.cellA1('A1'), sheet),
      isFalse,
    );

    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final archive = ZipDecoder().decodeBytes(saved);
    final sheetXml = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(sheetXml, contains('operator="between"'));
    expect(sheetXml, contains('operator="notBetween"'));
    expect(
      '<formula>1</formula><formula>6</formula>'.allMatches(sheetXml).length,
      2,
    );
  });

  test('ODS conditional comparison operators keep their meaning', () {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data"><t:table-row><t:table-cell '
        'o:value-type="float" o:value="5"><x:p>5</x:p></t:table-cell>'
        '</t:table-row><cal:conditional-formats>'
        '<cal:conditional-format cal:target-range-address="Data.A1:Data.A10">'
        '<cal:condition cal:apply-style-name="cf" cal:value="&gt;=5"/>'
        '<cal:condition cal:apply-style-name="cf" cal:value="&lt;&gt;3"/>'
        '</cal:conditional-format></cal:conditional-formats></t:table>',
        styles:
            '<s:style s:name="cf" s:family="table-cell">'
            '<s:table-cell-properties f:background-color="#00ff00"/>'
            '</s:style>',
      ),
    );
    final sheet = book.sheets.first;
    final rules = sheet.conditionalFormats;
    expect(rules.length, 2);
    expect(rules[0].kind, SmlConditionalKind.greaterOrEqual);
    expect(rules[1].kind, SmlConditionalKind.notEqual);
    expect(rules[0].matches(sheet.cellA1('A1'), sheet), isTrue);
    expect(rules[1].matches(sheet.cellA1('A1'), sheet), isTrue);
    sheet.cellA1('A1').value = 3;
    expect(rules[1].matches(sheet.cellA1('A1'), sheet), isFalse);
  });

  test('ODS conditional formats import and serialize', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data"><t:table-row><t:table-cell '
        'o:value-type="float" o:value="5"><x:p>5</x:p></t:table-cell>'
        '</t:table-row><cal:conditional-formats>'
        '<cal:conditional-format cal:target-range-address="Data.A1:Data.A10">'
        '<cal:condition cal:apply-style-name="cf" cal:value="&gt;3"/>'
        '</cal:conditional-format></cal:conditional-formats></t:table>',
        styles:
            '<s:style s:name="cf" s:family="table-cell">'
            '<s:table-cell-properties f:background-color="#00ff00"/>'
            '</s:style>',
      ),
    );
    final rule = book.sheets.first.conditionalFormats.single;
    expect(rule.kind, SmlConditionalKind.greaterThan);
    expect(rule.formula, '3');
    expect(rule.fillRgb, '00FF00');
    expect(rule.range.start.a1, 'A1');
    expect(rule.range.end.a1, 'A10');
    final sheet = book.sheets.first;
    expect(rule.matches(sheet.cellA1('A1'), sheet), isTrue);
    sheet.cellA1('A1').value = 2;
    expect(rule.matches(sheet.cellA1('A1'), sheet), isFalse);

    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final archive = ZipDecoder().decodeBytes(saved);
    final sheetXml = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(sheetXml, contains('conditionalFormatting'));
    expect(sheetXml, contains('greaterThan'));
    expect(sheetXml, contains('dxfId="0"'));
    final stylesXml = utf8.decode(
      archive.findFile('xl/styles.xml')!.content as List<int>,
    );
    expect(stylesXml, contains('<dxfs count="1">'));
    expect(stylesXml, contains('FF00FF00'));
  });
}

void validationTests() {
  test(
    'shared numeric rules on blank input cells survive an XLSX copy',
    () async {
      final book = OdsSheetReader.readBytes(
        _ods(
          '<t:content-validations><t:content-validation t:name="whole" '
          't:allow-empty-cell="false" '
          't:condition="of:cell-content-is-whole-number() '
          'and cell-content-is-between(1,10)"/></t:content-validations>'
          '<t:table t:name="Input"><t:table-row>'
          '<t:table-cell t:content-validation-name="whole"/>'
          '</t:table-row></t:table>',
        ),
      );
      void check(SmlWorkbook workbook) {
        final rule = workbook.firstSheet.validations.single;
        expect(rule.kind, SmlValidationKind.whole);
        expect(rule.range.start.a1, 'A1');
        expect(rule.accepts('5'), isTrue);
        expect(rule.accepts('1.5'), isFalse);
        expect(rule.accepts('11'), isFalse);
        expect(rule.accepts(''), isFalse);
      }

      check(book);
      check(
        SheetDeserializer().readBytes(
          await OfficeIsolateSave.workbook(book, recalculate: false),
        ),
      );
    },
  );

  test('blank validation references obey expansion and grid limits', () {
    for (final repeat in [
      't:number-columns-repeated="16385"',
      't:number-rows-repeated="100001"',
    ]) {
      final rowRepeat = repeat.contains('rows') ? repeat : '';
      final cellRepeat = repeat.contains('columns') ? repeat : '';
      expect(
        () => OdsSheetReader.readBytes(
          _ods(
            '<t:content-validations><t:content-validation t:name="v" '
            't:condition="of:cell-content-is-in-list(&quot;Yes&quot;)"/>'
            '</t:content-validations><t:table><t:table-row $rowRepeat>'
            '<t:table-cell $cellRepeat t:content-validation-name="v"/>'
            '</t:table-row></t:table>',
          ),
        ),
        _invalidOds,
      );
    }
  });

  test(
    'spreadsheet-level list validations apply to every referring sheet',
    () async {
      final book = OdsSheetReader.readBytes(
        _ods(
          '<t:table t:name="First"><t:table-row>'
          '<t:table-cell t:content-validation-name="shared"/>'
          '</t:table-row></t:table>'
          '<t:table t:name="Second"><t:table-row>'
          '<t:table-cell t:content-validation-name="shared"/>'
          '</t:table-row></t:table>',
          extra:
              '<t:content-validations><t:content-validation t:name="shared" '
              't:condition="of:cell-content-is-in-list(&quot;Yes&quot;;&quot;No&quot;)" '
              't:allow-empty-cell="false"/></t:content-validations>',
        ),
      );
      void check(SmlWorkbook workbook) {
        for (final sheet in workbook.sheets) {
          final validation = sheet.validations.single;
          expect(validation.listItems, ['Yes', 'No']);
          expect(validation.allowBlank, isFalse);
          expect(validation.range.start.a1, 'A1');
          expect(validation.accepts('Yes'), isTrue);
          expect(validation.accepts('Maybe'), isFalse);
        }
      }

      check(book);
      check(
        SheetDeserializer().readBytes(
          await OfficeIsolateSave.workbook(book, recalculate: false),
        ),
      );
    },
  );

  test('spreadsheet-level range lists resolve a later source sheet', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:content-validations><t:content-validation t:name="shared" '
        't:condition="of:cell-content-is-in-list(\$Lists.\$A\$1:.\$A\$2)"/>'
        '</t:content-validations>'
        '<t:table t:name="Data"><t:table-row>'
        '<t:table-cell t:content-validation-name="shared"/>'
        '</t:table-row></t:table>'
        '<t:table t:name="Lists"><t:table-row>${_value('Red')}</t:table-row>'
        '<t:table-row>${_value('Green')}</t:table-row></t:table>',
      ),
    );
    expect(book.firstSheet.validations.single.listItems, ['Red', 'Green']);
    final reopened = SheetDeserializer().readBytes(
      await OfficeIsolateSave.workbook(book, recalculate: false),
    );
    expect(reopened.firstSheet.validations.single.listItems, ['Red', 'Green']);
  });

  test('table-local definitions stay isolated and override shared names', () {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Local"><t:content-validations>'
        '<t:content-validation t:name="v" '
        't:condition="of:cell-content-is-in-list(&quot;Local&quot;)"/>'
        '</t:content-validations><t:table-row>'
        '<t:table-cell t:content-validation-name="v"/>'
        '</t:table-row></t:table>'
        '<t:table t:name="Shared"><t:table-row>'
        '<t:table-cell t:content-validation-name="v"/>'
        '</t:table-row></t:table>',
        extra:
            '<t:content-validations><t:content-validation t:name="v" '
            't:condition="of:cell-content-is-in-list(&quot;Shared&quot;)"/>'
            '</t:content-validations>',
      ),
    );
    expect(book.sheets[0].validations.single.listItems, ['Local']);
    expect(book.sheets[1].validations.single.listItems, ['Shared']);
  });

  test('foreign validation containers cannot define spreadsheet rules', () {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table><t:table-row>'
        '<t:table-cell t:content-validation-name="v"/>'
        '</t:table-row></t:table>',
        extra:
            '<e:content-validations><t:content-validation t:name="v" '
            't:condition="of:cell-content-is-in-list(&quot;Spoof&quot;)"/>'
            '</e:content-validations>',
      ),
    );
    expect(book.firstSheet.validations, isEmpty);
  });

  test('ODS validation prompts and error styles round-trip', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data"><t:table-row><t:table-cell '
        't:content-validation-name="v"><x:p>1</x:p></t:table-cell>'
        '</t:table-row><t:content-validations>'
        '<t:content-validation t:name="v" '
        't:condition="of:cell-content-is-whole-number() '
        'and cell-content-is-between(1,5)">'
        '<t:help-message t:title="Enter"><x:p>One to five</x:p>'
        '</t:help-message>'
        '<t:error-message t:message-type="warning" t:title="Bad">'
        '<x:p>Out of range</x:p></t:error-message>'
        '</t:content-validation></t:content-validations></t:table>',
      ),
    );
    final validation = book.sheets.first.validations.single;
    expect(validation.promptTitle, 'Enter');
    expect(validation.prompt, 'One to five');
    expect(validation.errorTitle, 'Bad');
    expect(validation.error, 'Out of range');
    expect(validation.errorStyle, 'warning');

    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final archive = ZipDecoder().decodeBytes(saved);
    final sheetXml = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(sheetXml, contains('promptTitle="Enter"'));
    expect(sheetXml, contains('prompt="One to five"'));
    expect(sheetXml, contains('errorStyle="warning"'));
  });

  test('ODS custom formula validations translate relative refs', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data"><t:table-row><t:table-cell '
        't:content-validation-name="v"><x:p>1</x:p></t:table-cell>'
        '</t:table-row><t:content-validations>'
        '<t:content-validation t:name="v" '
        't:condition="of:is-true-formula([.A1]&gt;0)"/>'
        '</t:content-validations></t:table>',
      ),
    );
    final validation = book.sheets.first.validations.single;
    expect(validation.kind, SmlValidationKind.custom);
    expect(validation.formula1, 'A1>0');
    expect(validation.accepts('1'), isTrue);

    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final archive = ZipDecoder().decodeBytes(saved);
    final sheetXml = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(sheetXml, contains('type="custom"'));
    expect(sheetXml, contains('A1&gt;0'));
  });

  test('ODS whole, decimal, date and text-length validations import', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data">'
        '<t:table-row><t:table-cell t:content-validation-name="v1">'
        '<x:p>5</x:p></t:table-cell></t:table-row>'
        '<t:table-row><t:table-cell t:content-validation-name="v2">'
        '<x:p>2.5</x:p></t:table-cell></t:table-row>'
        '<t:table-row><t:table-cell t:content-validation-name="v3">'
        '<x:p>2024-01-02</x:p></t:table-cell></t:table-row>'
        '<t:table-row><t:table-cell t:content-validation-name="v4">'
        '<x:p>abc</x:p></t:table-cell></t:table-row>'
        '<t:content-validations>'
        '<t:content-validation t:name="v1" t:title="Whole" '
        't:message="Enter 1-10" t:condition="of:cell-content-is-whole-number() '
        'and cell-content-is-between(1,10)"/>'
        '<t:content-validation t:name="v2" '
        't:condition="of:cell-content-is-decimal-number() '
        'and cell-content()&gt;1.5"/>'
        '<t:content-validation t:name="v3" '
        't:condition="of:cell-content-is-date() '
        'and cell-content()&gt;=2024-1-1"/>'
        '<t:content-validation t:name="v4" '
        't:condition="of:cell-content-text-length()&lt;=5"/>'
        '</t:content-validations></t:table>',
      ),
    );
    final sheet = book.sheets.first;
    expect(sheet.validations.length, 4);
    expect(sheet.validations[0].kind, SmlValidationKind.whole);
    expect(sheet.validations[0].operator, SmlValidationOperator.between);
    expect(sheet.validations[0].errorTitle, 'Whole');
    expect(sheet.validations[0].error, 'Enter 1-10');
    expect(sheet.validations[0].accepts('5'), isTrue);
    expect(sheet.validations[0].accepts('11'), isFalse);
    expect(sheet.validations[1].operator, SmlValidationOperator.greaterThan);
    expect(sheet.validations[1].accepts('2'), isTrue);
    expect(sheet.validations[1].accepts('1'), isFalse);
    expect(sheet.validations[2].kind, SmlValidationKind.date);
    expect(
      sheet.validations[2].operator,
      SmlValidationOperator.greaterThanOrEqual,
    );
    expect(sheet.validations[2].accepts('2024-01-02'), isTrue);
    expect(sheet.validations[2].accepts('2023-12-31'), isFalse);
    expect(sheet.validations[3].kind, SmlValidationKind.textLength);
    expect(sheet.validations[3].accepts('abc'), isTrue);
    expect(sheet.validations[3].accepts('abcdef'), isFalse);

    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final archive = ZipDecoder().decodeBytes(saved);
    final sheetXml = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(sheetXml, contains('operator="greaterThan"'));
    expect(sheetXml, contains('operator="greaterThanOrEqual"'));
    expect(sheetXml, contains('operator="lessThanOrEqual"'));
    expect(sheetXml, contains('type="textLength"'));
    final reopened = SheetDeserializer().readBytes(saved);
    expect(
      reopened.sheets.first.validations[1].operator,
      SmlValidationOperator.greaterThan,
    );
  });

  test('ODS list source preserves spaces in quoted sheet names', () {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data"><t:table-row><t:table-cell '
        't:content-validation-name="v"><x:p>Pick</x:p></t:table-cell></t:table-row><t:content-validations>'
        '<t:content-validation t:name="v" '
        "t:condition=\"of:cell-content-is-in-list(\$'Choice List'.\$A\$1:.\$A\$2)\"/>"
        '</t:content-validations></t:table>'
        '<t:table t:name="Choice List"><t:table-row><t:table-cell>'
        '<x:p>Red</x:p></t:table-cell></t:table-row>'
        '<t:table-row><t:table-cell><x:p>Green</x:p></t:table-cell>'
        '</t:table-row></t:table>',
      ),
    );
    expect(book.sheets.first.validations.single.listItems, ['Red', 'Green']);
  });

  test(
    'ODS validation source range is bounded before scanning empty cells',
    () {
      expect(
        () => OdsSheetReader.readBytes(
          _ods(
            '<t:table t:name="Data"><t:table-row><t:table-cell '
            't:content-validation-name="v"><x:p>Pick</x:p></t:table-cell></t:table-row><t:content-validations>'
            '<t:content-validation t:name="v" '
            't:condition="of:cell-content-is-in-list(\$Lists.\$A\$1:.\$C\$1000000)"/>'
            '</t:content-validations></t:table>'
            '<t:table t:name="Lists"><t:table-row><t:table-cell>'
            '<x:p>Red</x:p></t:table-cell></t:table-row></t:table>',
          ),
        ),
        throwsA(
          isA<OdsSheetFormatException>().having(
            (error) => error.toString(),
            'reason',
            contains('validation source work limit'),
          ),
        ),
      );
    },
  );

  test('ODS range-source list validations resolve across sheets', () {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data"><t:table-row><t:table-cell '
        't:content-validation-name="v"><x:p>Pick</x:p></t:table-cell>'
        '</t:table-row><t:content-validations>'
        '<t:content-validation t:name="v" '
        't:condition="of:cell-content-is-in-list(\$Lists.\$A\$1:.\$A\$2)"/>'
        '</t:content-validations></t:table>'
        '<t:table t:name="Lists"><t:table-row><t:table-cell>'
        '<x:p>Red</x:p></t:table-cell></t:table-row>'
        '<t:table-row><t:table-cell><x:p>Green</x:p></t:table-cell>'
        '</t:table-row></t:table>',
      ),
    );
    final validation = book.sheets.first.validations.single;
    expect(validation.listItems, ['Red', 'Green']);
    expect(validation.accepts('Green'), isTrue);
    expect(validation.accepts('Blue'), isFalse);
  });

  test('ODS validation source work is shared across definitions', () {
    final cells = [
      for (var i = 0; i < 3; i++)
        '<t:table-cell t:content-validation-name="v$i"><x:p>Pick</x:p></t:table-cell>',
    ].join();
    final rules = [
      for (var i = 0; i < 3; i++)
        '<t:content-validation t:name="v$i" '
            't:condition="of:cell-content-is-in-list(\$Lists.\$A\$1:.\$A\$1000000)"/>',
    ].join();
    expect(
      () => OdsSheetReader.readBytes(
        _ods(
          '<t:table t:name="Data"><t:table-row>$cells</t:table-row>'
          '<t:content-validations>$rules</t:content-validations></t:table>'
          '<t:table t:name="Lists"><t:table-row><t:table-cell>'
          '<x:p>Red</x:p></t:table-cell></t:table-row></t:table>',
        ),
      ),
      throwsA(
        isA<OdsSheetFormatException>().having(
          (error) => error.toString(),
          'reason',
          contains('validation source work limit'),
        ),
      ),
    );
  });

  test('ODS list validations become typed XLSX validations', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data">'
        '<t:table-row><t:table-cell t:content-validation-name="v">'
        '<x:p>Red</x:p></t:table-cell></t:table-row>'
        '<t:table-row><t:table-cell t:content-validation-name="v">'
        '<x:p>Green</x:p></t:table-cell></t:table-row>'
        '<t:content-validations><t:content-validation t:name="v" '
        't:condition="of:cell-content-is-in-list(&quot;Red&quot;;&quot;Green&quot;)" '
        't:allow-empty-cell="false"/></t:content-validations></t:table>',
      ),
    );
    final sheet = book.sheets.first;
    expect(sheet.validations.length, 2);
    expect(sheet.validations.first.kind, SmlValidationKind.list);
    expect(sheet.validations.first.listItems, ['Red', 'Green']);
    expect(sheet.validations.first.allowBlank, isFalse);
    expect(sheet.validations.first.range.start.a1, 'A1');
    expect(sheet.validations.last.range.start.a1, 'A2');
    expect(sheet.validations.first.accepts('Green'), isTrue);
    expect(sheet.validations.first.accepts('Blue'), isFalse);

    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final archive = ZipDecoder().decodeBytes(saved);
    final sheetXml = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(sheetXml, contains('type="list"'));
    expect(sheetXml, contains('"Red,Green"'));

    final reopened = SheetDeserializer().readBytes(saved);
    expect(reopened.sheets.first.validations.first.listItems, ['Red', 'Green']);
  });
}

void metadataTests() {
  test('ODS tab colour survives save and reopen', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data" t:style-name="taColor">'
        '<t:table-row><t:table-cell><x:p>Data</x:p></t:table-cell>'
        '</t:table-row></t:table>',
        styles:
            '<s:style s:name="taColor" s:family="table">'
            '<s:table-properties t:tab-color="#ff0000"/></s:style>',
      ),
    );
    expect(book.sheets.first.tabColorRgb, 'FF0000');
    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final archive = ZipDecoder().decodeBytes(saved);
    final sheetXml = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(sheetXml, contains('tabColor rgb="FFFF0000"'));
    final reopened = SheetDeserializer().readBytes(saved);
    expect(reopened.sheets.first.tabColorRgb, 'FF0000');
  });

  test('ODS print areas, titles, names and autofilter survive save', () async {
    final book = OdsSheetReader.readBytes(
      _ods(
        '<t:table t:name="Data" t:print-ranges="Data.A1:Data.B3">'
        '<t:table-row><t:table-cell><x:p>Name</x:p></t:table-cell>'
        '<t:table-cell><x:p>Qty</x:p></t:table-cell></t:table-row>'
        '<t:table-row><t:table-cell><x:p>A</x:p></t:table-cell>'
        '<t:table-cell o:value-type="float" o:value="1"><x:p>1</x:p>'
        '</t:table-cell></t:table-row>'
        '<t:named-expressions>'
        '<t:named-expression t:name="Excel_BuiltIn_Print_Titles" '
        't:expression="[\$Data.\$1:.\$1];[\$Data.\$A:.\$A]"/>'
        '</t:named-expressions></t:table>',
        extra:
            '<t:named-expressions><t:named-range t:name="Sales" '
            't:cell-range-address="\$Data.\$A\$2:.\$B\$3"/></t:named-expressions>'
            '<t:database-ranges><t:database-range '
            't:target-range-address="Data.A1:Data.B3"/></t:database-ranges>',
      ),
    );
    final sheet = book.sheets.first;
    String rangeA1(SmlRange range) => '${range.start.a1}:${range.end.a1}';
    expect(rangeA1(sheet.printArea!), 'A1:B3');
    expect(rangeA1(sheet.printTitleRows!), 'A1:A1');
    expect(rangeA1(sheet.printTitleCols!), 'A1:A1');
    expect(rangeA1(sheet.autoFilter!.range), 'A1:B3');
    expect(book.namedRanges.single.name, 'Sales');
    expect(book.namedRanges.single.sheetName, 'Data');
    expect(
      '${book.namedRanges.single.range.start.a1}:'
          '${book.namedRanges.single.range.end.a1}',
      'A2:B3',
    );

    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final archive = ZipDecoder().decodeBytes(saved);
    final workbookXml = utf8.decode(
      archive.findFile('xl/workbook.xml')!.content as List<int>,
    );
    final sheetXml = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(workbookXml, contains('_xlnm.Print_Area'));
    expect(workbookXml, contains('_xlnm.Print_Titles'));
    expect(workbookXml, contains('Sales'));
    expect(sheetXml, contains('autoFilter'));

    final reopened = SheetDeserializer().readBytes(saved);
    final restored = reopened.sheets.first;
    expect(rangeA1(restored.printArea!), 'A1:B3');
    expect(rangeA1(restored.printTitleRows!), 'A1:A1');
    expect(rangeA1(restored.printTitleCols!), 'A1:A1');
    expect(rangeA1(restored.autoFilter!.range), 'A1:B3');
    expect(reopened.namedRanges.single.name, 'Sales');
  });
}
