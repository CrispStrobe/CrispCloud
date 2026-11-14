import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _x = OfficeNamespaces.x;
const _addresses = ['A1', 'B1', 'C1', 'D1', 'E1', 'F1'];
const _fillIds = [3, 4, 5, 6, 2, 1];

String _nativeStyles() =>
    File('test/fixtures/fidelity/sheet-fill-native.xml').readAsStringSync();

SmlWorkbook _book({String? rows}) {
  final package = OpcPackage.create(OpcPackageKind.sheet);
  package
      .createPart('/xl/styles.xml', OfficeContentTypes.sheetStyles)
      .writeText(_nativeStyles());
  package
      .relationshipsFor('/xl/workbook.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  package
      .getPart('/xl/worksheets/sheet1.xml')!
      .writeText(
        '<s:worksheet xmlns:s="$_x"><s:sheetData>'
        '${rows ?? '<s:row r="1">${[for (var i = 0; i < _addresses.length; i++) '<s:c r="${_addresses[i]}" s="$i"><s:v>${i + 1}</s:v></s:c>'].join()}</s:row>'}'
        '</s:sheetData></s:worksheet>',
      );
  return SheetDeserializer().read(package);
}

XmlElement _styles(OpcPackage package) =>
    XmlDocument.parse(package.getPart('/xl/styles.xml')!.readText()).root!;

List<XmlElement> _entries(XmlElement root, String container, String name) =>
    root
        .firstChild(container, namespaceUri: _x)!
        .childrenNamed(name, namespaceUri: _x);

XmlElement _savedFill(OpcPackage package, String ref) {
  final sheet = XmlDocument.parse(
    package.getPart('/xl/worksheets/sheet1.xml')!.readText(),
  ).root!;
  final cell = sheet
      .firstChild('sheetData', namespaceUri: _x)!
      .childrenNamed('row', namespaceUri: _x)
      .expand((row) => row.childrenNamed('c', namespaceUri: _x))
      .singleWhere((cell) => cell.getAttribute('r', namespaceUri: '') == ref);
  final styles = _styles(package);
  final xf = _entries(
    styles,
    'cellXfs',
    'xf',
  )[int.parse(cell.getAttribute('s', namespaceUri: '') ?? '0')];
  return _entries(styles, 'fills', 'fill')[int.parse(
    xf.getAttribute('fillId', namespaceUri: '') ?? '0',
  )];
}

String _xml(XmlElement element) =>
    XmlDocument(root: element).toXmlString(declaration: false);

void _expectDirectFill(XmlElement fill, String rgb) {
  expect(fill.firstChild('gradientFill', namespaceUri: _x), isNull);
  final pattern = fill.firstChild('patternFill', namespaceUri: _x)!;
  expect(pattern.getAttribute('patternType'), rgb.isEmpty ? 'none' : 'solid');
  final color = pattern.firstChild('fgColor', namespaceUri: _x);
  if (rgb.isEmpty) {
    expect(color, isNull);
  } else {
    expect(color!.getAttribute('rgb'), 'FF$rgb');
    for (final name in ['theme', 'indexed', 'tint', 'auto']) {
      expect(color.getAttribute(name), isNull);
    }
  }
}

void main() {
  for (final edit in ['bold', 'alignment']) {
    test(
      'native fills survive an unrelated $edit edit and three saves',
      () async {
        final nativeFills = _entries(
          XmlDocument.parse(_nativeStyles()).root!,
          'fills',
          'fill',
        );
        var book = _book();
        for (final cell in book.firstSheet.allCells) {
          expect(cell.hasExplicitFillColorEdit, isFalse);
          if (edit == 'bold') {
            cell.fontBold = true;
          } else {
            cell.horizontalAlign = SmlHAlign.center;
          }
        }
        for (var cycle = 0; cycle < 3; cycle++) {
          final saved = OpcPackage.openBytes(
            cycle == 1
                ? await OfficeIsolateSave.workbook(book)
                : SheetSerializer().writeBytes(book),
          );
          for (var i = 0; i < _addresses.length; i++) {
            expect(
              _xml(_savedFill(saved, _addresses[i])),
              _xml(nativeFills[_fillIds[i]]),
              reason: '${_addresses[i]} cycle $cycle',
            );
          }
          book = SheetDeserializer().read(saved);
        }
      },
    );
  }

  test(
    'equal RGB commands replace native fill semantics without style growth',
    () {
      final book = _book();
      for (final cell in book.firstSheet.allCells) {
        cell.fillRgb = cell.fillRgb;
        expect(cell.hasExplicitFillColorEdit, isTrue);
      }
      int? count;
      for (var cycle = 0; cycle < 3; cycle++) {
        final saved = SheetSerializer().write(book);
        for (final address in _addresses) {
          _expectDirectFill(
            _savedFill(saved, address),
            book.firstSheet.cellA1(address).fillRgb,
          );
        }
        final current = _entries(_styles(saved), 'cellXfs', 'xf').length;
        count ??= current;
        expect(
          current,
          count,
          reason: 'Repeated saves must reuse the edited style',
        );
        expect(_entries(_styles(saved), 'fills', 'fill'), hasLength(8));
      }
    },
  );

  test('explicit fill intent survives isolate save and reopen', () async {
    var book = _book();
    book.firstSheet.cellA1('A1').fillRgb = '000000';
    book.firstSheet.cellA1('B1').fillRgb = 'FF0000';
    book.firstSheet.cellA1('C1').fillRgb = '';
    for (var cycle = 0; cycle < 3; cycle++) {
      final saved = OpcPackage.openBytes(
        await OfficeIsolateSave.workbook(book),
      );
      _expectDirectFill(_savedFill(saved, 'A1'), '000000');
      _expectDirectFill(_savedFill(saved, 'B1'), 'FF0000');
      _expectDirectFill(_savedFill(saved, 'C1'), '');
      expect(
        _savedFill(saved, 'D1')
            .firstChild('patternFill', namespaceUri: _x)!
            .firstChild('fgColor', namespaceUri: _x)!
            .getAttribute('indexed'),
        '2',
      );
      book = SheetDeserializer().read(saved);
      expect(book.firstSheet.cellA1('A1').hasExplicitFillColorEdit, isFalse);
    }
  });

  test('sorting carries fill intent with the originating cell', () {
    final book = _book(
      rows:
          '<s:row r="1"><s:c r="A1" s="0"><s:v>0</s:v></s:c></s:row>'
          '<s:row r="2"><s:c r="A2" s="0"><s:v>2</s:v></s:c></s:row>'
          '<s:row r="3"><s:c r="A3" s="0"><s:v>1</s:v></s:c></s:row>',
    );
    book.firstSheet.cellA1('A2').fillRgb = '000000';
    SmlAnalysis.sort(book.firstSheet, SmlRange.parse('A1:A3'), [
      const SmlSortKey(column: 0),
    ]);
    expect(book.firstSheet.cellA1('A2').value, 1);
    expect(book.firstSheet.cellA1('A2').hasExplicitFillColorEdit, isFalse);
    expect(book.firstSheet.cellA1('A3').value, 2);
    expect(book.firstSheet.cellA1('A3').hasExplicitFillColorEdit, isTrue);
    final saved = SheetSerializer().write(book);
    expect(
      _savedFill(saved, 'A2')
          .firstChild('patternFill', namespaceUri: _x)!
          .firstChild('fgColor', namespaceUri: _x)!
          .getAttribute('theme'),
      '1',
    );
    _expectDirectFill(_savedFill(saved, 'A3'), '000000');
  });
}
