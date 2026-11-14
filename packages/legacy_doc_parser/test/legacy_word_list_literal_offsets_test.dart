// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/legacy_word_numbering.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/list_word_fixture.dart';
import 'support/list_sequence_fixture.dart';
import 'support/structured_word_fixture.dart';
import 'support/story_word_fixture.dart';
import '../tool/list_literal_web_acceptance.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

List<String> _labels(LegacyWordDocument document) =>
    XmlDocument.parse(document.safeHtml)
        .findAllElements('span')
        .where((node) => node.getAttribute('data-word-list-label') == 'true')
        .map((node) => node.innerText)
        .toList();

XmlDocument _part(LegacyWordStructuredConversion result, String name) =>
    XmlDocument.parse(
      utf8.decode(
        ZipDecoder().decodeBytes(result.bytes).findFile(name)!.content
            as List<int>,
      ),
    );

List<Map<String, dynamic>> _evidence(LegacyWordStructuredConversion result) =>
    (jsonDecode(
              utf8.decode(
                ZipDecoder()
                    .decodeBytes(result.bytes)
                    .findFile('word/evidence/manifest.json')!
                    .content,
              ),
            )['records']
            as List)
        .cast<Map<String, dynamic>>();

LegacyWordDocument _model(
  List<LegacyWordNumberingLevel> levels, {
  List<LegacyWordParagraph>? paragraphs,
}) {
  final blocks =
      paragraphs ??
      [
        const LegacyWordParagraph(
          startCp: 0,
          endCp: 2,
          style: LegacyWordParagraphStyle(listId: 1),
          runs: [LegacyWordRun(startCp: 0, endCp: 1, text: 'x')],
        ),
      ];
  final numbering = [LegacyWordNumberingDefinition(id: 1, levels: levels)];
  return LegacyWordDocument(
    blocks: blocks,
    sections: const [],
    plainText: '',
    safeHtml: renderLegacyWordHtml(blocks, numberingDefinitions: numbering),
    numbering: numbering,
  );
}

LegacyWordDocument _crossParagraphField(String source, {bool numbered = true}) {
  final parsed = parseLegacyWordDocument(storyWordFixture(main: source));
  final paragraphs = parsed.blocks.cast<LegacyWordParagraph>().toList();
  return LegacyWordDocument(
    blocks: [
      for (final (index, paragraph) in paragraphs.indexed)
        LegacyWordParagraph(
          startCp: paragraph.startCp,
          endCp: paragraph.endCp,
          runs: paragraph.runs,
          mark: paragraph.mark,
          style: LegacyWordParagraphStyle(
            listId: numbered && index == 1 ? 1 : null,
          ),
        ),
    ],
    sections: parsed.sections,
    plainText: parsed.plainText,
    safeHtml: '',
    fields: parsed.fields,
    numbering: numbered
        ? const [
            LegacyWordNumberingDefinition(
              id: 1,
              levels: [
                LegacyWordNumberingLevel(
                  level: 0,
                  format: 'decimal',
                  text: '%1',
                  placeholderOffsets: [],
                ),
              ],
            ),
          ]
        : const [],
  );
}

void main() {
  test('408 exact binary label cases share VM and JavaScript acceptance', () {
    expect(verifyListLiteralWebAcceptance(), {
      'cases': 408,
      'fixtureCases': 24,
      'metamorphicCases': 384,
      'exactHtmlLabels': true,
      'exactDocxPrefixes': true,
      'sourceTemplatesRetained': true,
      'automaticRenumberingDisclosed': true,
      'sourceUnchanged': true,
    });
  });
  for (var number = 1; number <= 9; number++) {
    test('literal percent $number is preserved as text in both outputs', () {
      final literal = '%$number';
      final source = listWordFixture(
        levels: [listFixtureLevel(start: 7, text: literal, placeholders: [])],
      );
      final before = source.toList();
      final document = parseLegacyWordDocument(source);
      expect(_labels(document), [literal]);
      final result = convertLegacyWordDocument(document);
      final xml = _part(result, 'word/document.xml');
      final texts = xml
          .findAllElements('t', namespace: _w)
          .map((node) => node.innerText)
          .toList();
      expect(texts, [literal, 'Item']);
      expect(
        xml
            .findAllElements('numId', namespace: _w)
            .single
            .getAttribute('val', namespace: _w),
        '0',
      );
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.fieldsLists),
      );
      expect(result.preservedCounts['materializedNumberingLabels'], 1);
      expect(source, before);
    });
  }

  test(
    'null offsets retain legacy caller semantics; empty offsets are literal',
    () {
      final legacy = _model(const [
        LegacyWordNumberingLevel(
          level: 0,
          format: 'decimal',
          text: '%1',
          startAt: 7,
        ),
      ]);
      final exact = _model(const [
        LegacyWordNumberingLevel(
          level: 0,
          format: 'decimal',
          text: '%1',
          startAt: 7,
          placeholderOffsets: [],
        ),
      ]);
      expect(_labels(legacy), ['7']);
      expect(_labels(exact), ['%1']);
      expect(
        convertLegacyWordDocument(
          legacy,
        ).preservedCounts['materializedNumberingLabels'],
        isNull,
      );
      expect(
        convertLegacyWordDocument(
          exact,
        ).preservedCounts['materializedNumberingLabels'],
        1,
      );
    },
  );

  test(
    'parsed offsets are immutable and resolver snapshots public offsets',
    () {
      final parsed = parseLegacyWordDocument(listWordFixture());
      expect(
        () => parsed.numbering.single.levels.single.placeholderOffsets!.add(1),
        throwsUnsupportedError,
      );
      final positions = [0];
      final level = LegacyWordNumberingLevel(
        level: 0,
        format: 'decimal',
        text: '%1 literal %1',
        placeholderOffsets: positions,
      );
      final model = _model([level]);
      final resolver = LegacyWordNumberingResolver(model.numbering);
      positions.clear();
      expect(
        resolver.resolve(model.blocks).values.single!.labelText(),
        '1 literal %1',
      );
    },
  );

  for (final (name, level) in <(String, LegacyWordNumberingLevel)>[
    (
      'negative',
      const LegacyWordNumberingLevel(
        level: 0,
        format: 'decimal',
        text: '%1',
        placeholderOffsets: [-1],
      ),
    ),
    (
      'past end',
      const LegacyWordNumberingLevel(
        level: 0,
        format: 'decimal',
        text: '%1',
        placeholderOffsets: [2],
      ),
    ),
    (
      'not a percent',
      const LegacyWordNumberingLevel(
        level: 0,
        format: 'decimal',
        text: 'ab',
        placeholderOffsets: [0],
      ),
    ),
    (
      'not a numeral',
      const LegacyWordNumberingLevel(
        level: 0,
        format: 'decimal',
        text: '%x',
        placeholderOffsets: [0],
      ),
    ),
    (
      'zero numeral',
      const LegacyWordNumberingLevel(
        level: 0,
        format: 'decimal',
        text: '%0',
        placeholderOffsets: [0],
      ),
    ),
    (
      'higher level',
      const LegacyWordNumberingLevel(
        level: 0,
        format: 'decimal',
        text: '%2',
        placeholderOffsets: [0],
      ),
    ),
    (
      'duplicate',
      const LegacyWordNumberingLevel(
        level: 1,
        format: 'decimal',
        text: '%1%2',
        placeholderOffsets: [0, 0],
      ),
    ),
    (
      'unsorted',
      const LegacyWordNumberingLevel(
        level: 1,
        format: 'decimal',
        text: '%1%2',
        placeholderOffsets: [2, 0],
      ),
    ),
    (
      'overlap',
      const LegacyWordNumberingLevel(
        level: 1,
        format: 'decimal',
        text: '%1%2',
        placeholderOffsets: [0, 1],
      ),
    ),
    (
      'too many at level',
      const LegacyWordNumberingLevel(
        level: 0,
        format: 'decimal',
        text: '%1%1',
        placeholderOffsets: [0, 2],
      ),
    ),
    (
      'bullet substitution',
      const LegacyWordNumberingLevel(
        level: 0,
        format: 'bullet',
        text: '%1',
        placeholderOffsets: [0],
      ),
    ),
  ]) {
    test('rejects malformed explicit offsets: $name', () {
      final document = LegacyWordDocument(
        blocks: const [],
        sections: const [],
        plainText: '',
        safeHtml: '',
        numbering: [
          LegacyWordNumberingDefinition(id: 1, levels: [level]),
        ],
      );
      expect(() => convertLegacyWordDocument(document), throwsFormatException);
      expect(
        () => renderLegacyWordHtml(
          const [],
          numberingDefinitions: document.numbering,
        ),
        throwsFormatException,
      );
    });
  }

  test('literal fallback never invents a required unsupported numeral', () {
    final source = listWordFixture(
      levels: [
        listFixtureLevel(format: 45, text: '%1 \x00', placeholders: [4]),
      ],
    );
    final document = parseLegacyWordDocument(source);
    expect(document.safeHtml, contains('data-word-numbering="unsupported"'));
    expect(_labels(document), isEmpty);
    expect(
      () => convertLegacyWordDocument(document),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'reason',
          contains('unsupported numeral format'),
        ),
      ),
    );
    expect(document.numbering.single.levels.single.text, '%1 %1');
    expect(document.numbering.single.levels.single.placeholderOffsets, [3]);
  });

  test('a start-only override copies the exact placeholder identity', () {
    final source = listWordFixture(
      levels: [
        listFixtureLevel(text: '%1/\x00', placeholders: [4]),
      ],
      instances: listFixtureInstances(
        overrides: [
          [...wordU32(12), ...wordU32(0x10)],
        ],
      ),
    );
    final document = parseLegacyWordDocument(source);
    expect(document.numbering.single.levels.single.placeholderOffsets, [3]);
    expect(_labels(document), ['%1/12']);
    expect(
      _part(
        convertLegacyWordDocument(document),
        'word/document.xml',
      ).findAllElements('t', namespace: _w).first.innerText,
      '%1/12',
    );
  });

  test(
    'interleaved editable and materialized labels resume exact counters',
    () {
      final source = listSequenceFixture(
        [(1, 0), (2, 0), (2, 0), (1, 0), (2, 0), (1, 0)],
        overrides: [
          [],
          [
            [
              ...wordU32(0xffffffff),
              ...wordU32(0x20),
              ...listFixtureLevel(text: '%1/\x00', placeholders: [4]),
            ],
          ],
        ],
      );
      final document = parseLegacyWordDocument(source);
      expect(_labels(document), ['1.', '%1/2', '%1/3', '4.', '%1/5', '6.']);
      final result = convertLegacyWordDocument(document);
      final main = _part(result, 'word/document.xml');
      final ids = main
          .findAllElements('numId', namespace: _w)
          .map((node) => node.getAttribute('val', namespace: _w))
          .toList();
      expect([ids[1], ids[2], ids[4]], ['0', '0', '0']);
      expect({ids[0], ids[3], ids[5]}, hasLength(3));
      final native = _part(result, 'word/numbering.xml');
      final starts = {
        for (final node in native.findAllElements('num', namespace: _w))
          node.getAttribute('numId', namespace: _w): node
              .findAllElements('startOverride', namespace: _w)
              .map((node) => node.getAttribute('val', namespace: _w))
              .toList(),
      };
      expect(starts[ids[3]], ['4']);
      expect(starts[ids[5]], ['6']);
      expect(
        main.findAllElements('t', namespace: _w).map((node) => node.innerText),
        ['P1', '%1/2', 'P2', '%1/3', 'P3', 'P4', '%1/5', 'P5', 'P6'],
      );
      expect(result.preservedCounts['materializedNumberingLabels'], 3);
    },
  );

  test(
    'materialized ancestor keeps numeric format for editable descendants',
    () {
      final source = listSequenceFixture(
        [(1, 0), (1, 1), (1, 0), (1, 1)],
        levels: [
          listFixtureLevel(
            format: 1,
            start: 7,
            text: '%1/\x00',
            placeholders: [4],
          ),
          listFixtureLevel(level: 1, text: '\x00.\x01', placeholders: [1, 3]),
          for (var level = 2; level < 9; level++)
            listFixtureLevel(level: level),
        ],
      );
      final document = parseLegacyWordDocument(source);
      expect(_labels(document), ['%1/VII', 'VII.1', '%1/VIII', 'VIII.1']);
      final result = convertLegacyWordDocument(document);
      final numbering = _part(result, 'word/numbering.xml');
      final level = numbering.findAllElements('lvl', namespace: _w).first;
      expect(
        level
            .getElement('numFmt', namespace: _w)!
            .getAttribute('val', namespace: _w),
        'upperRoman',
      );
      expect(
        level
            .getElement('lvlText', namespace: _w)!
            .getAttribute('val', namespace: _w),
        '',
      );
      expect(
        numbering
            .findAllElements('startOverride', namespace: _w)
            .map((node) => node.getAttribute('val', namespace: _w)),
        contains('8'),
      );
      expect(result.preservedCounts['materializedNumberingLabels'], 2);
    },
  );

  test('original 1024-unit boundary allows nine placeholder expansions', () {
    final source = listWordFixture(
      levels: [
        for (var level = 0; level < 8; level++) listFixtureLevel(level: level),
        listFixtureLevel(
          level: 8,
          text: '\x00' * 9 + 'a' * 1015,
          placeholders: List.generate(9, (i) => i + 1),
        ),
      ],
      paragraph: [
        ...wordSprm(0x460b, wordU16(1)),
        ...wordSprm(0x260a, [8]),
      ],
    );
    final document = parseLegacyWordDocument(source);
    expect(document.numbering.single.levels.last.text.length, 1033);
    expect(
      document.numbering.single.levels.last.placeholderOffsets,
      List.generate(9, (i) => i * 2),
    );
    expect(_labels(document), ['1' * 9 + 'a' * 1015]);
    expect(convertLegacyWordDocument(document).bytes, isNotEmpty);
  });

  test('label budget includes literals following the final expansion', () {
    expect(
      () => _model(const [
        LegacyWordNumberingLevel(
          level: 0,
          format: 'upperLetter',
          text: '%1%1%1%1x',
          startAt: 26624,
        ),
      ]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'reason',
          contains('label exceeds'),
        ),
      ),
    );
    final bounded = _model(const [
      LegacyWordNumberingLevel(
        level: 0,
        format: 'upperLetter',
        text: '%1%1%1%1',
        startAt: 26624,
      ),
    ]);
    expect(_labels(bounded).single, 'Z' * 4096);
  });

  for (final explicitAscii in [false, true]) {
    test(
      'materialized marker keeps marker style and paragraph-mark font slots: $explicitAscii',
      () {
        final document = _model(
          [
            LegacyWordNumberingLevel(
              level: 0,
              format: 'decimal',
              text: '%1',
              placeholderOffsets: const [],
              suffix: LegacyWordListSuffix.space,
              characterStyle: LegacyWordCharacterStyle(
                fontName: explicitAscii ? 'Marker ASCII' : null,
                scriptFonts: const LegacyWordScriptFonts(
                  nonAscii: 'Marker Non-ASCII',
                ),
                bold: true,
                italic: true,
                underline: true,
                underlineStyle: 'double',
                strike: true,
                doubleStrike: true,
                smallCaps: true,
                allCaps: true,
                fontSizeHalfPoints: 30,
                colorHex: '123456',
                highlightHex: '654321',
                verticalAlign: LegacyWordVerticalAlignment.superscript,
                positionHalfPoints: 2,
                spacingTwips: 15,
                kerningThresholdHalfPoints: 8,
              ),
            ),
          ],
          paragraphs: [
            const LegacyWordParagraph(
              startCp: 0,
              endCp: 2,
              style: LegacyWordParagraphStyle(listId: 1),
              mark: LegacyWordParagraphMark(
                style: LegacyWordCharacterStyle(
                  fontName: 'Paragraph ASCII',
                  scriptFonts: LegacyWordScriptFonts(
                    nonAscii: 'Paragraph Non-ASCII',
                    eastAsia: 'Paragraph East Asian',
                    complexScript: 'Paragraph Complex',
                  ),
                ),
              ),
              runs: [
                LegacyWordRun(
                  startCp: 0,
                  endCp: 1,
                  text: 'x',
                  style: LegacyWordCharacterStyle(fontName: 'Body Only'),
                ),
              ],
            ),
          ],
        );
        final paragraph = _part(
          convertLegacyWordDocument(document),
          'word/document.xml',
        ).findAllElements('p', namespace: _w).single;
        final marker = paragraph.findElements('r', namespace: _w).first;
        expect(
          marker.findAllElements('t', namespace: _w).single.innerText,
          '%1 ',
        );
        final style = marker.getElement('rPr', namespace: _w)!;
        final fonts = style.getElement('rFonts', namespace: _w)!;
        expect(
          fonts.getAttribute('ascii', namespace: _w),
          explicitAscii ? 'Marker ASCII' : 'Paragraph ASCII',
        );
        expect(fonts.getAttribute('hAnsi', namespace: _w), 'Marker Non-ASCII');
        expect(
          fonts.getAttribute('eastAsia', namespace: _w),
          'Paragraph East Asian',
        );
        expect(fonts.getAttribute('cs', namespace: _w), 'Paragraph Complex');
        for (final tag in [
          'b',
          'i',
          'strike',
          'dstrike',
          'caps',
          'smallCaps',
        ]) {
          expect(
            style
                .getElement(tag, namespace: _w)!
                .getAttribute('val', namespace: _w),
            '1',
          );
        }
        for (final (tag, value) in [
          ('u', 'double'),
          ('sz', '30'),
          ('color', '123456'),
          ('vertAlign', 'superscript'),
          ('position', '2'),
          ('spacing', '15'),
          ('kern', '8'),
        ]) {
          expect(
            style
                .getElement(tag, namespace: _w)!
                .getAttribute('val', namespace: _w),
            value,
          );
        }
        expect(
          style
              .getElement('shd', namespace: _w)!
              .getAttribute('fill', namespace: _w),
          '654321',
        );
        expect(marker.toXmlString(), isNot(contains('Body Only')));
      },
    );
  }

  test('hidden materialized marker stays hidden without hiding body text', () {
    final document = _model(const [
      LegacyWordNumberingLevel(
        level: 0,
        format: 'decimal',
        text: '%1',
        placeholderOffsets: [],
        characterStyle: LegacyWordCharacterStyle(hidden: true),
      ),
    ]);
    expect(_labels(document), isEmpty);
    final paragraph = _part(
      convertLegacyWordDocument(document),
      'word/document.xml',
    ).findAllElements('p', namespace: _w).single;
    final runs = paragraph.findElements('r', namespace: _w).toList();
    expect(
      runs.first
          .findAllElements('vanish', namespace: _w)
          .single
          .getAttribute('val', namespace: _w),
      '1',
    );
    expect(
      runs.last
          .findAllElements('vanish', namespace: _w)
          .single
          .getAttribute('val', namespace: _w),
      '0',
    );
    expect(runs.last.findAllElements('t', namespace: _w).single.innerText, 'x');
  });

  test(
    'synthetic label leaves field/bookmark/note/revision event XML unchanged',
    () {
      const sourceText = '\x13 PAGE \x142\x15Z\r';
      final parsed = parseLegacyWordDocument(
        storyWordFixture(main: sourceText),
      );
      final old = parsed.blocks.single as LegacyWordParagraph;
      LegacyWordDocument document(bool numbered) => LegacyWordDocument(
        blocks: [
          LegacyWordParagraph(
            startCp: old.startCp,
            endCp: old.endCp,
            mark: old.mark,
            style: LegacyWordParagraphStyle(listId: numbered ? 1 : null),
            runs: [
              for (final run in old.runs)
                LegacyWordRun(
                  startCp: run.startCp,
                  endCp: run.endCp,
                  text: run.text,
                  style: run.style,
                  deleted: run.text == '2',
                  inserted: run.text == 'Z',
                  deletionRevision: const LegacyWordRevisionInfo(
                    author: 'Deleted Author',
                  ),
                  insertionRevision: const LegacyWordRevisionInfo(
                    author: 'Inserted Author',
                  ),
                ),
            ],
          ),
        ],
        sections: parsed.sections,
        plainText: parsed.plainText,
        safeHtml: '',
        fields: parsed.fields,
        bookmarks: [
          LegacyWordBookmark(
            name: 'AcrossField',
            startCp: 0,
            endCp: sourceText.length - 1,
          ),
        ],
        stories: const [
          LegacyWordStory(
            id: 'note',
            kind: LegacyWordStoryKind.footnote,
            startCp: 100,
            endCp: 105,
            plainText: 'Note',
            safeHtml: '',
            blocks: [
              LegacyWordParagraph(
                startCp: 100,
                endCp: 105,
                runs: [LegacyWordRun(startCp: 100, endCp: 104, text: 'Note')],
              ),
            ],
          ),
        ],
        noteReferences: [
          LegacyWordNoteReference(
            id: 1,
            anchorCp: sourceText.length - 2,
            storyId: 'note',
            endnote: false,
          ),
        ],
        numbering: numbered
            ? const [
                LegacyWordNumberingDefinition(
                  id: 1,
                  levels: [
                    LegacyWordNumberingLevel(
                      level: 0,
                      format: 'decimal',
                      text: '%1',
                      placeholderOffsets: [],
                    ),
                  ],
                ),
              ]
            : const [],
      );
      final baseline = convertLegacyWordDocument(document(false));
      final output = convertLegacyWordDocument(document(true));
      final before = _part(baseline, 'word/document.xml');
      final after = _part(output, 'word/document.xml');
      final paragraph = after.findAllElements('p', namespace: _w).single;
      final prefix = paragraph.childElements.elementAt(1);
      expect(prefix.name.local, 'r');
      expect(prefix.findAllElements('t', namespace: _w).single.innerText, '%1');
      expect(prefix.findAllElements('fldChar', namespace: _w), isEmpty);
      expect(
        paragraph.childElements
            .elementAt(2)
            .findAllElements('fldChar', namespace: _w)
            .single
            .getAttribute('fldCharType', namespace: _w),
        'begin',
      );
      expect(
        paragraph.findElements('bookmarkStart', namespace: _w),
        hasLength(1),
      );
      paragraph.children.remove(prefix);
      final numPr = paragraph.findAllElements('numPr', namespace: _w).single;
      numPr.parent!.children.remove(numPr);
      expect(after.toXmlString(), before.toXmlString());
      expect(
        _part(output, 'word/footnotes.xml').toXmlString(),
        _part(baseline, 'word/footnotes.xml').toXmlString(),
      );
      expect(
        after.findAllElements('delText', namespace: _w).single.innerText,
        '2',
      );
      expect(after.findAllElements('ins', namespace: _w).single.innerText, 'Z');
    },
  );

  test(
    'literal numbering history is qualified and retained without fake revision behavior',
    () {
      final document = _model(
        const [
          LegacyWordNumberingLevel(
            level: 0,
            format: 'decimal',
            text: '%1',
            placeholderOffsets: [],
          ),
        ],
        paragraphs: [
          LegacyWordParagraph(
            startCp: 0,
            endCp: 2,
            style: const LegacyWordParagraphStyle(listId: 1),
            runs: const [LegacyWordRun(startCp: 0, endCp: 1, text: 'x')],
            numberingRevision: LegacyWordNumberingRevision(
              previouslyNumbered: true,
              original: '%1:3:0:.',
              inserted: true,
              revision: const LegacyWordRevisionInfo(
                author: 'Author',
                authorIndex: 2,
              ),
            ),
          ),
        ],
      );
      final result = convertLegacyWordDocument(document);
      expect(
        result.limitations,
        containsAll([
          LegacyWordConversionLimitation.revisions,
          LegacyWordConversionLimitation.fieldsLists,
        ]),
      );
      final xml = _part(result, 'word/document.xml');
      expect(xml.findAllElements('numberingChange', namespace: _w), isEmpty);
      expect(xml.findAllElements('ins', namespace: _w), isEmpty);
      final evidence = _evidence(
        result,
      ).singleWhere((record) => record['kind'] == 'materializedNumbering');
      expect(evidence['originalNumbering'], '%1:3:0:.');
      expect(evidence['numberingInserted'], true);
      expect(evidence['previouslyNumbered'], true);
      expect(evidence['authorIndex'], 2);
      expect(evidence['revision'], {
        'author': 'Author',
        'time': null,
        'authorIndex': 2,
        'rawDate': null,
        'saveId': null,
        'reason': null,
      });
    },
  );

  test(
    'previous property wall cannot activate an ambiguous literal template',
    () {
      final document = _model(
        const [
          LegacyWordNumberingLevel(
            level: 0,
            format: 'decimal',
            text: '%1',
            placeholderOffsets: [],
          ),
        ],
        paragraphs: [
          const LegacyWordParagraph(
            startCp: 0,
            endCp: 2,
            runs: [LegacyWordRun(startCp: 0, endCp: 1, text: 'x')],
            formattingRevision: LegacyWordParagraphFormattingRevision(
              previousStyle: LegacyWordParagraphStyle(listId: 1),
              revision: LegacyWordRevisionInfo(author: 'Author'),
            ),
          ),
        ],
      );
      final result = convertLegacyWordDocument(document);
      expect(
        result.limitations,
        containsAll([
          LegacyWordConversionLimitation.revisions,
          LegacyWordConversionLimitation.fieldsLists,
        ]),
      );
      final xml = _part(result, 'word/document.xml');
      expect(
        xml
            .findAllElements('numId', namespace: _w)
            .single
            .getAttribute('val', namespace: _w),
        '0',
      );
      expect(
        _evidence(
          result,
        ).any((record) => record['kind'] == 'previousLiteralNumbering'),
        isTrue,
      );
    },
  );

  test('native editable markers retain every modeled character property', () {
    final document = _model(const [
      LegacyWordNumberingLevel(
        level: 0,
        format: 'decimal',
        text: '%1.',
        characterStyle: LegacyWordCharacterStyle(
          allCaps: true,
          smallCaps: true,
          strike: true,
          doubleStrike: true,
          spacingTwips: -15,
          positionHalfPoints: 2,
          highlightHex: '654321',
          verticalAlign: LegacyWordVerticalAlignment.subscript,
        ),
      ),
    ]);
    final result = convertLegacyWordDocument(document);
    final style = _part(
      result,
      'word/numbering.xml',
    ).findAllElements('rPr', namespace: _w).single;
    for (final (tag, value) in [
      ('caps', '1'),
      ('smallCaps', '1'),
      ('strike', '1'),
      ('dstrike', '1'),
      ('spacing', '-15'),
      ('position', '2'),
      ('vertAlign', 'subscript'),
    ]) {
      expect(
        style
            .getElement(tag, namespace: _w)
            ?.getAttribute('val', namespace: _w),
        value,
      );
    }
    expect(
      style
          .getElement('shd', namespace: _w)
          ?.getAttribute('fill', namespace: _w),
      '654321',
    );
    expect(result.preservedCounts['materializedNumberingLabels'], isNull);
  });

  test(
    'cross-paragraph field results explicitly qualify synthetic label updates',
    () {
      const source = 'A\x13 QUOTE "source" \x14Result\rNext\x15Z\r';
      final document = _crossParagraphField(source);
      final cached = document.fields.single.storedResult;
      final baseline = convertLegacyWordDocument(
        _crossParagraphField(source, numbered: false),
      );
      final result = convertLegacyWordDocument(document);
      final xml = _part(result, 'word/document.xml');
      final paragraph = xml.findAllElements('p', namespace: _w).last;
      final prefix = paragraph.findElements('r', namespace: _w).first;
      expect(prefix.findAllElements('t', namespace: _w).single.innerText, '%1');
      paragraph.children.remove(prefix);
      final numPr = paragraph
          .getElement('pPr', namespace: _w)!
          .getElement('numPr', namespace: _w)!;
      numPr.parent!.children.remove(numPr);
      expect(
        xml.toXmlString(),
        _part(baseline, 'word/document.xml').toXmlString(),
      );
      final context = _evidence(result).singleWhere(
        (record) => record['kind'] == 'materializedNumberingFieldContext',
      );
      expect(context['containingFields'], [
        {'id': document.fields.single.id, 'phase': 'result', 'active': true},
      ]);
      expect(context['reason'], contains('recalculation can replace'));
      expect(document.fields.single.storedResult, cached);
    },
  );

  test('cross-paragraph instructions suppress labels in both field modes', () {
    final document = _crossParagraphField(
      'A\x13 QUOTE "before\r after" \x14Value\x15Z\r',
    );
    for (final mode in LegacyWordFieldMode.values) {
      final result = convertLegacyWordDocument(document, fieldMode: mode);
      final xml = _part(result, 'word/document.xml');
      expect(
        xml.findAllElements('t', namespace: _w).map((node) => node.innerText),
        isNot(contains('%1')),
      );
      expect(result.preservedCounts['suppressedNumberingLabels'], 1);
      final evidence = _evidence(
        result,
      ).singleWhere((record) => record['kind'] == 'suppressedFieldNumbering');
      expect(evidence['cp'], document.blocks.last.startCp);
      if (mode == LegacyWordFieldMode.cachedResults) {
        expect(xml.findAllElements('fldChar', namespace: _w), isEmpty);
      }
    }
  });

  test('inert cross-paragraph instructions suppress source-hidden labels', () {
    final document = _crossParagraphField(
      'A\x13 DDEAUTO server\r topic item \x14Value\x15Z\r',
    );
    final result = convertLegacyWordDocument(document);
    final xml = _part(result, 'word/document.xml');
    expect(xml.findAllElements('fldChar', namespace: _w), isEmpty);
    expect(xml.findAllElements('instrText', namespace: _w), isEmpty);
    expect(
      xml.findAllElements('t', namespace: _w).map((node) => node.innerText),
      isNot(contains('%1')),
    );
    expect(result.preservedCounts['suppressedNumberingLabels'], 1);
    final context = _evidence(
      result,
    ).singleWhere((record) => record['kind'] == 'suppressedFieldNumbering');
    expect(context['cp'], document.blocks.last.startCp);
  });
}
