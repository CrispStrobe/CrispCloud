import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OpcPackage _source() => OpcPackage.openBytes(
  File(
    'test/fixtures/fidelity/sheet-normal-font-native.xlsx',
  ).readAsBytesSync(),
);

void _data(OpcPackage package, String xml) {
  final part = package.getPart('/xl/worksheets/sheet1.xml')!;
  part.writeText(
    part.readText().replaceFirst(
      RegExp(r'<sheetData>.*?</sheetData>', dotAll: true),
      '<sheetData>$xml</sheetData>',
    ),
  );
}

Map<String, String?> _styles(OpcPackage package) {
  final root = XmlDocument.parse(
    package.getPart('/xl/worksheets/sheet1.xml')!.readText(),
  ).root!;
  return <String, String?>{
    for (final row in root.firstChild('sheetData')!.childrenNamed('row'))
      for (final cell in row.childrenNamed('c'))
        cell.getAttribute('r')!: cell.getAttribute('s'),
  };
}

void _secondStyle(OpcPackage package) {
  final part = package.getPart('/xl/styles.xml')!;
  part.writeText(
    part
        .readText()
        .replaceFirst('<cellXfs count="1">', '<cellXfs count="2">')
        .replaceFirst(
          '</cellXfs>',
          '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" '
              'xfId="1" applyFont="1"/></cellXfs>',
        ),
  );
}

void main() {
  test(
    'explicit native style zero survives three direct and isolate saves',
    () async {
      final source = _source();
      final styles = source.getPart('/xl/styles.xml')!.readText();
      var book = SheetDeserializer().read(source);
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = cycle == 2
            ? await OfficeIsolateSave.workbook(book)
            : SheetSerializer().writeBytes(book);
        final saved = OpcPackage.openBytes(bytes);
        expect(_styles(saved), {'A1': '0'});
        expect(saved.getPart('/xl/styles.xml')!.readText(), styles);
        book = SheetDeserializer().read(saved);
        expect(book.firstSheet.cellA1('A1').hasExplicitStyleIndex, isTrue);
      }
    },
  );

  test(
    'an omitted source style remains omitted through repeated saves',
    () async {
      final source = _source();
      final part = source.getPart('/xl/worksheets/sheet1.xml')!;
      part.writeText(part.readText().replaceFirst(' s="0"', ''));
      var book = SheetDeserializer().read(source);
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = cycle == 2
            ? await OfficeIsolateSave.workbook(book)
            : SheetSerializer().writeBytes(book);
        final saved = OpcPackage.openBytes(bytes);
        expect(_styles(saved), {'A1': null});
        book = SheetDeserializer().read(saved);
        expect(book.firstSheet.cellA1('A1').hasExplicitStyleIndex, isFalse);
      }
    },
  );

  test('mixed explicit zero nonzero and absent styles are not normalized', () {
    final source = _source();
    _secondStyle(source);
    _data(
      source,
      '<row r="1"><c r="A1" s="0"><v>1</v></c>'
      '<c r="B1" s="1"><v>2</v></c><c r="C1"><v>3</v></c></row>',
    );
    final originalStyles = source.getPart('/xl/styles.xml')!.readText();
    final book = SheetDeserializer().read(source);
    book.firstSheet.setColumnWidth(2, 96);
    final saved = SheetSerializer().write(book);
    expect(_styles(saved), {'A1': '0', 'B1': '1', 'C1': null});
    expect(saved.getPart('/xl/styles.xml')!.readText(), originalStyles);
  });

  test('editing a native explicit style respects zero and nonzero values', () {
    final source = _source();
    _secondStyle(source);
    final book = SheetDeserializer().read(source);
    final cell = book.firstSheet.cellA1('A1');
    cell.styleIndex = 1;
    // Keep the modeled direct font equal to the newly chosen existing style.
    cell.fontSize = book.styles!.sizeAt(1);
    expect(_styles(SheetSerializer().write(book)), {'A1': '1'});
    cell.styleIndex = 0;
    cell.fontSize = book.styles!.sizeAt(0);
    expect(_styles(SheetSerializer().write(book)), {'A1': '0'});
  });

  test('row and column moves retain the originating cell style presence', () {
    final source = _source();
    _data(
      source,
      '<row r="1"><c r="A1" s="0"><v>1</v></c>'
      '<c r="B1"><v>2</v></c></row>',
    );
    final book = SheetDeserializer().read(source);
    book.firstSheet.insertRows(0);
    book.firstSheet.insertCols(0, 2);
    expect(_styles(SheetSerializer().write(book)), {'C2': '0', 'D2': null});
    book.firstSheet.deleteRows(0);
    book.firstSheet.deleteCols(0, 2);
    expect(_styles(SheetSerializer().write(book)), {'A1': '0', 'B1': null});
  });

  test('sorting carries explicit style presence with each copied cell', () {
    final source = _source();
    _data(
      source,
      '<row r="1"><c r="A1"><v>0</v></c></row>'
      '<row r="2"><c r="A2" s="0"><v>2</v></c></row>'
      '<row r="3"><c r="A3"><v>1</v></c></row>',
    );
    final book = SheetDeserializer().read(source);
    SmlAnalysis.sort(book.firstSheet, SmlRange.parse('A1:A3'), [
      const SmlSortKey(column: 0),
    ]);
    expect(book.firstSheet.cellA1('A2').value, 1);
    expect(book.firstSheet.cellA1('A3').value, 2);
    expect(_styles(SheetSerializer().write(book)), {
      'A1': null,
      'A2': null,
      'A3': '0',
    });
  });

  test(
    'an empty cell explicitly selecting style zero retains that selection',
    () {
      final source = _source();
      _data(source, '<row r="1"><c r="A1" s="0"/><c r="B1"/></row>');
      final book = SheetDeserializer().read(source);
      expect(_styles(SheetSerializer().write(book)), {'A1': '0', 'B1': null});
    },
  );
}
