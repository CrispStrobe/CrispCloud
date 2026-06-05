// lib/services/b2_client_adapter.dart
//
// Backblaze B2 native API adapter.
//
// Uses the B2 native HTTP API (NOT the S3-compatible layer), including:
//   b2_authorize_account, b2_list_buckets, b2_list_file_names,
//   b2_get_upload_url, b2_upload_file,
//   b2_start_large_file, b2_get_upload_part_url, b2_upload_part, b2_finish_large_file,
//   b2_download_file_by_name,
//   b2_hide_file, b2_delete_file_version,
//   b2_copy_file
//
// Authentication uses HTTP Basic auth (keyId:applicationKey → Base64).
// All uploads include a SHA1 checksum in X-Bz-Content-Sha1.
// Files > 100 MB are split into parts automatically.
// 429 / 503 responses are retried with Retry-After back-off.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'b2_config_service.dart';
import 'cloud_storage_interface.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';

/// Threshold above which we switch to the large-file (multipart) upload path.
const int _largeFileThreshold = 100 * 1024 * 1024; // 100 MB

/// Minimum part size for large-file uploads (5 MB, B2 minimum).
const int _minPartSize = 5 * 1024 * 1024; // 5 MB

/// Default part size for large-file uploads (10 MB).
const int _defaultPartSize = 10 * 1024 * 1024; // 10 MB

/// Maximum number of auto-retries on 429 / 503.
const int _maxRetries = 5;

class B2ClientAdapter extends CloudStorageClient {
  static final _log = Log('B2Client');

  final B2ConfigService _config;

  B2ConfigService get config => _config;

  // Credentials loaded from config / login call.
  String? _keyId;
  String? _applicationKey;
  String? _bucketId;
  String? _bucketName;
  bool _authenticated = false;

  B2ClientAdapter({required dynamic config})
      : _config = (config is B2ConfigService)
            ? config
            : B2ConfigService(secureStorage: InMemorySecureStorage());

  // ---------------------------------------------------------------------------
  // CloudStorageClient — metadata
  // ---------------------------------------------------------------------------

  @override
  String get providerName => 'Backblaze B2';

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated => _authenticated;

  @override
  String? get userId => _keyId;

  @override
  String? get bucketId => _bucketId;

  // ---------------------------------------------------------------------------
  // Capability flags
  // ---------------------------------------------------------------------------

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsMultipart => true;

  @override
  bool get supportsVersioning => true;

  @override
  bool get supportsSharing => true; // friendly download URLs

  @override
  bool get supportsSearch => false;

  @override
  bool get supportsThumbnails => false;

  @override
  bool get supportsTrash => true; // b2_hide_file = soft delete

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

  /// Login using a Backblaze B2 application key.
  ///
  /// [email]    — the application key ID (keyId)
  /// [password] — the application key secret
  ///
  /// The optional [twoFactorCode] is ignored (B2 does not use 2FA on API keys).
  @override
  Future<void> login(String email, String password,
      {String? twoFactorCode}) async {
    _keyId = email;
    _applicationKey = password;

    await _authorizeAccount();
  }

  @override
  Future<bool> is2faNeeded(String email) async => false;

  @override
  Future<void> logout() async {
    _keyId = null;
    _applicationKey = null;
    _bucketId = null;
    _bucketName = null;
    _authenticated = false;
    _config.clearAuthCache();
    await _config.clearCredentials();
  }

  // ---------------------------------------------------------------------------
  // b2_authorize_account
  // ---------------------------------------------------------------------------

  Future<void> _authorizeAccount() async {
    _log.info('b2_authorize_account for keyId=$_keyId');

    final credentials = base64Encode(utf8.encode('$_keyId:$_applicationKey'));
    final resp = await _retryableGet(
      Uri.parse(
          'https://api.backblazeb2.com/b2api/v3/b2_authorize_account'),
      headers: {
        'Authorization': 'Basic $credentials',
      },
      authRefreshAllowed: false,
    );

    _ensureSuccess(resp, 'b2_authorize_account');

    final body = _decodeJson(resp.body);
    final apiUrl = body['apiInfo']?['storageApi']?['apiUrl'] as String? ??
        body['apiUrl'] as String?;
    final downloadUrl =
        body['apiInfo']?['storageApi']?['downloadUrl'] as String? ??
            body['downloadUrl'] as String?;
    final authToken = body['authorizationToken'] as String?;
    final accountId = body['accountId'] as String?;

    if (apiUrl == null || downloadUrl == null || authToken == null) {
      throw StateError(
          'b2_authorize_account response missing required fields: $body');
    }

    _config.cacheAuthResponse(
      authToken: authToken,
      apiUrl: apiUrl,
      downloadUrl: downloadUrl,
      accountId: accountId ?? '',
    );

    // Save credentials so they can be restored across sessions.
    await _config.saveCredentials(
      keyId: _keyId!,
      applicationKey: _applicationKey!,
      bucketId: _bucketId,
      bucketName: _bucketName,
    );

    _authenticated = true;
    _log.info('B2 authenticated, apiUrl=$apiUrl');
  }

  /// Re-run authorize_account (called after a 401 response).
  Future<void> _refreshAuth() async {
    _log.info('Refreshing B2 auth token');
    _config.clearAuthCache();
    _authenticated = false;
    await _authorizeAccount();
  }

  // ---------------------------------------------------------------------------
  // Path operations
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    final norm = _normalizePath(path);

    // Root or bucket listing
    if (norm.isEmpty || norm == '/') {
      return {'name': '/', 'isFolder': true, 'path': '/'};
    }

    // Try to find a single matching file/folder
    final bucketId = await _resolveBucketId();
    final prefix = norm.startsWith('/') ? norm.substring(1) : norm;

    final result = await _listFileNames(
      bucketId: bucketId,
      prefix: prefix,
      delimiter: '/',
      maxFileCount: 1,
    );

    final files = result['files'] as List<dynamic>? ?? [];
    final folders = result['folders'] as List<dynamic>? ?? [];

    if (files.isNotEmpty) {
      final f = files.first as Map<String, dynamic>;
      return _fileInfoToMap(f);
    }
    if (folders.isNotEmpty) {
      final folderName = folders.first as String;
      return {
        'name': p.basename(folderName.replaceAll(RegExp(r'/$'), '')),
        'isFolder': true,
        'path': '/$folderName',
      };
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    final norm = _normalizePath(path);

    // Root — list buckets
    if (norm.isEmpty || norm == '/') {
      return _listBuckets();
    }

    final bucketId = await _resolveBucketId();
    String prefix = norm.startsWith('/') ? norm.substring(1) : norm;
    if (prefix.isNotEmpty && !prefix.endsWith('/')) {
      prefix = '$prefix/';
    }

    final result = await _listFileNames(
      bucketId: bucketId,
      prefix: prefix,
      delimiter: '/',
    );

    final rawFiles = result['files'] as List<dynamic>? ?? [];
    final rawFolders = result['folders'] as List<dynamic>? ?? [];

    final files = rawFiles
        .map((f) => _fileInfoToMap(f as Map<String, dynamic>))
        .toList();

    final folders = rawFolders.map<Map<String, dynamic>>((f) {
      final folderPath = f as String;
      final name =
          p.basename(folderPath.replaceAll(RegExp(r'/$'), ''));
      return {
        'name': name,
        'isFolder': true,
        'path': '/$folderPath',
        'uuid': folderPath,
      };
    }).toList();

    return {
      'files': [...folders, ...files],
      'nextStartFileName': result['nextFileName'],
    };
  }

  // ---------------------------------------------------------------------------
  // File upload
  // ---------------------------------------------------------------------------

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    final bytes = Uint8List.fromList(fileData);

    if (bytes.length > _largeFileThreshold) {
      await _uploadLargeFile(bytes, fileName, targetPath,
          onProgress: onProgress);
    } else {
      await _uploadSmallFile(bytes, fileName, targetPath,
          onProgress: onProgress);
    }
  }

  Future<void> _uploadSmallFile(
    Uint8List bytes,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    final bucketId = await _resolveBucketId();
    final uploadInfo = await _getUploadUrl(bucketId: bucketId);

    final uploadUrl = uploadInfo['uploadUrl'] as String;
    final uploadAuthToken = uploadInfo['authorizationToken'] as String;

    final b2FileName =
        _buildB2FileName(targetPath, fileName);
    final sha1 = _sha1Hex(bytes);
    final contentType = _guessContentType(fileName);

    _log.debug(
        'Uploading small file $b2FileName (${bytes.length} bytes) sha1=$sha1');

    final resp = await _retryablePost(
      Uri.parse(uploadUrl),
      headers: {
        'Authorization': uploadAuthToken,
        'X-Bz-File-Name': Uri.encodeComponent(b2FileName),
        'Content-Type': contentType,
        'Content-Length': '${bytes.length}',
        'X-Bz-Content-Sha1': sha1,
      },
      body: bytes,
      authRefreshAllowed: true,
    );

    _ensureSuccess(resp, 'b2_upload_file');
    _log.info('Uploaded $b2FileName');

    onProgress?.call(bytes.length, bytes.length);
  }

  // ---------------------------------------------------------------------------
  // Large file upload (> 100 MB)
  // ---------------------------------------------------------------------------

  Future<void> _uploadLargeFile(
    Uint8List bytes,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    final bucketId = await _resolveBucketId();
    final b2FileName = _buildB2FileName(targetPath, fileName);
    final contentType = _guessContentType(fileName);

    _log.info(
        'Starting large file upload for $b2FileName (${bytes.length} bytes)');

    // 1. Start large file
    final startResp = await _callApi('b2_start_large_file', {
      'bucketId': bucketId,
      'fileName': b2FileName,
      'contentType': contentType,
    });
    final fileId = startResp['fileId'] as String;

    // 2. Split into parts
    final partSize = _defaultPartSize.clamp(_minPartSize, bytes.length);
    final partCount = (bytes.length / partSize).ceil();
    final partSha1s = <String>[];
    int uploaded = 0;

    for (int i = 0; i < partCount; i++) {
      final start = i * partSize;
      final end = (start + partSize).clamp(0, bytes.length);
      final part = bytes.sublist(start, end);

      // Get upload part URL
      final partUrlResp = await _callApi('b2_get_upload_part_url', {
        'fileId': fileId,
      });
      final partUploadUrl = partUrlResp['uploadUrl'] as String;
      final partAuthToken = partUrlResp['authorizationToken'] as String;

      final partSha1 = _sha1Hex(part);

      _log.debug(
          'Uploading part ${i + 1}/$partCount size=${part.length} sha1=$partSha1');

      final partResp = await _retryablePost(
        Uri.parse(partUploadUrl),
        headers: {
          'Authorization': partAuthToken,
          'X-Bz-Part-Number': '${i + 1}',
          'Content-Length': '${part.length}',
          'X-Bz-Content-Sha1': partSha1,
        },
        body: part,
        authRefreshAllowed: true,
      );
      _ensureSuccess(partResp, 'b2_upload_part');
      partSha1s.add(partSha1);
      uploaded += part.length;
      onProgress?.call(uploaded, bytes.length);
    }

    // 3. Finish large file
    await _callApi('b2_finish_large_file', {
      'fileId': fileId,
      'partSha1Array': partSha1s,
    });

    _log.info('Large file upload complete: $b2FileName');
  }

  // ---------------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------------

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    final bytes = await downloadFileBytes(remotePath, onProgress: onProgress);
    if (!kIsWeb) {
      await File(localPath).writeAsBytes(bytes);
    }
  }

  @override
  Future<Uint8List> downloadFileBytes(String remotePath,
      {Function(int, int)? onProgress}) async {
    final downloadUrl = _config.getDownloadUrl();
    if (downloadUrl == null) throw StateError('Not authenticated');

    final bucketName = await _resolveBucketName();
    final norm = _normalizePath(remotePath);
    final filePath = norm.startsWith('/') ? norm.substring(1) : norm;

    final url = Uri.parse(
        '$downloadUrl/file/${Uri.encodeComponent(bucketName)}/${_encodeFilePath(filePath)}');

    _log.debug('Downloading $filePath from $url');

    final resp = await _retryableGet(
      url,
      headers: {'Authorization': _config.authToken ?? ''},
      authRefreshAllowed: true,
    );

    _ensureSuccess(resp, 'b2_download_file_by_name');
    onProgress?.call(resp.bodyBytes.length, resp.bodyBytes.length);
    return resp.bodyBytes;
  }

  // ---------------------------------------------------------------------------
  // Folder creation
  // ---------------------------------------------------------------------------

  @override
  Future<void> createFolderPath(String path) async {
    // B2 has no real folders — create a zero-byte file with trailing '/'
    final norm = _normalizePath(path);
    String folderKey = norm.startsWith('/') ? norm.substring(1) : norm;
    if (!folderKey.endsWith('/')) folderKey = '$folderKey/';

    _log.info('Creating B2 folder placeholder: $folderKey');

    final bucketId = await _resolveBucketId();
    final uploadInfo = await _getUploadUrl(bucketId: bucketId);
    final uploadUrl = uploadInfo['uploadUrl'] as String;
    final uploadAuthToken = uploadInfo['authorizationToken'] as String;

    final emptyBytes = Uint8List(0);
    final sha1 = _sha1Hex(emptyBytes);

    final resp = await _retryablePost(
      Uri.parse(uploadUrl),
      headers: {
        'Authorization': uploadAuthToken,
        'X-Bz-File-Name': Uri.encodeComponent(folderKey),
        'Content-Type': 'application/x-directory',
        'Content-Length': '0',
        'X-Bz-Content-Sha1': sha1,
      },
      body: emptyBytes,
      authRefreshAllowed: true,
    );
    _ensureSuccess(resp, 'b2_upload_file (folder placeholder)');
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  /// Soft-delete (hide) a file. Use [hardDelete] to permanently delete a
  /// specific file version.
  @override
  Future<void> deletePath(String path, {bool hardDelete = false}) async {
    final norm = _normalizePath(path);
    final fileKey = norm.startsWith('/') ? norm.substring(1) : norm;

    if (hardDelete) {
      await _deleteFileVersion(fileKey);
    } else {
      await _hideFile(fileKey);
    }
  }

  Future<void> _hideFile(String fileName) async {
    final bucketId = await _resolveBucketId();
    _log.info('Hiding file $fileName in bucket $bucketId');
    await _callApi('b2_hide_file', {
      'bucketId': bucketId,
      'fileName': fileName,
    });
  }

  Future<void> _deleteFileVersion(String fileName) async {
    // To hard-delete we need the fileId — first list to get it.
    final bucketId = await _resolveBucketId();
    final result = await _listFileNames(
      bucketId: bucketId,
      prefix: fileName,
      maxFileCount: 1,
    );
    final files = result['files'] as List<dynamic>? ?? [];
    if (files.isEmpty) {
      throw StateError('File not found for hard delete: $fileName');
    }
    final file = files.first as Map<String, dynamic>;
    final fileId = file['fileId'] as String;
    _log.info('Hard-deleting file $fileName fileId=$fileId');
    await _callApi('b2_delete_file_version', {
      'fileName': fileName,
      'fileId': fileId,
    });
  }

  // ---------------------------------------------------------------------------
  // Move / Rename — copy + delete (B2 has no native rename)
  // ---------------------------------------------------------------------------

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    await copyPath(sourcePath, targetPath);
    await deletePath(sourcePath, hardDelete: true);
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    final parent = p.dirname(path);
    final target = p.join(parent, newName);
    await movePath(path, target);
  }

  // ---------------------------------------------------------------------------
  // Quota
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, int>?> getQuota() async {
    // B2 does not expose a quota endpoint for application keys.
    return null;
  }

  // ---------------------------------------------------------------------------
  // Internal — B2 API helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _callApi(
      String endpoint, Map<String, dynamic> body,
      {bool authRefreshAllowed = true}) async {
    final apiUrl = _config.getApiUrl();
    if (apiUrl == null) throw StateError('Not authenticated');

    final uri = Uri.parse('$apiUrl/b2api/v3/$endpoint');
    final resp = await _retryablePost(
      uri,
      headers: {
        'Authorization': _config.authToken ?? '',
        'Content-Type': 'application/json',
      },
      body: utf8.encode(json.encode(body)),
      authRefreshAllowed: authRefreshAllowed,
    );
    _ensureSuccess(resp, endpoint);
    return _decodeJson(resp.body);
  }

  Future<Map<String, dynamic>> _getUploadUrl({required String bucketId}) async {
    return _callApi('b2_get_upload_url', {'bucketId': bucketId});
  }

  Future<Map<String, dynamic>> _listFileNames({
    required String bucketId,
    String? prefix,
    String? delimiter,
    int? maxFileCount,
    String? startFileName,
  }) async {
    final params = <String, dynamic>{
      'bucketId': bucketId,
      if (prefix != null && prefix.isNotEmpty) 'prefix': prefix,
      if (delimiter != null) 'delimiter': delimiter,
      if (maxFileCount != null) 'maxFileCount': maxFileCount,
      if (startFileName != null) 'startFileName': startFileName,
    };
    final resp = await _callApi('b2_list_file_names', params);

    final files = (resp['files'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .where((f) => f['action'] != 'folder')
        .toList();

    // Extract virtual folders from the response (delimiter-separated entries
    // with action == 'folder').
    final folders = (resp['files'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .where((f) => f['action'] == 'folder')
        .map((f) => f['fileName'] as String? ?? '')
        .toList();

    return {
      'files': files,
      'folders': folders,
      'nextFileName': resp['nextFileName'],
    };
  }

  Future<Map<String, dynamic>> _listBuckets() async {
    final accountId = _config.accountId;
    if (accountId == null || accountId.isEmpty) {
      throw StateError('No accountId — call login first');
    }

    final resp = await _callApi('b2_list_buckets', {
      'accountId': accountId,
    });

    final buckets = (resp['buckets'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((b) => {
              'name': b['bucketName'] as String? ?? '',
              'uuid': b['bucketId'] as String? ?? '',
              'isFolder': true,
              'path': '/${b['bucketName']}',
              'bucketType': b['bucketType'],
            })
        .toList();

    return {'files': buckets};
  }

  // ---------------------------------------------------------------------------
  // Internal — bucket resolution
  // ---------------------------------------------------------------------------

  Future<String> _resolveBucketId() async {
    if (_bucketId != null) return _bucketId!;

    // Try loading from persisted config
    final creds = await _config.readCredentials();
    if (creds != null && creds['bucketId'] != null) {
      _bucketId = creds['bucketId'];
      _bucketName = creds['bucketName'];
      return _bucketId!;
    }

    throw StateError(
        'No bucketId configured. Set it via B2ConfigService.saveCredentials.');
  }

  Future<String> _resolveBucketName() async {
    if (_bucketName != null) return _bucketName!;

    final creds = await _config.readCredentials();
    if (creds != null && creds['bucketName'] != null) {
      _bucketName = creds['bucketName'];
      _bucketId ??= creds['bucketId'];
      return _bucketName!;
    }

    throw StateError(
        'No bucketName configured. Set it via B2ConfigService.saveCredentials.');
  }

  // ---------------------------------------------------------------------------
  // Internal — HTTP with retry on 429 / 503
  // ---------------------------------------------------------------------------

  Future<http.Response> _retryableGet(
    Uri uri, {
    required Map<String, String> headers,
    bool authRefreshAllowed = true,
  }) async {
    int attempt = 0;
    while (true) {
      final resp = await http.get(uri, headers: headers);
      if (resp.statusCode == 401 && authRefreshAllowed && attempt == 0) {
        await _refreshAuth();
        headers = Map.from(headers)
          ..['Authorization'] = _config.authToken ?? '';
        attempt++;
        continue;
      }
      if ((resp.statusCode == 429 || resp.statusCode == 503) &&
          attempt < _maxRetries) {
        final delay = _parseRetryAfter(resp);
        _log.warn(
            'B2 rate-limited (${resp.statusCode}), retrying in ${delay.inSeconds}s '
            '(attempt ${attempt + 1}/$_maxRetries)');
        await Future.delayed(delay);
        attempt++;
        continue;
      }
      return resp;
    }
  }

  Future<http.Response> _retryablePost(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> body,
    bool authRefreshAllowed = true,
  }) async {
    int attempt = 0;
    while (true) {
      final request = http.Request('POST', uri);
      request.headers.addAll(headers);
      request.bodyBytes = Uint8List.fromList(body);
      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode == 401 && authRefreshAllowed && attempt == 0) {
        await _refreshAuth();
        headers = Map.from(headers)
          ..['Authorization'] = _config.authToken ?? '';
        attempt++;
        continue;
      }
      if ((resp.statusCode == 429 || resp.statusCode == 503) &&
          attempt < _maxRetries) {
        final delay = _parseRetryAfter(resp);
        _log.warn(
            'B2 rate-limited (${resp.statusCode}), retrying in ${delay.inSeconds}s '
            '(attempt ${attempt + 1}/$_maxRetries)');
        await Future.delayed(delay);
        attempt++;
        continue;
      }
      return resp;
    }
  }

  // ---------------------------------------------------------------------------
  // Internal — helpers
  // ---------------------------------------------------------------------------

  void _ensureSuccess(http.Response resp, String operation) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = resp.body.length > 500 ? resp.body.substring(0, 500) : resp.body;
      throw StateError(
          'B2 $operation failed with ${resp.statusCode}: $body');
    }
  }

  Map<String, dynamic> _decodeJson(String body) {
    try {
      return json.decode(body) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('B2 response is not valid JSON: $body');
    }
  }

  Duration _parseRetryAfter(http.Response resp) {
    final retryAfter = resp.headers['retry-after'];
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter);
      if (seconds != null) return Duration(seconds: seconds);
    }
    return const Duration(seconds: 5);
  }

  /// Compute hex SHA1 of [bytes].
  static String _sha1Hex(List<int> bytes) {
    return sha1.convert(bytes).toString();
  }

  /// Encode a forward-slash-delimited file path for use in B2 URLs while
  /// preserving the path separators.
  static String _encodeFilePath(String filePath) {
    return filePath
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
  }

  /// Strip leading/trailing slashes and normalise double slashes.
  static String _normalizePath(String path) {
    return path.replaceAll(RegExp(r'/+'), '/').trim();
  }

  /// Combine [targetPath] and [fileName] into a B2 object name.
  static String _buildB2FileName(String targetPath, String fileName) {
    var dir = _normalizePath(targetPath);
    if (dir.startsWith('/')) dir = dir.substring(1);
    if (dir.isEmpty) return fileName;
    if (dir.endsWith('/')) return '$dir$fileName';
    return '$dir/$fileName';
  }

  /// Guess a MIME type from the file extension.
  static String _guessContentType(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    const mime = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'svg': 'image/svg+xml',
      'pdf': 'application/pdf',
      'zip': 'application/zip',
      'gz': 'application/gzip',
      'tar': 'application/x-tar',
      'mp4': 'video/mp4',
      'mp3': 'audio/mpeg',
      'txt': 'text/plain',
      'md': 'text/markdown',
      'html': 'text/html',
      'css': 'text/css',
      'js': 'application/javascript',
      'json': 'application/json',
      'xml': 'application/xml',
      'csv': 'text/csv',
      'dart': 'application/dart',
    };
    return mime[ext] ?? 'application/octet-stream';
  }

  /// Convert a raw B2 fileInfo map to a CrispCloud FileItem-compatible map.
  static Map<String, dynamic> _fileInfoToMap(Map<String, dynamic> info) {
    final fileName = info['fileName'] as String? ?? '';
    final name = p.basename(fileName);
    final size = info['contentLength'] as int? ?? info['size'] as int? ?? 0;
    final uploadTimestamp = info['uploadTimestamp'] as int?;
    final fileId = info['fileId'] as String? ?? '';
    final action = info['action'] as String? ?? 'upload';

    // Extract X-Bz-Info-* metadata
    // The cast must handle Map<dynamic,dynamic> coming from JSON or test literals.
    final rawFileInfo = info['fileInfo'];
    final fileInfo = rawFileInfo is Map
        ? Map<String, dynamic>.from(rawFileInfo)
        : <String, dynamic>{};
    final extra = <String, dynamic>{};
    for (final entry in fileInfo.entries) {
      extra['X-Bz-Info-${entry.key}'] = entry.value;
    }

    return {
      'name': name,
      'uuid': fileId,
      'path': '/$fileName',
      'isFolder': action == 'folder' || fileName.endsWith('/'),
      'size': size,
      if (uploadTimestamp != null)
        'lastModified':
            DateTime.fromMillisecondsSinceEpoch(uploadTimestamp).toIso8601String(),
      'action': action,
      'contentType': info['contentType'],
      'sha1': info['contentSha1'],
      ...extra,
    };
  }

  // ---------------------------------------------------------------------------
  // Public helpers — exposed for unit tests
  // ---------------------------------------------------------------------------

  /// Compute the SHA1 hex digest of the given bytes.
  static String computeSha1(List<int> bytes) => _sha1Hex(bytes);

  /// Public wrapper for [_guessContentType] — used in tests.
  static String publicGuessContentType(String fileName) =>
      _guessContentType(fileName);

  /// Public wrapper for [_buildB2FileName] — used in tests.
  static String publicBuildB2FileName(String targetPath, String fileName) =>
      _buildB2FileName(targetPath, fileName);

  /// Public wrapper for [_normalizePath] — used in tests.
  static String publicNormalizePath(String path) => _normalizePath(path);

  /// Public wrapper for [_fileInfoToMap] — used in tests.
  static Map<String, dynamic> publicFileInfoToMap(
          Map<String, dynamic> info) =>
      _fileInfoToMap(info);
}
