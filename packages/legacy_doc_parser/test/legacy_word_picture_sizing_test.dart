// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/media_word_fixture.dart';
import 'support/metafile_fixture.dart';

Uint8List _source(
  (int, int) goals,
  (int, int) scale, {
  Uint8List? blip,
  Map<int, int> crop = const {},
}) {
  final picture = inlinePictureData(blip: blip, properties: crop);
  final data = ByteData.sublistView(picture);
  data.setInt16(28, goals.$1, Endian.little);
  data.setInt16(30, goals.$2, Endian.little);
  data.setUint16(32, scale.$1, Endian.little);
  data.setUint16(34, scale.$2, Endian.little);
  return inlinePictureWordFixture(picture: picture);
}

XmlDocument _xml(Uint8List source) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder()
        .decodeBytes(convertLegacyWord(source).bytes)
        .findFile('word/document.xml')!
        .content,
  ),
);

void main() {
  test('PICMID ratios truncate fractional twips across native boundaries', () {
    const cases = [
      ((1200, 600), (1200, 1200), (1440, 720)),
      ((1001, 1001), (1499, 499), (1500, 499)),
      ((1001, 1003), (1500, 500), (1501, 501)),
      ((1001, 1001), (1501, 501), (1502, 501)),
      ((1001, 1001), (1001, 1999), (1002, 2000)),
      ((9001, 5401), (960, 960), (8640, 5184)),
      ((9000, 5400), (960, 960), (8640, 5184)),
    ];
    for (final (goals, scale, expected) in cases) {
      final source = _source(goals, scale);
      final original = Uint8List.fromList(source);
      final picture = parseLegacyWordDocument(source).media.pictures.single;
      expect((picture.widthTwips, picture.heightTwips), expected);
      final extent = _xml(source).findAllElements('wp:extent').single;
      expect(extent.getAttribute('cx'), '${expected.$1 * 635}');
      expect(extent.getAttribute('cy'), '${expected.$2 * 635}');
      expect(source, orderedEquals(original));
    }
  });

  test('metafile and raster frames share the same source scale contract', () {
    for (final blip in [
      pictureBlip(),
      metafileBlip(emfFixture()),
      metafileBlip(wmfFixture(placeable: true), emf: false),
    ]) {
      final source = _source((9001, 5401), (960, 960), blip: blip);
      final document = parseLegacyWordDocument(source);
      final picture = document.media.pictures.single;
      expect((picture.widthTwips, picture.heightTwips), (8640, 5184));
      expect(document.media.assets.single.isRenderable, isTrue);
      expect(_xml(source).findAllElements('a:srcRect'), isEmpty);
    }
  });

  test('explicit OfficeArt crop does not rescale the final PICMID frame', () {
    final source = _source(
      (1001, 1003),
      (1500, 500),
      crop: {0x0100: 8192, 0x0101: -8192, 0x0102: 16384, 0x0103: 4096},
    );
    final picture = parseLegacyWordDocument(source).media.pictures.single;
    expect((picture.widthTwips, picture.heightTwips), (1501, 501));
    expect(
      [
        picture.cropLeftFixed16,
        picture.cropTopFixed16,
        picture.cropRightFixed16,
        picture.cropBottomFixed16,
      ],
      [16384, 8192, 4096, -8192],
    );
    final crop = _xml(source).findAllElements('a:srcRect').single;
    expect(
      [
        for (final key in ['l', 't', 'r', 'b']) crop.getAttribute(key),
      ],
      ['25000', '12500', '6250', '-12500'],
    );
  });

  test('exact bounds are checked before picture size quantization', () {
    for (final (goals, scale, expected) in [
      ((15, 15), (1000, 1000), (15, 15)),
      ((32000, 32000), (990, 990), (31680, 31680)),
    ]) {
      final picture = parseLegacyWordDocument(
        _source(goals, scale),
      ).media.pictures.single;
      expect((picture.widthTwips, picture.heightTwips), expected);
    }
    for (final (goals, scale) in [
      (
        (15, 720),
        (999, 1000),
      ), // 14.985: nearest rounding formerly admitted it.
      ((1440, 15), (1000, 999)),
      ((32001, 720), (990, 1000)), // 31680.99 must not enter by truncation.
      ((1440, 32001), (1000, 990)),
      ((1440, 720), (0, 1000)),
      ((1440, 720), (1000, 0)),
    ]) {
      expect(
        () => parseLegacyWordDocument(_source(goals, scale)),
        throwsFormatException,
      );
    }
  });
}
