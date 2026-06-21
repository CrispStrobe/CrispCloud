// lib/services/s3_client_adapter.dart
//
// S3-compatible cloud storage adapter. Works with AWS S3, MinIO, Backblaze B2,
// Wasabi, DigitalOcean Spaces, Cloudflare R2, and any S3-compatible service.
//
// Uses pure Dart HTTP + AWS Signature V4 signing (no heavy SDK).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_storage_interface.dart';
import 'delta_sync_service.dart';
import 'log_service.dart';
import 's3_config_service.dart';
import 'secure_storage_service.dart';

/// S3 server-side encryption modes.
enum S3Encryption {
  /// No server-side encryption.
  none,
  /// SSE-S3: AES-256 managed by S3 (x-amz-server-side-encryption: AES256).
  sseS3,
  /// SSE-KMS: AWS KMS managed key (x-amz-server-side-encryption: aws:kms).
  sseKms,
  /// SSE-C: Customer-provided key (x-amz-server-side-encryption-customer-*).
  sseC,
}

/// S3 storage classes per AWS documentation.
enum S3StorageClass {
  standard,
  standardIa,
  onezoneIa,
  intelligentTiering,
  glacier,
  glacierIr,
  deepArchive,
  reducedRedundancy,
}

extension S3StorageClassX on S3StorageClass {
  String get headerValue {
    switch (this) {
      case S3StorageClass.standard:
        return 'STANDARD';
      case S3StorageClass.standardIa:
        return 'STANDARD_IA';
      case S3StorageClass.onezoneIa:
        return 'ONEZONE_IA';
      case S3StorageClass.intelligentTiering:
        return 'INTELLIGENT_TIERING';
      case S3StorageClass.glacier:
        return 'GLACIER';
      case S3StorageClass.glacierIr:
        return 'GLACIER_IR';
      case S3StorageClass.deepArchive:
        return 'DEEP_ARCHIVE';
      case S3StorageClass.reducedRedundancy:
        return 'REDUCED_REDUNDANCY';
    }
  }

  String get displayName {
    switch (this) {
      case S3StorageClass.standard:
        return 'Standard';
      case S3StorageClass.standardIa:
        return 'Standard-IA';
      case S3StorageClass.onezoneIa:
        return 'One Zone-IA';
      case S3StorageClass.intelligentTiering:
        return 'Intelligent-Tiering';
      case S3StorageClass.glacier:
        return 'Glacier Flexible Retrieval';
      case S3StorageClass.glacierIr:
        return 'Glacier Instant Retrieval';
      case S3StorageClass.deepArchive:
        return 'Glacier Deep Archive';
      case S3StorageClass.reducedRedundancy:
        return 'Reduced Redundancy';
    }
  }

  static S3StorageClass fromHeaderValue(String value) {
    switch (value.toUpperCase()) {
      case 'STANDARD_IA':
        return S3StorageClass.standardIa;
      case 'ONEZONE_IA':
        return S3StorageClass.onezoneIa;
      case 'INTELLIGENT_TIERING':
        return S3StorageClass.intelligentTiering;
      case 'GLACIER':
        return S3StorageClass.glacier;
      case 'GLACIER_IR':
        return S3StorageClass.glacierIr;
      case 'DEEP_ARCHIVE':
        return S3StorageClass.deepArchive;
      case 'REDUCED_REDUNDANCY':
        return S3StorageClass.reducedRedundancy;
      default:
        return S3StorageClass.standard;
    }
  }
}

class S3ClientAdapter extends CloudStorageClient {
  static const _log = Log('S3Client');
  final S3ConfigService _config;

  /// Minimum part size for multipart upload (5MB, S3 minimum)
  static const int multipartThreshold = 5 * 1024 * 1024;
  /// Default part size for multipart upload (8MB)
  static const int defaultPartSize = 8 * 1024 * 1024;

  S3ConfigService get config => _config;

  String? _endpoint;
  String? _region;
  String? _bucket;
  String? _accessKey;
  String? _secretKey;
  bool _authenticated = false;

  /// Server-side encryption mode for uploads.
  S3Encryption encryption = S3Encryption.none;
  /// KMS key ID (for SSE-KMS).
  String? kmsKeyId;
  /// Customer encryption key (base64, for SSE-C).
  String? customerEncryptionKey;
  /// Storage class for new objects.
  S3StorageClass storageClass = S3StorageClass.standard;

  S3ClientAdapter({required dynamic config})
      : _config = (config is S3ConfigService)
            ? config
            : S3ConfigService(configPath: '', secureStorage: InMemorySecureStorage());

  @override
  String get providerName => 'S3';

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated => _authenticated;

  @override
  String? get userId => _accessKey;

  @override
  String? get bucketId => _bucket;

  @override
  bool get supportsMultipart => true;

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsServerSideCopy => true;

  @override
  bool get supportsNativeShare => true;

  // --- Upload header helpers ---

  /// Build extra headers for SSE + storage class on PUT requests.
  Map<String, String> _uploadHeaders({String contentType = 'application/octet-stream'}) {
    final headers = <String, String>{'content-type': contentType};

    // Storage class
    if (storageClass != S3StorageClass.standard) {
      headers['x-amz-storage-class'] = storageClass.headerValue;
    }

    // Server-side encryption
    switch (encryption) {
      case S3Encryption.sseS3:
        headers['x-amz-server-side-encryption'] = 'AES256';
        break;
      case S3Encryption.sseKms:
        headers['x-amz-server-side-encryption'] = 'aws:kms';
        if (kmsKeyId != null && kmsKeyId!.isNotEmpty) {
          headers['x-amz-server-side-encryption-aws-kms-key-id'] = kmsKeyId!;
        }
        break;
      case S3Encryption.sseC:
        if (customerEncryptionKey != null) {
          headers['x-amz-server-side-encryption-customer-algorithm'] = 'AES256';
          headers['x-amz-server-side-encryption-customer-key'] = customerEncryptionKey!;
          // MD5 of the raw key bytes
          final keyBytes = base64.decode(customerEncryptionKey!);
          final keyMd5 = base64.encode(md5.convert(keyBytes).bytes);
          headers['x-amz-server-side-encryption-customer-key-MD5'] = keyMd5;
        }
        break;
      case S3Encryption.none:
        break;
    }

    return headers;
  }

  // --- Addressing helpers ---

  /// Returns true if the endpoint is AWS and virtual-hosted-style should be used.
  bool get _useVirtualHostedStyle =>
      _endpoint != null && _endpoint!.contains('amazonaws.com');

  /// Build the URI for a given object key (or empty for bucket-level operations).
  Uri _buildUri(String key, {Map<String, String>? queryParams}) {
    final ep = _endpoint!;
    final uri = Uri.parse(ep);

    if (_useVirtualHostedStyle) {
      // Virtual-hosted style: https://bucket.s3.region.amazonaws.com/key
      final host = '$_bucket.${uri.host}';
      return Uri(
        scheme: uri.scheme,
        host: host,
        port: uri.hasPort ? uri.port : null,
        path: '/${_cleanKey(key)}',
        queryParameters: queryParams,
      );
    } else {
      // Path style: https://endpoint/bucket/key
      final pathPrefix = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '$pathPrefix$_bucket/${_cleanKey(key)}',
        queryParameters: queryParams,
      );
    }
  }

  /// Build URI for bucket-level operations (listing, etc.).
  Uri _buildBucketUri({Map<String, String>? queryParams}) {
    final ep = _endpoint!;
    final uri = Uri.parse(ep);

    if (_useVirtualHostedStyle) {
      final host = '$_bucket.${uri.host}';
      return Uri(
        scheme: uri.scheme,
        host: host,
        port: uri.hasPort ? uri.port : null,
        path: '/',
        queryParameters: queryParams,
      );
    } else {
      final pathPrefix = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '$pathPrefix$_bucket/',
        queryParameters: queryParams,
      );
    }
  }

  String _cleanKey(String key) {
    if (key.startsWith('/')) return key.substring(1);
    return key;
  }

  /// Convert an app-level path like /photos/cat.jpg to an S3 object key.
  String _pathToKey(String path) {
    var key = path;
    if (key.startsWith('/')) key = key.substring(1);
    return key;
  }

  // --- AWS Signature V4 ---

  /// Sign an HTTP request using AWS Signature V4.
  /// Returns the headers map that should be merged into the request.
  Map<String, String> signRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String payloadHash,
    required DateTime now,
  }) {
    final dateStamp = _formatDateStamp(now); // 20260529
    final amzDate = _formatAmzDate(now); // 20260529T143025Z
    final region = _region ?? 'us-east-1';
    const service = 's3';
    final scope = '$dateStamp/$region/$service/aws4_request';

    // Ensure required headers are present
    final signedHeaders = Map<String, String>.from(headers);
    signedHeaders['host'] = uri.host + (uri.hasPort && uri.port != 443 && uri.port != 80 ? ':${uri.port}' : '');
    signedHeaders['x-amz-date'] = amzDate;
    signedHeaders['x-amz-content-sha256'] = payloadHash;

    // Build canonical headers (lowercase key : trimmed value)
    final canonicalHeaderLines = <String>[];
    final headerMap = <String, String>{};
    for (final key in signedHeaders.keys) {
      headerMap[key.toLowerCase()] = signedHeaders[key]!.trim();
    }
    final sortedKeys = headerMap.keys.toList()..sort();
    for (final key in sortedKeys) {
      canonicalHeaderLines.add('$key:${headerMap[key]}');
    }
    final signedHeaderStr = sortedKeys.join(';');

    final canonicalQueryString = _buildCanonicalQueryString(uri);

    final canonicalRequest = [
      method,
      _canonicalPath(uri),
      canonicalQueryString,
      '${canonicalHeaderLines.join('\n')}\n',
      signedHeaderStr,
      payloadHash,
    ].join('\n');

    // String to sign
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    // Signing key
    final signingKey = _deriveSigningKey(dateStamp, region, service);

    // Signature
    final signature = Hmac(sha256, signingKey)
        .convert(utf8.encode(stringToSign))
        .toString();

    // Authorization header
    final authorization =
        'AWS4-HMAC-SHA256 Credential=$_accessKey/$scope, '
        'SignedHeaders=$signedHeaderStr, '
        'Signature=$signature';

    return {
      ...signedHeaders,
      'Authorization': authorization,
    };
  }

  List<int> _deriveSigningKey(String dateStamp, String region, String service) {
    final kDate = Hmac(sha256, utf8.encode('AWS4$_secretKey'))
        .convert(utf8.encode(dateStamp))
        .bytes;
    final kRegion = Hmac(sha256, kDate).convert(utf8.encode(region)).bytes;
    final kService = Hmac(sha256, kRegion).convert(utf8.encode(service)).bytes;
    final kSigning =
        Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
    return kSigning;
  }

  String _formatDateStamp(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatAmzDate(DateTime dt) {
    return '${_formatDateStamp(dt)}T'
        '${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}Z';
  }

  String _canonicalPath(Uri uri) {
    if (uri.path.isEmpty) return '/';
    // URI-encode each segment individually, then rejoin with leading /
    final encoded = uri.pathSegments
        .map((s) => Uri.encodeComponent(s))
        .join('/');
    final path = '/$encoded';
    // Preserve trailing slash if original had one
    if (uri.path.endsWith('/') && !path.endsWith('/')) return '$path/';
    return path;
  }

  String _buildCanonicalQueryString(Uri uri) {
    if (uri.queryParameters.isEmpty) return '';
    final sorted = uri.queryParameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
  }

  /// Perform a signed HTTP request and return the response.
  Future<http.Response> _signedRequest(
    String method,
    Uri uri, {
    Map<String, String>? extraHeaders,
    List<int>? body,
  }) async {
    final now = DateTime.now().toUtc();
    final payloadHash =
        sha256.convert(body ?? <int>[]).toString();

    final headers = <String, String>{};
    if (extraHeaders != null) headers.addAll(extraHeaders);

    final signed = signRequest(
      method: method,
      uri: uri,
      headers: headers,
      payloadHash: payloadHash,
      now: now,
    );

    final request = http.Request(method, uri);
    request.headers.addAll(signed);
    if (body != null) request.bodyBytes = body;

    final streamed = await http.Client().send(request);
    return http.Response.fromStream(streamed);
  }

  // --- Interface Implementation ---

  @override
  Future<void> login(String email, String password, {String? twoFactorCode}) async {
    // Parse login format: accessKey@endpoint/bucket?region=us-east-1
    // Password is the secretKey.
    final parsed = _parseLoginIdentity(email);
    _accessKey = parsed['accessKey'];
    _endpoint = parsed['endpoint'];
    _bucket = parsed['bucket'];
    _region = parsed['region'] ?? 'us-east-1';
    _secretKey = password;

    if (_accessKey == null || _endpoint == null || _bucket == null || _secretKey == null) {
      throw Exception(
        'Invalid S3 credentials format. '
        'Use: accessKey@endpoint/bucket?region=us-east-1',
      );
    }

    // Save credentials (including encryption + storage class settings)
    await _config.saveCredentials({
      'accessKey': _accessKey!,
      'secretKey': _secretKey!,
      'endpoint': _endpoint!,
      'bucket': _bucket!,
      'region': _region!,
      'encryption': encryption.name,
      if (kmsKeyId != null) 'kmsKeyId': kmsKeyId!,
      'storageClass': storageClass.headerValue,
    });

    // Test connection by listing with max-keys=1
    try {
      final uri = _buildBucketUri(queryParams: {
        'list-type': '2',
        'max-keys': '1',
      });
      final response = await _signedRequest('GET', uri);

      if (response.statusCode != 200) {
        await _config.clearCredentials();
        throw Exception(
          'S3 connection test failed (HTTP ${response.statusCode}): ${response.body}',
        );
      }

      _authenticated = true;
    } catch (e) {
      _authenticated = false;
      _accessKey = null;
      _secretKey = null;
      await _config.clearCredentials();
      rethrow;
    }
  }

  /// Parse the identity string: accessKey@endpoint/bucket?region=us-east-1
  static Map<String, String?> parseLoginIdentity(String identity) {
    return _parseLoginIdentityStatic(identity);
  }

  static Map<String, String?> _parseLoginIdentityStatic(String identity) {
    String? accessKey;
    String? endpoint;
    String? bucket;
    String? region;

    // Split at the first @ to get accessKey and the rest
    final atIdx = identity.indexOf('@');
    if (atIdx < 0) {
      return {'accessKey': null, 'endpoint': null, 'bucket': null, 'region': null};
    }

    accessKey = identity.substring(0, atIdx);
    var rest = identity.substring(atIdx + 1);

    // Extract region from query string if present
    final qIdx = rest.indexOf('?');
    if (qIdx >= 0) {
      final query = rest.substring(qIdx + 1);
      rest = rest.substring(0, qIdx);
      final params = Uri.splitQueryString(query);
      region = params['region'];
    }

    // rest is now endpoint/bucket or just endpoint
    // Find the bucket: last path segment
    // Handle URLs like https://s3.amazonaws.com/mybucket
    // or just s3.amazonaws.com/mybucket
    Uri? parsedUri;
    try {
      if (rest.startsWith('http://') || rest.startsWith('https://')) {
        parsedUri = Uri.parse(rest);
      } else {
        parsedUri = Uri.parse('https://$rest');
      }
    } catch (_) {
      return {'accessKey': accessKey, 'endpoint': null, 'bucket': null, 'region': region};
    }

    final pathSegments = parsedUri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (pathSegments.isNotEmpty) {
      bucket = pathSegments.last;
      // endpoint is the URL without the bucket path segment
      final scheme = rest.startsWith('http://') ? 'http' : 'https';
      final portStr = parsedUri.hasPort && parsedUri.port != 443 && parsedUri.port != 80
          ? ':${parsedUri.port}'
          : '';
      if (pathSegments.length > 1) {
        final basePath = pathSegments.sublist(0, pathSegments.length - 1).join('/');
        endpoint = '$scheme://${parsedUri.host}$portStr/$basePath';
      } else {
        endpoint = '$scheme://${parsedUri.host}$portStr';
      }
    } else {
      // No path segments - bucket might be missing
      final scheme = rest.startsWith('http://') ? 'http' : 'https';
      final portStr = parsedUri.hasPort && parsedUri.port != 443 && parsedUri.port != 80
          ? ':${parsedUri.port}'
          : '';
      endpoint = '$scheme://${parsedUri.host}$portStr';
    }

    return {
      'accessKey': accessKey,
      'endpoint': endpoint,
      'bucket': bucket,
      'region': region,
    };
  }

  Map<String, String?> _parseLoginIdentity(String identity) {
    return _parseLoginIdentityStatic(identity);
  }

  @override
  Future<bool> is2faNeeded(String email) async => false;

  @override
  Future<void> logout() async {
    _authenticated = false;
    _accessKey = null;
    _secretKey = null;
    _endpoint = null;
    _bucket = null;
    _region = null;
    await _config.clearCredentials();
  }

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    _ensureAuth();
    final key = _pathToKey(path);
    if (key.isEmpty) {
      // Root always "exists"
      return {'type': 'folder', 'name': '', 'path': '/', 'uuid': '/'};
    }

    final uri = _buildUri(key);
    try {
      final response = await _signedRequest('HEAD', uri);
      if (response.statusCode == 200) {
        return {
          'type': key.endsWith('/') ? 'folder' : 'file',
          'name': p.basename(key),
          'path': path,
          'size': int.tryParse(response.headers['content-length'] ?? '0') ?? 0,
          'uuid': path,
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    _ensureAuth();
    final prefix = _pathToKey(path);
    final normalizedPrefix = prefix.isEmpty
        ? ''
        : (prefix.endsWith('/') ? prefix : '$prefix/');

    final folders = <Map<String, dynamic>>[];
    final files = <Map<String, dynamic>>[];

    String? continuationToken;

    do {
      final params = <String, String>{
        'list-type': '2',
        'delimiter': '/',
        'max-keys': '1000',
      };
      if (normalizedPrefix.isNotEmpty) {
        params['prefix'] = normalizedPrefix;
      }
      if (continuationToken != null) {
        params['continuation-token'] = continuationToken;
      }

      final uri = _buildBucketUri(queryParams: params);
      final response = await _signedRequest('GET', uri);

      if (response.statusCode != 200) {
        throw Exception('S3 list failed (HTTP ${response.statusCode}): ${response.body}');
      }

      final body = response.body;
      final doc = xml.XmlDocument.parse(body);
      final root = doc.rootElement;

      // Parse CommonPrefixes (folders)
      for (final cp in root.findAllElements('CommonPrefixes')) {
        final prefixEl = cp.findElements('Prefix').firstOrNull;
        if (prefixEl == null) continue;
        final folderPrefix = prefixEl.innerText;
        // Remove the parent prefix to get relative name
        var folderName = folderPrefix;
        if (normalizedPrefix.isNotEmpty && folderName.startsWith(normalizedPrefix)) {
          folderName = folderName.substring(normalizedPrefix.length);
        }
        if (folderName.endsWith('/')) {
          folderName = folderName.substring(0, folderName.length - 1);
        }
        if (folderName.isEmpty) continue;

        folders.add({
          'uuid': '/$folderPrefix',
          'name': folderName,
          'type': 'folder',
          'path': '/$folderPrefix',
        });
      }

      // Parse Contents (files)
      for (final contents in root.findAllElements('Contents')) {
        final keyEl = contents.findElements('Key').firstOrNull;
        final lastModEl = contents.findElements('LastModified').firstOrNull;
        final sizeEl = contents.findElements('Size').firstOrNull;
        if (keyEl == null) continue;

        final key = keyEl.innerText;
        final lastModified = lastModEl?.innerText ?? '';
        final size = int.tryParse(sizeEl?.innerText ?? '0') ?? 0;

        // Skip the prefix itself (folder marker)
        if (key == normalizedPrefix) continue;
        // Skip keys that end with / (folder markers)
        if (key.endsWith('/') && size == 0) continue;

        var fileName = key;
        if (normalizedPrefix.isNotEmpty && fileName.startsWith(normalizedPrefix)) {
          fileName = fileName.substring(normalizedPrefix.length);
        }
        if (fileName.isEmpty) continue;

        files.add({
          'uuid': '/$key',
          'name': fileName,
          'type': 'file',
          'size': size,
          'modificationTime': lastModified,
          'path': '/$key',
        });
      }

      // Check for continuation
      final isTruncatedEl = root.findAllElements('IsTruncated').firstOrNull;
      final isTruncated = isTruncatedEl?.innerText == 'true';
      if (isTruncated) {
        final tokenEl = root.findAllElements('NextContinuationToken').firstOrNull;
        continuationToken = tokenEl?.innerText;
        if (continuationToken == null) break;
      } else {
        continuationToken = null;
      }
    } while (continuationToken != null);

    return {
      'folders': folders,
      'files': files,
    };
  }

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    _ensureAuth();
    final key = _pathToKey(p.posix.join(targetPath, fileName));

    // Use multipart upload for files > 5MB
    if (fileData.length > multipartThreshold) {
      await _multipartUpload(key, fileData, onProgress: onProgress);
      return;
    }

    final uri = _buildUri(key);
    final response = await _signedRequest(
      'PUT',
      uri,
      extraHeaders: _uploadHeaders(),
      body: fileData,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('S3 upload failed (HTTP ${response.statusCode}): ${response.body}');
    }

    onProgress?.call(fileData.length, fileData.length);
  }

  // --- Multipart Upload ---

  /// Initiate a multipart upload and return the upload ID.
  Future<String> _initiateMultipartUpload(String key) async {
    final uri = _buildUri(key, queryParams: {'uploads': ''});
    final response = await _signedRequest(
      'POST',
      uri,
      extraHeaders: _uploadHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('S3 initiate multipart failed (HTTP ${response.statusCode}): ${response.body}');
    }

    final match = RegExp(r'<UploadId>([^<]+)</UploadId>').firstMatch(response.body);
    if (match == null) {
      throw Exception('S3 initiate multipart: no UploadId in response');
    }
    return match.group(1)!;
  }

  /// Upload a single part and return its ETag.
  Future<String> _uploadPart(String key, String uploadId, int partNumber, List<int> partData) async {
    final uri = _buildUri(key, queryParams: {
      'partNumber': partNumber.toString(),
      'uploadId': uploadId,
    });
    final response = await _signedRequest(
      'PUT',
      uri,
      body: partData,
    );

    if (response.statusCode != 200) {
      throw Exception('S3 upload part $partNumber failed (HTTP ${response.statusCode})');
    }

    final etag = response.headers['etag'];
    if (etag == null) {
      throw Exception('S3 upload part $partNumber: no ETag in response');
    }
    return etag;
  }

  /// Complete a multipart upload with the list of part ETags.
  Future<void> _completeMultipartUpload(String key, String uploadId, List<PartETag> parts) async {
    final xmlParts = parts.map((p) =>
      '<Part><PartNumber>${p.partNumber}</PartNumber><ETag>${p.etag}</ETag></Part>'
    ).join();
    final body = '<CompleteMultipartUpload>$xmlParts</CompleteMultipartUpload>';

    final uri = _buildUri(key, queryParams: {'uploadId': uploadId});
    final response = await _signedRequest(
      'POST',
      uri,
      extraHeaders: {'content-type': 'application/xml'},
      body: utf8.encode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('S3 complete multipart failed (HTTP ${response.statusCode}): ${response.body}');
    }
  }

  /// Perform a full multipart upload: initiate, upload parts, complete.
  /// Tracks uploaded parts via SharedPreferences for resume support.
  Future<void> _multipartUpload(
    String key,
    List<int> fileData, {
    Function(int, int)? onProgress,
    int partSize = defaultPartSize,
  }) async {
    final totalSize = fileData.length;
    _log.info('Starting multipart upload: $totalSize bytes, part size: $partSize');

    final uploadId = await _initiateMultipartUpload(key);
    final parts = <PartETag>[];
    int uploaded = 0;

    try {
      int partNumber = 1;
      for (int offset = 0; offset < totalSize; offset += partSize) {
        final end = (offset + partSize > totalSize) ? totalSize : offset + partSize;
        final partData = fileData.sublist(offset, end);

        final etag = await _uploadPart(key, uploadId, partNumber, partData);
        final part = PartETag(partNumber, etag);
        parts.add(part);

        // Track each uploaded part for resume
        await _trackUploadedPart(uploadId, key, part);

        uploaded += partData.length;
        onProgress?.call(uploaded, totalSize);
        partNumber++;
      }

      await _completeMultipartUpload(key, uploadId, parts);
      await _clearUploadTracking(uploadId);
      _log.info('Multipart upload complete: $key ($partNumber parts)');
    } catch (e) {
      _log.error('Multipart upload failed: $key (uploadId=$uploadId)', e);
      // Do NOT abort — keep parts on server so the upload can be resumed.
      // The tracking data is already persisted per-part.
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Multipart resume support
  // ---------------------------------------------------------------------------

  /// SharedPreferences key prefix for multipart upload tracking.
  static const String _multipartTrackingPrefix = 'crisp_s3_multipart_';

  /// In-memory tracking of active multipart uploads for persistence on failure.
  final Map<String, _MultipartTrackingState> _activeMultipartUploads = {};

  /// Track a successfully uploaded part in SharedPreferences.
  Future<void> _trackUploadedPart(String uploadId, String key, PartETag part) async {
    // Update in-memory state
    final state = _activeMultipartUploads.putIfAbsent(
      uploadId,
      () => _MultipartTrackingState(
        uploadId: uploadId,
        bucket: _bucket ?? '',
        key: key,
      ),
    );
    state.parts.add(part);

    // Persist to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode({
        'uploadId': uploadId,
        'bucket': _bucket,
        'key': key,
        'parts': state.parts
            .map((p) => {'partNumber': p.partNumber, 'etag': p.etag})
            .toList(),
      });
      await prefs.setString('$_multipartTrackingPrefix$uploadId', json);
    } catch (e) {
      _log.warn('Failed to persist multipart tracking: $e');
    }
  }

  /// Clear tracking data after a successful upload or explicit abort.
  Future<void> _clearUploadTracking(String uploadId) async {
    _activeMultipartUploads.remove(uploadId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_multipartTrackingPrefix$uploadId');
    } catch (e) {
      _log.warn('Failed to clear multipart tracking: $e');
    }
  }

  /// Persist any active multipart upload state to SharedPreferences.
  /// Called by TransferNotifier when an S3 upload fails mid-multipart.
  Future<void> persistInterruptedUploads() async {
    // In-memory state is already persisted per-part in _trackUploadedPart,
    // so this is a no-op but available as an explicit flush point.
    _log.info('Persisting ${_activeMultipartUploads.length} interrupted uploads');
  }

  /// List parts already uploaded for a multipart upload via the S3 ListParts API.
  Future<List<PartETag>> listParts(String key, String uploadId) async {
    _ensureAuth();
    final parts = <PartETag>[];
    String? partMarker;

    do {
      final params = <String, String>{'uploadId': uploadId};
      if (partMarker != null) {
        params['part-number-marker'] = partMarker;
      }

      final uri = _buildUri(key, queryParams: params);
      final response = await _signedRequest('GET', uri);

      if (response.statusCode != 200) {
        throw Exception(
          'S3 ListParts failed (HTTP ${response.statusCode}): ${response.body}',
        );
      }

      final body = response.body;

      // Parse <Part> elements
      final partMatches = RegExp(
        r'<Part>\s*'
        r'<PartNumber>(\d+)</PartNumber>\s*'
        r'(?:<LastModified>[^<]*</LastModified>\s*)?'
        r'<ETag>([^<]+)</ETag>\s*'
        r'(?:<Size>[^<]*</Size>\s*)?'
        r'</Part>',
      ).allMatches(body);

      for (final match in partMatches) {
        final partNumber = int.parse(match.group(1)!);
        final etag = match.group(2)!;
        parts.add(PartETag(partNumber, etag));
      }

      // Check for truncation
      final isTruncated =
          RegExp(r'<IsTruncated>true</IsTruncated>').hasMatch(body);
      if (isTruncated) {
        final markerMatch = RegExp(
          r'<NextPartNumberMarker>(\d+)</NextPartNumberMarker>',
        ).firstMatch(body);
        partMarker = markerMatch?.group(1);
        if (partMarker == null) break;
      } else {
        partMarker = null;
      }
    } while (partMarker != null);

    return parts;
  }

  /// Retrieve all interrupted multipart uploads from SharedPreferences.
  Future<List<Map<String, dynamic>>> getInterruptedUploads() async {
    final prefs = await SharedPreferences.getInstance();
    final results = <Map<String, dynamic>>[];

    for (final key in prefs.getKeys()) {
      if (key.startsWith(_multipartTrackingPrefix)) {
        final json = prefs.getString(key);
        if (json != null) {
          try {
            results.add(jsonDecode(json) as Map<String, dynamic>);
          } catch (_) {}
        }
      }
    }
    return results;
  }

  /// Resume an interrupted multipart upload.
  ///
  /// Queries the S3 ListParts API to discover which parts are already on the
  /// server, then uploads the remaining parts and completes the upload.
  Future<void> resumeMultipartUpload(
    String remotePath,
    List<int> fileData, {
    Function(int, int)? onProgress,
    int partSize = defaultPartSize,
  }) async {
    _ensureAuth();
    final key = _pathToKey(remotePath);

    // Find the tracked upload for this key
    final interrupted = await getInterruptedUploads();
    final tracked = interrupted.where((u) => u['key'] == key).toList();
    if (tracked.isEmpty) {
      throw Exception('No interrupted upload found for $remotePath');
    }
    final uploadId = tracked.last['uploadId'] as String;
    _log.info('Resuming multipart upload: $key (uploadId=$uploadId)');

    // Query the server for actually uploaded parts
    final existingParts = await listParts(key, uploadId);
    final existingPartNumbers = existingParts.map((p) => p.partNumber).toSet();
    _log.info('Found ${existingParts.length} existing parts on server');

    final totalSize = fileData.length;
    final allParts = <PartETag>[...existingParts];

    // Calculate bytes already uploaded
    int uploaded = 0;
    for (final part in existingParts) {
      final offset = (part.partNumber - 1) * partSize;
      final end = (offset + partSize > totalSize) ? totalSize : offset + partSize;
      uploaded += (end - offset);
    }
    onProgress?.call(uploaded, totalSize);

    try {
      int partNumber = 1;
      for (int offset = 0; offset < totalSize; offset += partSize) {
        if (existingPartNumbers.contains(partNumber)) {
          partNumber++;
          continue;
        }

        final end = (offset + partSize > totalSize) ? totalSize : offset + partSize;
        final partData = fileData.sublist(offset, end);

        final etag = await _uploadPart(key, uploadId, partNumber, partData);
        final part = PartETag(partNumber, etag);
        allParts.add(part);
        await _trackUploadedPart(uploadId, key, part);

        uploaded += partData.length;
        onProgress?.call(uploaded, totalSize);
        partNumber++;
      }

      // Sort parts by part number before completing
      allParts.sort((a, b) => a.partNumber.compareTo(b.partNumber));
      await _completeMultipartUpload(key, uploadId, allParts);
      await _clearUploadTracking(uploadId);
      _log.info('Resumed multipart upload complete: $key');
    } catch (e) {
      _log.error('Resumed multipart upload failed: $key', e);
      rethrow;
    }
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    _ensureAuth();
    final key = _pathToKey(remotePath);

    final uri = _buildUri(key);
    final response = await _signedRequest('GET', uri);

    if (response.statusCode != 200) {
      throw Exception('S3 download failed (HTTP ${response.statusCode}): ${response.body}');
    }

    final bytes = response.bodyBytes;
    onProgress?.call(bytes.length, bytes.length);
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    final bytes = await downloadFileBytes(remotePath, onProgress: onProgress);
    final file = File(localPath);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> createFolderPath(String path) async {
    _ensureAuth();
    var key = _pathToKey(path);
    if (!key.endsWith('/')) key = '$key/';

    final uri = _buildUri(key);
    final response = await _signedRequest(
      'PUT',
      uri,
      extraHeaders: {'content-type': 'application/octet-stream'},
      body: <int>[],
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('S3 create folder failed (HTTP ${response.statusCode}): ${response.body}');
    }
  }

  @override
  Future<void> deletePath(String path) async {
    _ensureAuth();
    final key = _pathToKey(path);

    final uri = _buildUri(key);
    final response = await _signedRequest('DELETE', uri);

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('S3 delete failed (HTTP ${response.statusCode}): ${response.body}');
    }
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    // S3 doesn't have native move. Copy + Delete.
    _ensureAuth();
    final sourceKey = _pathToKey(sourcePath);
    final fileName = p.basename(sourceKey);
    final targetKey = _pathToKey(p.posix.join(targetPath, fileName));

    await _copyObject(sourceKey, targetKey);
    await deletePath(sourcePath);
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    _ensureAuth();
    final sourceKey = _pathToKey(path);
    final parentKey = p.posix.dirname(sourceKey);
    final targetKey = parentKey == '.' ? newName : '$parentKey/$newName';

    await _copyObject(sourceKey, targetKey);
    await deletePath(path);
  }

  @override
  Future<void> copyPath(String sourcePath, String targetPath) async {
    _ensureAuth();
    final sourceKey = _pathToKey(sourcePath);
    final fileName = p.posix.basename(sourceKey);
    final targetKey = _pathToKey(p.posix.join(targetPath, fileName));
    _log.info('Server-side copy: $sourceKey → $targetKey');
    await _copyObject(sourceKey, targetKey);
  }

  Future<void> _copyObject(String sourceKey, String targetKey) async {
    final uri = _buildUri(targetKey);
    final copySource = '/$_bucket/$sourceKey';

    final response = await _signedRequest(
      'PUT',
      uri,
      extraHeaders: {'x-amz-copy-source': copySource},
      body: <int>[],
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('S3 copy failed (HTTP ${response.statusCode}): ${response.body}');
    }
  }

  // ---------------------------------------------------------------------------
  // Presigned URLs
  // ---------------------------------------------------------------------------

  /// Generate a presigned URL for downloading (GET) a remote object.
  /// [expires] defaults to 1 hour.
  String generatePresignedUrl(String remotePath, {Duration? expires}) {
    _ensureAuth();
    final key = _pathToKey(remotePath);
    final expiresSeconds = (expires ?? const Duration(hours: 1)).inSeconds;
    final now = DateTime.now().toUtc();
    final dateStamp = _formatDateStamp(now);
    final amzDate = _formatAmzDate(now);
    final region = _region ?? 'us-east-1';
    const service = 's3';
    final scope = '$dateStamp/$region/$service/aws4_request';
    final uri = _buildUri(key);

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

    final signingKey = _deriveSigningKey(dateStamp, region, service);
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

  /// Generate a presigned PUT URL for uploading.
  /// [expires] defaults to 1 hour.
  String generatePresignedUploadUrl(String remotePath, {Duration? expires}) {
    _ensureAuth();
    final key = _pathToKey(remotePath);
    final expiresSeconds = (expires ?? const Duration(hours: 1)).inSeconds;
    final now = DateTime.now().toUtc();
    final dateStamp = _formatDateStamp(now);
    final amzDate = _formatAmzDate(now);
    final region = _region ?? 'us-east-1';
    const service = 's3';
    final scope = '$dateStamp/$region/$service/aws4_request';
    final uri = _buildUri(key);

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
      'PUT',
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

    final signingKey = _deriveSigningKey(dateStamp, region, service);
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

  // ---------------------------------------------------------------------------
  // Delta Sync — block-level file sync via Range GET + full upload fallback
  // ---------------------------------------------------------------------------

  /// Whether block-level delta sync is enabled for this connection.
  bool deltaSyncEnabled = false;

  final DeltaSyncService _deltaSyncService = DeltaSyncService();

  /// Download a byte range from a remote S3 object.
  Future<Uint8List> downloadRange(String remotePath, int offset, int length) async {
    _ensureAuth();
    final key = _pathToKey(remotePath);
    final uri = _buildUri(key);

    final response = await _signedRequest('GET', uri,
        extraHeaders: {'Range': 'bytes=$offset-${offset + length - 1}'});

    if (response.statusCode != 206 && response.statusCode != 200) {
      throw Exception('S3 range download failed (HTTP ${response.statusCode})');
    }
    return response.bodyBytes;
  }

  /// Get the ETag of a remote S3 object via HEAD request.
  Future<String?> getObjectETag(String remotePath) async {
    _ensureAuth();
    final key = _pathToKey(remotePath);
    final uri = _buildUri(key);

    final response = await _signedRequest('HEAD', uri);
    if (response.statusCode != 200) return null;
    return response.headers['etag']?.replaceAll('"', '');
  }

  /// Orchestrate a delta download: compare remote vs local, download only changed blocks.
  Future<DeltaResult?> deltaDownload(
    String remotePath,
    String localPath, {
    String? cacheDir,
    void Function(int, int, int)? onProgress,
  }) async {
    if (!deltaSyncEnabled) return null;
    _ensureAuth();

    final file = File(localPath);
    if (!file.existsSync()) return null;
    final fileSize = await file.length();
    if (!_deltaSyncService.shouldUseDeltaSync(fileSize)) return null;

    // Compute local block map
    final localMap = await _deltaSyncService.computeBlockMap(localPath);

    // Load cached remote block map
    BlockMap? remoteMap;
    if (cacheDir != null) {
      final cachePath = _deltaSyncService.blockMapCachePath(cacheDir, remotePath, 's3');
      remoteMap = await _deltaSyncService.loadBlockMap(cachePath);

      // Validate against ETag
      if (remoteMap != null) {
        final currentEtag = await getObjectETag(remotePath);
        if (currentEtag == null) remoteMap = null;
      }
    }
    if (remoteMap == null) return null; // Can't diff without remote map

    final delta = _deltaSyncService.compareBlockMaps(remoteMap, localMap);
    if (delta.changedBlocks.isEmpty) return delta;

    // Download changed blocks via Range GET
    final plan = _deltaSyncService.createTransferPlan(
        delta, TransferDirection.download, remoteMap);

    await _deltaSyncService.applyDelta(plan, localPath,
      remoteReadBlock: (blockIndex, offset, size) async {
        return await downloadRange(remotePath, offset, size);
      },
      onProgress: onProgress,
    );

    // Cache updated local map
    if (cacheDir != null) {
      final newMap = await _deltaSyncService.computeBlockMap(localPath);
      final cachePath = _deltaSyncService.blockMapCachePath(cacheDir, remotePath, 's3');
      await _deltaSyncService.saveBlockMap(newMap, cachePath);
    }

    return delta;
  }

  /// Orchestrate a delta upload: compare local vs cached remote, upload only if
  /// the savings justify it. S3 doesn't support partial writes, so we upload
  /// the full file but skip the upload entirely if nothing changed.
  ///
  /// When the cached block map shows changes, we still do a full upload (S3
  /// limitation) but cache the new block map for future comparisons. The savings
  /// come from skipping unnecessary uploads when files haven't changed.
  Future<DeltaResult?> deltaUpload(
    String localPath,
    String remotePath, {
    String? cacheDir,
    void Function(int, int, int)? onProgress,
  }) async {
    if (!deltaSyncEnabled) return null;
    _ensureAuth();

    final file = File(localPath);
    final fileSize = await file.length();
    if (!_deltaSyncService.shouldUseDeltaSync(fileSize)) return null;

    // Load cached remote block map
    BlockMap? remoteMap;
    if (cacheDir != null) {
      final cachePath = _deltaSyncService.blockMapCachePath(cacheDir, remotePath, 's3');
      remoteMap = await _deltaSyncService.loadBlockMap(cachePath);
    }
    if (remoteMap == null) return null; // No cache = can't compare

    final localMap = await _deltaSyncService.computeBlockMap(localPath,
        blockSize: remoteMap.blockSize, onProgress: onProgress);
    final delta = _deltaSyncService.compareBlockMaps(localMap, remoteMap);

    if (delta.changedBlocks.isEmpty) {
      _log.info('Delta sync: $remotePath is identical, skipping upload');
      return delta;
    }

    _log.info('Delta sync: $remotePath has ${delta.changedBlocks.length} changed blocks, uploading full file');

    // S3 doesn't support partial writes — upload the full file
    final bytes = await file.readAsBytes();
    await uploadFile(bytes, p.basename(remotePath), p.dirname(remotePath));

    // Cache new block map
    if (cacheDir != null) {
      final cachePath = _deltaSyncService.blockMapCachePath(cacheDir, remotePath, 's3');
      await _deltaSyncService.saveBlockMap(localMap, cachePath);
    }

    return delta;
  }

  void _ensureAuth() {
    if (!_authenticated || _accessKey == null || _secretKey == null) {
      throw Exception('Not authenticated. Call login() first.');
    }
  }

  /// Attempt to restore credentials from secure storage (for auto-login).
  Future<bool> restoreCredentials() async {
    final creds = await _config.readCredentials();
    if (creds == null) return false;

    _accessKey = creds['accessKey'];
    _secretKey = creds['secretKey'];
    _endpoint = creds['endpoint'];
    _bucket = creds['bucket'];
    _region = creds['region'] ?? 'us-east-1';

    // Restore encryption settings
    final encName = creds['encryption'];
    if (encName != null) {
      encryption = S3Encryption.values.firstWhere(
        (e) => e.name == encName,
        orElse: () => S3Encryption.none,
      );
    }
    kmsKeyId = creds['kmsKeyId'];

    // Restore storage class
    final scValue = creds['storageClass'];
    if (scValue != null) {
      storageClass = S3StorageClassX.fromHeaderValue(scValue);
    }

    if (_accessKey != null && _secretKey != null && _endpoint != null && _bucket != null) {
      _authenticated = true;
      return true;
    }
    return false;
  }
}

/// Helper class for multipart upload part tracking.
class PartETag {
  final int partNumber;
  final String etag;
  PartETag(this.partNumber, this.etag);
}

/// In-memory tracking state for an active multipart upload.
class _MultipartTrackingState {
  final String uploadId;
  final String bucket;
  final String key;
  final List<PartETag> parts = [];

  _MultipartTrackingState({
    required this.uploadId,
    required this.bucket,
    required this.key,
  });
}
