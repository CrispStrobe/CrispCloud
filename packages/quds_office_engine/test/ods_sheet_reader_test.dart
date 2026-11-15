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

String _xmlAttribute(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('"', '&quot;');

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
    test(
      'formula roundtrip preserves imported syntax: ${formula.key}',
      () async {
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
      },
    );
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
}
