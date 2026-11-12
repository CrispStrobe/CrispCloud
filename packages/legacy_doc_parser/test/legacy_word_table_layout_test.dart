// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';
import 'support/table_word_fixture.dart';

Uint8List _row(List<int> properties, {int flags = 0}) => tableFixture([
  const TableFixtureParagraph('Cell\x07', depth: 1, cell: true),
  TableFixtureParagraph(
    '\x07',
    depth: 1,
    row: true,
    extra: [
      ...tableFixtureDefinition([2400], flags: [flags]),
      ...properties,
    ],
  ),
]);

LegacyWordTableRow _model(Uint8List bytes) =>
    (parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable)
        .rows
        .single;

XmlDocument _xml(Uint8List bytes) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder()
        .decodeBytes(convertLegacyWordToStructuredDocx(bytes).bytes)
        .findFile('word/document.xml')!
        .content,
  ),
);

void main() {
  test('signed row heights retain exact, minimum and explicit auto modes', () {
    for (final entry in {-720: 'exact', 720: 'atLeast', 0: 'auto'}.entries) {
      final bytes = _row(wordSprm(0x9407, wordU16(entry.key)));
      expect(_model(bytes).heightTwips, entry.key);
      final height = _xml(bytes).findAllElements('w:trHeight').single;
      expect(height.getAttribute('w:val'), '${entry.key.abs()}');
      expect(height.getAttribute('w:hRule'), entry.value);
    }
    expect(_model(_row([])).heightTwips, isNull);
    expect(_xml(_row([])).findAllElements('w:trHeight'), isEmpty);
  });

  test('row height resets apply in record order', () {
    final bytes = _row([
      ...wordSprm(0x9407, wordU16(-1440)),
      ...wordSprm(0x9407, wordU16(0)),
    ]);
    expect(_model(bytes).heightTwips, 0);
  });

  test('modern cantSplit wins over the legacy flag in either order', () {
    for (final value in [false, true]) {
      for (final reverse in [false, true]) {
        final old = wordSprm(0x3403, [value ? 0 : 1]);
        final modern = wordSprm(0x3466, [value ? 1 : 0]);
        final bytes = _row(reverse ? [...modern, ...old] : [...old, ...modern]);
        expect(_model(bytes).cantSplit, value);
        expect(
          _xml(
            bytes,
          ).findAllElements('w:cantSplit').single.getAttribute('w:val'),
          value ? 'on' : 'off',
        );
      }
    }
    expect(_model(_row(wordSprm(0x3403, [1]))).cantSplit, true);
    expect(_model(_row([])).cantSplit, isNull);
  });

  test('rejects row heights outside YAS and malformed Bool8 flags', () {
    for (final height in [-32768, -31681, 31681, 32767]) {
      expect(
        () => _model(_row(wordSprm(0x9407, wordU16(height)))),
        throwsFormatException,
      );
    }
    for (final code in [0x3403, 0x3466]) {
      expect(() => _model(_row(wordSprm(code, [2]))), throwsFormatException);
    }
  });

  test('TC80 preserves every valid cell text flow mode', () {
    const directions = {
      0: 'lrTb',
      1: 'tbRl',
      3: 'btLr',
      4: 'lrTbV',
      5: 'tbRlV',
    };
    for (final entry in directions.entries) {
      final bytes = _row([], flags: entry.key << 2);
      expect(
        _model(bytes).cells.single.formatting.textDirection!.name,
        entry.value,
      );
      expect(
        _xml(
          bytes,
        ).findAllElements('w:textDirection').single.getAttribute('w:val'),
        entry.value,
      );
    }
    for (final flow in [2, 6, 7]) {
      expect(() => _model(_row([], flags: flow << 2)), throwsFormatException);
    }
  });

  test('fitText and hideMark keep true and explicit false independently', () {
    for (final fit in [false, true]) {
      for (final hide in [false, true]) {
        final bytes = _row([], flags: (fit ? 0x1000 : 0) | (hide ? 0x4000 : 0));
        final format = _model(bytes).cells.single.formatting;
        expect((format.fitText, format.hideMark), (fit, hide));
        final xml = _xml(bytes);
        expect(
          xml.findAllElements('w:tcFitText').single.getAttribute('w:val'),
          fit ? 'on' : 'off',
        );
        expect(
          xml.findAllElements('w:hideMark').single.getAttribute('w:val'),
          hide ? 'on' : 'off',
        );
      }
    }
  });
}
