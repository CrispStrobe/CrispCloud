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
    'floating table anchors retain each physical origin and ignore padding',
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
          expect(_attr(node, 'tblpX'), '1440');
          expect(_attr(node, 'tblpY'), '720');
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
      final node = _position(
        _source([..._two(0x940e, stored), ..._two(0x940f, stored)]),
      );
      expect(_attr(node, 'tblpX'), '${stored - 1}');
      expect(_attr(node, 'tblpY'), '${stored - 1}');
    }
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
      final xml = _xml(bytes, 'footnotes');
      expect(
        xml.rootElement.childElements.last.childElements.map(
          (e) => e.name.local,
        ),
        ['p', 'tbl'],
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
