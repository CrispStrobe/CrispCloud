import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _sheetNamespace =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _worksheetUri = '/xl/worksheets/sheet2.xml';

void main() {
  group('edits to imported conditional rules persist', () {
    for (final entry in <String, SmlConditionalKind>{
      '': SmlConditionalKind.top,
      'bottom="1"': SmlConditionalKind.bottom,
      'percent="1"': SmlConditionalKind.topPercent,
      'bottom="1" percent="1"': SmlConditionalKind.bottomPercent,
    }.entries) {
      test('rank-only edit survives repeated ${entry.value.name} saves', () {
        var book = _native(
          '<cfRule type="top10" rank="3" priority="7" '
          'stopIfTrue="true" ${entry.key}/>',
        );
        final rule = book.sheets[1].conditionalFormats.single;
        expect(rule.kind, entry.value);
        expect(rule.rank, 3);
        rule.rank = 1;

        for (var cycle = 0; cycle < 2; cycle++) {
          final bytes = SheetSerializer().writeBytes(book, recalculate: false);
          final package = OpcPackage.openBytes(bytes);
          expect(_nativeRule(package).getAttribute('rank'), '1');
          expect(_nativeRule(package).getAttribute('priority'), '7');
          expect(_nativeRule(package).getAttribute('stopIfTrue'), '1');
          book = SheetDeserializer().read(package);
          expect(book.sheets[1].conditionalFormats.single.kind, entry.value);
          expect(book.sheets[1].conditionalFormats.single.rank, 1);
          expect(book.sheets[1].conditionalFormats.single.priority, 7);
          expect(book.sheets[1].conditionalFormats.single.stopIfTrue, isTrue);
        }
      });
    }

    test('rank-only edit retains native DXF metadata through two saves', () {
      final sourcePackage = _native(
        '<cfRule type="top10" rank="3" priority="7" '
        'stopIfTrue="true" dxfId="1"/>',
      ).package!;
      final styles = XmlDocument.parse(SmlStyleSheet().toXml());
      styles.root!.addChild(
        XmlDocument.parse(
          '<dxfs xmlns="$_sheetNamespace" count="2">'
          '<dxf><fill><patternFill patternType="solid">'
          '<fgColor rgb="FF445566"/></patternFill></fill></dxf>'
          '<dxf><font><b/><color rgb="FF8A2BE2"/></font>'
          '<fill><patternFill patternType="solid">'
          '<fgColor rgb="FF12AB34"/></patternFill></fill>'
          '<border><bottom style="thin"><color rgb="FF112233"/>'
          '</bottom></border></dxf></dxfs>',
        ).root!,
      );
      final nativeStyles = styles.toXmlString();
      sourcePackage
          .createPart('/xl/styles.xml', OfficeContentTypes.sheetStyles)
          .writeText(nativeStyles);
      sourcePackage
          .relationshipsFor('/xl/workbook.xml')
          .add(type: RelationshipTypes.styles, target: 'styles.xml');

      var book = SheetDeserializer().read(sourcePackage);
      final original = book.sheets[1].conditionalFormats.single;
      expect(original.kind, SmlConditionalKind.top);
      expect(original.rank, 3);
      expect(original.priority, 7);
      expect(original.stopIfTrue, isTrue);
      expect(original.dxfId, 1);
      expect(original.fillRgb, '12AB34');
      expect(original.fontRgb, '8A2BE2');
      original.rank = 1;

      for (var cycle = 0; cycle < 2; cycle++) {
        final bytes = SheetSerializer().writeBytes(book, recalculate: false);
        final package = OpcPackage.openBytes(bytes);
        final nativeRule = _nativeRule(package);
        expect(nativeRule.getAttribute('rank'), '1');
        expect(nativeRule.getAttribute('priority'), '7');
        expect(nativeRule.getAttribute('stopIfTrue'), '1');
        expect(nativeRule.getAttribute('dxfId'), '1');
        // Keep native DXF properties outside the modeled colors, along with
        // both original entries and their indices, when regenerating a rule.
        expect(package.getPart('/xl/styles.xml')!.readText(), nativeStyles);
        book = SheetDeserializer().read(package);
        final reopened = book.sheets[1].conditionalFormats.single;
        expect(reopened.kind, SmlConditionalKind.top);
        expect(reopened.rank, 1);
        expect(reopened.priority, 7);
        expect(reopened.stopIfTrue, isTrue);
        expect(reopened.dxfId, 1);
        expect(reopened.fillRgb, '12AB34');
        expect(reopened.fontRgb, '8A2BE2');
      }
    });

    for (final operator in ['between', 'notBetween']) {
      test('upper-bound-only $operator edit survives isolate save', () async {
        final book = _native(
          '<cfRule type="cellIs" operator="$operator" priority="11" '
          'stopIfTrue="1">'
          '<formula>1</formula><formula>3</formula></cfRule>',
        );
        final rule = book.sheets[1].conditionalFormats.single;
        expect(rule.formula, '1');
        expect(rule.formula2, '3');
        rule.formula2 = '2';

        final bytes = await OfficeIsolateSave.workbook(
          book,
          recalculate: false,
        );
        final package = OpcPackage.openBytes(bytes);
        expect(_nativeRule(package).getAttribute('priority'), '11');
        expect(_nativeRule(package).getAttribute('stopIfTrue'), '1');
        expect(
          _nativeRule(
            package,
          ).childrenNamed('formula').map((node) => node.text),
          ['1', '2'],
        );
        final reopened = SheetDeserializer().read(package);
        expect(reopened.sheets[1].conditionalFormats.single.formula, '1');
        expect(reopened.sheets[1].conditionalFormats.single.formula2, '2');
      });
    }
  });

  group('conditional rule priorities and stopping semantics', () {
    test('every fresh rule receives a deterministic positive priority', () {
      final sheet = SmlWorksheet(name: 'Rules', sheetId: 2);
      sheet.conditionalFormats.addAll([
        for (final kind in SmlConditionalKind.values)
          SmlConditionalRule(
            range: SmlRange.parse('A1:A3'),
            kind: kind,
            formula: '1',
            formula2: '3',
          ),
      ]);
      final book = SmlWorkbook(
        sheets: [
          SmlWorksheet(name: 'Data', sheetId: 1),
          sheet,
        ],
      );
      final expected = List<int>.generate(
        sheet.conditionalFormats.length,
        (index) => index + 1,
      );
      for (var cycle = 0; cycle < 2; cycle++) {
        final package = SheetSerializer().write(book, recalculate: false);
        expect(_priorities(package), expected);
        expect(
          _nativeRules(package).map((rule) => rule.getAttribute('stopIfTrue')),
          everyElement('0'),
        );
        // Generated metadata must not make a prepared reference edit stale.
        expect(
          sheet.conditionalFormats.map((rule) => rule.priority),
          everyElement(isNull),
        );
      }
    });

    test(
      'authored precedence survives edits and an earlier unnumbered rule',
      () {
        final book = _native(
          '<cfRule type="top10" rank="3" priority="8" stopIfTrue="false"/>'
          '<cfRule type="cellIs" operator="between" priority="2" '
          'stopIfTrue="true"><formula>1</formula><formula>3</formula></cfRule>',
        );
        final rules = book.sheets[1].conditionalFormats;
        expect(rules.map((rule) => rule.priority), [8, 2]);
        rules[1].formula2 = '9';
        rules.insert(
          0,
          SmlConditionalRule(
            range: SmlRange.parse('A1:A3'),
            kind: SmlConditionalKind.equal,
            formula: '5',
          ),
        );
        final package = SheetSerializer().write(book, recalculate: false);
        expect(_priorities(package), [9, 8, 2]);
        expect(
          _nativeRules(package).map((rule) => rule.getAttribute('stopIfTrue')),
          ['0', '0', '1'],
        );
        final reopened = SheetDeserializer().read(package).sheets[1];
        expect(reopened.conditionalFormats.map((rule) => rule.priority), [
          9,
          8,
          2,
        ]);
        expect(reopened.conditionalFormats[2].formula2, '9');
        expect(reopened.conditionalFormats[2].stopIfTrue, isTrue);
      },
    );

    test(
      'invalid and duplicate priorities receive unique Int32 replacements',
      () {
        final book = _native(
          [
            for (final priority in <String?>[
              '0',
              '-2',
              '2147483648',
              '2147483647',
              '2',
              '2',
              null,
            ])
              '<cfRule type="expression" '
                  '${priority == null ? '' : 'priority="$priority"'}>'
                  '<formula>1</formula></cfRule>',
          ].join(),
        );
        book.sheets[1].conditionalFormats.first.formula = '2';
        final package = SheetSerializer().write(book, recalculate: false);
        final priorities = _priorities(package);
        expect(priorities, everyElement(inInclusiveRange(1, 0x7fffffff)));
        expect(priorities.toSet().length, priorities.length);
        expect(priorities[3], 0x7fffffff);
        expect(priorities[4], 2);
        expect(
          _priorities(SheetSerializer().write(book, recalculate: false)),
          priorities,
        );
      },
    );

    for (final property in ['priority', 'stopIfTrue']) {
      test('editing only $property replaces the native rule snapshot', () {
        final book = _native(
          '<cfRule type="top10" rank="3" priority="7" stopIfTrue="true"/>',
        );
        final rule = book.sheets[1].conditionalFormats.single;
        if (property == 'priority') {
          rule.priority = 3;
        } else {
          rule.stopIfTrue = false;
        }
        final package = SheetSerializer().write(book, recalculate: false);
        expect(
          _nativeRule(package).getAttribute('priority'),
          property == 'priority' ? '3' : '7',
        );
        expect(
          _nativeRule(package).getAttribute('stopIfTrue'),
          property == 'stopIfTrue' ? '0' : '1',
        );
      });
    }
  });

  group('SpreadsheetML boolean spellings', () {
    for (final entry in <String, SmlConditionalKind>{
      '': SmlConditionalKind.top,
      'bottom="0" percent="0"': SmlConditionalKind.top,
      'bottom="false" percent="false"': SmlConditionalKind.top,
      'bottom="1" percent="0"': SmlConditionalKind.bottom,
      'bottom="true" percent="false"': SmlConditionalKind.bottom,
      'bottom="0" percent="1"': SmlConditionalKind.topPercent,
      'bottom="false" percent="true"': SmlConditionalKind.topPercent,
      'bottom="1" percent="1"': SmlConditionalKind.bottomPercent,
      'bottom="true" percent="true"': SmlConditionalKind.bottomPercent,
    }.entries) {
      test('top10 ${entry.key.isEmpty ? 'defaults' : entry.key}', () {
        final book = _native(
          '<cfRule type="top10" rank="2" priority="1" ${entry.key}/>',
        );
        final rule = book.sheets[1].conditionalFormats.single;
        expect(rule.kind, entry.value);
        expect(rule.rank, 2);
      });
    }

    for (final entry in <String, SmlConditionalKind>{
      '': SmlConditionalKind.aboveAverage,
      'aboveAverage="1"': SmlConditionalKind.aboveAverage,
      'aboveAverage="true"': SmlConditionalKind.aboveAverage,
      'aboveAverage="0"': SmlConditionalKind.belowAverage,
      'aboveAverage="false"': SmlConditionalKind.belowAverage,
    }.entries) {
      test('aboveAverage ${entry.key.isEmpty ? 'default' : entry.key}', () {
        final book = _native(
          '<cfRule type="aboveAverage" priority="1" ${entry.key}/>',
        );
        expect(book.sheets[1].conditionalFormats.single.kind, entry.value);
      });
    }
  });

  group('conditional bounds follow reversible worksheet renames', () {
    for (final operator in ['between', 'notBetween']) {
      test('$operator keeps both modeled and native bounds through saves', () {
        final book = _native(
          '<cfRule type="cellIs" operator="$operator" priority="7" '
          'stopIfTrue="1"><formula>Data!A1</formula>'
          '<formula>Data!A2</formula></cfRule>',
        );
        final edit = SheetRename.prepare(book, book.firstSheet, "O'Brien");
        edit.apply();
        _expectRenamedBounds(book, "'O''Brien'!A1", "'O''Brien'!A2");
        edit.undo();
        _expectRenamedBounds(book, 'Data!A1', 'Data!A2');
        edit.apply();
        _expectRenamedBounds(book, "'O''Brien'!A1", "'O''Brien'!A2");
      });
    }

    test('a reference only in the upper bound follows the rename', () {
      final book = _native(
        '<cfRule type="cellIs" operator="between" priority="7" '
        'stopIfTrue="1"><formula>1</formula>'
        '<formula>Data!A2</formula></cfRule>',
      );
      SheetRename.rename(book, book.firstSheet, 'Next');
      _expectRenamedBounds(book, '1', "'Next'!A2");
    });

    for (final undo in [false, true]) {
      for (final property in ['rank', 'formula2', 'priority', 'stopIfTrue']) {
        test('${undo ? 'undo' : 'apply'} rejects a newer $property edit', () {
          final book = _native(
            property == 'rank'
                ? '<cfRule type="top10" rank="3" priority="1"/>'
                : '<cfRule type="cellIs" operator="between" priority="1">'
                      '<formula>Data!A1</formula><formula>Data!A2</formula>'
                      '</cfRule>',
          );
          final edit = SheetRename.prepare(book, book.firstSheet, 'Next');
          if (undo) edit.apply();
          final rule = book.sheets[1].conditionalFormats.single;
          switch (property) {
            case 'rank':
              rule.rank = 1;
            case 'formula2':
              rule.formula2 = '99';
            case 'priority':
              rule.priority = 9;
            case 'stopIfTrue':
              rule.stopIfTrue = true;
          }
          final before = _snapshot(book);

          expect(undo ? edit.undo : edit.apply, throwsStateError);
          expect(_snapshot(book), before);
        });
      }
    }
  });

  group('native expression predicates remain distinct', () {
    test('rename retains expression type and native rule metadata', () {
      final book = _native(
        '<cfRule type="expression" priority="7" stopIfTrue="1">'
        '<formula>Data!A1&gt;0</formula></cfRule>',
      );
      final sheet = book.sheets[1];
      final rule = sheet.conditionalFormats.single;
      expect(rule.kind, SmlConditionalKind.expression);
      final edit = SheetRename.rename(book, book.firstSheet, 'Next');
      expect(rule.formula, "'Next'!A1>0");
      expect(
        sheet.sourceConditionalFormatState,
        sheet.conditionalFormatState(),
      );

      final saved = OpcPackage.openBytes(
        SheetSerializer().writeBytes(book, recalculate: false),
      );
      expect(_nativeRule(saved).getAttribute('type'), 'expression');
      expect(_nativeRule(saved).getAttribute('priority'), '7');
      expect(_nativeRule(saved).getAttribute('stopIfTrue'), '1');
      expect(_nativeRule(saved).firstChild('formula')!.text, "'Next'!A1>0");
      edit.undo();
      expect(rule.formula, 'Data!A1>0');
      expect(
        _nativeRule(book.package!).firstChild('formula')!.text,
        'Data!A1>0',
      );
    });

    test('editing an expression saves its type without numeric fallback', () {
      final book = _native(
        '<cfRule type="expression" priority="5" stopIfTrue="true">'
        '<formula>1</formula></cfRule>',
      );
      final sheet = book.sheets[1];
      final rule = sheet.conditionalFormats.single;
      expect(rule.kind, SmlConditionalKind.expression);
      // A numeric true predicate is evaluated without substituting the old
      // greater-than rule or changing the preserved native expression.
      expect(rule.matches(sheet.cellA1('A1'), sheet), isTrue);
      rule.formula = 'A1>1';
      final saved = OpcPackage.openBytes(
        SheetSerializer().writeBytes(book, recalculate: false),
      );
      expect(_nativeRule(saved).getAttribute('type'), 'expression');
      expect(_nativeRule(saved).getAttribute('priority'), '5');
      expect(_nativeRule(saved).getAttribute('stopIfTrue'), '1');
      final reopened = SheetDeserializer().read(saved).sheets[1];
      expect(
        reopened.conditionalFormats.single.kind,
        SmlConditionalKind.expression,
      );
      expect(reopened.conditionalFormats.single.formula, 'A1>1');
    });

    test(
      'ODS formula-is uses the existing reference and string translator',
      () {
        const formula = r'''AND(A1>0,'Data'!$A$2<3,A1<>"A, B")''';
        final book = _native(
          '<cfRule type="expression" priority="1"><formula>'
          '${formula.replaceAll('<', '&lt;')}</formula></cfRule>',
        );
        final bytes = OdsSheetWriter.writeBytes(book);
        final archive = ZipDecoder().decodeBytes(bytes);
        final document = XmlDocument.parse(
          utf8.decode(archive.findFile('content.xml')!.content as List<int>),
        );
        final condition = document.root!
            .firstChild('body')!
            .firstChild('spreadsheet')!
            .childrenNamed('table')
            .last
            .firstChild('conditional-formats')!
            .firstChild('conditional-format')!
            .firstChild('condition')!;
        expect(
          condition.getAttribute('value'),
          r'''formula-is(AND([.A1]>0;[$'Data'.$A$2]<3;[.A1]<>"A, B"))''',
        );
        final reopened = OdsSheetReader.readBytes(bytes);
        final rule = reopened.sheets[1].conditionalFormats.single;
        expect(rule.kind, SmlConditionalKind.expression);
        expect(rule.formula, formula);
        final xlsx = SheetSerializer().write(reopened, recalculate: false);
        expect(_nativeRule(xlsx).getAttribute('type'), 'expression');
        expect(_nativeRule(xlsx).firstChild('formula')!.text, formula);
      },
    );
  });

  group('rename ownership excludes modeled page layout', () {
    test('undo preserves newer page settings through serialization', () {
      final book = _native(
        '<cfRule type="cellIs" operator="between" priority="7" '
        'stopIfTrue="1"><formula>Data!A1</formula>'
        '<formula>Data!A2</formula></cfRule>',
      );
      final edit = SheetRename.rename(book, book.firstSheet, 'Next');
      book.sheets[1].pageSetup = SmlPageSetup(
        marginTopIn: 1.25,
        scale: 85,
        printGridlines: true,
      );
      SheetSerializer().writeBytes(book, recalculate: false);
      edit.undo();
      _expectRenamedBounds(book, 'Data!A1', 'Data!A2');

      final root = XmlDocument.parse(
        book.package!.getPart(_worksheetUri)!.readText(),
      ).root!;
      expect(root.firstChild('pageMargins')!.getAttribute('top'), '1.25');
      expect(root.firstChild('pageSetup')!.getAttribute('scale'), '85');
      expect(root.firstChild('printOptions')!.getAttribute('gridLines'), '1');
      expect(book.sheets[1].pageSetup!.scale, 85);
    });

    test('first apply still rejects a newer native page edit', () {
      final book = _native(
        '<cfRule type="expression" priority="1">'
        '<formula>Data!A1&gt;0</formula></cfRule>',
      );
      final edit = SheetRename.prepare(book, book.firstSheet, 'Next');
      final part = book.package!.getPart(_worksheetUri)!;
      final document = XmlDocument.parse(part.readText());
      document.root!.addChild(
        XmlElement(localName: 'pageSetup', namespaceUri: _sheetNamespace)
          ..setAttribute('scale', '75'),
      );
      part.writeText(document.toXmlString());
      final before = _snapshot(book);
      expect(edit.apply, throwsStateError);
      expect(_snapshot(book), before);
    });

    test('undo still rejects newer native conditional metadata', () {
      final book = _native(
        '<cfRule type="expression" priority="7" stopIfTrue="1">'
        '<formula>Data!A1&gt;0</formula></cfRule>',
      );
      final edit = SheetRename.rename(book, book.firstSheet, 'Next');
      final part = book.package!.getPart(_worksheetUri)!;
      final document = XmlDocument.parse(part.readText());
      document.root!
          .firstChild('conditionalFormatting')!
          .firstChild('cfRule')!
          .setAttribute('stopIfTrue', '0');
      part.writeText(document.toXmlString());
      final before = _snapshot(book);
      expect(edit.undo, throwsStateError);
      expect(_snapshot(book), before);
    });
  });

  test('no-edit saves preserve native rule attributes and disjoint ranges', () {
    var book = _native(
      '<cfRule type="cellIs" operator="between" priority="7" '
      'stopIfTrue="1"><formula>Data!A1</formula>'
      '<formula>Data!A2</formula></cfRule>',
      sqref: 'A1:A3 C1:C3',
    );
    final original = _conditionalXml(book.package!);
    for (var cycle = 0; cycle < 2; cycle++) {
      final bytes = SheetSerializer().writeBytes(book, recalculate: false);
      final package = OpcPackage.openBytes(bytes);
      expect(_conditionalXml(package), original);
      book = SheetDeserializer().read(package);
    }
  });
}

SmlWorkbook _native(String ruleXml, {String sqref = 'A1:A3'}) {
  final book = SmlWorkbook(
    sheets: [
      SmlWorksheet(name: 'Data', sheetId: 1)
        ..cellA1('A1').value = 1
        ..cellA1('A2').value = 3,
      SmlWorksheet(name: 'Rules', sheetId: 2)..cellA1('A1').value = 2,
    ],
  );
  final package = SheetSerializer().write(book, recalculate: false);
  final part = package.getPart(_worksheetUri)!;
  final document = XmlDocument.parse(part.readText());
  document.root!.addChild(
    XmlDocument.parse(
      '<conditionalFormatting xmlns="$_sheetNamespace" sqref="$sqref">'
      '$ruleXml</conditionalFormatting>',
    ).root!,
  );
  part.writeText(document.toXmlString());
  return SheetDeserializer().read(package);
}

XmlElement _nativeRule(OpcPackage package) => XmlDocument.parse(
  package.getPart(_worksheetUri)!.readText(),
).root!.firstChild('conditionalFormatting')!.firstChild('cfRule')!;

List<XmlElement> _nativeRules(OpcPackage package) =>
    XmlDocument.parse(package.getPart(_worksheetUri)!.readText()).root!
        .childrenNamed('conditionalFormatting')
        .expand((group) => group.childrenNamed('cfRule'))
        .toList();

List<int> _priorities(OpcPackage package) => [
  for (final rule in _nativeRules(package))
    int.parse(rule.getAttribute('priority')!),
];

String _conditionalXml(OpcPackage package) => XmlDocument(
  root: XmlDocument.parse(
    package.getPart(_worksheetUri)!.readText(),
  ).root!.firstChild('conditionalFormatting')!,
).toXmlString(declaration: false);

void _expectRenamedBounds(SmlWorkbook book, String lower, String upper) {
  final sheet = book.sheets[1];
  final rule = sheet.conditionalFormats.single;
  expect(rule.formula, lower);
  expect(rule.formula2, upper);
  expect(sheet.sourceConditionalFormatState, sheet.conditionalFormatState());

  final bytes = SheetSerializer().writeBytes(book, recalculate: false);
  final package = OpcPackage.openBytes(bytes);
  final nativeRule = _nativeRule(package);
  expect(nativeRule.getAttribute('priority'), '7');
  expect(nativeRule.getAttribute('stopIfTrue'), '1');
  expect(nativeRule.childrenNamed('formula').map((node) => node.text), [
    lower,
    upper,
  ]);
  final reopened = SheetDeserializer().read(package);
  expect(reopened.sheets[1].conditionalFormats.single.formula, lower);
  expect(reopened.sheets[1].conditionalFormats.single.formula2, upper);
}

Map<String, Object?> _snapshot(SmlWorkbook book) {
  final rule = book.sheets[1].conditionalFormats.single;
  return {
    'name': book.firstSheet.name,
    'formula': rule.formula,
    'formula2': rule.formula2,
    'rank': rule.rank,
    'priority': rule.priority,
    'stopIfTrue': rule.stopIfTrue,
    'source': book.sheets[1].sourceConditionalFormatState,
    'parts': {
      for (final part in book.package!.parts) part.uri: part.readBytes(),
    },
  };
}
