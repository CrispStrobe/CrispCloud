// lib/services/dropbox_client_adapter.dart
//
// Dropbox adapter using the Dropbox API v2 with pure HTTP.
// OAuth2 PKCE browser flow (no SDK dependency).
//
// Key endpoints:
//   POST /2/files/list_folder      — list directory
//   POST /2/files/upload           — upload (up to 150 MB)
//   POST /2/files/download         — download
//   POST /2/files/create_folder_v2 — create folder
//   POST /2/files/delete_v2        — delete
//   POST /2/files/move_v2          — move/rename

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'cloud_storage_interface.dart';
import 'dropbox_config_service.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';

class DropboxClientAdapter extends CloudStorageClient {
  static const _log = Log('DropboxClient');

  final DropboxConfigService _config;

  DropboxConfigService get config => _config;

  String? _accessToken;
  String? _refreshToken;
  String? _email;
  String? _appKey;
  String? _appSecret;
  DateTime? _tokenExpiry;
  bool _authenticated = false;

  static const _apiBase = 'https://api.dropboxapi.com/2';
  static const _contentBase = 'https://content.dropboxapi.com/2';
  static const _authUrl = 'https://www.dropbox.com/oauth2/authorize';
  static const _tokenUrl = 'https://api.dropboxapi.com/oauth2/token';
  static const _redirectPort = 43825;

  DropboxClientAdapter({required dynamic config})
      : _config = (config is DropboxConfigService)
            ? config
            : DropboxConfigService(configPath: '', secureStorage: InMemorySecureStorage());

  @override
  String get providerName => 'Dropbox';

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
    // identity format: "appKey" or "appKey|appSecret"
    final parts = identity.split('|');
    _appKey = parts[0].trim();
    _appSecret = parts.length > 1 ? parts[1].trim() : null;

    if (_appKey == null || _appKey!.isEmpty) {
      throw Exception('App Key is required');
    }

    // Try stored refresh token
    final creds = await _config.readCredentials();
    if (creds != null &&
        creds['refresh_token'] != null &&
        creds['app_key'] == _appKey) {
      _refreshToken = creds['refresh_token'];
      _email = creds['email'];
      try {
        await _refreshAccessToken();
        _authenticated = true;
        return;
      } catch (_) {}
    }

    if (kIsWeb) {
      throw Exception('Dropbox OAuth2 on web requires a different redirect flow.');
    }

    await _browserOAuthFlow();
    _authenticated = true;
    await _fetchUserEmail();

    await _config.saveCredentials({
      'app_key': _appKey!,
      if (_appSecret != null) 'app_secret': _appSecret!,
      'refresh_token': _refreshToken ?? '',
      'email': _email ?? '',
    });
  }

  @override
  Future<bool> is2faNeeded(String email) async => false;

  @override
  Future<void> logout() async {
    if (_accessToken != null) {
      try {
        await http.post(
          Uri.parse('$_apiBase/auth/token/revoke'),
          headers: {'Authorization': 'Bearer $_accessToken'},
        );
      } catch (_) {}
    }
    _accessToken = null;
    _refreshToken = null;
    _email = null;
    _authenticated = false;
  }

  @override
  Future<Uint8List?> getThumbnail(String remotePath) async {
    await _ensureToken();
    try {
      final path = remotePath.isEmpty || remotePath == '/' ? '' : remotePath;
      final arg = json.encode({'resource': {'.tag': 'path', 'path': path}, 'format': 'jpeg', 'size': 'w128h128'});
      final resp = await http.post(
        Uri.parse('https://content.dropboxapi.com/2/files/get_thumbnail_v2'),
        headers: {'Authorization': 'Bearer $_accessToken', 'Dropbox-API-Arg': arg},
      );
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<bool> restoreCredentials() async {
    final creds = await _config.readCredentials();
    if (creds == null || creds['refresh_token'] == null || creds['refresh_token']!.isEmpty) {
      return false;
    }
    _appKey = creds['app_key'];
    _appSecret = creds['app_secret'];
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

  /// Dropbox uses "" for root, paths must start with / for non-root.
  String _dbxPath(String path) {
    if (path == '/' || path.isEmpty) return '';
    return path.startsWith('/') ? path : '/$path';
  }

  // --- Path Resolution ---

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    await _ensureToken();
    try {
      final resp = await _rpcPost('/files/get_metadata', {'path': _dbxPath(path)});
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

    var resp = await _rpcPost('/files/list_folder', {
      'path': _dbxPath(path),
      'limit': 2000,
      'include_mounted_folders': true,
    });

    void processEntries(List entries) {
      for (final item in entries) {
        final map = item as Map<String, dynamic>;
        final tag = map['.tag'] as String?;
        final name = map['name'] as String? ?? 'Unknown';
        final id = map['id'] as String? ?? '';

        final entry = <String, dynamic>{
          'name': name,
          'uuid': id,
          if (map['server_modified'] != null) 'lastModified': map['server_modified'],
          if (map['size'] != null) 'size': map['size'] as int,
          // Content hash for delta sync (256-bit block hash)
          if (map['content_hash'] != null) 'content_hash': map['content_hash'],
        };

        if (tag == 'folder') {
          folders.add(entry);
        } else {
          files.add(entry);
        }
      }
    }

    processEntries((resp['entries'] as List?) ?? []);

    // Handle pagination
    while (resp['has_more'] == true) {
      resp = await _rpcPost('/files/list_folder/continue', {
        'cursor': resp['cursor'],
      });
      processEntries((resp['entries'] as List?) ?? []);
    }

    return {'folders': folders, 'files': files};
  }

  // --- Shared Folders ---

  /// List shared folders the user has mounted.
  /// Returns a list of `{id, name, path, sharedFolderId}` maps.
  Future<List<Map<String, dynamic>>> listSharedFolders() async {
    await _ensureToken();
    final results = <Map<String, dynamic>>[];
    String? cursor;

    do {
      final Map<String, dynamic> resp;
      if (cursor == null) {
        resp = await _rpcPost('/sharing/list_folders', {'limit': 100});
      } else {
        resp = await _rpcPost('/sharing/list_folders/continue', {'cursor': cursor});
      }

      for (final item in (resp['entries'] as List?) ?? []) {
        final map = item as Map<String, dynamic>;
        results.add({
          'name': map['name'] as String? ?? 'Unknown',
          'sharedFolderId': map['shared_folder_id'] as String? ?? '',
          if (map['path_lower'] != null) 'path': map['path_lower'],
          'accessType': (map['access_type'] as Map<String, dynamic>?)?['.tag'] ?? 'viewer',
        });
      }

      cursor = resp['cursor'] as String?;
    } while (cursor != null);

    return results;
  }

  /// Mount a shared folder by its shared folder ID.
  Future<void> mountSharedFolder(String sharedFolderId) async {
    await _ensureToken();
    await _rpcPost('/sharing/mount_folder', {
      'shared_folder_id': sharedFolderId,
    });
  }

  /// Unmount a shared folder by its shared folder ID.
  Future<void> unmountSharedFolder(String sharedFolderId) async {
    await _ensureToken();
    await _rpcPost('/sharing/unmount_folder', {
      'shared_folder_id': sharedFolderId,
    });
  }

  /// Compute the Dropbox content hash for local data (for dedup comparison).
  ///
  /// The Dropbox content hash splits data into 4MB blocks, SHA-256 hashes each,
  /// concatenates those hashes, and SHA-256 hashes the result.
  static String computeContentHash(List<int> data) {
    const blockSize = 4 * 1024 * 1024; // 4 MB
    final blockHashes = <int>[];

    for (int offset = 0; offset < data.length; offset += blockSize) {
      final end = (offset + blockSize > data.length) ? data.length : offset + blockSize;
      final block = data.sublist(offset, end);
      blockHashes.addAll(sha256.convert(block).bytes);
    }

    // Handle empty data
    if (data.isEmpty) {
      blockHashes.addAll(sha256.convert(<int>[]).bytes);
    }

    return sha256.convert(blockHashes).toString();
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

    final filePath = targetPath == '/' || targetPath.isEmpty
        ? '/$fileName'
        : '$targetPath/$fileName';

    final uri = Uri.parse('$_contentBase/files/upload');
    final apiArg = json.encode({
      'path': filePath,
      'mode': 'overwrite',
      'autorename': false,
      'mute': false,
    });

    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/octet-stream',
        'Dropbox-API-Arg': apiArg,
      },
      body: Uint8List.fromList(fileData),
    );

    if (resp.statusCode != 200) {
      throw Exception('Dropbox upload failed (${resp.statusCode}): ${resp.body}');
    }

    onProgress?.call(fileData.length, fileData.length);
  }

  // --- Download ---

  @override
  Future<Uint8List> downloadFileBytes(String remotePath, {Function(int, int)? onProgress}) async {
    await _ensureToken();

    final uri = Uri.parse('$_contentBase/files/download');
    final apiArg = json.encode({'path': _dbxPath(remotePath)});

    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Dropbox-API-Arg': apiArg,
      },
    );

    if (resp.statusCode != 200) {
      throw Exception('Dropbox download failed (${resp.statusCode}): ${resp.body}');
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

    try {
      await _rpcPost('/files/create_folder_v2', {
        'path': _dbxPath(path),
        'autorename': false,
      });
    } catch (e) {
      // 409 conflict = folder exists — fine
      if (!e.toString().contains('409') && !e.toString().contains('path/conflict')) {
        rethrow;
      }
    }
  }

  // --- Copy ---

  @override
  Future<void> copyPath(String sourcePath, String targetPath) async {
    await _ensureToken();
    final fileName = p.posix.basename(sourcePath);
    final dest = '$targetPath/$fileName';
    _log.info('Server-side copy (Dropbox): $sourcePath → $dest');
    await _rpcPost('/files/copy_v2', {
      'from_path': _dbxPath(sourcePath),
      'to_path': _dbxPath(dest),
      'autorename': true,
    });
  }

  // --- Delete / Move / Rename ---

  @override
  Future<void> deletePath(String path) async {
    await _ensureToken();
    await _rpcPost('/files/delete_v2', {'path': _dbxPath(path)});
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    await _ensureToken();
    final fileName = p.posix.basename(sourcePath);
    final dest = '$targetPath/$fileName';
    await _rpcPost('/files/move_v2', {
      'from_path': _dbxPath(sourcePath),
      'to_path': _dbxPath(dest),
      'autorename': false,
    });
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    await _ensureToken();
    final parent = p.posix.dirname(path);
    final newPath = parent == '/' ? '/$newName' : '$parent/$newName';
    await _rpcPost('/files/move_v2', {
      'from_path': _dbxPath(path),
      'to_path': _dbxPath(newPath),
      'autorename': false,
    });
  }

  // --- Full-text search ---

  @override
  Future<List<Map<String, dynamic>>> fullTextSearch(
    String query,
    String remotePath,
  ) async {
    await _ensureToken();

    // Dropbox search_v2 supports content search via options.file_status
    final body = <String, dynamic>{
      'query': query,
      'options': {
        'path': _dbxPath(remotePath),
        'max_results': 100,
        'file_status': 'active',
        'filename_only': false, // Search file contents too
      },
    };

    final results = <Map<String, dynamic>>[];
    var hasMore = true;
    String? cursor;

    while (hasMore) {
      Map<String, dynamic> resp;
      if (cursor != null) {
        resp = await _rpcPost('/files/search/continue_v2', {'cursor': cursor});
      } else {
        resp = await _rpcPost('/files/search_v2', body);
      }

      final matches = (resp['matches'] as List?) ?? [];
      for (final match in matches) {
        final metadata = match['metadata'] as Map<String, dynamic>?;
        final inner = metadata?['metadata'] as Map<String, dynamic>?;
        if (inner == null) continue;
        if (inner['.tag'] == 'folder') continue;

        final name = inner['name'] as String? ?? 'Unknown';
        final pathDisplay = inner['path_display'] as String? ?? '';

        // Extract highlight snippet if available
        final highlight = match['highlight_spans'] as List?;
        String snippet;
        if (highlight != null && highlight.isNotEmpty) {
          snippet = highlight.map((s) => s['highlight_str'] ?? '').join('...');
        } else {
          snippet = 'Content matches "$query"';
        }

        results.add({
          'name': name,
          'uuid': inner['id'] ?? '',
          'path': pathDisplay,
          'size': inner['size'] as int? ?? 0,
          if (inner['server_modified'] != null)
            'lastModified': inner['server_modified'],
          'snippet': snippet,
        });
      }

      hasMore = resp['has_more'] == true;
      cursor = resp['cursor'] as String?;
    }

    return results;
  }

  // --- Internal ---

  Future<void> _ensureToken() async {
    if (_accessToken == null) throw Exception('Not authenticated');
    if (_tokenExpiry != null && DateTime.now().isAfter(_tokenExpiry!)) {
      await _refreshAccessToken();
    }
  }

  Future<void> _refreshAccessToken() async {
    if (_refreshToken == null || _appKey == null) {
      throw Exception('Cannot refresh: missing refresh token or app key');
    }

    final body = <String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': _refreshToken!,
      'client_id': _appKey!,
    };
    if (_appSecret != null && _appSecret!.isNotEmpty) {
      body['client_secret'] = _appSecret!;
    }

    final resp = await http.post(Uri.parse(_tokenUrl), body: body);
    if (resp.statusCode != 200) {
      throw Exception('Token refresh failed (${resp.statusCode}): ${resp.body}');
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String;
    final expiresIn = data['expires_in'] as int? ?? 14400;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
  }

  Future<void> _browserOAuthFlow() async {
    const redirectUri = 'http://localhost:$_redirectPort';

    final authUri = Uri.parse(_authUrl).replace(queryParameters: {
      'client_id': _appKey!,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'token_access_type': 'offline', // Request refresh token
    });

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _redirectPort);

    if (await canLaunchUrl(authUri)) {
      await launchUrl(authUri, mode: LaunchMode.externalApplication);
    } else {
      await server.close();
      throw Exception('Could not open browser for Dropbox authorization');
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
      throw Exception('Dropbox authorization was cancelled or failed');
    }

    final tokenBody = <String, String>{
      'code': authCode,
      'grant_type': 'authorization_code',
      'client_id': _appKey!,
      'redirect_uri': redirectUri,
    };
    if (_appSecret != null && _appSecret!.isNotEmpty) {
      tokenBody['client_secret'] = _appSecret!;
    }

    final tokenResp = await http.post(Uri.parse(_tokenUrl), body: tokenBody);
    if (tokenResp.statusCode != 200) {
      throw Exception('Token exchange failed (${tokenResp.statusCode}): ${tokenResp.body}');
    }

    final tokenData = json.decode(tokenResp.body) as Map<String, dynamic>;
    _accessToken = tokenData['access_token'] as String;
    _refreshToken = tokenData['refresh_token'] as String?;
    final expiresIn = tokenData['expires_in'] as int? ?? 14400;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
  }

  Future<void> _fetchUserEmail() async {
    try {
      final data = await _rpcPost('/users/get_current_account', null);
      _email = data['email'] as String?;
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _rpcPost(String endpoint, dynamic body) async {
    final uri = Uri.parse('$_apiBase$endpoint');
    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      },
      body: body != null ? json.encode(body) : null,
    );

    if (resp.statusCode == 401) {
      await _refreshAccessToken();
      final retryResp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: body != null ? json.encode(body) : null,
      );
      if (retryResp.statusCode != 200) {
        throw Exception('Dropbox API error (${retryResp.statusCode}): ${retryResp.body}');
      }
      return json.decode(retryResp.body) as Map<String, dynamic>;
    }

    if (resp.statusCode != 200) {
      throw Exception('Dropbox API error (${resp.statusCode}): ${resp.body}');
    }

    // Some endpoints (like delete) return empty body
    if (resp.body.isEmpty) return {};
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  // --- Paper Docs ---

  /// List Dropbox Paper documents accessible to the user.
  ///
  /// Uses the files/search API to find Paper documents by MIME type.
  /// Returns document metadata: name, id, path, lastModified.
  Future<List<Map<String, dynamic>>> listPaperDocs({String query = ''}) async {
    await _ensureToken();

    final searchQuery = query.isNotEmpty
        ? query
        : ''; // Empty query lists recent Paper docs
    final body = json.encode({
      'query': searchQuery,
      'options': {
        'file_categories': ['.paper'],
        'max_results': 100,
      },
    });

    final resp = await _rpcPost('/files/search_v2', body);
    final matches = (resp['matches'] as List?) ?? [];

    return matches.map((m) {
      final metadata = ((m as Map)['metadata'] as Map)['metadata'] as Map<String, dynamic>;
      return <String, dynamic>{
        'name': metadata['name'] ?? 'Untitled',
        'id': metadata['id'],
        'path': metadata['path_display'],
        if (metadata['server_modified'] != null) 'lastModified': metadata['server_modified'],
        if (metadata['size'] != null) 'size': (metadata['size'] as num).toInt(),
        'isPaper': true,
      };
    }).toList();
  }

  /// Export a Dropbox Paper document to markdown or HTML.
  ///
  /// [docPath] — the Dropbox path to the Paper document.
  /// [format] — 'markdown' or 'html' (default: 'markdown').
  Future<String> exportPaperDoc(String docPath, {String format = 'markdown'}) async {
    await _ensureToken();

    final uri = Uri.parse('$_contentBase/files/export');
    final req = http.Request('POST', uri);
    req.headers['Authorization'] = 'Bearer $_accessToken';
    req.headers['Dropbox-API-Arg'] = json.encode({
      'path': docPath,
      'export_format': format,
    });

    final resp = await http.Response.fromStream(await req.send());

    if (resp.statusCode != 200) {
      throw Exception('Paper export failed (${resp.statusCode}): ${resp.body}');
    }

    return resp.body;
  }
}
