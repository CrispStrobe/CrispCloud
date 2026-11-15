import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

Uint8List _ods(String tables, {String styles = '', String? namedStyles}) {
  final zip = ZipWriter();
  const bindings =
      'xmlns:o="$_office" xmlns:t="$_table" '
      'xmlns:x="$_text" xmlns:s="$_style" xmlns:f="$_fo" '
      'xmlns:e="urn:test:extension"';
  zip.addFile(
    'content.xml',
    utf8.encode(
      '<o:document-content $bindings>'
      '<o:automatic-styles>$styles</o:automatic-styles>'
      '<o:body><o:spreadsheet>$tables</o:spreadsheet></o:body>'
      '</o:document-content>',
    ),
  );
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

Matcher get _invalidOds => throwsA(isA<OdsSheetFormatException>());

/// Synthetic LibreOffice-generated ODS (values, formulas, styles, merge).
void main() {
  final bytes = File(
    'test/fixtures/fidelity/legacy-sheet.ods',
  ).readAsBytesSync();

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

  test('rejects a non-ODF package', () {
    expect(
      () => OdsSheetReader.readBytes(Uint8List.fromList(List.filled(64, 0))),
      throwsA(isA<OdsSheetFormatException>()),
    );
  });

  test(
    'merged covered cells consume one coordinate and retain row spans',
    () async {
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
    },
  );

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
    expect(sheet.columnWidths[0], closeTo(96, .01));
    expect(sheet.columnWidths[1], closeTo(96, .01));
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
    final table =
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

  test(
    'rejects invalid or out-of-range meaningful repeats instead of clipping',
    () {
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
    },
  );

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
    (name: 'omitted placeholder', span: 2, covered: '', nextColumn: 2),
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

  test('a new origin clears unconsumed merge placeholders', () async {
    final book = OdsSheetReader.readBytes(
      _odsRows('''
      <table:table-row>
        <table:table-cell office:value-type="string" table:number-columns-spanned="2"><text:p>First</text:p></table:table-cell>
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
  });

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

Future<SmlWorkbook> _roundTrip(SmlWorkbook book) async => SheetDeserializer()
    .readBytes(await OfficeIsolateSave.workbook(book, recalculate: false));

String _xmlAttribute(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('"', '&quot;');

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
