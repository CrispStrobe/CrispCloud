// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import 'support/media_word_fixture.dart';
import 'support/story_word_fixture.dart';
import 'support/structured_word_fixture.dart';
import 'support/table_word_fixture.dart';

Uint8List _linkedPicture({String name = 'https://invalid.test/image.png'}) {
  final header = inlinePictureData().sublist(0, 68);
  final raw = Uint8List.fromList([...header, name.length, ...name.codeUnits]);
  final data = ByteData.sublistView(raw);
  data.setUint32(0, raw.length, Endian.little);
  data.setUint16(6, 94, Endian.little);
  return raw;
}

List<int> _border({
  bool old = false,
  int first = 0,
  int limit = 1,
  int sides = 0x10,
  bool nil = true,
}) => wordSprm(old ? 0xd620 : 0xd62f, [
  old ? 7 : 11,
  first,
  limit,
  sides,
  ...List.filled(old ? 4 : 8, nil ? 255 : 0),
]);

Uint8List _table(List<int> operations) => tableFixture([
  const TableFixtureParagraph('First\x07', depth: 1),
  const TableFixtureParagraph('Second\x07', depth: 1),
  TableFixtureParagraph(
    '\x07',
    depth: 1,
    row: true,
    widths: const [1440, 1440],
    extra: operations,
  ),
]);

Uint8List _unpositioned({
  int count = 1,
  int shape = 42,
  bool header = false,
  bool duplicate = false,
  String content = 'Recovered textbox\r\r',
  bool overlong = false,
}) {
  final records = duplicate ? 2 : 1;
  final text = '${content * records}x';
  return storyWordFixture(
    main: 'Main\r',
    textboxes: header ? '' : text,
    headerTextboxes: header ? text : '',
    tablePairs: {
      header ? 58 : 56: storyPlc(
        [
          for (var i = 0; i <= records; i++) i * content.length,
          text.length + (overlong ? 10 : 0),
        ],
        [
          for (var i = 0; i < records; i++) ...[
            ...wordU32(count),
            ...wordU32(0),
            ...wordU16(0),
            ...wordU32(0xffffffff),
            ...wordU32(shape),
            ...wordU32(0),
          ],
          ...List.filled(22, 0),
        ],
      ),
    },
  );
}

void main() {
  test('legacy linked-file PICF retains inert name and exact source bytes', () {
    final pictureBytes = _linkedPicture();
    final bytes = inlinePictureWordFixture(picture: pictureBytes);
    final before = Uint8List.fromList(bytes);
    final parsed = parseLegacyWordDocument(bytes);
    final picture = parsed.media.pictures.single;
    expect(parsed.plainText, contains('A'));
    expect(parsed.plainText, contains('B'));
    expect(picture.storedExternalName, 'https://invalid.test/image.png');
    expect(picture.source.structure, 'PICFLinkedFileName');
    expect(picture.shape, isNull);
    expect(picture.imageId, isNull);
    expect(parsed.media.assets, isEmpty);
    expect((picture.widthTwips, picture.heightTwips), (1440, 720));
    expect(parsed.safeHtml, isNot(contains('https://')));
    final artifact = parsed.media.artifacts.single;
    expect(artifact.kind, LegacyWordArtifactKind.binaryData);
    expect(artifact.bytes, orderedEquals(pictureBytes));
    expect(picture.officeArtArtifactId, artifact.id);
    expect(
      parsed.media.notices.map((n) => n.issue),
      containsAll([
        LegacyWordMediaIssue.externalPictureNotFetched,
        LegacyWordMediaIssue.unsupportedImage,
      ]),
    );
    expect(bytes, orderedEquals(before));
    final package = ZipDecoder().decodeBytes(
      convertLegacyWordToStructuredDocx(bytes).bytes,
    );
    expect(
      package.files
          .where((file) => file.name.endsWith('.rels'))
          .every((file) => !utf8.decode(file.content).contains('invalid.test')),
      isTrue,
    );
    final evidence = utf8.decode(
      package.findFile('word/evidence/manifest.json')!.content,
    );
    expect(evidence, contains('externalPictureNotFetched'));
    expect(evidence, contains('PICFLinkedFileName'));
  });

  final invalidPictures = <String, void Function(Uint8List)>{
    'empty name': (data) => data[68] = 0,
    'truncated name': (data) => data[68]++,
    'unexplained trailing bytes': (data) => data[68]--,
    'embedded NUL': (data) => data[70] = 0,
    'unknown mapping mode': (data) => data[6] = 95,
    'oversized record': (data) =>
        ByteData.sublistView(data).setInt32(0, 0x7fffffff, Endian.little),
    'invalid dimensions': (data) =>
        ByteData.sublistView(data).setInt16(28, 0, Endian.little),
  };
  for (final entry in invalidPictures.entries) {
    test('linked-file recovery rejects ${entry.key}', () {
      final picture = _linkedPicture();
      entry.value(picture);
      expect(
        () =>
            parseLegacyWordDocument(inlinePictureWordFixture(picture: picture)),
        throwsFormatException,
      );
    });
  }

  for (final sides in [0x10, 0x20]) {
    test('recovers only corroborated old nil diagonal mask $sides', () {
      final source = _table([
        ..._border(old: true, sides: sides),
        ..._border(sides: sides),
      ]);
      final parsed = parseLegacyWordDocument(source);
      final table = parsed.blocks.single as LegacyWordTable;
      expect(table.rows.single.cells.map((cell) => cell.widthTwips), [
        1440,
        1440,
      ]);
      final side = sides == 0x10
          ? LegacyWordTableBorderSide.tl2br
          : LegacyWordTableBorderSide.tr2bl;
      expect(
        table.rows.single.cells.first.formatting.borders[side]!.style,
        'nil',
      );
      expect(table.rows.single.cells.last.formatting.borders[side], isNull);
      expect(
        parsed.warnings,
        contains(LegacyWordWarning.recoveredLegacyDiagonalBorder),
      );
      final converted = convertLegacyWordToStructuredDocx(source);
      expect(
        converted.limitations,
        contains(LegacyWordConversionLimitation.partialFormatting),
      );
    });
  }

  final invalidBorders = <String, List<int>>{
    'missing modern operation': _border(old: true),
    'different cell range': [
      ..._border(old: true),
      ..._border(first: 1, limit: 2),
    ],
    'different diagonal': [..._border(old: true), ..._border(sides: 0x20)],
    'non-nil old border': [..._border(old: true, nil: false), ..._border()],
    'non-nil modern border': [..._border(old: true), ..._border(nil: false)],
    'extra invalid side': [
      ..._border(old: true, sides: 0x40),
      ..._border(sides: 0x40),
    ],
    'out-of-bounds range': [
      ..._border(old: true, limit: 3),
      ..._border(limit: 3),
    ],
    'intervening property': [
      ..._border(old: true),
      ...wordSprm(0x3403, [1]),
      ..._border(),
    ],
  };
  for (final entry in invalidBorders.entries) {
    test('diagonal-border recovery rejects ${entry.key}', () {
      expect(
        () => parseLegacyWordDocument(_table(entry.value)),
        throwsFormatException,
      );
    });
  }

  test('unpositioned singleton text remains a distinct story and evidence', () {
    final source = _unpositioned();
    final parsed = parseLegacyWordDocument(source);
    expect(parsed.plainText, 'Main');
    expect(parsed.stories.single.plainText, 'Recovered textbox');
    final reference = parsed.textboxReferences.single;
    expect(reference.shapeId, 42);
    expect(reference.anchorCp, isNull);
    expect(reference.anchors, isEmpty);
    expect(reference.placementUnresolved, isTrue);
    expect(
      parsed.warnings,
      contains(LegacyWordWarning.recoveredUnpositionedTextbox),
    );
    final package = ZipDecoder().decodeBytes(
      convertLegacyWordToStructuredDocx(source).bytes,
    );
    final manifest =
        jsonDecode(
              utf8.decode(
                package.findFile('word/evidence/manifest.json')!.content,
              ),
            )
            as Map<String, dynamic>;
    final record = (manifest['records'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((record) => record['kind'] == 'textbox');
    expect(record['shapeId'], 42);
    expect(record['placementUnresolved'], isTrue);
    expect(
      utf8.decode(package.findFile(record['part'] as String)!.content),
      contains('Recovered textbox'),
    );
    expect(
      utf8.decode(package.findFile('word/document.xml')!.content),
      isNot(contains('Recovered textbox')),
    );
  });

  final invalidTextboxes = <String, Uint8List Function()>{
    'zero chain length': () => _unpositioned(count: 0),
    'unresolved chain': () => _unpositioned(count: 2),
    'oversized chain': () => _unpositioned(count: 4097),
    'missing shape identity': () => _unpositioned(shape: 0),
    'repeated shape identity': () => _unpositioned(duplicate: true),
    'unresolved header placement': () => _unpositioned(header: true),
    'missing range terminator': () => _unpositioned(content: 'No terminator'),
    'overlong final sentinel': () => _unpositioned(overlong: true),
  };
  for (final entry in invalidTextboxes.entries) {
    test('unpositioned recovery rejects ${entry.key}', () {
      expect(
        () => parseLegacyWordDocument(entry.value()),
        throwsFormatException,
      );
    });
  }
}
