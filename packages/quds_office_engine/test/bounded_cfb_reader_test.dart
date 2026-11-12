import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  group('bounded compound reader', () {
    test('directory owners are distinct and lookups are immutable', () {
      final bytes = _directoryFixture();
      final reader = BoundedCfbReader(bytes);
      expect(reader.readPath('storageA/shared'), orderedEquals([1, 2]));
      expect(reader.readPath('STORAGEb/SHARED'), orderedEquals([3, 4]));
      final children = reader.childrenOf(reader.root);
      expect(
        children.map((entry) => entry.name),
        containsAll(['storageA', 'storageB', 'alone']),
      );
      expect(() => children[0] = children.last, throwsUnsupportedError);
      expect(reader.readPath('storageA/shared'), orderedEquals([1, 2]));
    });

    final malformedDirectories = <String, void Function(Uint8List, CfbfFile)>{
      'two storages share a child tree': (bytes, file) {
        final a = file.entryByName('storageA')!;
        final b = file.entryByName('storageB')!;
        _setDirectoryWord(bytes, file, b, 76, a.child);
      },
      'a sibling points to itself': (bytes, file) {
        final entry = file.entryByName('alone')!;
        _setDirectoryWord(bytes, file, entry, 68, entry.index);
      },
      'a child points to the root storage': (bytes, file) {
        final entry = file.entryByName('storageA')!;
        _setDirectoryWord(bytes, file, entry, 76, file.root.index);
      },
      'a stream owns children': (bytes, file) {
        final stream = file.entryByName('alone')!;
        _setDirectoryWord(
          bytes,
          file,
          stream,
          76,
          file.entryByName('storageA')!.child,
        );
      },
      'the root has a sibling': (bytes, file) {
        _setDirectoryWord(
          bytes,
          file,
          file.root,
          72,
          file.entryByName('alone')!.index,
        );
      },
      'a referenced child is empty': (bytes, file) {
        bytes[_directoryOffset(file, file.entryByName('alone')!) + 66] = 0;
      },
      'a sibling is outside the directory': (bytes, file) {
        _setDirectoryWord(
          bytes,
          file,
          file.entryByName('alone')!,
          72,
          0xfffffffd,
        );
      },
      'siblings have duplicate case-insensitive names': (bytes, file) {
        final offset = _directoryOffset(file, file.entryByName('alone')!);
        const name = 'STORAGEa';
        bytes.fillRange(offset, offset + 64, 0);
        final view = ByteData.sublistView(bytes);
        for (var i = 0; i < name.length; i++) {
          view.setUint16(offset + i * 2, name.codeUnitAt(i), Endian.little);
        }
        view.setUint16(offset + 64, (name.length + 1) * 2, Endian.little);
      },
    };
    for (final entry in malformedDirectories.entries) {
      test('rejects at construction when ${entry.key}', () {
        final bytes = _directoryFixture();
        final file = CfbfFile.fromBytes(bytes);
        entry.value(bytes, file);
        expect(() => BoundedCfbReader(bytes), throwsFormatException);
      });
    }

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

Uint8List _directoryFixture() =>
    (CfbfWriter()
          ..addStream('storageA/shared', [1, 2])
          ..addStream('storageB/shared', [3, 4])
          ..addStream('alone', [5]))
        .build();

int _directoryOffset(CfbfFile file, CfbfDirectoryEntry entry) {
  final perSector = file.header.sectorSize ~/ 128;
  var sector = file.header.firstDirectorySector;
  for (var i = 0; i < entry.index ~/ perSector; i++) {
    sector = file.fat[sector];
  }
  return file.header.sectorOffset(sector) + (entry.index % perSector) * 128;
}

void _setDirectoryWord(
  Uint8List bytes,
  CfbfFile file,
  CfbfDirectoryEntry entry,
  int relativeOffset,
  int value,
) {
  ByteData.sublistView(bytes).setUint32(
    _directoryOffset(file, entry) + relativeOffset,
    value,
    Endian.little,
  );
}
