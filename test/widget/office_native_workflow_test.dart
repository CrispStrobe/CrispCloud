import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:xml/xml.dart' as xml;

import '../support/office_test_harness.dart';

const _fixtures = 'test/fixtures/office_native_workflows';
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _s = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';

class _NativeCase {
  _NativeCase(this.record);

  final Map<String, Object?> record;
  String get id => record['id']! as String;
  String get extension => record['format']! as String;
  Map<String, Object?> get expected =>
      (record['expected_semantics']! as Map<String, Object?>);

  Uint8List load(String role) {
    final bytes = File('$_fixtures/${record[role]}').readAsBytesSync();
    verify(role, bytes);
    return bytes;
  }

  void verify(String role, Uint8List bytes) {
    if (sha256.convert(bytes).toString() != record['${role}_sha256']) {
      throw FormatException('Independent $id $role fixture hash mismatch');
    }
  }

  void emitReference() {
    final bytes = load('expected');
    _assertOutput(bytes, this);
    File('build/fidelity-host/reference/${record['expected']}')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }
}

List<_NativeCase> _cases() {
  final manifest = jsonDecode(
    File('$_fixtures/manifest.json').readAsStringSync(),
  ) as Map<String, Object?>;
  if (manifest['version'] != 1) {
    throw const FormatException(
      'Unsupported independent Office fixture manifest',
    );
  }
  return [
    for (final entry in manifest['cases']! as List<Object?>)
      _NativeCase(entry! as Map<String, Object?>),
  ];
}

Archive _archive(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  expect(
    archive.files.map((file) => file.name).toSet(),
    hasLength(archive.files.length),
    reason: 'Duplicate package entries cannot establish independent evidence.',
  );
  return archive;
}

xml.XmlDocument _part(Archive archive, String path) {
  final file = archive.findFile(path);
  expect(file, isNotNull, reason: 'Missing native part $path');
  return xml.XmlDocument.parse(utf8.decode(file!.content));
}

bool _on(String? value) =>
    value == null || const {'1', 'true', 'on'}.contains(value.toLowerCase());

String _wordText(xml.XmlElement paragraph) => paragraph.descendants
    .whereType<xml.XmlElement>()
    .where((element) => element.name.namespaceUri == _w)
    .map(
      (element) => switch (element.name.local) {
        't' => element.innerText,
        'tab' => '\t',
        'br' => '\n',
        _ => '',
      },
    )
    .join();

void _assertWord(Archive archive, Map<String, Object?> expected) {
  final document = _part(archive, 'word/document.xml');
  final body = document.rootElement.getElement('body', namespace: _w)!;
  final paragraphs = body.findElements('p', namespace: _w).toList();
  expect(paragraphs.map(_wordText), expected['paragraphs']);
  final props = paragraphs.first.getElement('pPr', namespace: _w)!;
  expect(
    int.parse(
      props
          .getElement('ind', namespace: _w)!
          .getAttribute('left', namespace: _w)!,
    ),
    expected['first_paragraph_left_twips'],
  );
  expect(
    int.parse(
      props
          .getElement('spacing', namespace: _w)!
          .getAttribute('after', namespace: _w)!,
    ),
    expected['first_paragraph_after_twips'],
  );
  final runs = paragraphs.first
      .findElements('r', namespace: _w)
      .where((run) => run.findElements('t', namespace: _w).isNotEmpty);
  expect(runs, isNotEmpty);
  for (final run in runs) {
    final bold = run
        .getElement('rPr', namespace: _w)
        ?.getElement('b', namespace: _w);
    expect(bold, isNotNull);
    expect(
      _on(bold!.getAttribute('val', namespace: _w)),
      expected['first_paragraph_bold'],
    );
  }
  expect(
    paragraphs.last
        .findAllElements('b', namespace: _w)
        .where((bold) => _on(bold.getAttribute('val', namespace: _w))),
    isEmpty,
    reason:
        'Formatting the title must leave the reference paragraph unchanged.',
  );
}

xml.XmlElement _cell(xml.XmlDocument sheet, String address) => sheet
    .findAllElements('c', namespace: _s)
    .singleWhere((cell) => cell.getAttribute('r') == address);

Object? _cellValue(Archive archive, xml.XmlElement cell) {
  final value = cell.getElement('v', namespace: _s)?.innerText;
  return switch (cell.getAttribute('t')) {
    'inlineStr' =>
      cell
          .getElement('is', namespace: _s)!
          .findAllElements('t', namespace: _s)
          .map((part) => part.innerText)
          .join(),
    's' =>
      _part(archive, 'xl/sharedStrings.xml')
          .findAllElements('si', namespace: _s)
          .elementAt(int.parse(value!))
          .findAllElements('t', namespace: _s)
          .map((part) => part.innerText)
          .join(),
    'str' || 'e' => value,
    'b' => value == '1',
    _ => value == null || value.isEmpty ? null : num.parse(value),
  };
}

void _assertSheet(Archive archive, Map<String, Object?> expected) {
  final sheet = _part(archive, 'xl/worksheets/sheet1.xml');
  final styles = _part(archive, 'xl/styles.xml');
  expect(styles.rootElement.name.namespaceUri, _s);
  for (final address in ['A2', 'B2', 'B3']) {
    expect(_cellValue(archive, _cell(sheet, address)), expected[address]);
  }
  expect(_cellValue(archive, _cell(sheet, 'A1')), 'Native budget');
  expect(_cellValue(archive, _cell(sheet, 'B1')), 'Amount');
  expect(_cellValue(archive, _cell(sheet, 'A3')), 'Equipment');
  expect(_cellValue(archive, _cell(sheet, 'A5')), 'Approved for review');
  final formula = _cell(sheet, 'B4');
  expect(
    formula.getElement('f', namespace: _s)!.innerText,
    expected['B4_formula'],
  );
  expect(_cellValue(archive, formula), expected['B4_cache']);
  expect(
    sheet
        .findAllElements('mergeCell', namespace: _s)
        .map((merge) => merge.getAttribute('ref')),
    [expected['merge']],
  );
  final xfs = styles.rootElement
      .getElement('cellXfs', namespace: _s)!
      .findElements('xf', namespace: _s)
      .toList();
  final fonts = styles.rootElement
      .getElement('fonts', namespace: _s)!
      .findElements('font', namespace: _s)
      .toList();
  xml.XmlElement styleOf(String address) =>
      xfs[int.parse(_cell(sheet, address).getAttribute('s') ?? '0')];
  final edited = styleOf('A2');
  final font = fonts[int.parse(edited.getAttribute('fontId') ?? '0')];
  for (final (property, key) in [('b', 'A2_bold'), ('i', 'A2_italic')]) {
    final element = font.getElement(property, namespace: _s);
    expect(
      element,
      isNotNull,
      reason: 'Missing SpreadsheetML font property $property',
    );
    expect(_on(element!.getAttribute('val')), expected[key]);
  }
  expect(
    font.getElement('name', namespace: _s)!.getAttribute('val'),
    'Liberation Sans',
  );
  expect(
    font.getElement('color', namespace: _s)!.getAttribute('rgb')!.substring(2),
    '234567',
  );
  final alignment = edited.getElement('alignment', namespace: _s)!;
  expect(alignment.getAttribute('horizontal'), expected['A2_horizontal']);
  expect(alignment.getAttribute('vertical'), expected['A2_vertical']);
  expect(alignment.getAttribute('wrapText'), isIn(['1', 'true', 'on']));
  final footer = styleOf('A5').getElement('alignment', namespace: _s)!;
  expect(footer.getAttribute('horizontal'), expected['A5_horizontal']);
  expect(footer.getAttribute('vertical'), expected['A5_vertical']);
}

String _drawingText(xml.XmlElement body) => body
    .findElements('p', namespace: _a)
    .map(
      (paragraph) => paragraph
          .findAllElements('t', namespace: _a)
          .map((text) => text.innerText)
          .join(),
    )
    .join('\n');

void _assertSlide(Archive archive, Map<String, Object?> expected) {
  final slide = _part(archive, 'ppt/slides/slide1.xml');
  final texts = slide
      .findAllElements('sp', namespace: _p)
      .map((shape) => shape.getElement('txBody', namespace: _p))
      .whereType<xml.XmlElement>()
      .map(_drawingText);
  expect(texts, expected['texts']);
  final notes = _part(archive, 'ppt/notesSlides/notesSlide1.xml');
  final bodyShapes = notes
      .findAllElements('sp', namespace: _p)
      .where(
        (shape) => shape
            .findAllElements('ph', namespace: _p)
            .any((placeholder) => placeholder.getAttribute('type') == 'body'),
      );
  expect(bodyShapes, hasLength(1));
  expect(
    _drawingText(bodyShapes.single.getElement('txBody', namespace: _p)!),
    expected['notes'],
    reason: 'Speaker notes must match in full, including line boundaries.',
  );
}

void _assertOutput(Uint8List bytes, _NativeCase scenario) {
  final archive = _archive(bytes);
  switch (scenario.extension) {
    case 'docx':
      _assertWord(archive, scenario.expected);
    case 'xlsx':
      _assertSheet(archive, scenario.expected);
    case 'pptx':
      _assertSlide(archive, scenario.expected);
    default:
      throw StateError('Unexpected native fixture format');
  }
}

(Uint8List, Map<String, String>) _nativeFillSource() {
  // The container is independently authored with openpyxl. Replace its sheet
  // and styles with authored XML; neither input nor expectations use Quds.
  final container = _archive(
    _cases()
        .singleWhere((scenario) => scenario.id == 'native-sheet')
        .load('source'),
  );
  final nativeStyles = File(
    'packages/quds_office_engine/test/fixtures/fidelity/sheet-fill-native.xml',
  ).readAsStringSync();
  final fills = xml.XmlDocument.parse(nativeStyles).rootElement
      .getElement('fills', namespace: _s)!
      .findElements('fill', namespace: _s)
      .toList();
  final expected = {'A1': fills[5].toXmlString(), 'B1': fills[4].toXmlString()};
  final replacements = {
    'xl/styles.xml': nativeStyles,
    'xl/worksheets/sheet1.xml':
        '''<?xml version="1.0" encoding="UTF-8"?>
<s:worksheet xmlns:s="$_s"><s:sheetData><s:row r="1">
<s:c r="A1" s="2" t="inlineStr"><s:is><s:t>Native gradient</s:t></s:is></s:c>
<s:c r="B1" s="1" t="inlineStr"><s:is><s:t>Native pattern</s:t></s:is></s:c>
</s:row></s:sheetData></s:worksheet>''',
  };
  final archive = Archive();
  for (final file in container.files) {
    final replacement = replacements[file.name];
    archive.addFile(
      replacement == null
          ? file
          : ArchiveFile.bytes(file.name, utf8.encode(replacement)),
    );
  }
  return (Uint8List.fromList(ZipEncoder().encode(archive)), expected);
}

void _assertNativeFills(
  Uint8List bytes,
  Map<String, String> expected, {
  required bool edited,
}) {
  final archive = _archive(bytes);
  final sheet = _part(archive, 'xl/worksheets/sheet1.xml');
  final styles = _part(archive, 'xl/styles.xml').rootElement;
  final xfs = styles
      .getElement('cellXfs', namespace: _s)!
      .findElements('xf', namespace: _s)
      .toList();
  final fills = styles
      .getElement('fills', namespace: _s)!
      .findElements('fill', namespace: _s)
      .toList();
  xml.XmlElement styleOf(String address) =>
      xfs[int.parse(_cell(sheet, address).getAttribute('s') ?? '0')];
  for (final entry in expected.entries) {
    final fillId = int.parse(styleOf(entry.key).getAttribute('fillId')!);
    expect(
      fills[fillId].toXmlString(),
      entry.value,
      reason:
          '${entry.key} must retain the exact independently authored fill, '
          'including native pattern colors and gradient stops.',
    );
  }
  expect(_cellValue(archive, _cell(sheet, 'A1')), 'Native gradient');
  expect(_cellValue(archive, _cell(sheet, 'B1')), 'Native pattern');
  final font = styles
      .getElement('fonts', namespace: _s)!
      .findElements('font', namespace: _s)
      .elementAt(int.parse(styleOf('A1').getAttribute('fontId')!));
  final bold = font.getElement('b', namespace: _s);
  expect(bold != null && _on(bold.getAttribute('val')), edited);
  expect(
    styleOf('B1')
        .getElement('alignment', namespace: _s)
        ?.getAttribute('horizontal'),
    edited ? 'center' : null,
  );
}

typedef _StyleHistoryFixture = ({
  Uint8List bytes,
  Map<String, Map<String, String>> fills,
});

const _styleHistoryOutput = 'build/office-style-history-acceptance';
const _styleHistoryCells = <String, Map<String, String>>{
  'Budget': {
    'A1': 'Native gradient',
    'B1': 'Native pattern',
    'C1': 'Explicit style zero',
    'D1': 'Implicit style zero',
  },
  'Reference': {
    'A1': 'Reference indexed',
    'B1': 'Reference black',
    'C1': 'Reference gray',
    'D1': 'Reference implicit',
  },
};

_StyleHistoryFixture _nativeStyleHistorySource() {
  const r =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  const pr = 'http://schemas.openxmlformats.org/package/2006/relationships';
  const ct = 'http://schemas.openxmlformats.org/package/2006/content-types';
  final (nativeSource, _) = _nativeFillSource();
  final archive = _archive(nativeSource);
  final styles = _part(archive, 'xl/styles.xml');
  final font = styles.rootElement
      .getElement('fonts', namespace: _s)!
      .findElements('font', namespace: _s)
      .single;
  // Keep the authored native fills, and add a native theme/tint font color.
  // Expectations below concern this authored metadata, never a Quds export.
  final color = font.getElement('color', namespace: _s)!;
  color.attributes.clear();
  color.setAttribute('theme', '4');
  color.setAttribute('tint', '0.25');
  final nativeFills = styles.rootElement
      .getElement('fills', namespace: _s)!
      .findElements('fill', namespace: _s)
      .toList();
  final expectedFills = <String, Map<String, String>>{
    'Budget': {
      'A1': nativeFills[5].toXmlString(),
      'B1': nativeFills[4].toXmlString(),
      'C1': nativeFills[3].toXmlString(),
      'D1': nativeFills[3].toXmlString(),
    },
    'Reference': {
      'A1': nativeFills[6].toXmlString(),
      'B1': nativeFills[2].toXmlString(),
      'C1': nativeFills[1].toXmlString(),
      'D1': nativeFills[3].toXmlString(),
    },
  };
  final workbook = _part(archive, 'xl/workbook.xml');
  final sheets = workbook.rootElement.getElement('sheets', namespace: _s)!;
  expect(sheets.findElements('sheet', namespace: _s), hasLength(1));
  sheets.children.add(
    xml.XmlDocument.parse(
      '<sheet xmlns="$_s" xmlns:r="$r" name="Reference" '
      'sheetId="2" r:id="rId4"/>',
    ).rootElement.copy(),
  );
  final relationships = _part(archive, 'xl/_rels/workbook.xml.rels');
  relationships.rootElement.children.add(
    xml.XmlDocument.parse(
      '<Relationship xmlns="$pr" Id="rId4" Type="$r/worksheet" '
      'Target="worksheets/sheet2.xml"/>',
    ).rootElement.copy(),
  );
  final contentTypes = _part(archive, '[Content_Types].xml');
  contentTypes.rootElement.children.add(
    xml.XmlDocument.parse(
      '<Override xmlns="$ct" PartName="/xl/worksheets/sheet2.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.'
      'spreadsheetml.worksheet+xml"/>',
    ).rootElement.copy(),
  );
  final replacements = <String, String>{
    'xl/styles.xml': styles.toXmlString(),
    'xl/workbook.xml': workbook.toXmlString(),
    'xl/_rels/workbook.xml.rels': relationships.toXmlString(),
    '[Content_Types].xml': contentTypes.toXmlString(),
    'xl/worksheets/sheet1.xml':
        '''<?xml version="1.0" encoding="UTF-8"?>
<s:worksheet xmlns:s="$_s"><s:sheetData><s:row r="1">
<s:c r="A1" s="2" t="inlineStr"><s:is><s:t>Native gradient</s:t></s:is></s:c>
<s:c r="B1" s="1" t="inlineStr"><s:is><s:t>Native pattern</s:t></s:is></s:c>
<s:c r="C1" s="0" t="inlineStr"><s:is><s:t>Explicit style zero</s:t></s:is></s:c>
<s:c r="D1" t="inlineStr"><s:is><s:t>Implicit style zero</s:t></s:is></s:c>
</s:row></s:sheetData></s:worksheet>''',
    'xl/worksheets/sheet2.xml':
        '''<?xml version="1.0" encoding="UTF-8"?>
<s:worksheet xmlns:s="$_s"><s:sheetData><s:row r="1">
<s:c r="A1" s="3" t="inlineStr"><s:is><s:t>Reference indexed</s:t></s:is></s:c>
<s:c r="B1" s="4" t="inlineStr"><s:is><s:t>Reference black</s:t></s:is></s:c>
<s:c r="C1" s="5" t="inlineStr"><s:is><s:t>Reference gray</s:t></s:is></s:c>
<s:c r="D1" t="inlineStr"><s:is><s:t>Reference implicit</s:t></s:is></s:c>
</s:row></s:sheetData></s:worksheet>''',
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
  return (
    bytes: Uint8List.fromList(ZipEncoder().encode(result)),
    fills: expectedFills,
  );
}

xml.XmlDocument _styleHistorySheet(Archive archive, String name) {
  const r =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  const pr = 'http://schemas.openxmlformats.org/package/2006/relationships';
  final sheet = _part(archive, 'xl/workbook.xml')
      .findAllElements('sheet', namespace: _s)
      .singleWhere((sheet) => sheet.getAttribute('name') == name);
  final id = sheet.getAttribute('id', namespace: r);
  final relationship = _part(archive, 'xl/_rels/workbook.xml.rels')
      .findAllElements('Relationship', namespace: pr)
      .singleWhere((relationship) => relationship.getAttribute('Id') == id);
  expect(relationship.getAttribute('Type'), '$r/worksheet');
  final path = Uri.parse('xl/workbook.xml')
      .resolve(relationship.getAttribute('Target')!)
      .path;
  return _part(archive, path.startsWith('/') ? path.substring(1) : path);
}

void _assertNativeStyleHistory(
  Uint8List bytes,
  _StyleHistoryFixture fixture, {
  required bool budgetBold,
}) {
  final archive = _archive(bytes);
  final styles = _part(archive, 'xl/styles.xml').rootElement;
  final xfs = styles
      .getElement('cellXfs', namespace: _s)!
      .findElements('xf', namespace: _s)
      .toList();
  final fills = styles
      .getElement('fills', namespace: _s)!
      .findElements('fill', namespace: _s)
      .toList();
  final fonts = styles
      .getElement('fonts', namespace: _s)!
      .findElements('font', namespace: _s)
      .toList();
  for (final name in ['Budget', 'Reference']) {
    final sheet = _styleHistorySheet(archive, name);
    final values = <String, Object>{};
    for (final cell in sheet.findAllElements('c', namespace: _s)) {
      final value = _cellValue(archive, cell);
      if (value != null && value != '') values[cell.getAttribute('r')!] = value;
    }
    expect(
      values,
      _styleHistoryCells[name],
      reason: 'Styling must leave every worksheet cell value unchanged.',
    );
    for (final entry in fixture.fills[name]!.entries) {
      final cell = _cell(sheet, entry.key);
      final style = xfs[int.parse(cell.getAttribute('s') ?? '0')];
      final font = fonts[int.parse(style.getAttribute('fontId')!)];
      final bold = font.getElement('b', namespace: _s);
      expect(
        bold != null && _on(bold.getAttribute('val')),
        name == 'Budget' && budgetBold,
        reason: '$name!${entry.key} must reflect only its own style command.',
      );
      expect(
        fills[int.parse(style.getAttribute('fillId')!)].toXmlString(),
        entry.value,
        reason:
            '$name!${entry.key} lost an independently authored native fill.',
      );
      final color = font.getElement('color', namespace: _s)!;
      expect(
        color.getAttribute('theme'),
        '4',
        reason: '$name!${entry.key} must retain the native font theme.',
      );
      expect(color.getAttribute('tint'), '0.25');
      expect(color.getAttribute('rgb'), isNull);
      expect(color.getAttribute('indexed'), isNull);
      expect(font.getElement('sz', namespace: _s)!.getAttribute('val'), '11');
      expect(
        font.getElement('name', namespace: _s)!.getAttribute('val'),
        'Calibri',
      );
    }
    if (name == 'Budget' && !budgetBold) {
      expect(
        _cell(sheet, 'C1').getAttribute('s'),
        '0',
        reason: 'Undo must retain an explicitly authored style-zero cell.',
      );
      expect(
        _cell(sheet, 'D1').getAttribute('s'),
        isNull,
        reason: 'Undo must retain an implicitly styled cell.',
      );
    }
    if (name == 'Reference') {
      for (final entry in {
        'A1': '3',
        'B1': '4',
        'C1': '5',
        'D1': null,
      }.entries) {
        expect(
          _cell(sheet, entry.key).getAttribute('s'),
          entry.value,
          reason: 'Navigation must not change Reference style provenance.',
        );
      }
    }
  }
}

void _assertStyleProvenance(SheetEditorController sheet) {
  final budget = sheet.workbook.sheets[0];
  for (final address in ['A1', 'B1', 'C1', 'D1']) {
    final cell = budget.cell(SmlCellRef.parse(address));
    expect(
      (cell.hasExplicitFillColorEdit, cell.hasExplicitFontColorEdit),
      (false, false),
      reason: 'Unrelated formatting must not invent explicit color edits.',
    );
    expect(cell.hasExplicitStyleIndex, address != 'D1');
  }
}

void _styleHistoryEvidence(String name, Uint8List bytes) {
  File('$_styleHistoryOutput/$name')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

Future<void> _styleHistorySave(OfficeTestHarness host, String name) async {
  final previous = host.cloud.writes.length;
  final save = find.descendant(
    of: find.byType(OfficeEditorRibbon),
    matching: find.widgetWithIcon(IconButton, Icons.save_outlined),
  );
  expect(save, findsOneWidget);
  await _tap(host.tester, save);
  await officePumpUntil(host.tester, () => !host.ribbon.saving);
  expect(host.cloud.writes.length, previous + 1);
  expect(host.controller.isDirty, isFalse);
  _styleHistoryEvidence(name, host.savedBytes);
}

Future<void> _styleHistoryAction(WidgetTester tester, String action) async {
  await _tap(tester, find.text('Edit'));
  final item = find.widgetWithText(MenuItemButton, action);
  expect(tester.widget<MenuItemButton>(item).onPressed, isNotNull);
  await _tap(tester, item);
}

Future<void> _styleHistoryBold(
  WidgetTester tester,
  SheetEditorController sheet,
) async {
  sheet.selection.selectCell(SmlCellRef.parse('A1'));
  sheet.selection.extendTo(SmlCellRef.parse('D1'));
  sheet.refresh();
  await tester.pump();
  await _tap(tester, find.byTooltip('Bold'));
  for (final address in ['A1', 'B1', 'C1', 'D1']) {
    expect(
      sheet.sheet.cell(SmlCellRef.parse(address)).fontBold,
      isTrue,
      reason: 'The actual ribbon must format the full selected range.',
    );
  }
  expect(sheet.isDirty, isTrue);
}

Future<void> _withStyleHistoryHost(
  WidgetTester tester,
  _StyleHistoryFixture fixture,
  Future<void> Function(OfficeTestHarness, SheetEditorController) body,
) async {
  tester.view.physicalSize = const Size(2000, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() async {
    final host = await OfficeTestHarness.open(
      tester,
      name: 'native-style-history.xlsx',
      initialBytes: fixture.bytes,
    );
    try {
      final sheet = host.controller as SheetEditorController;
      expect(sheet.isDirty, isFalse);
      expect(sheet.sheet.name, 'Budget');
      _assertStyleProvenance(sheet);
      await body(host, sheet);
    } finally {
      await host.dispose();
    }
  });
  expect(tester.takeException(), isNull);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _editWord(WidgetTester tester, WordEditorController word) async {
  word.jumpToParagraph(0);
  word.caret.logicalIndex = 0;
  word.caret.collapseSelection();
  word.insertText('Reviewed: ');
  word.caret
    ..paragraphIndex = 0
    ..logicalIndex = word.document.paragraphs.first.text.length
    ..selectionAnchorParagraph = 0
    ..selectionAnchor = 0;
  word.refresh();
  await tester.pump();
  await _tap(tester, find.byTooltip('Bold (Ctrl+B)'));
  await _tap(tester, find.byTooltip('Paragraph settings…'));
  await tester.enterText(
    find.widgetWithText(TextField, 'Left indent (pt)'),
    '24',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Space after (pt)'),
    '18',
  );
  await _tap(tester, find.widgetWithText(ElevatedButton, 'Apply'));
}

Future<void> _typeSheetCell(
  WidgetTester tester,
  SheetEditorController sheet,
  String address,
  String value,
) async {
  sheet.selection.selectCell(SmlCellRef.parse(address));
  sheet.refresh();
  tester
      .widget<QudsSheetEditor>(find.byType(QudsSheetEditor))
      .focusNode!
      .requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.f2);
  await tester.pump();
  expect(sheet.cellEditor.editing, isTrue);
  tester.testTextInput.enterText(value);
  await tester.pump();
  sheet.commitPendingEdits();
  await tester.pump();
}

Future<void> _editSheet(
  WidgetTester tester,
  SheetEditorController sheet,
) async {
  await _typeSheetCell(tester, sheet, 'A2', 'Approved travel');
  await _typeSheetCell(tester, sheet, 'B2', '135.5');
  sheet.selection.selectCell(SmlCellRef.parse('A2'));
  sheet.refresh();
  await tester.pump();
  await _tap(tester, find.byTooltip('Bold'));
  await _tap(tester, find.byTooltip('Align center'));
  sheet.selection.selectCell(SmlCellRef.parse('A5'));
  sheet.refresh();
  await tester.pump();
  await _tap(tester, find.byTooltip('Align center'));
}

Future<void> _editSlide(
  WidgetTester tester,
  SlideEditorController slides,
) async {
  slides.selectShape(slides.slide.shapes.first);
  tester
      .widget<QudsSlideEditor>(find.byType(QudsSlideEditor))
      .focusNode!
      .requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.f2);
  await tester.pump();
  expect(slides.textEditor.editing, isTrue);
  tester.testTextInput.enterText('Reviewed slide title');
  await tester.pump();
  slides.commitPendingEdits();
  await tester.pump();
  await _tap(tester, find.byTooltip('Speaker notes').first);
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    'Reviewed notes\nDecision: approved\nReference retained.',
  );
  await _tap(tester, find.widgetWithText(ElevatedButton, 'Apply'));
}

void main() {
  testWidgets(
    'native fills survive unrelated formatting through three host uploads',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final (source, expected) = _nativeFillSource();
        const output = 'build/office-fill-host-acceptance';
        File('$output/source.xlsx')
          ..createSync(recursive: true)
          ..writeAsBytesSync(source);
        _assertNativeFills(source, expected, edited: false);
        var bytes = source;
        for (var cycle = 1; cycle <= 3; cycle++) {
          const name = 'native-fill-preservation.xlsx';
          final host = await OfficeTestHarness.open(
            tester,
            name: name,
            initialBytes: bytes,
          );
          expect(host.cloud.downloads, contains('/$name'));
          final sheet = host.controller as SheetEditorController;
          if (cycle == 1) {
            sheet.selection.selectCell(SmlCellRef.parse('A1'));
            sheet.refresh();
            await tester.pump();
            await _tap(tester, find.byTooltip('Bold'));
            sheet.selection.selectCell(SmlCellRef.parse('B1'));
            sheet.refresh();
            await tester.pump();
            await _tap(tester, find.byTooltip('Align center'));
            expect(sheet.isDirty, isTrue);
          }
          await host.save();
          expect(host.cloud.writes, ['/$name']);
          expect(sheet.isDirty, isFalse);
          bytes = Uint8List.fromList(host.savedBytes);
          File('$output/saved-$cycle.xlsx').writeAsBytesSync(bytes);
          // Compare every actual upload to the authored source definitions,
          // including the first save, so a lossy first export cannot pass.
          _assertNativeFills(bytes, expected, edited: true);
          await host.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    },
  );

  group('ribbon style history', () {
    late _StyleHistoryFixture fixture;
    setUpAll(() {
      fixture = _nativeStyleHistorySource();
      _assertNativeStyleHistory(fixture.bytes, fixture, budgetBold: false);
      _styleHistoryEvidence('source.xlsx', fixture.bytes);
    });

    testWidgets('targets its owning worksheet after navigation', (
      tester,
    ) async {
      await _withStyleHistoryHost(tester, fixture, (host, sheet) async {
        await _styleHistoryBold(tester, sheet);
        await _styleHistorySave(host, 'cross-sheet-applied.xlsx');
        _assertNativeStyleHistory(host.savedBytes, fixture, budgetBold: true);
        // This host has no worksheet selector; only navigation uses the public
        // controller. Styling, history and save use the actual ribbon controls.
        sheet.setActiveSheet(1);
        await tester.pump();
        expect(sheet.sheet.name, 'Reference');
        await _styleHistoryAction(tester, 'Undo');
        expect(sheet.activeSheetIndex, 1);
        await _styleHistorySave(host, 'cross-sheet-undo.xlsx');
        _assertNativeStyleHistory(host.savedBytes, fixture, budgetBold: false);
        _assertStyleProvenance(sheet);
        await _styleHistoryAction(tester, 'Redo');
        expect(sheet.activeSheetIndex, 1);
        await _styleHistorySave(host, 'cross-sheet-redo.xlsx');
        _assertNativeStyleHistory(host.savedBytes, fixture, budgetBold: true);
        _assertStyleProvenance(sheet);
      });
    });

    testWidgets('preserves native fill font and style provenance on undo', (
      tester,
    ) async {
      await _withStyleHistoryHost(tester, fixture, (host, sheet) async {
        await _styleHistoryBold(tester, sheet);
        await _styleHistoryAction(tester, 'Undo');
        for (final address in ['A1', 'B1', 'C1', 'D1']) {
          expect(sheet.sheet.cell(SmlCellRef.parse(address)).fontBold, isFalse);
        }
        await _styleHistorySave(host, 'native-undo.xlsx');
        _assertNativeStyleHistory(host.savedBytes, fixture, budgetBold: false);
        _assertStyleProvenance(sheet);
        await _styleHistoryAction(tester, 'Redo');
        await _styleHistorySave(host, 'native-redo.xlsx');
        _assertNativeStyleHistory(host.savedBytes, fixture, budgetBold: true);
        _assertStyleProvenance(sheet);
      });
    });
  });

  for (final scenario in _cases()) {
    test('${scenario.id} rejects a substituted valid expected package', () {
      final source = scenario.load('source');
      expect(() => scenario.verify('expected', source), throwsFormatException);
      _assertOutput(scenario.load('expected'), scenario);
    });

    testWidgets(
      '${scenario.id} matches independent expectations through three host saves',
      (tester) async {
        tester.view.physicalSize = const Size(2000, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          scenario.emitReference();
          var bytes = scenario.load('source');
          for (var cycle = 1; cycle <= 3; cycle++) {
            final name = '${scenario.id}.${scenario.extension}';
            final host = await OfficeTestHarness.open(
              tester,
              name: name,
              initialBytes: bytes,
            );
            expect(host.cloud.downloads, contains('/$name'));
            if (cycle == 1) {
              switch (host.controller) {
                case final WordEditorController word:
                  await _editWord(tester, word);
                case final SheetEditorController sheet:
                  await _editSheet(tester, sheet);
                case final SlideEditorController slides:
                  await _editSlide(tester, slides);
                default:
                  fail('Unexpected actual host controller');
              }
              expect(host.controller.isDirty, isTrue);
            }
            await host.save();
            expect(host.cloud.writes, ['/$name']);
            expect(host.controller.isDirty, isFalse);
            bytes = Uint8List.fromList(host.savedBytes);
            File(
                'build/fidelity-host/${scenario.id}-$cycle.${scenario.extension}',
              )
              ..createSync(recursive: true)
              ..writeAsBytesSync(bytes);
            _assertOutput(bytes, scenario);
            await host.dispose();
          }
        });
        expect(tester.takeException(), isNull);
      },
    );
  }
}
