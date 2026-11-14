import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_lzfse_codec.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lzfse_fixture.dart';
import 'support/lzfse_malformed_fixture.dart';

void main() {
  for (final fixture in lzfseReferenceFixtures) {
    test('decodes Apple-verified ${fixture.name} stream exactly', () {
      final expected = fixture.plain;
      expect(
        decodeArchiveLzfse(fixture.packed, expectedBytes: expected.length),
        expected,
      );
    });
  }

  test('handles views with a nonzero byte offset without mutating input', () {
    final fixture = lzfseV2Fixture;
    final packed = fixture.packed;
    final backing = Uint8List(packed.length + 19)
      ..fillRange(0, packed.length + 19, 0xa5);
    backing.setAll(7, packed);
    final view = Uint8List.sublistView(backing, 7, 7 + packed.length);
    final original = Uint8List.fromList(backing);
    final expected = fixture.plain;
    for (var i = 0; i < 2; i++) {
      expect(
        decodeArchiveLzfse(view, expectedBytes: expected.length),
        expected,
      );
    }
    expect(backing, original);
  });

  test('accepts the end marker alone for an empty stream', () {
    expect(decodeArchiveLzfse(lzfseStream([]), expectedBytes: 0), isEmpty);
  });

  for (final fixture in [
    lzfseRawFixture,
    lzfseLzvnFixture,
    lzfseV1Fixture,
    lzfseV2Fixture,
  ]) {
    test('rejects every truncated ${fixture.name} prefix', () {
      final packed = fixture.packed;
      final length = fixture.plain.length;
      for (var end = 0; end < packed.length; end++) {
        expect(
          () => decodeArchiveLzfse(
            Uint8List.sublistView(packed, 0, end),
            expectedBytes: length,
          ),
          throwsA(isA<ArchiveViewException>()),
          reason: '${fixture.name} prefix $end/${packed.length}',
        );
      }
    });
  }

  for (final fixture in lzfseMalformedFixtures()) {
    test('rejects ${fixture.name}', () {
      expect(
        () => decodeArchiveLzfse(
          fixture.packed,
          expectedBytes: fixture.expectedBytes,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
    });
  }

  test('bounds empty-block work independently of output length', () {
    final empty = lzfseStoredBlock([]);
    expect(
      decodeArchiveLzfse(
        lzfseStream(List.filled(4096, empty)),
        expectedBytes: 0,
      ),
      isEmpty,
    );
    expect(
      () => decodeArchiveLzfse(
        lzfseStream(List.filled(4097, empty)),
        expectedBytes: 0,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test('rejects fixed output and input ceilings before decoding', () {
    for (final length in [-1, kArchiveLzfseChunkLimit + 1]) {
      expect(
        () => decodeArchiveLzfse(Uint8List(0), expectedBytes: length),
        throwsA(isA<ArchiveViewException>()),
      );
    }
    expect(
      () => decodeArchiveLzfse(
        Uint8List(kArchiveLzfseChunkLimit + 1),
        expectedBytes: 0,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test('caller can lower but cannot raise the decoder ceiling', () {
    final fixture = lzfseLzvnFixture;
    expect(
      decodeArchiveLzfse(
        fixture.packed,
        expectedBytes: 1024,
        maxOutputBytes: 1024,
      ),
      fixture.plain,
    );
    expect(
      () => decodeArchiveLzfse(
        fixture.packed,
        expectedBytes: 1024,
        maxOutputBytes: 1023,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    for (final limit in [0, -1, kArchiveLzfseChunkLimit + 1]) {
      expect(
        () => decodeArchiveLzfse(
          Uint8List(0),
          expectedBytes: 0,
          maxOutputBytes: limit,
        ),
        throwsArgumentError,
      );
    }
  });
}
