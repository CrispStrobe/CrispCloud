import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_pbzx_source.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_pbzx_fixtures.dart';

class _TrackedSource implements koni.ByteSource {
  _TrackedSource(this.bytes);
  final Uint8List bytes;
  final reads = <(int, int)>[];
  int closes = 0;
  bool shortReads = false;
  Completer<void>? gate;
  @override
  int get length => bytes.length;
  @override
  String get name => 'Payload';
  @override
  Future<Uint8List> read(int offset, int count) async {
    if (closes > 0) throw StateError('Read after close');
    if (offset < 0 || count < 0 || count > length - offset) {
      throw StateError('Out-of-bounds read');
    }
    reads.add((offset, count));
    await gate?.future;
    return Uint8List.sublistView(
      bytes,
      offset,
      offset + count - (shortReads && count > 0 ? 1 : 0),
    );
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  test('rejects callers raising the per-read allocation bound', () async {
    final source = _TrackedSource(pbzxFixture([[1, 2, 3]]));
    await expectLater(
      ArchivePbzxSource.open(source, maxReadBytes: kArchiveReadLimit + 1),
      throwsArgumentError,
    );
    expect(source.closes, 1);
    expect(source.reads, isEmpty);
  });

  test(
    'indexes only metadata and lazily reads mixed stored/XZ chunks',
    () async {
      final raw = List<int>.generate(1024, (i) => i % 251);
      final source = _TrackedSource(
        pbzxFixture(
          [
            raw,
            List.filled(1024, 42),
            [1, 2, 3],
          ],
          compressedChunks: {1},
        ),
      );
      final decoded = await ArchivePbzxSource.open(source);
      expect(decoded.length, 2051);
      expect(source.reads.map((r) => r.$2), [12, 16, 16, 16]);
      expect(await decoded.read(1020, 9), [
        ...raw.skip(1020),
        42,
        42,
        42,
        42,
        42,
      ]);
      final before = source.reads.length;
      expect(await decoded.read(1200, 4), List.filled(4, 42));
      expect(
        source.reads.length,
        before,
        reason: 'one shared decoded-chunk cache',
      );
      expect(await decoded.read(2048, 3), [1, 2, 3]);
      expect(await decoded.read(0, 3), raw.take(3));
      await decoded.close();
      await decoded.close();
      expect(source.closes, 1);
      expect(() => decoded.read(0, 1), throwsA(isA<ArchiveViewException>()));
    },
  );

  test('concurrent requests reuse one bounded chunk decode', () async {
    final source = _TrackedSource(
      pbzxFixture([List.filled(4096, 9)], compressedChunks: {0}),
    );
    final decoded = await ArchivePbzxSource.open(source);
    addTearDown(decoded.close);
    final before = source.reads.length;
    final outputs = await Future.wait([
      decoded.read(0, 5),
      decoded.read(4000, 5),
    ]);
    expect(outputs, [List.filled(5, 9), List.filled(5, 9)]);
    expect(source.reads.length, before + 1);
  });

  test(
    'close invalidates in-flight and queued reads without repopulating cache',
    () async {
      final source = _TrackedSource(pbzxFixture([List.filled(1024, 9)]));
      final decoded = await ArchivePbzxSource.open(source);
      source.gate = Completer<void>();
      final first = decoded.read(0, 1);
      final second = decoded.read(1, 1);
      final firstCheck = expectLater(
        first,
        throwsA(isA<ArchiveViewException>()),
      );
      final secondCheck = expectLater(
        second,
        throwsA(isA<ArchiveViewException>()),
      );
      await Future<void>.delayed(Duration.zero);
      await decoded.close();
      source.gate!.complete();
      await Future.wait([firstCheck, secondCheck]);
      expect(source.closes, 1);
      expect(
        source.reads.length,
        3,
        reason: 'queued read must not touch closed parent',
      );
    },
  );

  test('validates checksums and exact decoded length on lazy reads', () async {
    final packed = pbzxFixture([List.filled(2048, 7)], compressedChunks: {0});
    for (final kind in ['checksum', 'length', 'magic']) {
      final bad = Uint8List.fromList(packed);
      if (kind == 'checksum') bad[bad.length - 16] ^= 0x80;
      if (kind == 'length') ByteData.sublistView(bad).setUint64(12, 2047);
      if (kind == 'magic') bad[28] = 0;
      final decoded = await ArchivePbzxSource.open(koni.MemoryByteSource(bad));
      addTearDown(decoded.close);
      await expectLater(
        decoded.read(0, 1),
        throwsA(isA<ArchiveViewException>()),
        reason: kind,
      );
    }
  });

  test('rejects short underlying reads while opening or decoding', () async {
    final bad = _TrackedSource(
      pbzxFixture([
        [1, 2, 3],
      ]),
    )..shortReads = true;
    await expectLater(
      ArchivePbzxSource.open(bad),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(bad.closes, 1);
    final source = _TrackedSource(
      pbzxFixture([
        [1, 2, 3],
      ]),
    );
    final decoded = await ArchivePbzxSource.open(source);
    addTearDown(decoded.close);
    source.shortReads = true;
    await expectLater(decoded.read(0, 1), throwsA(isA<ArchiveViewException>()));
  });

  test(
    'bounds per-read allocation and rejects out-of-range requests',
    () async {
      final decoded = await ArchivePbzxSource.open(
        koni.MemoryByteSource(
          pbzxFixture([
            [1, 2, 3],
          ]),
        ),
        maxReadBytes: 2,
      );
      addTearDown(decoded.close);
      for (final range in [(-1, 1), (0, -1), (2, 2), (4, 0), (0, 3)]) {
        expect(
          () => decoded.read(range.$1, range.$2),
          throwsA(isA<ArchiveViewException>()),
        );
      }
      expect(await decoded.read(3, 0), isEmpty);
    },
  );

  test('accepts an empty PBZX stream without allocating a chunk', () async {
    final decoded = await ArchivePbzxSource.open(
      koni.MemoryByteSource(pbzxFixture([])),
    );
    addTearDown(decoded.close);
    expect(decoded.length, 0);
    expect(await decoded.read(0, 0), isEmpty);
  });

  final mutations = <String, void Function(Uint8List)>{
    'wrong algorithm': (b) {
      b[3] = 0x34;
    },
    'zero block size': (b) {
      ByteData.sublistView(b).setUint64(4, 0);
    },
    'large block size': (b) {
      ByteData.sublistView(b).setUint64(4, kPbzxChunkLimit + 1);
    },
    'uint64 overflow': (b) {
      ByteData.sublistView(b).setUint32(4, 0xffffffff);
    },
    'zero decoded size': (b) {
      ByteData.sublistView(b).setUint64(12, 0);
    },
    'chunk above block size': (b) {
      ByteData.sublistView(b).setUint64(12, 4);
    },
    'zero stored size': (b) {
      ByteData.sublistView(b).setUint64(20, 0);
    },
    'stored size above decoded size': (b) {
      ByteData.sublistView(b).setUint64(20, 4);
    },
  };
  for (final mutation in mutations.entries) {
    test('rejects ${mutation.key} before payload allocation', () async {
      final bytes = pbzxFixture([
        [1, 2, 3],
      ]);
      mutation.value(bytes);
      final source = _TrackedSource(bytes);
      await expectLater(
        ArchivePbzxSource.open(source),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.closes, 1);
      expect(source.reads.every((r) => r.$2 <= 16), isTrue);
    });
  }

  test(
    'rejects truncation, short interior chunks and aggregate overflow',
    () async {
      final bytes = pbzxFixture([
        [1, 2, 3],
      ]);
      for (final length in [0, 4, 11, 13, 27, bytes.length - 1]) {
        await expectLater(
          ArchivePbzxSource.open(
            koni.MemoryByteSource(Uint8List.sublistView(bytes, 0, length)),
          ),
          throwsA(isA<ArchiveViewException>()),
        );
      }
      await expectLater(
        ArchivePbzxSource.open(
          koni.MemoryByteSource(
            pbzxFixture([
              [1],
              [2],
            ], blockSize: 3),
          ),
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      await expectLater(
        ArchivePbzxSource.open(
          koni.MemoryByteSource(
            pbzxFixture([
              [1, 2, 3],
              [4, 5, 6],
            ]),
          ),
          maxDecodedBytes: 5,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );
}
