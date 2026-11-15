import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:crisp_cloud/services/office_device_export.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';

import '../support/office_test_harness.dart';

Uint8List _source() =>
    File('packages/quds_office_engine/test/fixtures/fidelity/legacy-sheet.xls')
        .readAsBytesSync();
void _edit(SheetEditorController sheet, String text) {
  sheet.beginCellEdit(initial: text, replace: true);
  sheet.commitCellEdit();
}

void main() {
  testWidgets(
    'legacy Save emits XLSX, keeps BIFF original, and cleans only saved edits',
    (tester) async {
      await tester.runAsync(() async {
        final original = _source();
        Uint8List? output;
        final host = await OfficeTestHarness.open(
          tester,
          name: 'legacy.xls',
          initialBytes: original,
          copyExporter: (bytes, name, title) async {
            expect(name, 'legacy.xlsx');
            output = bytes;
            return OfficeCopyOutcome.savedCopy;
          },
        );
        final sheet = host.controller as SheetEditorController;
        expect(sheet.sheet.cellA1('A1').value, 'Quarter');
        _edit(sheet, 'Edited');
        expect(sheet.isDirty, isTrue);
        await host.save();
        expect(
          SheetDeserializer()
              .readBytes(output!)
              .sheets
              .first
              .cellA1('A1')
              .value,
          'Edited',
        );
        expect(sheet.isDirty, isFalse);
        expect(host.savedBytes, orderedEquals(original));
        expect(host.cloud.writes, isEmpty);
        await host.back();
        await officePumpUntil(
          tester,
          () => find.byType(OfficeEditorDialog).evaluate().isEmpty,
        );
        expect(find.byType(OfficeEditorDialog), findsNothing);
        await host.dispose();
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'legacy save cannot clean edits made while its copy picker is open',
    (tester) async {
      await tester.runAsync(() async {
        final picker = Completer<OfficeCopyOutcome?>();
        Uint8List? output;
        final host = await OfficeTestHarness.open(
          tester,
          name: 'legacy.xlt',
          initialBytes: _source(),
          copyExporter: (bytes, name, title) {
            expect(name, 'legacy.xlsx');
            output = bytes;
            return picker.future;
          },
        );
        final sheet = host.controller as SheetEditorController;
        _edit(sheet, 'Captured');
        host.ribbon.onSave();
        await officePumpUntil(tester, () => output != null);
        _edit(sheet, 'Later');
        picker.complete(OfficeCopyOutcome.savedCopy);
        await officePumpUntil(tester, () => !host.ribbon.saving);
        expect(sheet.isDirty, isTrue);
        expect(
          SheetDeserializer()
              .readBytes(output!)
              .sheets
              .first
              .cellA1('A1')
              .value,
          'Captured',
        );
        expect(sheet.sheet.cellA1('A1').value, 'Later');
        expect(host.cloud.writes, isEmpty);
        await host.dispose();
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a refused XLS export retains the true original bytes and extension',
    (tester) async {
      await tester.runAsync(() async {
        final supplied = Uint8List.fromList([1, 2, 3, 4]);
        Uint8List? output;
        final host = await OfficeTestHarness.open(
          tester,
          name: 'refused.xls',
          bytesOverride: supplied,
          expectEditor: false,
          copyExporter: (bytes, name, title) async {
            expect(name, 'refused.xls');
            expect(title, 'Export original');
            output = bytes;
            return OfficeCopyOutcome.savedCopy;
          },
        );
        supplied.fillRange(0, supplied.length, 0);
        await tester.tap(find.text('Export original'));
        await officePumpUntil(tester, () => output != null);
        expect(output, orderedEquals([1, 2, 3, 4]));
        expect(host.cloud.writes, isEmpty);
        await host.dispose();
      });
      expect(tester.takeException(), isNull);
    },
  );
}
