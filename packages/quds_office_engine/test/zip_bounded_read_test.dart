import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'duplicate rejection is opt-in and existing reader behavior is retained',
    () {
      final writer = ZipWriter()
        ..addFile('same', [1])
        ..addFile('same', [2]);
      final bytes = writer.close();
      expect(ZipReader.fromBytes(bytes).read('same'), [2]);
      expect(
        () => ZipReader.fromBytes(bytes, rejectDuplicateNames: true),
        throwsA(isA<ZipDuplicateEntryException>()),
      );
      expect(
        () => ZipReader.fromBytes(bytes, maxEntries: 1),
        throwsA(isA<ZipLimitException>()),
      );
    },
  );

  for (final store in [false, true]) {
    test(
      'bounded ZIP reads reject real output above forged sizes; store=$store',
      () {
        final expected = Uint8List.fromList(
          List<int>.generate(600, (index) => index % 251),
        );
        final writer = ZipWriter()..addFile('payload', expected, store: store);
        final bytes = writer.close();
        final reader = ZipReader.fromBytes(bytes);
        expect(reader.read('payload', maxBytes: 600), orderedEquals(expected));
        expect(
          () => reader.read('payload', maxBytes: 599),
          throwsA(isA<ZipLimitException>()),
        );
        final view = ByteData.sublistView(bytes);
        final central = view.getUint32(bytes.length - 6, Endian.little);
        view.setUint32(central + 24, 1, Endian.little);
        expect(
          () => ZipReader.fromBytes(bytes).read('payload', maxBytes: 599),
          throwsA(isA<ZipLimitException>()),
        );
      },
    );
  }

  for (final level in [0, 6]) {
    test(
      'raw inflate limits cover stored/literal/backreference output; level=$level',
      () {
        final expected = Uint8List.fromList(
          List<int>.generate(10000, (index) => index % 3),
        );
        final raw = RawDeflate.deflate(expected, level: level);
        expect(
          RawDeflate.inflate(raw, maxOutputBytes: expected.length),
          orderedEquals(expected),
        );
        for (final cap in [0, 1, 2, 128, expected.length - 1]) {
          expect(
            () => RawDeflate.inflate(raw, maxOutputBytes: cap),
            throwsA(isA<ZipDeflateLimitException>()),
          );
        }
      },
    );
  }

  test('empty streams can use a zero-byte budget', () {
    expect(
      RawDeflate.inflate(RawDeflate.deflate([]), maxOutputBytes: 0),
      isEmpty,
    );
    final writer = ZipWriter()..addFile('empty', []);
    expect(
      ZipReader.fromBytes(writer.close()).read('empty', maxBytes: 0),
      isEmpty,
    );
  });
}
