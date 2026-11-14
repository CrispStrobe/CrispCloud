import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _x = OfficeNamespaces.x;

SheetEditorController _controller() {
  final book = SmlWorkbook();
  book.firstSheet.cellA1('A1').value = 'Theme black';
  final package = SheetSerializer().write(book);
  package
      .createPart('/xl/styles.xml', OfficeContentTypes.sheetStyles)
      .writeText(
        '<s:styleSheet xmlns:s="$_x"><s:fonts count="1"><s:font>'
        '<s:sz val="11"/><s:color theme="1"/><s:name val="Calibri"/>'
        '</s:font></s:fonts><s:fills count="2"><s:fill><s:patternFill patternType="none"/>'
        '</s:fill><s:fill><s:patternFill patternType="gray125"/></s:fill></s:fills>'
        '<s:borders count="1"><s:border/></s:borders>'
        '<s:cellStyleXfs count="1"><s:xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>'
        '</s:cellStyleXfs><s:cellXfs count="1">'
        '<s:xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '</s:cellXfs></s:styleSheet>',
      );
  package
      .relationshipsFor('/xl/workbook.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  final controller = SheetEditorController(
    workbook: SheetDeserializer().read(package),
  );
  addTearDown(controller.dispose);
  return controller;
}

XmlElement _color(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  final sheet = XmlDocument.parse(
    package.getPart('/xl/worksheets/sheet1.xml')!.readText(),
  ).root!;
  final cell = sheet
      .firstChild('sheetData', namespaceUri: _x)!
      .firstChild('row', namespaceUri: _x)!
      .firstChild('c', namespaceUri: _x)!;
  final styles = XmlDocument.parse(
    package.getPart('/xl/styles.xml')!.readText(),
  ).root!;
  final format = styles
      .firstChild('cellXfs', namespaceUri: _x)!
      .childrenNamed(
        'xf',
        namespaceUri: _x,
      )[int.parse(cell.getAttribute('s') ?? '0')];
  final font = styles
      .firstChild('fonts', namespaceUri: _x)!
      .childrenNamed(
        'font',
        namespaceUri: _x,
      )[int.parse(format.getAttribute('fontId') ?? '0')];
  return font.firstChild('color', namespaceUri: _x)!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'equal RGB command writes fixed color and undo restores the imported theme',
    () {
      final controller = _controller();
      expect(controller.selectionFontRgb, '000000');
      expect(_color(controller.saveBytes()).getAttribute('theme'), '1');
      controller.setSelectionFontRgb('000000');
      expect(controller.sheet.cellA1('A1').hasExplicitFontColorEdit, isTrue);
      expect(_color(controller.saveBytes()).getAttribute('rgb'), 'FF000000');
      controller.undo();
      expect(controller.sheet.cellA1('A1').hasExplicitFontColorEdit, isFalse);
      expect(_color(controller.saveBytes()).getAttribute('theme'), '1');
      expect(_color(controller.saveBytes()).getAttribute('rgb'), isNull);
      controller.redo();
      expect(controller.sheet.cellA1('A1').hasExplicitFontColorEdit, isTrue);
      expect(_color(controller.saveBytes()).getAttribute('rgb'), 'FF000000');
      expect(_color(controller.saveBytes()).getAttribute('theme'), isNull);
    },
  );

  test('unrelated grid history does not materialize native theme color', () {
    final controller = _controller();
    controller.setSelectionFillRgb('ABCDEF');
    expect(_color(controller.saveBytes()).getAttribute('theme'), '1');
    controller.undo();
    expect(controller.sheet.cellA1('A1').hasExplicitFontColorEdit, isFalse);
    expect(_color(controller.saveBytes()).getAttribute('theme'), '1');
    controller.redo();
    expect(_color(controller.saveBytes()).getAttribute('theme'), '1');
  });
}
