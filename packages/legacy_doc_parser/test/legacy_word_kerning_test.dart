// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
List<int> _kern(int value) => wordSprm(0x484b, wordU16(value));

Uint8List _source({
  List<int> properties = const [],
  List<int> paragraph = const [],
  Map<int, WordFixtureStyle>? styles,
}) => StructuredWordFixture(
  pieces: const [WordFixturePiece('Word\r')],
  characterRuns: [WordFixtureFkpRun(8192, 8197, properties: properties)],
  paragraphRuns: [WordFixtureFkpRun(8192, 8197, properties: paragraph)],
  styles: styles ?? const {0: WordFixtureStyle(name: 'Normal', builtinId: 0)},
).build();

LegacyWordParagraph _paragraph(LegacyWordDocument document) =>
    document.blocks.whereType<LegacyWordParagraph>().single;
Map<String, Uint8List> _parts(LegacyWordDocument document) => {
  for (final file in ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  ))
    if (file.isFile) file.name: file.content,
};
XmlDocument _xml(LegacyWordDocument document) =>
    XmlDocument.parse(utf8.decode(_parts(document)['word/document.xml']!));
String? _threshold(XmlElement properties) => properties
    .getElement('kern', namespace: _w)
    ?.getAttribute('val', namespace: _w);

LegacyWordDocument _model(LegacyWordCharacterStyle style) => LegacyWordDocument(
  blocks: [
    LegacyWordParagraph(
      startCp: 0,
      endCp: 5,
      runs: [LegacyWordRun(startCp: 0, endCp: 4, text: 'Word', style: style)],
    ),
  ],
  sections: const [],
  plainText: 'Word',
  safeHtml: '',
);

void main() {
  test('source default disables kerning for text and paragraph marks', () {
    final document = parseLegacyWordDocument(_source());
    final paragraph = _paragraph(document);
    expect(paragraph.runs.single.style.kerningThresholdHalfPoints, 0);
    expect(paragraph.mark!.style.kerningThresholdHalfPoints, 0);
    expect(document.safeHtml, contains('font-kerning:none'));
    final xml = _xml(document);
    expect(
      xml
          .findAllElements('kern', namespace: _w)
          .map((e) => e.getAttribute('val', namespace: _w)),
      ['0', '0'],
    );
  });

  test('signed source thresholds retain exact native values and bounds', () {
    for (final threshold in [0, 1, 24, 3276]) {
      final document = parseLegacyWordDocument(
        _source(properties: _kern(threshold)),
      );
      expect(
        _paragraph(document).runs.single.style.kerningThresholdHalfPoints,
        threshold,
      );
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.unsupportedFormatting)),
      );
      final xml = _xml(document);
      expect(
        xml
            .findAllElements('kern', namespace: _w)
            .map((e) => e.getAttribute('val', namespace: _w)),
        [threshold.toString(), threshold.toString()],
      );
    }
    for (final invalid in [-32768, -1, 3277, 32767]) {
      expect(
        () => parseLegacyWordDocument(_source(properties: _kern(invalid))),
        throwsFormatException,
      );
    }
    expect(
      () => parseLegacyWordDocument(_source(properties: wordSprm(0x484b, [0]))),
      throwsFormatException,
    );
  });

  test('style inheritance, sequential CIstd and CPlain restore kerning', () {
    final styles = {
      0: WordFixtureStyle(
        name: 'Normal',
        builtinId: 0,
        characterProperties: _kern(20),
      ),
      1: const WordFixtureStyle(name: 'Inherited paragraph', parentIndex: 0),
      20: WordFixtureStyle(
        name: 'Character',
        character: true,
        characterProperties: _kern(36),
      ),
      21: const WordFixtureStyle(
        name: 'Inherited character',
        character: true,
        parentIndex: 20,
      ),
      22: const WordFixtureStyle(
        name: 'Unspecified character',
        character: true,
      ),
    };
    final paragraphStyle = wordSprm(0x4600, wordU16(1));
    for (final (operations, expected) in <(List<int>, int)>[
      ([], 20),
      (_kern(0), 0),
      ([..._kern(8), ...wordSprm(0x4a30, wordU16(21))], 36),
      ([...wordSprm(0x4a30, wordU16(21)), ..._kern(8)], 8),
      (
        [
          ...wordSprm(0x4a30, wordU16(21)),
          ...wordSprm(0x2a33, [0]),
        ],
        20,
      ),
      ([..._kern(8), ...wordSprm(0x4a30, wordU16(22))], 20),
    ]) {
      final document = parseLegacyWordDocument(
        _source(
          properties: operations,
          paragraph: paragraphStyle,
          styles: styles,
        ),
      );
      expect(
        _paragraph(document).runs.single.style.kerningThresholdHalfPoints,
        expected,
      );
    }
    final cleared = parseLegacyWordDocument(
      _source(
        properties: [
          ..._kern(36),
          ...wordSprm(0x2a33, [0]),
        ],
      ),
    );
    expect(_paragraph(cleared).runs.single.style.kerningThresholdHalfPoints, 0);
  });

  test(
    'piece properties override CHPX and distinct thresholds do not coalesce',
    () {
      final document = parseLegacyWordDocument(
        StructuredWordFixture(
          pieces: const [WordFixturePiece('AB\r', prm: 1)],
          prcs: [_kern(28)],
          characterRuns: [WordFixtureFkpRun(8192, 8195, properties: _kern(12))],
        ).build(),
      );
      expect(
        _paragraph(document).runs.single.style.kerningThresholdHalfPoints,
        28,
      );
      final adjacent = parseLegacyWordDocument(
        StructuredWordFixture(
          pieces: const [WordFixturePiece('AB\r')],
          characterRuns: [
            WordFixtureFkpRun(8192, 8193, properties: _kern(0)),
            WordFixtureFkpRun(8193, 8195, properties: _kern(24)),
          ],
        ).build(),
      );
      expect(
        _paragraph(
          adjacent,
        ).runs.map((r) => (r.text, r.style.kerningThresholdHalfPoints)),
        [('A', 0), ('B', 24)],
      );
      expect(
        const LegacyWordCharacterStyle(),
        const LegacyWordCharacterStyle(kerningThresholdHalfPoints: 0),
      );
      expect(
        const LegacyWordCharacterStyle(),
        isNot(const LegacyWordCharacterStyle(kerningThresholdHalfPoints: 24)),
      );
      final equivalentStyles = <LegacyWordCharacterStyle>{};
      equivalentStyles.add(const LegacyWordCharacterStyle());
      equivalentStyles.add(
        const LegacyWordCharacterStyle(kerningThresholdHalfPoints: 0),
      );
      expect(equivalentStyles, hasLength(1));
    },
  );

  test(
    'formatting history keeps previous threshold including an explicit off reset',
    () {
      for (final (before, after) in [(28, 0), (0, 28)]) {
        final document = parseLegacyWordDocument(
          _source(
            properties: [
              ..._kern(before),
              ...wordSprm(0x2a83, [1]),
              ..._kern(after),
              ...wordSprm(0xca89, [7, 1, ...wordU16(0), ...wordU32(0)]),
            ],
          ),
        );
        final run = _paragraph(document).runs.single;
        expect(run.style.kerningThresholdHalfPoints, after);
        expect(
          run.formattingRevision!.previousStyle!.kerningThresholdHalfPoints,
          before,
        );
        expect(run.formattingRevision!.previousPropertiesComplete, isTrue);
        final xml = _xml(document);
        final current = xml
            .findAllElements('r', namespace: _w)
            .single
            .getElement('rPr', namespace: _w)!;
        final change = current.getElement('rPrChange', namespace: _w)!;
        expect(_threshold(current), after.toString());
        expect(
          _threshold(change.getElement('rPr', namespace: _w)!),
          before.toString(),
        );
        expect(current.childElements.last, same(change));
      }
    },
  );

  test(
    'native linked textbox source retains the no-kerning choice in its story',
    () {
      final document = parseLegacyWordDocument(
        File(
          'test/fixtures/word_native/linked-textboxes.doc',
        ).readAsBytesSync(),
      );
      final runs = [
        for (final story in document.stories)
          for (final paragraph in story.blocks.whereType<LegacyWordParagraph>())
            ...paragraph.runs,
      ];
      final flow = runs.where((run) => run.text.contains('FLOW-01')).single;
      expect(flow.style.kerningThresholdHalfPoints, 0);
      expect(flow.style.fontName, 'Liberation Serif');
      final xml = _xml(document);
      final native = xml
          .findAllElements('r', namespace: _w)
          .singleWhere(
            (run) =>
                run
                    .getElement('t', namespace: _w)
                    ?.innerText
                    .contains('FLOW-01') ??
                false,
          );
      expect(_threshold(native.getElement('rPr', namespace: _w)!), '0');
    },
  );

  test(
    'HTML uses known thresholds and marks unresolved font-size thresholds',
    () {
      for (final (threshold, size, expected) in <(int, int?, String)>[
        (0, null, 'none'),
        (28, 24, 'none'),
        (24, 24, 'normal'),
        (1, 24, 'normal'),
        (28, null, 'auto'),
      ]) {
        final document = _model(
          LegacyWordCharacterStyle(
            kerningThresholdHalfPoints: threshold,
            fontSizeHalfPoints: size,
          ),
        );
        final html = renderLegacyWordHtml(document.blocks);
        expect(html, contains('font-kerning:$expected'));
        expect(
          html.contains('data-word-kerning="threshold-unresolved"'),
          threshold > 0 && size == null,
        );
      }
      final hidden = _model(
        const LegacyWordCharacterStyle(
          hidden: true,
          kerningThresholdHalfPoints: 28,
        ),
      );
      expect(renderLegacyWordHtml(hidden.blocks), isNot(contains('Word')));
    },
  );

  test('public invalid thresholds cannot reach native XML or preview CSS', () {
    for (final invalid in [-1, 3277]) {
      final document = _model(
        LegacyWordCharacterStyle(kerningThresholdHalfPoints: invalid),
      );
      expect(() => convertLegacyWordDocument(document), throwsFormatException);
      expect(
        () => renderLegacyWordHtml(document.blocks),
        throwsFormatException,
      );
    }
  });

  test('numbering marker formatting retains its kerning threshold', () {
    const document = LegacyWordDocument(
      blocks: [],
      sections: [],
      plainText: '',
      safeHtml: '',
      numbering: [
        LegacyWordNumberingDefinition(
          id: 1,
          levels: [
            LegacyWordNumberingLevel(
              level: 0,
              format: 'decimal',
              text: '%1.',
              characterStyle: LegacyWordCharacterStyle(
                kerningThresholdHalfPoints: 32,
              ),
            ),
          ],
        ),
      ],
    );
    final xml = XmlDocument.parse(
      utf8.decode(_parts(document)['word/numbering.xml']!),
    );
    expect(
      xml
          .findAllElements('kern', namespace: _w)
          .single
          .getAttribute('val', namespace: _w),
      '32',
    );
  });
}
