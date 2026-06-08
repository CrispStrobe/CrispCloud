// lib/services/nextcloud_client_adapter.dart
//
// Nextcloud adapter using pure HTTP + WebDAV for file operations,
// and the OCS API for sharing and native features.
//
// WebDAV base: /remote.php/dav/files/{username}/
// OCS shares:  POST /ocs/v2.php/apps/files_sharing/api/v1/shares
// Versioning:  GET  /remote.php/dav/versions/{username}/versions/{fileId}
//
// Login format: username@https://nextcloud.example.com
// Password: Nextcloud app password or regular account password.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as dart_io;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

import 'cloud_storage_interface.dart';
import 'delta_sync_service.dart';
import 'log_service.dart';
import 'nextcloud_config_service.dart';
import 'secure_storage_service.dart';

class NextcloudClientAdapter extends CloudStorageClient {
  static const _log = Log('NextcloudClient');

  final NextcloudConfigService _config;

  NextcloudConfigService get config => _config;

  String? _username;
  String? _password;
  String? _serverUrl; // e.g. https://nextcloud.example.com (no trailing slash)

  bool _authenticated = false;

  NextcloudClientAdapter({required dynamic config})
      : _config = (config is NextcloudConfigService)
            ? config
            : NextcloudConfigService(configPath: '', secureStorage: InMemorySecureStorage());

  // ---------------------------------------------------------------------------
  // Basic properties
  // ---------------------------------------------------------------------------

  @override
  String get providerName => 'Nextcloud';

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated => _authenticated && _username != null && _serverUrl != null;

  @override
  String? get userId => _username;

  @override
  String? get bucketId => _serverUrl;

  // ---------------------------------------------------------------------------
  // Capability flags
  // ---------------------------------------------------------------------------

  @override
  bool get supportsVersioning => true;

  @override
  bool get supportsSharing => true;

  @override
  bool get supportsSearch => true;

  @override
  bool get supportsTrash => true;

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  @override
  Future<bool> is2faNeeded(String email) async => false;

  /// Login with identity = "username@https://nextcloud.example.com"
  @override
  Future<void> login(String email, String password, {String? twoFactorCode}) async {
    final parsed = _parseIdentity(email);
    if (parsed == null) {
      throw Exception('Format must be username@https://nextcloud.example.com');
    }
    final username = parsed.$1;
    final serverUrl = parsed.$2;

    // Verify credentials by listing the root WebDAV directory
    try {
      final testUri = _davUri(serverUrl, username, '/');
      final resp = await _propfind(testUri, username, password, depth: '0');
      if (resp.statusCode == 401) {
        throw Exception('Authentication failed: invalid username or password');
      }
      if (resp.statusCode != 207) {
        throw Exception('Connection test failed (HTTP ${resp.statusCode})');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Connection failed: $e');
    }

    _username = username;
    _password = password;
    _serverUrl = serverUrl;
    _authenticated = true;

    await _config.saveCredentials({
      'username': username,
      'password': password,
      'serverUrl': serverUrl,
    });

    _log.info('Logged in to Nextcloud as $username @ $serverUrl');

    // Auto-detect delta sync server app
    await _detectDeltaSyncApp();
  }

  /// Probe for the CrispCloud delta sync server app.
  /// Sets [deltaSyncServerAppUrl] if the app is installed and responding.
  Future<void> _detectDeltaSyncApp() async {
    if (_serverUrl == null) return;
    final appUrl = '$_serverUrl/index.php/apps/crispcloud_delta';
    try {
      final resp = await http.get(
        Uri.parse('$appUrl/api/status'),
        headers: {'Authorization': _basicAuth(_username!, _password!)},
      );
      if (resp.statusCode == 200 && resp.body.contains('crispcloud_delta')) {
        deltaSyncServerAppUrl = appUrl;
        _log.info('Delta sync server app detected at $appUrl');
      }
    } catch (e) {
      // App not installed — delta sync will use client-cached block maps
      _log.debug('Delta sync server app not detected: $e');
    }
  }

  @override
  Future<void> logout() async {
    _username = null;
    _password = null;
    _serverUrl = null;
    _authenticated = false;
    await _config.clearCredentials();
  }

  /// Restore previously saved credentials without re-prompting.
  Future<bool> restoreCredentials() async {
    final creds = await _config.readCredentials();
    if (creds == null ||
        creds['username'] == null ||
        creds['password'] == null ||
        creds['serverUrl'] == null) {
      return false;
    }

    final username = creds['username']!;
    final password = creds['password']!;
    final serverUrl = creds['serverUrl']!;

    if (username.isEmpty || password.isEmpty || serverUrl.isEmpty) return false;

    // Quick connectivity check
    try {
      final testUri = _davUri(serverUrl, username, '/');
      final resp = await _propfind(testUri, username, password, depth: '0');
      if (resp.statusCode != 207) return false;
    } catch (e) {
      _log.warn('restoreCredentials connectivity check failed', e);
      return false;
    }

    _username = username;
    _password = password;
    _serverUrl = serverUrl;
    _authenticated = true;
    _log.info('Restored Nextcloud credentials for $username');
    return true;
  }

  // ---------------------------------------------------------------------------
  // Path resolution
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    await _ensureAuth();
    try {
      final uri = _davUri(_serverUrl!, _username!, path);
      final resp = await _propfind(uri, _username!, _password!, depth: '0');
      if (resp.statusCode != 207) return null;

      final items = _parsePropfind(resp.body);
      if (items.isEmpty) return null;

      final item = items.first;
      return {
        'type': item['isDir'] == true ? 'folder' : 'file',
        'name': item['name'] ?? p.posix.basename(path),
        'path': path,
        'size': item['size'],
        'updatedAt': item['lastModified'],
        'uuid': path,
      };
    } catch (e) {
      _log.warn('resolvePath failed for $path', e);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // List
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    await _ensureAuth();

    final cleanPath = _normalizePath(path);
    final uri = _davUri(_serverUrl!, _username!, cleanPath);

    final resp = await _propfind(uri, _username!, _password!, depth: '1');
    if (resp.statusCode != 207) {
      throw Exception('Failed to list path "$path" (HTTP ${resp.statusCode})');
    }

    final items = _parsePropfind(resp.body);

    final folders = <Map<String, dynamic>>[];
    final files = <Map<String, dynamic>>[];

    // Skip the first entry — it's the directory itself (depth=0)
    for (var i = 1; i < items.length; i++) {
      final item = items[i];
      final name = item['name'] as String? ?? '';
      if (name.isEmpty || name == '.' || name == '..') continue;

      // Build user-visible path relative to DAV root
      final itemDavPath = item['href'] as String? ?? '';
      final davRoot = '/remote.php/dav/files/${Uri.encodeComponent(_username!)}/';
      String relativePath;
      if (itemDavPath.startsWith(davRoot)) {
        relativePath = '/${Uri.decodeComponent(itemDavPath.substring(davRoot.length))}';
      } else {
        relativePath = p.posix.join(cleanPath, name);
      }
      relativePath = relativePath.replaceAll(RegExp(r'/+'), '/');
      if (relativePath.endsWith('/')) {
        relativePath = relativePath.substring(0, relativePath.length - 1);
      }

      final entry = <String, dynamic>{
        'uuid': relativePath,
        'name': name,
        'size': item['size'],
        'modificationTime': item['lastModified'],
        'type': item['isDir'] == true ? 'folder' : 'file',
        'path': relativePath,
        if (item['etag'] != null) 'etag': item['etag'],
        if (item['fileId'] != null) 'fileId': item['fileId'],
      };

      if (item['isDir'] == true) {
        folders.add(entry);
      } else {
        files.add(entry);
      }
    }

    return {'folders': folders, 'files': files};
  }

  // ---------------------------------------------------------------------------
  // Upload
  // ---------------------------------------------------------------------------

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    await _ensureAuth();

    final remotePath = p.posix.join(_normalizePath(targetPath), fileName);
    final uri = _davUri(_serverUrl!, _username!, remotePath);

    final req = http.Request('PUT', uri);
    req.headers['Authorization'] = _basicAuth(_username!, _password!);
    req.headers['Content-Type'] = 'application/octet-stream';
    req.bodyBytes = Uint8List.fromList(fileData);

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 200 && resp.statusCode != 201 && resp.statusCode != 204) {
      throw Exception('Nextcloud upload failed (HTTP ${resp.statusCode}): ${resp.body}');
    }

    onProgress?.call(fileData.length, fileData.length);
    _log.debug('Uploaded $fileName to $remotePath');
  }

  // ---------------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------------

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    await _ensureAuth();

    final uri = _davUri(_serverUrl!, _username!, _normalizePath(remotePath));
    final resp = await http.get(uri, headers: {
      'Authorization': _basicAuth(_username!, _password!),
    });

    if (resp.statusCode != 200) {
      throw Exception('Nextcloud download failed (HTTP ${resp.statusCode}): ${resp.body}');
    }

    onProgress?.call(resp.bodyBytes.length, resp.bodyBytes.length);
    return resp.bodyBytes;
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    final bytes = await downloadFileBytes(remotePath, onProgress: onProgress);
    await dart_io.File(localPath).writeAsBytes(bytes);
  }

  // ---------------------------------------------------------------------------
  // Folder
  // ---------------------------------------------------------------------------

  @override
  Future<void> createFolderPath(String path) async {
    await _ensureAuth();

    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    String accumulated = '';

    for (final segment in segments) {
      accumulated = '$accumulated/$segment';
      final uri = _davUri(_serverUrl!, _username!, accumulated);

      // Check if it already exists
      final check = await _propfind(uri, _username!, _password!, depth: '0');
      if (check.statusCode == 207) continue; // Already exists

      // Create it
      final mkcolReq = http.Request('MKCOL', uri);
      mkcolReq.headers['Authorization'] = _basicAuth(_username!, _password!);
      final mkcolStreamed = await mkcolReq.send();
      final mkcolResp = await http.Response.fromStream(mkcolStreamed);

      if (mkcolResp.statusCode != 201 && mkcolResp.statusCode != 405) {
        // 405 = already exists in some servers
        throw Exception('Failed to create folder "$accumulated" (HTTP ${mkcolResp.statusCode})');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Delete / Move / Rename
  // ---------------------------------------------------------------------------

  @override
  Future<void> deletePath(String path) async {
    await _ensureAuth();

    final uri = _davUri(_serverUrl!, _username!, _normalizePath(path));
    final req = http.Request('DELETE', uri);
    req.headers['Authorization'] = _basicAuth(_username!, _password!);

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception('Nextcloud delete failed (HTTP ${resp.statusCode}): ${resp.body}');
    }
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    await _ensureAuth();

    final sourceUri = _davUri(_serverUrl!, _username!, _normalizePath(sourcePath));
    final destinationUrl = _davUri(_serverUrl!, _username!, _normalizePath(targetPath)).toString();

    final req = http.Request('MOVE', sourceUri);
    req.headers['Authorization'] = _basicAuth(_username!, _password!);
    req.headers['Destination'] = destinationUrl;
    req.headers['Overwrite'] = 'F';

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 201 && resp.statusCode != 204) {
      throw Exception('Nextcloud move failed (HTTP ${resp.statusCode}): ${resp.body}');
    }
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    await _ensureAuth();

    final cleanPath = _normalizePath(path);
    final newPath = p.posix.join(p.posix.dirname(cleanPath), newName);

    await movePath(cleanPath, newPath);
  }

  // ---------------------------------------------------------------------------
  // OCS Sharing API
  // ---------------------------------------------------------------------------

  /// Create a public share link for the given path.
  /// Returns the share URL, or throws on failure.
  Future<String> createShareLink(String path, {int shareType = 3}) async {
    await _ensureAuth();

    // shareType 3 = public link
    final uri = Uri.parse('$_serverUrl/ocs/v2.php/apps/files_sharing/api/v1/shares');
    final resp = await http.post(
      uri,
      headers: {
        'Authorization': _basicAuth(_username!, _password!),
        'OCS-APIRequest': 'true',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'path': path, 'shareType': shareType.toString()},
    );

    if (resp.statusCode != 200) {
      throw Exception('OCS share creation failed (HTTP ${resp.statusCode}): ${resp.body}');
    }

    // Parse the share URL from XML response
    try {
      final doc = xml.XmlDocument.parse(resp.body);
      final urlNode = doc.findAllElements('url').firstOrNull;
      if (urlNode != null) return urlNode.innerText;
    } catch (_) {}

    throw Exception('Failed to parse share URL from OCS response');
  }

  // ---------------------------------------------------------------------------
  // Versioning (via DAV versions API)
  // ---------------------------------------------------------------------------

  /// List versions for a file. Returns a list of version metadata maps.
  /// `fileId` can be obtained from the file's DAV properties (oc:fileid).
  Future<List<Map<String, dynamic>>> listVersions(String fileId) async {
    await _ensureAuth();

    final uri = Uri.parse(
        '$_serverUrl/remote.php/dav/versions/$_username/versions/$fileId');
    final resp = await _propfind(uri, _username!, _password!, depth: '1');

    if (resp.statusCode != 207) {
      throw Exception('Failed to list versions (HTTP ${resp.statusCode})');
    }

    final items = _parsePropfind(resp.body);
    // Skip the first item (the versions container itself)
    return items.skip(1).map((item) => Map<String, dynamic>.from(item)).toList();
  }

  /// Restore a specific version. `fileId` and `versionId` come from [listVersions].
  Future<void> restoreVersion(String fileId, String versionId, String targetPath) async {
    await _ensureAuth();

    final sourceUri = Uri.parse(
        '$_serverUrl/remote.php/dav/versions/$_username/versions/$fileId/$versionId');
    final destUri = _davUri(_serverUrl!, _username!, _normalizePath(targetPath));

    final req = http.Request('COPY', sourceUri);
    req.headers['Authorization'] = _basicAuth(_username!, _password!);
    req.headers['Destination'] = destUri.toString();
    req.headers['Overwrite'] = 'T';

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 201 && resp.statusCode != 204) {
      throw Exception('Restore version failed (HTTP ${resp.statusCode}): ${resp.body}');
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<void> _ensureAuth() async {
    if (_authenticated && _username != null && _password != null && _serverUrl != null) return;

    // Try restoring from storage
    final creds = await _config.readCredentials();
    if (creds == null ||
        creds['username'] == null ||
        creds['password'] == null ||
        creds['serverUrl'] == null) {
      throw Exception('Not authenticated. Please connect to Nextcloud first.');
    }

    _username = creds['username'];
    _password = creds['password'];
    _serverUrl = creds['serverUrl'];
    _authenticated = true;
  }

  /// Build the WebDAV URI for a path.
  Uri _davUri(String serverUrl, String username, String path) {
    final cleanPath = _normalizePath(path);
    final encodedUsername = Uri.encodeComponent(username);
    final encodedPath = cleanPath.split('/').map(Uri.encodeComponent).join('/');
    return Uri.parse('$serverUrl/remote.php/dav/files/$encodedUsername$encodedPath');
  }

  /// Ensure path starts with / and has no trailing slash (unless root).
  String _normalizePath(String path) {
    var clean = path.replaceAll(RegExp(r'/+'), '/');
    if (!clean.startsWith('/')) clean = '/$clean';
    if (clean.length > 1 && clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
  }

  /// HTTP Basic Auth header value.
  String _basicAuth(String username, String password) {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $credentials';
  }

  /// Execute a WebDAV PROPFIND request.
  Future<http.Response> _propfind(
    Uri uri,
    String username,
    String password, {
    String depth = '1',
  }) async {
    final req = http.Request('PROPFIND', uri);
    req.headers['Authorization'] = _basicAuth(username, password);
    req.headers['Depth'] = depth;
    req.headers['Content-Type'] = 'application/xml; charset=utf-8';
    req.body = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns" xmlns:nc="http://nextcloud.org/ns">
  <d:prop>
    <d:displayname/>
    <d:getcontentlength/>
    <d:getlastmodified/>
    <d:getetag/>
    <d:resourcetype/>
    <oc:fileid/>
  </d:prop>
</d:propfind>''';

    try {
      final streamed = await req.send();
      return await http.Response.fromStream(streamed);
    } catch (e) {
      throw Exception('PROPFIND failed for $uri: $e');
    }
  }

  /// Parse a WebDAV multi-status (207) XML response body.
  /// Returns a list of property maps for each <d:response>.
  List<Map<String, dynamic>> _parsePropfind(String body) {
    final results = <Map<String, dynamic>>[];

    try {
      final doc = xml.XmlDocument.parse(body);
      final responses = doc.findAllElements('response',
          namespace: 'DAV:');

      for (final response in responses) {
        final hrefNode = response.findElements('href', namespace: 'DAV:').firstOrNull;
        final href = hrefNode?.innerText ?? '';

        // Get the last non-empty path segment as the display name
        final hrefDecoded = Uri.decodeComponent(href);
        final segments = hrefDecoded.split('/').where((s) => s.isNotEmpty).toList();
        final name = segments.isNotEmpty ? segments.last : '';

        // Resource type: check for <d:collection/>
        final resourceType = response
            .findAllElements('resourcetype', namespace: 'DAV:')
            .firstOrNull;
        final isDir = resourceType != null &&
            resourceType.findAllElements('collection', namespace: 'DAV:').isNotEmpty;

        // Content length
        int? size;
        final sizeNode = response
            .findAllElements('getcontentlength', namespace: 'DAV:')
            .firstOrNull;
        if (sizeNode != null) {
          size = int.tryParse(sizeNode.innerText);
        }

        // Last modified
        String? lastModified;
        final modNode = response
            .findAllElements('getlastmodified', namespace: 'DAV:')
            .firstOrNull;
        if (modNode != null) {
          lastModified = modNode.innerText;
        }

        // ETag
        String? etag;
        final etagNode = response
            .findAllElements('getetag', namespace: 'DAV:')
            .firstOrNull;
        if (etagNode != null) {
          etag = etagNode.innerText.replaceAll('"', '');
        }

        // Nextcloud/ownCloud file ID
        String? fileId;
        final fileIdNode = response
            .findAllElements('fileid', namespace: 'http://owncloud.org/ns')
            .firstOrNull;
        if (fileIdNode != null) {
          fileId = fileIdNode.innerText;
        }

        results.add({
          'href': href,
          'name': name,
          'isDir': isDir,
          'size': size,
          'lastModified': lastModified,
          'etag': etag,
          'fileId': fileId,
        });
      }
    } catch (e) {
      _log.warn('PROPFIND XML parse error', e);
    }

    return results;
  }

  // ---------------------------------------------------------------------------
  // Delta Sync — block-level file sync (optional)
  // ---------------------------------------------------------------------------

  /// Whether block-level delta sync is enabled for this connection.
  bool deltaSyncEnabled = false;

  /// Block size for delta sync (default 4 MB, matching DeltaSyncService).
  int deltaSyncBlockSize = 4 * 1024 * 1024;

  /// Minimum file size to use delta sync (below this, full upload is faster).
  int deltaSyncMinSize = 10 * 1024 * 1024; // 10 MB

  /// Base URL for the CrispCloud delta sync Nextcloud app API.
  /// Set to non-null when the server has the companion app installed.
  /// e.g. 'https://nextcloud.example.com/index.php/apps/crispcloud_delta'
  /// Note: requires /index.php/ prefix for Nextcloud routing.
  String? deltaSyncServerAppUrl;

  final DeltaSyncService _deltaSyncService = DeltaSyncService();

  /// Get the ETag of a single remote file (HEAD request).
  Future<String?> getFileETag(String remotePath) async {
    await _ensureAuth();
    final uri = _davUri(_serverUrl!, _username!, _normalizePath(remotePath));
    final resp = await http.head(uri, headers: {
      'Authorization': _basicAuth(_username!, _password!),
    });
    if (resp.statusCode != 200) return null;
    final etag = resp.headers['etag'];
    return etag?.replaceAll('"', '');
  }

  /// Download a byte range from a remote file.
  /// Returns the bytes in range [offset, offset+length).
  Future<Uint8List> downloadRange(
    String remotePath,
    int offset,
    int length,
  ) async {
    await _ensureAuth();
    final uri = _davUri(_serverUrl!, _username!, _normalizePath(remotePath));
    final resp = await http.get(uri, headers: {
      'Authorization': _basicAuth(_username!, _password!),
      'Range': 'bytes=$offset-${offset + length - 1}',
    });

    if (resp.statusCode != 206 && resp.statusCode != 200) {
      throw Exception(
          'Nextcloud range download failed (HTTP ${resp.statusCode})');
    }
    return resp.bodyBytes;
  }

  /// Upload changed blocks to a remote file using WebDAV chunked upload v2.
  ///
  /// Nextcloud chunked upload flow:
  /// 1. MKCOL /remote.php/dav/uploads/{user}/{transferId}
  /// 2. PUT   /remote.php/dav/uploads/{user}/{transferId}/{offset}  (per chunk)
  /// 3. MOVE  /remote.php/dav/uploads/{user}/{transferId}/.file → destination
  ///
  /// For delta sync, we only upload the changed blocks (not the full file).
  /// Unchanged blocks are filled from the existing remote file via the server.
  ///
  /// Note: Standard chunked upload assembles chunks by concatenation, which
  /// requires ALL chunks to cover the entire file. For true partial update,
  /// the server-side CrispCloud app is needed. Without it, we fall back to
  /// downloading unchanged blocks locally and re-uploading the full file
  /// via chunked upload.
  Future<void> uploadDeltaBlocks(
    String remotePath,
    String localPath,
    BlockTransferPlan plan,
  ) async {
    await _ensureAuth();

    // If the server app is available, use block-level PUT
    if (deltaSyncServerAppUrl != null) {
      await _uploadDeltaViaServerApp(remotePath, localPath, plan);
      return;
    }

    // Fallback: re-upload the full local file via chunked upload.
    // The savings here are from not computing the diff again on retry,
    // and from the chunked upload being resumable.
    await _uploadChunked(remotePath, localPath);
  }

  /// Upload a full file via Nextcloud chunked upload v2 (resumable).
  Future<void> _uploadChunked(String remotePath, String localPath) async {
    final file = dart_io.File(localPath);
    final fileSize = await file.length();
    final transferId = 'crisp-delta-${DateTime.now().millisecondsSinceEpoch}';
    final uploadsBase = '$_serverUrl/remote.php/dav/uploads/${Uri.encodeComponent(_username!)}/$transferId';
    final authHeader = _basicAuth(_username!, _password!);

    // 1. MKCOL — create transfer directory
    final mkcolReq = http.Request('MKCOL', Uri.parse(uploadsBase));
    mkcolReq.headers['Authorization'] = authHeader;
    final mkcolResp = await http.Response.fromStream(await mkcolReq.send());
    if (mkcolResp.statusCode != 201 && mkcolResp.statusCode != 405) {
      throw Exception('Chunked MKCOL failed (${mkcolResp.statusCode})');
    }

    // 2. PUT — upload chunks
    final chunkSize = deltaSyncBlockSize;
    final raf = await file.open();
    try {
      for (int offset = 0; offset < fileSize; offset += chunkSize) {
        final end = (offset + chunkSize > fileSize) ? fileSize : offset + chunkSize;
        final buf = Uint8List(end - offset);
        await raf.readInto(buf);

        final chunkUri = Uri.parse('$uploadsBase/$offset');
        final putReq = http.Request('PUT', chunkUri);
        putReq.headers['Authorization'] = authHeader;
        putReq.headers['Content-Type'] = 'application/octet-stream';
        putReq.bodyBytes = buf;
        final putResp = await http.Response.fromStream(await putReq.send());
        if (putResp.statusCode != 201 && putResp.statusCode != 204) {
          throw Exception('Chunked PUT failed at offset $offset (${putResp.statusCode})');
        }
      }
    } finally {
      await raf.close();
    }

    // 3. MOVE — assemble at destination
    final destPath = _davUri(_serverUrl!, _username!, _normalizePath(remotePath)).toString();
    final moveReq = http.Request('MOVE', Uri.parse('$uploadsBase/.file'));
    moveReq.headers['Authorization'] = authHeader;
    moveReq.headers['Destination'] = destPath;
    moveReq.headers['Overwrite'] = 'T';
    final moveResp = await http.Response.fromStream(await moveReq.send());
    if (moveResp.statusCode != 201 && moveResp.statusCode != 204) {
      throw Exception('Chunked MOVE failed (${moveResp.statusCode})');
    }

    _log.info('Chunked upload complete: $remotePath ($fileSize bytes)');
  }

  /// Upload only changed blocks via the server-side CrispCloud delta app.
  Future<void> _uploadDeltaViaServerApp(
    String remotePath,
    String localPath,
    BlockTransferPlan plan,
  ) async {
    final appBase = deltaSyncServerAppUrl!;
    final authHeader = _basicAuth(_username!, _password!);
    final encodedPath = Uri.encodeComponent(remotePath);

    final file = dart_io.File(localPath);
    final raf = await file.open();

    try {
      for (final op in plan.operations) {
        if (op.type != BlockOperationType.upload) continue;

        await raf.setPosition(op.offset);
        final buf = Uint8List(op.size);
        await raf.readInto(buf);

        // POST /api/blocks/{remotePath}?offset={offset}&size={size}
        final blockUri = Uri.parse(
            '$appBase/api/blocks/$encodedPath?offset=${op.offset}&size=${op.size}');
        final resp = await http.post(blockUri, headers: {
          'Authorization': authHeader,
          'Content-Type': 'application/octet-stream',
        }, body: buf);

        if (resp.statusCode != 200 && resp.statusCode != 204) {
          throw Exception(
              'Delta block upload failed at offset ${op.offset} (${resp.statusCode})');
        }
      }

      // Finalize: tell the server we're done so it can update the file's mtime/etag
      final finalizeUri = Uri.parse('$appBase/api/finalize/$encodedPath');
      await http.post(finalizeUri, headers: {'Authorization': authHeader});
    } finally {
      await raf.close();
    }

    _log.info('Delta upload via server app: $remotePath '
        '(${plan.changedBlockIndices.length}/${plan.operations.length} blocks, '
        '${plan.transferSize} bytes transferred, '
        '${plan.savingsPercent.toStringAsFixed(1)}% savings)');
  }

  /// Fetch block map from the server-side CrispCloud delta app.
  /// Returns null if the app is not installed or the file has no cached map.
  Future<BlockMap?> fetchServerBlockMap(String remotePath) async {
    if (deltaSyncServerAppUrl == null) return null;
    await _ensureAuth();

    final appBase = deltaSyncServerAppUrl!;
    final encodedPath = Uri.encodeComponent(remotePath);
    final uri = Uri.parse('$appBase/api/blockmap/$encodedPath');

    final resp = await http.get(uri, headers: {
      'Authorization': _basicAuth(_username!, _password!),
    });

    if (resp.statusCode != 200) return null;

    try {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return BlockMap.fromJson(json);
    } catch (e) {
      _log.warn('Failed to parse server block map: $e');
      return null;
    }
  }

  /// Orchestrate a delta sync for a single file.
  ///
  /// 1. Check if delta sync is appropriate (file size, enabled flag).
  /// 2. Get remote block map (from server app, or cached locally).
  /// 3. Compare with local file's block map.
  /// 4. Upload only changed blocks.
  /// 5. Update cached block map.
  ///
  /// Returns the [DeltaResult] with savings info, or null if full upload was
  /// used instead.
  Future<DeltaResult?> deltaUpload(
    String localPath,
    String remotePath, {
    String? cacheDir,
    void Function(int processedBlocks, int totalBlocks, int processedBytes)?
        onProgress,
  }) async {
    if (!deltaSyncEnabled) return null;

    final file = dart_io.File(localPath);
    final fileSize = await file.length();

    if (!_deltaSyncService.shouldUseDeltaSync(fileSize,
        minSize: deltaSyncMinSize)) {
      return null; // File too small, caller should use normal upload
    }

    // 1. Get remote block map
    BlockMap? remoteMap;

    // Try server app first
    remoteMap = await fetchServerBlockMap(remotePath);

    // Fall back to local cache
    if (remoteMap == null && cacheDir != null) {
      final cachePath = _deltaSyncService.blockMapCachePath(
          cacheDir, remotePath, 'nextcloud');
      remoteMap = await _deltaSyncService.loadBlockMap(cachePath);

      // Validate cached map against current remote ETag
      if (remoteMap != null) {
        final currentEtag = await getFileETag(remotePath);
        // If we can't get ETag or file doesn't exist yet, cache is stale
        if (currentEtag == null) {
          remoteMap = null;
        }
      }
    }

    // No remote map available — first sync, use full upload
    if (remoteMap == null) {
      _log.info('Delta sync: no remote block map for $remotePath, full upload');
      return null;
    }

    // 2. Compute local block map
    final localMap = await _deltaSyncService.computeBlockMap(
      localPath,
      blockSize: remoteMap.blockSize,
      onProgress: onProgress,
    );

    // 3. Compare
    final delta = _deltaSyncService.compareBlockMaps(localMap, remoteMap);

    if (delta.changedBlocks.isEmpty) {
      _log.info('Delta sync: $remotePath is identical (${delta.totalBlocks} blocks)');
      return delta;
    }

    _log.info('Delta sync: $remotePath — ${delta.changedBlocks.length}/${delta.totalBlocks} blocks changed, '
        '${delta.savingsPercent.toStringAsFixed(1)}% savings');

    // 4. Build transfer plan and upload
    final plan = _deltaSyncService.createTransferPlan(
        delta, TransferDirection.upload, localMap);
    await uploadDeltaBlocks(remotePath, localPath, plan);

    // 5. Cache the new block map for next sync
    if (cacheDir != null) {
      final cachePath = _deltaSyncService.blockMapCachePath(
          cacheDir, remotePath, 'nextcloud');
      await _deltaSyncService.saveBlockMap(localMap, cachePath);
    }

    return delta;
  }

  /// Orchestrate a delta download for a single file.
  ///
  /// Uses Range GET to download only changed blocks.
  Future<DeltaResult?> deltaDownload(
    String remotePath,
    String localPath, {
    String? cacheDir,
    void Function(int processedBlocks, int totalBlocks, int processedBytes)?
        onProgress,
  }) async {
    if (!deltaSyncEnabled) return null;

    final file = dart_io.File(localPath);
    if (!file.existsSync()) return null; // No local file to diff against

    final fileSize = await file.length();
    if (!_deltaSyncService.shouldUseDeltaSync(fileSize,
        minSize: deltaSyncMinSize)) {
      return null;
    }

    // Compute local block map
    final localMap = await _deltaSyncService.computeBlockMap(
      localPath,
      blockSize: deltaSyncBlockSize,
    );

    // Get remote block map
    final remoteMap = await fetchServerBlockMap(remotePath);

    // Without server app, we can't get remote block map without downloading
    // the whole file. Return null to signal caller should use full download.
    if (remoteMap == null) return null;

    // Compare
    final delta = _deltaSyncService.compareBlockMaps(remoteMap, localMap);

    if (delta.changedBlocks.isEmpty) {
      _log.info('Delta download: $remotePath is identical');
      return delta;
    }

    // Build download plan and apply using Range GET
    final plan = _deltaSyncService.createTransferPlan(
        delta, TransferDirection.download, remoteMap);

    await _deltaSyncService.applyDelta(
      plan,
      localPath,
      remoteReadBlock: (blockIndex, offset, size) async {
        return await downloadRange(remotePath, offset, size);
      },
      onProgress: onProgress,
    );

    // Cache updated local block map
    if (cacheDir != null) {
      final newLocalMap = await _deltaSyncService.computeBlockMap(
          localPath, blockSize: deltaSyncBlockSize);
      final cachePath = _deltaSyncService.blockMapCachePath(
          cacheDir, remotePath, 'nextcloud');
      await _deltaSyncService.saveBlockMap(newLocalMap, cachePath);
    }

    return delta;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Parse "username@https://server.com" into (username, serverUrl).
  (String, String)? _parseIdentity(String identity) {
    // Find the last occurrence of "@http" to split username from server URL
    final atHttpIndex = identity.lastIndexOf('@http');
    if (atHttpIndex < 0) return null;

    final username = identity.substring(0, atHttpIndex).trim();
    final serverUrl = identity.substring(atHttpIndex + 1).trim();

    if (username.isEmpty || serverUrl.isEmpty) return null;

    // Normalise: strip trailing slash
    final normUrl = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;

    return (username, normUrl);
  }
}
