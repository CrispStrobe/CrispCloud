// lib/services/azure_blob_adapter.dart
//
// Azure Blob Storage provider adapter.
//
// Supports three credential modes:
//   1. SAS token  — append ?sv=...&sig=... to every request URL
//   2. Account key — HMAC-SHA256 SharedKey auth header
//   3. Connection string — parsed into name + key
//
// REST API reference: https://docs.microsoft.com/en-us/rest/api/storageservices/blob-service-rest-api
// x-ms-version: 2023-11-03

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'azure_config_service.dart';
import 'cloud_storage_interface.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';

// ────────────────────────────────────────────────────────────────────────────
// Auth mode enum
// ────────────────────────────────────────────────────────────────────────────

enum _AzureAuthMode {
  /// No credentials — guest / public container.
  none,

  /// SAS token appended to every request URL.
  sas,

  /// SharedKey (HMAC-SHA256) signed Authorization header.
  sharedKey,
}

// ────────────────────────────────────────────────────────────────────────────
// Azure Blob tier
// ────────────────────────────────────────────────────────────────────────────

enum AzureBlobTier { hot, cool, cold, archive }

extension AzureBlobTierName on AzureBlobTier {
  String get headerValue {
    switch (this) {
      case AzureBlobTier.hot:
        return 'Hot';
      case AzureBlobTier.cool:
        return 'Cool';
      case AzureBlobTier.cold:
        return 'Cold';
      case AzureBlobTier.archive:
        return 'Archive';
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
// AzureBlobAdapter
// ────────────────────────────────────────────────────────────────────────────

class AzureBlobAdapter extends CloudStorageClient {
  static const _log = Log('AzureBlob');

  /// Azure REST API version used in every request.
  static const _apiVersion = '2023-11-03';

  final AzureConfigService _config;

  // Resolved after login()
  String? _accountName;
  String? _accountKey; // base64-encoded 512-bit key
  String? _sasToken; // raw query string (no leading '?')
  String? _container; // default/active container
  _AzureAuthMode _authMode = _AzureAuthMode.none;
  bool _authenticated = false;

  AzureBlobAdapter({required dynamic config})
      : _config = (config is AzureConfigService)
            ? config
            : AzureConfigService(secureStorage: InMemorySecureStorage());

  // ── CloudStorageClient identity ─────────────────────────────────────────────

  @override
  String get providerName => 'Azure Blob';

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated => _authenticated;

  @override
  String? get userId => _accountName;

  @override
  String? get bucketId => _container;

  // ── Capability flags ────────────────────────────────────────────────────────

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsMultipart => false; // block blobs used instead

  @override
  bool get supportsVersioning => false;

  @override
  bool get supportsSharing => true; // SAS URLs

  @override
  bool get supportsSearch => false;

  @override
  bool get supportsThumbnails => false;

  @override
  bool get supportsTrash => false;

  @override
  bool get supportsServerSideCopy => true;

  // ── Auth ─────────────────────────────────────────────────────────────────────

  @override
  Future<bool> is2faNeeded(String email) async => false;

  /// Log in with saved credentials from [AzureConfigService].
  ///
  /// The [email] parameter is ignored for Azure; all credential data is
  /// expected in the secure store or was injected via [loginWithKey],
  /// [loginWithSas], or [loginWithConnectionString].
  @override
  Future<void> login(String email, String password,
      {String? twoFactorCode}) async {
    _log.info('login: loading saved Azure credentials');
    final creds = await _config.readCredentials();
    if (creds == null) {
      throw Exception('No Azure credentials found. Call a loginWith* helper first.');
    }
    _applyCredentialMap(creds);
  }

  /// Authenticate using account name + account key.
  Future<void> loginWithKey({
    required String accountName,
    required String accountKey,
    String? container,
  }) async {
    final creds = <String, String>{
      'auth_mode': 'sharedKey',
      'account_name': accountName,
      'account_key': accountKey,
      if (container != null) 'container': container,
    };
    await _config.saveCredentials(creds);
    _applyCredentialMap(creds);
  }

  /// Authenticate using a SAS token (raw query string or full SAS URL).
  Future<void> loginWithSas({
    required String accountName,
    required String sasTokenOrUrl,
    String? container,
  }) async {
    // Accept either the raw query string or a full URL; extract token if needed.
    final token = sasTokenOrUrl.startsWith('http')
        ? (AzureConfigService.parseSasToken(sasTokenOrUrl) ?? sasTokenOrUrl)
        : sasTokenOrUrl;
    final creds = <String, String>{
      'auth_mode': 'sas',
      'account_name': accountName,
      'sas_token': token,
      if (container != null) 'container': container,
    };
    await _config.saveCredentials(creds);
    _applyCredentialMap(creds);
  }

  /// Authenticate using a connection string.
  Future<void> loginWithConnectionString({
    required String connectionString,
    String? container,
  }) async {
    final info = AzureConfigService.parseConnectionString(connectionString);
    if (info == null) {
      throw ArgumentError('Invalid Azure connection string');
    }
    final creds = <String, String>{
      'auth_mode': 'sharedKey',
      'account_name': info.accountName,
      'account_key': info.accountKey,
      if (container != null) 'container': container,
    };
    await _config.saveCredentials(creds);
    _applyCredentialMap(creds);
  }

  @override
  Future<void> logout() async {
    await _config.clearCredentials();
    _accountName = null;
    _accountKey = null;
    _sasToken = null;
    _container = null;
    _authMode = _AzureAuthMode.none;
    _authenticated = false;
  }

  // ── Path helpers ─────────────────────────────────────────────────────────────

  /// Splits a logical path into (container, blobName).
  ///
  /// Path conventions:
  ///   /                       → root listing (no container)
  ///   /mycontainer            → container root
  ///   /mycontainer/           → container root
  ///   /mycontainer/folder/f   → container='mycontainer', blob='folder/f'
  ///
  /// If a default container is set and the path does NOT look like it contains
  /// one, the default is used.
  ({String? container, String blob}) _splitPath(String path) {
    // Strip leading slash
    var p = path.startsWith('/') ? path.substring(1) : path;
    // Strip trailing slash
    if (p.endsWith('/')) p = p.substring(0, p.length - 1);

    if (p.isEmpty) return (container: null, blob: '');

    final slash = p.indexOf('/');
    if (slash < 0) {
      // Single segment — treat as container name, no blob
      return (container: p, blob: '');
    }
    final container = p.substring(0, slash);
    final blob = p.substring(slash + 1);
    return (container: container, blob: blob);
  }

  /// Build the effective container for a request, preferring [pathContainer]
  /// then the configured default.
  String _effectiveContainer(String? pathContainer) {
    final c = pathContainer ?? _container;
    if (c == null || c.isEmpty) {
      throw StateError('No container specified and no default container configured');
    }
    return c;
  }

  // ── URL / URI construction ────────────────────────────────────────────────────

  String get _baseEndpoint =>
      AzureConfigService.getEndpoint(_accountName ?? '');

  /// Build a URI for a blob or container-level operation.
  ///
  /// [container] — the container name (required unless listing service root).
  /// [blob]       — the blob name within the container (optional).
  /// [queryParams] — extra query params to add.
  Uri _buildUri(
    String? container, {
    String? blob,
    Map<String, String>? queryParams,
  }) {
    final sb = StringBuffer(_baseEndpoint);
    if (container != null && container.isNotEmpty) {
      sb.write('/');
      sb.write(Uri.encodeComponent(container));
    }
    if (blob != null && blob.isNotEmpty) {
      sb.write('/');
      // Encode each segment separately to preserve '/' separators
      sb.write(blob.split('/').map(Uri.encodeComponent).join('/'));
    }

    final allParams = <String, String>{};
    if (queryParams != null) allParams.addAll(queryParams);

    // SAS mode: append token params
    if (_authMode == _AzureAuthMode.sas && _sasToken != null) {
      final tokenParams = Uri.splitQueryString(_sasToken!);
      allParams.addAll(tokenParams);
    }

    final uri = Uri.parse(sb.toString());
    if (allParams.isNotEmpty) {
      return uri.replace(queryParameters: {...uri.queryParameters, ...allParams});
    }
    return uri;
  }

  // ── Request signing ──────────────────────────────────────────────────────────

  /// Returns the standard headers required on every Azure Blob REST request.
  Map<String, String> _baseHeaders({
    String? contentType,
    int? contentLength,
    Map<String, String>? extra,
  }) {
    final now = DateTime.now().toUtc();
    final headers = <String, String>{
      'x-ms-version': _apiVersion,
      'x-ms-date': _httpDate(now),
      if (contentType != null) 'Content-Type': contentType,
      if (contentLength != null) 'Content-Length': '$contentLength',
    };
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  /// RFC 1123 date format expected by Azure.
  static String _httpDate(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${days[dt.weekday - 1]}, '
        '${dt.day.toString().padLeft(2, '0')} '
        '${months[dt.month - 1]} '
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')} '
        'GMT';
  }

  /// Add an Authorization header for SharedKey authentication.
  ///
  /// See: https://docs.microsoft.com/en-us/rest/api/storageservices/authorize-with-shared-key
  void _addSharedKeyAuth(
    Map<String, String> headers,
    String method,
    Uri uri,
    List<int> body,
  ) {
    if (_authMode != _AzureAuthMode.sharedKey) return;

    final contentLength = body.isEmpty ? '' : '${body.length}';
    final contentType = headers['Content-Type'] ?? '';
    const date = ''; // x-ms-date takes precedence; leave this empty
    final msDate = headers['x-ms-date'] ?? '';

    // Canonicalized headers: sort x-ms-* headers (lowercase), newline-delimited
    final msHeaders = headers.entries
        .where((e) => e.key.toLowerCase().startsWith('x-ms-'))
        .toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    final canonicalizedHeaders = msHeaders
        .map((e) => '${e.key.toLowerCase()}:${e.value}')
        .join('\n');

    // Canonicalized resource
    final account = _accountName!;
    final pathPart = uri.path; // already percent-encoded
    final canonicalizedResource = StringBuffer('/$account$pathPart');
    if (uri.queryParameters.isNotEmpty) {
      final sortedParams = uri.queryParameters.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final kv in sortedParams) {
        canonicalizedResource.write('\n${kv.key}:${kv.value}');
      }
    }

    final stringToSign = [
      method.toUpperCase(),
      '', // Content-Encoding
      '', // Content-Language
      contentLength,
      '', // Content-MD5
      contentType,
      date, // Date (empty — using x-ms-date)
      '', // If-Modified-Since
      '', // If-Match
      '', // If-None-Match
      '', // If-Unmodified-Since
      '', // Range
      canonicalizedHeaders,
      canonicalizedResource.toString(),
    ].join('\n');

    final keyBytes = base64.decode(_accountKey!);
    final hmac = Hmac(sha256, keyBytes);
    final signature = base64.encode(hmac.convert(utf8.encode(stringToSign)).bytes);

    headers['Authorization'] = 'SharedKey $account:$signature';
  }

  // ── HTTP helpers ─────────────────────────────────────────────────────────────

  Future<http.Response> _get(Uri uri, {Map<String, String>? extraHeaders}) async {
    final headers = _baseHeaders(extra: extraHeaders);
    _addSharedKeyAuth(headers, 'GET', uri, const []);
    _log.debug('GET $uri');
    final response = await http.get(uri, headers: headers);
    _checkStatus(response);
    return response;
  }

  Future<http.Response> _put(
    Uri uri,
    List<int> body, {
    Map<String, String>? extraHeaders,
  }) async {
    final headers = _baseHeaders(
      contentLength: body.length,
      extra: extraHeaders,
    );
    _addSharedKeyAuth(headers, 'PUT', uri, body);
    _log.debug('PUT $uri (${body.length} bytes)');
    final response =
        await http.put(uri, headers: headers, body: Uint8List.fromList(body));
    _checkStatus(response);
    return response;
  }

  Future<http.Response> _delete(Uri uri) async {
    final headers = _baseHeaders();
    _addSharedKeyAuth(headers, 'DELETE', uri, const []);
    _log.debug('DELETE $uri');
    final response = await http.delete(uri, headers: headers);
    _checkStatus(response);
    return response;
  }

  Future<http.Response> _head(Uri uri) async {
    final headers = _baseHeaders();
    _addSharedKeyAuth(headers, 'HEAD', uri, const []);
    _log.debug('HEAD $uri');
    // http package doesn't have head(); use a Request
    final request = http.Request('HEAD', uri)..headers.addAll(headers);
    final streamed = await request.send();
    return await http.Response.fromStream(streamed);
  }

  void _checkStatus(http.Response resp) {
    if (resp.statusCode >= 400) {
      throw Exception(
          'Azure Blob error ${resp.statusCode}: ${resp.reasonPhrase}\n${resp.body}');
    }
  }

  // ── XML parsing helpers ──────────────────────────────────────────────────────

  /// Extracts all occurrences of a tag value from a simple (flat) XML string.
  /// e.g. _xmlValues('<Name>a</Name><Name>b</Name>', 'Name') → ['a', 'b']
  static List<String> _xmlValues(String xml, String tag) {
    final results = <String>[];
    final pattern = RegExp('<$tag>(.*?)</$tag>', dotAll: true);
    for (final match in pattern.allMatches(xml)) {
      results.add(match.group(1) ?? '');
    }
    return results;
  }

  /// Extracts the first occurrence of a tag value.
  static String? _xmlValue(String xml, String tag) {
    final m = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml);
    return m?.group(1);
  }

  /// Parses an EnumerationResults XML blob into a list/folder structure.
  ///
  /// Returns: { 'files': [...], 'folders': [...] }
  static Map<String, dynamic> _parseEnumerationResults(String xml) {
    final files = <Map<String, dynamic>>[];
    final folders = <Map<String, dynamic>>[];

    // ── Virtual directories (Prefix elements inside BlobPrefix) ──
    final prefixPattern =
        RegExp(r'<BlobPrefix>(.*?)</BlobPrefix>', dotAll: true);
    for (final match in prefixPattern.allMatches(xml)) {
      final block = match.group(1) ?? '';
      final name = _xmlValue(block, 'Name') ?? '';
      // Remove trailing '/' from virtual directory name
      final cleanName = name.endsWith('/') ? name.substring(0, name.length - 1) : name;
      // Strip leading path to get the leaf segment
      final leaf = cleanName.contains('/')
          ? cleanName.split('/').last
          : cleanName;
      folders.add({
        'name': leaf,
        'path': name, // full prefix
        'isFolder': true,
      });
    }

    // ── Blobs ──
    final blobPattern = RegExp(r'<Blob>(.*?)</Blob>', dotAll: true);
    for (final match in blobPattern.allMatches(xml)) {
      final block = match.group(1) ?? '';
      final name = _xmlValue(block, 'Name') ?? '';
      final sizeStr = _xmlValue(block, 'Content-Length') ?? '0';
      final lastModified = _xmlValue(block, 'Last-Modified');
      final contentType = _xmlValue(block, 'Content-Type');
      final tier = _xmlValue(block, 'AccessTier');

      final leaf = name.contains('/') ? name.split('/').last : name;
      files.add({
        'name': leaf,
        'path': name,
        'size': int.tryParse(sizeStr) ?? 0,
        if (lastModified != null) 'lastModified': lastModified,
        if (contentType != null) 'contentType': contentType,
        if (tier != null) 'tier': tier,
        'isFolder': false,
      });
    }

    return {'files': files, 'folders': folders};
  }

  /// Parses a ListContainersResult XML blob into a list of container names.
  static List<Map<String, dynamic>> _parseContainerList(String xml) {
    final containers = <Map<String, dynamic>>[];
    final containerPattern =
        RegExp(r'<Container>(.*?)</Container>', dotAll: true);
    for (final match in containerPattern.allMatches(xml)) {
      final block = match.group(1) ?? '';
      final name = _xmlValue(block, 'Name') ?? '';
      final lastModified = _xmlValue(block, 'Last-Modified');
      containers.add({
        'name': name,
        'path': '/$name',
        'isFolder': true,
        if (lastModified != null) 'lastModified': lastModified,
      });
    }
    return containers;
  }

  // ── CloudStorageClient — path resolution ─────────────────────────────────────

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    final (:container, :blob) = _splitPath(path);

    if (container == null) {
      // Root path — always "exists"
      return {'name': '/', 'isFolder': true, 'path': '/'};
    }

    if (blob.isEmpty) {
      // Container existence — GET ?restype=container
      try {
        final uri = _buildUri(
          container,
          queryParams: {'restype': 'container'},
        );
        await _get(uri);
        return {'name': container, 'isFolder': true, 'path': '/$container'};
      } catch (_) {
        return null;
      }
    }

    // Blob existence — HEAD request
    try {
      final uri = _buildUri(container, blob: blob);
      final resp = await _head(uri);
      if (resp.statusCode == 200) {
        final sizeStr = resp.headers['content-length'] ?? '0';
        return {
          'name': blob.contains('/') ? blob.split('/').last : blob,
          'path': '/$container/$blob',
          'size': int.tryParse(sizeStr) ?? 0,
          'isFolder': false,
          if (resp.headers['last-modified'] != null)
            'lastModified': resp.headers['last-modified'],
        };
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── CloudStorageClient — listing ──────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    final (:container, :blob) = _splitPath(path);

    // Root: list containers
    if (container == null) {
      return _listContainers();
    }

    // Container or sub-folder: list blobs with prefix + delimiter
    return _listBlobs(
      _effectiveContainer(container),
      prefix: blob.isEmpty ? null : (blob.endsWith('/') ? blob : '$blob/'),
    );
  }

  Future<Map<String, dynamic>> _listContainers() async {
    final uri = _buildUri(null, queryParams: {'comp': 'list'});
    final resp = await _get(uri);
    final containers = _parseContainerList(resp.body);
    return {
      'files': <Map<String, dynamic>>[],
      'folders': containers,
      'path': '/',
    };
  }

  Future<Map<String, dynamic>> _listBlobs(
    String container, {
    String? prefix,
  }) async {
    final params = <String, String>{
      'restype': 'container',
      'comp': 'list',
      'delimiter': '/',
    };
    if (prefix != null && prefix.isNotEmpty) params['prefix'] = prefix;

    final uri = _buildUri(container, queryParams: params);
    final resp = await _get(uri);
    final result = _parseEnumerationResults(resp.body);
    result['path'] = prefix != null ? '/$container/$prefix' : '/$container/';
    return result;
  }

  // ── CloudStorageClient — upload ───────────────────────────────────────────────

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
    AzureBlobTier? tier,
  }) async {
    final (:container, :blob) = _splitPath(targetPath);
    final c = _effectiveContainer(container);
    // If targetPath points to a "folder" (ends with /), append the file name
    final blobName = blob.isEmpty
        ? fileName
        : (blob.endsWith('/') ? '$blob$fileName' : blob);

    final extraHeaders = <String, String>{
      'x-ms-blob-type': 'BlockBlob',
    };
    if (tier != null) {
      extraHeaders['x-ms-access-tier'] = tier.headerValue;
    }

    final uri = _buildUri(c, blob: blobName);
    await _put(uri, fileData, extraHeaders: extraHeaders);
    onProgress?.call(fileData.length, fileData.length);
  }

  // ── CloudStorageClient — download ─────────────────────────────────────────────

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
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    final (:container, :blob) = _splitPath(remotePath);
    final c = _effectiveContainer(container);
    if (blob.isEmpty) throw ArgumentError('Cannot download a container as a file');

    final uri = _buildUri(c, blob: blob);
    final resp = await _get(uri);
    final bytes = resp.bodyBytes;
    onProgress?.call(bytes.length, bytes.length);
    return bytes;
  }

  // ── CloudStorageClient — folders ──────────────────────────────────────────────

  /// Azure Blob Storage uses virtual directories via prefixes.
  /// Folder creation is a no-op — the "folder" will appear once a blob with
  /// that prefix is uploaded.
  @override
  Future<void> createFolderPath(String path) async {
    _log.debug('createFolderPath: no-op for Azure Blob (virtual directories)');
    // No-op
  }

  // ── CloudStorageClient — delete ───────────────────────────────────────────────

  @override
  Future<void> deletePath(String path) async {
    final (:container, :blob) = _splitPath(path);
    final c = _effectiveContainer(container);

    if (blob.isEmpty) {
      // Deleting the container itself
      final uri = _buildUri(c, queryParams: {'restype': 'container'});
      await _delete(uri);
      return;
    }

    // Check if it's a virtual directory (prefix): list and delete all blobs
    // under the prefix; or delete a single blob.
    // Heuristic: if path ends with '/', treat as prefix.
    if (path.endsWith('/')) {
      await _deleteByPrefix(c, '$blob/');
    } else {
      final uri = _buildUri(c, blob: blob);
      await _delete(uri);
    }
  }

  Future<void> _deleteByPrefix(String container, String prefix) async {
    // List all blobs with this prefix (no delimiter) and delete each
    final params = <String, String>{
      'restype': 'container',
      'comp': 'list',
      'prefix': prefix,
    };
    final uri = _buildUri(container, queryParams: params);
    final resp = await _get(uri);
    final names = _xmlValues(resp.body, 'Name');
    for (final name in names) {
      final delUri = _buildUri(container, blob: name);
      await _delete(delUri);
    }
  }

  // ── CloudStorageClient — move / rename ────────────────────────────────────────

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    await _serverCopyBlob(sourcePath, targetPath);
    await deletePath(sourcePath);
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    final parts = path.split('/');
    parts[parts.length - 1] = newName;
    final newPath = parts.join('/');
    await movePath(path, newPath);
  }

  @override
  Future<void> copyPath(String sourcePath, String targetPath) async {
    await _serverCopyBlob(sourcePath, targetPath);
  }

  Future<void> _serverCopyBlob(String sourcePath, String targetPath) async {
    final srcParts = _splitPath(sourcePath);
    final dstParts = _splitPath(targetPath);
    final sourceBlob = srcParts.blob;
    final destBlob = dstParts.blob;

    final sc = _effectiveContainer(srcParts.container);
    final dc = _effectiveContainer(dstParts.container);

    if (sourceBlob.isEmpty || destBlob.isEmpty) {
      throw ArgumentError('Source and target must be blob paths, not container roots');
    }

    // Build the copy-source URL (without auth — source must be accessible)
    final sourceUri = _buildUri(sc, blob: sourceBlob);
    final destUri = _buildUri(dc, blob: destBlob);

    final headers = _baseHeaders(extra: {
      'x-ms-copy-source': sourceUri.toString(),
    });
    _addSharedKeyAuth(headers, 'PUT', destUri, const []);

    _log.debug('Copy blob $sourcePath → $targetPath');
    final response = await http.put(destUri, headers: headers);
    _checkStatus(response);
  }

  // ── Blob tier ─────────────────────────────────────────────────────────────────

  /// Set the access tier of an existing blob.
  Future<void> setBlobTier(String blobPath, AzureBlobTier tier) async {
    final (:container, :blob) = _splitPath(blobPath);
    final c = _effectiveContainer(container);
    if (blob.isEmpty) throw ArgumentError('blobPath must point to a blob');

    final uri = _buildUri(c, blob: blob, queryParams: {'comp': 'tier'});
    final headers = _baseHeaders(extra: {
      'x-ms-access-tier': tier.headerValue,
    });
    _addSharedKeyAuth(headers, 'PUT', uri, const []);

    final response = await http.put(uri, headers: headers);
    if (response.statusCode != 200 && response.statusCode != 202) {
      throw Exception(
          'setBlobTier error ${response.statusCode}: ${response.body}');
    }
  }

  // ── Streaming overrides ───────────────────────────────────────────────────────

  @override
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async* {
    final (:container, :blob) = _splitPath(remotePath);
    final c = _effectiveContainer(container);
    if (blob.isEmpty) throw ArgumentError('Cannot stream a container');

    final uri = _buildUri(c, blob: blob);
    final headers = _baseHeaders();
    _addSharedKeyAuth(headers, 'GET', uri, const []);

    final request = http.Request('GET', uri)..headers.addAll(headers);
    final streamed = await request.send();
    if (streamed.statusCode >= 400) {
      throw Exception('Azure download stream error ${streamed.statusCode}');
    }

    int received = 0;
    final total = streamed.contentLength ?? 0;

    await for (final chunk in streamed.stream) {
      received += chunk.length;
      onProgress?.call(received, total);
      yield chunk;
    }
  }

  @override
  Future<void> uploadStream(
    Stream<List<int>> dataStream,
    int length,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    // Buffer to memory (block blob max 5 GB fits in practice for most uploads;
    // for very large files the caller should use block blob staging instead).
    final builder = BytesBuilder(copy: false);
    await for (final chunk in dataStream) {
      builder.add(chunk);
    }
    await uploadFile(builder.takeBytes(), fileName, targetPath,
        onProgress: onProgress);
  }

  // ── Private helpers ───────────────────────────────────────────────────────────

  void _applyCredentialMap(Map<String, String> creds) {
    _accountName = creds['account_name'];
    _container = creds['container'];

    final mode = creds['auth_mode'] ?? 'none';
    switch (mode) {
      case 'sharedKey':
        _accountKey = creds['account_key'];
        _authMode = _AzureAuthMode.sharedKey;
        break;
      case 'sas':
        _sasToken = creds['sas_token'];
        _authMode = _AzureAuthMode.sas;
        break;
      default:
        _authMode = _AzureAuthMode.none;
    }

    if (_accountName == null || _accountName!.isEmpty) {
      throw StateError('Azure credentials missing account_name');
    }
    _authenticated = true;
    _log.info('Azure Blob authenticated [$mode] account=$_accountName');
  }
}
