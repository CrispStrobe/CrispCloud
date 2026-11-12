// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';
import 'support/table_review_fixture.dart';
import 'support/table_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
List<int> _wall(int value) => wordSprm(0x3668, [value]);

LegacyWordDocument _document(List<int> properties, {bool defined = true}) =>
    parseLegacyWordDocument(
      tableReviewFixture([
        ('CELL', properties),
      ], defineBeforeProperties: defined),
    );

LegacyWordTableRow _row(LegacyWordDocument document) =>
    document.blocks.whereType<LegacyWordTable>().single.rows.single;

Map<String, Uint8List> _parts(LegacyWordDocument document) => {
  for (final file in ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  ))
    if (file.isFile) file.name: file.content,
};

XmlDocument _xml(LegacyWordDocument document) =>
    XmlDocument.parse(utf8.decode(_parts(document)['word/document.xml']!));

List<Map<String, Object?>> _rows(XmlDocument document, {bool reject = false}) {
  var headerPrefix = true;
  return [
    for (final row in document.findAllElements('tr', namespace: _w))
      (() {
        final current = row.getElement('trPr', namespace: _w);
        final old = current
            ?.getElement('trPrChange', namespace: _w)
            ?.getElement('trPr', namespace: _w);
        final properties = reject && old != null ? old : current;
        final height = properties?.getElement('trHeight', namespace: _w);
        bool flag(String name) {
          final element = properties?.getElement(name, namespace: _w);
          return element != null &&
              !const {
                'off',
                'false',
                '0',
              }.contains(element.getAttribute('val', namespace: _w));
        }

        final header = flag('tblHeader');
        headerPrefix &= header;
        return {
          'height': height?.getAttribute('val', namespace: _w),
          'rule': height?.getAttribute('hRule', namespace: _w),
          'cantSplit': flag('cantSplit'),
          'headerRequest': header,
          'headerEffective': headerPrefix,
        };
      })(),
  ];
}

List<Map<String, dynamic>> _evidence(LegacyWordDocument document) {
  final parts = _parts(document);
  return ((jsonDecode(utf8.decode(parts['word/evidence/manifest.json']!))
              as Map<String, dynamic>)['records']
          as List)
      .cast<Map<String, dynamic>>()
      .where((record) => record['kind'] == 'tableRowFormattingRevision')
      .toList();
}

void main() {
  test(
    'TWall retains independently rejectable row properties and provenance',
    () {
      final document = _document([
        ...rowReviewProperties(height: -240, cantSplit: false, header: true),
        ..._wall(1),
        ...rowReviewProperties(height: 720, cantSplit: true, header: false),
        ...rowReviewMark(),
      ]);
      final row = _row(document), change = row.formattingRevision!;
      expect(
        (row.heightTwips, row.cantSplit, row.isHeader),
        (720, true, false),
      );
      expect(change.previousProperties!.heightTwips, -240);
      expect(change.previousProperties!.cantSplit, isFalse);
      expect(change.previousProperties!.isHeader, isTrue);
      expect(change.previousPropertiesComplete, isTrue);
      expect(change.unsupportedPropertyCodes, isEmpty);
      expect(change.revision.author, 'Alice');
      expect(change.revision.rawDate, tableReviewDate);
      final xml = _xml(document);
      expect(_rows(xml), [
        {
          'height': '720',
          'rule': 'atLeast',
          'cantSplit': true,
          'headerRequest': false,
          'headerEffective': false,
        },
      ]);
      expect(_rows(xml, reject: true), [
        {
          'height': '240',
          'rule': 'exact',
          'cantSplit': false,
          'headerRequest': true,
          'headerEffective': true,
        },
      ]);
      final mark = xml.findAllElements('trPrChange', namespace: _w).single;
      expect(mark.getAttribute('author', namespace: _w), 'Alice');
      expect(mark.getAttribute('date', namespace: _w), '2026-11-12T08:45:00');
      expect(
        convertLegacyWordDocument(
          document,
        ).preservedCounts['tableRowFormattingRevisions'],
        1,
      );
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.revisionMetadataIncomplete)),
      );
    },
  );

  for (final kind in tableReviewCases) {
    test(
      '$kind accept/reject projections match independently authored controls',
      () {
        final review = _xml(
          parseLegacyWordDocument(tableReviewControl(kind, 'review')),
        );
        for (final state in ['accepted', 'rejected']) {
          final control = _xml(
            parseLegacyWordDocument(tableReviewControl(kind, state)),
          );
          expect(
            _rows(review, reject: state == 'rejected'),
            _rows(control),
            reason: state,
          );
        }
      },
    );
  }

  test(
    'dormant second header request survives rejection of the first header edit',
    () {
      final document = parseLegacyWordDocument(
        tableReviewControl('header', 'review', dormantSecondHeader: true),
      );
      final rows = document.blocks.whereType<LegacyWordTable>().single.rows;
      expect(rows.take(2).map((row) => row.isHeader), [false, false]);
      expect(rows.take(2).map((row) => row.sourceHeaderRequest), [false, true]);
      expect(
        _rows(_xml(document)).take(2).map((row) => row['headerEffective']),
        [false, false],
      );
      expect(
        _rows(
          _xml(document),
          reject: true,
        ).take(2).map((row) => row['headerEffective']),
        [true, true],
      );
    },
  );

  test('false wall clears history without accepting or inventing a change', () {
    final document = _document([
      ...rowReviewProperties(height: 240),
      ..._wall(1),
      ...rowReviewProperties(height: 720),
      ..._wall(0),
      ...rowReviewMark(marked: 0),
    ]);
    expect(_row(document).heightTwips, 720);
    expect(_row(document).formattingRevision, isNull);
    expect(
      _xml(document).findAllElements('trPrChange', namespace: _w),
      isEmpty,
    );
  });

  for (final (name, properties) in [
    (
      'missing snapshot',
      [...rowReviewProperties(height: 720), ...rowReviewMark()],
    ),
    ('unmarked snapshot', [..._wall(1), ...rowReviewProperties(height: 720)]),
  ]) {
    test('$name remains explicit evidence', () {
      final document = _document(properties);
      expect(_row(document).formattingRevision, isNotNull);
      expect(
        document.warnings,
        contains(LegacyWordWarning.revisionMetadataIncomplete),
      );
      expect(
        convertLegacyWordDocument(document).limitations,
        contains(LegacyWordConversionLimitation.revisions),
      );
      expect(
        _xml(document).findAllElements('trPrChange', namespace: _w),
        isEmpty,
      );
      expect(_evidence(document), hasLength(1));
    });
  }

  for (final (name, operation, code) in [
    ('column width', wordSprm(0x7623, [0, 1, ...wordU16(3600)]), 0x7623),
    ('replacement cell definition', tableFixtureDefinition([3600]), 0xd608),
    ('auto-fit', wordSprm(0x3615, [1]), 0x3615),
    ('unknown table property', wordSprm(0x3601, [1]), 0x3601),
  ]) {
    test(
      'post-wall $name cannot masquerade as complete native row history',
      () {
        final document = _document([
          ...rowReviewProperties(height: 240),
          ..._wall(1),
          ...operation,
          ...rowReviewProperties(height: 720),
          ...rowReviewMark(),
        ]);
        final change = _row(document).formattingRevision!;
        expect(change.previousProperties!.heightTwips, 240);
        expect(change.unsupportedPropertyCodes, [code]);
        expect(
          () => change.unsupportedPropertyCodes.add(0),
          throwsUnsupportedError,
        );
        expect(
          _xml(document).findAllElements('trPrChange', namespace: _w),
          isEmpty,
        );
        expect(_evidence(document).single['unsupportedPropertyCodes'], [code]);
        expect(
          document.warnings,
          contains(LegacyWordWarning.revisionMetadataIncomplete),
        );
      },
    );
  }

  test(
    'a new true wall replaces the prior snapshot and its unsupported edits',
    () {
      final document = _document([
        ...rowReviewProperties(height: 240),
        ..._wall(1),
        ...wordSprm(0x7623, [0, 1, ...wordU16(3600)]),
        ...rowReviewProperties(height: 360),
        ..._wall(1),
        ...rowReviewProperties(height: 720),
        ...rowReviewMark(),
      ]);
      expect(
        _row(document).formattingRevision!.previousProperties!.heightTwips,
        360,
      );
      expect(
        _row(document).formattingRevision!.unsupportedPropertyCodes,
        isEmpty,
      );
      expect(
        _xml(document).findAllElements('trPrChange', namespace: _w),
        hasLength(1),
      );
    },
  );

  test('unknown pre-wall row properties prevent a complete-history claim', () {
    final document = _document([
      ...wordSprm(0x3601, [1]),
      ..._wall(1),
      ...rowReviewProperties(height: 720),
      ...rowReviewMark(),
    ]);
    expect(
      _row(document).formattingRevision!.previousPropertiesComplete,
      isFalse,
    );
    expect(
      _xml(document).findAllElements('trPrChange', namespace: _w),
      isEmpty,
    );
  });

  test('a wall before the first cell definition is diagnosed', () {
    final document = _document([
      ..._wall(1),
      ...rowReviewProperties(height: 720),
      ...rowReviewMark(),
    ], defined: false);
    expect(
      _row(document).formattingRevision!.previousPropertiesComplete,
      isFalse,
    );
    expect(_row(document).formattingRevision!.unsupportedPropertyCodes, [
      0xd608,
    ]);
    expect(
      _xml(document).findAllElements('trPrChange', namespace: _w),
      isEmpty,
    );
  });

  test('paragraph style changes preserve the independent table revision', () {
    final document = _document([
      ...rowReviewProperties(height: 240),
      ..._wall(1),
      ...wordSprm(0x4600, wordU16(0)),
      ...rowReviewProperties(height: 720),
      ...rowReviewMark(),
    ]);
    expect(
      _row(document).formattingRevision!.previousProperties!.heightTwips,
      240,
    );
    expect(
      _xml(document).findAllElements('trPrChange', namespace: _w),
      hasLength(1),
    );
  });

  test('two row revisions receive distinct native identifiers', () {
    final properties = [
      ...rowReviewProperties(height: 240),
      ..._wall(1),
      ...rowReviewProperties(height: 720),
      ...rowReviewMark(),
    ];
    final document = parseLegacyWordDocument(
      tableReviewFixture([('ONE', properties), ('TWO', properties)]),
    );
    final identifiers = _xml(document)
        .findAllElements('trPrChange', namespace: _w)
        .map((node) => node.getAttribute('id', namespace: _w))
        .toSet();
    expect(identifiers, hasLength(2));
  });

  for (final (name, properties) in [
    ('invalid wall Boolean', _wall(2)),
    ('invalid mark Boolean', rowReviewMark(marked: 2)),
    ('truncated PropRMark', wordSprm(0xd667, [6, 1, ...List.filled(5, 0)])),
    (
      'invalid historical height',
      [
        ...rowReviewProperties(height: -32000),
        ..._wall(1),
        ...rowReviewProperties(height: 720),
      ],
    ),
  ]) {
    test('rejects $name before a valid current value hides it', () {
      expect(() => _document(properties), throwsFormatException);
    });
  }
}
