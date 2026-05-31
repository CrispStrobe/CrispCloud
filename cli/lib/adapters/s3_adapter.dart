// lib/adapters/s3_adapter.dart
//
// Pure-Dart S3 adapter for the crisp CLI.
// Ported from lib/services/s3_client_adapter.dart with Flutter / SharedPreferences
// dependencies removed.  Implements AWS Signature V4 directly.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../config/cli_config.dart';
import 'cli_storage_client.dart';

class S3CliAdapter implements CliStorageClient {
  final String _accessKey;
  final String _secretKey;
  final String _endpoint;
  final String _bucket;
  final String _region;

  S3CliAdapter({
    required String accessKey,
    required String secretKey,
    required String endpoint,
    required String bucket,
    required String region,
  })  : _accessKey = accessKey,
        _secretKey = secretKey,
        _endpoint = endpoint,
        _bucket = bucket,
        _region = region;

  /// Create from a provider config map (as stored in ~/.config/crispcloud/config.yaml).
  factory S3CliAdapter.fromConfig(Map<String, dynamic> cfg) {
    final accessKey = cfg['access_key'] as String?;
    final secretKey = cfg['secret_key'] as String?;
    final endpoint = cfg['endpoint'] as String?;
    final bucket = cfg['bucket'] as String?;
    final region = (cfg['region'] as String?) ?? 'us-east-1';

    if (accessKey == null || secretKey == null || endpoint == null || bucket == null) {
      throw CliConfigException(
        'S3 provider config missing required fields: access_key, secret_key, endpoint, bucket',
      );
    }
    return S3CliAdapter(
      accessKey: accessKey,
      secretKey: secretKey,
      endpoint: endpoint,
      bucket: bucket,
      region: region,
    );
  }

  /// Parse the identity string used with `crisp connect`:
  ///   accessKey@endpoint/bucket?region=us-east-1
  static Map<String, String?> parseIdentity(String identity, String secretKey) {
    final atIdx = identity.indexOf('@');
    if (atIdx < 0) {
      throw CliConfigException(
        'Invalid S3 identity format. Expected: accessKey@endpoint/bucket[?region=REGION]',
      );
    }

    final accessKey = identity.substring(0, atIdx);
    var rest = identity.substring(atIdx + 1);
    String? region;

    final qIdx = rest.indexOf('?');
    if (qIdx >= 0) {
      final query = rest.substring(qIdx + 1);
      rest = rest.substring(0, qIdx);
      final params = Uri.splitQueryString(query);
      region = params['region'];
    }

    final Uri parsedUri;
    try {
      parsedUri = rest.startsWith('http://') || rest.startsWith('https://')
          ? Uri.parse(rest)
          : Uri.parse('https://$rest');
    } catch (_) {
      throw CliConfigException('Invalid S3 endpoint in identity: $rest');
    }

    final pathSegments = parsedUri.pathSegments.where((s) => s.isNotEmpty).toList();
    String? bucket;
    String? endpoint;

    if (pathSegments.isNotEmpty) {
      bucket = pathSegments.last;
      final scheme = rest.startsWith('http://') ? 'http' : 'https';
      final portStr = parsedUri.hasPort &&
              parsedUri.port != 443 &&
              parsedUri.port != 80
          ? ':${parsedUri.port}'
          : '';
      if (pathSegments.length > 1) {
        final base = pathSegments.sublist(0, pathSegments.length - 1).join('/');
        endpoint = '$scheme://${parsedUri.host}$portStr/$base';
      } else {
        endpoint = '$scheme://${parsedUri.host}$portStr';
      }
    } else {
      throw CliConfigException('S3 identity must include bucket: accessKey@endpoint/bucket');
    }

    return {
      'access_key': accessKey,
      'secret_key': secretKey,
      'endpoint': endpoint,
      'bucket': bucket,
      'region': region ?? 'us-east-1',
    };
  }

  @override
  String get providerName => 'S3';

  // ---------------------------------------------------------------------------
  // URI helpers
  // ---------------------------------------------------------------------------

  bool get _useVirtualHostedStyle => _endpoint.contains('amazonaws.com');

  Uri _buildObjectUri(String key, {Map<String, String>? queryParams}) {
    final uri = Uri.parse(_endpoint);
    if (_useVirtualHostedStyle) {
      return Uri(
        scheme: uri.scheme,
        host: '$_bucket.${uri.host}',
        port: uri.hasPort ? uri.port : null,
        path: '/${_cleanKey(key)}',
        queryParameters: queryParams,
      );
    } else {
      final prefix = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '$prefix$_bucket/${_cleanKey(key)}',
        queryParameters: queryParams,
      );
    }
  }

  Uri _buildBucketUri({Map<String, String>? queryParams}) {
    final uri = Uri.parse(_endpoint);
    if (_useVirtualHostedStyle) {
      return Uri(
        scheme: uri.scheme,
        host: '$_bucket.${uri.host}',
        port: uri.hasPort ? uri.port : null,
        path: '/',
        queryParameters: queryParams,
      );
    } else {
      final prefix = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '$prefix$_bucket/',
        queryParameters: queryParams,
      );
    }
  }

  String _cleanKey(String key) =>
      key.startsWith('/') ? key.substring(1) : key;

  String _pathToKey(String path) =>
      path.startsWith('/') ? path.substring(1) : path;

  // ---------------------------------------------------------------------------
  // AWS Signature V4
  // ---------------------------------------------------------------------------

  Map<String, String> _sign({
    required String method,
    required Uri uri,
    Map<String, String>? extraHeaders,
    List<int>? body,
  }) {
    final now = DateTime.now().toUtc();
    final dateStamp = _datestamp(now);
    final amzDate = _amzDate(now);
    final payloadHash = sha256.convert(body ?? <int>[]).toString();
    const service = 's3';
    final scope = '$dateStamp/$_region/$service/aws4_request';

    final headers = <String, String>{
      ...?extraHeaders,
      'host': uri.host +
          (uri.hasPort && uri.port != 443 && uri.port != 80 ? ':${uri.port}' : ''),
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
    };

    final sortedKeys = headers.keys.map((k) => k.toLowerCase()).toList()..sort();
    final canonicalHeaders =
        sortedKeys.map((k) => '$k:${headers[_origKey(headers, k)]!.trim()}').join('\n');
    final signedHeaderStr = sortedKeys.join(';');

    final canonicalRequest = [
      method,
      _canonicalPath(uri),
      _canonicalQueryString(uri),
      '$canonicalHeaders\n',
      signedHeaderStr,
      payloadHash,
    ].join('\n');

    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _derivedKey(dateStamp);
    final signature =
        Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).toString();

    return {
      ...headers,
      'Authorization':
          'AWS4-HMAC-SHA256 Credential=$_accessKey/$scope, '
          'SignedHeaders=$signedHeaderStr, '
          'Signature=$signature',
    };
  }

  // Find the original-case key given a lowercase key
  String _origKey(Map<String, String> map, String lower) {
    for (final k in map.keys) {
      if (k.toLowerCase() == lower) return k;
    }
    return lower;
  }

  List<int> _derivedKey(String dateStamp) {
    final kDate =
        Hmac(sha256, utf8.encode('AWS4$_secretKey')).convert(utf8.encode(dateStamp)).bytes;
    final kRegion = Hmac(sha256, kDate).convert(utf8.encode(_region)).bytes;
    final kService = Hmac(sha256, kRegion).convert(utf8.encode('s3')).bytes;
    return Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
  }

  String _datestamp(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}'
      '${dt.month.toString().padLeft(2, '0')}'
      '${dt.day.toString().padLeft(2, '0')}';

  String _amzDate(DateTime dt) =>
      '${_datestamp(dt)}T'
      '${dt.hour.toString().padLeft(2, '0')}'
      '${dt.minute.toString().padLeft(2, '0')}'
      '${dt.second.toString().padLeft(2, '0')}Z';

  String _canonicalPath(Uri uri) {
    if (uri.path.isEmpty) return '/';
    final encoded =
        uri.pathSegments.map((s) => Uri.encodeComponent(s)).join('/');
    final path = '/$encoded';
    if (uri.path.endsWith('/') && !path.endsWith('/')) return '$path/';
    return path;
  }

  String _canonicalQueryString(Uri uri) {
    if (uri.queryParameters.isEmpty) return '';
    final sorted = uri.queryParameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
  }

  // ---------------------------------------------------------------------------
  // HTTP helper
  // ---------------------------------------------------------------------------

  Future<http.Response> _request(
    String method,
    Uri uri, {
    Map<String, String>? extraHeaders,
    List<int>? body,
  }) async {
    final signed = _sign(
      method: method,
      uri: uri,
      extraHeaders: extraHeaders,
      body: body,
    );
    final req = http.Request(method, uri);
    req.headers.addAll(signed);
    if (body != null) req.bodyBytes = Uint8List.fromList(body);
    final streamed = await http.Client().send(req);
    return http.Response.fromStream(streamed);
  }

  // ---------------------------------------------------------------------------
  // CliStorageClient implementation
  // ---------------------------------------------------------------------------

  @override
  Future<List<CliFileItem>> list(String remotePath) async {
    final prefix = _pathToKey(remotePath);
    final normalizedPrefix =
        prefix.isEmpty ? '' : (prefix.endsWith('/') ? prefix : '$prefix/');

    final items = <CliFileItem>[];
    String? continuationToken;

    do {
      final params = <String, String>{
        'list-type': '2',
        'delimiter': '/',
        'max-keys': '1000',
      };
      if (normalizedPrefix.isNotEmpty) params['prefix'] = normalizedPrefix;
      if (continuationToken != null) {
        params['continuation-token'] = continuationToken;
      }

      final uri = _buildBucketUri(queryParams: params);
      final response = await _request('GET', uri);

      if (response.statusCode != 200) {
        throw Exception('S3 list failed (HTTP ${response.statusCode}): ${response.body}');
      }

      final body = response.body;

      // Parse CommonPrefixes (virtual folders)
      for (final m in RegExp(
        r'<CommonPrefixes>\s*<Prefix>([^<]+)</Prefix>\s*</CommonPrefixes>',
      ).allMatches(body)) {
        final folderPrefix = m.group(1)!;
        var folderName = folderPrefix;
        if (normalizedPrefix.isNotEmpty &&
            folderName.startsWith(normalizedPrefix)) {
          folderName = folderName.substring(normalizedPrefix.length);
        }
        if (folderName.endsWith('/')) {
          folderName = folderName.substring(0, folderName.length - 1);
        }
        if (folderName.isEmpty) continue;
        items.add(CliFileItem(
          name: folderName,
          path: '/$folderPrefix',
          isDirectory: true,
        ));
      }

      // Parse Contents (files)
      for (final m in RegExp(
        r'<Contents>\s*'
        r'<Key>([^<]+)</Key>\s*'
        r'<LastModified>([^<]+)</LastModified>\s*'
        r'(?:<ETag>[^<]*</ETag>\s*)?'
        r'<Size>([^<]+)</Size>',
      ).allMatches(body)) {
        final key = m.group(1)!;
        final lastModified = m.group(2)!;
        final size = int.tryParse(m.group(3) ?? '0') ?? 0;

        if (key == normalizedPrefix) continue;
        if (key.endsWith('/') && size == 0) continue;

        var fileName = key;
        if (normalizedPrefix.isNotEmpty && fileName.startsWith(normalizedPrefix)) {
          fileName = fileName.substring(normalizedPrefix.length);
        }
        if (fileName.isEmpty) continue;

        items.add(CliFileItem(
          name: fileName,
          path: '/$key',
          isDirectory: false,
          size: size,
          modifiedAt: lastModified,
        ));
      }

      final isTruncated =
          RegExp(r'<IsTruncated>true</IsTruncated>').hasMatch(body);
      if (isTruncated) {
        final tokenM = RegExp(
          r'<NextContinuationToken>([^<]+)</NextContinuationToken>',
        ).firstMatch(body);
        continuationToken = tokenM?.group(1);
        if (continuationToken == null) break;
      } else {
        continuationToken = null;
      }
    } while (continuationToken != null);

    return items;
  }

  @override
  Future<void> upload(
    List<int> data,
    String fileName,
    String remoteDir, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final key = _pathToKey(p.posix.join(remoteDir, fileName));
    const multipartThreshold = 5 * 1024 * 1024;

    if (data.length > multipartThreshold) {
      await _multipartUpload(key, data, onProgress: onProgress);
      return;
    }

    final uri = _buildObjectUri(key);
    final response = await _request(
      'PUT',
      uri,
      extraHeaders: {'content-type': 'application/octet-stream'},
      body: data,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('S3 upload failed (HTTP ${response.statusCode}): ${response.body}');
    }
    onProgress?.call(data.length, data.length);
  }

  Future<void> _multipartUpload(
    String key,
    List<int> data, {
    void Function(int, int)? onProgress,
    int partSize = 8 * 1024 * 1024,
  }) async {
    final uploadId = await _initiateMultipart(key);
    final parts = <_PartETag>[];
    int uploaded = 0;

    try {
      int partNum = 1;
      for (int offset = 0; offset < data.length; offset += partSize) {
        final end = (offset + partSize > data.length) ? data.length : offset + partSize;
        final chunk = data.sublist(offset, end);
        final etag = await _uploadPart(key, uploadId, partNum, chunk);
        parts.add(_PartETag(partNum, etag));
        uploaded += chunk.length;
        onProgress?.call(uploaded, data.length);
        partNum++;
      }
      await _completeMultipart(key, uploadId, parts);
    } catch (e) {
      rethrow;
    }
  }

  Future<String> _initiateMultipart(String key) async {
    final uri = _buildObjectUri(key, queryParams: {'uploads': ''});
    final response = await _request(
      'POST',
      uri,
      extraHeaders: {'content-type': 'application/octet-stream'},
    );
    if (response.statusCode != 200) {
      throw Exception('S3 initiate multipart failed (HTTP ${response.statusCode})');
    }
    final m = RegExp(r'<UploadId>([^<]+)</UploadId>').firstMatch(response.body);
    if (m == null) throw Exception('S3: no UploadId in initiate response');
    return m.group(1)!;
  }

  Future<String> _uploadPart(
      String key, String uploadId, int partNumber, List<int> chunk) async {
    final uri = _buildObjectUri(key, queryParams: {
      'partNumber': partNumber.toString(),
      'uploadId': uploadId,
    });
    final response = await _request('PUT', uri, body: chunk);
    if (response.statusCode != 200) {
      throw Exception('S3 upload part $partNumber failed (HTTP ${response.statusCode})');
    }
    return response.headers['etag'] ??
        (throw Exception('S3: no ETag for part $partNumber'));
  }

  Future<void> _completeMultipart(
      String key, String uploadId, List<_PartETag> parts) async {
    final xmlParts = parts
        .map((p) =>
            '<Part><PartNumber>${p.partNumber}</PartNumber><ETag>${p.etag}</ETag></Part>')
        .join();
    final body =
        '<CompleteMultipartUpload>$xmlParts</CompleteMultipartUpload>';
    final uri = _buildObjectUri(key, queryParams: {'uploadId': uploadId});
    final response = await _request(
      'POST',
      uri,
      extraHeaders: {'content-type': 'application/xml'},
      body: utf8.encode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('S3 complete multipart failed (HTTP ${response.statusCode})');
    }
  }

  @override
  Future<List<int>> downloadBytes(String remotePath) async {
    final key = _pathToKey(remotePath);
    final uri = _buildObjectUri(key);
    final response = await _request('GET', uri);
    if (response.statusCode != 200) {
      throw Exception('S3 download failed (HTTP ${response.statusCode}): ${response.body}');
    }
    return response.bodyBytes;
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final bytes = await downloadBytes(remotePath);
    await File(localPath).writeAsBytes(bytes);
    onProgress?.call(bytes.length, bytes.length);
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    var key = _pathToKey(remotePath);
    if (!key.endsWith('/')) key = '$key/';
    final uri = _buildObjectUri(key);
    final response = await _request(
      'PUT',
      uri,
      extraHeaders: {'content-type': 'application/octet-stream'},
      body: <int>[],
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('S3 mkdir failed (HTTP ${response.statusCode})');
    }
  }

  @override
  Future<void> delete(String remotePath) async {
    final key = _pathToKey(remotePath);
    final uri = _buildObjectUri(key);
    final response = await _request('DELETE', uri);
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('S3 delete failed (HTTP ${response.statusCode})');
    }
  }

  @override
  Future<void> move(String sourcePath, String targetPath) async {
    final srcKey = _pathToKey(sourcePath);
    final dstKey = _pathToKey(targetPath);
    // S3 copy + delete
    final copyUri = _buildObjectUri(dstKey);
    final response = await _request(
      'PUT',
      copyUri,
      extraHeaders: {'x-amz-copy-source': '/$_bucket/$srcKey'},
      body: <int>[],
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('S3 copy failed (HTTP ${response.statusCode})');
    }
    await delete(sourcePath);
  }

  @override
  Future<CliFileItem?> stat(String remotePath) async {
    final key = _pathToKey(remotePath);
    if (key.isEmpty) {
      return const CliFileItem(name: '', path: '/', isDirectory: true);
    }
    final uri = _buildObjectUri(key);
    try {
      final response = await _request('HEAD', uri);
      if (response.statusCode == 200) {
        return CliFileItem(
          name: p.basename(key),
          path: remotePath,
          isDirectory: key.endsWith('/'),
          size: int.tryParse(response.headers['content-length'] ?? '0'),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> share(String remotePath, {Duration? expires}) async {
    // Generate a pre-signed URL (query-string signing)
    final key = _pathToKey(remotePath);
    final expiresSeconds = (expires ?? const Duration(hours: 1)).inSeconds;
    final now = DateTime.now().toUtc();
    final dateStamp = _datestamp(now);
    final amzDate = _amzDate(now);
    const service = 's3';
    final scope = '$dateStamp/$_region/$service/aws4_request';
    final uri = _buildObjectUri(key);

    final credentialParam = '$_accessKey/$scope';
    final queryParams = <String, String>{
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': credentialParam,
      'X-Amz-Date': amzDate,
      'X-Amz-Expires': expiresSeconds.toString(),
      'X-Amz-SignedHeaders': 'host',
    };

    final sortedQuery = queryParams.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final canonicalQueryString = sortedQuery
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    final host = uri.host +
        (uri.hasPort && uri.port != 443 && uri.port != 80 ? ':${uri.port}' : '');
    final canonicalRequest = [
      'GET',
      _canonicalPath(uri),
      canonicalQueryString,
      'host:$host\n',
      'host',
      'UNSIGNED-PAYLOAD',
    ].join('\n');

    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _derivedKey(dateStamp);
    final signature =
        Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).toString();

    final signedUrl = uri.replace(
      queryParameters: {
        ...queryParams,
        'X-Amz-Signature': signature,
      },
    );

    return signedUrl.toString();
  }

  @override
  Future<void> dispose() async {}
}

class _PartETag {
  final int partNumber;
  final String etag;
  _PartETag(this.partNumber, this.etag);
}
