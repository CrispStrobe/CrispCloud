import 'dart:convert';
import 'dart:typed_data';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

Uint8List calcFixture(String contents) {
  final zip = ZipWriter();
  zip.addFile(
    'content.xml',
    utf8.encode('''
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
<office:body><office:spreadsheet><table:table table:name="Calc">
<table:table-row><table:table-cell office:value-type="string">$contents</table:table-cell></table:table-row>
</table:table></office:spreadsheet></office:body></office:document-content>'''),
  );
  return zip.close();
}

void main() {
  test('Calc literal spaces survive cell import, preview and search', () async {
    final bytes = calcFixture(
      '<text:p>  authored  spaces</text:p><text:p>second line </text:p>',
    );
    const expected = '  authored  spaces\nsecond line ';
    expect(
      OdsSheetReader.readBytes(bytes).firstSheet.cellA1('A1').value,
      expected,
    );
    expect(
      OfficeTextExtractor.extract(bytes, name: 'calc.ods').sheets.single.rows,
      [
        [expected],
      ],
    );
    expect(await officeSearchText(bytes, 'calc.ods', 65536), expected);
  });
  test(
    'ODS export makes authored whitespace explicit for other ODF readers',
    () {
      final sheet = SmlWorksheet(name: 'Values', sheetId: 1);
      sheet.cellA1('A1').value = '  A  B\tC\nD ';
      final bytes = OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [sheet]));
      final xml = utf8.decode(ZipReader.fromBytes(bytes).read('content.xml'));
      expect(xml, contains('<text:s text:c="2"/>'));
      expect(xml, contains('<text:tab/>'));
      expect(xml, contains('<text:line-break/>'));
      expect(
        OdsSheetReader.readBytes(bytes).firstSheet.cellA1('A1').value,
        '  A  B\tC\nD ',
      );
    },
  );
}
