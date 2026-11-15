import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:crisp_cloud/widgets/office_editor_find_bar.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:xml/xml.dart' as xml;

import '../support/office_test_harness.dart';

const _output = 'build/office-sheet-navigation-acceptance';
const _s = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pr = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _ct = 'http://schemas.openxmlformats.org/package/2006/content-types';
const _selector = Key('office-worksheet-selector');
const _rename = Key('office-worksheet-rename');
const _name = Key('office-worksheet-name');
const _submit = Key('office-worksheet-rename-submit');
const _cancel = Key('office-worksheet-rename-cancel');

xml.XmlDocument _part(Archive archive, String path) =>
    xml.XmlDocument.parse(utf8.decode(archive.findFile(path)!.content));

/// Author a two-sheet SpreadsheetML source without using the Quds serializer.
Uint8List _source() {
  final seed = File(
    'test/fixtures/office_native_workflows/native-sheet-source.xlsx',
  ).readAsBytesSync();
  expect(
    sha256.convert(seed).toString(),
    '548cf28efce66d0b4e3b9abb5a4f7f24f282ecadd7749cd65a5afa6ed0b5ba49',
  );
  final archive = ZipDecoder().decodeBytes(seed);
  final workbook = _part(archive, 'xl/workbook.xml');
  workbook.rootElement
      .getElement('sheets', namespace: _s)!
      .children
      .add(
        xml.XmlDocument.parse(
          '<sheet xmlns="$_s" xmlns:r="$_r" '
          'name="Reference" sheetId="2" r:id="rId4"/>',
        ).rootElement.copy(),
      );
  final oldNames = workbook.rootElement.getElement(
    'definedNames',
    namespace: _s,
  );
  if (oldNames != null) workbook.rootElement.children.remove(oldNames);
  final names = xml.XmlDocument.parse(
    '<definedNames xmlns="$_s">'
    '<definedName name="BudgetAmount">Budget!\$B\$2</definedName>'
    '</definedNames>',
  ).rootElement.copy();
  final sheets = workbook.rootElement.getElement('sheets', namespace: _s)!;
  workbook.rootElement.children.insert(
    workbook.rootElement.children.indexOf(sheets) + 1,
    names,
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
      '<Override xmlns="$_ct" '
      'PartName="/xl/worksheets/sheet2.xml" '
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
<worksheet xmlns="$_s"><sheetViews><sheetView workbookViewId="0"/></sheetViews>
<sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Budget header</t></is></c></row>
<row r="2"><c r="A2" t="inlineStr"><is><t>Travel</t></is></c><c r="B2"><v>125.5</v></c></row></sheetData>
<dataValidations count="1"><dataValidation type="decimal" operator="between" allowBlank="0" showErrorMessage="1" error="Enter an amount from 0 to 1000." sqref="B2"><formula1>0</formula1><formula2>1000</formula2></dataValidation></dataValidations>
</worksheet>''',
    'xl/worksheets/sheet2.xml':
        '''<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="$_s"><sheetViews><sheetView workbookViewId="0"/></sheetViews>
<sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Reference must remain</t></is></c><c r="B1"><v>73</v></c></row>
<row r="2"><c r="B2"><f>Budget!B2</f><v>125.5</v></c></row></sheetData></worksheet>''',
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
  final relationship = _part(archive, 'xl/_rels/workbook.xml.rels')
      .findAllElements('Relationship', namespace: _pr)
      .singleWhere(
        (rel) =>
            rel.getAttribute('Id') == sheet.getAttribute('id', namespace: _r),
      );
  final path = Uri.parse('xl/workbook.xml')
      .resolve(relationship.getAttribute('Target')!)
      .path;
  return _part(archive, path.startsWith('/') ? path.substring(1) : path);
}

void _assertSaved(
  Uint8List bytes, {
  String name = 'Budget',
  num amount = 125.5,
}) {
  final archive = ZipDecoder().decodeBytes(bytes);
  expect(
    archive.files.map((file) => file.name).toSet(),
    hasLength(archive.files.length),
  );
  final book = _part(archive, 'xl/workbook.xml');
  expect(
    book
        .findAllElements('sheet', namespace: _s)
        .map((sheet) => sheet.getAttribute('name')),
    [name, 'Reference'],
  );
  final budget = _sheetPart(archive, name);
  final reference = _sheetPart(archive, 'Reference');
  xml.XmlElement cell(xml.XmlDocument sheet, String address) => sheet
      .findAllElements('c', namespace: _s)
      .singleWhere((cell) => cell.getAttribute('r') == address);
  expect(
    num.parse(cell(budget, 'B2').getElement('v', namespace: _s)!.innerText),
    amount,
  );
  expect(
    num.parse(cell(reference, 'B1').getElement('v', namespace: _s)!.innerText),
    73,
  );
  final qualifier = name == 'Budget'
      ? 'Budget'
      : "'${name.replaceAll("'", "''")}'";
  expect(
    cell(reference, 'B2').getElement('f', namespace: _s)!.innerText,
    '$qualifier!B2',
  );
  expect(
    book
        .findAllElements('definedName', namespace: _s)
        .singleWhere((name) => name.getAttribute('name') == 'BudgetAmount')
        .innerText,
    '$qualifier!\$B\$2',
  );
  final opened = SheetDeserializer().readBytes(bytes);
  expect(opened.firstSheet.cellA1('A1').value, 'Budget header');
  expect(opened.firstSheet.cellA1('A2').value, 'Travel');
  expect(opened.sheets[1].cellA1('A1').value, 'Reference must remain');
  expect(opened.firstSheet.validations, hasLength(1));
}

void _evidence(String filename, Uint8List bytes) => File('$_output/$filename')
  ..createSync(recursive: true)
  ..writeAsBytesSync(bytes);

/// Optional preview of the actual host widget, separate from XLSX acceptance.
Future<void> _preview(WidgetTester tester, String filename) async {
  if (Platform.environment['OFFICE_NAVIGATION_PREVIEW'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final image = await boundary.toImage();
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    File('build/office-sheet-navigation-preview/$filename')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _switch(WidgetTester tester, String name) async {
  await _tap(tester, find.byKey(_selector));
  await _tap(tester, find.text(name).last);
}

void _type(SheetEditorController sheet, String value) {
  sheet.cellEditor.bridge.updateEditingValue(
    TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    ),
  );
}

void _draft(SheetEditorController sheet, String value) {
  sheet.selection.selectCell(SmlCellRef.parse('B2'));
  sheet.beginCellEdit();
  _type(sheet, value);
}

Future<void> _save(OfficeTestHarness host, String filename) async {
  final writes = host.cloud.writes.length;
  await _tap(
    host.tester,
    find.descendant(
      of: find.byType(OfficeEditorRibbon),
      matching: find.widgetWithIcon(IconButton, Icons.save_outlined),
    ),
  );
  await officePumpUntil(host.tester, () => !host.ribbon.saving);
  expect(host.cloud.writes.length, writes + 1);
  expect(host.controller.isDirty, isFalse);
  _evidence(filename, host.savedBytes);
}

Future<void> _history(WidgetTester tester, String action) async {
  await _tap(tester, find.text('Edit'));
  await _tap(tester, find.widgetWithText(MenuItemButton, action));
}

Future<void> _withHost(
  WidgetTester tester,
  Uint8List source,
  Future<void> Function(OfficeTestHarness, SheetEditorController) body, {
  Locale locale = const Locale('en'),
  double width = 1600,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() async {
    final host = await OfficeTestHarness.open(
      tester,
      name: 'worksheet-navigation.xlsx',
      initialBytes: source,
      locale: locale,
    );
    try {
      expect(find.byKey(_selector), findsOneWidget);
      await body(host, host.controller as SheetEditorController);
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
    _assertSaved(source);
    _evidence('source.xlsx', source);
  });

  testWidgets(
    'worksheet selector commits a valid draft to its original sheet before saving',
    (tester) async {
      await _withHost(tester, source, (host, sheet) async {
        _draft(sheet, '250');
        await _switch(tester, 'Reference');
        expect(sheet.activeSheetIndex, 1);
        expect(sheet.cellEditor.editing, isFalse);
        expect(sheet.workbook.firstSheet.cellA1('B2').value, 250);
        await _save(host, 'switched-draft.xlsx');
        _assertSaved(host.savedBytes, amount: 250);
      });
    },
  );

  testWidgets(
    'worksheet selector retains a rejected draft until corrected and saved',
    (tester) async {
      await _withHost(tester, source, (host, sheet) async {
        _draft(sheet, '9999');
        await _switch(tester, 'Reference');
        expect(sheet.activeSheetIndex, 0);
        expect(sheet.cellEditor.editing, isTrue);
        expect(sheet.cellEditor.formulaBar, '9999');
        expect(
          find.text('Correct the current cell before continuing.'),
          findsOneWidget,
        );
        expect(sheet.workbook.firstSheet.cellA1('B2').value, 125.5);
        _type(sheet, '300');
        await _save(host, 'rejected-draft-corrected.xlsx');
        _assertSaved(host.savedBytes, amount: 300);
        expect(
          find.text('Correct the current cell before continuing.'),
          findsNothing,
        );
        await _switch(tester, 'Reference');
        expect(sheet.activeSheetIndex, 1);
      });
    },
  );

  testWidgets(
    'rename dialog saves rewritten references through undo and redo on another sheet',
    (tester) async {
      await _withHost(tester, source, (host, sheet) async {
        await _tap(tester, find.byKey(_rename));
        await tester.enterText(find.byKey(_name), "O'Brien 2026");
        await _tap(tester, find.byKey(_submit));
        expect(sheet.sheet.name, "O'Brien 2026");
        await _save(host, 'rename.xlsx');
        _assertSaved(host.savedBytes, name: "O'Brien 2026");
        await _switch(tester, 'Reference');
        await _history(tester, 'Undo');
        expect(sheet.activeSheetIndex, 1);
        await _save(host, 'rename-undo.xlsx');
        _assertSaved(host.savedBytes);
        await _history(tester, 'Redo');
        expect(sheet.activeSheetIndex, 1);
        await _save(host, 'rename-redo.xlsx');
        _assertSaved(host.savedBytes, name: "O'Brien 2026");
      });
    },
  );

  testWidgets('invalid rename stays open and retains the name for correction', (
    tester,
  ) async {
    await _withHost(tester, source, (host, sheet) async {
      final revision = sheet.contentRevision;
      await _tap(tester, find.byKey(_rename));
      for (final invalid in ['Reference', 'a/b', '', "'invalid"]) {
        await tester.enterText(find.byKey(_name), invalid);
        await _tap(tester, find.byKey(_submit));
        expect(find.byKey(_name), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byKey(_name)).controller!.text,
          invalid,
        );
        expect(
          find.text(
            'Use a unique worksheet name of 1–31 characters without : \\ / ? * [ ] or an apostrophe at either end.',
          ),
          findsOneWidget,
        );
        expect(sheet.contentRevision, revision);
        expect(sheet.sheet.name, 'Budget');
        if (invalid == 'Reference') {
          await _preview(tester, 'rename-validation.png');
        }
      }
      await tester.enterText(find.byKey(_name), 'Travel 2026');
      await _tap(tester, find.byKey(_submit));
      expect(find.byKey(_name), findsNothing);
      expect(sheet.sheet.name, 'Travel 2026');
    });
  });

  testWidgets('cancelled rename preserves the cell draft and history', (
    tester,
  ) async {
    await _withHost(tester, source, (host, sheet) async {
      _draft(sheet, '500');
      final revision = sheet.contentRevision;
      await _tap(tester, find.byKey(_rename));
      await tester.enterText(find.byKey(_name), 'Changed');
      await _tap(tester, find.byKey(_cancel));
      expect(sheet.sheet.name, 'Budget');
      expect(sheet.cellEditor.editing, isTrue);
      expect(sheet.cellEditor.formulaBar, '500');
      expect(sheet.contentRevision, revision);
      expect(sheet.commands.canUndo, isFalse);
    });
  });

  testWidgets('rename dialog remains bound to the worksheet that opened it', (
    tester,
  ) async {
    await _withHost(tester, source, (host, sheet) async {
      await _tap(tester, find.byKey(_rename));
      sheet.setActiveSheet(1);
      await tester.pump();
      await tester.enterText(find.byKey(_name), 'Original owner');
      await _tap(tester, find.byKey(_submit));
      expect(sheet.workbook.firstSheet.name, 'Original owner');
      expect(sheet.sheet.name, 'Reference');
      expect(sheet.activeSheetIndex, 1);
    });
  });

  for (final mode in [
    OfficeInteractionMode.viewing,
    OfficeInteractionMode.selecting,
  ]) {
    testWidgets(
      '${mode.name} mode permits worksheet navigation and disables rename',
      (tester) async {
        await _withHost(tester, source, (host, sheet) async {
          host.ribbon.onConfigChanged(host.ribbon.config.copyWith(mode: mode));
          await tester.pump();
          final revision = sheet.contentRevision;
          expect(
            tester.widget<IconButton>(find.byKey(_rename)).onPressed,
            isNull,
          );
          await _switch(tester, 'Reference');
          expect(sheet.activeSheetIndex, 1);
          expect(sheet.isDirty, isFalse);
          expect(sheet.contentRevision, revision);
          expect(sheet.canUndo, isFalse);
        });
      },
    );
  }

  testWidgets(
    'selecting the current worksheet preserves selection and an uncommitted draft',
    (tester) async {
      await _withHost(tester, source, (host, sheet) async {
        _draft(sheet, '600');
        final revision = sheet.contentRevision;
        await _switch(tester, 'Budget');
        expect(sheet.activeCell.a1, 'B2');
        expect(sheet.cellEditor.editing, isTrue);
        expect(sheet.cellEditor.formulaBar, '600');
        expect(sheet.contentRevision, revision);
        expect(sheet.commands.canUndo, isFalse);
      });
    },
  );

  testWidgets('worksheet selector works from the keyboard', (tester) async {
    await _withHost(tester, source, (host, sheet) async {
      final dropdown = tester.widget<DropdownButton<int>>(
        find.byKey(_selector),
      );
      dropdown.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 350));
      expect(sheet.activeSheetIndex, 1);
      expect(sheet.isDirty, isFalse);
    });
  });

  testWidgets(
    'narrow Arabic host keeps worksheet chrome RTL and names unchanged',
    (tester) async {
      await _withHost(
        tester,
        source,
        (host, sheet) async {
          final element = tester.element(find.byKey(_selector));
          expect(Directionality.of(element), TextDirection.rtl);
          expect(find.byTooltip('ورقة العمل'), findsOneWidget);
          expect(find.byTooltip('إعادة تسمية ورقة العمل'), findsOneWidget);
          await _preview(tester, 'worksheet-arabic-narrow.png');
          await _switch(tester, 'Reference');
          expect(sheet.sheet.name, 'Reference');
          expect(tester.takeException(), isNull);
        },
        locale: const Locale('ar'),
        width: 390,
      );
    },
  );

  testWidgets(
    'find navigation shows a recoverable error without dropping a rejected cell draft',
    (tester) async {
      await _withHost(tester, source, (host, sheet) async {
        _draft(sheet, '9999');
        sheet.requestFind();
        await tester.pump();
        final query = find
            .descendant(
              of: find.byType(OfficeFindBar),
              matching: find.byType(TextField),
            )
            .first;
        await tester.enterText(query, 'Reference must remain');
        await tester.pump();
        expect(sheet.activeSheetIndex, 0);
        expect(sheet.activeCell.a1, 'B2');
        expect(sheet.cellEditor.editing, isTrue);
        expect(sheet.cellEditor.formulaBar, '9999');
        expect(
          find.text('Correct the current cell before continuing.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    },
  );
}
