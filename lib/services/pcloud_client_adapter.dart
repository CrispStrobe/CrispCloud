// lib/services/pcloud_client_adapter.dart
//
// pCloud adapter using the pCloud API with pure HTTP.
// OAuth2 browser flow: open browser → user authorizes → redirect to
// localhost:43826 callback → exchange code for token → store in SecureStorage.
//
// pCloud supports two API endpoints:
//   https://api.pcloud.com  (global / US)
//   https://eapi.pcloud.com (EU)
//
// Key endpoints used:
//   listfolder      — list directory contents
//   uploadfile      — upload files
//   getfilelink     — get a download link for a file
//   downloadfile    — (via getfilelink URL)
//   createfolder    — create a folder
//   deletefile      — delete a file
//   deletefolder    — delete a folder (must be empty) / deletefolderrecursive
//   renamefile      — rename a file
//   renamefolder    — rename a folder
//   movefile        — move a file
//   movefolder      — move a folder
//   userinfo        — get account info (email)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'cloud_storage_interface.dart';
import 'pcloud_config_service.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';

class PCloudClientAdapter extends CloudStorageClient {
  static final _log = Log('PCloudClient');

  final PCloudConfigService _config;

  PCloudConfigService get config => _config;

  String? _accessToken;
  String? _email;
  String? _appKey;
  bool _useEuApi;
  bool _authenticated = false;

  // pCloud folder IDs are integers; we keep a path → folderID cache.
  final Map<String, int> _pathToFolderId = {'/': 0};

  static const _authUrlGlobal = 'https://my.pcloud.com/oauth2/authorize';
  static const _authUrlEu = 'https://emy.pcloud.com/oauth2/authorize';
  static const _tokenUrlGlobal = 'https://api.pcloud.com/oauth2_token';
  static const _tokenUrlEu = 'https://eapi.pcloud.com/oauth2_token';
  static const _redirectPort = 43826;

  PCloudClientAdapter({required dynamic config, bool useEuApi = false})
      : _config = (config is PCloudConfigService)
            ? config
            : PCloudConfigService(configPath: '', secureStorage: InMemorySecureStorage()),
        _useEuApi = useEuApi;

  String get _apiBase => _useEuApi ? 'https://eapi.pcloud.com' : 'https://api.pcloud.com';
  String get _authUrl => _useEuApi ? _authUrlEu : _authUrlGlobal;
  String get _tokenUrl => _useEuApi ? _tokenUrlEu : _tokenUrlGlobal;

  @override
  String get providerName => 'pCloud';

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated => _authenticated && _accessToken != null;

  String? get accessToken => _accessToken;

  @override
  String? get userId => _email;

  @override
  String? get bucketId => null;

  // Capability flags
  @override
  bool get supportsVersioning => false;
  @override
  bool get supportsSharing => true;
  @override
  bool get supportsSearch => false;
  @override
  bool get supportsThumbnails => false;
  @override
  bool get supportsTrash => true;

  // --- Auth ---

  @override
  Future<void> login(String identity, String password, {String? twoFactorCode}) async {
    // identity format: "appKey" or "appKey|eu" to select EU endpoint
    final parts = identity.split('|');
    _appKey = parts[0].trim();
    if (parts.length > 1 && parts[1].trim().toLowerCase() == 'eu') {
      _useEuApi = true;
    }

    if (_appKey == null || _appKey!.isEmpty) {
      throw Exception('App Key is required');
    }

    // Try stored access token (pCloud long-lived tokens don't expire)
    final creds = await _config.readCredentials();
    if (creds != null &&
        creds['access_token'] != null &&
        creds['access_token']!.isNotEmpty &&
        creds['app_key'] == _appKey) {
      _accessToken = creds['access_token'];
      _email = creds['email'];
      if (creds['eu_api'] != null) {
        _useEuApi = creds['eu_api'] == 'true';
      }
      try {
        await _fetchUserInfo();
        _authenticated = true;
        return;
      } catch (_) {
        // Stored token invalid; proceed to browser flow
        _accessToken = null;
      }
    }

    if (kIsWeb) {
      throw Exception('pCloud OAuth2 on web requires a different redirect flow.');
    }

    await _browserOAuthFlow();
    _authenticated = true;
    await _fetchUserInfo();

    await _config.saveCredentials({
      'app_key': _appKey!,
      'access_token': _accessToken ?? '',
      'email': _email ?? '',
      'eu_api': _useEuApi.toString(),
    });
  }

  @override
  Future<bool> is2faNeeded(String email) async => false;

  @override
  Future<void> logout() async {
    // pCloud has no token-revocation endpoint for OAuth2 implicit tokens
    _accessToken = null;
    _email = null;
    _authenticated = false;
    _pathToFolderId
      ..clear()
      ..['/'] = 0;
  }

  Future<bool> restoreCredentials() async {
    final creds = await _config.readCredentials();
    if (creds == null ||
        creds['access_token'] == null ||
        creds['access_token']!.isEmpty) {
      return false;
    }
    _appKey = creds['app_key'];
    _accessToken = creds['access_token'];
    _email = creds['email'];
    _useEuApi = creds['eu_api'] == 'true';

    try {
      await _fetchUserInfo();
      _authenticated = true;
      return true;
    } catch (e) {
      _log.warn('Token validation failed during restore', e);
      return false;
    }
  }

  // --- Path helpers ---

  /// Resolve a slash-delimited virtual path to a pCloud folder ID.
  /// pCloud identifies folders by numeric ID (folderid), not path strings.
  /// We walk the tree and cache each segment as we discover it.
  Future<int> _resolveFolderId(String path) async {
    if (path == '/' || path.isEmpty) return 0;

    // Normalise
    final clean = path.startsWith('/') ? path : '/$path';
    if (_pathToFolderId.containsKey(clean)) return _pathToFolderId[clean]!;

    // Walk from root
    final segments = clean.split('/').where((s) => s.isNotEmpty).toList();
    int currentId = 0;
    String builtPath = '';

    for (final seg in segments) {
      builtPath += '/$seg';
      if (_pathToFolderId.containsKey(builtPath)) {
        currentId = _pathToFolderId[builtPath]!;
        continue;
      }
      // List the parent folder to find the child
      final uri = Uri.parse('$_apiBase/listfolder').replace(queryParameters: {
        'access_token': _accessToken!,
        'folderid': currentId.toString(),
        'nofiles': '1',
      });
      final resp = await http.get(uri);
      final data = _parseResponse(resp, 'listfolder');
      final contents = (data['metadata']?['contents'] as List?) ?? [];
      bool found = false;
      for (final item in contents) {
        if (item['isfolder'] == true && item['name'] == seg) {
          final fid = (item['folderid'] as num).toInt();
          _pathToFolderId[builtPath] = fid;
          currentId = fid;
          found = true;
          break;
        }
      }
      if (!found) {
        throw Exception('pCloud folder not found: $builtPath');
      }
    }

    return currentId;
  }

  /// Return the parent path and the last segment from a full path.
  ({String parent, String name}) _splitPath(String fullPath) {
    final norm = fullPath.endsWith('/') && fullPath.length > 1
        ? fullPath.substring(0, fullPath.length - 1)
        : fullPath;
    final parent = p.posix.dirname(norm);
    final name = p.posix.basename(norm);
    return (parent: parent.isEmpty ? '/' : parent, name: name);
  }

  // --- Path Resolution ---

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    _ensureToken();
    try {
      final folderId = await _resolveFolderId(path);
      return {'folderid': folderId, 'path': path};
    } catch (_) {
      return null;
    }
  }

  // --- List ---

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    _ensureToken();

    final folderId = await _resolveFolderId(path);
    final uri = Uri.parse('$_apiBase/listfolder').replace(queryParameters: {
      'access_token': _accessToken!,
      'folderid': folderId.toString(),
    });

    final resp = await http.get(uri);
    final data = _parseResponse(resp, 'listfolder');
    final contents = (data['metadata']?['contents'] as List?) ?? [];

    final folders = <Map<String, dynamic>>[];
    final files = <Map<String, dynamic>>[];

    for (final item in contents) {
      final name = item['name'] as String? ?? 'Unknown';
      final isFolder = item['isfolder'] == true;

      final entry = <String, dynamic>{
        'name': name,
        'uuid': isFolder
            ? 'd_${item['folderid']}'
            : 'f_${item['fileid']}',
        if (item['modified'] != null)
          'lastModified': item['modified'] as String,
        if (!isFolder && item['size'] != null)
          'size': (item['size'] as num).toInt(),
      };

      if (isFolder) {
        // Cache the folder ID for later navigation
        final childPath = path == '/' ? '/$name' : '$path/$name';
        _pathToFolderId[childPath] = (item['folderid'] as num).toInt();
        folders.add(entry);
      } else {
        files.add(entry);
      }
    }

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
    _ensureToken();

    final folderId = await _resolveFolderId(targetPath);

    // pCloud uploadfile uses multipart/form-data
    final uri = Uri.parse('$_apiBase/uploadfile');
    final request = http.MultipartRequest('POST', uri)
      ..fields['access_token'] = _accessToken!
      ..fields['folderid'] = folderId.toString()
      ..fields['filename'] = fileName
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        fileData,
        filename: fileName,
      ));

    final streamed = await request.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 200) {
      throw Exception('pCloud upload failed (${resp.statusCode}): ${resp.body}');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final result = data['result'] as int? ?? -1;
    if (result != 0) {
      throw Exception('pCloud upload error (result=$result): ${data['error'] ?? resp.body}');
    }

    onProgress?.call(fileData.length, fileData.length);
  }

  // --- Download ---

  @override
  Future<Uint8List> downloadFileBytes(String remotePath, {Function(int, int)? onProgress}) async {
    _ensureToken();

    // Step 1: resolve file ID from path
    final fileId = await _resolveFileId(remotePath);

    // Step 2: get a download link
    final linkUri = Uri.parse('$_apiBase/getfilelink').replace(queryParameters: {
      'access_token': _accessToken!,
      'fileid': fileId.toString(),
    });

    final linkResp = await http.get(linkUri);
    final linkData = _parseResponse(linkResp, 'getfilelink');

    // pCloud returns a list of hosts and a path to form the download URL
    final hosts = linkData['hosts'] as List?;
    final dlPath = linkData['path'] as String?;
    if (hosts == null || hosts.isEmpty || dlPath == null) {
      throw Exception('pCloud: no download link returned');
    }
    final downloadUrl = 'https://${hosts.first}$dlPath';

    // Step 3: download the file
    final dlResp = await http.get(Uri.parse(downloadUrl));
    if (dlResp.statusCode != 200) {
      throw Exception('pCloud download failed (${dlResp.statusCode})');
    }

    onProgress?.call(dlResp.bodyBytes.length, dlResp.bodyBytes.length);
    return dlResp.bodyBytes;
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    final bytes = await downloadFileBytes(remotePath, onProgress: onProgress);
    await File(localPath).writeAsBytes(bytes);
  }

  // --- Folder ---

  @override
  Future<void> createFolderPath(String path) async {
    _ensureToken();

    final split = _splitPath(path);
    final parentId = await _resolveFolderId(split.parent);

    final uri = Uri.parse('$_apiBase/createfolder').replace(queryParameters: {
      'access_token': _accessToken!,
      'folderid': parentId.toString(),
      'name': split.name,
    });

    try {
      final resp = await http.get(uri);
      final data = _parseResponse(resp, 'createfolder');
      // Cache new folder ID
      final newId = (data['metadata']?['folderid'] as num?)?.toInt();
      if (newId != null) {
        _pathToFolderId[path] = newId;
      }
    } catch (e) {
      // result=2002 = folder already exists
      if (!e.toString().contains('2002')) rethrow;
    }
  }

  // --- Delete ---

  @override
  Future<void> deletePath(String path) async {
    _ensureToken();

    // Try as a file first; fall back to folder
    try {
      final fileId = await _resolveFileId(path);
      final uri = Uri.parse('$_apiBase/deletefile').replace(queryParameters: {
        'access_token': _accessToken!,
        'fileid': fileId.toString(),
      });
      final resp = await http.get(uri);
      _parseResponse(resp, 'deletefile');
      return;
    } catch (_) {}

    // Delete folder recursively
    final folderId = await _resolveFolderId(path);
    final uri = Uri.parse('$_apiBase/deletefolderrecursive').replace(queryParameters: {
      'access_token': _accessToken!,
      'folderid': folderId.toString(),
    });
    final resp = await http.get(uri);
    _parseResponse(resp, 'deletefolderrecursive');
    _pathToFolderId.remove(path);
  }

  // --- Move ---

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    _ensureToken();

    final fileName = p.posix.basename(sourcePath);
    // targetPath is the destination directory
    final destFolderId = await _resolveFolderId(targetPath);

    // Try as a file first
    try {
      final fileId = await _resolveFileId(sourcePath);
      final uri = Uri.parse('$_apiBase/movefile').replace(queryParameters: {
        'access_token': _accessToken!,
        'fileid': fileId.toString(),
        'tofolderid': destFolderId.toString(),
        'toname': fileName,
      });
      final resp = await http.get(uri);
      _parseResponse(resp, 'movefile');
      return;
    } catch (_) {}

    // Move folder
    final folderId = await _resolveFolderId(sourcePath);
    final uri = Uri.parse('$_apiBase/movefolder').replace(queryParameters: {
      'access_token': _accessToken!,
      'folderid': folderId.toString(),
      'tofolderid': destFolderId.toString(),
      'toname': fileName,
    });
    final resp = await http.get(uri);
    _parseResponse(resp, 'movefolder');
    _pathToFolderId.remove(sourcePath);
  }

  // --- Rename ---

  @override
  Future<void> renamePath(String path, String newName) async {
    _ensureToken();

    // Try as a file first
    try {
      final fileId = await _resolveFileId(path);
      final uri = Uri.parse('$_apiBase/renamefile').replace(queryParameters: {
        'access_token': _accessToken!,
        'fileid': fileId.toString(),
        'toname': newName,
      });
      final resp = await http.get(uri);
      _parseResponse(resp, 'renamefile');
      return;
    } catch (_) {}

    // Rename folder
    final folderId = await _resolveFolderId(path);
    final parentId = await _resolveFolderId(_splitPath(path).parent);
    final uri = Uri.parse('$_apiBase/renamefolder').replace(queryParameters: {
      'access_token': _accessToken!,
      'folderid': folderId.toString(),
      'tofolderid': parentId.toString(),
      'toname': newName,
    });
    final resp = await http.get(uri);
    _parseResponse(resp, 'renamefolder');

    // Update cache
    final parent = _splitPath(path).parent;
    _pathToFolderId.remove(path);
    final newPath = parent == '/' ? '/$newName' : '$parent/$newName';
    _pathToFolderId[newPath] = folderId;
  }

  // --- Internal helpers ---

  void _ensureToken() {
    if (_accessToken == null) throw Exception('Not authenticated');
  }

  /// Get the numeric file ID for a given path by listing the parent folder.
  Future<int> _resolveFileId(String filePath) async {
    final split = _splitPath(filePath);
    final parentId = await _resolveFolderId(split.parent);

    final uri = Uri.parse('$_apiBase/listfolder').replace(queryParameters: {
      'access_token': _accessToken!,
      'folderid': parentId.toString(),
    });
    final resp = await http.get(uri);
    final data = _parseResponse(resp, 'listfolder');
    final contents = (data['metadata']?['contents'] as List?) ?? [];

    for (final item in contents) {
      if (item['isfolder'] != true && item['name'] == split.name) {
        return (item['fileid'] as num).toInt();
      }
    }
    throw Exception('pCloud file not found: $filePath');
  }

  Future<void> _fetchUserInfo() async {
    _ensureToken();
    final uri = Uri.parse('$_apiBase/userinfo').replace(queryParameters: {
      'access_token': _accessToken!,
    });
    final resp = await http.get(uri);
    final data = _parseResponse(resp, 'userinfo');
    _email = data['email'] as String?;
  }

  /// Parse a pCloud API JSON response and check the result code.
  Map<String, dynamic> _parseResponse(http.Response resp, String endpoint) {
    if (resp.statusCode != 200) {
      throw Exception('pCloud $endpoint HTTP error (${resp.statusCode}): ${resp.body}');
    }
    if (resp.body.isEmpty) return {};
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final result = data['result'] as int? ?? 0;
    if (result != 0) {
      throw Exception('pCloud $endpoint error (result=$result): ${data['error'] ?? resp.body}');
    }
    return data;
  }

  Future<void> _browserOAuthFlow() async {
    final redirectUri = 'http://localhost:$_redirectPort';

    final authUri = Uri.parse(_authUrl).replace(queryParameters: {
      'client_id': _appKey!,
      'response_type': 'code',
      'redirect_uri': redirectUri,
    });

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _redirectPort);

    if (await canLaunchUrl(authUri)) {
      await launchUrl(authUri, mode: LaunchMode.externalApplication);
    } else {
      await server.close();
      throw Exception('Could not open browser for pCloud authorization');
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
            ..write(
                '<html><body><h2>Authorization denied: $error</h2>'
                '<p>You can close this window.</p></body></html>');
          await request.response.close();
          break;
        }

        if (code != null) {
          authCode = code;
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write(
                '<html><body><h2>Authorization successful!</h2>'
                '<p>You can close this window and return to CrispCloud.</p></body></html>');
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
      throw Exception('pCloud authorization was cancelled or failed');
    }

    // Exchange code for access token
    final tokenUri = Uri.parse(_tokenUrl).replace(queryParameters: {
      'client_id': _appKey!,
      'code': authCode,
      'redirect_uri': redirectUri,
    });

    final tokenResp = await http.get(tokenUri);
    if (tokenResp.statusCode != 200) {
      throw Exception(
          'pCloud token exchange failed (${tokenResp.statusCode}): ${tokenResp.body}');
    }

    final tokenData = json.decode(tokenResp.body) as Map<String, dynamic>;
    final tokenResult = tokenData['result'] as int? ?? -1;
    if (tokenResult != 0) {
      throw Exception(
          'pCloud token error (result=$tokenResult): ${tokenData['error'] ?? tokenResp.body}');
    }

    _accessToken = tokenData['access_token'] as String?;
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw Exception('pCloud: no access token in response');
    }

    // If the response indicates EU location, switch to EU API
    final locationId = tokenData['locationid'] as int?;
    if (locationId == 2) {
      _useEuApi = true;
      _log.info('pCloud account is on EU servers; switching to eapi.pcloud.com');
    }
  }
}
