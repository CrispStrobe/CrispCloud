// test/delta_sync_test.dart
//
// Unit tests for DeltaSyncService:
//   - Adler-32 (10+ tests)
//   - SHA-256    (5  tests)
//   - BlockMap computation (10+ tests)
//   - Delta comparison     (15+ tests)
//   - Transfer plan        (8+  tests)
//   - Savings estimation   (5+  tests)
//   - shouldUseDeltaSync   (5+  tests)
//   - Block map persistence (3+ tests)
//
// All file-I/O tests create real temp files so the stream-based reader is
// exercised end-to-end.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/delta_sync_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Write [bytes] to a fresh temp file and return its path.
Future<String> _writeTempFile(List<int> bytes, {String? suffix}) async {
  final dir  = await Directory.systemTemp.createTemp('delta_sync_test_');
  final file = File('${dir.path}/data${suffix ?? '.bin'}');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Build a [List<int>] of [length] bytes all equal to [value].
List<int> _fill(int length, int value) =>
    List<int>.filled(length, value & 0xFF);

/// Build a [List<int>] where byte[i] = i % 256.
List<int> _ramp(int length) =>
    List<int>.generate(length, (i) => i & 0xFF);

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  late DeltaSyncService svc;

  setUp(() {
    svc = DeltaSyncService();
  });

  // =========================================================================
  // Adler-32
  // =========================================================================
  group('Adler-32', () {
    // RFC 1950 §9 example: adler32("Mark Adler") == 0x13070394
    // Widely cited: adler32("Wikipedia") == 0x11E60398
    test('known vector: "Wikipedia"', () {
      final data = 'Wikipedia'.codeUnits;
      expect(svc.adler32(data), equals(0x11E60398));
    });

    test('empty input returns initial value 1 (a=1, b=0 → 0x00000001)', () {
      expect(svc.adler32([]), equals(1));
    });

    test('single byte 0 → (a=1, b=1 → 0x00010001)', () {
      // a = (1+0) % M = 1, b = (0+1) % M = 1  → 0x00010001
      expect(svc.adler32([0]), equals(0x00010001));
    });

    test('single byte 1 → (a=2, b=2 → 0x00020002)', () {
      expect(svc.adler32([1]), equals(0x00020002));
    });

    test('single byte 255', () {
      // a = (1+255)%M = 256, b = 256 → 0x01000100
      expect(svc.adler32([255]), equals(0x01000100));
    });

    test('all-zero 1024 bytes is deterministic', () {
      final h1 = svc.adler32(_fill(1024, 0));
      final h2 = svc.adler32(_fill(1024, 0));
      expect(h1, equals(h2));
    });

    test('all-zero vs all-0xFF produce different hashes', () {
      final hZero = svc.adler32(_fill(1024, 0));
      final hFF   = svc.adler32(_fill(1024, 0xFF));
      expect(hZero, isNot(equals(hFF)));
    });

    test('all-0xFF 1024 bytes is deterministic', () {
      final h1 = svc.adler32(_fill(1024, 0xFF));
      final h2 = svc.adler32(_fill(1024, 0xFF));
      expect(h1, equals(h2));
    });

    test('large block (1 MB) does not overflow or return 0', () {
      final h = svc.adler32(_fill(1024 * 1024, 42));
      expect(h, isNot(equals(0)));
      expect(h, isNot(equals(1)));
    });

    test('different data produces different hash (collision test)', () {
      final a = svc.adler32([1, 2, 3, 4]);
      final b = svc.adler32([4, 3, 2, 1]);
      expect(a, isNot(equals(b)));
    });

    // Rolling update equivalence: sliding one byte should match full recompute
    test('rollingAdler32Update matches full recompute after sliding one byte', () {
      // Initial window: bytes 0..3
      final window1 = [10, 20, 30, 40];
      final hashBefore = svc.adler32(window1);

      // Slide: remove byte 10, add byte 50  →  window = [20, 30, 40, 50]
      final window2    = [20, 30, 40, 50];
      final hashFull   = svc.adler32(window2);
      final hashRolled = svc.rollingAdler32Update(hashBefore, 10, 50, 4);

      expect(hashRolled, equals(hashFull));
    });

    test('rollingAdler32Update is self-consistent over multiple slides', () {
      const blockSize = 8;
      final data = List<int>.generate(20, (i) => (i * 13) & 0xFF);

      // Compute initial hash for window [0..7]
      var rollingHash = svc.adler32(data.sublist(0, blockSize));

      for (int i = 0; i < 12; i++) {
        rollingHash = svc.rollingAdler32Update(
          rollingHash,
          data[i],
          data[i + blockSize],
          blockSize,
        );
        final fullHash = svc.adler32(data.sublist(i + 1, i + 1 + blockSize));
        expect(rollingHash, equals(fullHash),
            reason: 'mismatch at window offset ${i + 1}');
      }
    });
  });

  // =========================================================================
  // SHA-256
  // =========================================================================
  group('SHA-256', () {
    test('empty input matches FIPS 180-4 vector', () {
      expect(
        svc.sha256Hex([]),
        equals(
            'e3b0c44298fc1c149afbf4c8996fb924'
            '27ae41e4649b934ca495991b7852b855'),
      );
    });

    test('"abc" matches known vector', () {
      expect(
        svc.sha256Hex('abc'.codeUnits),
        equals(
            'ba7816bf8f01cfea414140de5dae2223'
            'b00361a396177a9cb410ff61f20015ad'),
      );
    });

    test('different data → different digest', () {
      final h1 = svc.sha256Hex([1, 2, 3]);
      final h2 = svc.sha256Hex([1, 2, 4]);
      expect(h1, isNot(equals(h2)));
    });

    test('result is always 64 hex characters', () {
      for (final data in <List<int>>[[], [0], _fill(4096, 0xAB)]) {
        expect(svc.sha256Hex(data).length, equals(64));
      }
    });

    test('same input always returns same digest (deterministic)', () {
      final data = _ramp(256);
      expect(svc.sha256Hex(data), equals(svc.sha256Hex(data)));
    });
  });

  // =========================================================================
  // Block map computation
  // =========================================================================
  group('BlockMap computation', () {
    const bs = 64 * 1024; // 64 KB — small so tests run fast

    test('single block file produces blockCount=1', () async {
      final path = await _writeTempFile(_fill(bs ~/ 2, 0xAA));
      final map  = await svc.computeBlockMap(path, blockSize: bs);
      expect(map.blockCount, equals(1));
      expect(map.signatures.length, equals(1));
    });

    test('exactly N*blockSize bytes → blockCount == N', () async {
      const n    = 4;
      final path = await _writeTempFile(_fill(n * bs, 0x55), suffix: '.bin');
      final map  = await svc.computeBlockMap(path, blockSize: bs);
      expect(map.blockCount, equals(n));
    });

    test('N*blockSize + 1 bytes → blockCount == N+1', () async {
      const n    = 4;
      final data = _fill(n * bs + 1, 0x33);
      final path = await _writeTempFile(data);
      final map  = await svc.computeBlockMap(path, blockSize: bs);
      expect(map.blockCount, equals(n + 1));
      // Last block has size 1
      expect(map.signatures.last.size, equals(1));
    });

    test('empty file → blockCount=0, no signatures', () async {
      final path = await _writeTempFile([]);
      final map  = await svc.computeBlockMap(path, blockSize: bs);
      expect(map.blockCount, equals(0));
      expect(map.signatures, isEmpty);
      expect(map.totalSize, equals(0));
    });

    test('last block is smaller when file is not a multiple of blockSize', () async {
      final data = _fill(bs + 37, 0x11);
      final path = await _writeTempFile(data);
      final map  = await svc.computeBlockMap(path, blockSize: bs);
      expect(map.blockCount, equals(2));
      expect(map.signatures.first.size, equals(bs));
      expect(map.signatures.last.size,  equals(37));
    });

    test('block offsets are contiguous and start at 0', () async {
      final data = _fill(3 * bs, 0x77);
      final path = await _writeTempFile(data);
      final map  = await svc.computeBlockMap(path, blockSize: bs);
      for (int i = 0; i < map.blockCount; i++) {
        expect(map.signatures[i].offset, equals(i * bs));
        expect(map.signatures[i].blockIndex, equals(i));
      }
    });

    test('identical files produce identical block maps', () async {
      final data  = _ramp(2 * bs);
      final path1 = await _writeTempFile(data);
      final path2 = await _writeTempFile(data);
      final map1  = await svc.computeBlockMap(path1, blockSize: bs);
      final map2  = await svc.computeBlockMap(path2, blockSize: bs);
      for (int i = 0; i < map1.blockCount; i++) {
        expect(map1.signatures[i].weakHash,   equals(map2.signatures[i].weakHash));
        expect(map1.signatures[i].strongHash, equals(map2.signatures[i].strongHash));
      }
    });

    test('different data in different blocks → different signatures', () async {
      final data1 = _fill(2 * bs, 0xAA);
      final data2 = [..._fill(bs, 0xAA), ..._fill(bs, 0xBB)];
      final path1 = await _writeTempFile(data1);
      final path2 = await _writeTempFile(data2);
      final map1  = await svc.computeBlockMap(path1, blockSize: bs);
      final map2  = await svc.computeBlockMap(path2, blockSize: bs);
      // Block 0 is identical
      expect(map1.signatures[0].strongHash, equals(map2.signatures[0].strongHash));
      // Block 1 differs
      expect(map1.signatures[1].strongHash,
          isNot(equals(map2.signatures[1].strongHash)));
    });

    test('progress callback receives correct totals', () async {
      final data = _fill(3 * bs, 0x42);
      final path = await _writeTempFile(data);
      final progressCalls = <(int, int, int)>[];
      await svc.computeBlockMap(
        path,
        blockSize: bs,
        onProgress: (p, t, b) => progressCalls.add((p, t, b)),
      );
      expect(progressCalls.length, equals(3));
      expect(progressCalls.last.$1, equals(3));  // processedBlocks
      expect(progressCalls.last.$2, equals(3));  // totalBlocks
      expect(progressCalls.last.$3, equals(3 * bs)); // processedBytes
    });

    test('BlockMap serialization round-trip', () async {
      final data  = _ramp(2 * bs);
      final path  = await _writeTempFile(data);
      final map   = await svc.computeBlockMap(path, blockSize: bs);
      final json  = map.toJson();
      final map2  = BlockMap.fromJson(json);
      expect(map2.filePath,   equals(map.filePath));
      expect(map2.totalSize,  equals(map.totalSize));
      expect(map2.blockSize,  equals(map.blockSize));
      expect(map2.blockCount, equals(map.blockCount));
      expect(map2.signatures.length, equals(map.signatures.length));
      for (int i = 0; i < map.signatures.length; i++) {
        expect(map2.signatures[i], equals(map.signatures[i]));
      }
    });
  });

  // =========================================================================
  // Delta comparison
  // =========================================================================
  group('Delta comparison (compareBlockMaps)', () {
    const bs = 64 * 1024; // 64 KB

    Future<BlockMap> _mapOf(List<int> data) async {
      final path = await _writeTempFile(data);
      return svc.computeBlockMap(path, blockSize: bs);
    }

    test('identical files → 0 changed blocks', () async {
      final data = _ramp(3 * bs);
      final m1   = await _mapOf(data);
      final m2   = await _mapOf(data);
      final d    = svc.compareBlockMaps(m1, m2);
      expect(d.changedBlocks, isEmpty);
      expect(d.unchangedBlocks, equals(3));
      expect(d.changedBytes, equals(0));
    });

    test('completely different files → all blocks changed', () async {
      final m1 = await _mapOf(_fill(3 * bs, 0xAA));
      final m2 = await _mapOf(_fill(3 * bs, 0xBB));
      final d  = svc.compareBlockMaps(m1, m2);
      expect(d.changedBlocks.length, equals(3));
      expect(d.unchangedBlocks, equals(0));
    });

    test('only middle block changed', () async {
      final base    = [..._fill(bs, 0x11), ..._fill(bs, 0x22), ..._fill(bs, 0x33)];
      final changed = [..._fill(bs, 0x11), ..._fill(bs, 0xFF), ..._fill(bs, 0x33)];
      final m1 = await _mapOf(base);
      final m2 = await _mapOf(changed);
      final d  = svc.compareBlockMaps(m1, m2);
      expect(d.changedBlocks, equals([1]));
    });

    test('only first block changed', () async {
      final base    = [..._fill(bs, 0x10), ..._fill(bs, 0x20)];
      final changed = [..._fill(bs, 0x11), ..._fill(bs, 0x20)];
      final m1 = await _mapOf(base);
      final m2 = await _mapOf(changed);
      final d  = svc.compareBlockMaps(m1, m2);
      expect(d.changedBlocks, equals([0]));
    });

    test('only last block changed', () async {
      final base    = [..._fill(bs, 0x10), ..._fill(bs, 0x20), ..._fill(bs, 0x30)];
      final changed = [..._fill(bs, 0x10), ..._fill(bs, 0x20), ..._fill(bs, 0x31)];
      final m1 = await _mapOf(base);
      final m2 = await _mapOf(changed);
      final d  = svc.compareBlockMaps(m1, m2);
      expect(d.changedBlocks, equals([2]));
    });

    test('file grew (new blocks at end) → new blocks reported as changed', () async {
      final short = _fill(2 * bs, 0xAA);
      final long  = [..._fill(2 * bs, 0xAA), ..._fill(bs, 0xBB)];
      final mShort = await _mapOf(short);
      final mLong  = await _mapOf(long);
      // Compare local=long vs remote=short → block 2 is new → changed
      final d = svc.compareBlockMaps(mLong, mShort);
      expect(d.changedBlocks, contains(2));
    });

    test('file shrank → local has fewer blocks, no crash, no phantom changes', () async {
      final long  = _fill(3 * bs, 0xCC);
      final short = _fill(2 * bs, 0xCC);
      final mLong  = await _mapOf(long);
      final mShort = await _mapOf(short);
      // Compare local=short vs remote=long → first 2 blocks match
      final d = svc.compareBlockMaps(mShort, mLong);
      expect(d.changedBlocks, isEmpty);
    });

    test('empty local file vs non-empty remote → 0 changed local blocks', () async {
      final mEmpty    = await _mapOf([]);
      final mNonEmpty = await _mapOf(_fill(bs, 0xDE));
      final d = svc.compareBlockMaps(mEmpty, mNonEmpty);
      expect(d.changedBlocks, isEmpty);
      expect(d.totalBlocks,   equals(0));
    });

    test('non-empty local vs empty remote → all local blocks changed', () async {
      final mNonEmpty = await _mapOf(_fill(2 * bs, 0xDE));
      final mEmpty    = await _mapOf([]);
      final d = svc.compareBlockMaps(mNonEmpty, mEmpty);
      expect(d.changedBlocks.length, equals(2));
    });

    test('block size boundary: file == N*blockSize, all blocks identical', () async {
      const n   = 5;
      final data = _fill(n * bs, 0x7F);
      final m1  = await _mapOf(data);
      final m2  = await _mapOf(data);
      final d   = svc.compareBlockMaps(m1, m2);
      expect(d.changedBlocks, isEmpty);
    });

    test('block size boundary: file == N*blockSize + 1 byte, last byte changed', () async {
      const n    = 2;
      final base    = [..._fill(n * bs, 0x11), 0x22];
      final changed = [..._fill(n * bs, 0x11), 0x23]; // last byte differs
      final m1 = await _mapOf(base);
      final m2 = await _mapOf(changed);
      final d  = svc.compareBlockMaps(m1, m2);
      expect(d.changedBlocks, equals([n])); // the partial last block
    });

    test('savingsPercent is 100 for identical files', () async {
      final data = _ramp(4 * bs);
      final m1   = await _mapOf(data);
      final m2   = await _mapOf(data);
      final d    = svc.compareBlockMaps(m1, m2);
      expect(d.savingsPercent, equals(100.0));
    });

    test('savingsPercent is 0 for completely different files', () async {
      final m1 = await _mapOf(_fill(2 * bs, 0xAA));
      final m2 = await _mapOf(_fill(2 * bs, 0xBB));
      final d  = svc.compareBlockMaps(m1, m2);
      expect(d.savingsPercent, equals(0.0));
    });

    test('savingsPercent reflects fraction of unchanged bytes', () async {
      // 4 blocks, 1 changed → 75 % savings
      final base = [
        ..._fill(bs, 0x10), ..._fill(bs, 0x20),
        ..._fill(bs, 0x30), ..._fill(bs, 0x40),
      ];
      final changed = [
        ..._fill(bs, 0x10), ..._fill(bs, 0xFF), // block 1 changed
        ..._fill(bs, 0x30), ..._fill(bs, 0x40),
      ];
      final m1 = await _mapOf(base);
      final m2 = await _mapOf(changed);
      final d  = svc.compareBlockMaps(m1, m2);
      expect(d.savingsPercent, closeTo(75.0, 0.01));
    });

    test('totalBlocks equals blockCount of local map', () async {
      final m1 = await _mapOf(_fill(5 * bs, 0xCC));
      final m2 = await _mapOf(_fill(5 * bs, 0xCC));
      final d  = svc.compareBlockMaps(m1, m2);
      expect(d.totalBlocks, equals(5));
    });

    test('changedBlocks + unchangedBlocks == totalBlocks', () async {
      final base    = _fill(4 * bs, 0xAA);
      final altered = [..._fill(2 * bs, 0xAA), ..._fill(2 * bs, 0xBB)];
      final m1 = await _mapOf(base);
      final m2 = await _mapOf(altered);
      final d  = svc.compareBlockMaps(m1, m2);
      expect(d.changedBlocks.length + d.unchangedBlocks, equals(d.totalBlocks));
    });
  });

  // =========================================================================
  // Transfer plan
  // =========================================================================
  group('createTransferPlan', () {
    const bs = 64 * 1024;

    Future<(BlockMap, BlockMap)> _twoMaps(
        List<int> local, List<int> remote) async {
      final lm = await svc.computeBlockMap(
          await _writeTempFile(local), blockSize: bs);
      final rm = await svc.computeBlockMap(
          await _writeTempFile(remote), blockSize: bs);
      return (lm, rm);
    }

    test('upload plan: changed blocks get upload ops, unchanged get skip', () async {
      final base    = [..._fill(bs, 0xAA), ..._fill(bs, 0xBB), ..._fill(bs, 0xCC)];
      final changed = [..._fill(bs, 0xAA), ..._fill(bs, 0xFF), ..._fill(bs, 0xCC)];
      final (lm, rm) = await _twoMaps(changed, base);
      final delta    = svc.compareBlockMaps(lm, rm);
      final plan     = svc.createTransferPlan(delta, TransferDirection.upload, lm);

      expect(plan.operations[0].type, equals(BlockOperationType.skip));
      expect(plan.operations[1].type, equals(BlockOperationType.upload));
      expect(plan.operations[2].type, equals(BlockOperationType.skip));
    });

    test('download plan: changed blocks get download ops, unchanged get skip', () async {
      final base    = [..._fill(bs, 0xAA), ..._fill(bs, 0xBB)];
      final changed = [..._fill(bs, 0xAA), ..._fill(bs, 0xFF)];
      final (lm, rm) = await _twoMaps(changed, base);
      final delta    = svc.compareBlockMaps(lm, rm);
      final plan     = svc.createTransferPlan(delta, TransferDirection.download, lm);

      expect(plan.operations[0].type, equals(BlockOperationType.skip));
      expect(plan.operations[1].type, equals(BlockOperationType.download));
    });

    test('correct offsets in plan', () async {
      final data  = _fill(3 * bs, 0x55);
      final path  = await _writeTempFile(data);
      final lm    = await svc.computeBlockMap(path, blockSize: bs);
      // Compare against itself — all skips, but offsets still correct.
      final delta = svc.compareBlockMaps(lm, lm);
      final plan  = svc.createTransferPlan(delta, TransferDirection.upload, lm);
      for (int i = 0; i < 3; i++) {
        expect(plan.operations[i].offset, equals(i * bs));
      }
    });

    test('transferSize is sum of changed block sizes', () async {
      final base    = [..._fill(bs, 0xAA), ..._fill(bs, 0xBB), ..._fill(bs, 0xCC)];
      final changed = [..._fill(bs, 0xFF), ..._fill(bs, 0xBB), ..._fill(bs, 0xFE)];
      final (lm, rm) = await _twoMaps(changed, base);
      final delta    = svc.compareBlockMaps(lm, rm);
      final plan     = svc.createTransferPlan(delta, TransferDirection.upload, lm);

      // Blocks 0 and 2 changed → transferSize = 2 * bs
      expect(plan.transferSize, equals(2 * bs));
    });

    test('all-unchanged plan has transferSize 0', () async {
      final data = _fill(2 * bs, 0x77);
      final path = await _writeTempFile(data);
      final lm   = await svc.computeBlockMap(path, blockSize: bs);
      final d    = svc.compareBlockMaps(lm, lm);
      final plan = svc.createTransferPlan(d, TransferDirection.upload, lm);
      expect(plan.transferSize, equals(0));
    });

    test('plan savingsPercent == 100 when nothing changed', () async {
      final data = _fill(4 * bs, 0x42);
      final path = await _writeTempFile(data);
      final lm   = await svc.computeBlockMap(path, blockSize: bs);
      final d    = svc.compareBlockMaps(lm, lm);
      final plan = svc.createTransferPlan(d, TransferDirection.upload, lm);
      expect(plan.savingsPercent, equals(100.0));
    });

    test('plan savingsPercent == 0 when everything changed', () async {
      final (lm, rm) = await _twoMaps(
        _fill(2 * bs, 0xAA), _fill(2 * bs, 0xBB));
      final d    = svc.compareBlockMaps(lm, rm);
      final plan = svc.createTransferPlan(d, TransferDirection.upload, lm);
      expect(plan.savingsPercent, equals(0.0));
    });

    test('changedBlockIndices matches changed blocks from delta', () async {
      final base    = [..._fill(bs, 0x11), ..._fill(bs, 0x22), ..._fill(bs, 0x33)];
      final changed = [..._fill(bs, 0xFF), ..._fill(bs, 0x22), ..._fill(bs, 0xFE)];
      final (lm, rm) = await _twoMaps(changed, base);
      final delta    = svc.compareBlockMaps(lm, rm);
      final plan     = svc.createTransferPlan(delta, TransferDirection.upload, lm);
      expect(
        plan.changedBlockIndices.toSet(),
        equals(delta.changedBlocks.toSet()),
      );
    });

    test('plan operation count equals blockCount of local map', () async {
      final data = _fill(5 * bs, 0xAB);
      final path = await _writeTempFile(data);
      final lm   = await svc.computeBlockMap(path, blockSize: bs);
      final d    = svc.compareBlockMaps(lm, lm);
      final plan = svc.createTransferPlan(d, TransferDirection.upload, lm);
      expect(plan.operations.length, equals(lm.blockCount));
    });
  });

  // =========================================================================
  // applyDelta (upload + download round-trip)
  // =========================================================================
  group('applyDelta', () {
    const bs = 64 * 1024;

    test('upload: remoteWriteBlock receives only changed block data', () async {
      final original = [..._fill(bs, 0xAA), ..._fill(bs, 0xBB)];
      final updated  = [..._fill(bs, 0xAA), ..._fill(bs, 0xFF)]; // block 1 changed

      final localPath = await _writeTempFile(updated);
      final origPath  = await _writeTempFile(original);

      final lm    = await svc.computeBlockMap(localPath, blockSize: bs);
      final rm    = await svc.computeBlockMap(origPath, blockSize: bs);
      final delta = svc.compareBlockMaps(lm, rm);
      final plan  = svc.createTransferPlan(delta, TransferDirection.upload, lm);

      final uploaded = <int, List<int>>{};
      await svc.applyDelta(
        plan,
        localPath,
        remoteWriteBlock: (idx, offset, data) async {
          uploaded[idx] = data;
        },
      );

      expect(uploaded.keys, equals({1}));
      expect(uploaded[1], equals(_fill(bs, 0xFF)));
    });

    test('download: changed blocks are written to localPath', () async {
      final original = [..._fill(bs, 0x11), ..._fill(bs, 0x22)];
      final remote   = [..._fill(bs, 0x11), ..._fill(bs, 0x33)]; // block 1 differs

      // local file starts as "original"; we'll patch it with the remote block
      final localPath   = await _writeTempFile(original);
      final remotePath  = await _writeTempFile(remote);

      final lm    = await svc.computeBlockMap(localPath, blockSize: bs);
      final rm    = await svc.computeBlockMap(remotePath, blockSize: bs);
      // direction: we want to download remote → local
      final delta = svc.compareBlockMaps(rm, lm); // local=rm, remote=lm for comparison
      final plan  = svc.createTransferPlan(delta, TransferDirection.download, rm);

      final remoteData = await File(remotePath).readAsBytes();

      await svc.applyDelta(
        plan,
        localPath,
        remoteReadBlock: (idx, offset, size) async {
          return remoteData.sublist(offset, offset + size);
        },
      );

      final result = await File(localPath).readAsBytes();
      // Block 1 should now be 0x33
      expect(result.sublist(bs, 2 * bs), equals(_fill(bs, 0x33)));
    });

    test('download: unchanged blocks are preserved in local file', () async {
      // 3 blocks: only block 1 differs between local and remote
      final local  = [..._fill(bs, 0xAA), ..._fill(bs, 0xBB), ..._fill(bs, 0xCC)];
      final remote = [..._fill(bs, 0xAA), ..._fill(bs, 0xFF), ..._fill(bs, 0xCC)];

      final localPath  = await _writeTempFile(local);
      final remotePath = await _writeTempFile(remote);

      final lm    = await svc.computeBlockMap(localPath, blockSize: bs);
      final rm    = await svc.computeBlockMap(remotePath, blockSize: bs);
      final delta = svc.compareBlockMaps(rm, lm);
      final plan  = svc.createTransferPlan(delta, TransferDirection.download, rm);

      final remoteData = await File(remotePath).readAsBytes();

      await svc.applyDelta(
        plan,
        localPath,
        remoteReadBlock: (idx, offset, size) async {
          return remoteData.sublist(offset, offset + size);
        },
      );

      final result = await File(localPath).readAsBytes();
      // Block 0 preserved (unchanged)
      expect(result.sublist(0, bs), equals(_fill(bs, 0xAA)),
          reason: 'Block 0 should be preserved');
      // Block 1 updated
      expect(result.sublist(bs, 2 * bs), equals(_fill(bs, 0xFF)),
          reason: 'Block 1 should be updated');
      // Block 2 preserved (unchanged)
      expect(result.sublist(2 * bs, 3 * bs), equals(_fill(bs, 0xCC)),
          reason: 'Block 2 should be preserved');
    });

    test('download: only first block changed, rest preserved', () async {
      final local  = [..._fill(bs, 0x11), ..._fill(bs, 0x22), ..._fill(bs, 0x33), ..._fill(bs, 0x44)];
      final remote = [..._fill(bs, 0xFF), ..._fill(bs, 0x22), ..._fill(bs, 0x33), ..._fill(bs, 0x44)];

      final localPath  = await _writeTempFile(local);
      final remotePath = await _writeTempFile(remote);
      final lm = await svc.computeBlockMap(localPath, blockSize: bs);
      final rm = await svc.computeBlockMap(remotePath, blockSize: bs);
      final delta = svc.compareBlockMaps(rm, lm);
      final plan  = svc.createTransferPlan(delta, TransferDirection.download, rm);
      final remoteData = await File(remotePath).readAsBytes();

      await svc.applyDelta(plan, localPath,
        remoteReadBlock: (idx, offset, size) async => remoteData.sublist(offset, offset + size));

      final result = await File(localPath).readAsBytes();
      expect(result.sublist(0, bs), equals(_fill(bs, 0xFF)), reason: 'Block 0 updated');
      expect(result.sublist(bs, 2 * bs), equals(_fill(bs, 0x22)), reason: 'Block 1 preserved');
      expect(result.sublist(2 * bs, 3 * bs), equals(_fill(bs, 0x33)), reason: 'Block 2 preserved');
      expect(result.sublist(3 * bs, 4 * bs), equals(_fill(bs, 0x44)), reason: 'Block 3 preserved');
    });

    test('download: only last block changed, rest preserved', () async {
      final local  = [..._fill(bs, 0x11), ..._fill(bs, 0x22), ..._fill(bs, 0x33)];
      final remote = [..._fill(bs, 0x11), ..._fill(bs, 0x22), ..._fill(bs, 0xEE)];

      final localPath  = await _writeTempFile(local);
      final remotePath = await _writeTempFile(remote);
      final lm = await svc.computeBlockMap(localPath, blockSize: bs);
      final rm = await svc.computeBlockMap(remotePath, blockSize: bs);
      final delta = svc.compareBlockMaps(rm, lm);
      final plan  = svc.createTransferPlan(delta, TransferDirection.download, rm);
      final remoteData = await File(remotePath).readAsBytes();

      await svc.applyDelta(plan, localPath,
        remoteReadBlock: (idx, offset, size) async => remoteData.sublist(offset, offset + size));

      final result = await File(localPath).readAsBytes();
      expect(result.sublist(0, bs), equals(_fill(bs, 0x11)), reason: 'Block 0 preserved');
      expect(result.sublist(bs, 2 * bs), equals(_fill(bs, 0x22)), reason: 'Block 1 preserved');
      expect(result.sublist(2 * bs, 3 * bs), equals(_fill(bs, 0xEE)), reason: 'Block 2 updated');
    });

    test('download: multiple non-contiguous blocks changed', () async {
      final local  = [..._fill(bs, 0x11), ..._fill(bs, 0x22), ..._fill(bs, 0x33), ..._fill(bs, 0x44), ..._fill(bs, 0x55)];
      final remote = [..._fill(bs, 0xAA), ..._fill(bs, 0x22), ..._fill(bs, 0xCC), ..._fill(bs, 0x44), ..._fill(bs, 0xEE)];

      final localPath  = await _writeTempFile(local);
      final remotePath = await _writeTempFile(remote);
      final lm = await svc.computeBlockMap(localPath, blockSize: bs);
      final rm = await svc.computeBlockMap(remotePath, blockSize: bs);
      final delta = svc.compareBlockMaps(rm, lm);
      expect(delta.changedBlocks.toSet(), equals({0, 2, 4}));

      final plan = svc.createTransferPlan(delta, TransferDirection.download, rm);
      final remoteData = await File(remotePath).readAsBytes();

      await svc.applyDelta(plan, localPath,
        remoteReadBlock: (idx, offset, size) async => remoteData.sublist(offset, offset + size));

      final result = await File(localPath).readAsBytes();
      expect(result.sublist(0, bs), equals(_fill(bs, 0xAA)), reason: 'Block 0 updated');
      expect(result.sublist(bs, 2 * bs), equals(_fill(bs, 0x22)), reason: 'Block 1 preserved');
      expect(result.sublist(2 * bs, 3 * bs), equals(_fill(bs, 0xCC)), reason: 'Block 2 updated');
      expect(result.sublist(3 * bs, 4 * bs), equals(_fill(bs, 0x44)), reason: 'Block 3 preserved');
      expect(result.sublist(4 * bs, 5 * bs), equals(_fill(bs, 0xEE)), reason: 'Block 4 updated');
    });

    test('all-skip plan calls onProgress for every block', () async {
      final data = _fill(3 * bs, 0x42);
      final path = await _writeTempFile(data);
      final lm   = await svc.computeBlockMap(path, blockSize: bs);
      final d    = svc.compareBlockMaps(lm, lm);
      final plan = svc.createTransferPlan(d, TransferDirection.upload, lm);

      final calls = <int>[];
      await svc.applyDelta(
        plan,
        path,
        onProgress: (p, t, b) => calls.add(p),
      );
      expect(calls, equals([1, 2, 3]));
    });
  });

  // =========================================================================
  // Savings estimation
  // =========================================================================
  group('estimateSavings', () {
    const bs = 64 * 1024;

    test('identical file → savings == 100 %', () async {
      final data = _ramp(4 * bs);
      final path = await _writeTempFile(data);
      final rm   = await svc.computeBlockMap(path, blockSize: bs);
      final pct  = await svc.estimateSavings(path, rm);
      expect(pct, equals(100.0));
    });

    test('completely different file → savings == 0 %', () async {
      final rpath = await _writeTempFile(_fill(2 * bs, 0xBB));
      final lpath = await _writeTempFile(_fill(2 * bs, 0xAA));
      final rm    = await svc.computeBlockMap(rpath, blockSize: bs);
      final pct   = await svc.estimateSavings(lpath, rm);
      expect(pct, equals(0.0));
    });

    test('1 of 20 blocks changed → ~95 % savings', () async {
      final data = _fill(20 * bs, 0x55);
      final rpath = await _writeTempFile(data);
      final rm    = await svc.computeBlockMap(rpath, blockSize: bs);

      // Change block 10
      final mutated = List<int>.from(data);
      for (int i = 10 * bs; i < 11 * bs; i++) mutated[i] = 0xAA;
      final lpath = await _writeTempFile(mutated);

      final pct = await svc.estimateSavings(lpath, rm);
      expect(pct, closeTo(95.0, 0.1));
    });

    test('empty local file vs non-empty remote → 100 % savings (0 local bytes)', () async {
      final rpath = await _writeTempFile(_fill(2 * bs, 0xCC));
      final lpath = await _writeTempFile([]);
      final rm    = await svc.computeBlockMap(rpath, blockSize: bs);
      final pct   = await svc.estimateSavings(lpath, rm);
      // Local is empty → 0 bytes to transfer → 100 % savings from local POV
      expect(pct, equals(100.0));
    });

    test('uses blockSize from remoteBlockMap when scanning local', () async {
      final data  = _fill(4 * bs, 0xDD);
      final rpath = await _writeTempFile(data);
      final rm    = await svc.computeBlockMap(rpath, blockSize: bs);
      // Slight mutation
      final mutated = List<int>.from(data)..[0] = 0xEE;
      final lpath = await _writeTempFile(mutated);

      // Should not throw and should show < 100 % savings
      final pct = await svc.estimateSavings(lpath, rm);
      expect(pct, lessThan(100.0));
    });
  });

  // =========================================================================
  // shouldUseDeltaSync
  // =========================================================================
  group('shouldUseDeltaSync', () {
    const tenMB = 10 * 1024 * 1024;

    test('returns false for file smaller than threshold', () {
      expect(svc.shouldUseDeltaSync(1024), isFalse);
    });

    test('returns false for file just under threshold (tenMB - 1)', () {
      expect(svc.shouldUseDeltaSync(tenMB - 1), isFalse);
    });

    test('returns true for file exactly at threshold (tenMB)', () {
      expect(svc.shouldUseDeltaSync(tenMB), isTrue);
    });

    test('returns true for file above threshold', () {
      expect(svc.shouldUseDeltaSync(100 * 1024 * 1024), isTrue);
    });

    test('custom minSize threshold is respected (1 MB)', () {
      const oneMB = 1024 * 1024;
      expect(svc.shouldUseDeltaSync(oneMB - 1, minSize: oneMB), isFalse);
      expect(svc.shouldUseDeltaSync(oneMB,     minSize: oneMB), isTrue);
    });
  });

  // =========================================================================
  // Block map persistence (save / load)
  // =========================================================================
  group('Block map persistence', () {
    const bs = 64 * 1024;

    test('save and load round-trip preserves all fields', () async {
      final data    = _ramp(3 * bs);
      final path    = await _writeTempFile(data);
      final map     = await svc.computeBlockMap(path, blockSize: bs);
      final cacheDir = (await Directory.systemTemp.createTemp('bm_cache_')).path;
      final cachePath = '$cacheDir/test_blockmap.json';

      await svc.saveBlockMap(map, cachePath);
      final loaded = await svc.loadBlockMap(cachePath);

      expect(loaded, isNotNull);
      expect(loaded!.filePath,   equals(map.filePath));
      expect(loaded.totalSize,   equals(map.totalSize));
      expect(loaded.blockSize,   equals(map.blockSize));
      expect(loaded.blockCount,  equals(map.blockCount));
      expect(loaded.signatures.length, equals(map.signatures.length));
      for (int i = 0; i < map.signatures.length; i++) {
        expect(loaded.signatures[i], equals(map.signatures[i]));
      }
    });

    test('loadBlockMap returns null for missing file', () async {
      final result = await svc.loadBlockMap('/tmp/does_not_exist_xyz.json');
      expect(result, isNull);
    });

    test('loadBlockMap returns null for corrupted JSON', () async {
      final dir  = await Directory.systemTemp.createTemp('bm_corrupt_');
      final path = '${dir.path}/corrupt.json';
      await File(path).writeAsString('not valid json {{{', flush: true);
      final result = await svc.loadBlockMap(path);
      expect(result, isNull);
    });
  });

  // =========================================================================
  // blockMapCachePath helper
  // =========================================================================
  group('blockMapCachePath', () {
    test('returns path ending in .json', () {
      final p = svc.blockMapCachePath('/cache', '/files/big.vcf', 'dropbox');
      expect(p, endsWith('.json'));
    });

    test('different provider → different path', () {
      final p1 = svc.blockMapCachePath('/cache', '/file.bin', 'dropbox');
      final p2 = svc.blockMapCachePath('/cache', '/file.bin', 'gdrive');
      expect(p1, isNot(equals(p2)));
    });

    test('different filePath → different path', () {
      final p1 = svc.blockMapCachePath('/cache', '/a.bin', 'dropbox');
      final p2 = svc.blockMapCachePath('/cache', '/b.bin', 'dropbox');
      expect(p1, isNot(equals(p2)));
    });

    test('same inputs → same path (deterministic)', () {
      final p1 = svc.blockMapCachePath('/cache', '/file.bin', 'onedrive');
      final p2 = svc.blockMapCachePath('/cache', '/file.bin', 'onedrive');
      expect(p1, equals(p2));
    });
  });

  // =========================================================================
  // BlockSignature model
  // =========================================================================
  group('BlockSignature', () {
    test('equality: same values → equal', () {
      const s1 = BlockSignature(
          blockIndex: 0, offset: 0, size: 4096, weakHash: 1234, strongHash: 'abc');
      const s2 = BlockSignature(
          blockIndex: 0, offset: 0, size: 4096, weakHash: 1234, strongHash: 'abc');
      expect(s1, equals(s2));
    });

    test('equality: different weakHash → not equal', () {
      const s1 = BlockSignature(
          blockIndex: 0, offset: 0, size: 4096, weakHash: 1, strongHash: 'abc');
      const s2 = BlockSignature(
          blockIndex: 0, offset: 0, size: 4096, weakHash: 2, strongHash: 'abc');
      expect(s1, isNot(equals(s2)));
    });

    test('JSON round-trip', () {
      const original = BlockSignature(
          blockIndex: 7, offset: 65536, size: 4096, weakHash: 999, strongHash: 'deadbeef');
      final decoded = BlockSignature.fromJson(original.toJson());
      expect(decoded, equals(original));
    });
  });
}
