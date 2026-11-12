// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/decorated_word_fixture.dart';
import 'support/story_word_fixture.dart';
import 'support/structured_word_fixture.dart';
import 'support/table_review_fixture.dart';
import 'support/table_width_fixture.dart';
import 'support/table_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

List<int> _condition(int code, int mask, List<int> properties) =>
    wordSprm(code, [properties.length + 2, ...wordU16(mask), ...properties]);

/// Old-state controls contain their own literal header instructions. They do
/// not derive expected child formatting by projecting the converter's XML.
Uint8List _source({
  List<bool> current = const [true, false],
  List<bool> previous = const [true, true],
  bool review = true,
  bool oldState = false,
  bool inherited = false,
  bool cellRule = false,
  bool banding = false,
  bool conditional = true,
  bool heightOnly = false,
  bool unusedConditionalStyle = false,
}) {
  final character = cellRule
      ? <int>[]
      : !conditional
      ? wordSprm(0x0835, [1])
      : banding
      ? [
          ..._condition(0xca85, 0x40, wordSprm(0x0835, [0])),
          ..._condition(0xca85, 0x80, wordSprm(0x0835, [1])),
        ]
      : _condition(0xca85, 1, wordSprm(0x0835, [1]));
  final cell = cellRule
      ? _condition(0xd66a, 1, [
          ...wordSprm(0xd687, [10, ...wordShading(background: 0xff)]),
        ])
      : <int>[];
  WordFixtureStyle style(int parent, bool rules) => WordFixtureStyle(
    name: 'Row review style',
    table: true,
    parentIndex: parent,
    tableProperties: rules ? cell : const [],
    characterProperties: rules ? character : const [],
  );
  return tableFixture(
    [
      for (var row = 0; row < current.length; row++) ...[
        TableFixtureParagraph('ROW$row\x07', depth: 1),
        TableFixtureParagraph(
          '\x07',
          depth: 1,
          row: true,
          widths: const [2000],
          extra: [
            ...wordSprm(0x563a, wordU16(20)),
            ...wordSprm(0x740a, [...wordU16(0), ...wordU16(0x20)]),
            if (review &&
                (current[row] != previous[row] ||
                    (heightOnly && row == 1))) ...[
              ...rowReviewProperties(height: 240, header: previous[row]),
              ...wordSprm(0x3668, [1]),
              ...rowReviewProperties(height: 720, header: current[row]),
              ...rowReviewMark(),
            ] else
              ...rowReviewProperties(
                height: oldState ? 240 : 720,
                header: oldState ? previous[row] : current[row],
              ),
          ],
        ),
      ],
    ],
    styles: {
      0: const WordFixtureStyle(name: 'Normal'),
      20: style(inherited ? 21 : 0xfff, !inherited),
      if (inherited) 21: style(0xfff, true),
      if (unusedConditionalStyle)
        22: WordFixtureStyle(
          name: 'Unused conditional style',
          table: true,
          characterProperties: _condition(0xca85, 1, wordSprm(0x0835, [1])),
        ),
    },
    extraTablePairs: {
      51: storyBookmarkNames(['Unknown', 'Alice']),
    },
  );
}

List<LegacyWordTableRow> _rows(LegacyWordDocument document) =>
    document.blocks.whereType<LegacyWordTable>().single.rows;

Map<String, Uint8List> _parts(LegacyWordDocument document) => {
  for (final file in ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  ))
    if (file.isFile) file.name: file.content,
};

XmlDocument _xml(LegacyWordDocument document) =>
    XmlDocument.parse(utf8.decode(_parts(document)['word/document.xml']!));

List<Map<String, dynamic>> _evidence(LegacyWordDocument document) {
  final parts = _parts(document);
  return ((jsonDecode(utf8.decode(parts['word/evidence/manifest.json']!))
              as Map<String, dynamic>)['records']
          as List)
      .cast<Map<String, dynamic>>()
      .where((record) => record['kind'] == 'tableRowFormattingRevision')
      .toList();
}

void _expectInert(LegacyWordDocument document, List<int> changedRows) {
  final rows = _rows(document);
  for (final index in changedRows) {
    final change = rows[index].formattingRevision!;
    expect(change.conditionalFormattingMayChange, isTrue);
    expect(change.previousPropertiesComplete, isTrue);
    expect(change.unsupportedPropertyCodes, isEmpty);
    expect(change.revision.author, 'Alice');
  }
  expect(
    document.warnings,
    contains(LegacyWordWarning.revisionMetadataIncomplete),
  );
  final converted = convertLegacyWordDocument(document);
  expect(
    converted.limitations,
    contains(LegacyWordConversionLimitation.revisions),
  );
  expect(converted.preservedCounts['tableRowFormattingRevisions'], isNull);
  final xml = _xml(document);
  for (final name in ['trPrChange', 'rPrChange', 'pPrChange']) {
    expect(xml.findAllElements(name, namespace: _w), isEmpty);
  }
  final evidence = _evidence(document);
  expect(evidence.map((record) => record['rowIndex']), changedRows);
  for (final record in evidence) {
    expect(record['conditionalFormattingMayChange'], isTrue);
    expect(record['reason'], contains('downstream header-prefix/banding'));
    expect(record['previousProperties'], isNotNull);
  }
}

void main() {
  for (final inherited in [false, true]) {
    test(
      '${inherited ? 'inherited' : 'direct'} conditional text defeats a header-only rejection',
      () {
        final review = parseLegacyWordDocument(_source(inherited: inherited));
        final rejected = parseLegacyWordDocument(
          _source(inherited: inherited, review: false, oldState: true),
        );
        expect(
          _rows(
            review,
          )[1].cells.single.paragraphs.single.runs.single.style.bold,
          isFalse,
        );
        expect(
          _rows(
            rejected,
          )[1].cells.single.paragraphs.single.runs.single.style.bold,
          isTrue,
        );
        final currentXml = _xml(
          review,
        ).findAllElements('tr', namespace: _w).last;
        expect(
          currentXml
              .findAllElements('b', namespace: _w)
              .map((node) => node.getAttribute('val', namespace: _w)),
          everyElement('0'),
        );
        _expectInert(review, [1]);
      },
    );

    test(
      '${inherited ? 'inherited' : 'direct'} conditional cell formatting retains history as evidence',
      () {
        final review = parseLegacyWordDocument(
          _source(inherited: inherited, cellRule: true),
        );
        final rejected = parseLegacyWordDocument(
          _source(
            inherited: inherited,
            cellRule: true,
            review: false,
            oldState: true,
          ),
        );
        expect(
          _rows(review)[1].cells.single.shading?.backgroundHex,
          isNot('FF0000'),
        );
        expect(
          _rows(rejected)[1].cells.single.shading?.backgroundHex,
          'FF0000',
        );
        _expectInert(review, [1]);
      },
    );
  }

  test('an earlier header edit changes a downstream dormant header style', () {
    final review = parseLegacyWordDocument(
      _source(current: [false, true], previous: [true, true]),
    );
    final rejected = parseLegacyWordDocument(
      _source(
        current: [false, true],
        previous: [true, true],
        review: false,
        oldState: true,
      ),
    );
    expect(_rows(review).map((row) => row.isHeader), [false, false]);
    expect(_rows(rejected).map((row) => row.isHeader), [true, true]);
    expect(
      _rows(review)[1].cells.single.paragraphs.single.runs.single.style.bold,
      isFalse,
    );
    expect(
      _rows(rejected)[1].cells.single.paragraphs.single.runs.single.style.bold,
      isTrue,
    );
    _expectInert(review, [0]);
  });

  test('a header edit changes banding on a later ordinary row', () {
    final review = parseLegacyWordDocument(
      _source(
        current: [true, false, false],
        previous: [true, true, false],
        banding: true,
      ),
    );
    final rejected = parseLegacyWordDocument(
      _source(
        current: [true, false, false],
        previous: [true, true, false],
        banding: true,
        review: false,
        oldState: true,
      ),
    );
    expect(
      _rows(review)[2].cells.single.paragraphs.single.runs.single.style.bold,
      isTrue,
    );
    expect(
      _rows(rejected)[2].cells.single.paragraphs.single.runs.single.style.bold,
      isFalse,
    );
    _expectInert(review, [1]);
  });

  test(
    'independent dormant header edits cannot evade the conservative guard',
    () {
      final review = parseLegacyWordDocument(
        _source(current: [false, false], previous: [true, true]),
      );
      _expectInert(review, [0, 1]);
    },
  );

  test('nonconditional used styles retain native header history', () {
    final document = parseLegacyWordDocument(
      _source(conditional: false, unusedConditionalStyle: true),
    );
    expect(
      _rows(document)[1].formattingRevision!.conditionalFormattingMayChange,
      isFalse,
    );
    expect(
      document.warnings,
      isNot(contains(LegacyWordWarning.revisionMetadataIncomplete)),
    );
    expect(
      _xml(document).findAllElements('trPrChange', namespace: _w),
      hasLength(1),
    );
  });

  test(
    'unchanged header instructions keep conditional-style height revisions native',
    () {
      final document = parseLegacyWordDocument(
        _source(
          current: [true, true],
          previous: [true, true],
          heightOnly: true,
        ),
      );
      expect(
        _rows(document)[1].formattingRevision!.conditionalFormattingMayChange,
        isFalse,
      );
      expect(
        _xml(document).findAllElements('trPrChange', namespace: _w),
        hasLength(1),
      );
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.revisionMetadataIncomplete)),
      );
    },
  );

  test('the public-model writer independently checks conditional ancestry', () {
    final parsed = parseLegacyWordDocument(_source(inherited: true));
    final table = parsed.blocks.single as LegacyWordTable;
    final document = LegacyWordDocument(
      blocks: [
        LegacyWordTable(
          startCp: table.startCp,
          endCp: table.endCp,
          rows: [
            for (final row in table.rows)
              LegacyWordTableRow(
                cells: row.cells,
                isHeader: row.isHeader,
                sourceHeaderRequest: row.sourceHeaderRequest,
                tableStyleId: row.tableStyleId,
                styleOptions: row.styleOptions,
                heightTwips: row.heightTwips,
                formattingRevision: row.formattingRevision == null
                    ? null
                    : LegacyWordTableRowFormattingRevision(
                        previousProperties:
                            row.formattingRevision!.previousProperties,
                        revision: row.formattingRevision!.revision,
                      ),
              ),
          ],
        ),
      ],
      sections: parsed.sections,
      plainText: parsed.plainText,
      safeHtml: parsed.safeHtml,
      tableStyles: parsed.tableStyles,
    );
    expect(
      _rows(document)[1].formattingRevision!.conditionalFormattingMayChange,
      isFalse,
    );
    expect(
      _xml(document).findAllElements('trPrChange', namespace: _w),
      isEmpty,
    );
    expect(
      _evidence(document).single['conditionalFormattingMayChange'],
      isTrue,
    );
    expect(
      convertLegacyWordDocument(document).limitations,
      contains(LegacyWordConversionLimitation.revisions),
    );
  });

  test(
    'pre-wall preferred width survives a safe row revision and paragraph style reset',
    () {
      final document = parseLegacyWordDocument(
        tableReviewFixture([
          (
            'CELL',
            [
              ...tablePreferredWidth(0, 1, 3, 1200),
              ...rowReviewProperties(height: 240),
              ...wordSprm(0x3668, [1]),
              ...wordSprm(0x4600, wordU16(0)),
              ...rowReviewProperties(height: 720),
              ...rowReviewMark(),
            ],
          ),
        ]),
      );
      final row = _rows(document).single;
      expect(row.formattingRevision!.previousProperties!.heightTwips, 240);
      expect(row.cells.single.formatting.preferredWidth!.value, 1200);
      expect(
        _xml(document).findAllElements('trPrChange', namespace: _w),
        hasLength(1),
      );
    },
  );

  for (final operation in [
    tablePreferredWidth(0, 1, 3, 1200),
    wordSprm(0xd639, [3, 0, 1, 1]),
    wordSprm(0x563a, wordU16(11)),
  ]) {
    final code = operation[0] | (operation[1] << 8);
    test('post-wall ${code.toRadixString(16)} remains incomplete history', () {
      final document = parseLegacyWordDocument(
        tableReviewFixture([
          (
            'CELL',
            [
              ...rowReviewProperties(height: 240),
              ...wordSprm(0x3668, [1]),
              ...operation,
              ...rowReviewProperties(height: 720),
              ...rowReviewMark(),
            ],
          ),
        ]),
      );
      expect(
        _rows(document).single.formattingRevision!.unsupportedPropertyCodes,
        [code],
      );
      expect(
        _xml(document).findAllElements('trPrChange', namespace: _w),
        isEmpty,
      );
      expect(
        document.warnings,
        contains(LegacyWordWarning.revisionMetadataIncomplete),
      );
      expect(_evidence(document).single['unsupportedPropertyCodes'], [code]);
    });
  }
}
