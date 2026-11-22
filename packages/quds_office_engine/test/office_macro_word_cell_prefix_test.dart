import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _tool = 'docx.tableCellRangeInsertBefore';

WmlParagraph _paragraph(String text) => WmlParagraph(
  properties: WmlParagraphProps(
    justification: WmlJustification.center,
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

WmlTable _table(String name) => WmlTable(
  grid: [80, 90],
  properties: WmlTableProps(cellMargin: 6),
  rows: [
    for (var row = 0; row < 2; row++)
      WmlTableRow(
        cantSplit: true,
        cells: [
          for (var column = 0; column < 2; column++)
            WmlTableCell(
              width: column == 0 ? 80 : 90,
              blocks: [_paragraph('$name $row/$column')],
            ),
        ],
      ),
  ],
);

WmlDocument _document() {
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [_paragraph('Before'), _table('First'), _paragraph('Between')],
        header: [_paragraph('Header')],
      ),
      WmlSection(blocks: [_table('Second'), _paragraph('After')]),
    ],
  );
  _target(document).inlines = [
    WmlRun(
      text: 'Alpha',
      properties: WmlRunProps(
        italic: true,
        color: '123456',
        fontSizeHalfPoints: 28,
      ),
    ),
    WmlRun(
      text: ' Beta',
      properties: WmlRunProps(bold: true, color: 'ABCDEF'),
    ),
  ];
  return document;
}

List<WmlTable> _tables(WmlDocument document) => [
  for (final section in document.sections)
    ...section.blocks.whereType<WmlTable>(),
];

WmlParagraph _target(
  WmlDocument document, {
  int table = 0,
  int row = 0,
  int column = 0,
}) =>
    _tables(document)[table].rows[row].cells[column].blocks.first
        as WmlParagraph;

Map<String, Object?> _arguments({
  Object? table = 0,
  Object? row = 0,
  Object? column = 0,
  Object? text = 'Label: ',
}) => {'table': table, 'row': row, 'column': column, 'text': text};

void _apply(WmlDocument document, [Map<String, Object?>? arguments]) =>
    OfficeOperationCatalog.apply(document, _tool, arguments ?? _arguments());

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

WmlDocument _native(String Function(String) edit) {
  final package = OpcPackage.openBytes(_bytes());
  final part = package.getPart('/word/document.xml')!;
  part.writeText(edit(part.readText()));
  return WordDeserializer().read(package);
}

void _refuses(
  WmlDocument document, {
  Map<String, Object?>? arguments,
  Matcher matcher = throwsUnsupportedError,
  bool publicCatalog = false,
}) {
  final paragraph = _target(document);
  final inlines = paragraph.inlines;
  final properties = paragraph.properties;
  final text = paragraph.text;
  final parts = <String, Uint8List>{
    if (document.package case final package?)
      for (final part in package.parts)
        part.uri: package.getPart(part.uri)!.readBytes(),
  };
  expect(
    () => publicCatalog
        ? _apply(document, arguments)
        : native.applyStep(document, {
            'op': 'tableCellRangeInsertBefore',
            ...arguments ?? _arguments(),
          }),
    matcher,
  );
  expect(paragraph.inlines, same(inlines));
  expect(paragraph.properties, same(properties));
  expect(paragraph.text, text);
  if (document.package case final package?) {
    expect({
      for (final part in package.parts)
        part.uri: package.getPart(part.uri)!.readBytes(),
    }, parts);
  }
}

OfficeMacro _plan(List<Map<String, Object?>> arguments) => OfficeMacro(
  name: 'Cell prefixes',
  format: OfficeMacroFormat.docx,
  steps: [
    for (final item in arguments) OfficeMacroStep(tool: _tool, arguments: item),
  ],
);

void main() {
  for (final prefix in ['Label: ', '  A\tB  ', 'é😀 العربية <&>']) {
    test('$prefix retains all existing text and distinct run formatting', () {
      var document = WordDeserializer().readBytes(_bytes());
      final target = _target(document);
      final table = _tables(document).first;
      final cell = table.rows.first.cells.first;
      final properties = target.properties;
      _apply(document, _arguments(text: prefix));
      expect(cell.blocks.single, same(target));
      expect(target.properties, same(properties));
      expect(_tables(document).first, same(table));
      expect(table.rows.first.cells.first, same(cell));
      for (var cycle = 0; cycle < 3; cycle++) {
        final selected = _target(document);
        expect(selected.text, '${prefix}Alpha Beta');
        final first = WmlRunEdit.propsAt(selected, 0);
        final retainedFirst = WmlRunEdit.propsAt(selected, prefix.length + 1);
        final retainedLast = WmlRunEdit.propsAt(selected, prefix.length + 6);
        expect(first.italic, isTrue);
        expect(first.color, '123456');
        expect(first.fontSizeHalfPoints, 28);
        expect(retainedFirst.italic, isTrue);
        expect(retainedFirst.bold, isFalse);
        expect(retainedFirst.color, '123456');
        expect(retainedLast.bold, isTrue);
        expect(retainedLast.italic, isFalse);
        expect(retainedLast.color, 'ABCDEF');
        expect(selected.properties.justification, WmlJustification.center);
        expect(selected.properties.spacingAfter, 6);
        expect(_tables(document).first.grid, [80, 90]);
        expect(_tables(document).first.properties.cellMargin, 6);
        expect(_target(document, column: 1).text, 'First 0/1');
        expect(_target(document, table: 1).text, 'Second 0/0');
        expect(document.sections.first.header.single.text, 'Header');
        final saved = WordSerializer().writeBytes(document);
        expect(
          OpcPackage.openBytes(
            saved,
          ).getPart('/word/vbaProject.bin')!.readBytes(),
          [0, 1, 7, 255, 48, 66],
        );
        document = WordDeserializer().readBytes(saved);
      }
    });
  }

  test('successive calls prefix current text in operation order', () {
    final document = _document();
    _apply(document, _arguments(text: 'first: '));
    _apply(document, _arguments(text: 'second: '));
    expect(_target(document).text, 'second: first: Alpha Beta');
    _apply(document, _arguments(table: 1, row: 1, column: 1, text: 'Other: '));
    expect(
      _target(document, table: 1, row: 1, column: 1).text,
      'Other: Second 1/1',
    );
    expect(_target(document, row: 1, column: 1).text, 'First 1/1');
    expect(
      (document.sections.first.blocks.first as WmlParagraph).text,
      'Before',
    );
  });

  for (final emptyRuns in [false, true]) {
    test('empty prefix preserves ${emptyRuns ? 'empty' : 'rich'} inlines', () {
      final document = _document();
      final target = _target(document);
      if (emptyRuns) target.inlines.clear();
      final inlines = target.inlines;
      final members = List<WmlInline>.of(inlines);
      final properties = target.properties;
      _apply(document, _arguments(text: ''));
      expect(target.inlines, same(inlines));
      expect(target.inlines, members);
      for (var index = 0; index < members.length; index++) {
        expect(target.inlines[index], same(members[index]));
      }
      expect(target.properties, same(properties));
    });
  }

  test('empty prefix still rejects nonexistent and malformed targets', () {
    _refuses(
      _document(),
      arguments: _arguments(table: 2, text: ''),
      matcher: throwsArgumentError,
    );
    final document = _document();
    _tables(document).first.rows.first.cells.first.gridSpan = 2;
    _refuses(document, arguments: _arguments(text: ''));
  });

  for (final retainedRun in [false, true]) {
    test(
      'empty cell inherits ${retainedRun ? 'run' : 'paragraph mark'} style',
      () {
        final document = _document();
        final target = _target(document)..inlines.clear();
        final style = WmlRunProps(bold: true, color: '654321');
        if (retainedRun) {
          target.inlines.add(WmlRun(properties: style));
        } else {
          target.properties.importedParagraphMark = style;
        }
        _apply(document, _arguments(text: 'Fresh'));
        final runs = target.inlines.whereType<WmlRun>().toList();
        expect(runs, hasLength(retainedRun ? 2 : 1));
        final run = runs.first;
        expect(run.text, 'Fresh');
        expect(run.properties.bold, isTrue);
        expect(run.properties.color, '654321');
        expect(run.properties, isNot(same(style)));
        if (retainedRun) {
          expect(runs.last.text, isEmpty);
          expect(runs.last.properties.color, '654321');
        }
        final reopened = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        expect(_target(reopened).text, 'Fresh');
        expect(WmlRunEdit.propsAt(_target(reopened), 0).color, '654321');
      },
    );
  }

  test(
    'unformatted empty cell accepts a prefix without adding a paragraph',
    () {
      final document = _document();
      final target = _target(document)..inlines.clear();
      _apply(document);
      expect(_tables(document).first.rows.first.cells.first.blocks, [target]);
      expect(target.text, 'Label: ');
    },
  );

  test('prefix copies shared property objects without leaking later edits', () {
    final document = _document();
    final target = _target(document);
    final neighbor = _target(document, column: 1);
    final shared = (target.inlines.first as WmlRun).properties;
    (neighbor.inlines.single as WmlRun).properties = shared;
    _apply(document);
    final inserted = (target.inlines.first as WmlRun).properties;
    expect(inserted, isNot(same(shared)));
    inserted.color = 'FFFFFF';
    expect(shared.color, '123456');
    expect(WmlRunEdit.propsAt(neighbor, 0).color, '123456');
    expect(neighbor.text, 'First 0/1');
  });

  test('prefix never coalesces original runs that differ only in kerning', () {
    var document = _document();
    _target(document).inlines = [
      WmlRun(text: 'A', properties: WmlRunProps(kerningHalfPoints: 0)),
      WmlRun(text: 'B', properties: WmlRunProps(kerningHalfPoints: 24)),
    ];
    _apply(document, _arguments(text: 'Prefix: '));
    expect(_target(document).inlines, hasLength(3));
    for (var cycle = 0; cycle < 3; cycle++) {
      final target = _target(document);
      expect(target.text, 'Prefix: AB');
      expect(WmlRunEdit.propsAt(target, 0).kerningHalfPoints, 0);
      expect(WmlRunEdit.propsAt(target, 8).kerningHalfPoints, 0);
      expect(WmlRunEdit.propsAt(target, 9).kerningHalfPoints, 24);
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
    }
  });

  test('prefix preserves distinct zero-width native run metadata', () {
    var document = _native((xml) {
      final start = xml.indexOf('<w:tbl>');
      return (xml.substring(0, start) +
              xml
                  .substring(start)
                  .replaceFirst(
                    '<w:r>',
                    '<w:r><w:rPr><x:keep x:value="empty-retained"/></w:rPr>'
                        '<w:t/></w:r><w:r>',
                  ))
          .replaceFirst(
            '<w:document ',
            '<w:document xmlns:x="urn:prefix-empty-test" ',
          );
    });
    for (var cycle = 0; cycle < 3; cycle++) {
      _apply(document, _arguments(text: '[$cycle]'));
      final runs = _target(document).inlines.whereType<WmlRun>().toList();
      final empty = runs.where((run) => run.text.isEmpty).single;
      expect(empty.properties.sourcePropertiesXml, contains('empty-retained'));
      expect(
        runs.first.properties.sourcePropertiesXml,
        isNot(contains('empty-retained')),
      );
      final bytes = WordSerializer().writeBytes(document);
      final xml = OpcPackage.openBytes(
        bytes,
      ).getPart('/word/document.xml')!.readText();
      expect(RegExp('empty-retained').allMatches(xml), hasLength(1));
      document = WordDeserializer().readBytes(bytes);
    }
    expect(_target(document).text, '[2][1][0]Alpha Beta');
  });

  test('a multilingual prefix preserves the existing text run boundaries', () {
    var document = _document();
    final target = _target(document);
    final first = target.inlines.first as WmlRun;
    first.properties.proofingLanguage = 'en-US';
    first.properties.complexScriptLanguage = 'ar-SA';
    _apply(document, _arguments(text: 'العربية: '));
    for (var cycle = 0; cycle < 3; cycle++) {
      final runs = _target(document).inlines.whereType<WmlRun>().toList();
      expect(runs.map((run) => run.text), ['العربية: ', 'Alpha', ' Beta']);
      expect(runs[1].properties.proofingLanguage, 'en-US');
      expect(runs[1].properties.complexScriptLanguage, 'ar-SA');
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
    }
  });

  test(
    'native namespace aliases and sparse paragraph/run metadata survive',
    () {
      var document = _native((xml) {
        final firstTable = xml.indexOf('<w:tbl>');
        final before = xml.substring(0, firstTable);
        final tableAndTail = xml
            .substring(firstTable)
            .replaceFirst(
              '<w:pPr>',
              '<w:pPr><x:keep x:value="paragraph-retained"/>',
            )
            .replaceFirst('<w:rPr>', '<w:rPr><x:keep x:value="run-retained"/>');
        return '$before$tableAndTail'
            .replaceFirst(
              '<w:document ',
              '<w:document xmlns:x="urn:prefix-test" ',
            )
            .replaceAll('w:', 'q:')
            .replaceFirst('xmlns:w=', 'xmlns:q=');
      });
      for (var cycle = 0; cycle < 3; cycle++) {
        _apply(document, _arguments(text: '[$cycle]'));
        final bytes = WordSerializer().writeBytes(document);
        final xml = OpcPackage.openBytes(
          bytes,
        ).getPart('/word/document.xml')!.readText();
        expect(xml, contains('paragraph-retained'));
        expect(xml, contains('run-retained'));
        expect(xml, contains('urn:prefix-test'));
        document = WordDeserializer().readBytes(bytes);
      }
      expect(_target(document).text, '[2][1][0]Alpha Beta');
      expect(WmlRunEdit.propsAt(_target(document), 15).color, 'ABCDEF');
    },
  );

  for (final (label, arguments) in <(String, Map<String, Object?>)>[
    ('negative table', _arguments(table: -1)),
    ('fractional table', _arguments(table: 0.5)),
    ('string row', _arguments(row: '0')),
    ('Boolean column', _arguments(column: false)),
    ('missing table', _arguments()..remove('table')),
    ('missing row', _arguments()..remove('row')),
    ('missing column', _arguments()..remove('column')),
    ('missing text', _arguments()..remove('text')),
    ('non-string text', _arguments(text: 42)),
    ('table out of range', _arguments(table: 2)),
    ('row out of range', _arguments(row: 2)),
    ('column out of range', _arguments(column: 2)),
    ('body story alias', {..._arguments(), 'story': 'body'}),
    ('paragraph projection', {..._arguments(), 'paragraph': 0}),
    ('arbitrary start', {..._arguments(), 'start': 0}),
    ('arbitrary end', {..._arguments(), 'end': 1}),
  ]) {
    test('$label refuses before native mutation', () {
      _refuses(_document(), arguments: arguments, matcher: throwsArgumentError);
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
    test('structural or malformed prefix ${text.codeUnits} is refused', () {
      _refuses(
        _document(),
        arguments: _arguments(text: text),
        matcher: throwsArgumentError,
      );
    });
  }

  for (final (label, change) in <(String, void Function(WmlDocument))>[
    (
      'merged cell',
      (d) => _tables(d).first.rows.first.cells.first.gridSpan = 2,
    ),
    ('ragged grid', (d) => _tables(d).first.rows.last.cells.removeLast()),
    (
      'nested table',
      (d) => _tables(d).last.rows.last.cells.last.blocks.add(_table('Nested')),
    ),
    (
      'multiple paragraphs',
      (d) => _tables(
        d,
      ).first.rows.first.cells.first.blocks.add(_paragraph('Second paragraph')),
    ),
    (
      'field result',
      (d) => (_target(d).inlines.first as WmlRun).fieldInstruction = 'PAGE',
    ),
    (
      'hyperlink',
      (d) => (_target(d).inlines.first as WmlRun).hyperlink =
          const WmlHyperlink(url: 'https://example.com'),
    ),
    (
      'comment anchor',
      (d) => (_target(d).inlines.first as WmlRun).commentIds.add(7),
    ),
    ('note mark', (d) => (_target(d).inlines.first as WmlRun).noteRefId = 2),
    ('bookmark', (d) => _target(d).properties.bookmarkName = 'Retain'),
    ('restricted document', (d) => d.restrictEditing = true),
    ('formatting protection', (d) => d.protectionFormattingRestricted = true),
    ('revision tracking', (d) => d.trackRevisions = true),
  ]) {
    test('$label retains the existing cell admission guard', () {
      final document = _document();
      change(document);
      _refuses(document);
    });
  }

  for (final cyclic in [false, true]) {
    test(
      'public catalog refuses ${cyclic ? 'cyclic' : 'shared'} ownership',
      () {
        final document = _document();
        final table = _tables(document).first;
        if (cyclic) {
          table.rows.last.cells.last.blocks.add(table);
        } else {
          table.rows.last.cells[1] = table.rows.first.cells.first;
        }
        _refuses(document, publicCatalog: true);
      },
    );
  }

  test(
    'shared paragraph across stories is refused before catalog admission',
    () {
      final document = _document();
      document.sections.first.header.add(_target(document));
      _refuses(document, publicCatalog: true);
    },
  );

  test(
    'unsupported neighboring native cell packets still prevent insertion',
    () {
      final document = _native(
        (xml) => xml.replaceFirst(
          '</w:tcPr>',
          '<w:vAlign w:val="center"/></w:tcPr>',
        ),
      );
      _refuses(document, arguments: _arguments(table: 1));
    },
  );

  test('native run control markers cannot become ordinary prefix text', () {
    final document = _native(
      (xml) => xml.replaceFirst('Alpha</w:t>', 'Alpha</w:t><w:br/>'),
    );
    _refuses(document);
  });

  test('native property history is refused before prefix mutation', () {
    final document = _native((xml) {
      final start = xml.indexOf('<w:tbl>');
      return xml.substring(0, start) +
          xml.substring(start).replaceFirst('<w:rPr>', '<w:rPr><w:rPrChange/>');
    });
    _refuses(document);
  });

  test(
    'native session validates without publication and records/replays prefixes',
    () async {
      final input = _bytes();
      final plan = _plan([
        _arguments(text: 'First: '),
        _arguments(text: 'Second: '),
        _arguments(table: 1, row: 1, column: 1, text: 'Remote: '),
      ]);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final validation = await session.validate(plan);
      expect(validation.validatedOnly, isTrue);
      expect(session.bytes, input);
      expect(session.revision, 0);
      await session.run(plan);
      expect(session.revision, 1);
      final output = WordDeserializer().readBytes(session.bytes);
      expect(_target(output).text, 'Second: First: Alpha Beta');
      expect(
        _target(output, table: 1, row: 1, column: 1).text,
        'Remote: Second 1/1',
      );

      final recording = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
      )..startRecording('Reusable cell prefixes');
      for (final step in plan.steps) {
        await recording.callTool(step.tool, step.arguments);
      }
      final recorded = recording.stopRecording();
      expect(recorded.steps, hasLength(3));
      final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await replay.run(
        OfficeMacro.fromJson(
          jsonDecode(jsonEncode(recorded.toJson())) as Map<String, Object?>,
        ),
      );
      expect(
        _target(WordDeserializer().readBytes(replay.bytes)).text,
        'Second: First: Alpha Beta',
      );
    },
  );

  test(
    'a later invalid cell discards earlier prefixes during validation and run',
    () async {
      final document = _document();
      _tables(document).last.rows.last.cells.last.blocks.add(
        _paragraph('Unsupported second paragraph'),
      );
      final input = WordSerializer().writeBytes(document);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('Atomic prefix attempt');
      final plan = _plan([
        _arguments(text: 'Discard me: '),
        _arguments(table: 1, row: 1, column: 1),
      ]);
      for (final action in [session.validate, session.run]) {
        await expectLater(action(plan), throwsA(isA<OfficeMacroException>()));
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  for (final (label, policy) in [
    ('mutation denied', OfficeMacroPolicy(allowMutation: false)),
    (
      'tool allowlist',
      OfficeMacroPolicy(allowedTools: {'docx.tableCellRangeText'}),
    ),
    ('step budget', OfficeMacroPolicy(maxSteps: 1)),
  ]) {
    test('$label applies to the new native operation', () async {
      final input = _bytes();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: policy,
      );
      await expectLater(
        session.run(_plan([_arguments(), _arguments()])),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    });
  }

  test('pre-cancelled prefix plans cannot publish', () async {
    final input = _bytes();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    await expectLater(
      session.run(
        _plan([_arguments()]),
        cancellation: OfficeMacroCancellation()..cancel(),
      ),
      throwsA(isA<OfficeMacroException>()),
    );
    expect(session.bytes, input);
    expect(session.revision, 0);
  });
}
