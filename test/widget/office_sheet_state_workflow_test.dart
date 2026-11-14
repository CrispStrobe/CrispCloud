import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:xml/xml.dart' as xml;

import '../support/office_test_harness.dart';

const _output = 'build/office-sheet-state-acceptance';
const _s = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pr = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _ct = 'http://schemas.openxmlformats.org/package/2006/content-types';
const _budget = <String, Object>{
  'A1': 'Header',
  'B1': 'Amount',
  'A2': 'Travel',
  'B2': 125.5,
  'A3': 'Equipment',
  'B3': 300,
};
const _budgetAfterDelete = <String, Object>{
  'A1': 'Header',
  'B1': 'Amount',
  'A2': 'Equipment',
  'B2': 300,
};
const _reference = <String, Object>{
  'A1': 'Reference must remain',
  'B1': 73,
  'C3': 'Do not modify',
};

xml.XmlDocument _part(Archive archive, String path) {
  final entry = archive.findFile(path);
  expect(entry, isNotNull, reason: 'Missing native part $path');
  return xml.XmlDocument.parse(utf8.decode(entry!.content));
}

Archive _archive(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  expect(
    archive.files.map((entry) => entry.name).toSet(),
    hasLength(archive.files.length),
  );
  return archive;
}

/// Assemble the two worksheets directly as SpreadsheetML in an independently
/// authored native container. The input never passes through the Quds writer.
Uint8List _source() {
  final seed = File(
    'test/fixtures/office_native_workflows/native-sheet-source.xlsx',
  ).readAsBytesSync();
  expect(
    sha256.convert(seed).toString(),
    '548cf28efce66d0b4e3b9abb5a4f7f24f282ecadd7749cd65a5afa6ed0b5ba49',
  );
  final archive = _archive(seed);
  final workbook = _part(archive, 'xl/workbook.xml');
  workbook.rootElement
      .getElement('sheets', namespace: _s)!
      .children
      .add(
        xml.XmlDocument.parse(
          '<sheet xmlns="$_s" xmlns:r="$_r" name="Reference" '
          'sheetId="2" r:id="rId4"/>',
        ).rootElement.copy(),
      );
  final relationships = _part(archive, 'xl/_rels/workbook.xml.rels');
  relationships.rootElement.children.add(
    xml.XmlDocument.parse(
      '<Relationship xmlns="$_pr" Id="rId4" '
      'Type="$_r/worksheet" Target="worksheets/sheet2.xml"/>',
    ).rootElement.copy(),
  );
  final contentTypes = _part(archive, '[Content_Types].xml');
  contentTypes.rootElement.children.add(
    xml.XmlDocument.parse(
      '<Override xmlns="$_ct" PartName="/xl/worksheets/sheet2.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.'
      'spreadsheetml.worksheet+xml"/>',
    ).rootElement.copy(),
  );
  final replacements = <String, String>{
    'xl/workbook.xml': workbook.toXmlString(),
    'xl/_rels/workbook.xml.rels': relationships.toXmlString(),
    '[Content_Types].xml': contentTypes.toXmlString(),
    'xl/worksheets/sheet1.xml':
        '''<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="$_s">
<sheetViews><sheetView workbookViewId="0"/></sheetViews>
<sheetData>
<row r="1"><c r="A1" t="inlineStr"><is><t>Header</t></is></c><c r="B1" t="inlineStr"><is><t>Amount</t></is></c></row>
<row r="2"><c r="A2" t="inlineStr"><is><t>Travel</t></is></c><c r="B2"><v>125.5</v></c></row>
<row r="3"><c r="A3" t="inlineStr"><is><t>Equipment</t></is></c><c r="B3"><v>300</v></c></row>
</sheetData></worksheet>''',
    'xl/worksheets/sheet2.xml':
        '''<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="$_s">
<sheetViews><sheetView workbookViewId="0"/></sheetViews>
<sheetData>
<row r="1"><c r="A1" t="inlineStr"><is><t>Reference must remain</t></is></c><c r="B1"><v>73</v></c></row>
<row r="3"><c r="C3" t="inlineStr"><is><t>Do not modify</t></is></c></row>
</sheetData></worksheet>''',
  };
  final result = Archive();
  for (final entry in archive.files) {
    final replacement = replacements.remove(entry.name);
    result.addFile(
      replacement == null
          ? entry
          : ArchiveFile.bytes(entry.name, utf8.encode(replacement)),
    );
  }
  for (final entry in replacements.entries) {
    result.addFile(ArchiveFile.bytes(entry.key, utf8.encode(entry.value)));
  }
  return Uint8List.fromList(ZipEncoder().encode(result));
}

xml.XmlDocument _sheetPart(Archive archive, String name) {
  final sheet = _part(archive, 'xl/workbook.xml')
      .findAllElements('sheet', namespace: _s)
      .singleWhere((sheet) => sheet.getAttribute('name') == name);
  final id = sheet.getAttribute('id', namespace: _r);
  expect(id, isNotNull);
  final relationship = _part(archive, 'xl/_rels/workbook.xml.rels')
      .findAllElements('Relationship', namespace: _pr)
      .singleWhere((relationship) => relationship.getAttribute('Id') == id);
  expect(relationship.getAttribute('Type'), '$_r/worksheet');
  final path = Uri.parse('xl/workbook.xml')
      .resolve(relationship.getAttribute('Target')!)
      .path;
  return _part(archive, path.startsWith('/') ? path.substring(1) : path);
}

Map<String, Object> _cells(Archive archive, String name) {
  final result = <String, Object>{};
  for (final cell in _sheetPart(
    archive,
    name,
  ).findAllElements('c', namespace: _s)) {
    final raw = cell.getElement('v', namespace: _s)?.innerText;
    final Object? value = switch (cell.getAttribute('t')) {
      'inlineStr' =>
        cell
            .getElement('is', namespace: _s)!
            .findAllElements('t', namespace: _s)
            .map((text) => text.innerText)
            .join(),
      's' =>
        _part(archive, 'xl/sharedStrings.xml')
            .findAllElements('si', namespace: _s)
            .elementAt(int.parse(raw!))
            .findAllElements('t', namespace: _s)
            .map((text) => text.innerText)
            .join(),
      'str' || 'e' => raw,
      'b' => raw == '1',
      _ => raw == null || raw.isEmpty ? null : num.parse(raw),
    };
    if (value != null && value != '') result[cell.getAttribute('r')!] = value;
  }
  return result;
}

void _assertGrid(Uint8List bytes, Map<String, Object> budget) {
  final archive = _archive(bytes);
  expect(
    _cells(archive, 'Budget'),
    budget,
    reason: 'History must update the worksheet that owns the grid command.',
  );
  expect(
    _cells(archive, 'Reference'),
    _reference,
    reason: 'Navigating to Reference must never make it an undo/redo target.',
  );
}

void _assertView(
  Uint8List bytes, {
  bool rtl = false,
  int rows = 0,
  int columns = 0,
  String? topLeftCell,
}) {
  final archive = _archive(bytes);
  final views = _sheetPart(
    archive,
    'Budget',
  ).findAllElements('sheetView', namespace: _s).toList();
  expect(views.length, lessThanOrEqualTo(1));
  final view = views.isEmpty ? null : views.single;
  expect(const {'1', 'true'}.contains(view?.getAttribute('rightToLeft')), rtl);
  final panes = view?.findElements('pane', namespace: _s).toList() ?? [];
  if (rows == 0 && columns == 0) {
    expect(panes, isEmpty, reason: 'The saved worksheet must be unfrozen.');
  } else {
    expect(panes, hasLength(1));
    final pane = panes.single;
    expect(pane.getAttribute('state'), 'frozen');
    expect(num.parse(pane.getAttribute('xSplit') ?? '0'), columns);
    expect(num.parse(pane.getAttribute('ySplit') ?? '0'), rows);
    expect(pane.getAttribute('topLeftCell'), topLeftCell);
  }
  // Neither worksheet navigation nor a view edit may change cell content.
  _assertGrid(bytes, _budget);
}

void _evidence(String filename, Uint8List bytes) {
  File('$_output/$filename')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _choose(WidgetTester tester, String label) => _tap(
  tester,
  find.descendant(of: find.byType(AlertDialog), matching: find.text(label)),
);

Finder _ribbonButton(IconData icon) => find.descendant(
  of: find.byType(OfficeEditorRibbon),
  matching: find.widgetWithIcon(IconButton, icon),
);

Future<void> _history(WidgetTester tester, String action) async {
  await _tap(tester, find.text('Edit'));
  final item = find.widgetWithText(MenuItemButton, action);
  expect(tester.widget<MenuItemButton>(item).onPressed, isNotNull);
  await _tap(tester, item);
}

Future<void> _save(OfficeTestHarness host, String filename) async {
  final writes = host.cloud.writes.length;
  await _tap(host.tester, _ribbonButton(Icons.save_outlined));
  await officePumpUntil(host.tester, () => !host.ribbon.saving);
  expect(host.cloud.writes.length, writes + 1);
  expect(host.controller.isDirty, isFalse);
  _evidence(filename, host.savedBytes);
}

Future<void> _select(
  WidgetTester tester,
  SheetEditorController sheet,
  String address,
) async {
  sheet.selection.selectCell(SmlCellRef.parse(address));
  sheet.refresh();
  await tester.pump();
}

Future<void> _withHost(
  WidgetTester tester,
  Uint8List source,
  Future<void> Function(OfficeTestHarness, SheetEditorController) body,
) async {
  tester.view.physicalSize = const Size(2000, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() async {
    final host = await OfficeTestHarness.open(
      tester,
      name: 'worksheet-state.xlsx',
      initialBytes: source,
    );

    try {
      final sheet = host.controller as SheetEditorController;
      expect(sheet.isDirty, isFalse);
      expect(sheet.sheet.rightToLeft, isFalse);
      expect((sheet.sheet.freezeRows, sheet.sheet.freezeCols), (0, 0));
      await body(host, sheet);
    } finally {
      await host.dispose();
    }
  });
  expect(tester.takeException(), isNull);
}

void main() {
  late Uint8List source;
  setUpAll(() {
    source = _source();
    _assertView(source);
    _evidence('source.xlsx', source);
  });

  testWidgets(
    'clean RTL ribbon edits prompt on close and save through history',
    (tester) async {
      await _withHost(tester, source, (host, sheet) async {
        final revision = sheet.contentRevision;
        await _tap(tester, find.text('Data'));
        await _tap(tester, find.byTooltip('Right-to-left'));
        expect(
          sheet.sheet.rightToLeft,
          isTrue,
          reason: 'The real ribbon action must execute before the close check.',
        );
        final dirtyAfterEdit = sheet.isDirty;
        final revisionAfterEdit = sheet.contentRevision;
        await _tap(tester, _ribbonButton(Icons.close));
        expect(
          find.text('Unsaved changes'),
          findsOneWidget,
          reason: 'A direction-only edit must participate in clean-close protection.',
        );
        expect(dirtyAfterEdit, isTrue);
        expect(revisionAfterEdit, greaterThan(revision));
        await _choose(tester, 'Cancel');
        expect(sheet.sheet.rightToLeft, isTrue);
        await _save(host, 'rtl-enabled.xlsx');
        _assertView(host.savedBytes, rtl: true);
        await _history(tester, 'Undo');
        expect(sheet.sheet.rightToLeft, isFalse);
        expect(sheet.isDirty, isTrue);
        await _save(host, 'rtl-undo.xlsx');
        _assertView(host.savedBytes);
        await _history(tester, 'Redo');
        expect(sheet.sheet.rightToLeft, isTrue);
        await _save(host, 'rtl-redo.xlsx');
        _assertView(host.savedBytes, rtl: true);
      });
    },
  );

  testWidgets(
    'clean freeze ribbon edits prompt and persist each pane command',
    (tester) async {
      await _withHost(tester, source, (host, sheet) async {
        final revision = sheet.contentRevision;
        await _select(tester, sheet, 'C5');
        await _tap(tester, find.text('Data'));
        await _tap(tester, find.text('Freeze panes'));
        expect(
          (sheet.sheet.freezeRows, sheet.sheet.freezeCols),
          (4, 2),
          reason:
              'The actual ribbon must freeze relative to the selected cell.',
        );
        final dirtyAfterEdit = sheet.isDirty;
        final revisionAfterEdit = sheet.contentRevision;
        await _tap(tester, _ribbonButton(Icons.close));
        expect(
          find.text('Unsaved changes'),
          findsOneWidget,
          reason:
              'A freeze-only edit must participate in clean-close protection.',
        );
        expect(dirtyAfterEdit, isTrue);
        expect(revisionAfterEdit, greaterThan(revision));
        await _choose(tester, 'Cancel');
        await _save(host, 'freeze-selection.xlsx');
        _assertView(host.savedBytes, rows: 4, columns: 2, topLeftCell: 'C5');
        await _history(tester, 'Undo');
        expect((sheet.sheet.freezeRows, sheet.sheet.freezeCols), (0, 0));
        expect(sheet.isDirty, isTrue);
        await _save(host, 'freeze-undo.xlsx');
        _assertView(host.savedBytes);
        await _history(tester, 'Redo');
        expect((sheet.sheet.freezeRows, sheet.sheet.freezeCols), (4, 2));
        await _save(host, 'freeze-redo.xlsx');
        _assertView(host.savedBytes, rows: 4, columns: 2, topLeftCell: 'C5');
        await _tap(tester, find.byTooltip('Freeze top row'));
        expect((sheet.sheet.freezeRows, sheet.sheet.freezeCols), (1, 0));
        expect(sheet.isDirty, isTrue);
        await _save(host, 'freeze-top-row.xlsx');
        _assertView(host.savedBytes, rows: 1, topLeftCell: 'A2');
        await _tap(tester, find.byTooltip('Freeze first column'));
        expect((sheet.sheet.freezeRows, sheet.sheet.freezeCols), (0, 1));
        expect(sheet.isDirty, isTrue);
        await _save(host, 'freeze-first-column.xlsx');
        _assertView(host.savedBytes, columns: 1, topLeftCell: 'B1');
        await _tap(tester, find.text('Freeze panes'));
        expect((sheet.sheet.freezeRows, sheet.sheet.freezeCols), (0, 0));
        expect(sheet.isDirty, isTrue);
        await _save(host, 'freeze-cleared.xlsx');
        _assertView(host.savedBytes);
      });
    },
  );

  for (final setting in ['rtl', 'freeze']) {
    testWidgets(
      '$setting changed during close upload remains open until saved',
      (tester) async {
        await _withHost(tester, source, (host, sheet) async {
          // An ordinary committed cell edit starts the Save-and-Close operation.
          await _tap(tester, find.byTooltip('Bold'));
          expect(sheet.isDirty, isTrue);
          host.cloud.pauseNextUpload();
          await _tap(tester, _ribbonButton(Icons.close));
          await _choose(tester, 'Save');
          await officePumpUntil(tester, () => host.cloud.pendingBytes != null);
          final captured = Uint8List.fromList(host.cloud.pendingBytes!);
          _assertView(captured);
          final savingRevision = sheet.contentRevision;
          var released = false;
          try {
            await _tap(tester, find.text('Data'));
            await _tap(
              tester,
              find.byTooltip(
                setting == 'rtl' ? 'Right-to-left' : 'Freeze top row',
              ),
            );
            if (setting == 'rtl') {
              expect(sheet.sheet.rightToLeft, isTrue);
            } else {
              expect((sheet.sheet.freezeRows, sheet.sheet.freezeCols), (1, 0));
            }
            final changedRevision = sheet.contentRevision;
            host.cloud.releaseUpload();
            released = true;
            await officePumpUntil(
              tester,
              () =>
                  find.byType(OfficeEditorDialog).evaluate().isEmpty ||
                  !host.ribbon.saving,
            );
            await tester.pump(const Duration(milliseconds: 400));
            _evidence('$setting-upload-before.xlsx', host.savedBytes);
            expect(
              host.savedBytes,
              captured,
              reason:
                  'The first actual upload must be the pre-change snapshot.',
            );
            _assertView(host.savedBytes);
            expect(
              find.byType(OfficeEditorDialog),
              findsOneWidget,
              reason:
                  'A later worksheet view edit must keep Save-and-Close open.',
            );
            expect(changedRevision, greaterThan(savingRevision));
            expect(sheet.isDirty, isTrue);
            await _tap(tester, _ribbonButton(Icons.close));
            expect(find.text('Unsaved changes'), findsOneWidget);
            await _choose(tester, 'Save');
            await officePumpUntil(
              tester,
              () => find.byType(OfficeEditorDialog).evaluate().isEmpty,
            );
            expect(host.cloud.writes, [
              '/worksheet-state.xlsx',
              '/worksheet-state.xlsx',
            ]);
            _evidence('$setting-upload-after.xlsx', host.savedBytes);
            _assertView(
              host.savedBytes,
              rtl: setting == 'rtl',
              rows: setting == 'freeze' ? 1 : 0,
              topLeftCell: setting == 'freeze' ? 'A2' : null,
            );
          } finally {
            if (!released) host.cloud.releaseUpload();
          }
        });
      },
    );
  }

  testWidgets('grid undo and redo after navigation save only the owning sheet', (
    tester,
  ) async {
    await _withHost(tester, source, (host, sheet) async {
      await _select(tester, sheet, 'A2');
      await _tap(tester, find.byTooltip('Delete rows'));
      expect(sheet.sheet.cell(SmlCellRef.parse('A2')).value, 'Equipment');
      await _save(host, 'grid-delete.xlsx');
      _assertGrid(host.savedBytes, _budgetAfterDelete);
      // The host exposes no worksheet selector. Navigate through the public
      // controller, then use the actual Edit menu and Save toolbar for history.
      sheet.setActiveSheet(1);
      await tester.pump();
      expect(sheet.sheet.name, 'Reference');
      await _history(tester, 'Undo');
      expect(sheet.activeSheetIndex, 1);
      await _save(host, 'grid-undo-other-sheet.xlsx');
      _assertGrid(host.savedBytes, _budget);
      await _history(tester, 'Redo');
      expect(sheet.activeSheetIndex, 1);
      await _save(host, 'grid-redo-other-sheet.xlsx');
      _assertGrid(host.savedBytes, _budgetAfterDelete);
    });
  });
}
