import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

SheetEditorController _controller() {
  final package = OpcPackage.openBytes(
    File(
      '../quds_office_engine/test/fixtures/fidelity/sheet-normal-font-native.xlsx',
    ).readAsBytesSync(),
  );
  final part = package.getPart('/xl/worksheets/sheet1.xml')!;
  part.writeText(
    part.readText().replaceFirst(
      RegExp(r'<sheetData>.*?</sheetData>', dotAll: true),
      '<sheetData><row r="1"><c r="A1" s="0"><v>1</v></c>'
      '<c r="B1"><v>2</v></c></row></sheetData>',
    ),
  );
  final controller = SheetEditorController.fromBytes(
    package.save(),
    columnMetricsResolver: (_) => null,
  );
  addTearDown(controller.dispose);
  return controller;
}

Map<String, String?> _styles(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  final root = XmlDocument.parse(
    package.getPart('/xl/worksheets/sheet1.xml')!.readText(),
  ).root!;
  return <String, String?>{
    for (final row in root.firstChild('sheetData')!.childrenNamed('row'))
      for (final cell in row.childrenNamed('c'))
        cell.getAttribute('r')!: cell.getAttribute('s'),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final rows in <bool>[false, true]) {
    test(
      '${rows ? 'row' : 'column'} history preserves explicit and absent native styles',
      () async {
        final controller = _controller();
        expect(_styles(controller.saveBytes()), {'A1': '0', 'B1': null});
        if (rows) {
          controller.insertSheetRows(after: false, index: 0);
        } else {
          controller.insertSheetCols(after: false, index: 0);
        }
        final shifted = rows
            ? {'A2': '0', 'B2': null}
            : {'B1': '0', 'C1': null};
        expect(_styles(controller.saveBytes()), shifted);
        controller.undo();
        expect(_styles(controller.saveBytes()), {'A1': '0', 'B1': null});
        controller.redo();
        expect(_styles(await controller.saveBytesAsync()), shifted);
        controller.undo();
        final saved = await controller.saveBytesAsync();
        await controller.loadBytesAsync(saved);
        expect(_styles(controller.saveBytes()), {'A1': '0', 'B1': null});
        expect(controller.sheet.cellA1('A1').hasExplicitStyleIndex, isTrue);
        expect(controller.sheet.cellA1('B1').hasExplicitStyleIndex, isFalse);
      },
    );
  }

  test(
    'undoing deletion restores explicit style zero on the recovered cell',
    () {
      final controller = _controller();
      controller.deleteSheetCols(index: 0);
      expect(_styles(controller.saveBytes()), {'A1': null});
      controller.undo();
      expect(_styles(controller.saveBytes()), {'A1': '0', 'B1': null});
      controller.redo();
      expect(_styles(controller.saveBytes()), {'A1': null});
    },
  );
}
