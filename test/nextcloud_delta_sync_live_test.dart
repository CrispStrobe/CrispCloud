// test/nextcloud_delta_sync_live_test.dart
//
// Live integration tests for block-level delta sync against Nextcloud 33.
//
// Prerequisites (run once before tests):
//   dd if=/dev/urandom of=/tmp/delta_test_12m.bin bs=1M count=12
//   curl -u admin:admin2026 -T /tmp/delta_test_12m.bin http://localhost:8888/remote.php/dav/files/admin/delta-live-bm.bin
//   curl -u admin:admin2026 -T /tmp/delta_test_12m.bin http://localhost:8888/remote.php/dav/files/admin/delta-live-wr.bin
//   python3 -c "import sys; sys.stdout.buffer.write(b'\x00'*4*1024*1024 + b'\xff'*4*1024*1024)" > /tmp/delta_test_range.bin
//   curl -u admin:admin2026 -T /tmp/delta_test_range.bin http://localhost:8888/remote.php/dav/files/admin/delta-live-range.bin
//
// Run:  flutter test test/nextcloud_delta_sync_live_test.dart --run-skipped
@Tags(['live'])

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/delta_sync_service.dart';

const _ncUrl = 'http://localhost:8888';
const _ncUser = 'admin';
const _ncPass = 'admin2026';
const _ncAppBase = '$_ncUrl/index.php/apps/crispcloud_delta';

// ---------------------------------------------------------------------------
// curl-based HTTP (bypasses Flutter test HttpClient override)
// ---------------------------------------------------------------------------

Future<(int, String)> _curl(String method, String url, {
  Map<String, String>? headers, List<int>? body,
}) async {
  final args = ['-s', '-X', method, '-u', '$_ncUser:$_ncPass', '-w', '\n__S__%{http_code}'];
  headers?.forEach((k, v) => args.addAll(['-H', '$k: $v']));
  String? tmp;
  if (body != null) {
    final f = File('/tmp/_curl_${DateTime.now().microsecondsSinceEpoch}.bin');
    await f.writeAsBytes(body, flush: true);
    tmp = f.path;
    args.addAll(['--data-binary', '@$tmp']);
  }
  args.add(url);
  final r = await Process.run('curl', args);
  if (tmp != null) try { File(tmp).deleteSync(); } catch (_) {}
  final out = r.stdout.toString();
  final m = RegExp(r'__S__(\d+)$').firstMatch(out);
  return (int.tryParse(m?.group(1) ?? '') ?? 0, out.substring(0, m?.start ?? out.length));
}

Future<Uint8List> _curlGetBytes(String url, {Map<String, String>? headers}) async {
  final tmp = File('/tmp/_curl_dl_${DateTime.now().microsecondsSinceEpoch}.bin');
  final args = ['-s', '-u', '$_ncUser:$_ncPass', '-o', tmp.path];
  headers?.forEach((k, v) => args.addAll(['-H', '$k: $v']));
  args.add(url);
  await Process.run('curl', args);
  final bytes = await tmp.readAsBytes();
  try { await tmp.delete(); } catch (_) {}
  return bytes;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Status', () {
    test('app responds with version info', () async {
      final (code, body) = await _curl('GET', '$_ncAppBase/api/status');
      expect(code, equals(200));
      final d = json.decode(body);
      expect(d['app'], equals('crispcloud_delta'));
      expect(d['version'], equals('0.1.0'));
      expect(d['blockSize'], equals(4 * 1024 * 1024));
    });
  });

  group('Block map — pre-uploaded delta-live-bm.bin', () {
    test('returns 3 blocks for 12 MB file', () async {
      final (code, body) = await _curl('GET', '$_ncAppBase/api/blockmap/delta-live-bm.bin');
      expect(code, equals(200));
      final d = json.decode(body);
      expect(d['totalSize'], equals(12 * 1024 * 1024));
      expect(d['blockCount'], equals(3));
      expect(d['blockSize'], equals(4 * 1024 * 1024));
      expect(d['etag'], isNotEmpty);
      final sigs = d['signatures'] as List;
      expect(sigs.length, equals(3));
      for (final s in sigs) {
        expect(s['size'], equals(4 * 1024 * 1024));
        expect((s['strongHash'] as String).length, equals(64));
      }
    });

    test('hashes match Dart DeltaSyncService', () async {
      final fileData = await _curlGetBytes(
          '$_ncUrl/remote.php/dav/files/$_ncUser/delta-live-bm.bin');
      final tmp = File('/tmp/_delta_verify.bin');
      await tmp.writeAsBytes(fileData);
      final svc = DeltaSyncService();
      final localMap = await svc.computeBlockMap(tmp.path);

      final (_, body) = await _curl('GET', '$_ncAppBase/api/blockmap/delta-live-bm.bin');
      final serverMap = BlockMap.fromJson(json.decode(body));

      expect(localMap.blockCount, equals(serverMap.blockCount));
      for (int i = 0; i < localMap.blockCount; i++) {
        expect(localMap.signatures[i].weakHash,
            equals(serverMap.signatures[i].weakHash),
            reason: 'Block $i weak hash mismatch');
        expect(localMap.signatures[i].strongHash,
            equals(serverMap.signatures[i].strongHash),
            reason: 'Block $i strong hash mismatch');
      }
      await tmp.delete();
    });

    test('returns 404 for non-existent file', () async {
      final (code, _) = await _curl('GET', '$_ncAppBase/api/blockmap/no-such-file.bin');
      expect(code, equals(404));
    });

    test('cached response matches first response', () async {
      final (_, b1) = await _curl('GET', '$_ncAppBase/api/blockmap/delta-live-bm.bin');
      final (_, b2) = await _curl('GET', '$_ncAppBase/api/blockmap/delta-live-bm.bin');
      final d1 = json.decode(b1);
      final d2 = json.decode(b2);
      // Same hashes
      expect(d1['signatures'][0]['strongHash'], equals(d2['signatures'][0]['strongHash']));
      expect(d1['etag'], equals(d2['etag']));
    });
  });

  group('Block write — pre-uploaded delta-live-wr.bin', () {
    test('writing block 1 changes only block 1 hash', () async {
      // Get hashes before
      final (_, bmBefore) = await _curl('GET', '$_ncAppBase/api/blockmap/delta-live-wr.bin');
      final before = (json.decode(bmBefore)['signatures'] as List)
          .map((s) => s['strongHash'] as String).toList();

      // Write data seeded with current timestamp so it's always different
      final seed = DateTime.now().microsecondsSinceEpoch;
      final patch = List.generate(4 * 1024 * 1024, (i) => (i * 7 + seed) & 0xFF);
      final (wCode, wBody) = await _curl('POST',
        '$_ncAppBase/api/blocks/delta-live-wr.bin?offset=4194304&size=4194304',
        headers: {'Content-Type': 'application/octet-stream', 'OCS-APIREQUEST': 'true'},
        body: patch,
      );
      expect(json.decode(wBody)['status'], equals('ok'));

      // Finalize
      final (_, fBody) = await _curl('POST',
        '$_ncAppBase/api/finalize/delta-live-wr.bin',
        headers: {'OCS-APIREQUEST': 'true'},
      );
      expect(json.decode(fBody)['status'], equals('finalized'));

      // Get hashes after
      final (_, bmAfter) = await _curl('GET', '$_ncAppBase/api/blockmap/delta-live-wr.bin');
      final after = (json.decode(bmAfter)['signatures'] as List)
          .map((s) => s['strongHash'] as String).toList();

      expect(after[0], equals(before[0]), reason: 'Block 0 unchanged');
      expect(after[1], isNot(equals(before[1])), reason: 'Block 1 changed');
      expect(after[2], equals(before[2]), reason: 'Block 2 unchanged');
    });
  });

  group('Range GET — pre-uploaded delta-live-range.bin', () {
    test('block 0 bytes are 0x00', () async {
      final bytes = await _curlGetBytes(
        '$_ncUrl/remote.php/dav/files/$_ncUser/delta-live-range.bin',
        headers: {'Range': 'bytes=0-99'},
      );
      expect(bytes.length, equals(100));
      expect(bytes.every((b) => b == 0x00), isTrue);
    });

    test('block 1 bytes are 0xFF', () async {
      final bytes = await _curlGetBytes(
        '$_ncUrl/remote.php/dav/files/$_ncUser/delta-live-range.bin',
        headers: {'Range': 'bytes=4194304-4194403'},
      );
      expect(bytes.length, equals(100));
      expect(bytes.every((b) => b == 0xFF), isTrue);
    });
  });

  // ===========================================================================
  // Error handling
  // ===========================================================================
  group('Error handling', () {
    test('blockmap returns 404 for directory path', () async {
      // Create a test directory via WebDAV
      await _curl('MKCOL', '$_ncUrl/remote.php/dav/files/$_ncUser/delta-test-dir/');
      final (code, body) = await _curl('GET', '$_ncAppBase/api/blockmap/delta-test-dir');
      expect(code, equals(404));
      final d = json.decode(body);
      expect(d['error'], isNotEmpty);
      // Cleanup
      await _curl('DELETE', '$_ncUrl/remote.php/dav/files/$_ncUser/delta-test-dir/');
    });

    test('finalize returns error for non-existent file', () async {
      final (code, body) = await _curl('POST',
        '$_ncAppBase/api/finalize/no-such-file-xyz.bin',
        headers: {'OCS-APIREQUEST': 'true'},
      );
      expect(code, equals(500));
      final d = json.decode(body);
      expect(d['error'], isNotEmpty);
    });

    test('block write returns error for empty body', () async {
      final (code, body) = await _curl('POST',
        '$_ncAppBase/api/blocks/delta-live-bm.bin?offset=0&size=4096',
        headers: {'Content-Type': 'application/octet-stream', 'OCS-APIREQUEST': 'true'},
      );
      expect(code, equals(400));
      final d = json.decode(body);
      expect(d['error'], contains('Empty'));
    });
  });

  // ===========================================================================
  // Full delta sync round-trip
  // ===========================================================================
  group('Full delta sync round-trip', () {
    test('upload → modify → upload cycle with block-level verification', () async {
      // Step 1: Upload a fresh 12 MB test file via WebDAV
      final testFile = 'delta-live-roundtrip.bin';
      final originalData = List<int>.generate(
          12 * 1024 * 1024, (i) => (i * 3 + 7) & 0xFF);
      final (upCode, _) = await _curl('PUT',
        '$_ncUrl/remote.php/dav/files/$_ncUser/$testFile',
        headers: {'Content-Type': 'application/octet-stream'},
        body: originalData,
      );
      expect(upCode, anyOf(equals(201), equals(204)));

      // Step 2: Get initial block map
      final (bmCode1, bmBody1) = await _curl('GET', '$_ncAppBase/api/blockmap/$testFile');
      expect(bmCode1, equals(200));
      final bm1 = json.decode(bmBody1);
      expect(bm1['blockCount'], equals(3));
      final sigs1 = bm1['signatures'] as List;

      // Step 3: Verify hashes match Dart-computed hashes
      final svc = DeltaSyncService();
      final tmpFile = File('/tmp/_delta_roundtrip.bin');
      await tmpFile.writeAsBytes(originalData);
      final localMap = await svc.computeBlockMap(tmpFile.path);
      for (int i = 0; i < 3; i++) {
        expect(sigs1[i]['weakHash'], equals(localMap.signatures[i].weakHash),
            reason: 'Block $i weak hash should match');
        expect(sigs1[i]['strongHash'], equals(localMap.signatures[i].strongHash),
            reason: 'Block $i strong hash should match');
      }

      // Step 4: Modify block 0 locally and compute new block map
      final modifiedData = List<int>.from(originalData);
      for (int i = 0; i < 4 * 1024 * 1024; i++) {
        modifiedData[i] = 0xDE;
      }
      final modFile = File('/tmp/_delta_roundtrip_mod.bin');
      await modFile.writeAsBytes(modifiedData);
      final modMap = await svc.computeBlockMap(modFile.path);

      // Step 5: Compare — only block 0 should differ
      final serverMap = BlockMap.fromJson(bm1);
      final delta = svc.compareBlockMaps(modMap, serverMap);
      expect(delta.changedBlocks, equals([0]));
      expect(delta.savingsPercent, closeTo(66.7, 0.1));

      // Step 6: Upload only the changed block via API
      final changedBlock = modifiedData.sublist(0, 4 * 1024 * 1024);
      final (wCode, wBody) = await _curl('POST',
        '$_ncAppBase/api/blocks/$testFile?offset=0&size=${4 * 1024 * 1024}',
        headers: {'Content-Type': 'application/octet-stream', 'OCS-APIREQUEST': 'true'},
        body: changedBlock,
      );
      expect(json.decode(wBody)['status'], equals('ok'));

      // Step 7: Finalize
      final (fCode, fBody) = await _curl('POST',
        '$_ncAppBase/api/finalize/$testFile',
        headers: {'OCS-APIREQUEST': 'true'},
      );
      expect(json.decode(fBody)['status'], equals('finalized'));

      // Step 8: Verify updated block map
      final (bmCode2, bmBody2) = await _curl('GET', '$_ncAppBase/api/blockmap/$testFile');
      expect(bmCode2, equals(200));
      final bm2 = json.decode(bmBody2);
      final sigs2 = bm2['signatures'] as List;
      // Block 0 should have new hash
      expect(sigs2[0]['strongHash'], isNot(equals(sigs1[0]['strongHash'])),
          reason: 'Block 0 hash should differ after update');
      // Blocks 1 and 2 should be unchanged
      expect(sigs2[1]['strongHash'], equals(sigs1[1]['strongHash']),
          reason: 'Block 1 should be unchanged');
      expect(sigs2[2]['strongHash'], equals(sigs1[2]['strongHash']),
          reason: 'Block 2 should be unchanged');

      // Step 9: Verify block 0 hash matches the modified data
      expect(sigs2[0]['strongHash'], equals(modMap.signatures[0].strongHash),
          reason: 'Block 0 server hash should match locally computed hash');

      // Cleanup
      await _curl('DELETE', '$_ncUrl/remote.php/dav/files/$_ncUser/$testFile');
      await tmpFile.delete();
      await modFile.delete();
    });

    test('ETag changes after block write and finalize', () async {
      final (_, bmBefore) = await _curl('GET', '$_ncAppBase/api/blockmap/delta-live-bm.bin');
      final etagBefore = json.decode(bmBefore)['etag'] as String;
      expect(etagBefore, isNotEmpty);

      // Write a block (will change file content)
      final patch = List<int>.generate(4 * 1024 * 1024, (i) => (i * 11) & 0xFF);
      await _curl('POST',
        '$_ncAppBase/api/blocks/delta-live-bm.bin?offset=0&size=4194304',
        headers: {'Content-Type': 'application/octet-stream', 'OCS-APIREQUEST': 'true'},
        body: patch,
      );
      await _curl('POST',
        '$_ncAppBase/api/finalize/delta-live-bm.bin',
        headers: {'OCS-APIREQUEST': 'true'},
      );

      final (_, bmAfter) = await _curl('GET', '$_ncAppBase/api/blockmap/delta-live-bm.bin');
      final etagAfter = json.decode(bmAfter)['etag'] as String;
      expect(etagAfter, isNotEmpty);
      expect(etagAfter, isNot(equals(etagBefore)),
          reason: 'ETag should change after block write + finalize');
    });

    test('block write with size mismatch is rejected', () async {
      // Send 100 bytes but claim size=200
      final data = List<int>.filled(100, 0x42);
      final (code, body) = await _curl('POST',
        '$_ncAppBase/api/blocks/delta-live-bm.bin?offset=0&size=200',
        headers: {'Content-Type': 'application/octet-stream', 'OCS-APIREQUEST': 'true'},
        body: data,
      );
      expect(code, equals(400));
      final d = json.decode(body);
      expect(d['error'], contains('mismatch'));
    });

    test('block write at non-zero offset preserves preceding data', () async {
      // Upload a fresh test file
      final testFile = 'delta-live-offset-test.bin';
      final data = [...List.filled(4 * 1024 * 1024, 0xAA), ...List.filled(4 * 1024 * 1024, 0xBB)];
      await _curl('PUT',
        '$_ncUrl/remote.php/dav/files/$_ncUser/$testFile',
        headers: {'Content-Type': 'application/octet-stream'},
        body: data,
      );

      // Write to block 1 only
      final newBlock = List<int>.filled(4 * 1024 * 1024, 0xFF);
      await _curl('POST',
        '$_ncAppBase/api/blocks/$testFile?offset=4194304&size=4194304',
        headers: {'Content-Type': 'application/octet-stream', 'OCS-APIREQUEST': 'true'},
        body: newBlock,
      );
      await _curl('POST',
        '$_ncAppBase/api/finalize/$testFile',
        headers: {'OCS-APIREQUEST': 'true'},
      );

      // Download and verify block 0 is still 0xAA
      final downloaded = await _curlGetBytes(
        '$_ncUrl/remote.php/dav/files/$_ncUser/$testFile',
        headers: {'Range': 'bytes=0-99'},
      );
      expect(downloaded.every((b) => b == 0xAA), isTrue,
          reason: 'Block 0 should be preserved after writing block 1');

      // Verify block 1 is now 0xFF
      final block1 = await _curlGetBytes(
        '$_ncUrl/remote.php/dav/files/$_ncUser/$testFile',
        headers: {'Range': 'bytes=4194304-4194403'},
      );
      expect(block1.every((b) => b == 0xFF), isTrue,
          reason: 'Block 1 should contain new data');

      // Cleanup
      await _curl('DELETE', '$_ncUrl/remote.php/dav/files/$_ncUser/$testFile');
    });
  });
}
