import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _stylesUri = '/xl/styles.xml';

void main() {
  test('native conditional color edits retain unmodeled DXF properties', () {
    var book = _native();
    final original = _dxfs(book.package!).map(_xml).toList();
    final rule = book.firstSheet.conditionalFormats.single
      ..fillRgb = '12AB34'
      ..fontRgb = '8A2BE2';
    for (var cycle = 0; cycle < 2; cycle++) {
      final saved = _save(book);
      expect(_dxfs(saved).take(2).map(_xml), original);
      expect(_dxfs(saved), hasLength(3));
      book = SheetDeserializer().read(saved);
      final restored = book.firstSheet.conditionalFormats.single;
      expect(restored.fillRgb, '12AB34');
      expect(restored.fontRgb, '8A2BE2');
      expect(restored.dxfId, rule.dxfId);
      _expectNativeExtras(_dxfs(saved)[restored.dxfId!]);
    }
  });

  test('repeated in-memory saves reuse conditional style ids', () {
    final book = _native();
    final rule = book.firstSheet.conditionalFormats.single..fillRgb = '12AB34';
    final first = _save(book);
    final firstXml = first.getPart(_stylesUri)!.readText();
    final firstId = rule.dxfId;
    for (var cycle = 0; cycle < 3; cycle++) {
      final saved = _save(book);
      expect(saved.getPart(_stylesUri)!.readText(), firstXml);
      expect(rule.dxfId, firstId);
      expect(_dxfs(saved), hasLength(3));
    }
    rule.fillRgb = 'AA0000';
    final reverted = _save(book);
    expect(rule.dxfId, 0);
    expect(_dxfs(reverted), hasLength(3));
    expect(
      SheetDeserializer()
          .read(reverted)
          .firstSheet
          .conditionalFormats
          .single
          .fillRgb,
      'AA0000',
    );
  });

  test(
    'new rules in a native workbook receive reusable differential styles',
    () {
      var book = _native();
      book.firstSheet.conditionalFormats.addAll([
        _rule('B1', fill: '123456', font: 'ABCDEF'),
        _rule('C1', fill: '123456', font: 'ABCDEF'),
        _rule('D1'),
      ]);
      for (var cycle = 0; cycle < 2; cycle++) {
        final saved = _save(book);
        expect(_dxfs(saved), hasLength(3));
        book = SheetDeserializer().read(saved);
        final rules = book.firstSheet.conditionalFormats;
        expect(rules[1].fillRgb, '123456');
        expect(rules[1].fontRgb, 'ABCDEF');
        expect(rules[2].dxfId, rules[1].dxfId);
        expect(rules[3].fillRgb, isEmpty);
        expect(rules[3].fontRgb, isEmpty);
        expect(rules[3].dxfId, isNull);
        _expectValidIds(book, saved);
      }
    },
  );

  test('new styled rules work when a native workbook has no dxfs', () {
    final initial = SmlWorkbook()..firstSheet.cellA1('A1').value = 7;
    var book = SheetDeserializer().read(_save(initial));
    book.firstSheet.conditionalFormats.add(_rule('A1', fill: '12AB34'));
    for (var cycle = 0; cycle < 2; cycle++) {
      final saved = _save(book);
      book = SheetDeserializer().read(saved);
      expect(book.firstSheet.conditionalFormats.single.fillRgb, '12AB34');
      expect(_dxfs(saved), hasLength(1));
      _expectValidIds(book, saved);
    }
  });

  for (final clear in ['fill', 'font', 'both']) {
    test('clearing native conditional $clear removes only that override', () {
      var book = _native();
      final original = _dxfs(book.package!).map(_xml).toList();
      final rule = book.firstSheet.conditionalFormats.single;
      if (clear != 'font') rule.fillRgb = '';
      if (clear != 'fill') rule.fontRgb = '';
      for (var cycle = 0; cycle < 2; cycle++) {
        final saved = _save(book);
        expect(_dxfs(saved).take(2).map(_xml), original);
        expect(_dxfs(saved), hasLength(3));
        book = SheetDeserializer().read(saved);
        final restored = book.firstSheet.conditionalFormats.single;
        expect(restored.fillRgb, clear == 'font' ? 'AA0000' : '');
        expect(restored.fontRgb, clear == 'fill' ? '003366' : '');
        final dxf = _dxfs(saved)[restored.dxfId!];
        _expectNativeExtras(dxf);
        if (clear != 'font') {
          expect(dxf.firstChild('fill', namespaceUri: _ns), isNull);
        }
        if (clear != 'fill') {
          expect(
            dxf
                .firstChild('font', namespaceUri: _ns)!
                .firstChild('color', namespaceUri: _ns),
            isNull,
          );
        }
      }
    });
  }

  for (final edit in ['rank', 'priority', 'formula', 'stop']) {
    test('$edit-only native edits keep exact stylesheet bytes', () {
      var book = _native();
      // Preserve formatting as well as the native XML tree when no style is
      // edited; byte fidelity must not depend on canonical input whitespace.
      final part = book.package!.getPart(_stylesUri)!;
      final original = part.readText().replaceFirst(
        '<styleSheet',
        '\n<styleSheet',
      );
      part.writeText(original);
      book = SheetDeserializer().read(book.package!);
      final rule = book.firstSheet.conditionalFormats.single;
      switch (edit) {
        case 'rank':
          rule.rank = 2;
        case 'priority':
          rule.priority = 7;
        case 'formula':
          rule.formula = 'A1>2';
        case 'stop':
          rule.stopIfTrue = true;
      }
      for (var cycle = 0; cycle < 2; cycle++) {
        final saved = _save(book);
        expect(saved.getPart(_stylesUri)!.readText(), original);
        expect(_dxfs(saved), hasLength(2));
        book = SheetDeserializer().read(saved);
        expect(book.firstSheet.conditionalFormats.single.dxfId, 0);
      }
    });
  }

  test('editing a shared native DXF does not restyle its other owner', () {
    final book = _native(shared: true);
    book.firstSheet.conditionalFormats.first.fillRgb = '12AB34';
    final saved = _save(book);
    final rules = SheetDeserializer().read(saved).firstSheet.conditionalFormats;
    expect(rules.first.fillRgb, '12AB34');
    expect(rules.last.fillRgb, 'AA0000');
    expect(rules.first.dxfId, 2);
    expect(rules.last.dxfId, 0);
    _expectNativeExtras(_dxfs(saved)[2]);
  });

  test('font edit keeps native theme fill and foreign color attributes', () {
    var book = _native(theme: true);
    final originalFill = _xml(
      _dxfs(book.package!).first.firstChild('fill', namespaceUri: _ns)!,
    );
    final expectedFill = book.firstSheet.conditionalFormats.single.fillRgb;
    book.firstSheet.conditionalFormats.single.fontRgb = '12AB34';
    for (var cycle = 0; cycle < 2; cycle++) {
      final saved = _save(book);
      book = SheetDeserializer().read(saved);
      final rule = book.firstSheet.conditionalFormats.single;
      final dxf = _dxfs(saved)[rule.dxfId!];
      expect(rule.fontRgb, '12AB34');
      expect(rule.fillRgb, expectedFill);
      expect(_xml(dxf.firstChild('fill', namespaceUri: _ns)!), originalFill);
      final color = dxf
          .firstChild('font', namespaceUri: _ns)!
          .firstChild('color', namespaceUri: _ns)!;
      expect(color.getAttribute('rgb', namespaceUri: ''), 'FF12AB34');
      expect(color.getAttribute('theme', namespaceUri: ''), isNull);
      expect(color.getAttribute('tint', namespaceUri: ''), isNull);
      expect(
        color.getAttribute('theme', namespaceUri: 'urn:quds:dxf-test'),
        'opaque',
      );
    }
  });

  test(
    'a new worksheet can add styles alongside an untouched native sheet',
    () {
      final book = _native();
      final other = SmlWorksheet(name: 'New', sheetId: 2);
      other.conditionalFormats.add(_rule('A1', fill: '12AB34'));
      book.sheets.add(other);
      final saved = _save(book);
      final reopened = SheetDeserializer().read(saved);
      expect(reopened.firstSheet.conditionalFormats.single.dxfId, 0);
      expect(reopened.sheets.last.conditionalFormats.single.fillRgb, '12AB34');
      expect(reopened.sheets.last.conditionalFormats.single.dxfId, 2);
      _expectValidIds(reopened, saved);
    },
  );

  test('an invalid supplied dxfId cannot corrupt a newly styled rule', () {
    final book = _native();
    book.firstSheet.conditionalFormats.add(
      _rule('B1', fill: '12AB34')..dxfId = 999,
    );
    final saved = _save(book);
    final reopened = SheetDeserializer().read(saved);
    expect(reopened.firstSheet.conditionalFormats.last.fillRgb, '12AB34');
    _expectValidIds(reopened, saved);
  });

  for (final state in [
    'fresh empty',
    'fresh rule',
    'native empty',
    'native edit',
  ]) {
    test('rename save checkpoint permits undo and redo: $state', () {
      final book = state == 'native edit'
          ? _native()
          : state == 'native empty'
          ? SheetDeserializer().read(_save(SmlWorkbook()))
          : SmlWorkbook();
      final sheet = book.firstSheet;
      final originalName = sheet.name;
      if (state == 'fresh rule') {
        sheet.conditionalFormats.add(
          _rule('A1', fill: '12AB34')..formula = '$originalName!A1>0',
        );
      } else if (state == 'native edit') {
        sheet.conditionalFormats.single.fillRgb = '12AB34';
      }
      final originalState = sheet.conditionalFormatState();
      final rename = SheetRename.rename(book, sheet, 'Next');
      final renamedState = sheet.conditionalFormatState();
      _save(book);
      expect(sheet.sourceConditionalFormatState, renamedState);

      rename.undo();
      expect(sheet.name, originalName);
      expect(sheet.conditionalFormatState(), originalState);
      var reopened = SheetDeserializer().read(_save(book));
      expect(reopened.firstSheet.name, originalName);
      expect(
        reopened.firstSheet.conditionalFormats.map((rule) => rule.formula),
        sheet.conditionalFormats.map((rule) => rule.formula),
      );

      rename.apply();
      expect(sheet.name, 'Next');
      expect(sheet.conditionalFormatState(), renamedState);
      reopened = SheetDeserializer().read(_save(book));
      expect(reopened.firstSheet.name, 'Next');
      expect(
        reopened.firstSheet.conditionalFormats.map((rule) => rule.formula),
        sheet.conditionalFormats.map((rule) => rule.formula),
      );
      if (sheet.conditionalFormats.isNotEmpty) {
        expect(reopened.firstSheet.conditionalFormats.single.fillRgb, '12AB34');
      }
    });
  }

  test(
    'rename save checkpoint still rejects a newer saved conditional edit',
    () {
      final book = _native();
      final sheet = book.firstSheet;
      final rename = SheetRename.rename(book, sheet, 'Next');
      _save(book);
      sheet.conditionalFormats.single.fillRgb = '12AB34';
      _save(book);
      final source = sheet.sourceConditionalFormatState;
      final native = book.package!
          .getPart('/xl/worksheets/sheet1.xml')!
          .readText();
      expect(rename.undo, throwsStateError);
      expect(sheet.name, 'Next');
      expect(sheet.conditionalFormats.single.fillRgb, '12AB34');
      expect(sheet.sourceConditionalFormatState, source);
      expect(
        book.package!.getPart('/xl/worksheets/sheet1.xml')!.readText(),
        native,
      );
    },
  );
}

SmlConditionalRule _rule(String range, {String fill = '', String font = ''}) =>
    SmlConditionalRule(
      range: SmlRange.parse(range),
      kind: SmlConditionalKind.expression,
      formula: 'TRUE',
      fillRgb: fill,
      fontRgb: font,
    );

OpcPackage _save(SmlWorkbook book) => OpcPackage.openBytes(
  SheetSerializer().writeBytes(book, recalculate: false),
);

List<XmlElement> _dxfs(OpcPackage package) =>
    XmlDocument.parse(package.getPart(_stylesUri)!.readText()).root!
        .firstChild('dxfs', namespaceUri: _ns)!
        .childrenNamed('dxf', namespaceUri: _ns);

String _xml(XmlElement node) =>
    XmlDocument(root: node).toXmlString(declaration: false);

void _expectNativeExtras(XmlElement dxf) {
  expect(
    dxf
        .firstChild('font', namespaceUri: _ns)!
        .firstChild('b', namespaceUri: _ns),
    isNotNull,
  );
  expect(
    dxf
        .firstChild('border', namespaceUri: _ns)!
        .firstChild('bottom', namespaceUri: _ns)!
        .getAttribute('style'),
    'thin',
  );
  expect(
    dxf.firstChild('numFmt', namespaceUri: _ns)!.getAttribute('formatCode'),
    '0.00',
  );
  expect(
    dxf
        .firstChild('opaque', namespaceUri: 'urn:quds:dxf-test')!
        .getAttribute('value'),
    'retained',
  );
}

void _expectValidIds(SmlWorkbook book, OpcPackage package) {
  final count = _dxfs(package).length;
  for (final sheet in book.sheets) {
    for (final rule in sheet.conditionalFormats) {
      if (rule.dxfId != null) {
        expect(rule.dxfId, inInclusiveRange(0, count - 1));
      }
    }
  }
}

SmlWorkbook _native({bool shared = false, bool theme = false}) {
  final initial = SmlWorkbook()..firstSheet.cellA1('A1').value = 7;
  final package = _save(initial);
  final styles = XmlDocument.parse(SmlStyleSheet().toXml());
  styles.root!.attributes.add(
    XmlAttribute(
      localName: 'q',
      prefix: 'xmlns',
      namespaceUri: 'http://www.w3.org/2000/xmlns/',
      value: 'urn:quds:dxf-test',
    ),
  );
  final fontColor = theme ? 'theme="4" tint="0.25"' : 'rgb="FF003366"';
  final fillColor = theme ? 'theme="5" tint="0.4"' : 'rgb="FFAA0000"';
  styles.root!.addChild(
    XmlDocument.parse(
      '<dxfs xmlns="$_ns" xmlns:q="urn:quds:dxf-test" count="2">'
      '<dxf><font><b/><color $fontColor q:theme="opaque"/></font>'
      '<numFmt numFmtId="2" formatCode="0.00"/>'
      '<fill><patternFill patternType="solid"><fgColor $fillColor/>'
      '</patternFill></fill>'
      '<border><bottom style="thin"><color rgb="FF112233"/></bottom></border>'
      '<q:opaque value="retained"/></dxf>'
      '<dxf><font><i/><color rgb="FF445566"/></font></dxf>'
      '</dxfs>',
    ).root!,
  );
  package
      .createPart(_stylesUri, OfficeContentTypes.sheetStyles)
      .writeText(styles.toXmlString());
  package
      .relationshipsFor('/xl/workbook.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  final sheet = package.getPart('/xl/worksheets/sheet1.xml')!;
  final document = XmlDocument.parse(sheet.readText());
  for (final range in ['A1', if (shared) 'B1']) {
    document.root!.addChild(
      XmlDocument.parse(
        '<conditionalFormatting xmlns="$_ns" sqref="$range">'
        '<cfRule type="expression" priority="${range == 'A1' ? 1 : 2}" dxfId="0">'
        '<formula>TRUE</formula></cfRule></conditionalFormatting>',
      ).root!,
    );
  }
  sheet.writeText(document.toXmlString());
  return SheetDeserializer().read(package);
}
