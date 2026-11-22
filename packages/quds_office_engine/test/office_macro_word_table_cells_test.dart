import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;

WmlParagraph _paragraph(String text) => WmlParagraph(
  properties: WmlParagraphProps(
    justification: WmlJustification.center,
    spacingBefore: 3,
    spacingAfter: 6,
  ),
  inlines: [
    WmlRun(
      text: text,
      properties: WmlRunProps(
        italic: true,
        color: '123456',
        fontSizeHalfPoints: 28,
      ),
    ),
  ],
);

WmlTable _table(String label) => WmlTable(
  grid: [80, 90],
  properties: WmlTableProps(
    cellMargin: 6,
    borderColor: '334455',
    borderWidth: 1,
  ),
  rows: [
    for (var row = 0; row < 2; row++)
      WmlTableRow(
        cantSplit: true,
        height: 20,
        cells: [
          for (var column = 0; column < 2; column++)
            WmlTableCell(
              width: column == 0 ? 80 : 90,
              fillColor: 'DDEEFF',
              borderTop: true,
              blocks: [_paragraph('$label $row/$column')],
            ),
        ],
      ),
  ],
);

WmlDocument _document() => WmlDocument(
  sections: [
    WmlSection(
      blocks: [_paragraph('Before'), _table('First'), _paragraph('Between')],
      header: [_paragraph('Untouched header')],
    ),
    WmlSection(blocks: [_table('Second'), _paragraph('After')]),
  ],
);

List<WmlTable> _tables(WmlDocument document) => [
  for (final section in document.sections)
    ...section.blocks.whereType<WmlTable>(),
];

WmlParagraph _target(
  WmlDocument document, {
  int table = 0,
  int row = 0,
  int column = 0,
}) => _tables(
  document,
)[table].rows[row].cells[column].blocks.whereType<WmlParagraph>().first;

Map<String, Object?> _step({
  Object? table = 0,
  Object? row = 0,
  Object? column = 0,
  Object? text = 'Replacement',
}) => {
  'op': 'tableCellRangeText',
  'table': table,
  'row': row,
  'column': column,
  'text': text,
};

Uint8List _bytes() {
  final package = OpcPackage.openBytes(
    WordSerializer().writeBytes(_document()),
  );
  package.createPart(
    '/word/vbaProject.bin',
    'application/vnd.ms-office.vbaProject',
    Uint8List.fromList([0, 1, 7, 255, 48, 66]),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(
        type:
            'http://schemas.microsoft.com/office/2006/relationships/vbaProject',
        target: 'vbaProject.bin',
      );
  return package.save();
}

Map<String, Uint8List> _parts(WmlDocument document) => {
  if (document.package case final package?)
    for (final part in package.parts)
      part.uri: package.getPart(part.uri)!.readBytes(),
};

void _refuses(
  WmlDocument document, {
  Map<String, Object?>? step,
  WmlParagraph? target,
  Matcher matcher = throwsUnsupportedError,
}) {
  final paragraph = target ?? _target(document);
  final inlines = paragraph.inlines;
  final properties = paragraph.properties;
  final text = paragraph.text;
  final parts = _parts(document);
  final revisions = [
    for (final revision in document.revisions)
      (
        revision.targetParagraph,
        revision.paragraphIndex,
        revision.hasCapturedTarget,
      ),
  ];
  expect(() => native.applyStep(document, step ?? _step()), matcher);
  expect(paragraph.inlines, same(inlines));
  expect(paragraph.properties, same(properties));
  expect(paragraph.text, text);
  expect(_parts(document), parts);
  expect([
    for (final revision in document.revisions)
      (
        revision.targetParagraph,
        revision.paragraphIndex,
        revision.hasCapturedTarget,
      ),
  ], revisions);
}

WmlDocument _native(String Function(String xml) change) {
  final package = OpcPackage.openBytes(_bytes());
  final part = package.getPart('/word/document.xml')!;
  part.writeText(change(part.readText()));
  return WordDeserializer().read(package);
}

void main() {
  for (final text in ['', 'One cell', '  A\tB  ', 'Aé😀 العربية <&>']) {
    test(
      'cell text $text preserves formatting and ownership across repeated saves',
      () {
        var document = WordDeserializer().readBytes(_bytes());
        final table = _tables(document).first;
        final cell = table.rows.first.cells.first;
        final paragraph = _target(document);
        final paragraphProperties = paragraph.properties;
        final firstProperties = paragraph.inlines
            .whereType<WmlRun>()
            .first
            .properties;
        paragraph.inlines.add(
          WmlRun(text: ' tail', properties: WmlRunProps(bold: true)),
        );
        final originalOther = _target(document, table: 1).text;
        native.applyStep(document, _step(text: text));
        expect(_tables(document).first, same(table));
        expect(table.rows.first.cells.first, same(cell));
        expect(cell.blocks.single, same(paragraph));
        expect(paragraph.properties, same(paragraphProperties));
        expect(paragraph.text, text);
        for (var cycle = 0; cycle < 3; cycle++) {
          final current = _target(document);
          expect(current.text, text);
          final run = current.inlines.whereType<WmlRun>().single;
          expect(run.properties.italic, firstProperties.italic);
          expect(run.properties.bold, firstProperties.bold);
          expect(run.properties.color, '123456');
          expect(run.properties.fontSizeHalfPoints, 28);
          expect(current.properties.justification, WmlJustification.center);
          expect(current.properties.spacingBefore, 3);
          expect(current.properties.spacingAfter, 6);
          final currentTable = _tables(document).first;
          expect(currentTable.grid, [80, 90]);
          expect(currentTable.properties.cellMargin, 6);
          expect(currentTable.rows.first.height, 20);
          expect(currentTable.rows.first.cantSplit, isTrue);
          expect(currentTable.rows.first.cells.first.fillColor, 'DDEEFF');
          expect(currentTable.rows.first.cells.first.borderTop, isTrue);
          expect(_target(document, table: 1).text, originalOther);
          final saved = WordSerializer().writeBytes(document);
          expect(
            OpcPackage.openBytes(
              saved,
            ).getPart('/word/vbaProject.bin')!.readBytes(),
            [0, 1, 7, 255, 48, 66],
          );
          document = WordDeserializer().readBytes(saved);
          // A serialized native payload remains safe after the first save.
          native.applyStep(
            document,
            Map<String, Object?>.from(
              jsonDecode(jsonEncode(_step(text: text))) as Map<String, Object?>,
            ),
          );
        }
      },
    );
  }

  test('table selectors follow direct main-story order across sections', () {
    final document = _document();
    native.applyStep(document, _step(table: 1, row: 1, column: 1));
    expect(_target(document, table: 1, row: 1, column: 1).text, 'Replacement');
    expect(_target(document).text, 'First 0/0');
    expect(document.sections.first.header.single.text, 'Untouched header');
  });

  test('empty cell uses its existing paragraph-mark formatting', () {
    final document = _document();
    final target = _target(document)..inlines.clear();
    target.properties.importedParagraphMark = WmlRunProps(
      bold: true,
      color: 'ABCDEF',
    );
    native.applyStep(document, _step());
    final run = target.inlines.whereType<WmlRun>().single;
    expect(run.text, 'Replacement');
    expect(run.properties.bold, isTrue);
    expect(run.properties.color, 'ABCDEF');
  });

  test(
    'source aliases preserve native namespaces and sparse property metadata',
    () {
      final document = _native(
        (xml) => xml
            .replaceFirst(
              '<w:document ',
              '<w:document xmlns:x="urn:cell-test" ',
            )
            .replaceFirst('<w:pPr>', '<w:pPr><x:keep x:value="paragraph"/>')
            .replaceFirst('<w:tcPr>', '<w:tcPr>')
            .replaceAll('w:', 'q:')
            .replaceFirst('xmlns:w=', 'xmlns:q='),
      );
      native.applyStep(document, _step());
      final saved = WordSerializer().writeBytes(document);
      expect(_target(WordDeserializer().readBytes(saved)).text, 'Replacement');
      expect(
        OpcPackage.openBytes(saved).getPart('/word/document.xml')!.readText(),
        contains('paragraph'),
      );
    },
  );

  for (final entry in <(String, Map<String, Object?>)>[
    ('negative table', _step(table: -1)),
    ('fractional table', _step(table: 0.5)),
    ('string table', _step(table: '0')),
    ('table outside collection', _step(table: 2)),
    ('negative row', _step(row: -1)),
    ('row outside table', _step(row: 2)),
    ('column outside table', _step(column: 2)),
    ('Boolean column', _step(column: true)),
    ('missing text', _step()..remove('text')),
    ('non-string text', _step(text: 17)),
    ('missing table', _step()..remove('table')),
    ('missing row', _step()..remove('row')),
    ('missing column', _step()..remove('column')),
    ('logical-grid alternative', {..._step(), 'gridColumn': 0}),
    ('story override', {..._step(), 'story': 'header'}),
  ]) {
    test('${entry.$1} refuses before direct mutation', () {
      _refuses(_document(), step: entry.$2, matcher: throwsArgumentError);
    });
  }

  for (final text in [
    '\r',
    '\n',
    '\r\n',
    '\u0007',
    '\u0000',
    '\u000B',
    '\u000C',
    '\uFFFE',
    '\uFFFF',
    String.fromCharCode(0xD800),
    String.fromCharCode(0xDC00),
    '${String.fromCharCode(0xD800)}A',
  ]) {
    test(
      'structural marker or malformed UTF16 ${text.codeUnits} refuses atomically',
      () {
        _refuses(
          _document(),
          step: _step(text: text),
          matcher: throwsArgumentError,
        );
      },
    );
  }

  for (final entry in <(String, void Function(WmlTable))>[
    ('horizontal merge', (table) => table.rows.first.cells.first.gridSpan = 2),
    (
      'vertical merge origin',
      (table) => table.rows.first.cells.first.vMerge = WmlVMerge.restart,
    ),
    (
      'vertical covered slot',
      (table) => table.rows.last.cells.first.vMerge = WmlVMerge.cont,
    ),
    ('omitted leading cell', (table) => table.rows.first.gridBefore = 1),
    ('omitted trailing cell', (table) => table.rows.first.gridAfter = 1),
    ('ragged row', (table) => table.rows.last.cells.removeLast()),
    ('missing grid', (table) => table.grid.clear()),
    ('nonfinite grid', (table) => table.grid[0] = double.nan),
    ('zero-width grid', (table) => table.grid[0] = 0),
  ]) {
    test('${entry.$1} never aliases another cell owner', () {
      final document = _document();
      final table = _tables(document).first;
      final text = table.rows.last.cells.first.blocks
          .whereType<WmlParagraph>()
          .single
          .text;
      entry.$2(table);
      _refuses(document);
      expect(
        table.rows.last.cells.first.blocks
            .whereType<WmlParagraph>()
            .single
            .text,
        text,
      );
    });
  }

  for (final entry in <(String, void Function(WmlParagraph))>[
    (
      'hyperlink',
      (paragraph) => (paragraph.inlines.first as WmlRun).hyperlink =
          const WmlHyperlink(url: 'https://example.com'),
    ),
    (
      'comment',
      (paragraph) => (paragraph.inlines.first as WmlRun).commentIds.add(3),
    ),
    (
      'note reference',
      (paragraph) => (paragraph.inlines.first as WmlRun).noteRefId = 2,
    ),
    (
      'simple field',
      (paragraph) =>
          (paragraph.inlines.first as WmlRun).fieldInstruction = 'PAGE',
    ),
    (
      'paragraph field',
      (paragraph) => paragraph.properties.fieldInstruction = 'DATE',
    ),
    (
      'paragraph bookmark',
      (paragraph) => paragraph.properties.bookmarkName = 'Keep',
    ),
    (
      'paragraph page field',
      (paragraph) => paragraph.properties.pageNumberField = true,
    ),
    ('note paragraph', (paragraph) => paragraph.properties.noteId = 1),
    (
      'complex field boundary',
      (paragraph) => paragraph.inlines.insert(
        0,
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
      ),
    ),
    (
      'bookmark boundary',
      (paragraph) => paragraph.inlines.insert(
        0,
        WmlBookmarkBoundary(id: '1', isStart: true, name: 'Keep'),
      ),
    ),
  ]) {
    test('${entry.$1} is preserved by refusing the cell replacement', () {
      final document = _document();
      entry.$2(_target(document));
      _refuses(document);
    });
  }

  test('a multiple-paragraph cell is refused without replacing blocks', () {
    final document = _document();
    final cell = _tables(document).first.rows.first.cells.first;
    cell.blocks.add(_paragraph('Second paragraph'));
    final blocks = List<WmlBlock>.of(cell.blocks);
    _refuses(document);
    expect(cell.blocks, blocks);
  });

  test(
    'nested tables anywhere cannot silently change document table numbering',
    () {
      final document = _document();
      _tables(document).first.rows.last.cells.last.blocks.add(_table('Nested'));
      _refuses(document, step: _step(table: 1));
    },
  );

  test('framed table collection refuses rather than retargeting table 2', () {
    final document = _document();
    document.sections.first.blocks.insert(
      1,
      WmlFrame(blocks: [_table('Frame')]),
    );
    _refuses(document, step: _step(table: 1));
  });

  test(
    'control-wrapped table collection is explicit unsupported ownership',
    () {
      final document = _document();
      final first = _tables(document).first;
      document.sections.first.blocks[1] = WmlContentControlBlock(
        control: WmlContentControlData(
          xml: '<w:sdt xmlns:w="$_w"><w:sdtPr/><w:sdtContent/></w:sdt>',
          sourcePartUri: '/word/document.xml',
          relationships: [],
        ),
        blocks: [first],
      );
      _refuses(
        document,
        target: first.rows.first.cells.first.blocks.single as WmlParagraph,
      );
    },
  );

  test('opaque body blocks cannot hide table collection members', () {
    final document = _document();
    document.sections.first.blocks.add(
      WmlOpaqueBlock(
        xml: '<x:wrapper xmlns:x="urn:test"><w:tbl xmlns:w="$_w"/></x:wrapper>',
        sourcePartUri: '/word/document.xml',
        relationships: [],
      ),
    );
    _refuses(document);
  });

  test('shared cell ownership refuses without changing either occurrence', () {
    final document = _document();
    final table = _tables(document).first;
    table.rows.last.cells[1] = table.rows.first.cells.first;
    _refuses(document);
    expect(table.rows.last.cells[1], same(table.rows.first.cells.first));
  });

  test(
    'cyclic table ownership is rejected before recursive model traversal',
    () {
      final document = _document();
      final table = _tables(document).first;
      table.rows.last.cells.last.blocks.add(table);
      _refuses(document);
    },
  );

  for (final cyclic in [false, true]) {
    test(
      'public native catalog rejects ${cyclic ? 'cyclic' : 'shared'} table ownership before admission',
      () {
        final document = _document();
        final table = _tables(document).first;
        final target = _target(document);
        final inlines = target.inlines;
        if (cyclic) {
          table.rows.last.cells.last.blocks.add(table);
        } else {
          table.rows.last.cells[1] = table.rows.first.cells.first;
        }
        expect(
          () => OfficeOperationCatalog.apply(
            document,
            'docx.tableCellRangeText',
            {'table': 0, 'row': 0, 'column': 0, 'text': 'Refuse'},
          ),
          throwsUnsupportedError,
        );
        expect(target.inlines, same(inlines));
        expect(target.text, 'First 0/0');
      },
    );
  }

  test(
    'paragraph shared with another story is never changed through a cell',
    () {
      final document = _document();
      document.sections.first.header.add(_target(document));
      _refuses(document);
    },
  );

  test('unresolved revision indexes are not rebound by rejection', () {
    final document = _document();
    document.revisions.add(
      WmlRevision(
        id: 2,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 1,
        start: 0,
        end: 2,
        text: 'Fi',
      ),
    );
    _refuses(document);
  });

  for (final mode in ['restricted', 'formatting', 'tracking']) {
    test('$mode document refuses direct cell writes', () {
      final document = _document();
      if (mode == 'restricted') document.restrictEditing = true;
      if (mode == 'formatting') document.protectionFormattingRestricted = true;
      if (mode == 'tracking') document.trackRevisions = true;
      _refuses(document);
    });
  }

  test('cross-paragraph bookmark enclosing a table cell is retained', () {
    final document = _document();
    (document.sections.first.blocks.first as WmlParagraph).inlines.add(
      WmlBookmarkBoundary(id: '9', isStart: true, name: 'AroundTable'),
    );
    (document.sections.first.blocks.last as WmlParagraph).inlines.add(
      WmlBookmarkBoundary(id: '9', isStart: false),
    );
    _refuses(document);
  });

  test(
    'cross-paragraph field enclosing a table cell refuses text flattening',
    () {
      final document = _document();
      (document.sections.first.blocks.first as WmlParagraph).inlines.add(
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
      );
      (document.sections.first.blocks.last as WmlParagraph).inlines.add(
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
      );
      _refuses(document);
    },
  );

  test(
    'native comment spanning an empty cell remains protected without model runs',
    () {
      final document = _native(
        (xml) => xml
            .replaceFirst('First 0/0', '')
            .replaceFirst(
              '</w:p><w:tbl>',
              '<w:commentRangeStart w:id="8"/></w:p><w:tbl>',
            )
            .replaceFirst(
              '</w:tbl><w:p>',
              '</w:tbl><w:p><w:commentRangeEnd w:id="8"/>',
            ),
      );
      final target = _target(document)..inlines.clear();
      _refuses(document, target: target);
      expect(target.inlines, isEmpty);
    },
  );

  test(
    'native field spanning an empty cell remains protected without model runs',
    () {
      final document = _native(
        (xml) => xml
            .replaceFirst('First 0/0', '')
            .replaceFirst(
              '</w:p><w:tbl>',
              '<w:r><w:fldChar w:fldCharType="begin"/></w:r></w:p><w:tbl>',
            )
            .replaceFirst(
              '</w:tbl><w:p>',
              '</w:tbl><w:p><w:r><w:fldChar w:fldCharType="end"/></w:r>',
            ),
      );
      final target = _target(document)..inlines.clear();
      _refuses(document, target: target);
      expect(target.inlines, isEmpty);
    },
  );

  for (final entry in <(String, String Function(String))>[
    (
      'vertical alignment',
      (xml) =>
          xml.replaceFirst('</w:tcPr>', '<w:vAlign w:val="center"/></w:tcPr>'),
    ),
    (
      'cell margin override',
      (xml) => xml.replaceFirst(
        '</w:tcPr>',
        '<w:tcMar><w:left w:w="200" w:type="dxa"/></w:tcMar></w:tcPr>',
      ),
    ),
    (
      'exact row height',
      (xml) => xml.replaceFirst('w:hRule="atLeast"', 'w:hRule="exact"'),
    ),
    (
      'repeating header row',
      (xml) => xml.replaceFirst('</w:trPr>', '<w:tblHeader/></w:trPr>'),
    ),
    (
      'foreign cell metadata',
      (xml) => xml.replaceFirst(
        '</w:tcPr>',
        '<x:keep xmlns:x="urn:cell-test"/></w:tcPr>',
      ),
    ),
    (
      'row attribute',
      (xml) => xml
          .replaceFirst('<w:tr>', '<w:tr w:rsidR="ABCD"/>')
          .replaceFirst('/><w:trPr>', '><w:trPr>'),
    ),
    (
      'patterned background',
      (xml) => xml.replaceFirst('w:val="clear"', 'w:val="pct20"'),
    ),
    (
      'run control marker',
      (xml) => xml.replaceFirst('First 0/0</w:t>', 'First 0/0</w:t><w:br/>'),
    ),
    (
      'alternate table markup',
      (xml) => xml
          .replaceFirst(
            '<w:tbl>',
            '<mc:AlternateContent xmlns:mc="${OfficeNamespaces.mc}"><mc:Choice Requires="w"><w:tbl>',
          )
          .replaceFirst(
            '</w:tbl>',
            '</w:tbl></mc:Choice><mc:Fallback/></mc:AlternateContent>',
          ),
    ),
  ]) {
    test(
      'unpreserved source ${entry.$1} rejects before live or package mutation',
      () {
        final document = _native(entry.$2);
        _refuses(document);
      },
    );
  }

  test(
    'pending structural changes require synchronized native table identity',
    () {
      final document = WordDeserializer().readBytes(_bytes());
      document.sections.last.blocks.add(_table('New after import'));
      _refuses(document);
    },
  );

  test('legacy tableCellText continues replacing the entire cell story', () {
    final document = _document();
    final cell = _tables(document).first.rows.first.cells.first;
    cell.blocks.add(_paragraph('Second paragraph'));
    native.applyStep(document, {..._step(), 'op': 'tableCellText'});
    expect(cell.blocks, hasLength(1));
    final paragraph = cell.blocks.single as WmlParagraph;
    expect(paragraph.text, 'Replacement');
    expect(paragraph.properties.justification, WmlJustification.left);
    expect((paragraph.inlines.single as WmlRun).properties.italic, isFalse);
  });

  test(
    'native session validates, records and replays serialized cell writes',
    () async {
      final source = _bytes();
      final session = OfficeMacroSession(
        source,
        format: OfficeMacroFormat.docx,
      );
      final plan = OfficeMacro(
        name: 'Fill template',
        format: OfficeMacroFormat.docx,
        steps: [
          OfficeMacroStep(
            tool: 'docx.tableCellRangeText',
            arguments: {
              'table': 0,
              'row': 0,
              'column': 1,
              'text': 'First update',
            },
          ),
          OfficeMacroStep(
            tool: 'docx.tableCellRangeText',
            arguments: {
              'table': 1,
              'row': 1,
              'column': 0,
              'text': 'Second update',
            },
          ),
        ],
      );
      session.startRecording('Cell writes');
      final validation = await session.validate(plan);
      expect(validation.validatedOnly, isTrue);
      expect(session.bytes, source);
      expect(session.revision, 0);
      await session.run(plan);
      expect(session.revision, 1);
      final reopened = WordDeserializer().readBytes(session.bytes);
      expect(_target(reopened, column: 1).text, 'First update');
      expect(_target(reopened, table: 1, row: 1).text, 'Second update');
      final recording = session.stopRecording();
      expect(
        recording.steps,
        isEmpty,
        reason: 'Macro playback is not recorded.',
      );
      session.startRecording('Explicit cell tool calls');
      for (final step in plan.steps) {
        await session.callTool(step.tool, step.arguments);
      }
      final toolRecording = session.stopRecording();
      expect(toolRecording.steps, hasLength(2));
      final replay = OfficeMacroSession(source, format: OfficeMacroFormat.docx);
      await replay.run(
        OfficeMacro.fromJson(
          jsonDecode(jsonEncode(toolRecording.toJson()))
              as Map<String, Object?>,
        ),
      );
      expect(
        _target(WordDeserializer().readBytes(replay.bytes), column: 1).text,
        'First update',
      );
    },
  );

  test(
    'late native refusal rolls back earlier writes and records nothing',
    () async {
      final document = _document();
      _tables(
        document,
      ).last.rows.last.cells.last.blocks.add(_paragraph('Second paragraph'));
      final source = WordSerializer().writeBytes(document);
      final session = OfficeMacroSession(
        source,
        format: OfficeMacroFormat.docx,
      );
      session.startRecording('Atomic cells');
      final plan = OfficeMacro(
        name: 'Refuse second cell',
        format: OfficeMacroFormat.docx,
        steps: [
          OfficeMacroStep(
            tool: 'docx.tableCellRangeText',
            arguments: {
              'table': 0,
              'row': 0,
              'column': 0,
              'text': 'Must roll back',
            },
          ),
          OfficeMacroStep(
            tool: 'docx.tableCellRangeText',
            arguments: {'table': 1, 'row': 1, 'column': 1, 'text': 'Refuse'},
          ),
        ],
      );
      await expectLater(
        session.run(plan),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, source);
      expect(session.revision, 0);
      expect(session.stopRecording().steps, isEmpty);
    },
  );
}
