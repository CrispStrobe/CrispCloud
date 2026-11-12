// SPDX-License-Identifier: MPL-2.0

import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/legacy_word_document.dart';
import 'package:test/test.dart';

import 'support/media_word_fixture.dart';
import 'support/structured_word_fixture.dart';

void main() {
  test(
    'extracts the referenced inline PNG with source CP, dimensions and crop',
    () {
      final bytes = inlinePictureWordFixture(
        picture: inlinePictureData(properties: {0x0102: 16384}),
      );
      final before = Uint8List.fromList(bytes);
      final document = parseLegacyWordDocument(bytes);
      final picture = document.media.pictures.single;
      final image = document.media.assets.single;
      expect(picture.cp, 1);
      expect(picture.imageId, image.id);
      expect((picture.widthTwips, picture.heightTwips), (1440, 720));
      expect(picture.cropLeftFixed16, 16384);
      expect(image.bytes, orderedEquals(mediaFixturePng()));
      expect(image.contentType, 'image/png');
      expect(image.source.streamPath, 'Data');
      expect(picture.source.offset, 16);
      expect(bytes, before);
      expect(() => image.bytes[0] = 0, throwsUnsupportedError);
      expect(() => document.media.assets.clear(), throwsUnsupportedError);
    },
  );

  test('requires CFSpec and never carves unreferenced image signatures', () {
    final bytes = rewriteCompoundFixture(
      inlinePictureWordFixture(special: false),
      (writer) => writer.addStream('Unrelated', mediaFixturePng()),
    );
    final media = parseLegacyWordDocument(bytes).media;
    expect(media.assets, isEmpty);
    expect(media.pictures, isEmpty);
  });

  test('rejects a floating anchor without the required CFSpec property', () {
    expect(
      () => parseLegacyWordDocument(floatingPictureWordFixture(special: false)),
      throwsFormatException,
    );
  });

  test('retains visibility and revision state for each media occurrence', () {
    final properties = [
      ...wordSprm(0x083c, [1]),
      ...wordSprm(0x0800, [1]),
    ];
    final image = parseLegacyWordDocument(
      inlinePictureWordFixture(characterProperties: properties),
    ).media.pictures.single;
    final drawing = parseLegacyWordDocument(
      floatingPictureWordFixture(characterProperties: properties),
    ).media.drawings.single;
    final object = parseLegacyWordDocument(
      oleWordFixture(characterProperties: properties),
    ).media.embeddedObjects.single;
    for (final presentation in [
      image.presentation,
      drawing.presentation,
      object.presentation,
    ]) {
      expect(presentation.hidden, isTrue);
      expect(presentation.deleted, isTrue);
      expect(presentation.inserted, isFalse);
      expect(presentation.revisionAuthor, isNull);
    }
  });

  test('keeps an external picture path only as metadata', () {
    final media = parseLegacyWordDocument(
      inlinePictureWordFixture(
        picture: inlinePictureData(
          storedName: 'https://invalid.test/private.png',
        ),
      ),
    ).media;
    expect(
      media.pictures.single.storedExternalName,
      'https://invalid.test/private.png',
    );
    expect(media.assets.single.bytes, orderedEquals(mediaFixturePng()));
    expect(
      media.notices.map((n) => n.issue),
      contains(LegacyWordMediaIssue.externalPictureNotFetched),
    );
  });

  test('keeps pictures in field instructions and private results hidden', () {
    for (final privateResult in [false, true]) {
      final text = privateResult
          ? '\x13IF\x14\x01\x15\r'
          : '\x13\x01\x14shown\x15\r';
      final pictureCp = privateResult ? 4 : 1;
      final separatorCp = privateResult ? 3 : 2;
      final endCp = privateResult ? 5 : 8;
      final document = parseLegacyWordDocument(
        StructuredWordFixture(
          pieces: [WordFixturePiece(text)],
          characterRuns: [
            WordFixtureFkpRun(8192, 8192 + pictureCp),
            WordFixtureFkpRun(
              8192 + pictureCp,
              8193 + pictureCp,
              properties: [
                ...wordSprm(0x0855, [1]),
                ...wordSprm(0x6a03, wordU32(16)),
              ],
            ),
            WordFixtureFkpRun(8193 + pictureCp, 8192 + text.length),
          ],
          extraTablePairs: {
            16: [
              ...wordU32(0),
              ...wordU32(separatorCp),
              ...wordU32(endCp),
              ...wordU32(text.length),
              0x13,
              7,
              0x14,
              0,
              0x15,
              privateResult ? 0xa0 : 0x80,
            ],
          },
          extraStreams: {
            'Data': Uint8List.fromList([
              ...List.filled(16, 0),
              ...inlinePictureData(),
            ]),
          },
        ).build(),
      );
      expect(document.media.pictures.single.presentation.hidden, isTrue);
      expect(
        document.media.assets.single.bytes,
        orderedEquals(mediaFixturePng()),
      );
    }
  });

  test(
    'resolves floating anchors through shape IDs and a BLIP-store reference',
    () {
      final media = parseLegacyWordDocument(floatingPictureWordFixture()).media;
      final drawing = media.drawings.single;
      expect(drawing.shapeId, 1025);
      expect(drawing.anchorCp, 1);
      expect(
        (
          drawing.leftTwips,
          drawing.topTwips,
          drawing.rightTwips,
          drawing.bottomTwips,
        ),
        (120, 240, 1560, 960),
      );
      expect(
        (drawing.horizontalOrigin, drawing.verticalOrigin, drawing.wrapMode),
        (1, 2, 3),
      );
      expect(drawing.behindText, isTrue);
      expect(drawing.anchorLocked, isTrue);
      expect(drawing.imageId, media.assets.single.id);
      expect(media.assets.single.bytes, orderedEquals(mediaFixturePng()));
    },
  );

  test(
    'uses the WordDocument delay stream only at its declared BLIP offset',
    () {
      final media = parseLegacyWordDocument(
        floatingPictureWordFixture(delayed: true),
      ).media;
      expect(media.assets.single.bytes, orderedEquals(mediaFixturePng()));
      expect(media.assets.single.source.streamPath, 'WordDocument');
      expect(media.assets.single.source.offset, 20000 + 8 + 17);
    },
  );

  test('rejects a textbox identifier that has no corresponding text story', () {
    expect(
      () => parseLegacyWordDocument(
        floatingPictureWordFixture(textboxId: 0x00010002, nextShapeId: 1026),
      ),
      throwsFormatException,
    );
  });

  test('retains floating crop and independent deleted-shape state', () {
    final drawing = parseLegacyWordDocument(
      floatingPictureWordFixture(
        imageProperties: {0x0100: 8192, 0x0103: 16384},
        shapeFlags: 0x0a08,
      ),
    ).media.drawings.single;
    expect((drawing.cropTopFixed16, drawing.cropRightFixed16), (8192, 16384));
    expect(drawing.shapeDeleted, isTrue);
    expect(drawing.presentation.deleted, isFalse);
    final picture = parseLegacyWordDocument(
      inlinePictureWordFixture(picture: inlinePictureData(shapeFlags: 0x0a08)),
    ).media.pictures.single;
    expect(picture.shapeDeleted, isTrue);
    expect(picture.presentation.deleted, isFalse);
  });

  test('does not decode unreferenced global BLIPs', () {
    final media = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('No image reference\r')],
        extraTablePairs: {
          50: drawingContent(shape: pictureShape(), blip: pictureBlip()),
        },
      ).build(),
    ).media;
    expect(media.assets, isEmpty);
    expect(media.pictures, isEmpty);
    expect(media.drawings, isEmpty);
    expect(media.artifacts.single.kind, LegacyWordArtifactKind.officeArt);
  });

  test(
    'normalizes ignored anchor flags and retains their exact source record',
    () {
      final flags = (1 << 1) | (2 << 3) | (1 << 5) | (15 << 9) | 0xc000;
      final media = parseLegacyWordDocument(
        floatingPictureWordFixture(anchorFlags: flags),
      ).media;
      expect(media.drawings.single.wrapMode, 1);
      expect(media.drawings.single.wrapSide, 0);
      expect(media.drawings.single.behindText, isFalse);
      final anchor = media.artifacts.singleWhere(
        (a) => a.source.structure == 'PlcfSpaMom',
      );
      expect(anchor.bytes, orderedEquals(drawingAnchor(flags: flags)));
    },
  );

  test(
    'retains opaque metafile records without inflating or rendering them',
    () {
      final metafile = officeArtRecord(
        0xf01b,
        List.filled(50, 0),
        instance: 0x216,
      );
      final media = parseLegacyWordDocument(
        inlinePictureWordFixture(picture: inlinePictureData(blip: metafile)),
      ).media;
      expect(media.assets.single.format, LegacyWordImageFormat.wmf);
      expect(media.assets.single.isRenderable, isFalse);
      expect(media.assets.single.bytes, orderedEquals(metafile));
      expect(
        media.notices.map((n) => n.issue),
        contains(LegacyWordMediaIssue.unsupportedImage),
      );
    },
  );

  test(
    'preserves referenced OLE streams and directory metadata in a reusable CFB',
    () {
      final object = parseLegacyWordDocument(
        oleWordFixture(),
      ).media.embeddedObjects.single;
      expect(object.cp, 6);
      expect(object.canEmbed, isTrue);
      expect(object.linked, isFalse);
      final cfb = BoundedCfbReader(object.storage.bytes);
      expect(cfb.readPath('CONTENTS'), orderedEquals([1, 2, 3, 4]));
      expect(cfb.readPath('Nested/extra'), orderedEquals([5, 6, 7]));
      expect(cfb.root.clsid, orderedEquals(List.generate(16, (i) => i + 1)));
      expect(cfb.root.stateBits, 0x1234);
      expect(cfb.root.createdFiletime, orderedEquals([1, 2, 3, 4, 5, 6, 7, 0]));
      expect(
        cfb.child(cfb.root, 'Nested')!.clsid,
        orderedEquals(List.filled(16, 7)),
      );
      expect(() => object.storage.bytes[0] = 0, throwsUnsupportedError);
      expect(
        () => object.storage.streams.first.bytes[0] = 0,
        throwsUnsupportedError,
      );
    },
  );

  test(
    'linked and unverifiable OLE fields remain ineligible for active embedding',
    () {
      for (final bytes in [
        oleWordFixture(linked: true),
        oleWordFixture(fieldTable: false),
      ]) {
        final object = parseLegacyWordDocument(
          bytes,
        ).media.embeddedObjects.single;
        expect(object.canEmbed, isFalse);
        expect(object.storage.streams, isNotEmpty);
      }
    },
  );

  test(
    'zombie OLE fields retain their storage only as inert unreferenced evidence',
    () {
      final media = parseLegacyWordDocument(oleWordFixture(zombie: true)).media;
      expect(media.embeddedObjects, isEmpty);
      final artifact = media.artifacts.singleWhere(
        (a) => a.kind == LegacyWordArtifactKind.unreferencedObjectStorage,
      );
      expect(
        BoundedCfbReader(artifact.bytes).readPath('CONTENTS'),
        orderedEquals([1, 2, 3, 4]),
      );
    },
  );

  test('does not activate a truncated OLE header as an embedded object', () {
    final input = oleWordFixture(
      oleRecord: Uint8List.fromList([...wordU32(0x02000001), ...wordU32(0)]),
    );
    final object = parseLegacyWordDocument(input).media.embeddedObjects.single;
    expect(object.linked, isNull);
    expect(object.canEmbed, isFalse);
    expect(object.storage.streams, isNotEmpty);
  });

  test(
    'preserves a complete VBA project and distinguishes both signature scopes',
    () {
      final signatureValue = [2, 0, 0xaa, 0xbb, 0xcc, 0xdd];
      final stw = [
        ...wordU16(0xffff),
        ...wordU16(1),
        ...wordU16(4),
        ...wordU16(4),
        for (final ch in 'Sign'.codeUnits) ...wordU16(ch),
        ...wordU32(0),
        ...signatureValue,
      ];
      final document = parseLegacyWordDocument(
        StructuredWordFixture(
          pieces: const [WordFixturePiece('Macros\r')],
          extraTablePairs: {60: stw},
          extraStreams: {
            'Macros/PROJECT': Uint8List.fromList('Name="Fixture"'.codeUnits),
            'Macros/VBA/dir': Uint8List.fromList([1, 2, 3]),
            'Macros/VBA/_VBA_PROJECT': Uint8List.fromList([
              0xcc,
              0x61,
              0,
              0,
              0,
              0,
              0,
            ]),
            'Macros/VBA/Module1': Uint8List.fromList([11, 22, 33]),
            '_signatures': Uint8List.fromList([9, 8, 7]),
            '_xmlsignatures/sig1.xml': Uint8List.fromList(
              '<Signature/>'.codeUnits,
            ),
          },
        ).build(),
      );
      final media = document.media;
      final project = media.vbaProjects.single;
      expect(project.hasRequiredStreams, isTrue);
      expect(
        BoundedCfbReader(project.storage.bytes).readPath('VBA/Module1'),
        orderedEquals([11, 22, 33]),
      );
      final vbaSignature = media.artifacts.singleWhere(
        (a) => a.kind == LegacyWordArtifactKind.vbaSignature,
      );
      expect(vbaSignature.bytes, orderedEquals(signatureValue));
      expect(vbaSignature.source.structure, 'StwUser/Sign/WordSigBlob');
      expect(project.signatureArtifactIds, [vbaSignature.id]);
      expect(
        media.artifacts.where(
          (a) => a.kind == LegacyWordArtifactKind.documentSignature,
        ),
        hasLength(2),
      );
      expect(media.artifacts.every((a) => !a.signatureVerified), isTrue);
    },
  );

  test(
    'retains opaque artifacts and diagnostics when all stories are empty',
    () {
      final document = parseLegacyWordDocument(
        StructuredWordFixture(
          pieces: const [WordFixturePiece('\r')],
          mainCharacterCount: 0,
          extraStreams: {
            'Macros/PROJECT': Uint8List.fromList('Name="Incomplete"'.codeUnits),
            'ObjectPool/_1/Payload': Uint8List.fromList([1, 2, 3]),
            '_signatures': Uint8List.fromList([4, 5, 6]),
          },
        ).build(),
      );
      expect(document.blocks, isEmpty);
      expect(document.plainText, isEmpty);
      expect(document.safeHtml, isEmpty);
      expect(document.media.vbaProjects.single.hasRequiredStreams, isFalse);
      expect(
        document.media.notices.map((notice) => notice.issue),
        containsAll([
          LegacyWordMediaIssue.incompleteVbaProject,
          LegacyWordMediaIssue.unreferencedObjectStorage,
        ]),
      );
      expect(
        document.warnings,
        containsAll([
          LegacyWordWarning.macrosOmitted,
          LegacyWordWarning.floatingObjectsOmitted,
        ]),
      );
      final object = document.media.artifacts.singleWhere(
        (artifact) =>
            artifact.kind == LegacyWordArtifactKind.unreferencedObjectStorage,
      );
      expect(
        BoundedCfbReader(object.bytes).readPath('Payload'),
        orderedEquals([1, 2, 3]),
      );
      final signature = document.media.artifacts.singleWhere(
        (artifact) => artifact.kind == LegacyWordArtifactKind.documentSignature,
      );
      expect(signature.bytes, orderedEquals([4, 5, 6]));
      expect(signature.signatureVerified, isFalse);
    },
  );

  test(
    'rejects overlong PICF and OfficeArt records before reading outside their references',
    () {
      final picf = inlinePictureData();
      ByteData.sublistView(picf).setUint32(0, 0x7fffffff, Endian.little);
      expect(
        () => parseLegacyWordDocument(inlinePictureWordFixture(picture: picf)),
        throwsFormatException,
      );
      final art = inlinePictureData();
      ByteData.sublistView(art).setUint32(68 + 4, 0x7fffffff, Endian.little);
      expect(
        () => parseLegacyWordDocument(inlinePictureWordFixture(picture: art)),
        throwsFormatException,
      );
    },
  );

  test('bounds nested OfficeArt records and delayed-stream extents', () {
    var nested = officeArtRecord(0xf004, const [], version: 15);
    for (var i = 0; i < 33; i++) {
      nested = officeArtRecord(0xf003, nested, version: 15);
    }
    expect(
      () => parseLegacyWordDocument(
        StructuredWordFixture(
          pieces: const [WordFixturePiece('A\x08B\r')],
          extraTablePairs: {50: drawingContent(shape: nested)},
        ).build(),
      ),
      throwsFormatException,
    );
    expect(
      () => parseLegacyWordDocument(
        StructuredWordFixture(
          pieces: const [WordFixturePiece('A\x08B\r')],
          characterRuns: [
            WordFixtureFkpRun(8192, 8196, properties: wordSprm(0x0855, [1])),
          ],
          extraTablePairs: {
            40: drawingAnchor(),
            50: drawingContent(
              shape: pictureShape(),
              blip: pictureBlip(),
              delayOffset: 0x7fffffff,
            ),
          },
        ).build(),
      ),
      throwsFormatException,
    );
  });

  test(
    'extracts the image from the actual authored Word fixture by its references',
    () {
      final bytes = File(
        'test/fixtures/word_native/formatting.doc',
      ).readAsBytesSync();
      final media = parseLegacyWordDocument(bytes).media;
      expect(media.pictures, hasLength(1));
      expect(media.assets.single.format, LegacyWordImageFormat.png);
      expect(media.assets.single.isRenderable, isTrue);
      expect(media.pictures.single.imageId, media.assets.single.id);
    },
  );
}
