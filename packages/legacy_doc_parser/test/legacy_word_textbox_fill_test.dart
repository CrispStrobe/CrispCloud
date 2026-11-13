// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/media_word_fixture.dart';
import 'support/officeart_shape_fixture.dart';
import 'support/structured_word_fixture.dart';
import 'support/textbox_fill_fixture.dart';

const _v = 'urn:schemas-microsoft-com:vml';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

void main() {
  test('qualified bitmap fills reference exact embedded source images', () {
    for (final (name, type) in [
      ('picture', 'frame'),
      ('texture', 'tile'),
      ('pattern', 'pattern'),
    ]) {
      final bytes = textboxFillFixture(name);
      final source = parseLegacyWordDocument(bytes);
      final fill = source.media.drawings.single.shape!.fill!;
      final asset = source.media.assets.single;
      expect(fill.imageId, asset.id);
      expect(
        source.media.drawings.single.shape!.unsupportedProperties,
        isEmpty,
      );
      final converted = convertLegacyWord(bytes);
      final archive = ZipDecoder().decodeBytes(converted.bytes);
      final xml = XmlDocument.parse(
        utf8.decode(archive.findFile('word/document.xml')!.content),
      );
      final element = xml.findAllElements('fill', namespace: _v).single;
      expect(element.getAttribute('type'), type);
      final relationship = element.getAttribute('id', namespace: _r)!;
      final rels = XmlDocument.parse(
        utf8.decode(archive.findFile('word/_rels/document.xml.rels')!.content),
      );
      final target = rels
          .findAllElements('Relationship')
          .singleWhere((item) => item.getAttribute('Id') == relationship)
          .getAttribute('Target')!;
      final embedded = archive.findFile('word/$target')!.content;
      if (name == 'pattern') {
        expect(asset.bytes, monochromePatternDib());
        expect(asset.nativeBitmapBytes!.sublist(14), asset.bytes);
        expect(embedded, asset.nativeBitmapBytes);
        expect(element.getAttribute('color'), '#6699CC');
        expect(element.getAttribute('color2'), '#CC6633');
        expect(target, endsWith('.bmp'));
      } else {
        expect(asset.bytes, mediaFixturePng());
        expect(asset.nativeBitmapBytes, isNull);
        expect(embedded, asset.bytes);
      }
      expect(
        xml
            .findAllElements(
              'txbxContent',
              namespace:
                  'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
            )
            .single
            .innerText,
        'FILL',
      );
      expect(
        converted.limitations,
        contains(LegacyWordConversionLimitation.partialFormatting),
      );
    }
  });

  test('unqualified DIB variants remain raw and do not become previews', () {
    final malformed = <Uint8List>[
      Uint8List(0),
      monochromePatternDib().sublist(0, 79),
      Uint8List.fromList([...monochromePatternDib(), 0]),
      for (final (offset, value) in [
        (0, 124),
        (4, 9),
        (8, 7),
        (12, 2),
        (14, 8),
        (16, 1),
        (20, 31),
        (32, 3),
        (36, 3),
        (40, 0x112233),
      ])
        Uint8List.fromList(monochromePatternDib())
          ..buffer.asByteData().setUint32(offset, value, Endian.little),
    ];
    for (final dib in malformed) {
      final source = parseLegacyWordDocument(
        textboxFillFixture('pattern', blip: dibPatternBlip(dib)),
      );
      final asset = source.media.assets.single;
      expect(asset.bytes, dib);
      expect(asset.isRenderable, isFalse);
      expect(asset.nativeBitmapBytes, isNull);
      expect(
        source.media.drawings.single.shape!.unsupportedProperties,
        containsAll([0x0180, 0x0186]),
      );
      final converted = convertLegacyWordDocument(source);
      final archive = ZipDecoder().decodeBytes(converted.bytes);
      final xml = utf8.decode(archive.findFile('word/document.xml')!.content);
      expect(xml, isNot(contains('<v:fill')));
      expect(
        archive.files.where((file) => file.name.startsWith('word/media/')),
        isEmpty,
      );
      expect(
        archive.files.any((file) => file.name.startsWith('word/evidence/')),
        isTrue,
      );
    }
  });

  test(
    'DIB wrapper keeps palettes, scanline orientation and UID forms exact',
    () {
      for (final reverse in [false, true]) {
        for (final height in [8, -8]) {
          for (final two in [false, true]) {
            final dib = monochromePatternDib(
              reversePalette: reverse,
              height: height,
            );
            final asset = parseLegacyWordDocument(
              textboxFillFixture(
                'pattern',
                blip: dibPatternBlip(dib, twoUids: two),
              ),
            ).media.assets.single;
            final bitmap = asset.nativeBitmapBytes!;
            expect(asset.bytes, dib);
            expect(bitmap.sublist(14), dib);
            final header = ByteData.sublistView(bitmap);
            expect(header.getUint16(0, Endian.little), 0x4d42);
            expect(header.getUint32(2, Endian.little), 94);
            expect(header.getUint32(10, Endian.little), 62);
            expect(asset.contentType, 'image/bmp');
            expect(() => bitmap[0] = 0, throwsUnsupportedError);
          }
        }
      }
    },
  );

  test('unused and disabled fill references never fetch unrelated BLIPs', () {
    final disabled = parseLegacyWordDocument(
      textboxFillFixture('picture', extra: {0x4186: 999, 0x01bf: 0x00100000}),
    );
    expect(disabled.media.assets, isEmpty);
    expect(disabled.media.drawings.single.shape!.fill!.enabled, isFalse);
    final unflagged = parseLegacyWordDocument(
      textboxFillFixture('picture', extra: {0x4186: 0, 0x0186: 1}),
    );
    expect(unflagged.media.assets, isEmpty);
    final unanchored = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('No drawing anchor\r')],
        extraTablePairs: {
          50: drawingContent(
            shape: officeArtRecord(0xf004, [
              ...officeArtRecord(
                0xf00a,
                [...wordU32(1025), ...wordU32(0xa00)],
                version: 2,
                instance: 202,
              ),
              ...shapePropertyRecord(values: {0x0180: 3, 0x4186: 1}),
            ], version: 15),
            blip: pictureBlip(),
          ),
        },
      ).build(),
    );
    expect(unanchored.media.assets, isEmpty);
    final inline = parseLegacyWordDocument(
      inlinePictureWordFixture(
        picture: inlinePictureData(properties: {0x0180: 3, 0x4186: 999}),
      ),
    );
    expect(inline.media.pictures.single.imageId, inline.media.assets.single.id);
    expect(inline.media.pictures.single.shape!.fill!.imageId, isNull);
  });

  test('fill BLIP flags follow scalar inheritance and complex overrides', () {
    LegacyWordDocument inherited(
      Map<int, int> defaults,
      Map<int, int> values, {
      Map<int, Uint8List> complex = const {},
    }) => parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('A\x08B\r')],
        characterRuns: [
          WordFixtureFkpRun(8192, 8196, properties: wordSprm(0x0855, [1])),
        ],
        extraTablePairs: {
          40: drawingAnchor(),
          50: [
            ...officeArtRecord(0xf000, [
              ...shapePropertyRecord(values: defaults),
              ...officeArtRecord(
                0xf001,
                blipStoreEntry(pictureBlip()),
                version: 15,
                instance: 1,
              ),
            ], version: 15),
            0,
            ...officeArtRecord(
              0xf002,
              officeArtRecord(0xf004, [
                ...officeArtRecord(
                  0xf00a,
                  [...wordU32(1025), ...wordU32(0xa00)],
                  version: 2,
                  instance: 202,
                ),
                ...shapePropertyRecord(values: values, complex: complex),
              ], version: 15),
              version: 15,
            ),
          ],
        },
      ).build(),
    );
    for (final (defaults, values, expected) in [
      ({0x0180: 3, 0x4186: 1}, <int, int>{}, true),
      ({0x0180: 3, 0x4186: 1}, {0x0186: 1}, false),
      ({0x0180: 3, 0x0186: 1}, {0x4186: 1}, true),
      ({0x0180: 3, 0x4186: 999}, {0x4186: 1}, true),
      ({0x0180: 3, 0x4186: 1}, {0x4186: 0}, false),
      ({0x0180: 3, 0x4186: 1, 0x01bf: 0x00100000}, {0x01bf: 0x10}, false),
      ({0x0180: 3, 0x4186: 1, 0x01bf: 0x00100000}, {0x01bf: 0x00100010}, true),
    ]) {
      final source = inherited(defaults, values);
      expect(source.media.assets.isNotEmpty, expected);
      expect(
        source.media.drawings.single.shape!.fill!.imageId != null,
        expected,
      );
    }
    final complex = inherited(
      {0x0180: 3, 0x4186: 1},
      {},
      complex: {0x0186: Uint8List(0)},
    );
    expect(complex.media.assets, isEmpty);
    expect(
      complex.media.drawings.single.shape!.unsupportedProperties,
      contains(0x0186),
    );
    expect(
      () => inherited({0x0180: 3, 0x4186: 999}, {}),
      throwsFormatException,
    );
  });

  test(
    'pattern alpha stays source-valued and uses qualified secondary opacity',
    () {
      final bytes = textboxFillFixture(
        'pattern',
        extra: {0x0182: 32768, 0x0184: 16384},
      );
      final archive = ZipDecoder().decodeBytes(convertLegacyWord(bytes).bytes);
      final xml = XmlDocument.parse(
        utf8.decode(archive.findFile('word/document.xml')!.content),
      );
      final fill = xml.findAllElements('fill', namespace: _v).single;
      expect(fill.getAttribute('opacity'), '0.5');
      expect(
        fill.getAttribute(
          'opacity2',
          namespace: 'urn:schemas-microsoft-com:office:office',
        ),
        '0.25',
      );
      expect(fill.getAttribute('opacity2'), isNull);
    },
  );

  test(
    'stored fill names stay inert and used recolor modifiers stay guarded',
    () {
      final comment = Uint8List.fromList([
        for (final unit in 'https://invalid.example/fill\u0000'.codeUnits)
          ...wordU16(unit),
      ]);
      final source = parseLegacyWordDocument(
        textboxFillFixture(
          'picture',
          complex: {0x0187: comment},
          extra: {0x01bf: 0x00500050},
        ),
      );
      final fill = source.media.drawings.single.shape!.fill!;
      expect(fill.imageSourceName, 'https://invalid.example/fill');
      expect(fill.recolorAsPicture, isTrue);
      expect(
        source.media.drawings.single.shape!.unsupportedProperties,
        isEmpty,
      );
      final archive = ZipDecoder().decodeBytes(
        convertLegacyWordDocument(source).bytes,
      );
      final xml = utf8.decode(archive.findFile('word/document.xml')!.content);
      expect(xml, isNot(contains('invalid.example')));
      for (final extra in [
        {0x0188: 2},
        {0x01bf: 0x00500050, 0x010d: 0x00112233},
        {0x01bf: 0x00500050, 0x0185: 0x00112233},
      ]) {
        final unresolved = parseLegacyWordDocument(
          textboxFillFixture('picture', extra: extra),
        );
        expect(
          unresolved.media.drawings.single.shape!.unsupportedProperties,
          isNotEmpty,
        );
        final out = ZipDecoder().decodeBytes(
          convertLegacyWordDocument(unresolved).bytes,
        );
        expect(
          utf8.decode(out.findFile('word/document.xml')!.content),
          isNot(contains('<v:fill')),
        );
      }
    },
  );
}
