// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _date = 45 | (8 << 6) | (12 << 11) | (11 << 16) | (126 << 20);
const _date2 = 15 | (9 << 6) | (12 << 11) | (11 << 16) | (126 << 20);
List<int> _property(int code, int value) => wordSprm(code, [value]);
List<int> _mark(
  int code, {
  int enabled = 1,
  int author = 1,
  int date = _date,
}) => wordSprm(code, [7, enabled, ...wordU16(author), ...wordU32(date)]);
List<int> _authors() => [
  ...wordU16(0xffff),
  ...wordU16(3),
  ...wordU16(0),
  for (final name in ['Unknown', 'Alice', 'Bob']) ...[
    ...wordU16(name.length),
    for (final c in name.codeUnits) ...wordU16(c),
  ],
];
Uint8List _source({
  List<int> character = const [],
  List<int> paragraph = const [],
  Map<int, WordFixtureStyle>? styles,
  List<WordFixtureFkpRun>? runs,
}) => StructuredWordFixture(
  pieces: const [WordFixturePiece('Text\r')],
  characterRuns: runs ?? [WordFixtureFkpRun(8192, 8197, properties: character)],
  paragraphRuns: [WordFixtureFkpRun(8192, 8197, properties: paragraph)],
  styles: styles ?? const {0: WordFixtureStyle(name: 'Normal', builtinId: 0)},
  extraTablePairs: {51: _authors()},
).build();
LegacyWordParagraph _paragraph(LegacyWordDocument value) =>
    value.blocks.single as LegacyWordParagraph;
Map<String, Uint8List> _parts(Uint8List value) => {
  for (final file in ZipDecoder().decodeBytes(value))
    if (file.isFile) file.name: file.content,
};
XmlDocument _xml(Uint8List value) =>
    XmlDocument.parse(utf8.decode(_parts(value)['word/document.xml']!));
Iterable<XmlElement> _elements(XmlNode node, String name) =>
    node.findAllElements(name, namespace: _w);
String? _attr(XmlElement node, String name) =>
    node.getAttribute(name, namespace: _w);

void main() {
  test(
    'CWall captures previous character properties before current changes',
    () {
      final document = parseLegacyWordDocument(
        _source(
          character: [
            ..._property(0x0835, 1),
            ...wordSprm(0x4a43, wordU16(24)),
            ..._property(0x2a83, 1),
            ..._property(0x0835, 0),
            ..._property(0x0836, 1),
            ...wordSprm(0x4a43, wordU16(36)),
            ..._mark(0xca89),
          ],
        ),
      );
      final run = _paragraph(document).runs.single;
      expect(run.style.bold, isFalse);
      expect(run.style.italic, isTrue);
      expect(run.style.fontSizeHalfPoints, 36);
      final change = run.formattingRevision!;
      expect(change.previousStyle!.bold, isTrue);
      expect(change.previousStyle!.italic, isFalse);
      expect(change.previousStyle!.fontSizeHalfPoints, 24);
      expect(change.revision.author, 'Alice');
      expect(change.revision.rawDate, _date);
      expect(change.revision.time, DateTime.utc(2026, 11, 12, 8, 45));
      expect(document.plainText, 'Text');
      expect(
        document.safeHtml,
        contains('data-word-formatting-revision="character"'),
      );
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.revisionMetadataIncomplete)),
      );

      final result = convertLegacyWordDocument(document);
      final xml = _xml(result.bytes);
      final current = _elements(
        xml,
        'r',
      ).first.getElement('rPr', namespace: _w)!;
      final changeXml = current.getElement('rPrChange', namespace: _w)!;
      expect(current.childElements.last, same(changeXml));
      expect(_attr(changeXml, 'author'), 'Alice');
      expect(_attr(changeXml, 'date'), '2026-11-12T08:45:00');
      final previous = changeXml.getElement('rPr', namespace: _w)!;
      expect(_attr(previous.getElement('b', namespace: _w)!, 'val'), '1');
      expect(_attr(previous.getElement('i', namespace: _w)!, 'val'), '0');
      expect(_attr(previous.getElement('sz', namespace: _w)!, 'val'), '24');
      expect(
        result.preservedCounts['characterFormattingRevisions'],
        2,
        reason: 'text and its separately revised paragraph mark',
      );
    },
  );

  test(
    'CPlain and a character style preserve the wall snapshot and metadata',
    () {
      final document = parseLegacyWordDocument(
        _source(
          character: [
            ..._property(0x0835, 1),
            ..._property(0x2a83, 1),
            ..._mark(0xca57),
            ...wordSprm(0x4a30, wordU16(20)),
            ..._property(0x2a33, 0),
          ],
          styles: {
            0: const WordFixtureStyle(name: 'Normal', builtinId: 0),
            20: WordFixtureStyle(
              name: 'Emphasis',
              character: true,
              characterProperties: _property(0x0836, 1),
            ),
          },
        ),
      );
      final run = _paragraph(document).runs.single;
      expect(run.style.bold, isFalse);
      expect(run.style.italic, isFalse);
      expect(run.formattingRevision!.previousStyle!.bold, isTrue);
      expect(run.formattingRevision!.revision.author, 'Alice');
    },
  );

  test(
    'false wall clears earlier snapshot and missing snapshots stay evidence',
    () {
      final document = parseLegacyWordDocument(
        _source(
          character: [
            ..._property(0x2a83, 1),
            ..._property(0x0835, 1),
            ..._property(0x2a83, 0),
            ..._mark(0xca89),
          ],
        ),
      );
      final change = _paragraph(document).runs.single.formattingRevision!;
      expect(change.previousStyle, isNull);
      final result = convertLegacyWordDocument(document);
      expect(_elements(_xml(result.bytes), 'rPrChange'), isEmpty);
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.revisions),
      );
      expect(
        _parts(result.bytes).keys,
        contains('word/evidence/manifest.json'),
      );
    },
  );

  test('PWall snapshots before a later paragraph-style reset', () {
    final document = parseLegacyWordDocument(
      _source(
        paragraph: [
          ...wordSprm(0x840f, wordU16(360)),
          ..._property(0x2664, 1),
          ...wordSprm(0x4600, wordU16(1)),
          ..._mark(0xc66f, author: 2),
          ...wordSprm(0x6467, wordU32(0x10203040)),
        ],
        styles: {
          0: const WordFixtureStyle(name: 'Normal', builtinId: 0),
          1: WordFixtureStyle(
            name: 'Heading 1',
            builtinId: 1,
            paragraphProperties: _property(0x2403, 2),
            characterProperties: _property(0x0835, 1),
          ),
        },
      ),
    );
    final paragraph = _paragraph(document);
    expect(paragraph.style.styleIndex, 1);
    expect(paragraph.style.headingLevel, 1);
    expect(paragraph.style.leftIndentTwips, 0);
    expect(paragraph.runs.single.style.bold, isTrue);
    final old = paragraph.formattingRevision!;
    expect(old.previousStyle!.styleIndex, 0);
    expect(old.previousStyle!.leftIndentTwips, 360);
    expect(old.previousStyle!.headingLevel, isNull);
    expect(old.revision.author, 'Bob');
    final xml = _xml(convertLegacyWordDocument(document).bytes);
    final p = _elements(xml, 'p').first;
    expect(_attr(p, 'rsidP'), '10203040');
    final ppr = p.getElement('pPr', namespace: _w)!;
    expect(ppr.childElements.last.name.local, 'pPrChange');
    final change = ppr.getElement('pPrChange', namespace: _w)!;
    expect(_attr(change, 'author'), 'Bob');
    final previous = change.getElement('pPr', namespace: _w)!;
    expect(_attr(previous.getElement('ind', namespace: _w)!, 'left'), '360');
    expect(
      _attr(previous.getElement('pStyle', namespace: _w)!, 'val'),
      'Legacy0',
    );
  });

  test(
    'simultaneous insertion and deletion retain distinct authors and times',
    () {
      final source = _source(
        character: [
          ..._property(0x0801, 1),
          ...wordSprm(0x4804, wordU16(1)),
          ...wordSprm(0x6805, wordU32(_date)),
          ...wordSprm(0x6816, wordU32(0x11)),
          ..._property(0x0800, 1),
          ...wordSprm(0x4863, wordU16(2)),
          ...wordSprm(0x6864, wordU32(_date2)),
          ...wordSprm(0x6817, wordU32(0x22)),
        ],
      );
      final document = parseLegacyWordDocument(source);
      final run = _paragraph(document).runs.single;
      expect(run.insertionRevision!.author, 'Alice');
      expect(run.deletionRevision!.author, 'Bob');
      expect(run.revisionAuthor, 'Bob');
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.revisionMetadataIncomplete)),
      );
      final xml = _xml(convertLegacyWordDocument(document).bytes);
      final ins = _elements(
        xml,
        'ins',
      ).singleWhere((e) => e.childElements.isNotEmpty);
      final del = ins.getElement('del', namespace: _w)!;
      expect(_attr(ins, 'author'), 'Alice');
      expect(_attr(ins, 'date'), '2026-11-12T08:45:00');
      expect(_attr(del, 'author'), 'Bob');
      expect(_attr(del, 'date'), '2026-11-12T09:15:00');
      final outputRun = del.getElement('r', namespace: _w)!;
      expect(_attr(outputRun, 'rsidR'), '00000011');
      expect(_attr(outputRun, 'rsidDel'), '00000022');
      expect(outputRun.getElement('delText', namespace: _w)!.innerText, 'Text');
    },
  );

  test(
    'a deleted paragraph mark never marks ordinary paragraph text deleted',
    () {
      final document = parseLegacyWordDocument(
        _source(
          runs: [
            const WordFixtureFkpRun(8192, 8196),
            WordFixtureFkpRun(
              8196,
              8197,
              properties: [
                ..._property(0x0800, 1),
                ...wordSprm(0x4863, wordU16(2)),
                ...wordSprm(0x6864, wordU32(_date2)),
              ],
            ),
          ],
        ),
      );
      final paragraph = _paragraph(document);
      expect(paragraph.runs.single.deleted, isFalse);
      expect(paragraph.mark!.deleted, isTrue);
      expect(document.safeHtml, contains('data-word-paragraph-mark="deleted"'));
      final xml = _xml(convertLegacyWordDocument(document).bytes);
      expect(_elements(xml, 'delText'), isEmpty);
      expect(_elements(xml, 't').single.innerText, 'Text');
      final deletion = _elements(xml, 'del').single;
      expect(deletion.parentElement!.name.local, 'rPr');
      expect(deletion.parentElement!.parentElement!.name.local, 'pPr');
      expect(_attr(deletion, 'author'), 'Bob');
    },
  );

  test(
    'unsupported prior properties produce a specific revision limitation',
    () {
      final document = parseLegacyWordDocument(
        _source(
          character: [
            ..._property(0x0854, 1),
            ..._property(0x2a83, 1),
            ..._property(0x0835, 1),
            ..._mark(0xca89),
          ],
        ),
      );
      expect(
        _paragraph(
          document,
        ).runs.single.formattingRevision!.previousPropertiesComplete,
        isFalse,
      );
      expect(
        document.warnings,
        contains(LegacyWordWarning.revisionMetadataIncomplete),
      );
      expect(
        convertLegacyWordDocument(document).limitations,
        contains(LegacyWordConversionLimitation.revisions),
      );
    },
  );

  for (final (inserted, deleted) in [
    (true, false),
    (false, true),
    (true, true),
  ]) {
    test(
      'styled paragraph mark orders insertion=$inserted deletion=$deleted before current properties',
      () {
        final document = parseLegacyWordDocument(
          _source(
            character: [
              ..._property(0x0835, 1),
              ..._property(0x2a83, 1),
              ..._property(0x083c, 1),
              ..._mark(0xca89),
              ..._property(0x0801, inserted ? 1 : 0),
              ..._property(0x0800, deleted ? 1 : 0),
              ...wordSprm(0x4804, wordU16(1)),
              ...wordSprm(0x6805, wordU32(_date)),
              ...wordSprm(0x4863, wordU16(2)),
              ...wordSprm(0x6864, wordU32(_date2)),
            ],
          ),
        );
        final xml = _xml(convertLegacyWordDocument(document).bytes);
        final mark = _elements(
          xml,
          'pPr',
        ).single.getElement('rPr', namespace: _w)!;
        final names = mark.childElements.map((e) => e.name.local).toList();
        final revisions = [if (inserted) 'ins', if (deleted) 'del'];
        expect(names.take(revisions.length), revisions);
        expect(names.last, 'rPrChange');
        expect(_attr(mark.getElement('b', namespace: _w)!, 'val'), '1');
        expect(_attr(mark.getElement('vanish', namespace: _w)!, 'val'), '1');
        final previous = mark
            .getElement('rPrChange', namespace: _w)!
            .getElement('rPr', namespace: _w)!;
        expect(_attr(previous.getElement('b', namespace: _w)!, 'val'), '1');
        expect(
          _attr(previous.getElement('vanish', namespace: _w)!, 'val'),
          '0',
        );
      },
    );
  }

  test('preview does not reveal old or current hidden revision text', () {
    final document = parseLegacyWordDocument(
      _source(
        character: [
          ..._property(0x2a83, 1),
          ..._property(0x083c, 1),
          ..._mark(0xca89),
          ..._property(0x0800, 1),
        ],
      ),
    );
    expect(document.safeHtml, isNot(contains('Text')));
    expect(document.safeHtml, isNot(contains('¶')));
    expect(
      _paragraph(
        document,
      ).runs.single.formattingRevision!.previousStyle!.hidden,
      isFalse,
    );
  });

  for (final code in [0xca57, 0xca89, 0xc63f, 0xc66f]) {
    test('rejects invalid property revision operand $code', () {
      for (final value in [
        [6, ...List.filled(6, 0)],
        [7, 2, ...List.filled(6, 0)],
      ]) {
        final operation = wordSprm(code, value);
        expect(
          () => parseLegacyWordDocument(
            _source(
              character: code == 0xca57 || code == 0xca89
                  ? operation
                  : const [],
              paragraph: code == 0xc63f || code == 0xc66f
                  ? operation
                  : const [],
            ),
          ),
          throwsFormatException,
        );
      }
    });
  }
}
