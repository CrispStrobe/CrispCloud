// test/mock_server_test.dart
//
// Tests for MockS3Server and MockWebDavServer — offline CI mock servers.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'mock_server/mock_s3_server.dart';
import 'mock_server/mock_webdav_server.dart';

// ---------------------------------------------------------------------------
// Helper: simple HTTP client wrappers (no package:http dependency needed)
// ---------------------------------------------------------------------------

Future<HttpClientResponse> _request(
  String method,
  String url, {
  List<int>? body,
  Map<String, String>? headers,
}) async {
  final uri = Uri.parse(url);
  final client = HttpClient();
  final req = await client.openUrl(method, uri);
  if (headers != null) {
    headers.forEach((k, v) => req.headers.set(k, v));
  }
  if (body != null) {
    req.headers.set('Content-Length', body.length.toString());
    req.add(body);
  }
  return req.close();
}

Future<Uint8List> _responseBytes(HttpClientResponse resp) async {
  final chunks = <List<int>>[];
  await for (final chunk in resp) {
    chunks.add(chunk);
  }
  return Uint8List.fromList(chunks.expand((c) => c).toList());
}

Future<String> _responseString(HttpClientResponse resp) async =>
    utf8.decode(await _responseBytes(resp));

// ---------------------------------------------------------------------------
// S3 Tests
// ---------------------------------------------------------------------------

void main() {
  group('MockS3Server', () {
    late MockS3Server server;

    setUp(() async {
      server = MockS3Server();
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    // --- Lifecycle ---

    test('start assigns a non-zero port', () {
      expect(server.port, greaterThan(0));
    });

    test('stop closes server (subsequent request fails)', () async {
      final port = server.port;
      await server.stop();
      expect(
        () async => await _request('GET', 'http://127.0.0.1:$port/'),
        throwsA(anything),
      );
    });

    // --- Bucket operations ---

    test('PUT /{bucket} creates bucket and returns 200', () async {
      final resp = await _request('PUT', '${server.baseUrl}/mybucket');
      expect(resp.statusCode, equals(200));
    });

    test('GET / lists buckets (empty initially)', () async {
      final resp = await _request('GET', '${server.baseUrl}/');
      expect(resp.statusCode, equals(200));
      final body = await _responseString(resp);
      expect(body, contains('<ListAllMyBucketsResult'));
    });

    test('GET / lists created buckets', () async {
      server.createBucket('alpha');
      server.createBucket('beta');
      final resp = await _request('GET', '${server.baseUrl}/');
      final body = await _responseString(resp);
      expect(body, contains('<Name>alpha</Name>'));
      expect(body, contains('<Name>beta</Name>'));
    });

    // --- Object PUT / GET ---

    test('PUT object then GET returns same data', () async {
      server.createBucket('bucket');
      final data = Uint8List.fromList(utf8.encode('hello world'));
      final put = await _request(
        'PUT',
        '${server.baseUrl}/bucket/docs/file.txt',
        body: data,
      );
      expect(put.statusCode, equals(200));

      final get = await _request('GET', '${server.baseUrl}/bucket/docs/file.txt');
      expect(get.statusCode, equals(200));
      final returned = await _responseBytes(get);
      expect(returned, equals(data));
    });

    test('GET non-existent key returns 404', () async {
      server.createBucket('bucket');
      final resp = await _request('GET', '${server.baseUrl}/bucket/no-such-key');
      expect(resp.statusCode, equals(404));
      final body = await _responseString(resp);
      expect(body, contains('NoSuchKey'));
    });

    test('GET from non-existent bucket returns 404', () async {
      final resp = await _request('GET', '${server.baseUrl}/ghost/key');
      expect(resp.statusCode, equals(404));
    });

    // --- HEAD ---

    test('HEAD returns correct Content-Length', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      server.seedData('bucket', 'file.bin', data);
      final resp = await _request('HEAD', '${server.baseUrl}/bucket/file.bin');
      expect(resp.statusCode, equals(200));
      expect(resp.headers.value('content-length'), equals('5'));
    });

    test('HEAD non-existent key returns 404', () async {
      server.createBucket('bucket');
      final resp = await _request('HEAD', '${server.baseUrl}/bucket/missing');
      expect(resp.statusCode, equals(404));
    });

    // --- DELETE ---

    test('DELETE object → subsequent GET returns 404', () async {
      server.seedData('bucket', 'target.txt', Uint8List.fromList([42]));
      final del = await _request('DELETE', '${server.baseUrl}/bucket/target.txt');
      expect(del.statusCode, equals(204));

      final get = await _request('GET', '${server.baseUrl}/bucket/target.txt');
      expect(get.statusCode, equals(404));
    });

    // --- LIST ---

    test('GET /{bucket} with list-type=2 lists objects', () async {
      server.seedData('bkt', 'a.txt', Uint8List.fromList([1]));
      server.seedData('bkt', 'b.txt', Uint8List.fromList([2]));
      final resp = await _request('GET', '${server.baseUrl}/bkt?list-type=2');
      expect(resp.statusCode, equals(200));
      final body = await _responseString(resp);
      expect(body, contains('<ListBucketResult'));
      expect(body, contains('<Key>a.txt</Key>'));
      expect(body, contains('<Key>b.txt</Key>'));
    });

    test('List objects with prefix filter', () async {
      server.seedData('bkt', 'photos/cat.jpg', Uint8List.fromList([1]));
      server.seedData('bkt', 'photos/dog.jpg', Uint8List.fromList([2]));
      server.seedData('bkt', 'docs/readme.md', Uint8List.fromList([3]));
      final resp = await _request(
          'GET', '${server.baseUrl}/bkt?list-type=2&prefix=photos/');
      final body = await _responseString(resp);
      expect(body, contains('photos/cat.jpg'));
      expect(body, contains('photos/dog.jpg'));
      expect(body, isNot(contains('docs/readme.md')));
    });

    test('List objects with delimiter returns common prefixes', () async {
      server.seedData('bkt', 'a/x.txt', Uint8List.fromList([1]));
      server.seedData('bkt', 'a/y.txt', Uint8List.fromList([2]));
      server.seedData('bkt', 'b/z.txt', Uint8List.fromList([3]));
      final resp = await _request(
          'GET', '${server.baseUrl}/bkt?list-type=2&delimiter=/');
      final body = await _responseString(resp);
      expect(body, contains('<Prefix>a/</Prefix>'));
      expect(body, contains('<Prefix>b/</Prefix>'));
      // individual keys should not appear as Contents
      expect(body, isNot(contains('<Key>a/x.txt</Key>')));
    });

    test('List empty bucket returns empty result', () async {
      server.createBucket('empty');
      final resp = await _request('GET', '${server.baseUrl}/empty?list-type=2');
      final body = await _responseString(resp);
      expect(body, contains('<KeyCount>0</KeyCount>'));
      expect(body, isNot(contains('<Contents>')));
    });

    test('Pagination: max-keys limits results and sets NextContinuationToken', () async {
      for (var i = 0; i < 5; i++) {
        server.seedData('pg', 'file$i.txt', Uint8List.fromList([i]));
      }
      final resp = await _request(
          'GET', '${server.baseUrl}/pg?list-type=2&max-keys=2');
      final body = await _responseString(resp);
      expect(body, contains('<IsTruncated>true</IsTruncated>'));
      expect(body, contains('<NextContinuationToken>'));
    });

    test('Pagination continuation-token returns next page', () async {
      for (var i = 0; i < 4; i++) {
        server.seedData('pg2', 'item${i.toString().padLeft(2, '0')}.txt',
            Uint8List.fromList([i]));
      }
      // First page
      final r1 = await _request(
          'GET', '${server.baseUrl}/pg2?list-type=2&max-keys=2');
      final b1 = await _responseString(r1);
      final tokenMatch =
          RegExp(r'<NextContinuationToken>(.*?)</NextContinuationToken>')
              .firstMatch(b1);
      expect(tokenMatch, isNotNull);
      final token = Uri.encodeComponent(tokenMatch!.group(1)!);

      // Second page
      final r2 = await _request(
          'GET',
          '${server.baseUrl}/pg2?list-type=2&max-keys=2&continuation-token=$token');
      final b2 = await _responseString(r2);
      expect(b2, contains('<IsTruncated>false</IsTruncated>'));
    });

    // --- Multiple buckets isolation ---

    test('Multiple buckets are isolated', () async {
      server.seedData('alpha', 'key.txt', Uint8List.fromList([1]));
      server.seedData('beta', 'key.txt', Uint8List.fromList([2]));

      final ra = await _request('GET', '${server.baseUrl}/alpha/key.txt');
      final rb = await _request('GET', '${server.baseUrl}/beta/key.txt');
      expect(await _responseBytes(ra), equals(Uint8List.fromList([1])));
      expect(await _responseBytes(rb), equals(Uint8List.fromList([2])));
    });

    // --- seedData / reset ---

    test('seedData populates data correctly', () async {
      final data = Uint8List.fromList(utf8.encode('seeded'));
      server.seedData('sb', 'obj', data);
      final resp = await _request('GET', '${server.baseUrl}/sb/obj');
      expect(resp.statusCode, equals(200));
      expect(await _responseBytes(resp), equals(data));
    });

    test('reset clears all data', () async {
      server.seedData('bk', 'k', Uint8List.fromList([9]));
      server.reset();
      final resp = await _request('GET', '${server.baseUrl}/bk/k');
      expect(resp.statusCode, equals(404));
    });

    // --- ETag ---

    test('ETag is consistent for same data', () async {
      final data = Uint8List.fromList(utf8.encode('same'));
      server.seedData('eb', 'f1', data);
      server.seedData('eb', 'f2', Uint8List.fromList(utf8.encode('same')));

      final r1 = await _request('HEAD', '${server.baseUrl}/eb/f1');
      final r2 = await _request('HEAD', '${server.baseUrl}/eb/f2');
      await _responseBytes(r1);
      await _responseBytes(r2);
      expect(r1.headers.value('etag'), equals(r2.headers.value('etag')));
    });

    test('ETag present in PUT response', () async {
      server.createBucket('et');
      final resp = await _request(
        'PUT',
        '${server.baseUrl}/et/obj',
        body: utf8.encode('data'),
      );
      expect(resp.headers.value('etag'), isNotNull);
      expect(resp.headers.value('etag'), isNotEmpty);
    });

    // --- XML response validity ---

    test('List bucket XML contains required elements', () async {
      server.seedData('xml', 'k', Uint8List.fromList([1]));
      final resp = await _request('GET', '${server.baseUrl}/xml?list-type=2');
      final body = await _responseString(resp);
      expect(body, contains('<?xml'));
      expect(body, contains('<ListBucketResult'));
      expect(body, contains('<Name>xml</Name>'));
      expect(body, contains('</ListBucketResult>'));
    });

    // --- Multi-delete ---

    test('POST /{bucket}?delete removes multiple objects', () async {
      server.seedData('md', 'a', Uint8List.fromList([1]));
      server.seedData('md', 'b', Uint8List.fromList([2]));
      server.seedData('md', 'c', Uint8List.fromList([3]));

      final xmlBody = '''<?xml version="1.0" encoding="UTF-8"?>
<Delete>
  <Object><Key>a</Key></Object>
  <Object><Key>b</Key></Object>
</Delete>''';

      final del = await _request(
        'POST',
        '${server.baseUrl}/md?delete',
        body: utf8.encode(xmlBody),
        headers: {'Content-Type': 'application/xml'},
      );
      expect(del.statusCode, equals(200));

      final ga = await _request('GET', '${server.baseUrl}/md/a');
      expect(ga.statusCode, equals(404));
      final gc = await _request('GET', '${server.baseUrl}/md/c');
      expect(gc.statusCode, equals(200));
      await _responseBytes(gc);
    });
  });

  // ---------------------------------------------------------------------------
  // WebDAV Tests
  // ---------------------------------------------------------------------------

  group('MockWebDavServer', () {
    late MockWebDavServer server;

    setUp(() async {
      server = MockWebDavServer();
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    // --- Lifecycle ---

    test('start assigns a non-zero port', () {
      expect(server.port, greaterThan(0));
    });

    test('stop closes server', () async {
      final port = server.port;
      await server.stop();
      expect(
        () async => await _request('OPTIONS', 'http://127.0.0.1:$port/'),
        throwsA(anything),
      );
    });

    // --- PUT / GET ---

    test('PUT file then GET returns same data', () async {
      final data = Uint8List.fromList(utf8.encode('webdav content'));
      final put = await _request(
        'PUT',
        '${server.baseUrl}/hello.txt',
        body: data,
      );
      expect(put.statusCode, equals(201));

      final get = await _request('GET', '${server.baseUrl}/hello.txt');
      expect(get.statusCode, equals(200));
      expect(await _responseBytes(get), equals(data));
    });

    test('GET non-existent path returns 404', () async {
      final resp = await _request('GET', '${server.baseUrl}/missing.txt');
      expect(resp.statusCode, equals(404));
    });

    // --- Content-Length header ---

    test('Content-Length header is correct for GET', () async {
      final data = Uint8List.fromList([10, 20, 30, 40, 50]);
      server.seedFile('/size.bin', data);
      final resp = await _request('GET', '${server.baseUrl}/size.bin');
      expect(resp.headers.value('content-length'), equals('5'));
      await _responseBytes(resp);
    });

    // --- PROPFIND ---

    test('PROPFIND root lists files', () async {
      server.seedFile('/alpha.txt', Uint8List.fromList([1]));
      server.seedFile('/beta.txt', Uint8List.fromList([2]));
      final resp = await _request(
        'PROPFIND',
        '${server.baseUrl}/',
        headers: {'Depth': '1'},
      );
      expect(resp.statusCode, equals(207));
      final body = await _responseString(resp);
      expect(body, contains('alpha.txt'));
      expect(body, contains('beta.txt'));
    });

    test('PROPFIND with Depth: 0 returns only target', () async {
      server.seedFile('/only.txt', Uint8List.fromList([1]));
      server.seedFile('/other.txt', Uint8List.fromList([2]));
      final resp = await _request(
        'PROPFIND',
        '${server.baseUrl}/only.txt',
        headers: {'Depth': '0'},
      );
      expect(resp.statusCode, equals(207));
      final body = await _responseString(resp);
      expect(body, contains('only.txt'));
      expect(body, isNot(contains('other.txt')));
    });

    test('PROPFIND with Depth: 1 returns direct children only', () async {
      server.seedFolder('/parent');
      server.seedFile('/parent/child.txt', Uint8List.fromList([1]));
      server.seedFolder('/parent/subdir');
      server.seedFile('/parent/subdir/deep.txt', Uint8List.fromList([2]));
      final resp = await _request(
        'PROPFIND',
        '${server.baseUrl}/parent',
        headers: {'Depth': '1'},
      );
      final body = await _responseString(resp);
      expect(body, contains('child.txt'));
      expect(body, contains('subdir'));
      // deep.txt is grandchild — should not appear
      expect(body, isNot(contains('deep.txt')));
    });

    test('PROPFIND non-existent path returns 404', () async {
      final resp = await _request(
        'PROPFIND',
        '${server.baseUrl}/ghost',
        headers: {'Depth': '1'},
      );
      expect(resp.statusCode, equals(404));
    });

    test('Multistatus XML contains required DAV elements', () async {
      server.seedFile('/doc.txt', Uint8List.fromList([1]));
      final resp = await _request(
        'PROPFIND',
        '${server.baseUrl}/doc.txt',
        headers: {'Depth': '0'},
      );
      final body = await _responseString(resp);
      expect(body, contains('<?xml'));
      expect(body, contains('<D:multistatus'));
      expect(body, contains('<D:response>'));
      expect(body, contains('<D:href>'));
      expect(body, contains('<D:status>'));
      expect(body, contains('</D:multistatus>'));
    });

    // --- MKCOL ---

    test('MKCOL creates folder', () async {
      final resp = await _request('MKCOL', '${server.baseUrl}/newfolder');
      expect(resp.statusCode, equals(201));

      final pf = await _request(
        'PROPFIND',
        '${server.baseUrl}/newfolder',
        headers: {'Depth': '0'},
      );
      expect(pf.statusCode, equals(207));
      final body = await _responseString(pf);
      expect(body, contains('<D:collection'));
    });

    test('MKCOL on existing path returns 405', () async {
      server.seedFolder('/exists');
      final resp = await _request('MKCOL', '${server.baseUrl}/exists');
      expect(resp.statusCode, equals(405));
    });

    test('MKCOL with missing parent returns 409', () async {
      final resp = await _request('MKCOL', '${server.baseUrl}/noparent/child');
      expect(resp.statusCode, equals(409));
    });

    // --- DELETE ---

    test('DELETE file → PROPFIND no longer lists it', () async {
      server.seedFile('/todelete.txt', Uint8List.fromList([1]));
      final del = await _request('DELETE', '${server.baseUrl}/todelete.txt');
      expect(del.statusCode, equals(204));
      await _responseBytes(del);

      final pf = await _request(
        'PROPFIND',
        '${server.baseUrl}/',
        headers: {'Depth': '1'},
      );
      final body = await _responseString(pf);
      expect(body, isNot(contains('todelete.txt')));
    });

    test('DELETE folder removes folder and all contents', () async {
      server.seedFolder('/folder');
      server.seedFile('/folder/file.txt', Uint8List.fromList([1]));
      final del = await _request('DELETE', '${server.baseUrl}/folder');
      expect(del.statusCode, equals(204));
      await _responseBytes(del);

      final resp = await _request('GET', '${server.baseUrl}/folder/file.txt');
      expect(resp.statusCode, equals(404));
    });

    test('DELETE non-existent path returns 404', () async {
      final resp = await _request('DELETE', '${server.baseUrl}/gone');
      expect(resp.statusCode, equals(404));
    });

    // --- MOVE ---

    test('MOVE renames file', () async {
      final data = Uint8List.fromList(utf8.encode('move me'));
      server.seedFile('/source.txt', data);
      final resp = await _request(
        'MOVE',
        '${server.baseUrl}/source.txt',
        headers: {'Destination': '${server.baseUrl}/dest.txt'},
      );
      expect(resp.statusCode, equals(201));

      final get = await _request('GET', '${server.baseUrl}/dest.txt');
      expect(get.statusCode, equals(200));
      expect(await _responseBytes(get), equals(data));

      final old = await _request('GET', '${server.baseUrl}/source.txt');
      expect(old.statusCode, equals(404));
    });

    test('MOVE non-existent source returns 404', () async {
      final resp = await _request(
        'MOVE',
        '${server.baseUrl}/nosource.txt',
        headers: {'Destination': '${server.baseUrl}/dest.txt'},
      );
      expect(resp.statusCode, equals(404));
    });

    // --- COPY ---

    test('COPY duplicates file', () async {
      final data = Uint8List.fromList(utf8.encode('copy me'));
      server.seedFile('/original.txt', data);
      final resp = await _request(
        'COPY',
        '${server.baseUrl}/original.txt',
        headers: {'Destination': '${server.baseUrl}/copy.txt'},
      );
      expect(resp.statusCode, equals(201));

      final getOrig = await _request('GET', '${server.baseUrl}/original.txt');
      expect(getOrig.statusCode, equals(200));
      expect(await _responseBytes(getOrig), equals(data));

      final getCopy = await _request('GET', '${server.baseUrl}/copy.txt');
      expect(getCopy.statusCode, equals(200));
      expect(await _responseBytes(getCopy), equals(data));
    });

    test('COPY non-existent source returns 404', () async {
      final resp = await _request(
        'COPY',
        '${server.baseUrl}/nosource.txt',
        headers: {'Destination': '${server.baseUrl}/dest.txt'},
      );
      expect(resp.statusCode, equals(404));
    });

    // --- Nested folders ---

    test('Nested folders: PUT and GET work across depth', () async {
      final data = Uint8List.fromList(utf8.encode('deep file'));
      final put = await _request(
        'PUT',
        '${server.baseUrl}/a/b/c/deep.txt',
        body: data,
      );
      expect(put.statusCode, equals(201));

      final get = await _request('GET', '${server.baseUrl}/a/b/c/deep.txt');
      expect(get.statusCode, equals(200));
      expect(await _responseBytes(get), equals(data));
    });

    // --- seedFile / seedFolder ---

    test('seedFile populates data correctly', () async {
      final data = Uint8List.fromList(utf8.encode('seeded file'));
      server.seedFile('/seeded.txt', data);
      final get = await _request('GET', '${server.baseUrl}/seeded.txt');
      expect(get.statusCode, equals(200));
      expect(await _responseBytes(get), equals(data));
    });

    test('seedFolder creates a traversable directory', () async {
      server.seedFolder('/mydir');
      final pf = await _request(
        'PROPFIND',
        '${server.baseUrl}/mydir',
        headers: {'Depth': '0'},
      );
      expect(pf.statusCode, equals(207));
      final body = await _responseString(pf);
      expect(body, contains('<D:collection'));
    });

    // --- reset ---

    test('reset clears all data', () async {
      server.seedFile('/tmp.txt', Uint8List.fromList([1]));
      server.reset();
      final resp = await _request('GET', '${server.baseUrl}/tmp.txt');
      expect(resp.statusCode, equals(404));
    });

    test('reset preserves root', () async {
      server.seedFile('/f.txt', Uint8List.fromList([1]));
      server.reset();
      // PROPFIND on root should still work
      final resp = await _request(
        'PROPFIND',
        '${server.baseUrl}/',
        headers: {'Depth': '1'},
      );
      expect(resp.statusCode, equals(207));
      await _responseString(resp);
    });

    // --- OPTIONS ---

    test('OPTIONS returns DAV header', () async {
      final resp = await _request('OPTIONS', '${server.baseUrl}/');
      expect(resp.statusCode, equals(200));
      expect(resp.headers.value('dav'), contains('1'));
    });
  });
}
