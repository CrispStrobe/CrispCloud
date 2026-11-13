// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/story_word_fixture.dart';
import 'support/structured_word_fixture.dart';
import 'support/table_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
List<int> _one(int code, int value) => wordSprm(code, [value]);
List<int> _two(int code, int value) => wordSprm(code, wordU16(value));
Uint8List _source(List<int> properties) => tableFixture([
  const TableFixtureParagraph('CELL\x07', depth: 1),
  TableFixtureParagraph(
    '\x07',
    depth: 1,
    row: true,
    widths: [2400],
    extra: properties,
  ),
]);
LegacyWordTable _table(Uint8List bytes) =>
    parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable;
XmlDocument _xml(Uint8List bytes, [String part = 'document']) =>
    XmlDocument.parse(
      utf8.decode(
        ZipDecoder()
            .decodeBytes(convertLegacyWordToStructuredDocx(bytes).bytes)
            .findFile('word/$part.xml')!
            .content,
      ),
    );
XmlElement _position(Uint8List bytes) =>
    _xml(bytes).findAllElements('tblpPr', namespace: _w).single;
String? _attr(XmlElement node, String name) =>
    node.getAttribute(name, namespace: _w);

List<int> _padding(int code, int width) =>
    wordSprm(code, [6, 0, 1, 2, 3, ...wordU16(width)]);
List<int> _border(int width, {int style = 1, int? rightWidth}) =>
    wordSprm(0xd613, [
      48,
      for (var side = 0; side < 6; side++) ...[
        0,
        0,
        0,
        0,
        side == 3 ? rightWidth ?? width : width,
        style,
        0,
        0,
      ],
    ]);

Uint8List _noteSource({required bool endnote, String trailing = ''}) {
  const main = 'A\x02\r';
  final note = '\x02N\rCELL\x07\x07$trailing';
  final fc = endnote ? 22528 : 8192;
  return storyWordFixture(
    main: main,
    footnotes: endnote ? '' : '$note\r',
    endnotes: endnote ? '$note\r' : '',
    tablePairs: {
      endnote ? 46 : 2: storyPlc([1, main.length], wordU16(1)),
      endnote ? 47 : 3: storyPlc([0, note.length, 0xffffffff]),
    },
    paragraphRuns: [
      WordFixtureFkpRun(8192, fc + 6),
      WordFixtureFkpRun(fc + 6, fc + 16, properties: _one(0x2416, 1)),
      WordFixtureFkpRun(
        fc + 16,
        fc + 18,
        properties: [
          ..._one(0x2416, 1),
          ..._one(0x2417, 1),
          ...tableFixtureDefinition([2400]),
        ],
      ),
      WordFixtureFkpRun(fc + 18, 28672),
    ],
  );
}

void main() {
  test(
    'floating table anchors retain each physical origin and ignore padding bits',
    () {
      for (var horizontal = 0; horizontal < 3; horizontal++) {
        for (var vertical = 0; vertical < 3; vertical++) {
          final source = _source([
            ..._one(0x360d, (horizontal << 6) | (vertical << 4) | 15),
            ..._two(0x940e, 1441),
            ..._two(0x940f, 721),
          ]);
          final position = _table(source).position!;
          expect(position.horizontalOffsetTwips, 1440);
          expect(position.verticalOffsetTwips, 720);
          final node = _position(source);
          expect(
            _attr(node, 'horzAnchor'),
            ['text', 'margin', 'page'][horizontal],
          );
          expect(
            _attr(node, 'vertAnchor'),
            ['margin', 'page', 'text'][vertical],
          );
          expect(_attr(node, 'tblpX'), '1549');
          expect(_attr(node, 'tblpY'), '721');
        }
      }
    },
  );

  test('alignment sentinels remain distinct from signed absolute offsets', () {
    for (final x in {
      0: 'left',
      -4: 'center',
      -8: 'right',
      -12: 'inside',
      -16: 'outside',
    }.entries) {
      for (final y in {
        0: 'inline',
        -4: 'top',
        -8: 'center',
        -12: 'bottom',
        -16: 'inside',
        -20: 'outside',
      }.entries) {
        final node = _position(
          _source([
            ..._one(0x360d, 0xa0),
            ..._two(0x940e, x.key),
            ..._two(0x940f, y.key),
          ]),
        );
        expect(_attr(node, 'tblpXSpec'), x.value);
        expect(_attr(node, 'tblpYSpec'), y.value);
        expect(_attr(node, 'tblpX'), isNull);
        expect(_attr(node, 'tblpY'), isNull);
      }
    }
    for (final stored in [-31679, -1440, -1, 1, 31681]) {
      final source = _source([
        ..._two(0x940e, stored),
        ..._two(0x940f, stored),
      ]);
      final position = _table(source).position!;
      expect(position.horizontalOffsetTwips, stored - 1);
      expect(position.verticalOffsetTwips, stored - 1);
      final node = _position(source);
      expect(_attr(node, 'tblpX'), '${stored + 108}');
      expect(_attr(node, 'tblpY'), '$stored');
    }
  });

  test('native page table retains source defaults independently of cells', () {
    final source = File(
      'test/fixtures/word_native/word16-page-origin.doc',
    ).readAsBytesSync();
    final table = parseLegacyWordDocument(
      source,
    ).blocks.whereType<LegacyWordTable>().single;
    expect(table.position!.horizontalOffsetTwips, 856);
    expect(table.position!.verticalOffsetTwips, 2544);
    for (final row in table.rows) {
      expect(row.defaultCellMargins, {
        LegacyWordBorderSide.top: 0,
        LegacyWordBorderSide.left: 0,
        LegacyWordBorderSide.bottom: 0,
        LegacyWordBorderSide.right: 0,
      });
      for (final cell in row.cells) {
        expect(cell.formatting.margins[LegacyWordBorderSide.bottom], 113);
      }
    }
    final xml = _xml(source);
    final margins = xml.findAllElements('tblCellMar', namespace: _w).single;
    expect(margins.childElements.map((e) => e.name.local), [
      'top',
      'left',
      'bottom',
      'right',
    ]);
    expect(margins.childElements.map((e) => _attr(e, 'w')), [
      '0',
      '0',
      '0',
      '0',
    ]);
    final position = xml.findAllElements('tblpPr', namespace: _w).single;
    expect(_attr(position, 'tblpX'), '857');
    expect(_attr(position, 'tblpY'), '2545');
  });

  test(
    'absolute table origin maps padding and bounded single-border edges',
    () {
      // Literal expected offsets are independently checked by native exports
      // and CELL-to-BODY measurements, including the source .75pt -> 7tw half.
      for (final (stored, margin, cellMargin, border, origin, expected)
          in <(int, int, int?, int, int, int)>[
            (1441, 0, null, 0, 0, 1441),
            (1441, 108, null, 0, 0, 1549),
            (1441, 240, null, 0, 0, 1681),
            (-361, 240, null, 0, 0, -121),
            (-361, 240, null, 8, 0, -111),
            (-361, 240, null, 6, 0, -114),
            (-361, 240, null, 10, 0, -109),
            (1441, 240, 0, 0, 0, 1681),
            (1441, 0, 240, 0, 0, 1441),
            (1441, 240, null, 6, 480, 2168),
            (1441, 240, null, 6, -108, 1580),
          ]) {
        final source = _source([
          ...tableFixtureDefinition([2400], origin: origin),
          ..._one(0x360d, 0x50),
          ..._two(0x940e, stored),
          ..._two(0x940f, 2161),
          ..._padding(0xd634, margin),
          if (cellMargin != null) ..._padding(0xd632, cellMargin),
          if (border != 0) ..._border(border),
        ]);
        expect(_table(source).position!.horizontalOffsetTwips, stored - 1);
        expect(_attr(_position(source), 'tblpX'), '$expected');
        expect(_attr(_position(source), 'tblpY'), '2161');
      }
    },
  );

  test('physical floating edge keeps the first left border for RTL rows', () {
    for (final rtl in [false, true]) {
      final source = tableFixture([
        const TableFixtureParagraph('CELL0\x07', depth: 1, cell: true),
        const TableFixtureParagraph('CELL1\x07', depth: 1, cell: true),
        TableFixtureParagraph(
          '\x07',
          depth: 1,
          row: true,
          widths: [1200, 1200],
          extra: [
            ..._one(0x360d, 0x50),
            ..._two(0x940e, 1441),
            ..._two(0x940f, 2161),
            ..._two(0x560b, rtl ? 1 : 0),
            ..._padding(0xd634, 240),
            ..._border(6, rightWidth: 16),
          ],
        ),
      ]);
      expect(_attr(_position(source), 'tblpX'), '1688');
    }
  });

  test('named horizontal positions do not receive absolute-origin offsets', () {
    for (final (sourceValue, name) in [
      (0, 'left'),
      (-4, 'center'),
      (-8, 'right'),
    ]) {
      final node = _position(
        _source([
          ..._one(0x360d, 0x50),
          ..._two(0x940e, sourceValue),
          ..._two(0x940f, 2161),
          ..._padding(0xd634, 240),
          ..._border(8),
        ]),
      );
      expect(_attr(node, 'tblpXSpec'), name);
      expect(_attr(node, 'tblpX'), isNull);
    }
  });

  test('compound-border origins stay diagnosed without invented extents', () {
    final source = _source([
      ..._two(0x940e, 1441),
      ..._two(0x940f, 2161),
      ..._padding(0xd634, 240),
      ..._border(8, style: 3),
    ]);
    final converted = convertLegacyWordToStructuredDocx(source);
    expect(_attr(_position(source), 'tblpX'), '1681');
    expect(
      converted.limitations,
      contains(LegacyWordConversionLimitation.partialFormatting),
    );
    final evidence = ZipDecoder()
        .decodeBytes(converted.bytes)
        .files
        .where((file) => file.name.endsWith('.json'))
        .map((file) => utf8.decode(file.content))
        .join();
    expect(evidence, contains('floatingTableBorderOrigin'));
  });

  test('absolute position plus its row context fails on target overflow', () {
    final source = _source([
      ..._two(0x940e, 31681),
      ..._two(0x940f, 1),
      ..._padding(0xd634, 2000),
    ]);
    expect(_table(source).position!.horizontalOffsetTwips, 31680);
    expect(() => _position(source), throwsFormatException);
  });

  test(
    'wrapping distances and no-overlap retain direction and record order',
    () {
      final source = _source([
        ..._one(0x360d, 0xa0),
        ..._two(0x940e, -4),
        ..._two(0x940f, -4),
        ..._two(0x9410, 100),
        ..._two(0x9411, 200),
        ..._two(0x941e, 300),
        ..._two(0x941f, 400),
        ..._one(0x3465, 0),
        ..._one(0x3465, 1),
        ..._two(0x9410, 500),
      ]);
      final node = _position(source);
      expect(_attr(node, 'leftFromText'), '500');
      expect(_attr(node, 'topFromText'), '200');
      expect(_attr(node, 'rightFromText'), '300');
      expect(_attr(node, 'bottomFromText'), '400');
      expect(_table(source).position!.allowOverlap, false);
      expect(
        _attr(
          _xml(source).findAllElements('tblOverlap', namespace: _w).single,
          'val',
        ),
        'never',
      );
    },
  );

  test('default and explicit none positions do not float inline tables', () {
    for (final properties in [
      <int>[],
      [..._one(0x360d, 15), ..._two(0x940e, 0), ..._two(0x940f, 0)],
      [..._one(0x360d, 0x30), ..._two(0x940f, -4)],
      [..._one(0x360d, 0xc0), ..._two(0x940f, -4)],
    ]) {
      final source = _source(properties);
      expect(_table(source).position, isNull);
      expect(_xml(source).findAllElements('tblpPr', namespace: _w), isEmpty);
    }
  });

  test('rejects out-of-range positioning and wrapping operands', () {
    for (final code in [0x940e, 0x940f]) {
      for (final value in [-32768, -31680, 31682, 32767]) {
        expect(() => _table(_source(_two(code, value))), throwsFormatException);
      }
    }
    for (final code in [0x9410, 0x9411, 0x941e, 0x941f]) {
      for (final value in [31681, 65535]) {
        expect(() => _table(_source(_two(code, value))), throwsFormatException);
      }
    }
    expect(() => _table(_source(_one(0x3465, 2))), throwsFormatException);
  });

  for (final endnote in [false, true]) {
    for (final trailing in ['', '\r', '\rAFTER\r']) {
      test(
        '${endnote ? 'endnote' : 'footnote'} preserves exact final source blocks $trailing',
        () {
          final source = _noteSource(endnote: endnote, trailing: trailing);
          final part = endnote ? 'endnotes' : 'footnotes';
          final xml = _xml(source, part);
          final note = xml.rootElement.childElements.last;
          expect(note.childElements.map((e) => e.name.local), [
            'p',
            'tbl',
            if (trailing.isNotEmpty) 'p',
            if (trailing.contains('AFTER')) 'p',
          ]);
          expect(
            note.findAllElements('t', namespace: _w).map((e) => e.innerText),
            ['N', 'CELL', if (trailing.contains('AFTER')) 'AFTER'],
          );
        },
      );
    }
  }

  test(
    'native table-ended note emits no new paragraph after its source boundary',
    () {
      final file = File('test/fixtures/word_native/note-table-ending.doc');
      final bytes = file.readAsBytesSync();
      final document = parseLegacyWordDocument(bytes);
      final note = document.stories.singleWhere(
        (s) => s.kind == LegacyWordStoryKind.footnote,
      );
      expect(note.blocks.map((b) => b.runtimeType), [
        LegacyWordParagraph,
        LegacyWordTable,
      ]);
      // The native DOC importer flattens this footnote table, so its DOCX
      // export is not a structural oracle. Literal PAPX/TDefTable bytes retain
      // CP 124..147, one 2000-twip cell, and 108-twip side margins. See the
      // independently decoded source anchors in table-note-oracle-20261113.
      final table = note.blocks.last as LegacyWordTable;
      expect((table.startCp, table.endCp), (124, 147));
      expect(table.rows, hasLength(1));
      final row = table.rows.single;
      expect(row.originTwips, 0);
      expect(row.cells, hasLength(1));
      expect(row.cells.single.widthTwips, 2000);
      expect(row.defaultCellMargins[LegacyWordBorderSide.left], 108);
      expect(row.defaultCellMargins[LegacyWordBorderSide.right], 108);
      final xml = _xml(bytes, 'footnotes');
      expect(
        xml.rootElement.childElements.last.childElements.map(
          (e) => e.name.local,
        ),
        ['p', 'tbl'],
      );
      expect(
        _attr(xml.findAllElements('tblW', namespace: _w).single, 'w'),
        '2000',
      );
      expect(
        _attr(xml.findAllElements('gridCol', namespace: _w).single, 'w'),
        '2000',
      );
      expect(file.readAsBytesSync(), bytes);
    },
  );

  test(
    'native floating note table keeps the real anchor and following paragraph',
    () {
      final bytes = File(
        'test/fixtures/word_native/note-floating-table.doc',
      ).readAsBytesSync();
      final document = parseLegacyWordDocument(bytes);
      final note = document.stories.singleWhere((s) => s.id == 'footnote-6');
      expect(note.blocks.map((b) => (b.startCp, b.endCp)), [
        (167, 188),
        (188, 189),
        (189, 206),
      ]);
      final position = (note.blocks.first as LegacyWordTable).position!;
      expect(position.horizontalAnchor, LegacyWordTableAnchor.page);
      expect(position.verticalAnchor, LegacyWordTableAnchor.text);
      expect(
        position.horizontalPlacement,
        LegacyWordTableHorizontalPlacement.center,
      );
      expect(position.verticalPlacement, LegacyWordTableVerticalPlacement.top);
      final xml = _xml(bytes, 'footnotes');
      expect(
        xml.rootElement.childElements.last.childElements.map(
          (e) => e.name.local,
        ),
        ['tbl', 'p', 'p'],
      );
      expect(
        _attr(xml.findAllElements('tblpPr', namespace: _w).single, 'tblpXSpec'),
        'center',
      );
    },
  );
}
