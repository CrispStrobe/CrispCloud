import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _x = OfficeNamespaces.x;

SheetEditorController _controller(int styleIndex) {
  final package = OpcPackage.create(OpcPackageKind.sheet);
  package
      .createPart('/xl/styles.xml', OfficeContentTypes.sheetStyles)
      .writeText(
        File(
          '../quds_office_engine/test/fixtures/fidelity/sheet-fill-native.xml',
        ).readAsStringSync(),
      );
  package
      .relationshipsFor('/xl/workbook.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  package
      .getPart('/xl/worksheets/sheet1.xml')!
      .writeText(
        '<s:worksheet xmlns:s="$_x"><s:sheetData><s:row r="1">'
        '<s:c r="A1" s="$styleIndex"><s:v>42</s:v></s:c>'
        '</s:row></s:sheetData></s:worksheet>',
      );
  final controller = SheetEditorController(
    workbook: SheetDeserializer().read(package),
  );
  addTearDown(controller.dispose);
  return controller;
}

XmlElement _savedFill(SheetEditorController controller) {
  final package = OpcPackage.openBytes(controller.saveBytes());
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
  final xf = styles
      .firstChild('cellXfs', namespaceUri: _x)!
      .childrenNamed(
        'xf',
        namespaceUri: _x,
      )[int.parse(cell.getAttribute('s') ?? '0')];
  return styles
      .firstChild('fills', namespaceUri: _x)!
      .childrenNamed('fill', namespaceUri: _x)[int.parse(
    xf.getAttribute('fillId')!,
  )];
}

String _xml(XmlElement element) =>
    XmlDocument(root: element).toXmlString(declaration: false);

void _expectSolid(XmlElement fill, String rgb) {
  final pattern = fill.firstChild('patternFill', namespaceUri: _x)!;
  expect(pattern.getAttribute('patternType'), 'solid');
  final color = pattern.firstChild('fgColor', namespaceUri: _x)!;
  expect(color.getAttribute('rgb'), 'FF$rgb');
  expect(color.getAttribute('theme'), isNull);
  expect(color.getAttribute('indexed'), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final styleIndex in [0, 1, 3]) {
    test('equal-color command and undo preserve native fill $styleIndex', () {
      final controller = _controller(styleIndex);
      final before = _xml(_savedFill(controller));
      final rgb = controller.selectionFillRgb;
      controller.setSelectionFillRgb(rgb);
      expect(controller.sheet.cellA1('A1').hasExplicitFillColorEdit, isTrue);
      _expectSolid(_savedFill(controller), rgb);
      controller.undo();
      expect(controller.sheet.cellA1('A1').hasExplicitFillColorEdit, isFalse);
      expect(_xml(_savedFill(controller)), before);
      controller.redo();
      expect(controller.sheet.cellA1('A1').hasExplicitFillColorEdit, isTrue);
      _expectSolid(_savedFill(controller), rgb);
    });
  }

  test('clearing an imported gradient is undoable even with an empty RGB', () {
    final controller = _controller(2);
    expect(controller.selectionFillRgb, isEmpty);
    final before = _xml(_savedFill(controller));
    expect(
      _savedFill(controller).firstChild('gradientFill', namespaceUri: _x),
      isNotNull,
    );
    controller.setSelectionFillRgb('');
    expect(
      _savedFill(controller).firstChild('gradientFill', namespaceUri: _x),
      isNull,
    );
    expect(
      _savedFill(controller)
          .firstChild('patternFill', namespaceUri: _x)!
          .getAttribute('patternType'),
      'none',
    );
    controller.undo();
    expect(controller.sheet.cellA1('A1').hasExplicitFillColorEdit, isFalse);
    expect(_xml(_savedFill(controller)), before);
    controller.redo();
    expect(
      _savedFill(controller).firstChild('gradientFill', namespaceUri: _x),
      isNull,
    );
  });

  test('unrelated font history retains the exact native gradient', () {
    final controller = _controller(2);
    final before = _xml(_savedFill(controller));
    controller.setSelectionFontRgb('00FF00');
    expect(controller.sheet.cellA1('A1').hasExplicitFillColorEdit, isFalse);
    expect(_xml(_savedFill(controller)), before);
    controller.undo();
    expect(_xml(_savedFill(controller)), before);
    controller.redo();
    expect(_xml(_savedFill(controller)), before);
  });

  test(
    'interleaved grid history retains explicit fill intent until undone',
    () {
      final controller = _controller(0);
      final before = _xml(_savedFill(controller));
      controller.setSelectionFillRgb('000000');
      controller.setSelectionFontRgb('FF0000');
      _expectSolid(_savedFill(controller), '000000');
      controller.undo();
      expect(controller.sheet.cellA1('A1').hasExplicitFillColorEdit, isTrue);
      _expectSolid(_savedFill(controller), '000000');
      controller.undo();
      expect(controller.sheet.cellA1('A1').hasExplicitFillColorEdit, isFalse);
      expect(_xml(_savedFill(controller)), before);
      controller.redo();
      controller.redo();
      _expectSolid(_savedFill(controller), '000000');
    },
  );
}
