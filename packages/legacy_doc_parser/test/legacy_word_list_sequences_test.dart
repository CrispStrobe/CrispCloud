// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/list_sequence_fixture.dart';
import 'support/list_word_fixture.dart';
import 'support/structured_word_fixture.dart';

List<String> _labels(String html) =>
    RegExp(r'<span data-word-list-label="true"[^>]*>(.*?)</span>', dotAll: true)
        .allMatches(html)
        .map((match) => match.group(1)!.replaceAll(RegExp('<[^>]*>'), ''))
        .toList();

Map<String, XmlDocument> _xml(LegacyWordDocument document) {
  final archive = ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  );
  return {
    for (final name in [
      'word/document.xml',
      'word/numbering.xml',
      'word/footnotes.xml',
    ])
      if (archive.findFile(name) case final entry?)
        name: XmlDocument.parse(utf8.decode(entry.content)),
  };
}

List<String> _ids(XmlDocument document) => document
    .findAllElements('w:numId')
    .map((e) => e.getAttribute('w:val')!)
    .toList();

Map<String, Map<int, int>> _starts(XmlDocument numbering) => {
  for (final num in numbering.findAllElements('w:num'))
    num.getAttribute('w:numId')!: {
      for (final override in num.findElements('w:lvlOverride'))
        int.parse(override.getAttribute('w:ilvl')!): int.parse(
          override.getElement('w:startOverride')!.getAttribute('w:val')!,
        ),
    },
};

LegacyWordParagraph _item(int cp, {int id = 1, int level = 0}) =>
    LegacyWordParagraph(
      startCp: cp,
      endCp: cp + 2,
      style: LegacyWordParagraphStyle(listId: id, listLevel: level),
      runs: [LegacyWordRun(startCp: cp, endCp: cp + 1, text: 'x')],
    );

void main() {
  test(
    'distinct unmodified LFOs continue a shared LSID and remain editable',
    () {
      final bytes = listSequenceFixture([
        (1, 0),
        (1, 0),
        (2, 0),
        (2, 0),
        (1, 0),
      ]);
      final original = Uint8List.fromList(bytes);
      final document = parseLegacyWordDocument(bytes);
      expect(_labels(document.safeHtml), ['1.', '2.', '3.', '4.', '5.']);
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.numberingNotReconstructed)),
      );
      final files = _xml(document), ids = _ids(files['word/document.xml']!);
      // Identical unmodified instances can share one editable native sequence.
      expect(ids.toSet(), hasLength(1));
      expect(
        files['word/numbering.xml']!.findAllElements('w:num'),
        hasLength(1),
      );
      expect(
        files['word/document.xml']!
            .findAllElements('w:t')
            .map((e) => e.innerText),
        ['P1', 'P2', 'P3', 'P4', 'P5'],
      );
      expect(bytes, original);
    },
  );

  test('explicit start override retains its separate restart sequence', () {
    final bytes = listSequenceFixture(
      [(1, 0), (1, 0), (2, 0), (2, 0), (1, 0), (2, 0)],
      overrides: [
        [],
        [
          [...wordU32(7), ...wordU32(0x10)],
        ],
      ],
    );
    final document = parseLegacyWordDocument(bytes);
    expect(document.numbering[1].startOverrides, {0: 7});
    expect(document.numbering[0].startOverrides, isEmpty);
    expect(
      document.warnings,
      contains(LegacyWordWarning.numberingNotReconstructed),
    );
    expect(_labels(document.safeHtml), ['1.', '2.', '7.', '8.', '3.', '9.']);
    final files = _xml(document), ids = _ids(files['word/document.xml']!);
    expect(ids[4], ids[0]);
    expect(ids[5], ids[2]);
    expect(ids.toSet(), hasLength(2));
    expect(
      files['word/numbering.xml']!
          .findAllElements('w:start')
          .map((e) => e.getAttribute('w:val')),
      contains('7'),
    );
  });

  test(
    'format override can continue a number while retaining Roman labels',
    () {
      final bytes = listSequenceFixture(
        [(1, 0), (1, 0), (2, 0), (2, 0), (1, 0)],
        overrides: [
          [],
          [
            [
              ...wordU32(0xffffffff),
              ...wordU32(0x20),
              ...listFixtureLevel(format: 1),
            ],
          ],
        ],
      );
      final document = parseLegacyWordDocument(bytes);
      expect(document.numbering[1].startOverrides, isEmpty);
      expect(_labels(document.safeHtml), ['1.', '2.', 'III.', 'IV.', '5.']);
      final files = _xml(document), ids = _ids(files['word/document.xml']!);
      expect(_starts(files['word/numbering.xml']!)[ids[2]]![0], 3);
      expect(
        files['word/numbering.xml']!
            .findAllElements('w:numFmt')
            .map((e) => e.getAttribute('w:val')),
        contains('upperRoman'),
      );
    },
  );

  test(
    'formatting and start flags use the overriding LVL, not undefined iStartAt',
    () {
      final document = parseLegacyWordDocument(
        listSequenceFixture(
          [(1, 0), (2, 0)],
          overrides: [
            [],
            [
              [
                ...wordU32(0xffffffff),
                ...wordU32(0x30),
                ...listFixtureLevel(format: 1, start: 9),
              ],
            ],
          ],
        ),
      );
      expect(document.numbering[1].startOverrides, {0: 9});
      expect(_labels(document.safeHtml), ['1.', 'IX.']);
    },
  );

  test('resumed native instances retain paragraph numbering revisions', () {
    final parsed = parseLegacyWordDocument(
      listSequenceFixture(
        [(1, 0), (1, 0), (2, 0), (2, 0), (1, 0)],
        overrides: [
          [],
          [
            [
              ...wordU32(0xffffffff),
              ...wordU32(0x20),
              ...listFixtureLevel(format: 1),
            ],
          ],
        ],
      ),
    );
    final last = parsed.blocks.last as LegacyWordParagraph;
    final document = LegacyWordDocument(
      blocks: [
        ...parsed.blocks.take(parsed.blocks.length - 1),
        LegacyWordParagraph(
          startCp: last.startCp,
          endCp: last.endCp,
          style: last.style,
          runs: last.runs,
          numberingRevision: LegacyWordNumberingRevision(
            previouslyNumbered: true,
            original: '%1:4:0:.',
            inserted: true,
            revision: const LegacyWordRevisionInfo(author: 'Reviewer'),
          ),
        ),
      ],
      sections: parsed.sections,
      plainText: parsed.plainText,
      safeHtml: parsed.safeHtml,
      numbering: parsed.numbering,
    );
    final files = _xml(document), main = files['word/document.xml']!;
    final ids = _ids(main);
    expect(ids.last, isNot(ids.first));
    expect(_starts(files['word/numbering.xml']!)[ids.last]![0], 5);
    final properties = main.findAllElements('w:numPr').last;
    expect(
      properties
          .findElements('w:numberingChange')
          .single
          .getAttribute('w:original'),
      '%1:4:0:.',
    );
    expect(
      properties.findElements('w:ins').single.getAttribute('w:author'),
      'Reviewer',
    );
  });

  test('same level on distinct source lists remains independent', () {
    final document = parseLegacyWordDocument(
      listSequenceFixture(
        [(1, 0), (2, 0), (1, 0), (2, 0)],
        sourceIds: [42, 99],
      ),
    );
    expect(_labels(document.safeHtml), ['1.', '1.', '2.', '2.']);
  });

  test(
    'source ancestor references use the same ILFO while counters share LSID',
    () {
      final levels = [
        for (var level = 0; level < 9; level++)
          listFixtureLevel(
            level: level,
            text: level == 1 ? '\x00.\x01)' : null,
            placeholders: level == 1 ? [1, 3] : null,
          ),
      ];
      final document = parseLegacyWordDocument(
        listSequenceFixture([
          (1, 0),
          (1, 1),
          (2, 1),
          (2, 0),
          (1, 1),
        ], levels: levels),
      );
      expect(_labels(document.safeHtml), ['1.', '1.1)', '1.2)', '2.', '1.1)']);
      final files = _xml(document), ids = _ids(files['word/document.xml']!);
      expect(ids[4], isNot(ids[0]));
      final restart = _starts(files['word/numbering.xml']!)[ids[4]]!;
      // The new real numbering instance resets to the original instance's
      // ancestor1; it must not borrow ancestor2 from the other source ILFO.
      expect(restart[0] ?? 1, 1);
      expect(restart[1] ?? 1, 1);
    },
  );

  test(
    'never-restart lower level survives higher shared-instance paragraphs',
    () {
      final levels = [
        for (var level = 0; level < 9; level++)
          listFixtureLevel(
            level: level,
            text: level == 1 ? '\x00.\x01)' : null,
            placeholders: level == 1 ? [1, 3] : null,
            flags: level == 1 ? 8 : 0,
            restart: 0,
          ),
      ];
      final document = parseLegacyWordDocument(
        listSequenceFixture([
          (1, 0),
          (1, 1),
          (2, 1),
          (2, 0),
          (1, 1),
        ], levels: levels),
      );
      expect(_labels(document.safeHtml), ['1.', '1.1)', '1.2)', '2.', '1.3)']);
      final files = _xml(document);
      expect(
        files['word/numbering.xml']!
            .findAllElements('w:lvlRestart')
            .map((e) => e.getAttribute('w:val')),
        contains('0'),
      );
    },
  );

  test('legal numbering keeps decimalZero ancestor formatting', () {
    final levels = [
      for (var level = 0; level < 9; level++)
        listFixtureLevel(
          level: level,
          format: level == 0 ? 22 : 0,
          text: level == 1 ? '\x00.\x01)' : null,
          placeholders: level == 1 ? [1, 3] : null,
          flags: level == 1 ? 4 : 0,
        ),
    ];
    final document = parseLegacyWordDocument(
      listSequenceFixture([(1, 0), (1, 1)], levels: levels),
    );
    expect(_labels(document.safeHtml), ['01.', '01.1)']);
  });

  test(
    'hidden marker style remains hidden in HTML and actual numbering XML',
    () {
      final source = listSequenceFixture(
        [(1, 0)],
        levels: [
          listFixtureLevel(
            format: 23,
            text: 'X',
            placeholders: [],
            character: wordSprm(0x083c, [1]),
          ),
        ],
      );
      final document = parseLegacyWordDocument(source);
      expect(_labels(document.safeHtml), isEmpty);
      final files = _xml(document);
      expect(
        files['word/numbering.xml']!.findAllElements('w:vanish'),
        hasLength(1),
      );
      expect(
        files['word/document.xml']!.findAllElements('w:t').single.innerText,
        'P1',
      );
    },
  );

  test(
    'separate note stories receive independent real numbering instances',
    () {
      final document = LegacyWordDocument(
        blocks: [_item(0), _item(2)],
        sections: const [],
        plainText: '',
        safeHtml: '',
        numbering: const [
          LegacyWordNumberingDefinition(
            id: 1,
            sourceListId: 42,
            levels: [
              LegacyWordNumberingLevel(
                level: 0,
                format: 'decimal',
                text: '%1.',
              ),
            ],
          ),
        ],
        stories: [
          LegacyWordStory(
            id: 'note1',
            kind: LegacyWordStoryKind.footnote,
            startCp: 4,
            endCp: 6,
            blocks: [_item(4)],
            plainText: 'x',
            safeHtml: '',
          ),
        ],
        noteReferences: const [
          LegacyWordNoteReference(
            id: 1,
            anchorCp: 0,
            storyId: 'note1',
            endnote: false,
          ),
        ],
      );
      final files = _xml(document);
      final main = _ids(files['word/document.xml']!),
          note = _ids(files['word/footnotes.xml']!);
      expect(main.toSet(), hasLength(1));
      expect(note.single, isNot(main.first));
      expect(_starts(files['word/numbering.xml']!)[note.single]![0] ?? 1, 1);
    },
  );

  test(
    'conflicting base policies stay disclosed instead of guessed continuation',
    () {
      final source = listSequenceFixture(
        [(1, 0), (2, 0)],
        overrides: [
          [],
          [
            [...wordU32(0), ...wordU32(0x20), ...listFixtureLevel(start: 9)],
          ],
        ],
      );
      final document = parseLegacyWordDocument(source);
      expect(
        document.warnings,
        contains(LegacyWordWarning.numberingNotReconstructed),
      );
      expect(
        document.safeHtml,
        contains('data-word-numbering="instance-approximation"'),
      );
      expect(
        convertLegacyWordDocument(document).limitations,
        contains(LegacyWordConversionLimitation.fieldsLists),
      );
    },
  );

  for (final overrides in [
    {1: 7},
    {0: -1},
    {0: 32768},
  ]) {
    test('rejects invalid explicit start metadata $overrides', () {
      final document = LegacyWordDocument(
        blocks: [_item(0)],
        sections: const [],
        plainText: '',
        safeHtml: '',
        numbering: [
          LegacyWordNumberingDefinition(
            id: 1,
            startOverrides: overrides,
            levels: const [
              LegacyWordNumberingLevel(
                level: 0,
                format: 'decimal',
                text: '%1.',
              ),
            ],
          ),
        ],
      );
      expect(() => convertLegacyWordDocument(document), throwsFormatException);
    });
  }
}
