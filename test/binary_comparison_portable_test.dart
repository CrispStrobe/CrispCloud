import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/binary_comparison_source.dart';
import 'package:crisp_cloud/services/file_comparison_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';

/// No host-file or browser mocks: the real capture chooses native private
/// storage on the VM and its bounded memory implementation in compiled JS.
class _PortableBackend extends FileOperationBackend {
  _PortableBackend(List<int> bytes) : bytes = Uint8List.fromList(bytes);

  Uint8List bytes;
  bool current = true, knownSize = true;
  int? declaredSize;
  Object sourceIdentity = Object();
  final metadata = <String, dynamic>{};
  int reads = 0, stats = 0, writes = 0;
  Future<FileItem?> Function(int call)? onStat;
  Stream<List<int>> Function(int call)? onRead;

  FileItem get item => FileItem(
    name: 'fixture.bin',
    path: '/fixture.bin',
    uuid: 'fixture-object',
    isFolder: false,
    size: knownSize ? declaredSize ?? bytes.length : null,
    updatedAt: DateTime.utc(2026, 11, 14),
    metadata: metadata,
  );

  @override
  Object get identity => sourceIdentity;
  @override
  bool get isCurrent => current;
  @override
  String get label => 'Portable comparison fixture';
  @override
  p.Context get paths => p.Context(style: p.Style.posix);

  @override
  Future<FileItem?> stat(String path) async {
    stats++;
    if (path != item.path) return null;
    return onStat == null ? item : await onStat!(stats);
  }

  @override
  Stream<List<int>> readFile(FileItem file) {
    reads++;
    return onRead == null
        ? Stream.value(Uint8List.fromList(bytes))
        : onRead!(reads);
  }

  @override
  Future<List<FileItem>> list(String path) async => [item];
  @override
  Future<void> createDirectory(String path) async {
    writes++;
  }

  @override
  Future<void> deleteFile(FileItem file) async {
    writes++;
  }

  @override
  Future<void> deleteEmptyDirectory(String path) async {
    writes++;
  }

  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async {
    writes++;
  }
}

Future<BinaryComparisonSession> _open(
  _PortableBackend left,
  _PortableBackend right, {
  int maxIndexedRanges = 4096,
  bool Function()? isCancelled,
}) => BinaryComparisonSession.open(
  left,
  left.item,
  right,
  right.item,
  maxIndexedRanges: maxIndexedRanges,
  isCancelled: isCancelled,
);

void main() {
  test(
    'the actual target enforces its default capture ceiling before reading',
    () async {
      const expected = kIsWeb ? 32 * 1024 * 1024 : 8 * 1024 * 1024 * 1024;
      const limits = BinaryComparisonLimits();
      expect(limits.maxBytes, expected);
      expect(limits.maxChunks, 1024 * 1024);
      expect(limits.maxEmptyChunks, 1024);
      limits.validate();
      expect(
        () => const BinaryComparisonLimits(maxBytes: expected + 1).validate(),
        throwsRangeError,
      );
      final backend = _PortableBackend([0])..declaredSize = expected + 1;
      await expectLater(
        BinaryComparisonSnapshot.capture(backend, backend.item),
        throwsA(isA<BinaryComparisonLimitExceeded>()),
      );
      expect(backend.reads, 0);
      expect(backend.writes, 0);
    },
  );

  test('two-pass capture matches the published SHA-256 abc vector and owns its bytes', () async {
    final backend = _PortableBackend([0x61, 0x62, 0x63]);
    final snapshot = await BinaryComparisonSnapshot.capture(
      backend,
      backend.item,
      limits: const BinaryComparisonLimits(maxBytes: 3),
    );
    addTearDown(snapshot.close);
    expect(
      snapshot.sha256Digest,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(snapshot.length, 3);
    expect(backend.reads, 2);

    final page = await snapshot.read(0, 3);
    page[0] = 0;
    final chunks = await snapshot.readRange(0).toList();
    chunks.single[1] = 0;
    backend.bytes.fillRange(0, 3, 0x78);
    await snapshot.validate();
    expect(await snapshot.read(0, 3), [0x61, 0x62, 0x63]);
    expect(await snapshot.readRange(0).expand((part) => part).toList(), [
      0x61,
      0x62,
      0x63,
    ]);
    expect(backend.reads, 2);
    expect(backend.writes, 0);

    await snapshot.close();
    await snapshot.close();
    expect(snapshot.isClosed, isTrue);
    await expectLater(snapshot.read(0, 1), throwsStateError);
    await expectLater(snapshot.readRange(3).toList(), throwsStateError);
  });

  test(
    'capture copies provider buffers before a provider reuses them',
    () async {
      final backend = _PortableBackend([1, 2, 3, 4]);
      backend.onRead = (_) {
        Stream<List<int>> reused() async* {
          final buffer = Uint8List.fromList([1, 2]);
          yield buffer;
          buffer[0] = 3;
          buffer[1] = 4;
          yield buffer;
        }

        return reused();
      };
      final snapshot = await BinaryComparisonSnapshot.capture(
        backend,
        backend.item,
      );
      addTearDown(snapshot.close);
      expect(await snapshot.read(0, 4), [1, 2, 3, 4]);
      expect(backend.reads, 2);
    },
  );

  test(
    'unknown-size capture measures exact length and obeys a lower byte cap',
    () async {
      final allowed = _PortableBackend([1, 2, 3])..knownSize = false;
      final snapshot = await BinaryComparisonSnapshot.capture(
        allowed,
        allowed.item,
        limits: const BinaryComparisonLimits(maxBytes: 3),
      );
      addTearDown(snapshot.close);
      expect(snapshot.length, 3);
      expect(await snapshot.read(0, 3), [1, 2, 3]);

      final oversized = _PortableBackend(List<int>.filled(513, 0))
        ..knownSize = false;
      await expectLater(
        BinaryComparisonSnapshot.capture(
          oversized,
          oversized.item,
          limits: const BinaryComparisonLimits(maxBytes: 512),
        ),
        throwsA(isA<BinaryComparisonLimitExceeded>()),
      );
      expect(oversized.reads, 1);
      expect(oversized.writes, 0);
    },
  );

  for (final declared in [2, 4]) {
    test('a declared size of $declared cannot admit three bytes', () async {
      final backend = _PortableBackend([1, 2, 3])..declaredSize = declared;
      await expectLater(
        BinaryComparisonSnapshot.capture(backend, backend.item),
        throwsA(isA<BinaryComparisonSourceChanged>()),
      );
      expect(backend.reads, 1);
      expect(backend.writes, 0);
    });
  }

  test(
    'same-length metadata-preserving second-pass changes are refused',
    () async {
      final backend = _PortableBackend([1, 2, 3]);
      backend.onRead = (call) =>
          Stream.value(call == 1 ? [1, 2, 3] : [1, 8, 3]);
      await expectLater(
        BinaryComparisonSnapshot.capture(backend, backend.item),
        throwsA(isA<BinaryComparisonSourceChanged>()),
      );
      expect(backend.reads, 2);
      expect(backend.writes, 0);
    },
  );

  test(
    'unknown-size verification cannot accept a shorter second pass',
    () async {
      final backend = _PortableBackend([1, 2, 3])..knownSize = false;
      backend.onRead = (call) => Stream.value(call == 1 ? [1, 2, 3] : [1, 2]);
      await expectLater(
        BinaryComparisonSnapshot.capture(backend, backend.item),
        throwsA(isA<BinaryComparisonSourceChanged>()),
      );
      expect(backend.reads, 2);
    },
  );

  test('a sparse comparison index navigates an independent exact-range fixture', () async {
    final original = List<int>.generate(64, (i) => i);
    final changed = List<int>.of(original);
    const positions = [
      1,
      4,
      7,
      10,
      13,
      16,
      19,
      22,
      25,
      28,
      31,
      34,
      37,
      40,
      43,
      46,
      49,
      52,
      55,
      58,
    ];
    for (final position in positions) {
      changed[position] = 255 - changed[position];
    }
    changed.addAll([64, 65, 66]);
    const expectedRanges = [
      [1, 2],
      [4, 5],
      [7, 8],
      [10, 11],
      [13, 14],
      [16, 17],
      [19, 20],
      [22, 23],
      [25, 26],
      [28, 29],
      [31, 32],
      [34, 35],
      [37, 38],
      [40, 41],
      [43, 44],
      [46, 47],
      [49, 50],
      [52, 53],
      [55, 56],
      [58, 59],
      [64, 67],
    ];
    final left = _PortableBackend(original), right = _PortableBackend(changed);
    final session = await _open(left, right, maxIndexedRanges: 2);
    addTearDown(session.close);
    expect(session.result.leftBytes, 64);
    expect(session.result.rightBytes, 67);
    expect(session.result.differingBytes, 23);
    expect(session.result.rangeCount, expectedRanges.length);
    expect(session.result.ranges.length, lessThanOrEqualTo(3));

    // Unversioned live bytes now disagree with the captured comparison. Both
    // sparse-index rescans and windows must still reference the original pair.
    left.bytes.fillRange(0, left.bytes.length, 0);
    right.bytes.fillRange(0, right.bytes.length, 0);
    for (final index in [7, 0, 20, 13, 12, 1, 18, 7]) {
      final range = await session.difference(index);
      expect(range.index, index);
      expect([range.start, range.end], expectedRanges[index]);
    }
    final window = await session.window(19, length: 13);
    expect(window.left, original.sublist(19, 32));
    expect(window.right, changed.sublist(19, 32));
    window.left[0] = 255;
    window.right[0] = 255;
    final again = await session.window(19, length: 13);
    expect(again.left, original.sublist(19, 32));
    expect(again.right, changed.sublist(19, 32));
    expect(left.reads, 2);
    expect(right.reads, 2);
    expect(left.writes + right.writes, 0);
  });

  test(
    'ranges join across captured 64 KiB chunks and include unmatched tails',
    () async {
      final left = _PortableBackend(List<int>.filled(65540, 0));
      final rightBytes = List<int>.filled(65542, 0);
      rightBytes.fillRange(65534, 65538, 1);
      rightBytes[65539] = 2;
      final right = _PortableBackend(rightBytes);
      final session = await _open(left, right);
      addTearDown(session.close);
      expect(session.result.differingBytes, 7);
      expect(session.result.ranges.map((range) => [range.start, range.end]), [
        [65534, 65538],
        [65539, 65542],
      ]);
      final window = await session.window(65535, length: 16);
      expect(window.left, List<int>.filled(5, 0));
      expect(window.right, [1, 1, 1, 0, 2, 0, 0]);
    },
  );

  for (final bothEmpty in [false, true]) {
    test(
      'empty captures preserve exact EOF${bothEmpty ? " on both sides" : " against a tail"}',
      () async {
        final left = _PortableBackend([]);
        final right = _PortableBackend(bothEmpty ? [] : [0, 0, 0]);
        final session = await _open(left, right);
        addTearDown(session.close);
        expect(
          session.leftSha256,
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        );
        expect(session.result.equal, bothEmpty);
        expect(session.result.differingBytes, bothEmpty ? 0 : 3);
        expect((await session.window(session.totalBytes)).length, 0);
        if (!bothEmpty) {
          final range = await session.difference(0);
          expect([range.start, range.end], [0, 3]);
          final page = await session.window(2);
          expect(page.left, isEmpty);
          expect(page.right, [0]);
        }
      },
    );
  }

  for (final change in ['identity', 'account', 'version']) {
    test(
      '$change changes permanently invalidate captured navigation',
      () async {
        final left = _PortableBackend([1, 2]);
        final right = _PortableBackend([1, 3])..metadata['version'] = 'one';
        final session = await _open(left, right);
        addTearDown(session.close);
        switch (change) {
          case 'identity':
            right.sourceIdentity = Object();
          case 'account':
            right.current = false;
          case 'version':
            right.metadata['version'] = 'two';
        }
        expect(session.rightFile.metadata!['version'], 'one');
        await expectLater(
          session.difference(0),
          throwsA(isA<BinaryComparisonSourceChanged>()),
        );
        expect(session.isClosed, isTrue);
        await expectLater(session.window(0), throwsStateError);
        expect(left.reads + right.reads, 4);
        expect(left.writes + right.writes, 0);
      },
    );
  }

  test(
    'navigation cancellation closes the session and all future navigation',
    () async {
      final session = await _open(
        _PortableBackend([1, 2]),
        _PortableBackend([1, 3]),
      );
      addTearDown(session.close);
      await expectLater(
        session.window(0, isCancelled: () => true),
        throwsA(isA<BinaryComparisonCancelled>()),
      );
      expect(session.isClosed, isTrue);
      await expectLater(session.difference(0), throwsStateError);
      await session.close();
      await session.close();
    },
  );

  test(
    'cancellation detaches a stalled metadata wait during the second capture',
    () async {
      final left = _PortableBackend([1, 2]);
      final right = _PortableBackend([1, 3]);
      final entered = Completer<void>(), metadata = Completer<FileItem?>();
      right.onStat = (_) {
        if (!entered.isCompleted) entered.complete();
        return metadata.future;
      };
      var cancelled = false;
      final pending = _open(left, right, isCancelled: () => cancelled);
      final checked = expectLater(
        pending.timeout(const Duration(seconds: 3)),
        throwsA(isA<BinaryComparisonCancelled>()),
      );
      await entered.future;
      cancelled = true;
      await checked;
      metadata.completeError(StateError('late portable provider failure'));
      await Future<void>.delayed(Duration.zero);
      expect(left.reads, 2);
      expect(right.reads, 0);
      expect(left.writes + right.writes, 0);
    },
  );

  test(
    'invalid window sizes leave a valid capture usable until explicit close',
    () async {
      final session = await _open(_PortableBackend([1]), _PortableBackend([2]));
      addTearDown(session.close);
      await expectLater(session.window(0, length: 65537), throwsRangeError);
      await expectLater(session.window(-1), throwsRangeError);
      expect(session.isClosed, isFalse);
      expect((await session.window(0)).right, [2]);
      await session.close();
      await expectLater(session.window(0), throwsStateError);
    },
  );
}
