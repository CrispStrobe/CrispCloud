import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _sheetNamespace =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _chartNamespace =
    'http://schemas.openxmlformats.org/drawingml/2006/chart';
const _worksheetUri = '/xl/worksheets/sheet2.xml';
const _chartUri = '/xl/charts/chart1.xml';

void main() {
  group('prepared rename preserves newer state atomically', () {
    for (final undo in [false, true]) {
      for (final newerEdit in [
        'formula',
        'native extension',
        'name collision',
      ]) {
        test('${undo ? 'undo' : 'apply'} rejects newer $newerEdit', () {
          final book = _native();
          final edit = SheetRename.prepare(book, book.firstSheet, 'Next');
          if (undo) edit.apply();

          switch (newerEdit) {
            case 'formula':
              book.sheets[1].cellA1('D1').formula = undo ? '88' : '77';
            case 'native extension':
              final part = book.package!.getPart(_worksheetUri)!;
              final original = part.readText();
              const extension =
                  '<extLst><ext uri="urn:later-edit">'
                  '<later xmlns="urn:later-edit">Keep this newer payload</later>'
                  '</ext></extLst>';
              expect(original, contains('</worksheet>'));
              part.writeText(
                original.replaceFirst('</worksheet>', '$extension</worksheet>'),
              );
            case 'name collision':
              book.sheets[1].name = undo ? 'Data' : 'Next';
          }

          // Snapshot every field the rename can update, plus exact native
          // bytes. Serializing here would itself modify the state under test.
          final before = _snapshot(book);
          expect(undo ? edit.undo : edit.apply, throwsStateError);
          expect(_snapshot(book), before);
        });
      }
    }
  });

  group('qualified range endpoints remain separate from 3-D sheet names', () {
    final cases = <String, String>{
      'SUM(Data!A:Data!B)': "SUM('Next'!A:'Next'!B)",
      'SUM(Data!1:Data!3)': "SUM('Next'!1:'Next'!3)",
      r'SUM(Data!$A:Data!$B)': r"SUM('Next'!$A:'Next'!$B)",
      r'SUM(Data!$1:Data!$3)': r"SUM('Next'!$1:'Next'!$3)",
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(
          SheetRename.rewriteFormula(entry.key, 'Data', 'Next'),
          entry.value,
        );
        final package = _nativePackage();
        final part = package.getPart(_worksheetUri)!;
        final document = XmlDocument.parse(part.readText());
        final formula = _cellFormula(document.root!, 'D14');
        formula.children.clear();
        formula.addText(entry.key);
        part.writeText(document.toXmlString());

        final book = SheetDeserializer().read(package);
        expect(book.sheets[1].cellA1('D14').formula, entry.key);
        SheetRename.rename(book, book.firstSheet, 'Next');
        expect(book.sheets[1].cellA1('D14').formula, entry.value);
        final saved = OpcPackage.openBytes(
          SheetSerializer().writeBytes(book, recalculate: false),
        );
        final native = XmlDocument.parse(
          saved.getPart(_worksheetUri)!.readText(),
        ).root!;
        expect(_cellFormula(native, 'D14').text, entry.value);
        expect(
          SheetDeserializer().read(saved).sheets[1].cellA1('D14').formula,
          entry.value,
        );
      });
    }
  });

  group('unrecognized affected native owners reject atomically', () {
    final cases = <String, String>{
      'vendor attribute without a formula-like name':
          '<v:root xmlns:v="urn:vendor" target="Data!A1"/>',
      'unrecognized leaf in the SpreadsheetML namespace':
          '<v:root xmlns:v="urn:vendor" xmlns:x="$_sheetNamespace">'
          '<x:unknownFormula>Data!A1</x:unknownFormula></v:root>',
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        final book = _native();
        book.package!.createPart(
          '/customXml/reference.xml',
          'application/xml',
          utf8.encode(entry.value),
        );
        final before = _snapshot(book);
        expect(
          () => SheetRename.rename(book, book.firstSheet, 'Next'),
          throwsUnsupportedError,
        );
        expect(_snapshot(book), before);
      });
    }
  });

  test(
    'external sparse chart cache stays opaque through three saves',
    () async {
      final package = _nativePackage();
      final part = package.getPart(_chartUri)!;
      final document = XmlDocument.parse(
        part.readText().replaceAll("'Data'!", "'[Remote.xlsx]Data'!"),
      );
      final series = _elements(document.root!, _chartNamespace, 'ser').single;
      final reference = series
          .firstChild('val', namespaceUri: _chartNamespace)!
          .firstChild('numRef', namespaceUri: _chartNamespace)!;
      reference.addChild(
        XmlDocument.parse(
          '<numCache xmlns="$_chartNamespace">'
          '<formatCode>0.00</formatCode><ptCount val="3"/>'
          '<pt idx="0"><v>30</v></pt><pt idx="2"><v>50</v></pt>'
          '</numCache>',
        ).root!,
      );
      part.writeText(document.toXmlString());
      final originalChart = part.readBytes();
      final originalExternal = package
          .getPart('/xl/externalLinks/externalLink1.xml')!
          .readBytes();

      var book = SheetDeserializer().read(package);
      expect(
        book.firstSheet.drawings.single.sourceSheetName,
        '[Remote.xlsx]Data',
      );
      SheetRename.rename(book, book.firstSheet, 'Next');
      expect(book.firstSheet.name, 'Next');
      expect(book.sheets[1].cellA1('D1').formula, r"'Next'!$B$2");

      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = cycle == 1
            ? await OfficeIsolateSave.workbook(book)
            : SheetSerializer().writeBytes(book);
        final saved = OpcPackage.openBytes(bytes);
        final chart = XmlDocument.parse(
          saved.getPart(_chartUri)!.readText(),
        ).root!;
        final cache = _elements(chart, _chartNamespace, 'numCache').single;
        expect(cache.firstChild('formatCode')!.text, '0.00');
        expect(cache.firstChild('ptCount')!.getAttribute('val'), '3');
        expect(
          cache
              .childrenNamed('pt')
              .map(
                (point) => [
                  point.getAttribute('idx'),
                  point.firstChild('v')!.text,
                ],
              ),
          [
            ['0', '30'],
            ['2', '50'],
          ],
        );
        expect(
          _elements(chart, _chartNamespace, 'f').map((node) => node.text),
          [
            "'[Remote.xlsx]Data'!B1",
            r"'[Remote.xlsx]Data'!$A$2:$A$3",
            r"'[Remote.xlsx]Data'!$B$2:$B$3",
          ],
        );
        expect(saved.getPart(_chartUri)!.readBytes(), originalChart);
        expect(
          saved.getPart('/xl/externalLinks/externalLink1.xml')!.readBytes(),
          originalExternal,
        );
        book = SheetDeserializer().read(saved);
        expect(book.firstSheet.name, 'Next');
        expect(book.sheets[1].cellA1('D1').formula, r"'Next'!$B$2");
      }
    },
  );

  test(
    'duplicate-source native chart series survive rename and three saves',
    () async {
      final package = _nativePackage();
      final part = package.getPart(_chartUri)!;
      final document = XmlDocument.parse(part.readText());
      final first = _elements(document.root!, _chartNamespace, 'ser').single;
      final second = first.copy();
      second.firstChild('idx')!.setAttribute('val', '1');
      second.firstChild('order')!.setAttribute('val', '1');
      final parent = first.parent!;
      second.parent = parent;
      parent.children.insert(parent.children.indexOf(first) + 1, second);
      part.writeText(document.toXmlString());

      var book = SheetDeserializer().read(package);
      SheetRename.rename(book, book.firstSheet, 'Next');
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = cycle == 1
            ? await OfficeIsolateSave.workbook(book)
            : SheetSerializer().writeBytes(book);
        final saved = OpcPackage.openBytes(bytes);
        final chart = XmlDocument.parse(
          saved.getPart(_chartUri)!.readText(),
        ).root!;
        final series = _elements(chart, _chartNamespace, 'ser').toList();
        expect(series, hasLength(2));
        expect(
          series.map((node) => node.firstChild('idx')!.getAttribute('val')),
          ['0', '1'],
        );
        expect(
          series.map((node) => node.firstChild('order')!.getAttribute('val')),
          ['0', '1'],
        );
        for (final entry in series) {
          expect(
            _elements(entry, _chartNamespace, 'f').map((node) => node.text),
            ["'Next'!B1", r"'Next'!$A$2:$A$3", r"'Next'!$B$2:$B$3"],
          );
        }
        book = SheetDeserializer().read(saved);
        expect(book.firstSheet.name, 'Next');
      }
    },
  );
}

OpcPackage _nativePackage() => OpcPackage.openBytes(
  File('test/fixtures/fidelity/sheet-rename-native.xlsx').readAsBytesSync(),
);

SmlWorkbook _native() => SheetDeserializer().read(_nativePackage());

Iterable<XmlElement> _elements(
  XmlElement root,
  String namespace,
  String localName,
) sync* {
  if (root.namespaceUri == namespace && root.localName == localName) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, namespace, localName);
  }
}

XmlElement _cellFormula(XmlElement root, String address) =>
    _elements(root, _sheetNamespace, 'c')
        .singleWhere((cell) => cell.getAttribute('r') == address)
        .firstChild('f', namespaceUri: _sheetNamespace)!;

Map<String, Object?> _snapshot(SmlWorkbook book) => {
  'definedNames': book.definedNameState(),
  'sourceDefinedNames': book.sourceDefinedNameState,
  'sheets': [
    for (final sheet in book.sheets)
      {
        'identity': identityHashCode(sheet),
        'name': sheet.name,
        'id': sheet.sheetId,
        'sourceUri': sheet.sourcePartUri,
        'cells': [
          for (final cell in sheet.allCells)
            [
              identityHashCode(cell),
              cell.ref.a1,
              cell.formula,
              cell.value,
              cell.type.name,
            ],
        ],
        'validations': sheet.validationState(),
        'sourceValidations': sheet.sourceValidationState,
        'conditionals': sheet.conditionalFormatState(),
        'sourceConditionals': sheet.sourceConditionalFormatState,
        'pivots': [
          for (final pivot in sheet.pivots)
            [identityHashCode(pivot), pivot.sourceSheetName],
        ],
        'drawings': [
          for (final drawing in sheet.drawings)
            [
              identityHashCode(drawing),
              drawing.sourceSheetName,
              drawing.sourceChartPartUri,
              drawing.sourceChartState,
            ],
        ],
      },
  ],
  'contentTypes': book.package!.contentTypes.toXml(),
  'packageRelationships': book.package!.packageRelationships.toXml(),
  'nativeParts': {
    for (final part in book.package!.parts)
      part.uri: book.package!.getPart(part.uri)!.readBytes(),
  },
};
