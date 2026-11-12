import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

Uint8List _source() => File(
  '../quds_office_engine/test/fixtures/fidelity/sheet-normal-font-native.xlsx',
).readAsBytesSync();

List<String?> _widths(Uint8List bytes) =>
    XmlDocument.parse(
          OpcPackage.openBytes(
            bytes,
          ).getPart('/xl/worksheets/sheet1.xml')!.readText(),
        ).root!
        .firstChild('cols')!
        .childElements
        .map((col) => col.getAttribute('width'))
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  test(
    'opening uses the actual loaded Normal face instead of fixed width seven',
    () {
      // Independent hmtx proof for the exact bundled face, not a TextPainter or
      // engine column-conversion assertion. Liberation Mono's ten advances are
      // all 1229/2048 em: at 24pt/96dpi they are 19.203125px, rounded to 19px.
      final font = SfntFont.parse(
        File('fonts/LiberationMono-Regular.ttf').readAsBytesSync(),
      );
      expect(font.unitsPerEm, 2048);
      for (var digit = 48; digit <= 57; digit++) {
        expect(font.advanceWidth(font.glyphIdFor(digit)), 1229);
      }
      final controller = SheetEditorController.fromBytes(_source());
      addTearDown(controller.dispose);
      expect(controller.sheet.columnWidth(0), 165);
      expect(controller.sheet.columnWidth(1), 166);
      expect(controller.sheet.columnWidth(2), 418);
      expect(controller.sheet.columnWidth(3), 195);
      expect(controller.sheet.columnAt(330.9), 1);
      expect(controller.sheet.columnAt(331), 2);
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      expect(_widths(controller.saveBytes()), ['8.7109375', '8.72', '22.0']);
    },
  );
}
