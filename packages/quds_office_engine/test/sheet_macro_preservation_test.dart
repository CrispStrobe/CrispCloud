import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

Uint8List _package({required bool template, bool macro = false}) {
  final source = ZipDecoder().decodeBytes(
    File('test/fixtures/fidelity/native.xlsx').readAsBytesSync(),
  );
  final files = <String, List<int>>{};
  for (final file in source.files) {
    if (file.isFile) files[file.name] = file.content as List<int>;
  }
  var types = utf8.decode(files['[Content_Types].xml']!);
  types = types.replaceFirst(
    template
        ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml'
        : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
    template
        ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.template.main+xml'
        : 'application/vnd.ms-excel.sheet.macroEnabled.main+xml',
  );
  if (macro) {
    types = types.replaceFirst(
      '</Types>',
      '<Override PartName="/xl/vbaProject.bin" '
          'ContentType="application/vnd.ms-office.vbaProject"/></Types>',
    );
    files['xl/vbaProject.bin'] = utf8.encode('INERT-VBA-BYTES');
    final rels = utf8.decode(files['xl/_rels/workbook.xml.rels']!);
    files['xl/_rels/workbook.xml.rels'] = utf8.encode(
      rels.replaceFirst(
        '</Relationships>',
        '<Relationship Id="rIdVba" '
            'Type="http://schemas.microsoft.com/office/2006/relationships/vbaProject" '
            'Target="vbaProject.bin"/></Relationships>',
      ),
    );
  }
  files['[Content_Types].xml'] = utf8.encode(types);
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Map<String, List<int>> _unzip(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  return {
    for (final file in archive.files)
      if (file.isFile) file.name: file.content as List<int>,
  };
}

void main() {
  test(
    'editing an xlsm keeps the macro project and main content type',
    () async {
      final book = SheetDeserializer().readBytes(
        _package(template: false, macro: true),
      );
      book.sheets.first.cellA1('A1').value = 'Changed';
      final saved = _unzip(
        await OfficeIsolateSave.workbook(book, recalculate: false),
      );
      expect(saved, contains('xl/vbaProject.bin'));
      expect(
        utf8.decode(saved['[Content_Types].xml']!),
        contains('macroEnabled'),
      );
      expect(
        utf8.decode(saved['xl/_rels/workbook.xml.rels']!),
        contains('vbaProject'),
      );
    },
  );

  test('editing an xltx keeps the template main content type', () async {
    final book = SheetDeserializer().readBytes(_package(template: true));
    book.sheets.first.cellA1('A1').value = 'Changed';
    final saved = _unzip(
      await OfficeIsolateSave.workbook(book, recalculate: false),
    );
    final types = utf8.decode(saved['[Content_Types].xml']!);
    expect(types, contains('spreadsheetml.template.main+xml'));
    expect(types, isNot(contains('spreadsheetml.sheet.main+xml')));
  });
}
