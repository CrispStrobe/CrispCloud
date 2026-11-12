import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _fixture = 'test/fixtures/fidelity/sheet-qualified-names-native.xlsx';

SmlWorkbook _read() =>
    SheetDeserializer().readBytes(File(_fixture).readAsBytesSync());

Object? _eval(SmlWorkbook book, String formula, {int sheet = 2}) =>
    evaluateFormula(
      formula,
      FormulaContext(
        workbook: book,
        sheet: book.sheets[sheet],
        origin: SmlCellRef.parse('Z20'),
      ),
    );

XmlElement _xmlCell(OpcPackage package, int sheet, String address) =>
    XmlDocument.parse(
          package.getPart('/xl/worksheets/sheet$sheet.xml')!.readText(),
        ).root!
        .firstChild('sheetData')!
        .childrenNamed('row')
        .expand((row) => row.childrenNamed('c'))
        .singleWhere((cell) => cell.getAttribute('r') == address);

List<Map<String, String>> _definitions(OpcPackage package) => [
  for (final node in XmlDocument.parse(
    package.getPart('/xl/workbook.xml')!.readText(),
  ).root!.firstChild('definedNames')!.childrenNamed('definedName'))
    {
      for (final attribute in node.attributes)
        attribute.qualifiedName: attribute.value,
      'definition': node.text,
    },
];

SmlWorkbook _withDefinition(String definition, {String name = 'Probe'}) {
  final package = OpcPackage.openBytes(File(_fixture).readAsBytesSync());
  final part = package.getPart('/xl/workbook.xml')!;
  final document = XmlDocument.parse(part.readText());
  final node = XmlElement(localName: 'definedName')
    ..setAttribute('name', name)
    ..setAttribute('localSheetId', '1')
    ..text = definition;
  document.root!.firstChild('definedNames')!.children.add(node);
  part.writeText(document.toXmlString());
  return SheetDeserializer().read(package);
}

void main() {
  test(
    'localSheetId is the worksheet index and locals precede global names',
    () {
      final book = _read();
      expect(book.sheets.map((sheet) => sheet.sheetId), [41, 7, 99]);
      expect(_eval(book, 'Price', sheet: 0), 13);
      expect(_eval(book, 'Price', sheet: 1), 7);
      expect(_eval(book, 'Price'), 11);
    },
  );

  test(
    'qualified names select their scope independently of the target sheet',
    () {
      final book = _read();
      expect(_eval(book, 'aLpHa!pRiCe'), 13);
      expect(_eval(book, "'O''Brien Data'!pRiCe"), 7);
      expect(_eval(book, "SUM('O''Brien Data'!Points)"), 16);
      expect(_eval(book, "'O''Brien Data'!Foreign"), 17);
      expect(_eval(book, "'O''Brien Data'!_Local.Total"), 9);
      expect(_eval(book, "'O''Brien Data'!قيمة"), 7);
    },
  );

  test(
    'named scalar constants preserve boolean, text, error and numeric types',
    () {
      final book = _read();
      expect(_eval(book, "'O''Brien Data'!Flag"), isTrue);
      expect(_eval(book, "'O''Brien Data'!Text"), '#REF!');
      expect(_eval(book, "ISERROR('O''Brien Data'!Text)"), isFalse);
      expect(_eval(book, "ISERROR('O''Brien Data'!Problem)"), isTrue);
      expect(_eval(book, "'O''Brien Data'!Rate"), -2.5);
      expect(_eval(book, "SUM('O''Brien Data'!Errors)"), '#DIV/0!');
    },
  );

  test(
    'unsupported local definitions shadow globals and retain typed caches',
    () {
      final book = _read();
      FormulaDepGraph(book).recalculate();
      final sheet = book.sheets[2];
      expect(sheet.cellA1('D13').value, 42);
      expect(sheet.cellA1('D14').value, isTrue);
      expect(sheet.cellA1('D15').value, '#REF!');
      expect(sheet.cellA1('D15').type, SmlCellType.string);
      expect(sheet.cellA1('D16').value, '#N/A');
      expect(sheet.cellA1('D16').type, SmlCellType.error);
      expect(sheet.cellA1('D17').value, 81);
      expect(sheet.cellA1('D18').value, 73);
    },
  );

  test('named dependencies recalculate before users, including range ends', () {
    final book = _read();
    book.namedRanges.add(
      SmlNamedRange(
        name: 'Later',
        sheetName: 'Summary',
        range: SmlRange.parse('Z30:Z31'),
        localSheetId: 0,
      ),
    );
    book.firstSheet.cellA1('D1')
      ..formula = 'SUM(Alpha!Later)'
      ..value = 999;
    book.sheets[2].cellA1('Z30')
      ..formula = '2+5'
      ..value = 123;
    book.sheets[2].cellA1('Z31')
      ..formula = "'O''Brien Data'!Price*2"
      ..value = 123;
    FormulaDepGraph(book).recalculate();
    expect(book.firstSheet.cellA1('D1').value, 21);
    book.sheets[1].cellA1('B2').value = 20;
    FormulaDepGraph(book).recalculate();
    expect(book.firstSheet.cellA1('D1').value, 47);
  });

  test('cross-sheet lazy formulas evaluate in their own local scope', () {
    final book = _read();
    book.sheets[1].cellA1('Z30')
      ..formula = 'Price+B3'
      ..value = null;
    expect(_eval(book, "'O''Brien Data'!Z30"), 16);
    expect(_eval(book, "LET(Price,100,'O''Brien Data'!Z30)"), 16);
    expect(_eval(book, "LET(Price,100,'O''Brien Data'!Price+Price)"), 107);
  });

  test('every named cycle member loses its stale numeric cache', () {
    final book = _read();
    book.firstSheet.cellA1('B3')
      ..formula = "'O''Brien Data'!Price+1"
      ..value = 600;
    book.sheets[1].cellA1('B2')
      ..formula = 'Alpha!Price+1'
      ..value = 700;
    final graph = FormulaDepGraph(book)..recalculate();
    expect(graph.circular, {'Alpha!B3', "O'Brien Data!B2"});
    for (final cell in [
      book.firstSheet.cellA1('B3'),
      book.sheets[1].cellA1('B2'),
      book.sheets[2].cellA1('D1'),
      book.sheets[2].cellA1('D2'),
    ]) {
      expect(cell.value, '#CIRC!');
      expect(cell.type, SmlCellType.error);
    }
  });

  test('LET bindings and missing target sheets do not manufacture cycles', () {
    final book = _read();
    book.firstSheet.cellA1('B3')
      ..formula = 'LET(Price,6,Price+1)'
      ..value = 123;
    book.sheets[2].cellA1('Z30')
      ..formula = 'Absent!Z30'
      ..value = 321;
    final graph = FormulaDepGraph(book)..recalculate();
    expect(graph.circular, isEmpty);
    expect(book.firstSheet.cellA1('B3').value, 7);
    expect(book.sheets[2].cellA1('Z30').value, '#REF!');
    expect(_eval(book, 'Absent!Price'), '#REF!');
  });

  for (final definition in [
    r'SUM(Alpha!$B$2,Alpha!$B$3)',
    r'Alpha!B2',
    r'Alpha!$B2',
    r'Alpha!B$2',
    r'Alpha!$B:$B',
    r'Alpha!$2:$3',
    r"'[Remote.xlsx]Alpha'!$B$2",
    r'Alpha:Summary!$B$2',
    r'[1]Alpha!$B$2',
    r'Alpha!$XFE$1',
    r'Alpha!$A$1048577',
    'OtherName',
    '{1,2}',
  ]) {
    test('unmodeled definition cannot partially calculate: $definition', () {
      final book = _withDefinition(definition);
      final cell = book.sheets[1].cellA1('Z30')
        ..formula = 'SUM(Probe)+Z30'
        ..value = 97;
      final graph = FormulaDepGraph(book)..recalculate();
      expect(graph.circular, isEmpty);
      expect(cell.value, 97);
      expect(
        book.formulaNames.singleWhere((name) => name.name == 'Probe').formula,
        definition,
      );
    });
  }

  for (final error in [
    '#NULL!',
    '#DIV/0!',
    '#VALUE!',
    '#REF!',
    '#NAME?',
    '#NUM!',
    '#N/A',
  ]) {
    test('named native $error is a real error, not unsupported evaluation', () {
      final book = _withDefinition(error);
      final cell = book.sheets[1].cellA1('Z30')
        ..formula = 'Probe'
        ..value = 42;
      FormulaDepGraph(book).recalculate();
      expect(cell.value, error);
      expect(cell.type, SmlCellType.error);
      expect(_eval(book, "IFERROR('O''Brien Data'!Probe,12)"), 12);
    });
  }

  test('unsupported names retain even explicit NAME error caches', () {
    final book = _read();
    final cell = book.sheets[2].cellA1('D13')
      ..type = SmlCellType.error
      ..value = '#NAME?';
    FormulaDepGraph(book).recalculate();
    expect(cell.value, '#NAME?');
    expect(cell.type, SmlCellType.error);
  });

  test('dynamic OFFSET on a newly scoped name retains its authored cache', () {
    final book = _read();
    for (final formula in [
      "OFFSET('O''Brien Data'!Price,1,0)",
      'OFFSET(Price,1,0)',
    ]) {
      final cell = book.sheets[1].cellA1('Z30')
        ..formula = formula
        ..value = 97;
      FormulaDepGraph(book).recalculate();
      expect(cell.value, 97);
    }
  });

  test(
    'scoped caches and native definitions survive three saves and rename',
    () async {
      final source = File(_fixture).readAsBytesSync();
      final output = Directory('build/fidelity-sheet-qualified-names')
        ..createSync(recursive: true);
      File('${output.path}/source.xlsx').writeAsBytesSync(source);
      for (final phase in ['recalculated', 'renamed']) {
        File(
          'test/fixtures/fidelity/sheet-qualified-names-$phase-expected.xlsx',
        ).copySync('${output.path}/expected-$phase.xlsx');
      }
      var book = SheetDeserializer().readBytes(source);
      var expectedDefinitions = _definitions(OpcPackage.openBytes(source));
      const expected = <int, (String?, String)>{
        1: (null, '13'),
        2: (null, '7'),
        3: (null, '16'),
        4: (null, '17'),
        5: ('b', '1'),
        6: ('str', '#REF!'),
        7: ('e', '#REF!'),
        8: (null, '-2.5'),
        9: (null, '9'),
        10: (null, '7'),
        11: (null, '11'),
        12: ('e', '#DIV/0!'),
        13: (null, '42'),
        14: ('b', '1'),
        15: ('str', '#REF!'),
        16: ('e', '#N/A'),
        17: (null, '81'),
        18: (null, '73'),
      };
      for (final phase in ['recalculated', 'renamed']) {
        if (phase == 'renamed') {
          final edit = SheetRename.prepare(
            book,
            book.sheets[1],
            "Next's Sheet",
          );
          edit.apply();
          expect(_eval(book, "'Next''s Sheet'!Price"), 7);
          edit.undo();
          expect(_eval(book, "'O''Brien Data'!Price"), 7);
          edit.apply();
          expectedDefinitions = [
            for (final definition in expectedDefinitions)
              {
                ...definition,
                'definition': definition['definition']!.replaceAll(
                  "'O''Brien Data'!",
                  "'Next''s Sheet'!",
                ),
              },
          ];
        }
        for (var cycle = 1; cycle <= 3; cycle++) {
          final bytes = cycle == 2
              ? await OfficeIsolateSave.workbook(book)
              : SheetSerializer().writeBytes(book);
          File('${output.path}/$phase-$cycle.xlsx').writeAsBytesSync(bytes);
          final package = OpcPackage.openBytes(bytes);
          expect(_definitions(package), expectedDefinitions);
          for (final entry in expected.entries) {
            final cell = _xmlCell(package, 3, 'D${entry.key}');
            expect(
              cell.getAttribute('t'),
              entry.value.$1,
              reason: 'D${entry.key} type',
            );
            expect(
              entry.value.$1 == null
                  ? double.parse(cell.firstChild('v')!.text)
                  : cell.firstChild('v')!.text,
              entry.value.$1 == null
                  ? double.parse(entry.value.$2)
                  : entry.value.$2,
              reason: 'D${entry.key} cache',
            );
          }
          expect(
            double.parse(_xmlCell(package, 1, 'D1').firstChild('v')!.text),
            13,
          );
          expect(
            double.parse(_xmlCell(package, 2, 'D1').firstChild('v')!.text),
            7,
          );
          book = SheetDeserializer().read(package);
        }
      }
    },
  );

  test(
    'editing one range preserves opaque owners, scope and metadata on rebuild',
    () {
      final book = _read();
      final source = _definitions(book.package!);
      final foreign = book.namedRanges.singleWhere(
        (name) => name.name == 'Foreign',
      );
      foreign.range = SmlRange.parse('B2');
      final reopened = SheetDeserializer().readBytes(
        SheetSerializer().writeBytes(book),
      );
      expect(_eval(reopened, "'O''Brien Data'!Foreign"), 11);
      final written = _definitions(reopened.package!);
      for (final definition in source) {
        final actual = written.singleWhere(
          (entry) =>
              entry['name'] == definition['name'] &&
              entry['localSheetId'] == definition['localSheetId'],
        );
        expect(actual['localSheetId'], definition['localSheetId']);
        expect(actual['hidden'], definition['hidden']);
        expect(actual['comment'], definition['comment']);
        if (book.formulaNames.any(
          (name) =>
              name.name == definition['name'] &&
              '${name.localSheetId}' == definition['localSheetId'],
        )) {
          expect(actual, definition);
        }
      }
    },
  );
}
