// test/mock_server/mock_s3_server.dart
//
// In-process S3-compatible mock HTTP server for offline CI testing.
// Uses dart:io HttpServer on localhost with port 0 (dynamic allocation).
// SigV4 signature validation is intentionally skipped.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// In-process mock S3 server.
///
/// Storage layout: `_store[bucket][key] = bytes`
class MockS3Server {
  HttpServer? _server;

  /// bucket → key → data
  final Map<String, Map<String, Uint8List>> _store = {};

  /// Metadata map: bucket → key → {etag, lastModified}
  final Map<String, Map<String, Map<String, String>>> _meta = {};

  int get port => _server?.port ?? 0;

  String get baseUrl => 'http://127.0.0.1:$port';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> start([int port = 0]) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_handleRequest);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ---------------------------------------------------------------------------
  // Data helpers
  // ---------------------------------------------------------------------------

  void seedData(String bucket, String key, Uint8List data) {
    _store.putIfAbsent(bucket, () => {});
    _meta.putIfAbsent(bucket, () => {});
    _store[bucket]![key] = data;
    _meta[bucket]![key] = {
      'etag': _etag(data),
      'lastModified': HttpDate.format(DateTime.now().toUtc()),
    };
  }

  void createBucket(String bucket) {
    _store.putIfAbsent(bucket, () => {});
    _meta.putIfAbsent(bucket, () => {});
  }

  void reset() {
    _store.clear();
    _meta.clear();
  }

  // ---------------------------------------------------------------------------
  // ETag helper (MD5 hex of data)
  // ---------------------------------------------------------------------------

  String _etag(Uint8List data) {
    // Simple deterministic hash: use length + xor checksum for speed in tests.
    // In production S3 this is MD5, but we only need consistency here.
    int xor = 0;
    for (final b in data) {
      xor ^= b;
    }
    final hex = data.length.toRadixString(16).padLeft(8, '0') +
        xor.toRadixString(16).padLeft(2, '0');
    return '"$hex"';
  }

  // ---------------------------------------------------------------------------
  // Request dispatch
  // ---------------------------------------------------------------------------

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      // Filter out empty segments (from trailing slashes like /bucket/)
      final rawSegments = req.uri.pathSegments;
      final segments = rawSegments.where((s) => s.isNotEmpty).toList();
      final method = req.method.toUpperCase();
      final queryParams = req.uri.queryParameters;
      final queryString = req.uri.query;
      // Debug: uncomment to trace requests
      // print('[MockS3] $method ${req.uri.path} segs=$segments q=${req.uri.query}');

      // --- GET / → list buckets ---
      if (method == 'GET' && segments.isEmpty) {
        await _listBuckets(req);
        return;
      }

      if (segments.isEmpty) {
        _sendXmlError(req.response, 400, 'InvalidRequest', 'Empty path');
        return;
      }

      final bucket = segments[0];

      // --- PUT /{bucket} → create bucket ---
      if (method == 'PUT' && segments.length == 1) {
        await _createBucket(req, bucket);
        return;
      }

      // --- GET /{bucket}?list-type=2 → list objects ---
      if (method == 'GET' && segments.length == 1) {
        await _listObjects(req, bucket, queryParams);
        return;
      }

      // --- POST /{bucket}?delete → multi-delete ---
      if (method == 'POST' && segments.length == 1 && queryString.contains('delete')) {
        await _multiDelete(req, bucket);
        return;
      }

      // Object-level operations
      if (segments.length < 2) {
        _sendXmlError(req.response, 400, 'InvalidRequest', 'Missing key');
        return;
      }

      final key = segments.sublist(1).join('/');

      switch (method) {
        case 'GET':
          await _getObject(req, bucket, key);
          break;
        case 'PUT':
          await _putObject(req, bucket, key);
          break;
        case 'DELETE':
          await _deleteObject(req, bucket, key);
          break;
        case 'HEAD':
          await _headObject(req, bucket, key);
          break;
        default:
          _sendXmlError(req.response, 405, 'MethodNotAllowed', 'Method not allowed');
      }
    } catch (e, st) {
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Operation handlers
  // ---------------------------------------------------------------------------

  Future<void> _listBuckets(HttpRequest req) async {
    final now = HttpDate.format(DateTime.now().toUtc());
    final bucketXml = _store.keys.map((b) => '''
  <Bucket>
    <Name>$b</Name>
    <CreationDate>$now</CreationDate>
  </Bucket>''').join('\n');

    final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Owner>
    <ID>mock-owner</ID>
    <DisplayName>mock</DisplayName>
  </Owner>
  <Buckets>
$bucketXml
  </Buckets>
</ListAllMyBucketsResult>''';
    _sendXml(req.response, 200, xml);
  }

  Future<void> _createBucket(HttpRequest req, String bucket) async {
    // Drain body (may contain CreateBucketConfiguration)
    await req.drain<void>();
    _store.putIfAbsent(bucket, () => {});
    _meta.putIfAbsent(bucket, () => {});
    req.response.statusCode = 200;
    req.response.headers.set('Location', '/$bucket');
    await req.response.close();
  }

  Future<void> _listObjects(
    HttpRequest req,
    String bucket,
    Map<String, String> params,
  ) async {
    if (!_store.containsKey(bucket)) {
      _sendXmlError(req.response, 404, 'NoSuchBucket', 'The bucket does not exist');
      return;
    }

    final prefix = params['prefix'] ?? '';
    final delimiter = params['delimiter'] ?? '';
    final maxKeysParam = params['max-keys'] ?? params['max_keys'] ?? '1000';
    final continuationToken = params['continuation-token'] ?? '';
    final int maxKeys = int.tryParse(maxKeysParam) ?? 1000;

    final allKeys = _store[bucket]!.keys
        .where((k) => k.startsWith(prefix))
        .toList()
      ..sort();

    // Apply continuation token (it stores the key to start after)
    int startIndex = 0;
    if (continuationToken.isNotEmpty) {
      startIndex = allKeys.indexOf(continuationToken) + 1;
      if (startIndex <= 0) startIndex = allKeys.length; // invalid token → empty
    }

    // Apply delimiter: collect common prefixes and objects
    final commonPrefixes = <String>{};
    final objects = <String>[];

    for (final key in allKeys.skip(startIndex)) {
      if (delimiter.isNotEmpty) {
        final rest = key.substring(prefix.length);
        final delimIdx = rest.indexOf(delimiter);
        if (delimIdx >= 0) {
          commonPrefixes.add(prefix + rest.substring(0, delimIdx + delimiter.length));
          continue;
        }
      }
      objects.add(key);
    }

    // Paginate
    final pagedObjects = objects.take(maxKeys).toList();
    final bool isTruncated = objects.length > maxKeys;
    final nextToken = isTruncated ? pagedObjects.last : '';

    final contentsXml = pagedObjects.map((k) {
      final data = _store[bucket]![k]!;
      final m = _meta[bucket]?[k];
      final etag = m?['etag'] ?? _etag(data);
      final lm = m?['lastModified'] ?? HttpDate.format(DateTime.now().toUtc());
      // Order: Key, LastModified, ETag, Size — matches adapter's XML regex
      return '''  <Contents>
    <Key>$k</Key>
    <LastModified>$lm</LastModified>
    <ETag>$etag</ETag>
    <Size>${data.length}</Size>
    <StorageClass>STANDARD</StorageClass>
  </Contents>''';
    }).join('\n');

    final prefixesXml = commonPrefixes.map((cp) => '''  <CommonPrefixes>
    <Prefix>$cp</Prefix>
  </CommonPrefixes>''').join('\n');

    final nextTokenXml = isTruncated
        ? '<NextContinuationToken>$nextToken</NextContinuationToken>'
        : '';

    final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Name>$bucket</Name>
  <Prefix>${_xmlEscape(prefix)}</Prefix>
  <MaxKeys>$maxKeys</MaxKeys>
  <KeyCount>${pagedObjects.length}</KeyCount>
  <IsTruncated>$isTruncated</IsTruncated>
  $nextTokenXml
$contentsXml
$prefixesXml
</ListBucketResult>''';
    _sendXml(req.response, 200, xml);
  }

  Future<void> _getObject(HttpRequest req, String bucket, String key) async {
    if (!_store.containsKey(bucket)) {
      _sendXmlError(req.response, 404, 'NoSuchBucket', 'The bucket does not exist');
      return;
    }
    final data = _store[bucket]![key];
    if (data == null) {
      _sendXmlError(req.response, 404, 'NoSuchKey', 'The specified key does not exist');
      return;
    }
    final m = _meta[bucket]?[key];
    final etag = m?['etag'] ?? _etag(data);
    final lm = m?['lastModified'] ?? HttpDate.format(DateTime.now().toUtc());

    req.response.statusCode = 200;
    req.response.headers
      ..set('Content-Length', data.length.toString())
      ..set('ETag', etag)
      ..set('Last-Modified', lm)
      ..set('Content-Type', 'application/octet-stream');
    req.response.add(data);
    await req.response.close();
  }

  Future<void> _putObject(HttpRequest req, String bucket, String key) async {
    if (!_store.containsKey(bucket)) {
      // Auto-create bucket for convenience in tests
      _store[bucket] = {};
      _meta[bucket] = {};
    }
    final bytes = await _readBody(req);
    final data = Uint8List.fromList(bytes);
    _store[bucket]![key] = data;
    _meta.putIfAbsent(bucket, () => {})[key] = {
      'etag': _etag(data),
      'lastModified': HttpDate.format(DateTime.now().toUtc()),
    };
    final etag = _etag(data);
    req.response.statusCode = 200;
    req.response.headers.set('ETag', etag);
    await req.response.close();
  }

  Future<void> _deleteObject(HttpRequest req, String bucket, String key) async {
    await req.drain<void>();
    if (!_store.containsKey(bucket)) {
      _sendXmlError(req.response, 404, 'NoSuchBucket', 'The bucket does not exist');
      return;
    }
    _store[bucket]!.remove(key);
    _meta[bucket]?.remove(key);
    req.response.statusCode = 204;
    await req.response.close();
  }

  Future<void> _headObject(HttpRequest req, String bucket, String key) async {
    await req.drain<void>();
    if (!_store.containsKey(bucket)) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    final data = _store[bucket]![key];
    if (data == null) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    final m = _meta[bucket]?[key];
    final etag = m?['etag'] ?? _etag(data);
    final lm = m?['lastModified'] ?? HttpDate.format(DateTime.now().toUtc());

    req.response.statusCode = 200;
    req.response.headers
      ..set('Content-Length', data.length.toString())
      ..set('ETag', etag)
      ..set('Last-Modified', lm)
      ..set('Content-Type', 'application/octet-stream');
    await req.response.close();
  }

  Future<void> _multiDelete(HttpRequest req, String bucket) async {
    final body = await _readBody(req);
    final xmlStr = utf8.decode(body);

    if (!_store.containsKey(bucket)) {
      _sendXmlError(req.response, 404, 'NoSuchBucket', 'The bucket does not exist');
      return;
    }

    // Simple regex extraction of <Key> elements
    final keyMatches = RegExp(r'<Key>(.*?)</Key>').allMatches(xmlStr);
    final deleted = <String>[];
    for (final m in keyMatches) {
      final key = m.group(1)!;
      _store[bucket]!.remove(key);
      _meta[bucket]?.remove(key);
      deleted.add(key);
    }

    final deletedXml = deleted
        .map((k) => '  <Deleted><Key>${_xmlEscape(k)}</Key></Deleted>')
        .join('\n');

    final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<DeleteResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
$deletedXml
</DeleteResult>''';
    _sendXml(req.response, 200, xml);
  }

  // ---------------------------------------------------------------------------
  // Utility helpers
  // ---------------------------------------------------------------------------

  Future<List<int>> _readBody(HttpRequest req) async {
    final chunks = <List<int>>[];
    await for (final chunk in req) {
      chunks.add(chunk);
    }
    return chunks.expand((c) => c).toList();
  }

  void _sendXml(HttpResponse response, int status, String xml) {
    final bytes = utf8.encode(xml);
    response.statusCode = status;
    response.headers
      ..set('Content-Type', 'application/xml; charset=utf-8')
      ..set('Content-Length', bytes.length.toString());
    response.add(bytes);
    response.close();
  }

  void _sendXmlError(
    HttpResponse response,
    int status,
    String code,
    String message,
  ) {
    final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Error>
  <Code>$code</Code>
  <Message>${_xmlEscape(message)}</Message>
</Error>''';
    _sendXml(response, status, xml);
  }

  String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
