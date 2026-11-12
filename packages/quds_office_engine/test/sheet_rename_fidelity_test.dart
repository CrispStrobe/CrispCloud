import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/fidelity/sheet_steps.dart';

void main() {
  group('sheet qualifier lexer', () {
    final cases = <String, String>{
      'Data!A1+DATA!\$B\$2': "'O''Brien 2026'!A1+'O''Brien 2026'!\$B\$2",
      "'Data'!A1": "'O''Brien 2026'!A1",
      'Data!LongRange:Data!OtherRange':
          "'O''Brien 2026'!LongRange:'O''Brien 2026'!OtherRange",
      'Data!A1:Data!B2': "'O''Brien 2026'!A1:'O''Brien 2026'!B2",
      "Summary!A1:'Data'!B2": "Summary!A1:'O''Brien 2026'!B2",
      'SUM(Data:Last!A1)': "SUM('O''Brien 2026:Last'!A1)",
      "SUM('First:Data'!A1)": "SUM('First:O''Brien 2026'!A1)",
      "SUM('Data':'Last Sheet'!A1)": "SUM('O''Brien 2026:Last Sheet'!A1)",
      'Data!LocalName+Data!A:A+Data!1:3':
          "'O''Brien 2026'!LocalName+'O''Brien 2026'!A:A+'O''Brien 2026'!1:3",
      '[1]Data!A1+[1]First:Data!B2': '[1]Data!A1+[1]First:Data!B2',
      "'[Book.xlsx]Data'!A1+'C:\\work\\[Book.xlsx]Data'!B2":
          "'[Book.xlsx]Data'!A1+'C:\\work\\[Book.xlsx]Data'!B2",
      'IF(Data!A1,"Data!A1 ""x""","\'Data\'!A1")':
          "IF('O''Brien 2026'!A1,\"Data!A1 \"\"x\"\"\",\"'Data'!A1\")",
      'Table[Data!A1]+Table[[#All],[Data!A1]]':
          'Table[Data!A1]+Table[[#All],[Data!A1]]',
      "Table[Column']Data!A1]": "Table[Column']Data!A1]",
      'OtherData!A1+Data2!A1+INDIRECT("Data!A1")':
          'OtherData!A1+Data2!A1+INDIRECT("Data!A1")',
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(
          SheetRename.rewriteFormula(entry.key, 'Data', "O'Brien 2026"),
          entry.value,
        );
      });
    }
    test('old apostrophes and case-only names', () {
      expect(
        SheetRename.rewriteFormula(
          "'O''Brien 2026'!A1",
          "O'Brien 2026",
          'Next',
        ),
        "'Next'!A1",
      );
      expect(
        SheetRename.rewriteFormula('Data!A1', 'Data', 'DATA'),
        "'DATA'!A1",
      );
    });
  });

  test('independent native formula owners survive three saves', () async {
    final source = File(
      'test/fixtures/fidelity/sheet-rename-native.xlsx',
    ).readAsBytesSync();
    var book = SheetDeserializer().readBytes(source);
    final output = Directory('build/fidelity-sheet-rename')
      ..createSync(recursive: true);
    File('${output.path}/source.xlsx').writeAsBytesSync(source);
    final originalExternal = book.package!
        .getPart('/xl/externalLinks/externalLink1.xml')!
        .readBytes();
    final edit = SheetRename.prepare(book, book.firstSheet, "O'Brien 2026");
    expect(book.firstSheet.name, 'Data');
    expect(book.sheets[1].cellA1('D1').formula, r'Data!$B$2');
    edit.apply();
    expect(book.sheets[1].cellA1('D1').formula, r"'O''Brien 2026'!$B$2");
    expect(book.namedRanges.first.sheetName, "O'Brien 2026");
    for (var cycle = 1; cycle <= 3; cycle++) {
      final bytes = cycle == 2
          ? await OfficeIsolateSave.workbook(book)
          : SheetSerializer().writeBytes(book);
      File('${output.path}/renamed-$cycle.xlsx').writeAsBytesSync(bytes);
      final package = OpcPackage.openBytes(bytes);
      expect(
        package.getPart('/xl/externalLinks/externalLink1.xml')!.readBytes(),
        originalExternal,
      );
      book = SheetDeserializer().read(package);
      expect(book.firstSheet.name, "O'Brien 2026");
      expect(
        book.sheets[1].validations.first.formula2,
        r"'O''Brien 2026'!$B$3",
      );
    }
  });

  for (final extra in <String, String>{
    'unknown XML formula owner':
        '<v:root xmlns:v="urn:vendor"><v:formula>Data!A1</v:formula></v:root>',
    'unknown XML sheet attribute':
        '<v:root xmlns:v="urn:vendor" sheet="Data"/>',
    'unknown extension formula namespace':
        '<v:root xmlns:v="urn:vendor"><v:f>Data!A1</v:f></v:root>',
  }.entries) {
    test('${extra.key} rejects without any model or native mutation', () {
      final book = _native();
      book.package!.createPart(
        '/customXml/reference.xml',
        'application/xml',
        utf8.encode(extra.value),
      );
      final before = _parts(book);
      final formula = book.sheets[1].cellA1('D1').formula;
      expect(
        () => SheetRename.rename(book, book.firstSheet, 'Next'),
        throwsUnsupportedError,
      );
      expect(book.firstSheet.name, 'Data');
      expect(book.sheets[1].cellA1('D1').formula, formula);
      expect(_parts(book), before);
    });
  }

  test('opaque executable owner rejects before mutation', () {
    final book = _native();
    book.package!.createPart(
      '/xl/vbaProject.bin',
      'application/vnd.ms-office.vbaProject',
      [0, 1, 2],
    );
    final before = _parts(book);
    expect(
      () => SheetRename.rename(book, book.firstSheet, 'Next'),
      throwsUnsupportedError,
    );
    expect(_parts(book), before);
    expect(book.firstSheet.name, 'Data');
  });

  test(
    'renaming after source cell changes keeps native chart references and fresh values',
    () {
      final book = _native();
      book.firstSheet.cellA1('B2').value = 7;
      SheetRename.rename(book, book.firstSheet, 'Next');
      final package = SheetSerializer().write(book);
      final chart = XmlDocument.parse(
        package.getPart('/xl/charts/chart1.xml')!.readText(),
      ).root!;
      Iterable<XmlElement> find(XmlElement node, String localName) sync* {
        if (node.localName == localName) yield node;
        for (final child in node.childElements) {
          yield* find(child, localName);
        }
      }

      expect(find(chart, 'f').map((node) => node.text), [
        "'Next'!B1",
        r"'Next'!$A$2:$A$3",
        r"'Next'!$B$2:$B$3",
      ]);
      expect(
        find(chart, 'numCache')
            .expand((node) => find(node, 'v'))
            .map((node) => double.parse(node.text)),
        [7, 5],
      );
    },
  );

  test('array formula topology is guarded before model changes', () {
    final package = _native().package!;
    final part = package.getPart('/xl/worksheets/sheet2.xml')!;
    part.writeText(
      part.readText().replaceFirst(
        r'<f>Data!$B$2</f>',
        r'<f t="array" ref="D1:D2">Data!$B$2</f>',
      ),
    );
    final book = SheetDeserializer().read(package);
    final before = _parts(book);
    expect(
      () => SheetRename.rename(book, book.firstSheet, 'Next'),
      throwsUnsupportedError,
    );
    expect(book.firstSheet.name, 'Data');
    expect(_parts(book), before);
  });

  test(
    'unrelated opaque text and a valid exclamation mark in a sheet name',
    () {
      final book = _native();
      book.package!.createPart(
        '/customXml/text.xml',
        'application/xml',
        utf8.encode("<root>I don't reference any worksheet.</root>"),
      );
      SheetRename.rename(book, book.firstSheet, 'Sheet!Name');
      final reopened = SheetDeserializer().readBytes(
        SheetSerializer().writeBytes(book),
      );
      expect(reopened.firstSheet.name, 'Sheet!Name');
      expect(reopened.sheets[1].cellA1('D1').formula, r"'Sheet!Name'!$B$2");
    },
  );

  for (final kind in ['name', 'validation', 'conditional', 'chart']) {
    test('modified native $kind projection is guarded atomically', () {
      final book = _native();
      switch (kind) {
        case 'name':
          book.namedRanges.first.name = 'Changed';
        case 'validation':
          book.sheets[1].validations.first.formula1 = '12';
        case 'conditional':
          book.sheets[1].conditionalFormats.first.formula = '12';
        case 'chart':
          book.firstSheet.drawings.first.visual.title = 'Changed';
      }
      final before = _parts(book);
      expect(
        () => SheetRename.rename(book, book.firstSheet, 'Next'),
        throwsUnsupportedError,
      );
      expect(book.firstSheet.name, 'Data');
      expect(_parts(book), before);
    });
  }

  test('invalid names and malformed qualifiers cannot partially rename', () {
    final book = _native();
    final before = _parts(book);
    for (final name in [
      '',
      ' ',
      'Summary',
      'summary',
      'a/b',
      "'Name",
      "Name'",
      'a' * 32,
      'nul\u0000',
    ]) {
      expect(
        () => SheetRename.rename(book, book.firstSheet, name),
        throwsArgumentError,
      );
    }
    book.sheets[1].cellA1('D14').formula = "'Data!B2";
    expect(
      () => SheetRename.rename(book, book.firstSheet, 'Next'),
      throwsFormatException,
    );
    expect(book.firstSheet.name, 'Data');
    expect(book.sheets[1].cellA1('D1').formula, r'Data!$B$2');
    expect(_parts(book), before);
  });

  test(
    'no-op is clean and undo/redo preserves saved values and native references',
    () {
      final book = _native();
      final before = _nativeReferences(book);
      expect(
        SheetRename.prepare(book, book.firstSheet, 'Data').isEmpty,
        isTrue,
      );
      final edit = SheetRename.rename(book, book.firstSheet, 'Next');
      SheetSerializer().writeBytes(book);
      edit.undo();
      expect(book.firstSheet.name, 'Data');
      expect(book.sheets[1].cellA1('D1').formula, r'Data!$B$2');
      expect(_nativeReferences(book), before);
      // The save calculated this value from B2. Undoing a rename must keep the
      // current cached values instead of restoring the source package's 42.
      final savedSheet = XmlDocument.parse(
        book.package!.getPart('/xl/worksheets/sheet2.xml')!.readText(),
      ).root!;
      final cell = savedSheet
          .firstChild('sheetData')!
          .childrenNamed('row')
          .expand((row) => row.childrenNamed('c'))
          .singleWhere((cell) => cell.getAttribute('r') == 'D1');
      expect(double.parse(cell.firstChild('v')!.text), 2);
      final savedChart = XmlDocument.parse(
        book.package!.getPart('/xl/charts/chart1.xml')!.readText(),
      ).root!;
      expect(_elements(savedChart, 'numCache'), isNotEmpty);
      edit.apply();
      expect(
        SheetDeserializer()
            .readBytes(SheetSerializer().writeBytes(book))
            .firstSheet
            .name,
        'Next',
      );
    },
  );

  test(
    'script renames native references before three direct/isolate saves',
    () async {
      // This workbook was authored independently with openpyxl/native OOXML,
      // rather than by the engine serializer whose output is under test.
      var book = SheetDeserializer().readBytes(
        File('test/fixtures/fidelity/native.xlsx').readAsBytesSync(),
      );
      applySheetStep(book, {
        'op': 'renameSheet',
        'sheet': 0,
        'name': "O'Brien 2026",
      });
      expect(book.firstSheet.name, "O'Brien 2026");
      expect(book.sheets.last.pivots.single.sourceSheetName, "O'Brien 2026");
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = cycle.isEven
            ? SheetSerializer().writeBytes(book)
            : await OfficeIsolateSave.workbook(book);
        final package = OpcPackage.openBytes(bytes);
        final cache = XmlDocument.parse(
          package
              .getPart('/xl/pivotCache/pivotCacheDefinition1.xml')!
              .readText(),
        );
        expect(
          cache.root!
              .firstChild('cacheSource')!
              .firstChild('worksheetSource')!
              .getAttribute('sheet'),
          "O'Brien 2026",
        );
        final chart = package.getPart('/xl/charts/chart1.xml')!.readText();
        expect(chart, contains("'O''Brien 2026'!"));
        expect(chart, isNot(contains("'Data'!")));
        book = SheetDeserializer().readBytes(bytes);
        expect(book.firstSheet.name, "O'Brien 2026");
      }
    },
  );
}

SmlWorkbook _native() => SheetDeserializer().readBytes(
  File('test/fixtures/fidelity/sheet-rename-native.xlsx').readAsBytesSync(),
);

Map<String, List<int>> _parts(SmlWorkbook book) => {
  for (final part in book.package!.parts)
    part.uri: book.package!.getPart(part.uri)!.readBytes(),
};

Iterable<XmlElement> _elements(XmlElement node, String localName) sync* {
  if (node.localName == localName) yield node;
  for (final child in node.childElements) {
    yield* _elements(child, localName);
  }
}

Map<String, List<String>> _nativeReferences(SmlWorkbook book) => {
  for (final part in book.package!.parts)
    if (<String>{
      '/xl/workbook.xml',
      '/xl/worksheets/sheet1.xml',
      '/xl/worksheets/sheet2.xml',
      '/xl/charts/chart1.xml',
    }.contains(part.uri))
      part.uri: [
        for (final name in [
          'f',
          'definedName',
          'formula',
          'formula1',
          'formula2',
        ])
          for (final node in _elements(
            XmlDocument.parse(
              book.package!.getPart(part.uri)!.readText(),
            ).root!,
            name,
          ))
            node.text,
      ],
};
