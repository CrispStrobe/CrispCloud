import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

Uint8List _source({String? family}) {
  final bytes = File(
    '../quds_office_engine/test/fixtures/fidelity/sheet-normal-font-native.xlsx',
  ).readAsBytesSync();
  if (family == null) return bytes;
  final package = OpcPackage.openBytes(bytes);
  final part = package.getPart('/xl/styles.xml')!;
  part.writeText(part.readText().replaceFirst('Liberation Mono', family));
  return package.save();
}

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
    'isolate open and three host saves use the same resolved metric',
    () async {
      final controller = SheetEditorController();
      addTearDown(controller.dispose);
      await controller.loadBytesAsync(_source());
      expect(controller.workbook.columnMetrics!.maximumDigitWidthPx, 19);
      expect(
        controller.workbook.columnMetrics!.resolvedFontFamily,
        'Liberation Mono',
      );
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = cycle == 2
            ? await controller.saveBytesAsync()
            : controller.saveBytes();
        expect(_widths(bytes), ['8.7109375', '8.72', '22.0']);
        await controller.loadBytesAsync(bytes);
        expect(controller.sheet.columnWidth(1), 166);
        expect(controller.sheet.columnWidth(2), 418);
        expect(controller.isDirty, isFalse);
      }
    },
  );

  test(
    'unavailable families keep fallback provenance and native precision',
    () {
      final controller = SheetEditorController.fromBytes(
        _source(family: 'Missing custom face 029'),
      );
      addTearDown(controller.dispose);
      expect(controller.workbook.columnMetrics, isNull);
      expect(controller.sheet.maximumDigitWidthPx, 7);
      expect(controller.sheet.columnWidth(2), 154);
      expect(controller.refreshColumnMetrics(), isFalse);
      expect(controller.isDirty, isFalse);
      expect(_widths(controller.saveBytes()), ['8.7109375', '8.72', '22.0']);
    },
  );

  test('known aliases record the actual bundled face explicitly', () {
    final controller = SheetEditorController.fromBytes(
      _source(family: 'Courier New'),
    );
    addTearDown(controller.dispose);
    final metrics = controller.workbook.columnMetrics!;
    expect(metrics.resolvedFontFamily, 'Liberation Mono');
    expect(
      metrics.substitutes(controller.workbook.styles!.normalFont!),
      isTrue,
    );
    expect(controller.sheet.columnWidth(2), 418);
    expect(OfficeHostFonts.registeredFamily('Unknown face'), isNull);
    expect(
      OfficeHostFonts.registeredFamily('Noto Naskh Arabic', italic: true),
      isNull,
    );
  });

  test(
    'view-only refresh preserves dirty state, history and edited pixels',
    () {
      var ready = false;
      final controller = SheetEditorController.fromBytes(
        _source(),
        columnMetricsResolver: (font) =>
            ready ? SheetFontMetrics.measure(font) : null,
      );
      addTearDown(controller.dispose);
      expect(controller.sheet.columnWidth(2), 154);
      controller.previewColumnWidth(0, 96);
      controller.commitResize();
      final revision = controller.contentRevision;
      expect(controller.isDirty, isTrue);
      expect(controller.canUndo, isTrue);
      ready = true;
      expect(controller.refreshColumnMetrics(), isTrue);
      expect(controller.contentRevision, revision);
      expect(controller.isDirty, isTrue);
      expect(controller.canUndo, isTrue);
      expect(controller.sheet.columnWidth(0), 96);
      expect(controller.sheet.columnWidth(2), 418);
      expect(_widths(controller.saveBytes()), ['5.05078125', '8.72', '22.0']);
    },
  );

  test('resize undo restores native precision after late font resolution', () {
    var ready = false;
    final controller = SheetEditorController.fromBytes(
      _source(),
      columnMetricsResolver: (font) =>
          ready ? SheetFontMetrics.measure(font) : null,
    );
    addTearDown(controller.dispose);
    controller.previewColumnWidth(1, 96);
    controller.commitResize();
    ready = true;
    controller.refreshColumnMetrics();
    expect(controller.sheet.columnWidth(1), 96);
    controller.undo();
    expect(controller.sheet.columnWidth(1), 166);
    expect(_widths(controller.saveBytes()), ['8.7109375', '8.72', '22.0']);
    controller.redo();
    expect(controller.sheet.columnWidth(1), 96);
    expect(_widths(controller.saveBytes()), [
      '8.7109375',
      '5.05078125',
      '22.0',
    ]);
  });

  test('no-op resize keeps the native width for later font resolution', () {
    var ready = false;
    final controller = SheetEditorController.fromBytes(
      _source(),
      columnMetricsResolver: (font) =>
          ready ? SheetFontMetrics.measure(font) : null,
    );
    addTearDown(controller.dispose);
    controller.previewColumnWidth(1, 61);
    controller.commitResize();
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    ready = true;
    controller.refreshColumnMetrics();
    expect(controller.sheet.columnWidth(1), 166);
    expect(_widths(controller.saveBytes()), ['8.7109375', '8.72', '22.0']);
  });

  test('column insertion undo restores native widths under the new metric', () {
    var ready = false;
    final controller = SheetEditorController.fromBytes(
      _source(),
      columnMetricsResolver: (font) =>
          ready ? SheetFontMetrics.measure(font) : null,
    );
    addTearDown(controller.dispose);
    controller.insertSheetCols(index: 1, after: false);
    ready = true;
    controller.refreshColumnMetrics();
    controller.undo();
    expect(controller.sheet.columnWidth(1), 166);
    expect(_widths(controller.saveBytes()), ['8.7109375', '8.72', '22.0']);
  });

  test('newly selected sheets use the resolved workbook metric', () {
    final controller = SheetEditorController.fromBytes(_source());
    addTearDown(controller.dispose);
    final added = SmlWorksheet(name: 'Added', sheetId: 2)
      ..setColumnWidth(0, 96);
    controller.workbook.sheets.add(added);
    controller.setActiveSheet(1);
    expect(controller.sheet.maximumDigitWidthPx, 19);
    expect(controller.sheet.columnWidth(0), 96);
    final saved = OpcPackage.openBytes(controller.saveBytes());
    final xml = XmlDocument.parse(
      saved.getPart(added.sourcePartUri!)!.readText(),
    );
    expect(
      xml.root!.firstChild('cols')!.childElements.single.getAttribute('width'),
      '5.05078125',
    );
  });

  for (final column in [true, false]) {
    test(
      '${column ? "column" : "row"} resize stays with preview sheet across tab changes',
      () {
        final controller = SheetEditorController.fromBytes(_source());
        addTearDown(controller.dispose);
        final original = controller.sheet;
        final another = SmlWorksheet(name: 'Other', sheetId: 2)
          ..setColumnWidth(1, 120)
          ..setRowHeight(1, 32);
        controller.workbook.sheets.add(another);
        if (column) {
          controller.previewColumnWidth(1, 96);
        } else {
          controller.previewRowHeight(1, 48);
        }
        controller.setActiveSheet(1);
        controller.commitResize();
        expect(original.columnWidth(1), column ? 96 : 166);
        expect(original.rowHeightAt(1), column ? 20 : 48);
        expect(another.columnWidth(1), 120);
        expect(another.rowHeightAt(1), 32);
        controller.undo();
        expect(original.columnWidth(1), 166);
        expect(original.exportColumnWidth(1), 8.72);
        expect(original.rowHeights.containsKey(1), isFalse);
        expect(another.columnWidth(1), 120);
        expect(another.rowHeightAt(1), 32);
        controller.redo();
        expect(original.columnWidth(1), column ? 96 : 166);
        expect(original.rowHeightAt(1), column ? 20 : 48);
        expect(another.columnWidth(1), 120);
        expect(another.rowHeightAt(1), 32);
      },
    );

    for (final transition in ['setMode', 'config', 'syncConfig']) {
      test(
        '$transition cancels a pending ${column ? "column" : "row"} preview without history',
        () {
          final controller = SheetEditorController.fromBytes(_source());
          addTearDown(controller.dispose);
          final original = controller.sheet;
          final revision = controller.contentRevision;
          if (column) {
            controller.previewColumnWidth(1, 96);
          } else {
            controller.previewRowHeight(1, 48);
          }
          const viewing = OfficeSurfaceConfig(
            mode: OfficeInteractionMode.viewing,
          );
          switch (transition) {
            case 'setMode':
              controller.setMode(OfficeInteractionMode.viewing);
            case 'config':
              controller.config = viewing;
            case 'syncConfig':
              controller.syncConfig(viewing);
          }
          expect(original.columnWidth(1), 166);
          expect(original.exportColumnWidth(1), 8.72);
          expect(original.rowHeights.containsKey(1), isFalse);
          controller.commitResize();
          expect(controller.isDirty, isFalse);
          expect(controller.canUndo, isFalse);
          expect(controller.contentRevision, revision);
        },
      );
    }
  }

  test('read-only controllers resolve geometry without document edits', () {
    final controller = SheetEditorController.fromBytes(
      _source(),
      config: const OfficeSurfaceConfig(mode: OfficeInteractionMode.viewing),
    );
    addTearDown(controller.dispose);
    final revision = controller.contentRevision;
    expect(controller.sheet.columnWidth(2), 418);
    expect(controller.refreshColumnMetrics(), isTrue);
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    expect(controller.contentRevision, revision);
  });
}
