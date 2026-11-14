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
import 'package:http_parser/http_parser.dart' show parseHttpDate;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

import 'cloud_storage_interface.dart';
import 'bounded_http_transfer.dart';
import 'bounded_transfer_stream.dart';
import 'transfer_stream_request.dart';
import 'transfer_spool.dart';
import 'spooled_http_upload.dart';
import 'delta_sync_service.dart';
import 'log_service.dart';
import 'nextcloud_config_service.dart';
import 'secure_storage_service.dart';
import './connection_failure.dart';
import './nextcloud_operation_failure.dart';
import 'nextcloud_browser_failure.dart';

class NextcloudAuthenticationException implements Exception {
  const NextcloudAuthenticationException();

  @override
  String toString() =>
      'Authentication failed. Check your username and password. '
      'If your account uses two-factor authentication, create an app password '
      'in Nextcloud security settings.';
}

class NextcloudClientAdapter extends CloudStorageClient
    with CloudTransferOperations {
  @override
  bool get supportsStreaming => true;
  @override
  StorageTransferCapabilities get transferCapabilities =>
      const StorageTransferCapabilities(
        boundedUpload: true,
        boundedDownload: true,
      );
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
          : NextcloudConfigService(
              configPath: '',
              secureStorage: InMemorySecureStorage(),
            );

  // ---------------------------------------------------------------------------
  // Basic properties
  // ---------------------------------------------------------------------------

  @override
  String get providerName => 'Nextcloud';

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated =>
      _authenticated && _username != null && _serverUrl != null;

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
  Future<void> login(
    String email,
    String password, {
    String? twoFactorCode,
  }) async {
    final parsed = _parseIdentity(email);
    if (parsed == null) {
      throw NextcloudOperationFailure(
        NextcloudOperationCode.invalidIdentity,
        'Format must be username@https://nextcloud.example.com',
      );
    }
    final username = parsed.$1;
    final serverUrl = parsed.$2;

    // Verify credentials by listing the root WebDAV directory
    try {
      final testUri = _davUri(serverUrl, username, '/');
      final resp = await _propfind(testUri, username, password, depth: '0');
      if (resp.statusCode == 401) {
        throw const NextcloudAuthenticationException();
      }
      if (resp.statusCode != 207) {
        throw ConnectionFailure(
          ConnectionFailureCode.nextcloudHttp,
          'Connection test failed (HTTP ${resp.statusCode})',
          {'status': resp.statusCode},
        );
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw NextcloudOperationFailure(
        NextcloudOperationCode.connectionFailed,
        'Connection failed: $e',
        {'error': e},
      );
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
      throw NextcloudOperationFailure(
        NextcloudOperationCode.list,
        'Failed to list path "$path" (HTTP ${resp.statusCode})',
        {'path': path, 'status': resp.statusCode},
      );
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
      final davRoot =
          '/remote.php/dav/files/${Uri.encodeComponent(_username!)}/';
      String relativePath;
      if (itemDavPath.startsWith(davRoot)) {
        relativePath =
            '/${Uri.decodeComponent(itemDavPath.substring(davRoot.length))}';
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
  }) => uploadStream(
    Stream.value(fileData),
    fileData.length,
    fileName,
    targetPath,
    onProgress: onProgress,
  );

  void Function() _captureTransfer() {
    final user = _username, password = _password, server = _serverUrl;
    void check() {
      if (!isAuthenticated ||
          user != _username ||
          password != _password ||
          server != _serverUrl) {
        throw StateError(
          'The original Nextcloud account is no longer available.',
        );
      }
    }

    check();
    return check;
  }

  @override
  Future<void> uploadStream(
    Stream<List<int>> dataStream,
    int length,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    if (length < 0) throw ArgumentError.value(length, 'length');
    if (fileName.isEmpty ||
        fileName == '.' ||
        fileName == '..' ||
        fileName.contains('/') ||
        fileName.contains(r'\') ||
        fileName.contains('\u0000')) {
      throw const FormatException('Enter a file name without path separators.');
    }
    await _ensureAuth();
    final check = _captureTransfer();
    final uri = _davUri(
      _serverUrl!,
      _username!,
      p.posix.join(_normalizePath(targetPath), fileName),
    );
    final headers = {
      'authorization': _basicAuth(_username!, _password!),
      'content-type': 'application/octet-stream',
    };
    http.Response response;
    if (kIsWeb) {
      final spool = await createTransferSpool(
        dataStream,
        expectedLength: length,
        checkpoint: () async => check(),
      );
      try {
        response = await uploadSpooledHttpBody(
          uri,
          spool,
          operation: 'Nextcloud upload',
          headers: headers,
          allowHttp: true,
          checkCurrent: check,
          onProgress: onProgress,
        );
      } finally {
        await spool.dispose();
      }
    } else {
      final client = http.Client();
      var sent = 0;
      try {
        final body = validatedTransferParts(dataStream, length, 64 * 1024).map((
          chunk,
        ) {
          check();
          sent += chunk.length;
          onProgress?.call(sent, length);
          return chunk;
        });
        response = await sendTransferRequest(
          client,
          TransferStreamRequest('PUT', uri, body, length)
            ..headers.addAll(headers),
          operation: 'Nextcloud upload',
        );
      } finally {
        client.close();
      }
    }
    check();
    if (!const {200, 201, 204}.contains(response.statusCode)) {
      throw StateError(
        'Nextcloud upload was not confirmed (HTTP ${response.statusCode}).',
      );
    }
    onProgress?.call(length, length);
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
    final resp = await http.get(
      uri,
      headers: {'Authorization': _basicAuth(_username!, _password!)},
    );

    if (resp.statusCode != 200) {
      throw NextcloudOperationFailure(
        NextcloudOperationCode.download,
        'Nextcloud download failed (HTTP ${resp.statusCode}): ${resp.body}',
        {'status': resp.statusCode, 'body': resp.body},
      );
    }

    onProgress?.call(resp.bodyBytes.length, resp.bodyBytes.length);
    return resp.bodyBytes;
  }

  @override
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async* {
    await _ensureAuth();
    final check = _captureTransfer();
    final uri = _davUri(_serverUrl!, _username!, _normalizePath(remotePath));
    yield* streamHttpDownload(
      uri,
      operation: 'Nextcloud download',
      headers: {
        'authorization': _basicAuth(_username!, _password!),
        'accept-encoding': 'identity',
      },
      followRedirects: false,
      allowHttp: true,
      checkCurrent: check,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    final sink = dart_io.File(localPath).openWrite();
    try {
      await sink.addStream(downloadStream(remotePath, onProgress: onProgress));
      await sink.flush();
    } finally {
      await sink.close();
    }
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
        throw NextcloudOperationFailure(
          NextcloudOperationCode.createFolder,
          'Failed to create folder "$accumulated" (HTTP ${mkcolResp.statusCode})',
          {'path': accumulated, 'status': mkcolResp.statusCode},
        );
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
      throw NextcloudOperationFailure(
        NextcloudOperationCode.delete,
        'Nextcloud delete failed (HTTP ${resp.statusCode}): ${resp.body}',
        {'status': resp.statusCode, 'body': resp.body},
      );
    }
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    await _ensureAuth();

    final sourceUri = _davUri(
      _serverUrl!,
      _username!,
      _normalizePath(sourcePath),
    );
    final destinationUrl = _davUri(
      _serverUrl!,
      _username!,
      _normalizePath(targetPath),
    ).toString();

    final req = http.Request('MOVE', sourceUri);
    req.headers['Authorization'] = _basicAuth(_username!, _password!);
    req.headers['Destination'] = destinationUrl;
    req.headers['Overwrite'] = 'F';

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 201 && resp.statusCode != 204) {
      throw NextcloudOperationFailure(
        NextcloudOperationCode.move,
        'Nextcloud move failed (HTTP ${resp.statusCode}): ${resp.body}',
        {'status': resp.statusCode, 'body': resp.body},
      );
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
    final uri = Uri.parse(
      '$_serverUrl/ocs/v2.php/apps/files_sharing/api/v1/shares',
    );
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
      throw NextcloudOperationFailure(
        NextcloudOperationCode.share,
        'OCS share creation failed (HTTP ${resp.statusCode}): ${resp.body}',
        {'status': resp.statusCode, 'body': resp.body},
      );
    }

    // Parse the share URL from XML response
    try {
      final doc = xml.XmlDocument.parse(resp.body);
      final urlNode = doc.findAllElements('url').firstOrNull;
      if (urlNode != null) return urlNode.innerText;
    } catch (_) {}

    throw NextcloudOperationFailure(
      NextcloudOperationCode.shareParse,
      'Failed to parse share URL from OCS response',
    );
  }

  // ---------------------------------------------------------------------------
  // Versioning (via DAV versions API)
  // ---------------------------------------------------------------------------

  /// List versions for a file. Returns a list of version metadata maps.
  /// `fileId` can be obtained from the file's DAV properties (oc:fileid).
  Future<List<Map<String, dynamic>>> listVersions(String fileId) async {
    await _ensureAuth();

    final uri = Uri.parse(
      '$_serverUrl/remote.php/dav/versions/$_username/versions/$fileId',
    );
    final resp = await _propfind(uri, _username!, _password!, depth: '1');

    if (resp.statusCode != 207) {
      throw NextcloudOperationFailure(
        NextcloudOperationCode.listVersions,
        'Failed to list versions (HTTP ${resp.statusCode})',
        {'status': resp.statusCode},
      );
    }

    final items = _parsePropfind(resp.body);
    // Skip the first item (the versions container itself)
    return items
        .skip(1)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  /// Restore a specific version. `fileId` and `versionId` come from [listVersions].
  Future<void> restoreVersion(
    String fileId,
    String versionId,
    String targetPath,
  ) async {
    await _ensureAuth();

    final sourceUri = Uri.parse(
      '$_serverUrl/remote.php/dav/versions/$_username/versions/$fileId/$versionId',
    );
    final destUri = _davUri(
      _serverUrl!,
      _username!,
      _normalizePath(targetPath),
    );

    final req = http.Request('COPY', sourceUri);
    req.headers['Authorization'] = _basicAuth(_username!, _password!);
    req.headers['Destination'] = destUri.toString();
    req.headers['Overwrite'] = 'T';

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 201 && resp.statusCode != 204) {
      throw NextcloudOperationFailure(
        NextcloudOperationCode.restoreVersion,
        'Restore version failed (HTTP ${resp.statusCode}): ${resp.body}',
        {'status': resp.statusCode, 'body': resp.body},
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<void> _ensureAuth() async {
    if (_authenticated &&
        _username != null &&
        _password != null &&
        _serverUrl != null) {
      return;
    }

    // Try restoring from storage
    final creds = await _config.readCredentials();
    if (creds == null ||
        creds['username'] == null ||
        creds['password'] == null ||
        creds['serverUrl'] == null) {
      throw NextcloudOperationFailure(
        NextcloudOperationCode.notAuthenticated,
        'Not authenticated. Please connect to Nextcloud first.',
      );
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
    return Uri.parse(
      '$serverUrl/remote.php/dav/files/$encodedUsername$encodedPath',
    );
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

    final client = http.Client();
    try {
      return await (() async {
        final streamed = await client.send(req);
        return http.Response.fromStream(streamed);
      })().timeout(const Duration(seconds: 30));
    } catch (e) {
      if (kIsWeb) throw nextcloudBrowserFailure(uri, Uri.base, e);
      throw NextcloudOperationFailure(
        NextcloudOperationCode.propfind,
        'PROPFIND failed for $uri: $e',
        {'uri': uri, 'error': e},
      );
    } finally {
      client.close();
    }
  }

  /// Parse a WebDAV multi-status (207) XML response body.
  /// Returns a list of property maps for each <d:response>.
  List<Map<String, dynamic>> _parsePropfind(String body) {
    final results = <Map<String, dynamic>>[];

    try {
      final doc = xml.XmlDocument.parse(body);
      final responses = doc.findAllElements('response', namespace: 'DAV:');

      for (final response in responses) {
        final hrefNode = response
            .findElements('href', namespace: 'DAV:')
            .firstOrNull;
        final href = hrefNode?.innerText ?? '';

        // Get the last non-empty path segment as the display name
        final hrefDecoded = Uri.decodeComponent(href);
        final segments = hrefDecoded
            .split('/')
            .where((s) => s.isNotEmpty)
            .toList();
        final name = segments.isNotEmpty ? segments.last : '';

        // Resource type: check for <d:collection/>
        final resourceType = response
            .findAllElements('resourcetype', namespace: 'DAV:')
            .firstOrNull;
        final isDir =
            resourceType != null &&
            resourceType
                .findAllElements('collection', namespace: 'DAV:')
                .isNotEmpty;

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
          final raw = modNode.innerText.trim();
          final iso = DateTime.tryParse(raw);
          if (iso != null) {
            lastModified = iso.toUtc().toIso8601String();
          } else {
            try {
              lastModified = parseHttpDate(raw).toIso8601String();
            } on FormatException {
              // An invalid optional timestamp must not hide a readable folder.
              lastModified = null;
            }
          }
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

  /// Retained preference; provider delta execution requires a staged contract.
  /// Ordinary transfers remain available regardless of this value.
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

  /// Get the ETag of a single remote file (HEAD request).
  Future<String?> getFileETag(String remotePath) async {
    await _ensureAuth();
    final uri = _davUri(_serverUrl!, _username!, _normalizePath(remotePath));
    final resp = await http.head(
      uri,
      headers: {'Authorization': _basicAuth(_username!, _password!)},
    );
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
    final resp = await http.get(
      uri,
      headers: {
        'Authorization': _basicAuth(_username!, _password!),
        'Range': 'bytes=$offset-${offset + length - 1}',
      },
    );

    if (resp.statusCode != 206 && resp.statusCode != 200) {
      throw NextcloudOperationFailure(
        NextcloudOperationCode.rangeDownload,
        'Nextcloud range download failed (HTTP ${resp.statusCode})',
        {'status': resp.statusCode},
      );
    }
    return resp.bodyBytes;
  }

  /// Reject the legacy direct-block writer before authentication or I/O.
  ///
  /// Neither the companion app nor the old chunked fallback supplies this
  /// adapter with version-bound staging and verified conditional publication.
  /// Callers must use the ordinary upload route until that contract exists.
  Future<void> uploadDeltaBlocks(
    String remotePath,
    String localPath,
    BlockTransferPlan plan,
  ) async {
    throw UnsupportedError(
      'Nextcloud delta block uploads require version-bound staging and '
      'verified publication. Use ordinary uploads.',
    );
  }

  /// Fetch block map from the server-side CrispCloud delta app.
  /// Returns null if the app is not installed or the map is invalid. The
  /// validated result is informational and does not admit a delta transfer.
  Future<BlockMap?> fetchServerBlockMap(String remotePath) async {
    if (deltaSyncServerAppUrl == null) return null;
    await _ensureAuth();

    final appBase = deltaSyncServerAppUrl!;
    final encodedPath = Uri.encodeComponent(remotePath);
    final uri = Uri.parse('$appBase/api/blockmap/$encodedPath');

    final resp = await http.get(
      uri,
      headers: {'Authorization': _basicAuth(_username!, _password!)},
    );

    if (resp.statusCode != 200) return null;

    try {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return BlockMap.fromJson(json);
    } catch (e) {
      _log.warn('Failed to parse server block map: $e');
      return null;
    }
  }

  /// Decline remote delta execution before authentication or file/cache I/O.
  ///
  /// Return null so the caller can use the ordinary upload route. A saved
  /// enable flag or discovered companion app does not establish the required
  /// base identity, private staging, final verification and publication proof.
  Future<DeltaResult?> deltaUpload(
    String localPath,
    String remotePath, {
    String? cacheDir,
    void Function(int processedBlocks, int totalBlocks, int processedBytes)?
    onProgress,
  }) async {
    return null;
  }

  /// Decline remote delta execution without opening or altering the local file.
  ///
  /// The legacy range reader is not bound to a single remote revision. Return
  /// null for ordinary download fallback even when the delta preference is set.
  Future<DeltaResult?> deltaDownload(
    String remotePath,
    String localPath, {
    String? cacheDir,
    void Function(int processedBlocks, int totalBlocks, int processedBytes)?
    onProgress,
  }) async {
    return null;
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

    final uri = Uri.tryParse(serverUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }

    // Normalise: strip trailing slash
    final normUrl = serverUrl.replaceFirst(RegExp(r'/+$'), '');

    return (username, normUrl);
  }
}
