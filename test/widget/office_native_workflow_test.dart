import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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
