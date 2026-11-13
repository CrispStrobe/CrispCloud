import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_volume_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_volume_fixtures.dart';

class _Part {
  _Part(Uint8List bytes) : this.sparse(bytes.length, {0: bytes});
  _Part.sparse(this.length, this.regions);
  final int length;
  final Map<int, Uint8List> regions;
  final opened = <_Source>[];
  int validations = 0;
  bool changed = false,
      shortRead = false,
      throwRead = false,
      throwClose = false;
  Completer<void>? opening, reading, entered;
  void Function()? onRead, onOpen;

  ArchiveVolumePart descriptor(String name) => ArchiveVolumePart(
    name: name,
    length: length,
    validate: () async {
      validations++;
      if (changed) throw StateError('Captured identity changed.');
    },
    open: () async {
      entered?.complete();
      await opening?.future;
      final source = _Source(this);
      opened.add(source);
      onOpen?.call();
      return source;
    },
  );
}

class _Source implements koni.ByteSource {
  _Source(this.part) : length = part.length;
  final _Part part;
  @override
  int length;
  @override
  String get name => 'captured-part';
  int closes = 0;
  final reads = <({int offset, int count})>[];

  @override
  Future<Uint8List> read(int offset, int count) async {
    reads.add((offset: offset, count: count));
    if (closes != 0) throw StateError('Read after part close.');
    if (offset < 0 || count < 0 || offset > length || count > length - offset) {
      throw StateError('Underlying read leaves a part.');
    }
    part.onRead?.call();
    await part.reading?.future;
    if (part.throwRead) throw StateError('Injected read failure.');
    final bytes = Uint8List(part.shortRead && count > 0 ? count - 1 : count);
    for (final region in part.regions.entries) {
      final from = offset > region.key ? offset : region.key;
      final availableEnd = region.key + region.value.length;
      final to = offset + bytes.length < availableEnd
          ? offset + bytes.length
          : availableEnd;
      if (from < to) {
        bytes.setRange(
          from - offset,
          to - offset,
          region.value,
          from - region.key,
        );
      }
    }
    return bytes;
  }

  @override
  Future<void> close() async {
    closes++;
    if (part.throwClose) throw StateError('Injected close failure.');
  }
}

List<_Part> _parts(Uint8List bytes, {int size = 97, List<int>? sizes}) =>
    volumeSplitBytes(
      bytes,
      partBytes: size,
      sizes: sizes,
    ).map(_Part.new).toList();

List<ArchiveVolumePart> _manifest(List<_Part> parts, {int width = 3}) => [
  for (var index = 0; index < parts.length; index++)
    parts[index].descriptor(
      'fixture.7z.${(index + 1).toString().padLeft(width, '0')}',
    ),
];

Iterable<_Source> _opened(List<_Part> parts) =>
    parts.expand((part) => part.opened);

void _allClosed(List<_Part> parts) {
  for (final source in _opened(parts)) {
    expect(source.closes, 1);
  }
}

Future<koni.ArchiveReader> _reader(
  ArchiveVolumeSource source, {
  String? password,
}) => koni.builtInFormats.openReader(
  source,
  options: koni.ArchiveReadOptions(
    password: password,
    maxEntryCount: 200000,
    maxEntrySize: kArchiveReadLimit,
    maxContainerDecodeSize: kArchiveReadLimit,
  ),
);

Future<Uint8List> _member(koni.ArchiveReader reader, String name) async {
  final entry = reader.entries.singleWhere((entry) => entry.path == name);
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in reader.openRead(entry)) {
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

void _startCrc(Uint8List bytes) => ByteData.sublistView(
  bytes,
).setUint32(8, getCrc32(Uint8List.sublistView(bytes, 12, 32)), Endian.little);

void main() {
  group('split 7z source', () {
    test(
      'independent four-volume 7-Zip fixture lists and reads exact bytes',
      () async {
        final bytes = volumeReferenceSevenZip();
        final parts = _parts(bytes);
        expect(parts.map((part) => part.length), volumeReferenceSizes);
        final source = await openSevenZipVolumes(_manifest(parts));
        final reader = await _reader(source);
        expect(source.name, 'fixture.7z');
        expect(source.partCount, 4);
        expect(await _member(reader, 'first.txt'), volumeReferenceFirstFile());
        expect(
          utf8.decode(await _member(reader, 'nested/second.txt')),
          'Second member in another volume.\n',
        );
        await reader.close();
        await source.close();
        await source.close();
        _allClosed(parts);
      },
    );

    test(
      'signature and next header can span many tiny variable-size parts',
      () async {
        final bytes = volumeReferenceSevenZip();
        final parts = _parts(bytes, sizes: [1, 2, 3, 4, 5, 6, 7, 8, 251, 33]);
        final source = await openSevenZipVolumes(_manifest(parts, width: 4));
        addTearDown(source.close);
        expect(await source.read(0, bytes.length), bytes);
        final reader = await _reader(source);
        addTearDown(reader.close);
        expect(await _member(reader, 'first.txt'), volumeReferenceFirstFile());
      },
    );

    test(
      'single numbered part and a deliberately small read window work',
      () async {
        final bytes = volumeReferenceSevenZip();
        final parts = [_Part(bytes)];
        final source = await openSevenZipVolumes(
          _manifest(parts),
          maxReadBytes: 7,
        );
        addTearDown(source.close);
        expect(
          await source.read(bytes.length - 7, 7),
          bytes.sublist(bytes.length - 7),
        );
        await expectLater(
          source.read(0, 8),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );

    test(
      'ordinary compressed 7z remains readable after byte splitting',
      () async {
        final bytes = File('test/fixtures/archives/sample.7z')
            .readAsBytesSync();
        final source = await openSevenZipVolumes(
          _manifest(_parts(bytes, size: 127)),
        );
        addTearDown(source.close);
        final reader = await _reader(source);
        addTearDown(reader.close);
        expect((await _member(reader, 'nested/deep/data.bin')).length, 100000);
      },
    );

    test(
      'logical source supports independent concurrent positional requests',
      () async {
        final bytes = volumeReferenceSevenZip();
        final source = await openSevenZipVolumes(_manifest(_parts(bytes)));
        addTearDown(source.close);
        final ranges = [(90, 125), (0, 32), (280, 40), (12, 4), (97, 97)];
        final results = await Future.wait([
          for (final range in ranges) source.read(range.$1, range.$2),
        ]);
        for (var index = 0; index < ranges.length; index++) {
          final range = ranges[index];
          expect(results[index], bytes.sublist(range.$1, range.$1 + range.$2));
        }
      },
    );

    test(
      'handle cache stays bounded and reopens evicted parts independently',
      () async {
        final parts = _parts(volumeReferenceSevenZip());
        var peak = 0;
        for (final part in parts) {
          part.onOpen = () {
            final active = _opened(parts)
                .where((source) => source.closes == 0)
                .length;
            if (active > peak) peak = active;
          };
        }
        final source = await openSevenZipVolumes(_manifest(parts));
        for (final offset in [100, 200, 10, 300, 100, 200, 10]) {
          await source.read(offset, 1);
        }
        expect(peak, 2);
        expect(parts.first.opened.length, greaterThan(1));
        await source.close();
        _allClosed(parts);
      },
    );

    test(
      '5 GiB logical archive opens with bounded metadata reads only',
      () async {
        const total = 5 * 1024 * 1024 * 1024;
        const firstSize = 2 * 1024 * 1024 * 1024 + 7;
        const secondSize = 2 * 1024 * 1024 * 1024 + 11;
        const lastSize = total - firstSize - secondSize;
        final next = Uint8List.fromList([1, 0]);
        final header = Uint8List(32)
          ..setRange(0, 8, [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0, 4]);
        final view = ByteData.sublistView(header);
        view.setUint64(12, total - 32 - next.length, Endian.little);
        view.setUint64(20, next.length, Endian.little);
        view.setUint32(28, getCrc32(next), Endian.little);
        _startCrc(header);
        final parts = [
          _Part.sparse(firstSize, {0: header}),
          _Part.sparse(secondSize, {}),
          _Part.sparse(lastSize, {lastSize - next.length: next}),
        ];
        final source = await openSevenZipVolumes(_manifest(parts));
        expect(source.length, total);
        expect(parts[1].opened, isEmpty);
        expect(
          _opened(parts)
              .expand((source) => source.reads)
              .fold<int>(0, (sum, read) => sum + read.count),
          34,
        );
        expect(await source.read(firstSize - 2, 5), [0, 0, 0, 0, 0]);
        await source.close();
        _allClosed(parts);
      },
    );

    test(
      'large individual reads are broken into 256 KiB input requests',
      () async {
        const body = 700000;
        final header = Uint8List(32)
          ..setRange(0, 8, [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0, 4]);
        ByteData.sublistView(header).setUint64(12, body, Endian.little);
        _startCrc(header);
        final part = _Part.sparse(32 + body, {0: header});
        final source = await openSevenZipVolumes(_manifest([part]));
        expect((await source.read(32, body)).length, body);
        expect(
          part.opened.single.reads.every((read) => read.count <= 256 * 1024),
          isTrue,
        );
        await source.close();
      },
    );
  });

  group('manifest refusals', () {
    final invalid = <String, List<String>>{
      'empty': [],
      'not first': ['fixture.7z.002'],
      'gap': ['fixture.7z.001', 'fixture.7z.003'],
      'duplicate': ['fixture.7z.001', 'fixture.7z.001'],
      'wrong order': ['fixture.7z.001', 'fixture.7z.003', 'fixture.7z.002'],
      'mixed width': ['fixture.7z.001', 'fixture.7z.0002'],
      'short suffix': ['fixture.7z.01'],
      'overlong suffix': ['fixture.7z.0000001'],
      'wrong base': ['fixture.7z.001', 'other.7z.002'],
      'case alias': ['fixture.7z.001', 'Fixture.7z.002'],
      'parent traversal': ['../fixture.7z.001'],
      'windows path': [r'..\fixture.7z.001'],
      'absolute path': ['/fixture.7z.001'],
      'nul name': ['fi\x00xture.7z.001'],
      'wrong format': ['fixture.zip.001'],
    };
    for (final example in invalid.entries) {
      test('rejects ${example.key} before opening any source', () async {
        var opens = 0, releases = 0;
        final parts = [
          for (final name in example.value)
            ArchiveVolumePart(
              name: name,
              length: 32,
              open: () async {
                opens++;
                return koni.MemoryByteSource(Uint8List(32));
              },
            ),
        ];
        await expectLater(
          openSevenZipVolumes(parts, onClose: () async => releases++),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(opens, 0);
        expect(releases, 1);
      });
    }

    test(
      'empty parts, excessive part count and aggregate size are refused',
      () async {
        final part = _Part(volumeReferenceSevenZip());
        for (final parts in [
          [
            ArchiveVolumePart(
              name: 'a.7z.001',
              length: 0,
              open: () async => _Source(part),
            ),
          ],
          [
            ArchiveVolumePart(
              name: 'a.7z.001',
              length: kArchiveStreamingLimit + 1,
              open: () async => _Source(part),
            ),
          ],
          _manifest([part, part]),
        ]) {
          await expectLater(
            openSevenZipVolumes(parts, maxVolumes: 1),
            throwsA(isA<ArchiveViewException>()),
          );
        }
        expect(part.opened, isEmpty);
      },
    );

    test('preflight validates names and total without acquiring handles', () {
      final parts = _parts(volumeReferenceSevenZip());
      final manifest = validateSevenZipVolumeManifest(_manifest(parts));
      expect(manifest.name, 'fixture.7z');
      expect(manifest.length, 320);
      expect(_opened(parts), isEmpty);
      expect(sevenZipVolumeBaseName('fixture.7z.01'), 'fixture.7z');
      expect(sevenZipVolumeBaseName('fixture.7Z.0001'), 'fixture.7Z');
      expect(sevenZipVolumeBaseName('fixture.7z.txt'), isNull);
    });
  });

  group('framing and input validation', () {
    final corruptions = <String, void Function(Uint8List)>{
      'signature': (bytes) => bytes[0] ^= 1,
      'major version': (bytes) => bytes[6] = 1,
      'start checksum': (bytes) => bytes[8] ^= 1,
      'next checksum': (bytes) => bytes[bytes.length - 1] ^= 1,
      'unrepresentable offset': (bytes) {
        ByteData.sublistView(bytes).setUint32(16, 0x200000, Endian.little);
        _startCrc(bytes);
      },
      'out of bounds offset': (bytes) {
        ByteData.sublistView(bytes).setUint64(12, 1000000, Endian.little);
        _startCrc(bytes);
      },
    };
    for (final mutation in corruptions.entries) {
      test('rejects ${mutation.key} and releases all opened inputs', () async {
        final bytes = volumeReferenceSevenZip();
        mutation.value(bytes);
        final parts = _parts(bytes);
        var releases = 0;
        await expectLater(
          openSevenZipVolumes(
            _manifest(parts),
            onClose: () async => releases++,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
        _allClosed(parts);
        expect(releases, 1);
      });
    }

    test(
      'missing final volume, truncated signature and trailing part fail',
      () async {
        for (final bytes in [
          Uint8List.fromList(volumeReferenceSevenZip().sublist(0, 291)),
          Uint8List(31),
          Uint8List.fromList([...volumeReferenceSevenZip(), 0]),
        ]) {
          final parts = _parts(bytes);
          await expectLater(
            openSevenZipVolumes(_manifest(parts)),
            throwsA(isA<ArchiveViewException>()),
          );
          _allClosed(parts);
        }
      },
    );

    test(
      'metadata budget rejects a bounded next header before reading it',
      () async {
        final parts = _parts(volumeReferenceSevenZip());
        await expectLater(
          openSevenZipVolumes(_manifest(parts), maxMetadataBytes: 32),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(parts.last.opened, isEmpty);
        _allClosed(parts);
      },
    );

    test(
      'short reads and native failures clean up the attempted source',
      () async {
        for (final short in [true, false]) {
          final parts = _parts(volumeReferenceSevenZip());
          parts.first.shortRead = short;
          parts.first.throwRead = !short;
          await expectLater(
            openSevenZipVolumes(_manifest(parts)),
            throwsA(anyOf(isA<ArchiveViewException>(), isA<StateError>())),
          );
          _allClosed(parts);
        }
      },
    );

    test(
      'range and configuration checks retain explicit error types',
      () async {
        final source = await openSevenZipVolumes(
          _manifest(_parts(volumeReferenceSevenZip())),
        );
        addTearDown(source.close);
        expect(await source.read(source.length, 0), isEmpty);
        await expectLater(source.read(-1, 0), throwsArgumentError);
        await expectLater(source.read(0, -1), throwsArgumentError);
        await expectLater(
          source.read(source.length, 1),
          throwsA(isA<koni.UnexpectedEofException>()),
        );
        await expectLater(
          source.read(source.length + 1, 0),
          throwsA(isA<koni.UnexpectedEofException>()),
        );
        var released = false;
        await expectLater(
          openSevenZipVolumes(
            [],
            maxReadBytes: 0,
            onClose: () async => released = true,
          ),
          throwsArgumentError,
        );
        expect(released, isTrue);
      },
    );
  });

  group('ownership and change races', () {
    test(
      'changed cached length does not lose the handle during cleanup',
      () async {
        final parts = _parts(volumeReferenceSevenZip());
        final source = await openSevenZipVolumes(_manifest(parts));
        parts.last.opened.single.length++;
        await expectLater(
          source.read(source.length - 1, 1),
          throwsA(isA<ArchiveViewException>()),
        );
        await source.close();
        _allClosed(parts);
      },
    );

    test(
      'all manifest identities are checked even for unopened middle parts',
      () async {
        final parts = _parts(volumeReferenceSevenZip());
        parts[1].changed = true;
        var released = false;
        await expectLater(
          openSevenZipVolumes(
            _manifest(parts),
            onClose: () async => released = true,
          ),
          throwsStateError,
        );
        expect(_opened(parts), isEmpty);
        expect(released, isTrue);
      },
    );

    test('part identity is rechecked after each completed read', () async {
      final parts = _parts(volumeReferenceSevenZip());
      final source = await openSevenZipVolumes(_manifest(parts));
      parts[1].onRead = () => parts[1].changed = true;
      await expectLater(source.read(100, 1), throwsStateError);
      await source.close();
      _allClosed(parts);
    });

    test('source guard invalidation rejects reads and pending opens', () async {
      final parts = _parts(volumeReferenceSevenZip());
      var current = true;
      final source = await openSevenZipVolumes(
        _manifest(parts),
        isCurrent: () => current,
      );
      parts[1].onOpen = () => current = false;
      await expectLater(
        source.read(100, 1),
        throwsA(isA<ArchiveViewException>()),
      );
      await expectLater(
        source.read(0, 1),
        throwsA(isA<ArchiveViewException>()),
      );
      await source.close();
      _allClosed(parts);
    });

    test(
      'close waits for a pending open and releases shared ownership last',
      () async {
        final parts = _parts(volumeReferenceSevenZip());
        var released = false;
        final source = await openSevenZipVolumes(
          _manifest(parts),
          onClose: () async {
            _allClosed(parts);
            released = true;
          },
        );
        parts[1].opening = Completer<void>();
        parts[1].entered = Completer<void>();
        final pending = expectLater(
          source.read(100, 1),
          throwsA(isA<koni.ArchiveClosedException>()),
        );
        await parts[1].entered!.future;
        final closing = source.close();
        expect(source.isClosed, isTrue);
        expect(released, isFalse);
        parts[1].opening!.complete();
        await pending;
        await closing;
        expect(released, isTrue);
        _allClosed(parts);
      },
    );

    test(
      'close invalidates a read before returning partial cross-volume data',
      () async {
        final parts = _parts(volumeReferenceSevenZip());
        final source = await openSevenZipVolumes(_manifest(parts));
        final entered = Completer<void>();
        parts.first.reading = Completer<void>();
        parts.first.onRead = entered.complete;
        final pending = expectLater(
          source.read(90, 20),
          throwsA(isA<koni.ArchiveClosedException>()),
        );
        await entered.future;
        final closing = source.close();
        parts.first.reading!.complete();
        await pending;
        await closing;
        await expectLater(
          source.read(0, 1),
          throwsA(isA<koni.ArchiveClosedException>()),
        );
        _allClosed(parts);
      },
    );

    test('cleanup continues after one part close fails', () async {
      final parts = _parts(volumeReferenceSevenZip());
      var released = 0;
      final source = await openSevenZipVolumes(
        _manifest(parts),
        onClose: () async => released++,
      );
      parts.last.throwClose = true;
      await expectLater(source.close(), throwsStateError);
      await expectLater(source.close(), throwsStateError);
      expect(released, 1);
      _allClosed(parts);
    });
  });
}
