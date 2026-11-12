// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/story_word_fixture.dart';
import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _offset = 8192;

Uint8List _fixture({
  String text = 'Text\r',
  bool compressed = false,
  int? characterEnd,
  int? paragraphEnd,
  int? mainCharacterCount,
  int prm = 0,
  List<int> properties = const [],
  List<List<int>> prcs = const [],
  void Function(ByteData, Uint8List)? mutate,
}) {
  final width = compressed ? 1 : 2;
  return StructuredWordFixture(
    pieces: [WordFixturePiece(text, compressed: compressed, prm: prm)],
    mainCharacterCount: mainCharacterCount,
    characterRuns: [
      WordFixtureFkpRun(
        _offset,
        characterEnd ?? _offset + (text.length - 1) * width,
        properties: properties,
      ),
    ],
    paragraphRuns: paragraphEnd == null
        ? const []
        : [WordFixtureFkpRun(_offset, paragraphEnd)],
    prcs: prcs,
  ).build(mutate: mutate);
}

LegacyWordParagraph _paragraph(LegacyWordDocument document) =>
    document.blocks.single as LegacyWordParagraph;

XmlDocument _xml(Uint8List bytes) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content,
  ),
);

void _binEnd(ByteData word, Uint8List table, int pair, int value) {
  expect(word.getUint32(158 + pair * 8, Endian.little), 12);
  final offset = word.getUint32(154 + pair * 8, Endian.little);
  ByteData.sublistView(table).setUint32(offset + 4, value, Endian.little);
}

Uint8List _native() => File(
  'test/fixtures/word_native/officeart-terminal-mark.doc',
).readAsBytesSync();

Uint8List _mutateNative(void Function(ByteData, Uint8List) mutate) {
  final source = BoundedCfbReader(_native());
  final word = Uint8List.fromList(source.readPath('WordDocument')!);
  final table = Uint8List.fromList(source.readPath('1Table')!);
  mutate(ByteData.sublistView(word), table);
  final writer = CfbfWriter();
  void copy(CfbfDirectoryEntry parent, String prefix) {
    for (final entry in source.childrenOf(parent)) {
      final path = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
      if (entry.isStorage) {
        writer.addStorage(path);
        copy(entry, path);
      } else {
        writer.addStream(
          path,
          path == 'WordDocument'
              ? word
              : path == '1Table'
              ? table
              : source.readEntry(entry),
        );
      }
    }
  }

  copy(source.root, '');
  return writer.build();
}

void main() {
  for (final compressed in [false, true]) {
    test(
      'one omitted terminal CR has unknown mark (compressed=$compressed)',
      () {
        final bytes = _fixture(
          compressed: compressed,
          properties: wordSprm(0x0835, [1]), // bold preceding text
        );
        final original = Uint8List.fromList(bytes);
        final document = parseLegacyWordDocument(bytes);
        final paragraph = _paragraph(document);
        expect(document.plainText, 'Text');
        expect(paragraph.runs.single.style.bold, isTrue);
        expect(paragraph.mark, isNull);
        expect(
          document.warnings,
          containsAll([
            LegacyWordWarning.terminalMarkFormattingUnavailable,
            LegacyWordWarning.revisionMetadataIncomplete,
          ]),
        );
        final result = convertLegacyWordDocument(document);
        expect(
          result.limitations,
          containsAll([
            LegacyWordConversionLimitation.partialFormatting,
            LegacyWordConversionLimitation.revisions,
          ]),
        );
        final xml = _xml(result.bytes);
        final outputParagraph = xml.findAllElements('p', namespace: _w).single;
        expect(
          outputParagraph
              .getElement('pPr', namespace: _w)
              ?.getElement('rPr', namespace: _w),
          isNull,
          reason: 'No paragraph-mark style or revision state may be invented.',
        );
        expect(xml.findAllElements('b', namespace: _w), hasLength(1));
        expect(bytes, original);
      },
    );
  }

  test('a preceding deleted run is never copied to the missing mark', () {
    final document = parseLegacyWordDocument(
      _fixture(properties: wordSprm(0x0800, [1])),
    );
    expect(_paragraph(document).runs.single.deleted, isTrue);
    expect(_paragraph(document).mark, isNull);
    final xml = _xml(convertLegacyWordDocument(document).bytes);
    expect(
      xml.findAllElements('delText', namespace: _w).single.innerText,
      'Text',
    );
    expect(
      xml
          .findAllElements('pPr', namespace: _w)
          .expand((p) => p.findAllElements('del', namespace: _w)),
      isEmpty,
    );
  });

  test('a genuinely covered mark retains its own character properties', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('Text\r', compressed: false)],
        characterRuns: [
          const WordFixtureFkpRun(_offset, _offset + 8),
          WordFixtureFkpRun(
            _offset + 8,
            _offset + 10,
            properties: wordSprm(0x0835, [1]),
          ),
        ],
      ).build(),
    );
    expect(_paragraph(document).runs.single.style.bold, isFalse);
    expect(_paragraph(document).mark!.style.bold, isTrue);
    expect(
      document.warnings,
      isNot(contains(LegacyWordWarning.terminalMarkFormattingUnavailable)),
    );
    final xml = _xml(convertLegacyWordDocument(document).bytes);
    final mark = xml
        .findAllElements('pPr', namespace: _w)
        .single
        .getElement('rPr', namespace: _w)!;
    expect(mark.getElement('b', namespace: _w), isNotNull);
  });

  test('an uncovered interior paragraph mark stays invalid', () {
    expect(
      () => parseLegacyWordDocument(
        _fixture(text: 'A\rB\r', characterEnd: _offset + 2),
      ),
      throwsFormatException,
    );
  });

  test('a hole before the terminal mark is not recovered', () {
    expect(
      () => parseLegacyWordDocument(_fixture(characterEnd: _offset + 6)),
      throwsFormatException,
    );
  });

  for (final ending in ['X', '\x0c', '\x07']) {
    test(
      'a missing non-CR ending ${ending.codeUnitAt(0)} is not recovered',
      () {
        expect(
          () => parseLegacyWordDocument(_fixture(text: 'Text$ending')),
          throwsFormatException,
        );
      },
    );
  }

  test('extra CLX extent beyond the main story is not recovered', () {
    expect(
      () => parseLegacyWordDocument(
        _fixture(
          text: 'Text\rX',
          mainCharacterCount: 5,
          characterEnd: _offset + 8,
          paragraphEnd: _offset + 10,
        ),
      ),
      throwsFormatException,
    );
  });

  test('a separate unformatted terminal piece is not recovered', () {
    expect(
      () => parseLegacyWordDocument(
        StructuredWordFixture(
          pieces: const [
            WordFixturePiece('Text', compressed: false),
            WordFixturePiece('\r', offset: _offset + 8, compressed: false),
          ],
          characterRuns: const [WordFixtureFkpRun(_offset, _offset + 8)],
        ).build(),
      ),
      throwsFormatException,
    );
  });

  test('a terminal piece PRM is never silently discarded', () {
    expect(
      () => parseLegacyWordDocument(
        _fixture(
          prm: 1,
          prcs: [
            wordSprm(0x0800, [1]),
          ],
        ),
      ),
      throwsFormatException,
    );
  });

  test('a half-covered UTF-16 paragraph mark is invalid', () {
    expect(
      () => parseLegacyWordDocument(_fixture(characterEnd: _offset + 9)),
      throwsFormatException,
    );
  });

  test('a clipped bin cannot masquerade as a missing physical CHPX run', () {
    expect(
      () => parseLegacyWordDocument(
        _fixture(
          characterEnd: _offset + 10,
          mutate: (word, table) => _binEnd(word, table, 12, _offset + 8),
        ),
      ),
      throwsFormatException,
    );
  });

  for (final end in [_offset + 8, _offset + 9, _offset + 12]) {
    test('unmatched PAPX end $end prevents terminal recovery', () {
      expect(
        () => parseLegacyWordDocument(_fixture(paragraphEnd: end)),
        throwsFormatException,
      );
    });
  }

  test('a clipped PAPX bin is not exact physical paragraph coverage', () {
    expect(
      () => parseLegacyWordDocument(
        _fixture(
          paragraphEnd: _offset + 12,
          mutate: (word, table) => _binEnd(word, table, 13, _offset + 10),
        ),
      ),
      throwsFormatException,
    );
  });

  test('an absent paragraph-format table does not enable recovery', () {
    expect(
      () => parseLegacyWordDocument(
        _fixture(
          mutate: (word, table) {
            word.setUint32(158 + 13 * 8, 0, Endian.little);
          },
        ),
      ),
      throwsFormatException,
    );
  });

  test('an auxiliary story rules out the terminal-main recovery', () {
    const note = '\x02Foot\r';
    Uint8List source({required bool omitMainMark}) => storyWordFixture(
      main: 'A\x02\r',
      footnotes: '$note\r',
      tablePairs: {
        2: storyPlc([1, 0xffffffff], wordU16(1)),
        3: storyPlc([0, note.length, 0xffffffff]),
      },
      characterRuns: [WordFixtureFkpRun(8192, omitMainMark ? 16388 : 16390)],
      paragraphRuns: const [WordFixtureFkpRun(8192, 16390)],
    );
    expect(
      parseLegacyWordDocument(source(omitMainMark: false)).stories,
      hasLength(1),
    );
    expect(
      () => parseLegacyWordDocument(source(omitMainMark: true)),
      throwsFormatException,
    );
  });

  test(
    'pinned native OfficeArt export retains shapes without inventing a mark',
    () {
      final bytes = _native();
      final original = Uint8List.fromList(bytes);
      final source = BoundedCfbReader(bytes);
      final word = ByteData.sublistView(source.readPath('WordDocument')!);
      final table = ByteData.sublistView(source.readPath('1Table')!);
      final chpx = word.getUint32(154 + 12 * 8, Endian.little);
      final papx = word.getUint32(154 + 13 * 8, Endian.little);
      expect(word.getUint32(76, Endian.little), 85);
      expect(table.getUint32(chpx + 4, Endian.little), 2216);
      expect(table.getUint32(papx + 4, Endian.little), 2218);
      expect(word.getUint16(2216, Endian.little), 0x0d);

      final document = parseLegacyWordDocument(bytes);
      expect(
        document.plainText,
        'OfficeArt geometry, solid fill, dash, opacity, rotation and offset shadow probes.',
      );
      expect(document.media.drawings, hasLength(3));
      expect(_paragraph(document).mark, isNull);
      expect(
        document.warnings,
        contains(LegacyWordWarning.terminalMarkFormattingUnavailable),
      );
      final result = convertLegacyWordDocument(document);
      final xml = _xml(result.bytes);
      expect(xml.findAllElements('pict', namespace: _w), hasLength(3));
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.revisions),
      );
      expect(bytes, original);
    },
  );

  test(
    'shortening the pinned native CHPX into the preceding character still fails',
    () {
      final malformed = _mutateNative((word, table) {
        final binOffset = word.getUint32(154 + 12 * 8, Endian.little);
        final data = ByteData.sublistView(table);
        final page =
            (data.getUint32(binOffset + 8, Endian.little) & 0x3fffff) * 512;
        final count = word.getUint8(page + 511);
        // Keep the final drawing run nonempty, but shorten the last UTF-16 code
        // unit to one byte. Both table/page endpoints agree; this is still invalid.
        data.setUint32(binOffset + 4, 2215, Endian.little);
        word.setUint32(page + count * 4, 2215, Endian.little);
      });
      expect(() => parseLegacyWordDocument(malformed), throwsFormatException);
    },
  );
}
