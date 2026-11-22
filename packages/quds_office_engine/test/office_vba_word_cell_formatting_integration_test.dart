import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_table_cells_smoke.dart' as table_fixture;

const _cell = 'ActiveDocument.Tables(1).Cell(1, 1).Range';
const _w = OfficeNamespaces.w;

// The existing serializer materializes an inherited second-section header on
// the first ordinary read/save. Establish that no-macro control save before
// checking XML semantics, opaque part bytes and core metadata other than the
// ordinary save timestamp.
Uint8List _input({bool macroEnabled = true}) => WordSerializer().writeBytes(
  WordDeserializer().readBytes(
    table_fixture.wordTableInput(macroEnabled: macroEnabled),
  ),
);

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'CellFormatting',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

List<WmlTable> _tables(WmlDocument document) => [
  for (final section in document.sections)
    ...section.blocks.whereType<WmlTable>(),
];

WmlParagraph _paragraph(
  WmlDocument document, {
  int table = 0,
  int row = 0,
  int column = 0,
}) =>
    _tables(document)[table].rows[row].cells[column].blocks.single
        as WmlParagraph;

XmlElement _documentXml(Uint8List bytes) => XmlDocument.parse(
  OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
).root!;

List<XmlElement> _elements(XmlElement root, String name) => [
  for (final child in root.childElements) ...[
    if (child.localName == name && child.namespaceUri == _w) child,
    ..._elements(child, name),
  ],
];

// Native saves may rebind a namespace on a preserved property packet. Compare
// expanded names, all substantive attributes and ordered children, so that only
// redundant xmlns declarations and prefix choices are ignored.
Object _xmlValue(XmlNode node) => switch (node) {
  XmlElement() => {
    'name': [node.namespaceUri, node.localName],
    'attributes': {
      for (final attribute
          in (node.attributes
              .where(
                (attribute) =>
                    attribute.prefix != 'xmlns' &&
                    !(attribute.prefix.isEmpty &&
                        attribute.localName == 'xmlns'),
              )
              .toList()
            ..sort(
              (a, b) => '${a.namespaceUri}:${a.localName}'.compareTo(
                '${b.namespaceUri}:${b.localName}',
              ),
            )))
        '${attribute.namespaceUri}:${attribute.localName}': attribute.value,
    },
    'children': [for (final child in node.children) _xmlValue(child)],
  },
  XmlText() => {'text': node.text},
  XmlCdata() => {'cdata': node.text},
  XmlComment() => {'comment': node.text},
};

String _xml(XmlElement element) => jsonEncode(_xmlValue(element));

String _coreMetadata(String source) {
  final root = XmlDocument.parse(source).root!;
  // An ordinary save refreshes only this timestamp. Keep all other core
  // metadata, the modified element itself, and its attributes in the check.
  for (final modified in root.childrenNamed(
    'modified',
    namespaceUri: 'http://purl.org/dc/terms/',
  )) {
    expect(modified.childElements, isEmpty);
    expect(DateTime.tryParse(modified.text), isNotNull);
    modified.children.clear();
    modified.addText('save timestamp');
  }
  return _xml(root);
}

Map<String, Object?> _untouched(Uint8List bytes) {
  final root = _documentXml(bytes);
  final body = root.childrenNamed('body', namespaceUri: _w).single;
  final cells = _elements(root, 'tc');
  final package = OpcPackage.openBytes(bytes);
  return {
    'bodyParagraphs': [
      for (final paragraph in body.childrenNamed('p', namespaceUri: _w))
        _xml(paragraph),
    ],
    // Only the first cell is formatted by the report below.
    'otherCells': [for (final cell in cells.skip(1)) _xml(cell)],
    for (final name in ['tblPr', 'tblGrid', 'trPr', 'tcPr', 'sectPr'])
      name: [for (final element in _elements(root, name)) _xml(element)],
    'parts': {
      for (final part in package.parts)
        if (part.uri != '/word/document.xml')
          part.uri: part.uri == '/docProps/core.xml'
              ? _coreMetadata(package.getPart(part.uri)!.readText())
              : package.getPart(part.uri)!.readBytes(),
    },
  };
}

const _report = '''
Option Explicit
Sub Paint(ByVal target As Font)
  target.Bold = False
  target.Italic = True
  target.Size = 15.5
  target.Color = RGB(18, 52, 86)
  target.AllCaps = True
End Sub
Sub Main()
  Dim targetCell As Cell, retained As Range, layout As ParagraphFormat
  Set targetCell = Application.ActiveDocument.Tables.Item(1).Cell(1, 1)
  Set retained = targetCell.Range
  retained.Text = "Quarterly 😀"
  Paint retained.Font
  Set layout = retained.ParagraphFormat
  With layout
    .Alignment = wdAlignParagraphRight
    .LeftIndent = 18.25
    .RightIndent = 4.5
    .FirstLineIndent = -9.5
    .SpaceBefore = 6
    .SpaceAfter = 8.5
    .KeepTogether = True
    .PageBreakBefore = False
    .LineSpacingRule = wdLineSpaceExactly
    .LineSpacing = 17.25
    .TabStops.ClearAll
    .TabStops.Add Position:=72.5, Alignment:=wdAlignTabRight, Leader:=wdTabLeaderDots
  End With
  Set targetCell = ActiveDocument.Tables(2).Cell(1, 1)
  retained.Font.Underline = wdUnderlineDouble
End Sub
''';

void _assertReport(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  final paragraph = _paragraph(document);
  expect(paragraph.text, 'Quarterly 😀');
  for (final run in paragraph.inlines.whereType<WmlRun>()) {
    expect(run.properties.bold, isFalse);
    expect(run.properties.italic, isTrue);
    expect(run.properties.asciiFont, 'Courier New');
    expect(run.properties.fontSizeHalfPoints, 31);
    expect(run.properties.color, '123456');
    expect(run.properties.allCaps, isTrue);
    expect(run.properties.underline, WmlUnderline.double);
  }
  final properties = paragraph.properties;
  expect(properties.justification, WmlJustification.right);
  expect(properties.indent.left, 18.25);
  expect(properties.indent.right, 4.5);
  expect(properties.indent.firstLine, 0);
  expect(properties.indent.hanging, 9.5);
  expect(properties.spacingBefore, 6);
  expect(properties.spacingAfter, 8.5);
  expect(properties.keepTogether, isTrue);
  expect(properties.pageBreakBefore, isFalse);
  expect(properties.lineSpacingRule, WmlLineSpacingRule.exact);
  expect(properties.lineSpacing, 17.25);
  expect(properties.tabs, hasLength(1));
  expect(properties.tabs.single.position, 72.5);
  expect(properties.tabs.single.alignment, WmlTabAlignment.right);
  expect(properties.tabs.single.leader, WmlTabLeader.dot);
  final cellXml = _elements(_documentXml(bytes), 'tc').first;
  final spacing = _elements(cellXml, 'spacing').single;
  for (final attribute in const {
    'before': '120',
    'after': '170',
    'line': '345',
    'lineRule': 'exact',
  }.entries) {
    expect(
      spacing.getAttribute(attribute.key, namespaceUri: _w),
      attribute.value,
    );
  }
  final indent = _elements(cellXml, 'ind').single;
  for (final attribute in const {
    'left': '365',
    'right': '90',
    'hanging': '190',
  }.entries) {
    expect(
      indent.getAttribute(attribute.key, namespaceUri: _w),
      attribute.value,
    );
  }
}

Uint8List _changed(void Function(WmlDocument document) change) {
  final document = WordDeserializer().readBytes(_input());
  change(document);
  return WordSerializer().writeBytes(document);
}

Uint8List _inheritedTableStyleInput() {
  final package = OpcPackage.openBytes(_input());
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="$_w"><w:body>
<w:p><w:r><w:t>Untouched body</w:t></w:r></w:p>
<w:tbl><w:tblPr><w:tblStyle w:val="CellFormattingBase"/></w:tblPr>
<w:tblGrid><w:gridCol w:w="2400"/><w:gridCol w:w="2400"/></w:tblGrid>
<w:tr><w:tc><w:p><w:r><w:t>Selected</w:t></w:r></w:p></w:tc>
<w:tc><w:p><w:r><w:t>Neighbor</w:t></w:r></w:p></w:tc></w:tr>
</w:tbl><w:sectPr/></w:body></w:document>
''');
  package.getPart('/word/styles.xml')!.writeText('''
<w:styles xmlns:w="$_w">
<w:style w:type="table" w:styleId="CellFormattingBase">
<w:pPr><w:jc w:val="center"/><w:spacing w:before="240" w:after="120"/></w:pPr>
<w:rPr><w:b/><w:caps/><w:color w:val="AABBCC"/></w:rPr>
</w:style></w:styles>
''');
  return package.save();
}

Future<void> _assertRefused(Uint8List input, OfficeMacro plan) async {
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Refused cell formatting');
  for (final action in [session.validate, session.run]) {
    await expectLater(action(plan), throwsA(isA<OfficeMacroException>()));
    expect(session.bytes, input);
    expect(session.revision, 0);
  }
  expect(session.stopRecording().steps, isEmpty);
}

void main() {
  for (final macroEnabled in [false, true]) {
    test(
      '${macroEnabled ? 'DOCM' : 'DOCX'} report preserves neighboring XML semantics and opaque part bytes',
      () async {
        final input = _input(macroEnabled: macroEnabled);
        final untouched = _untouched(input);
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        final plan = _source(_report);
        final preview = await session.validate(plan);
        expect(preview.validatedOnly, isTrue);
        expect(preview.completedSteps, plan.steps.length);
        expect(session.bytes, input);
        expect(session.revision, 0);
        await session.run(OfficeMacro.parse(plan.encode()));
        expect(session.revision, 1);
        var saved = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          _assertReport(saved);
          expect(_untouched(saved), untouched, reason: 'reopen $cycle');
          if (cycle < 2) {
            saved = WordSerializer().writeBytes(
              WordDeserializer().readBytes(saved),
            );
          }
        }
        // Repeating explicit values is idempotent after their first native save.
        final firstXml = _xml(_documentXml(session.bytes));
        await session.run(plan);
        _assertReport(session.bytes);
        expect(_xml(_documentXml(session.bytes)), firstXml);
        expect(_untouched(session.bytes), untouched);
        expect(session.revision, 2);
      },
    );
  }

  test(
    'formatting before cell text replacement survives later writes',
    () async {
      final input = _input();
      final untouched = _untouched(input);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(
        _compile('''
With $_cell
  .Font.Bold = False
  .Font.ColorIndex = wdRed
  .Font.Size = 14
  .ParagraphFormat.Alignment = wdAlignParagraphLeft
  .Text = "New\tvalue"
End With
'''),
      );
      final paragraph = _paragraph(WordDeserializer().readBytes(session.bytes));
      expect(paragraph.text, 'New\tvalue');
      expect(paragraph.properties.justification, WmlJustification.left);
      expect(
        paragraph.inlines.whereType<WmlRun>().single.properties.bold,
        isFalse,
      );
      expect(
        paragraph.inlines.whereType<WmlRun>().single.properties.color,
        'FF0000',
      );
      expect(
        paragraph.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .fontSizeHalfPoints,
        28,
      );
      expect(_untouched(session.bytes), untouched);
    },
  );

  test(
    'cell selector remains distinct from body and other cells during spacing pairing',
    () async {
      final session = OfficeMacroSession(
        _input(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        _source('''
Sub Finish(ByVal target As ParagraphFormat, ByVal amount As Double)
  target.LineSpacing = amount
End Sub
Sub Main()
  Dim target As ParagraphFormat, retained As ParagraphFormat
  Set target = $_cell.ParagraphFormat
  Set retained = target
  retained.LineSpacingRule = wdLineSpaceExactly
  Set target = ActiveDocument.Tables(1).Cell(1, 2).Range.ParagraphFormat
  Finish retained, 19.5
  target.Space2
  ActiveDocument.Paragraphs(1).Format.Space15
  ActiveDocument.Tables(2).Cell(1, 1).Range.Font.ColorIndex = wdBlue
End Sub
'''),
      );
      final document = WordDeserializer().readBytes(session.bytes);
      final first = _paragraph(document).properties;
      expect(first.lineSpacingRule, WmlLineSpacingRule.exact);
      expect(first.lineSpacing, 19.5);
      final neighbor = _paragraph(document, column: 1).properties;
      expect(neighbor.lineSpacingRule, WmlLineSpacingRule.auto);
      expect(neighbor.lineSpacing, 2);
      final body = document.sections.first.blocks.first as WmlParagraph;
      expect(body.properties.lineSpacingRule, WmlLineSpacingRule.auto);
      expect(body.properties.lineSpacing, 1.5);
      expect(
        _paragraph(
          document,
          table: 1,
        ).inlines.whereType<WmlRun>().single.properties.color,
        '0000FF',
      );
      expect(
        _paragraph(
          document,
        ).inlines.whereType<WmlRun>().single.properties.color,
        '1F4E79',
      );
    },
  );

  test(
    'recorded native cell formatting replays to the same saved document',
    () async {
      final input = _input();
      final plan = _source(_report);
      final recorder = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
      );
      recorder.startRecording('Cell formatting report');
      for (final step in plan.steps) {
        await recorder.callTool(step.tool, step.arguments);
      }
      final recorded = recorder.stopRecording();
      expect(recorded.steps, hasLength(plan.steps.length));
      final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await replay.run(OfficeMacro.parse(recorded.encode()));
      _assertReport(replay.bytes);
      expect(
        _xml(_documentXml(replay.bytes)),
        _xml(_documentXml(recorder.bytes)),
      );
      expect(_untouched(replay.bytes), _untouched(input));
    },
  );

  test(
    'whole-cell font changes retain mixed ordinary run formatting',
    () async {
      final input = _changed((document) {
        _paragraph(document).inlines = [
          WmlRun(
            text: 'First ',
            properties: WmlRunProps(
              italic: true,
              color: '112233',
              fontSizeHalfPoints: 20,
            ),
          ),
          WmlRun(
            text: 'second',
            properties: WmlRunProps(color: '445566', fontSizeHalfPoints: 28),
          ),
        ];
      });
      final untouched = _untouched(input);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(
        _compile('''
$_cell.Font.Bold = True
$_cell.ParagraphFormat.SpaceAfter = 9.5
'''),
      );
      var saved = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final paragraph = _paragraph(WordDeserializer().readBytes(saved));
        final runs = paragraph.inlines.whereType<WmlRun>().toList();
        expect(paragraph.text, 'First second');
        expect(paragraph.properties.spacingAfter, 9.5);
        expect(runs.map((run) => run.text), ['First ', 'second']);
        expect(runs.map((run) => run.properties.bold), [true, true]);
        expect(runs.map((run) => run.properties.italic), [true, false]);
        expect(runs.map((run) => run.properties.color), ['112233', '445566']);
        expect(runs.map((run) => run.properties.fontSizeHalfPoints), [20, 28]);
        expect(_untouched(saved), untouched);
        if (cycle < 2) {
          saved = WordSerializer().writeBytes(
            WordDeserializer().readBytes(saved),
          );
        }
      }
    },
  );

  test(
    'false and automatic values explicitly override inherited table styles',
    () async {
      final input = _inheritedTableStyleInput();
      final original = WordDeserializer().readBytes(input);
      final initialRun = _paragraph(
        original,
      ).inlines.whereType<WmlRun>().single;
      expect(initialRun.properties.bold, isTrue);
      expect(initialRun.properties.allCaps, isTrue);
      expect(initialRun.properties.color, 'AABBCC');
      expect(_paragraph(original).properties.spacingBefore, 12);
      final styles = _xml(
        XmlDocument.parse(
          OpcPackage.openBytes(input).getPart('/word/styles.xml')!.readText(),
        ).root!,
      );
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(
        _compile('''
With $_cell
  .Font.Bold = False
  .Font.AllCaps = False
  .Font.Color = wdColorAutomatic
  .ParagraphFormat.Alignment = wdAlignParagraphLeft
  .ParagraphFormat.SpaceBefore = 0
End With
'''),
      );
      var saved = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final document = WordDeserializer().readBytes(saved);
        final target = _paragraph(document);
        final run = target.inlines.whereType<WmlRun>().single;
        expect(run.properties.bold, isFalse);
        expect(run.properties.allCaps, isFalse);
        expect(run.properties.color, 'auto');
        expect(target.properties.justification, WmlJustification.left);
        expect(target.properties.spacingBefore, 0);
        expect(target.properties.spacingAfter, 6);
        final neighbor = _paragraph(document, column: 1);
        final otherRun = neighbor.inlines.whereType<WmlRun>().single;
        expect(otherRun.properties.bold, isTrue);
        expect(otherRun.properties.allCaps, isTrue);
        expect(otherRun.properties.color, 'AABBCC');
        expect(neighbor.properties.justification, WmlJustification.center);
        expect(neighbor.properties.spacingBefore, 12);
        expect(
          _xml(
            XmlDocument.parse(
              OpcPackage.openBytes(
                saved,
              ).getPart('/word/styles.xml')!.readText(),
            ).root!,
          ),
          styles,
        );
        if (cycle < 2) {
          saved = WordSerializer().writeBytes(document);
        }
      }
    },
  );

  test(
    'MCP compiles, previews and applies the cell formatting source',
    () async {
      final input = _input();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final adapter = OfficeMacroMcp(session);
      final compiled = await adapter.callTool('office_macro_compile', {
        'source': {
          'language': 'vba-word',
          'format': 'docx',
          'moduleName': 'CellFormatting',
          'source': _report,
        },
      });
      expect(compiled['isError'], isFalse, reason: '$compiled');
      final content = compiled['structuredContent']! as Map<String, Object?>;
      final arguments = <String, Object?>{'macro': content['macro']};
      final preview = await adapter.callTool(
        'office_macro_validate',
        arguments,
      );
      expect(preview['isError'], isFalse, reason: '$preview');
      expect(session.bytes, input);
      expect(session.revision, 0);
      final result = await adapter.callTool('office_macro_run', arguments);
      expect(result['isError'], isFalse, reason: '$result');
      _assertReport(session.bytes);
      expect(session.revision, 1);
    },
  );

  for (final (label, change) in <(String, void Function(WmlDocument))>[
    (
      'horizontal merge',
      (document) => _tables(document).first.rows.first.cells.first.gridSpan = 2,
    ),
    (
      'vertical merge',
      (document) => _tables(document).first.rows.first.cells.first.vMerge =
          WmlVMerge.restart,
    ),
    (
      'nested table in another cell',
      (document) => _tables(document).first.rows.last.cells.last.blocks.add(
        WmlTable(
          grid: [60],
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(
                  blocks: [
                    WmlParagraph(inlines: [WmlRun(text: 'Nested')]),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    (
      'multiple cell paragraphs',
      (document) => _tables(document).first.rows.first.cells.first.blocks.add(
        WmlParagraph(inlines: [WmlRun(text: 'Second')]),
      ),
    ),
    (
      'hyperlinked run',
      (document) => (_paragraph(document).inlines.first as WmlRun).hyperlink =
          const WmlHyperlink(url: 'https://example.com'),
    ),
    (
      'simple field',
      (document) =>
          (_paragraph(document).inlines.first as WmlRun).fieldInstruction =
              'PAGE',
    ),
    (
      'bookmark',
      (document) =>
          _paragraph(document).properties.bookmarkName = 'CellBookmark',
    ),
    ('edit restriction', (document) => document.restrictEditing = true),
    ('revision tracking', (document) => document.trackRevisions = true),
  ]) {
    test(
      '$label refuses formatting without publishing earlier edits',
      () async {
        final input = _changed(change);
        for (final formatting in [
          '$_cell.Font.Italic = True',
          '$_cell.ParagraphFormat.Alignment = wdAlignParagraphRight',
        ]) {
          await _assertRefused(
            input,
            _compile('''
ActiveDocument.Paragraphs(1).Range.Font.ColorIndex = wdRed
$formatting
'''),
          );
        }
      },
    );
  }

  test('native formatting restriction refuses cell writes', () async {
    final package = OpcPackage.openBytes(_input());
    final settings =
        package.getPart('/word/settings.xml') ??
        package.createPart(
          '/word/settings.xml',
          OfficeContentTypes.wordSettings,
        );
    settings.writeText('''
<w:settings xmlns:w="$_w"><w:documentProtection
w:formatting="1" w:enforcement="1" w:edit="readOnly"/></w:settings>
''');
    final relationships = package.relationshipsFor('/word/document.xml');
    if (relationships.byType(RelationshipTypes.settings).isEmpty) {
      relationships.add(
        type: RelationshipTypes.settings,
        target: 'settings.xml',
      );
    }
    final input = package.save();
    expect(
      WordDeserializer().readBytes(input).protectionFormattingRestricted,
      isTrue,
    );
    for (final body in [
      '$_cell.Font.Bold = False',
      '$_cell.ParagraphFormat.Alignment = wdAlignParagraphRight',
    ]) {
      await _assertRefused(input, _compile(body));
    }
  });

  test(
    'late missing cell rolls back text, font, paragraph and recorded operations',
    () async {
      await _assertRefused(
        _input(),
        _compile('''
$_cell.Text = "Do not publish"
$_cell.Font.Bold = False
$_cell.ParagraphFormat.Alignment = wdAlignParagraphRight
ActiveDocument.Tables(2).Cell(2, 1).Range.Font.Italic = True
'''),
      );
    },
  );

  test(
    'paragraph formatting admits empty cells while Font requires existing text',
    () async {
      final input = _changed(
        (document) => _paragraph(document).inlines.clear(),
      );
      await _assertRefused(input, _compile('$_cell.Font.Bold = False'));
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(
        _compile('''
$_cell.ParagraphFormat.Alignment = wdAlignParagraphRight
$_cell.ParagraphFormat.SpaceBefore = 6
'''),
      );
      final paragraph = _paragraph(WordDeserializer().readBytes(session.bytes));
      expect(paragraph.text, isEmpty);
      expect(paragraph.properties.justification, WmlJustification.right);
      expect(paragraph.properties.spacingBefore, 6);
    },
  );

  for (final policy in [
    OfficeMacroPolicy(allowMutation: false),
    OfficeMacroPolicy(allowedTools: {'docx.tableCellRangeText'}),
    OfficeMacroPolicy(maxSteps: 1),
  ]) {
    test('cell formatting obeys session policy $policy', () async {
      final input = _input();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: policy,
      );
      final plan = _compile('''
$_cell.Font.Bold = False
$_cell.ParagraphFormat.Alignment = wdAlignParagraphRight
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(action(plan), throwsA(isA<OfficeMacroException>()));
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
    });
  }

  test(
    'unsupported cell reads refuse the whole MCP compilation before mutation',
    () async {
      final input = _input();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final result = await OfficeMacroMcp(session).callTool(
        'office_macro_compile',
        {
          'source': {
            'language': 'vba-word',
            'format': 'docx',
            'moduleName': 'CellFormatting',
            'source':
                '''
Sub Main()
  $_cell.Font.Bold = False
  Dim value As Boolean
  value = $_cell.Font.Bold
End Sub
''',
          },
        },
      );
      expect(result['isError'], isTrue);
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );
}
