import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/services/office_device_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import '../support/office_test_harness.dart';

Uint8List _source() {
  const content = '''
<office:document-content
 xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
 <office:body><office:spreadsheet><table:table table:name="Budget">
  <table:table-row>
   <table:table-cell office:value-type="string" table:number-columns-spanned="2"><text:p>Heading</text:p></table:table-cell>
   <table:covered-table-cell/>
   <table:table-cell office:value-type="float" office:value="7"/>
  </table:table-row>
  <table:table-row table:number-rows-repeated="2"/>
  <table:table-row><table:table-cell office:value-type="string"><text:p>Tail</text:p></table:table-cell></table:table-row>
 </table:table></office:spreadsheet></office:body>
</office:document-content>
''';
  final archive = Archive()
    ..addFile(
      ArchiveFile.bytes(
        'mimetype',
        utf8.encode('application/vnd.oasis.opendocument.spreadsheet'),
      ),
    )
    ..addFile(ArchiveFile.bytes('content.xml', utf8.encode(content)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void _edit(SheetEditorController sheet, String text) {
  sheet.selection.selectCell(SmlCellRef.parse('A4'));
  sheet.beginCellEdit(initial: text, replace: true);
  sheet.commitCellEdit();
  expect(sheet.isDirty, isTrue);
}

void _checkCopy(Uint8List bytes, String text) {
  final reopened = SheetEditorController.fromBytes(bytes);
  try {
    expect(reopened.sheet.name, 'Budget');
    expect(reopened.sheet.cellA1('A1').value, 'Heading');
    expect(reopened.sheet.cellA1('C1').value, 7);
    expect(reopened.sheet.cellA1('A2').asString, isEmpty);
    expect(reopened.sheet.cellA1('A3').asString, isEmpty);
    expect(reopened.sheet.cellA1('A4').value, text);
  } finally {
    reopened.dispose();
  }
}

void main() {
  testWidgets('Save As adopts converted ODS workbook as a writable XLSX', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'office-converted-save-as-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final destination = '${directory.path}/budget.xlsx';
      final original = _source();
      var copies = 0;
      final host = await OfficeTestHarness.open(
        tester,
        name: 'budget.ods',
        initialBytes: original,
        saveAsExporter: (bytes, name, title, {initialDirectory}) async {
          expect(name, 'budget.xlsx');
          File(destination).writeAsBytesSync(bytes);
          return destination;
        },
        copyExporter: (bytes, name, title, {initialDirectory}) async {
          copies++;
          return null;
        },
      );
      final sheet = host.controller as SheetEditorController;
      _edit(sheet, 'Save As workbook');
      host.ribbon.onSaveAs!();
      await officePumpUntil(
        tester,
        () => host.ribbon.title == 'budget.xlsx' && !host.ribbon.saving,
      );
      expect(sheet.isDirty, isFalse);
      _edit(sheet, 'Later workbook edit');
      await host.save();
      expect(sheet.isDirty, isFalse);
      expect(copies, 0);
      final reopened = SheetEditorController.fromBytes(
        File(destination).readAsBytesSync(),
      );
      expect(reopened.sheet.cellA1('A4').value, 'Later workbook edit');
      reopened.dispose();
      expect(host.savedBytes, orderedEquals(original));
      expect(host.cloud.uploadAttempts, 0);
      await host.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('ODS editing saves an XLSX copy and preserves its source', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final original = _source();
      Uint8List? copied;
      final host = await OfficeTestHarness.open(
        tester,
        name: 'budget.ods',
        initialBytes: original,
        copyExporter: (bytes, name, title, {initialDirectory}) async {
          expect(name, 'budget.xlsx');
          expect(title, 'Save a copy');
          copied = bytes;
          return OfficeCopyOutcome.savedCopy;
        },
      );
      try {
        final sheet = host.controller as SheetEditorController;
        expect(sheet.sheet.cellA1('C1').value, 7);
        expect(sheet.sheet.cellA1('A4').value, 'Tail');
        _edit(sheet, 'Edited');
        await host.save();
        _checkCopy(copied!, 'Edited');
        expect(sheet.isDirty, isFalse);
        expect(host.cloud.uploadAttempts, 0);
        expect(host.cloud.writes, isEmpty);
        expect(host.savedBytes, orderedEquals(original));
      } finally {
        await host.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });

  for (final outcome in <OfficeCopyOutcome?>[
    null,
    OfficeCopyOutcome.downloadedCopy,
  ]) {
    testWidgets('ODS copy outcome $outcome retains unsaved edits', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final original = _source();
        var copies = 0;
        final host = await OfficeTestHarness.open(
          tester,
          name: 'budget.ods',
          initialBytes: original,
          copyExporter: (bytes, name, title, {initialDirectory}) async {
            copies++;
            expect(name, 'budget.xlsx');
            _checkCopy(bytes, 'Unsaved');
            return outcome;
          },
        );
        try {
          final sheet = host.controller as SheetEditorController;
          _edit(sheet, 'Unsaved');
          await host.save();
          expect(copies, 1);
          expect(sheet.isDirty, isTrue);
          expect(host.ribbon.dirty, isTrue);
          expect(host.cloud.uploadAttempts, 0);
          expect(host.savedBytes, orderedEquals(original));
        } finally {
          await host.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ODS copy completion cannot clean a newer edit', (tester) async {
    await tester.runAsync(() async {
      final original = _source();
      final picker = Completer<OfficeCopyOutcome?>();
      Uint8List? copied;
      final host = await OfficeTestHarness.open(
        tester,
        name: 'budget.ods',
        initialBytes: original,
        copyExporter: (bytes, name, title, {initialDirectory}) {
          copied = bytes;
          return picker.future;
        },
      );
      try {
        final sheet = host.controller as SheetEditorController;
        _edit(sheet, 'Exported');
        host.ribbon.onSave();
        await officePumpUntil(tester, () => copied != null);
        _edit(sheet, 'Newer');
        picker.complete(OfficeCopyOutcome.savedCopy);
        await officePumpUntil(tester, () => !host.ribbon.saving);
        _checkCopy(copied!, 'Exported');
        expect(sheet.sheet.cellA1('A4').value, 'Newer');
        expect(sheet.isDirty, isTrue);
        expect(host.cloud.uploadAttempts, 0);
        expect(host.savedBytes, orderedEquals(original));
      } finally {
        if (!picker.isCompleted) picker.complete(null);
        await host.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });
}
