// lib/services/onedrive_client_adapter.dart
//
// OneDrive / SharePoint adapter using Microsoft Graph API v1.0.
// Pure HTTP + OAuth2 browser flow (no MSAL dependency).
//
// Graph API supports path-based addressing natively:
//   /me/drive/root:/{path}:/children
// so we don't need the ID-resolution caching that GDrive requires.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'cloud_storage_interface.dart';
import 'log_service.dart';
import 'onedrive_config_service.dart';
import 'secure_storage_service.dart';

class OneDriveClientAdapter extends CloudStorageClient {
  static final _log = Log('OneDriveClient');

  final OneDriveConfigService _config;

  OneDriveConfigService get config => _config;

  String? _accessToken;
  String? _refreshToken;
  String? _email;
  String? _clientId;
  String? _clientSecret;
  DateTime? _tokenExpiry;
  bool _authenticated = false;

  static const _graphBase = 'https://graph.microsoft.com/v1.0';
  static const _authUrl = 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize';
  static const _tokenUrl = 'https://login.microsoftonline.com/common/oauth2/v2.0/token';
  static const _scopes = 'Files.ReadWrite.All User.Read offline_access';
  static const _redirectPort = 43824;

  OneDriveClientAdapter({required dynamic config})
      : _config = (config is OneDriveConfigService)
            ? config
            : OneDriveConfigService(configPath: '', secureStorage: InMemorySecureStorage());

  @override
  String get providerName => 'OneDrive';

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated => _authenticated && _accessToken != null;

  /// Expose access token for direct API calls (e.g. version history, restore).
  String? get accessToken => _accessToken;

  @override
  String? get userId => _email;

  @override
  String? get bucketId => null;

  // Capability flags
  @override
  bool get supportsVersioning => true;
  @override
  bool get supportsSharing => true;
  @override
  bool get supportsNativeShare => true;
  @override
  bool get supportsSearch => true;
  @override
  bool get supportsThumbnails => true;
  @override
  bool get supportsTrash => true;
  @override
  bool get supportsServerSideCopy => true;
  @override
  bool get supportsFullTextSearch => true;

  // --- Auth ---

  @override
  Future<void> login(String identity, String password, {String? twoFactorCode}) async {
    // identity format: "clientId" or "clientId|clientSecret"
    final parts = identity.split('|');
    _clientId = parts[0].trim();
    _clientSecret = parts.length > 1 ? parts[1].trim() : null;

    if (_clientId == null || _clientId!.isEmpty) {
      throw Exception('Application (Client) ID is required');
    }

    // Try stored refresh token first
    final creds = await _config.readCredentials();
    if (creds != null &&
        creds['refresh_token'] != null &&
        creds['client_id'] == _clientId) {
      _refreshToken = creds['refresh_token'];
      _email = creds['email'];
      try {
        await _refreshAccessToken();
        _authenticated = true;
        return;
      } catch (_) {}
    }

    if (kIsWeb) {
      throw Exception('OneDrive OAuth2 on web requires a different redirect flow.');
    }

    await _browserOAuthFlow();
    _authenticated = true;
    await _fetchUserEmail();

    await _config.saveCredentials({
      'client_id': _clientId!,
      if (_clientSecret != null) 'client_secret': _clientSecret!,
      'refresh_token': _refreshToken ?? '',
      'email': _email ?? '',
    });
  }

  @override
  Future<bool> is2faNeeded(String email) async => false;

  @override
  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _email = null;
    _authenticated = false;
  }

  @override
  Future<Uint8List?> getThumbnail(String remotePath) async {
    await _ensureToken();
    try {
      final encodedPath = Uri.encodeComponent(remotePath.startsWith('/') ? remotePath.substring(1) : remotePath);
      final uri = Uri.parse('https://graph.microsoft.com/v1.0/me/drive/root:/$encodedPath:/thumbnails/0/medium/content');
      final resp = await http.get(uri, headers: {'Authorization': 'Bearer $_accessToken'});
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<bool> restoreCredentials() async {
    final creds = await _config.readCredentials();
    if (creds == null || creds['refresh_token'] == null || creds['refresh_token']!.isEmpty) {
      return false;
    }
    _clientId = creds['client_id'];
    _clientSecret = creds['client_secret'];
    _refreshToken = creds['refresh_token'];
    _email = creds['email'];

    try {
      await _refreshAccessToken();
      _authenticated = true;
      return true;
    } catch (e) {
      _log.warn('Token refresh failed', e);
      return false;
    }
  }

  // --- Path helpers ---

  /// Build a Graph API path for a drive item addressed by path.
  /// "/Documents/report.pdf" → "/me/drive/root:/Documents/report.pdf:"
  String _drivePath(String path) {
    if (path == '/' || path.isEmpty) return '/me/drive/root';
    final clean = path.startsWith('/') ? path : '/$path';
    return '/me/drive/root:$clean:';
  }

  /// Build a Graph API path for listing children of a folder.
  String _childrenPath(String path) {
    if (path == '/' || path.isEmpty) return '/me/drive/root/children';
    final clean = path.startsWith('/') ? path : '/$path';
    return '/me/drive/root:$clean:/children';
  }

  // --- Path Resolution ---

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    await _ensureToken();
    try {
      final resp = await _graphGet(_drivePath(path));
      return resp;
    } catch (_) {
      return null;
    }
  }

  // --- List ---

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    await _ensureToken();

    final folders = <Map<String, dynamic>>[];
    final files = <Map<String, dynamic>>[];
    String? nextLink;
    var url = '$_graphBase${_childrenPath(path)}?\$top=200&\$select=id,name,size,lastModifiedDateTime,folder,file';

    do {
      final resp = await http.get(
        Uri.parse(url),
        headers: _authHeaders(),
      );

      if (resp.statusCode == 401) {
        await _refreshAccessToken();
        continue; // retry
      }

      if (resp.statusCode != 200) {
        throw Exception('OneDrive list failed (${resp.statusCode}): ${resp.body}');
      }

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final items = (data['value'] as List?) ?? [];

      for (final item in items) {
        final map = item as Map<String, dynamic>;
        final name = map['name'] as String? ?? 'Unknown';
        final id = map['id'] as String;
        final isFolder = map.containsKey('folder');

        final entry = <String, dynamic>{
          'name': name,
          'uuid': id,
          if (map['lastModifiedDateTime'] != null) 'lastModified': map['lastModifiedDateTime'],
          if (map['size'] != null) 'size': map['size'] as int,
        };

        // Capture content hash for delta sync
        if (!isFolder) {
          final fileInfo = map['file'] as Map<String, dynamic>?;
          final hashes = fileInfo?['hashes'] as Map<String, dynamic>?;
          final crc = hashes?['crc32Hash'] as String?;
          final sha1 = hashes?['sha1Hash'] as String?;
          if (crc != null) entry['crc32Hash'] = crc;
          if (sha1 != null) entry['content_hash'] = sha1;
        }

        if (isFolder) {
          folders.add(entry);
        } else {
          files.add(entry);
        }
      }

      nextLink = data['@odata.nextLink'] as String?;
      if (nextLink != null) url = nextLink;
    } while (nextLink != null);

    return {'folders': folders, 'files': files};
  }

  // --- Upload ---

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    await _ensureToken();

    // Simple upload for files <= 4MB, otherwise use upload session
    final parentPath = targetPath == '/' || targetPath.isEmpty
        ? '/me/drive/root'
        : '/me/drive/root:$targetPath:';
    final uploadUrl = '$_graphBase$parentPath:/$fileName:/content';

    final resp = await http.put(
      Uri.parse(uploadUrl),
      headers: {
        ..._authHeaders(),
        'Content-Type': 'application/octet-stream',
      },
      body: Uint8List.fromList(fileData),
    );

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('OneDrive upload failed (${resp.statusCode}): ${resp.body}');
    }

    onProgress?.call(fileData.length, fileData.length);
  }

  // --- Download ---

  @override
  Future<Uint8List> downloadFileBytes(String remotePath, {Function(int, int)? onProgress}) async {
    await _ensureToken();

    // Get download URL from item metadata
    final meta = await _graphGet('${_drivePath(remotePath)}?\$select=@microsoft.graph.downloadUrl');
    final downloadUrl = meta['@microsoft.graph.downloadUrl'] as String?;

    if (downloadUrl == null) {
      throw Exception('No download URL for: $remotePath');
    }

    final resp = await http.get(Uri.parse(downloadUrl));
    if (resp.statusCode != 200) {
      throw Exception('OneDrive download failed (${resp.statusCode})');
    }

    onProgress?.call(resp.bodyBytes.length, resp.bodyBytes.length);
    return resp.bodyBytes;
  }

  @override
  Future<void> downloadFileByPath(String remotePath, String localPath, {Function(int, int)? onProgress}) async {
    final bytes = await downloadFileBytes(remotePath, onProgress: onProgress);
    await File(localPath).writeAsBytes(bytes);
  }

  // --- Folder ---

  @override
  Future<void> createFolderPath(String path) async {
    await _ensureToken();

    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    String parentPath = '';

    for (final segment in segments) {
      final parentApiPath = parentPath.isEmpty
          ? '/me/drive/root/children'
          : '/me/drive/root:$parentPath:/children';

      final body = json.encode({
        'name': segment,
        'folder': {},
        '@microsoft.graph.conflictBehavior': 'fail',
      });

      final resp = await http.post(
        Uri.parse('$_graphBase$parentApiPath'),
        headers: {
          ..._authHeaders(),
          'Content-Type': 'application/json',
        },
        body: body,
      );

      // 409 Conflict = folder already exists, which is fine
      if (resp.statusCode != 201 && resp.statusCode != 200 && resp.statusCode != 409) {
        throw Exception('OneDrive createFolder failed (${resp.statusCode}): ${resp.body}');
      }

      parentPath = '$parentPath/$segment';
    }
  }

  // --- Copy ---

  @override
  Future<void> copyPath(String sourcePath, String targetPath) async {
    await _ensureToken();
    // Resolve the target folder ID
    final targetMeta = await _graphGet('${_drivePath(targetPath)}?\$select=id,parentReference');
    final targetId = targetMeta['id'] as String?;
    if (targetId == null) throw Exception('Target folder not found: $targetPath');
    final fileName = p.posix.basename(sourcePath);
    _log.info('Server-side copy (OneDrive): $sourcePath → $targetPath');
    final body = json.encode({
      'parentReference': {'id': targetId},
      'name': fileName,
      '@microsoft.graph.conflictBehavior': 'rename',
    });
    final resp = await http.post(
      Uri.parse('$_graphBase${_drivePath(sourcePath)}/copy'),
      headers: {
        ..._authHeaders(),
        'Content-Type': 'application/json',
        'Prefer': 'respond-async',
      },
      body: body,
    );
    // Graph API returns 202 Accepted for async copy; treat 200/202 as success
    if (resp.statusCode != 200 && resp.statusCode != 202) {
      throw Exception('OneDrive copy failed (${resp.statusCode}): ${resp.body}');
    }
  }

  // --- Delete / Move / Rename ---

  @override
  Future<void> deletePath(String path) async {
    await _ensureToken();
    final resp = await http.delete(
      Uri.parse('$_graphBase${_drivePath(path)}'),
      headers: _authHeaders(),
    );
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception('OneDrive delete failed (${resp.statusCode}): ${resp.body}');
    }
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    await _ensureToken();

    // Resolve target folder ID
    final targetMeta = await _graphGet('${_drivePath(targetPath)}?\$select=id,parentReference');
    final targetId = targetMeta['id'] as String?;
    if (targetId == null) throw Exception('Target folder not found: $targetPath');

    final body = json.encode({
      'parentReference': {'id': targetId},
    });

    final resp = await http.patch(
      Uri.parse('$_graphBase${_drivePath(sourcePath)}'),
      headers: {
        ..._authHeaders(),
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (resp.statusCode != 200) {
      throw Exception('OneDrive move failed (${resp.statusCode}): ${resp.body}');
    }
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    await _ensureToken();

    final body = json.encode({'name': newName});
    final resp = await http.patch(
      Uri.parse('$_graphBase${_drivePath(path)}'),
      headers: {
        ..._authHeaders(),
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (resp.statusCode != 200) {
      throw Exception('OneDrive rename failed (${resp.statusCode}): ${resp.body}');
    }
  }

  // --- Full-text search ---

  @override
  Future<List<Map<String, dynamic>>> fullTextSearch(
    String query,
    String remotePath,
  ) async {
    await _ensureToken();

    // Microsoft Graph search endpoint
    final body = json.encode({
      'requests': [
        {
          'entityTypes': ['driveItem'],
          'query': {
            'queryString': query,
          },
          'from': 0,
          'size': 100,
        },
      ],
    });

    final resp = await http.post(
      Uri.parse('$_graphBase/search/query'),
      headers: {
        ..._authHeaders(),
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (resp.statusCode != 200) {
      // Fallback to default implementation if search endpoint unavailable
      return super.fullTextSearch(query, remotePath);
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;
    final results = <Map<String, dynamic>>[];

    final values = (data['value'] as List?) ?? [];
    for (final resultSet in values) {
      final hits = (resultSet['hitsContainers'] as List?) ?? [];
      for (final container in hits) {
        final hitList = (container['hits'] as List?) ?? [];
        for (final hit in hitList) {
          final resource = hit['resource'] as Map<String, dynamic>?;
          if (resource == null) continue;

          final name = resource['name'] as String? ?? 'Unknown';
          final id = resource['id'] as String? ?? '';
          final size = resource['size'] as int? ?? 0;
          final webUrl = resource['webUrl'] as String? ?? '';

          // Extract summary/snippet from hit
          final summary = hit['summary'] as String? ?? 'Content matches "$query"';

          results.add({
            'name': name,
            'uuid': id,
            'path': webUrl,
            'size': size,
            if (resource['lastModifiedDateTime'] != null)
              'lastModified': resource['lastModifiedDateTime'],
            'snippet': summary,
          });
        }
      }
    }

    return results;
  }

  // --- Internal ---

  Map<String, String> _authHeaders() => {'Authorization': 'Bearer $_accessToken'};

  Future<void> _ensureToken() async {
    if (_accessToken == null) throw Exception('Not authenticated');
    if (_tokenExpiry != null && DateTime.now().isAfter(_tokenExpiry!)) {
      await _refreshAccessToken();
    }
  }

  Future<void> _refreshAccessToken() async {
    if (_refreshToken == null || _clientId == null) {
      throw Exception('Cannot refresh: missing refresh token or client ID');
    }

    final body = <String, String>{
      'client_id': _clientId!,
      'grant_type': 'refresh_token',
      'refresh_token': _refreshToken!,
      'scope': _scopes,
    };
    if (_clientSecret != null && _clientSecret!.isNotEmpty) {
      body['client_secret'] = _clientSecret!;
    }

    final resp = await http.post(Uri.parse(_tokenUrl), body: body);
    if (resp.statusCode != 200) {
      throw Exception('Token refresh failed (${resp.statusCode}): ${resp.body}');
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String;
    if (data['refresh_token'] != null) {
      _refreshToken = data['refresh_token'] as String;
    }
    final expiresIn = data['expires_in'] as int? ?? 3600;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
  }

  Future<void> _browserOAuthFlow() async {
    final redirectUri = 'http://localhost:$_redirectPort';

    final authUri = Uri.parse(_authUrl).replace(queryParameters: {
      'client_id': _clientId!,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _scopes,
      'response_mode': 'query',
    });

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _redirectPort);

    if (await canLaunchUrl(authUri)) {
      await launchUrl(authUri, mode: LaunchMode.externalApplication);
    } else {
      await server.close();
      throw Exception('Could not open browser for Microsoft authorization');
    }

    String? authCode;
    try {
      await for (final request in server) {
        final code = request.uri.queryParameters['code'];
        final error = request.uri.queryParameters['error'];

        if (error != null) {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write('<html><body><h2>Authorization denied: $error</h2><p>You can close this window.</p></body></html>');
          await request.response.close();
          break;
        }

        if (code != null) {
          authCode = code;
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write('<html><body><h2>Authorization successful!</h2><p>You can close this window and return to CrispCloud.</p></body></html>');
          await request.response.close();
          break;
        }

        request.response
          ..statusCode = 404
          ..write('Not found');
        await request.response.close();
      }
    } finally {
      await server.close();
    }

    if (authCode == null) {
      throw Exception('Microsoft authorization was cancelled or failed');
    }

    // Exchange code for tokens
    final tokenBody = <String, String>{
      'code': authCode,
      'client_id': _clientId!,
      'redirect_uri': redirectUri,
      'grant_type': 'authorization_code',
      'scope': _scopes,
    };
    if (_clientSecret != null && _clientSecret!.isNotEmpty) {
      tokenBody['client_secret'] = _clientSecret!;
    }

    final tokenResp = await http.post(Uri.parse(_tokenUrl), body: tokenBody);
    if (tokenResp.statusCode != 200) {
      throw Exception('Token exchange failed (${tokenResp.statusCode}): ${tokenResp.body}');
    }

    final tokenData = json.decode(tokenResp.body) as Map<String, dynamic>;
    _accessToken = tokenData['access_token'] as String;
    _refreshToken = tokenData['refresh_token'] as String?;
    final expiresIn = tokenData['expires_in'] as int? ?? 3600;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
  }

  Future<void> _fetchUserEmail() async {
    try {
      final data = await _graphGet('/me?\$select=userPrincipalName,mail');
      _email = (data['mail'] ?? data['userPrincipalName']) as String?;
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _graphGet(String endpoint) async {
    final url = endpoint.startsWith('http') ? endpoint : '$_graphBase$endpoint';
    final resp = await http.get(Uri.parse(url), headers: _authHeaders());

    if (resp.statusCode == 401) {
      await _refreshAccessToken();
      final retryResp = await http.get(Uri.parse(url), headers: _authHeaders());
      if (retryResp.statusCode != 200) {
        throw Exception('Graph API error (${retryResp.statusCode}): ${retryResp.body}');
      }
      return json.decode(retryResp.body) as Map<String, dynamic>;
    }

    if (resp.statusCode != 200) {
      throw Exception('Graph API error (${resp.statusCode}): ${resp.body}');
    }

    return json.decode(resp.body) as Map<String, dynamic>;
  }
}
