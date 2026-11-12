import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  group('bounded compound reader', () {
    test('small and regular streams retain exact contents', () {
      final regular = List<int>.generate(8192, (index) => index % 256);
      final writer = CfbfWriter()
        ..addStream('parent/small', [7, 9, 11])
        ..addStream('parent/large', regular);
      final reader = BoundedCfbReader(writer.build());
      expect(reader.readPath('parent/small'), orderedEquals([7, 9, 11]));
      expect(reader.readPath('parent/large'), orderedEquals(regular));
      expect(reader.readPath('small'), isNull);
    });

    test('duplicate FAT references fail before the parser allocates them', () {
      final bytes = (CfbfWriter()..addStream('small', [1])).build();
      final view = ByteData.sublistView(bytes);
      view.setUint32(80, view.getUint32(76, Endian.little), Endian.little);
      expect(() => BoundedCfbReader(bytes), throwsFormatException);
    });

    test('untrusted stream size and cumulative read budget are bounded', () {
      final bytes = (CfbfWriter()..addStream('small', [1, 2, 3])).build();
      final reader = BoundedCfbReader(bytes, maxTotalReadBytes: 4);
      expect(reader.readPath('small'), orderedEquals([1, 2, 3]));
      expect(() => reader.readPath('small'), throwsFormatException);
      final view = ByteData.sublistView(bytes);
      final directory = (view.getUint32(48, Endian.little) + 1) * 512;
      view.setUint32(directory + 128 + 120, 0x7fffffff, Endian.little);
      expect(() => BoundedCfbReader(bytes), throwsFormatException);
      view.setUint32(directory + 128 + 120, 3, Endian.little);
      view.setUint32(directory + 128 + 124, 1, Endian.little);
      expect(() => BoundedCfbReader(bytes), throwsFormatException);
    });

    test('file and individual stream limits are enforced independently', () {
      final bytes = (CfbfWriter()..addStream('small', [1, 2, 3])).build();
      expect(
        () => BoundedCfbReader(bytes, maxFileBytes: bytes.length - 1),
        throwsFormatException,
      );
      final reader = BoundedCfbReader(bytes, maxStreamBytes: 2);
      expect(() => reader.readPath('small'), throwsFormatException);
    });

    test(
      'a mini-stream cycle cannot repeat bytes to satisfy its declared size',
      () {
        final bytes =
            (CfbfWriter()..addStream('small', List<int>.filled(128, 7)))
                .build();
        final file = CfbfFile.fromBytes(bytes);
        final entry = file.entryByName('small')!;
        final data = ByteData.sublistView(bytes);
        final miniFatOffset = (data.getUint32(60, Endian.little) + 1) * 512;
        data.setUint32(
          miniFatOffset + entry.startSector * 4,
          entry.startSector,
          Endian.little,
        );
        final reader = BoundedCfbReader(bytes);
        expect(
          () => reader.readPath('small'),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Invalid compound mini-stream chain',
            ),
          ),
        );
      },
    );
  });
}
