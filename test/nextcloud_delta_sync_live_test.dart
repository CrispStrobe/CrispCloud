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

      // Write random data to block 1
      final patch = List.generate(4 * 1024 * 1024, (i) => (i * 7 + 13) % 256);
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
}
