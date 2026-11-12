// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/legacy_word_metafile.dart';
import 'package:test/test.dart';

import 'support/media_word_fixture.dart';
import 'support/metafile_fixture.dart';
import 'support/structured_word_fixture.dart';

LegacyWordDocument _document(Uint8List blip) => parseLegacyWordDocument(
  inlinePictureWordFixture(picture: inlinePictureData(blip: blip)),
);

void main() {
  for (final emf in [true, false]) {
    for (final compressed in [true, false]) {
      for (final twoUids in [true, false]) {
        test(
          '${emf ? 'EMF' : 'WMF'} ${compressed ? 'zlib' : 'plain'} ${twoUids ? 2 : 1} UID payload',
          () {
            final payload = emf
                ? emfFixture()
                : wmfFixture(placeable: !twoUids);
            final blip = metafileBlip(
              payload,
              emf: emf,
              compressed: compressed,
              twoUids: twoUids,
            );
            final document = _document(blip);
            final asset = document.media.assets.single;
            expect(asset.bytes, orderedEquals(payload));
            expect(asset.isRenderable, isTrue);
            expect(asset.metafile!.nativeEmbeddingAllowed, isTrue);
            expect(asset.metafile!.widthEmu, 914400);
            expect(asset.metafile!.heightEmu, 457200);
            expect(asset.source.structure, 'OfficeArtMetafileData');
            expect(
              document.media.notices.map((n) => n.issue),
              isNot(contains(LegacyWordMediaIssue.unsupportedImage)),
            );
            expect(
              document.media.artifacts.single.bytes,
              containsAllInOrder(blip),
            );
            expect(() => asset.bytes[0] = 0, throwsUnsupportedError);
            final output = convertLegacyWordDocument(document);
            final zip = ZipDecoder().decodeBytes(output.bytes);
            final image = zip.findFile(
              'word/media/image1.${emf ? 'emf' : 'wmf'}',
            )!;
            expect(image.content, orderedEquals(payload));
            final types = utf8.decode(
              zip.findFile('[Content_Types].xml')!.content,
            );
            expect(types, contains(emf ? 'image/x-emf' : 'image/x-wmf'));
            expect(output.preservedCounts['pictureReferences'], 1);
          },
        );
      }
    }
  }

  test('rejects malformed metadata before inflation', () {
    for (final mutate in <void Function(ByteData)>[
      (h) => h.setUint32(0, legacyWordMetafileByteLimit + 1, Endian.little),
      (h) => h.setUint32(0, 0, Endian.little),
      (h) => h.setUint32(28, 0xffffffff, Endian.little),
      (h) => h.setUint8(32, 1),
      (h) => h.setUint8(33, 0),
    ]) {
      expect(
        () => _document(metafileBlip(emfFixture(), mutateHeader: mutate)),
        throwsFormatException,
      );
    }
  });

  test(
    'enforces declared output size on literals and repeated backreferences',
    () {
      for (final length in [1, 108, 32768]) {
        final payload = Uint8List(100000)..fillRange(0, 100000, 0x41);
        expect(
          () => _document(
            metafileBlip(
              payload,
              mutateHeader: (h) => h.setUint32(0, length, Endian.little),
            ),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => _document(
          metafileBlip(
            emfFixture(),
            mutateHeader: (h) => h.setUint32(0, 109, Endian.little),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'rejects checksum, truncation, missing final block and trailing deflate',
    () {
      final payload = emfFixture();
      for (final mutate in <Uint8List Function(Uint8List)>[
        (value) => Uint8List.fromList(value)..[value.length - 1] ^= 1,
        (value) => Uint8List.sublistView(value, 0, value.length - 1),
        (value) => Uint8List.fromList(value)..[2] &= 0xfe,
        (value) => Uint8List.fromList([
          ...value.sublist(0, value.length - 4),
          0,
          ...value.sublist(value.length - 4),
        ]),
        (value) => Uint8List.fromList([...value, 0, 0, 0, 0]),
      ]) {
        expect(
          () => _document(metafileBlip(payload, mutateCompressed: mutate)),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'rejects forged EMF record sizes, counts, handles and terminal records',
    () {
      for (final mutate in <void Function(ByteData)>[
        (h) => h.setUint32(48, 0xffffffff, Endian.little),
        (h) => h.setUint32(52, 50001, Endian.little),
        (h) => h.setUint32(52, 3, Endian.little),
        (h) => h.setUint16(56, 5000, Endian.little),
        (h) => h.setUint32(92, 0xfffffff0, Endian.little),
        (h) => h.setUint32(92, 0, Endian.little),
        (h) => h.setUint32(88, 43, Endian.little),
        (h) => h.setUint32(96, 100, Endian.little),
      ]) {
        final payload = emfFixture();
        mutate(ByteData.sublistView(payload));
        expect(() => _document(metafileBlip(payload)), throwsFormatException);
      }
    },
  );

  test('rejects malformed standard and placeable WMF boundaries', () {
    for (final mutate in <void Function(ByteData)>[
      (h) => h.setUint32(6, 0xffffffff, Endian.little),
      (h) => h.setUint32(12, 2, Endian.little),
      (h) => h.setUint32(18, 0, Endian.little),
      (h) => h.setUint16(22, 0x100, Endian.little),
    ]) {
      final payload = wmfFixture();
      mutate(ByteData.sublistView(payload));
      expect(
        () => _document(metafileBlip(payload, emf: false)),
        throwsFormatException,
      );
    }
    final placeable = wmfFixture(placeable: true)..[20] ^= 1;
    expect(
      () => _document(metafileBlip(placeable, emf: false)),
      throwsFormatException,
    );
  });

  test('keeps GDI escapes inert instead of activating native image parts', () {
    for (final emf in [true, false]) {
      final payload = emf
          ? emfFixture(
              records: [
                emfRecord(105, [...wordU32(1), ...wordU32(0)]),
              ],
            )
          : wmfFixture(
              records: [
                wmfRecord(0x626, [...wordU16(9), ...wordU16(0)]),
              ],
            );
      final document = _document(metafileBlip(payload, emf: emf));
      expect(document.media.assets.single.isRenderable, isFalse);
      expect(document.media.assets.single.bytes, orderedEquals(payload));
      final result = convertLegacyWordDocument(document);
      expect(result.preservedCounts['pictureReferences'], isNull);
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.images),
      );
      expect(
        ZipDecoder()
            .decodeBytes(result.bytes)
            .files
            .where((f) => f.name.startsWith('word/media/')),
        isEmpty,
      );
    }
  });
}
