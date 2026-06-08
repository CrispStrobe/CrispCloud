// lib/services/gdrive_client_adapter.dart
//
// Google Drive adapter using the Drive REST API v3 with pure HTTP.
// OAuth2 browser flow: opens browser → user authorizes → redirect to
// localhost callback → exchange code for tokens → store in SecureStorage.
//
// Does NOT depend on googleapis or google_sign_in packages.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'cloud_storage_interface.dart';
import 'gdrive_config_service.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';

class GDriveClientAdapter extends CloudStorageClient {
  static const _log = Log('GDriveClient');

  final GDriveConfigService _config;

  GDriveConfigService get config => _config;

  String? _accessToken;
  String? _refreshToken;
  String? _email;
  String? _clientId;
  String? _clientSecret;
  DateTime? _tokenExpiry;
  bool _authenticated = false;

  /// Folder-ID stack: Google Drive uses file IDs, not paths.
  /// We maintain a map of path → folder ID for navigation.
  final Map<String, String> _pathToId = {'/': 'root'};

  static const _apiBase = 'https://www.googleapis.com/drive/v3';
  static const _uploadBase = 'https://www.googleapis.com/upload/drive/v3';
  static const _authUrl = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const _scopes = 'https://www.googleapis.com/auth/drive';
  static const _redirectPort = 43823; // Arbitrary high port for localhost redirect

  GDriveClientAdapter({required dynamic config})
      : _config = (config is GDriveConfigService)
            ? config
            : GDriveConfigService(configPath: '', secureStorage: InMemorySecureStorage());

  @override
  String get providerName => 'Google Drive';

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
    // identity format: "clientId|clientSecret" or just "clientId" for public clients
    // password: not used (OAuth2 — handled via browser redirect)

    final parts = identity.split('|');
    _clientId = parts[0].trim();
    _clientSecret = parts.length > 1 ? parts[1].trim() : null;

    if (_clientId == null || _clientId!.isEmpty) {
      throw Exception('Client ID is required');
    }

    // Check for stored refresh token first (re-auth without browser)
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
      } catch (_) {
        // Refresh failed — fall through to browser flow
      }
    }

    // Browser-based OAuth2 flow
    if (kIsWeb) {
      throw Exception('Google Drive OAuth2 on web requires a different redirect flow. Use desktop or mobile.');
    }

    await _browserOAuthFlow();
    _authenticated = true;

    // Fetch user email for display
    await _fetchUserEmail();

    // Persist credentials
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
    // Optionally revoke the token
    if (_accessToken != null) {
      try {
        await http.post(Uri.parse('https://oauth2.googleapis.com/revoke?token=$_accessToken'));
      } catch (_) {}
    }
    _accessToken = null;
    _refreshToken = null;
    _email = null;
    _authenticated = false;
    _pathToId.clear();
    _pathToId['/'] = 'root';
  }

  @override
  Future<Uint8List?> getThumbnail(String remotePath) async {
    await _ensureToken();
    final fileId = await _resolveFileId(remotePath);
    if (fileId == null) return null;
    try {
      final uri = Uri.parse('$_apiBase/files/$fileId?fields=thumbnailLink');
      final resp = await http.get(uri, headers: {'Authorization': 'Bearer $_accessToken'});
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body);
      final thumbUrl = data['thumbnailLink'] as String?;
      if (thumbUrl == null) return null;
      final thumbResp = await http.get(Uri.parse(thumbUrl));
      if (thumbResp.statusCode == 200) return thumbResp.bodyBytes;
    } catch (_) {}
    return null;
  }

  /// Restore credentials from secure storage for auto-login.
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

  // --- Path Resolution ---

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    final id = await _resolvePathToId(path);
    if (id == null) return null;
    return {'id': id, 'path': path};
  }

  /// Resolve a path like /Documents/Photos to a Google Drive folder ID.
  /// Caches results in [_pathToId].
  Future<String?> _resolvePathToId(String path) async {
    if (path == '/' || path.isEmpty) return 'root';
    if (_pathToId.containsKey(path)) return _pathToId[path];

    // Walk segments: /a/b/c → resolve a under root, b under a, c under b
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    String parentId = 'root';
    String accumulated = '';

    for (final segment in segments) {
      accumulated = '$accumulated/$segment';

      if (_pathToId.containsKey(accumulated)) {
        parentId = _pathToId[accumulated]!;
        continue;
      }

      // Query for folder with this name under parent
      final query = "name='${_escapeQuery(segment)}' and '$parentId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final resp = await _apiGet('/files', queryParams: {
        'q': query,
        'fields': 'files(id,name)',
        'pageSize': '1',
      });

      final files = (resp['files'] as List?) ?? [];
      if (files.isEmpty) return null;

      final folderId = files[0]['id'] as String;
      _pathToId[accumulated] = folderId;
      parentId = folderId;
    }

    return parentId;
  }

  // --- List ---

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    await _ensureToken();

    final parentId = await _resolvePathToId(path) ?? 'root';
    final query = "'$parentId' in parents and trashed=false";

    final folders = <Map<String, dynamic>>[];
    final files = <Map<String, dynamic>>[];
    String? pageToken;

    do {
      final params = <String, String>{
        'q': query,
        'fields': 'nextPageToken,files(id,name,mimeType,size,modifiedTime,parents)',
        'pageSize': '1000',
        'orderBy': 'folder,name',
      };
      if (pageToken != null) params['pageToken'] = pageToken;

      final resp = await _apiGet('/files', queryParams: params);

      for (final item in (resp['files'] as List?) ?? []) {
        final map = item as Map<String, dynamic>;
        final isFolder = map['mimeType'] == 'application/vnd.google-apps.folder';
        final name = map['name'] as String? ?? 'Unknown';
        final id = map['id'] as String;

        // Cache folder ID
        if (isFolder) {
          _pathToId['$path${path.endsWith('/') ? '' : '/'}$name'] = id;
        }

        final entry = <String, dynamic>{
          'name': name,
          'uuid': id,
          if (map['modifiedTime'] != null) 'lastModified': map['modifiedTime'],
          if (map['size'] != null) 'size': int.tryParse(map['size'].toString()) ?? 0,
        };

        if (isFolder) {
          folders.add(entry);
        } else {
          files.add(entry);
        }
      }

      pageToken = resp['nextPageToken'] as String?;
    } while (pageToken != null);

    return {'folders': folders, 'files': files};
  }

  // --- Shared Drives ---

  /// List all shared drives the user has access to.
  /// Returns a list of `{id, name}` maps.
  Future<List<Map<String, String>>> listSharedDrives() async {
    await _ensureToken();
    final drives = <Map<String, String>>[];
    String? pageToken;

    do {
      final params = <String, String>{
        'pageSize': '100',
        'fields': 'nextPageToken,drives(id,name)',
      };
      if (pageToken != null) params['pageToken'] = pageToken;

      final resp = await _apiGet('/drives', queryParams: params);
      for (final item in (resp['drives'] as List?) ?? []) {
        final map = item as Map<String, dynamic>;
        drives.add({
          'id': map['id'] as String,
          'name': map['name'] as String? ?? 'Unknown',
        });
      }
      pageToken = resp['nextPageToken'] as String?;
    } while (pageToken != null);

    return drives;
  }

  /// List files in a shared drive at the given path.
  /// [driveId] is the shared drive ID from [listSharedDrives].
  Future<Map<String, dynamic>> listSharedDrivePath(
    String driveId,
    String path,
  ) async {
    await _ensureToken();

    final parentId = path == '/' || path.isEmpty
        ? driveId
        : await _resolveSharedDrivePathToId(driveId, path) ?? driveId;

    final query = "'$parentId' in parents and trashed=false";
    final folders = <Map<String, dynamic>>[];
    final files = <Map<String, dynamic>>[];
    String? pageToken;

    do {
      final params = <String, String>{
        'q': query,
        'fields': 'nextPageToken,files(id,name,mimeType,size,modifiedTime,parents)',
        'pageSize': '1000',
        'orderBy': 'folder,name',
        'corpora': 'drive',
        'driveId': driveId,
        'includeItemsFromAllDrives': 'true',
        'supportsAllDrives': 'true',
      };
      if (pageToken != null) params['pageToken'] = pageToken;

      final resp = await _apiGet('/files', queryParams: params);

      for (final item in (resp['files'] as List?) ?? []) {
        final map = item as Map<String, dynamic>;
        final isFolder = map['mimeType'] == 'application/vnd.google-apps.folder';
        final name = map['name'] as String? ?? 'Unknown';
        final id = map['id'] as String;

        final entry = <String, dynamic>{
          'name': name,
          'uuid': id,
          if (map['modifiedTime'] != null) 'lastModified': map['modifiedTime'],
          if (map['size'] != null) 'size': int.tryParse(map['size'].toString()) ?? 0,
        };

        if (isFolder) {
          folders.add(entry);
        } else {
          files.add(entry);
        }
      }

      pageToken = resp['nextPageToken'] as String?;
    } while (pageToken != null);

    return {'folders': folders, 'files': files};
  }

  /// Resolve a path inside a shared drive to a folder ID.
  Future<String?> _resolveSharedDrivePathToId(String driveId, String path) async {
    if (path == '/' || path.isEmpty) return driveId;

    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    String parentId = driveId;

    for (final segment in segments) {
      final query =
          "name='${_escapeQuery(segment)}' and '$parentId' in parents "
          "and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final resp = await _apiGet('/files', queryParams: {
        'q': query,
        'fields': 'files(id,name)',
        'pageSize': '1',
        'corpora': 'drive',
        'driveId': driveId,
        'includeItemsFromAllDrives': 'true',
        'supportsAllDrives': 'true',
      });

      final files = (resp['files'] as List?) ?? [];
      if (files.isEmpty) return null;
      parentId = files[0]['id'] as String;
    }

    return parentId;
  }

  // --- Starred Files ---

  /// List starred files across the user's Drive.
  Future<List<Map<String, dynamic>>> listStarredFiles() async {
    await _ensureToken();
    final results = <Map<String, dynamic>>[];
    String? pageToken;

    do {
      final params = <String, String>{
        'q': 'starred=true and trashed=false',
        'fields': 'nextPageToken,files(id,name,mimeType,size,modifiedTime)',
        'pageSize': '1000',
        'orderBy': 'modifiedTime desc',
      };
      if (pageToken != null) params['pageToken'] = pageToken;

      final resp = await _apiGet('/files', queryParams: params);

      for (final item in (resp['files'] as List?) ?? []) {
        final map = item as Map<String, dynamic>;
        results.add({
          'name': map['name'] as String? ?? 'Unknown',
          'uuid': map['id'] as String,
          'type': map['mimeType'] == 'application/vnd.google-apps.folder' ? 'folder' : 'file',
          if (map['modifiedTime'] != null) 'lastModified': map['modifiedTime'],
          if (map['size'] != null) 'size': int.tryParse(map['size'].toString()) ?? 0,
        });
      }

      pageToken = resp['nextPageToken'] as String?;
    } while (pageToken != null);

    return results;
  }

  /// Star or unstar a file by its ID.
  Future<void> setStarred(String fileId, bool starred) async {
    await _ensureToken();
    final url = Uri.parse('$_apiBase/files/$fileId');
    await http.patch(
      url,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      },
      body: json.encode({'starred': starred}),
    );
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

    final parentId = await _resolvePathToId(targetPath) ?? 'root';

    // Check if file already exists — update instead of create
    final existingId = await _findFileInFolder(parentId, fileName);

    if (existingId != null) {
      // Update existing file
      final uri = Uri.parse('$_uploadBase/files/$existingId?uploadType=media');
      final req = http.Request('PATCH', uri);
      req.headers['Authorization'] = 'Bearer $_accessToken';
      req.headers['Content-Type'] = 'application/octet-stream';
      req.bodyBytes = Uint8List.fromList(fileData);

      final resp = await http.Response.fromStream(await req.send());
      if (resp.statusCode != 200) {
        throw Exception('GDrive upload update failed (${resp.statusCode}): ${resp.body}');
      }
    } else {
      // Multipart upload: metadata + file content
      final metadata = json.encode({
        'name': fileName,
        'parents': [parentId],
      });

      final boundary = 'crisp_cloud_${DateTime.now().millisecondsSinceEpoch}';
      final body = StringBuffer();
      body.writeln('--$boundary');
      body.writeln('Content-Type: application/json; charset=UTF-8');
      body.writeln();
      body.writeln(metadata);
      body.writeln('--$boundary');
      body.writeln('Content-Type: application/octet-stream');
      body.writeln();
      // We need binary content, so use raw bytes approach

      final metaPart = utf8.encode(
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n'
        '\r\n'
        '$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: application/octet-stream\r\n'
        '\r\n',
      );
      final endPart = utf8.encode('\r\n--$boundary--');

      final bodyBytes = Uint8List.fromList([...metaPart, ...fileData, ...endPart]);

      final uri = Uri.parse('$_uploadBase/files?uploadType=multipart');
      final req = http.Request('POST', uri);
      req.headers['Authorization'] = 'Bearer $_accessToken';
      req.headers['Content-Type'] = 'multipart/related; boundary=$boundary';
      req.bodyBytes = bodyBytes;

      final resp = await http.Response.fromStream(await req.send());
      if (resp.statusCode != 200) {
        throw Exception('GDrive upload failed (${resp.statusCode}): ${resp.body}');
      }
    }

    onProgress?.call(fileData.length, fileData.length);
  }

  // --- Google Docs MIME type handling ---

  /// Google Apps MIME types that require export (can't be downloaded directly).
  static const _googleDocsMimeTypes = <String, String>{
    'application/vnd.google-apps.document': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.google-apps.spreadsheet': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.google-apps.presentation': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/vnd.google-apps.drawing': 'application/pdf',
    'application/vnd.google-apps.script': 'application/vnd.google-apps.script+json',
  };

  /// File extensions for exported Google Docs.
  static const _exportExtensions = <String, String>{
    'application/vnd.google-apps.document': '.docx',
    'application/vnd.google-apps.spreadsheet': '.xlsx',
    'application/vnd.google-apps.presentation': '.pptx',
    'application/vnd.google-apps.drawing': '.pdf',
    'application/vnd.google-apps.script': '.json',
  };

  /// Check if a MIME type is a Google Apps type that requires export.
  static bool isGoogleDocsMimeType(String mimeType) =>
      _googleDocsMimeTypes.containsKey(mimeType);

  /// Get the export extension for a Google Docs MIME type.
  static String? getExportExtension(String mimeType) =>
      _exportExtensions[mimeType];

  /// Export a Google Docs file to the specified format.
  ///
  /// [fileId] — the Google Drive file ID.
  /// [exportMimeType] — the target MIME type (e.g., 'application/pdf').
  /// Defaults to the standard export format for the document type.
  Future<Uint8List> exportGoogleDoc(String fileId, {String? exportMimeType}) async {
    await _ensureToken();

    // Get file metadata to determine MIME type
    final meta = await _apiGet('/files/$fileId', queryParams: {
      'fields': 'mimeType',
    });
    final docMimeType = meta['mimeType'] as String? ?? '';
    final targetMime = exportMimeType ?? _googleDocsMimeTypes[docMimeType];
    if (targetMime == null) {
      throw Exception('Not a Google Docs file or unknown type: $docMimeType');
    }

    final uri = Uri.parse('$_apiBase/files/$fileId/export?mimeType=${Uri.encodeComponent(targetMime)}');
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $_accessToken'});

    if (resp.statusCode != 200) {
      throw Exception('GDrive export failed (${resp.statusCode}): ${resp.body}');
    }

    return resp.bodyBytes;
  }

  /// List available export formats for a Google Docs file.
  static List<Map<String, String>> getExportFormats(String mimeType) {
    switch (mimeType) {
      case 'application/vnd.google-apps.document':
        return [
          {'mimeType': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'ext': '.docx', 'label': 'Word'},
          {'mimeType': 'application/pdf', 'ext': '.pdf', 'label': 'PDF'},
          {'mimeType': 'text/plain', 'ext': '.txt', 'label': 'Plain Text'},
          {'mimeType': 'application/rtf', 'ext': '.rtf', 'label': 'Rich Text'},
          {'mimeType': 'text/html', 'ext': '.html', 'label': 'HTML'},
          {'mimeType': 'application/epub+zip', 'ext': '.epub', 'label': 'EPUB'},
        ];
      case 'application/vnd.google-apps.spreadsheet':
        return [
          {'mimeType': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'ext': '.xlsx', 'label': 'Excel'},
          {'mimeType': 'application/pdf', 'ext': '.pdf', 'label': 'PDF'},
          {'mimeType': 'text/csv', 'ext': '.csv', 'label': 'CSV'},
          {'mimeType': 'text/tab-separated-values', 'ext': '.tsv', 'label': 'TSV'},
        ];
      case 'application/vnd.google-apps.presentation':
        return [
          {'mimeType': 'application/vnd.openxmlformats-officedocument.presentationml.presentation', 'ext': '.pptx', 'label': 'PowerPoint'},
          {'mimeType': 'application/pdf', 'ext': '.pdf', 'label': 'PDF'},
          {'mimeType': 'text/plain', 'ext': '.txt', 'label': 'Plain Text'},
        ];
      case 'application/vnd.google-apps.drawing':
        return [
          {'mimeType': 'application/pdf', 'ext': '.pdf', 'label': 'PDF'},
          {'mimeType': 'image/png', 'ext': '.png', 'label': 'PNG'},
          {'mimeType': 'image/svg+xml', 'ext': '.svg', 'label': 'SVG'},
        ];
      default:
        return [];
    }
  }

  // --- File Versions (Revisions API) ---

  /// List all revisions (versions) of a file.
  ///
  /// Returns a list of revision metadata maps with keys:
  ///   id, modifiedTime, originalFilename, mimeType, size, lastModifyingUser
  Future<List<Map<String, dynamic>>> listVersions(String fileId) async {
    await _ensureToken();

    final resp = await _apiGet('/files/$fileId/revisions', queryParams: {
      'fields': 'revisions(id,modifiedTime,originalFilename,mimeType,size,lastModifyingUser/displayName,keepForever)',
      'pageSize': '1000',
    });

    final revisions = (resp['revisions'] as List?) ?? [];
    return revisions.map((r) {
      final rev = r as Map<String, dynamic>;
      return <String, dynamic>{
        'id': rev['id'],
        'modifiedTime': rev['modifiedTime'],
        if (rev['originalFilename'] != null) 'originalFilename': rev['originalFilename'],
        if (rev['mimeType'] != null) 'mimeType': rev['mimeType'],
        if (rev['size'] != null) 'size': int.tryParse(rev['size'].toString()) ?? 0,
        if (rev['lastModifyingUser'] != null)
          'lastModifyingUser': (rev['lastModifyingUser'] as Map)['displayName'],
        'keepForever': rev['keepForever'] ?? false,
      };
    }).toList();
  }

  /// Download a specific revision (version) of a file.
  Future<Uint8List> downloadVersion(String fileId, String revisionId) async {
    await _ensureToken();

    final uri = Uri.parse('$_apiBase/files/$fileId/revisions/$revisionId?alt=media');
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $_accessToken'});

    if (resp.statusCode != 200) {
      throw Exception('GDrive revision download failed (${resp.statusCode}): ${resp.body}');
    }

    return resp.bodyBytes;
  }

  /// Pin a revision so it won't be automatically purged.
  Future<void> pinVersion(String fileId, String revisionId) async {
    await _ensureToken();

    final uri = Uri.parse('$_apiBase/files/$fileId/revisions/$revisionId');
    final resp = await http.patch(
      uri,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      },
      body: json.encode({'keepForever': true}),
    );

    if (resp.statusCode != 200) {
      throw Exception('GDrive pin revision failed (${resp.statusCode}): ${resp.body}');
    }
  }

  /// Delete a specific revision (version) of a file.
  Future<void> deleteVersion(String fileId, String revisionId) async {
    await _ensureToken();

    final uri = Uri.parse('$_apiBase/files/$fileId/revisions/$revisionId');
    final resp = await http.delete(uri, headers: {'Authorization': 'Bearer $_accessToken'});

    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw Exception('GDrive delete revision failed (${resp.statusCode}): ${resp.body}');
    }
  }

  // --- Download ---

  @override
  Future<Uint8List> downloadFileBytes(String remotePath, {Function(int, int)? onProgress}) async {
    await _ensureToken();

    final fileId = await _resolveFileId(remotePath);
    if (fileId == null) throw Exception('File not found: $remotePath');

    // Check if this is a Google Docs file that needs export
    final meta = await _apiGet('/files/$fileId', queryParams: {
      'fields': 'mimeType',
    });
    final mimeType = meta['mimeType'] as String? ?? '';

    if (isGoogleDocsMimeType(mimeType)) {
      _log.info('Exporting Google Docs file: $remotePath ($mimeType)');
      final bytes = await exportGoogleDoc(fileId);
      onProgress?.call(bytes.length, bytes.length);
      return bytes;
    }

    final uri = Uri.parse('$_apiBase/files/$fileId?alt=media');
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $_accessToken'});

    if (resp.statusCode != 200) {
      throw Exception('GDrive download failed (${resp.statusCode}): ${resp.body}');
    }

    onProgress?.call(resp.bodyBytes.length, resp.bodyBytes.length);
    return resp.bodyBytes;
  }

  @override
  Future<void> downloadFileByPath(String remotePath, String localPath, {Function(int, int)? onProgress}) async {
    final bytes = await downloadFileBytes(remotePath, onProgress: onProgress);
    final file = File(localPath);
    await file.writeAsBytes(bytes);
  }

  // --- Folder ---

  @override
  Future<void> createFolderPath(String path) async {
    await _ensureToken();

    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    String parentId = 'root';
    String accumulated = '';

    for (final segment in segments) {
      accumulated = '$accumulated/$segment';

      if (_pathToId.containsKey(accumulated)) {
        parentId = _pathToId[accumulated]!;
        continue;
      }

      // Check if folder already exists
      final existing = await _findFolderInParent(parentId, segment);
      if (existing != null) {
        _pathToId[accumulated] = existing;
        parentId = existing;
        continue;
      }

      // Create folder
      final metadata = json.encode({
        'name': segment,
        'mimeType': 'application/vnd.google-apps.folder',
        'parents': [parentId],
      });

      final resp = await _apiPost('/files', body: metadata, contentType: 'application/json');
      final id = resp['id'] as String;
      _pathToId[accumulated] = id;
      parentId = id;
    }
  }

  // --- Copy ---

  @override
  Future<void> copyPath(String sourcePath, String targetPath) async {
    await _ensureToken();
    final fileId = await _resolveFileId(sourcePath);
    if (fileId == null) throw Exception('File not found: $sourcePath');
    final parentId = await _resolvePathToId(targetPath) ?? 'root';
    final fileName = p.posix.basename(sourcePath);
    _log.info('Server-side copy (GDrive): $sourcePath → $targetPath');
    final body = json.encode({
      'name': fileName,
      'parents': [parentId],
    });
    final uri = Uri.parse('$_apiBase/files/$fileId/copy');
    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      },
      body: body,
    );
    if (resp.statusCode != 200) {
      throw Exception('GDrive copy failed (${resp.statusCode}): ${resp.body}');
    }
  }

  // --- Delete / Move / Rename ---

  @override
  Future<void> deletePath(String path) async {
    await _ensureToken();
    final fileId = await _resolveFileId(path);
    if (fileId == null) throw Exception('Not found: $path');

    final uri = Uri.parse('$_apiBase/files/$fileId');
    final resp = await http.delete(uri, headers: {'Authorization': 'Bearer $_accessToken'});

    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception('GDrive delete failed (${resp.statusCode}): ${resp.body}');
    }

    // Invalidate cache
    _pathToId.remove(path);
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    await _ensureToken();
    final fileId = await _resolveFileId(sourcePath);
    if (fileId == null) throw Exception('Not found: $sourcePath');

    // Get current parents
    final meta = await _apiGet('/files/$fileId', queryParams: {'fields': 'parents'});
    final currentParents = ((meta['parents'] as List?) ?? []).join(',');

    // Resolve new parent
    final newParentId = await _resolvePathToId(targetPath) ?? 'root';

    // Move via PATCH
    final uri = Uri.parse('$_apiBase/files/$fileId?addParents=$newParentId&removeParents=$currentParents');
    final resp = await http.patch(uri, headers: {'Authorization': 'Bearer $_accessToken'});

    if (resp.statusCode != 200) {
      throw Exception('GDrive move failed (${resp.statusCode}): ${resp.body}');
    }

    _pathToId.remove(sourcePath);
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    await _ensureToken();
    final fileId = await _resolveFileId(path);
    if (fileId == null) throw Exception('Not found: $path');

    final body = json.encode({'name': newName});
    final uri = Uri.parse('$_apiBase/files/$fileId');
    final resp = await http.patch(
      uri,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (resp.statusCode != 200) {
      throw Exception('GDrive rename failed (${resp.statusCode}): ${resp.body}');
    }

    _pathToId.remove(path);
  }

  // --- Full-text search ---

  @override
  Future<List<Map<String, dynamic>>> fullTextSearch(
    String query,
    String remotePath,
  ) async {
    await _ensureToken();

    // Google Drive API: fullText contains 'query'
    final escaped = _escapeQuery(query);
    final q = "fullText contains '$escaped' and trashed=false";

    final results = <Map<String, dynamic>>[];
    String? pageToken;

    do {
      final params = <String, String>{
        'q': q,
        'fields': 'nextPageToken,files(id,name,mimeType,size,modifiedTime,parents)',
        'pageSize': '100',
      };
      if (pageToken != null) params['pageToken'] = pageToken;

      final resp = await _apiGet('/files', queryParams: params);

      for (final item in (resp['files'] as List?) ?? []) {
        final map = item as Map<String, dynamic>;
        final isFolder = map['mimeType'] == 'application/vnd.google-apps.folder';
        if (isFolder) continue; // Skip folders for content search

        final name = map['name'] as String? ?? 'Unknown';
        final id = map['id'] as String;

        results.add({
          'name': name,
          'uuid': id,
          'path': name, // GDrive doesn't return full path in search
          'size': int.tryParse(map['size']?.toString() ?? '') ?? 0,
          if (map['modifiedTime'] != null) 'lastModified': map['modifiedTime'],
          'snippet': 'Content matches "$query"',
        });
      }

      pageToken = resp['nextPageToken'] as String?;
    } while (pageToken != null);

    return results;
  }

  // --- Internal helpers ---

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
    };
    if (_clientSecret != null) body['client_secret'] = _clientSecret!;

    final resp = await http.post(Uri.parse(_tokenUrl), body: body);
    if (resp.statusCode != 200) {
      throw Exception('Token refresh failed (${resp.statusCode}): ${resp.body}');
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String;
    final expiresIn = data['expires_in'] as int? ?? 3600;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
  }

  Future<void> _browserOAuthFlow() async {
    const redirectUri = 'http://localhost:$_redirectPort';

    final authUri = Uri.parse(_authUrl).replace(queryParameters: {
      'client_id': _clientId!,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _scopes,
      'access_type': 'offline',
      'prompt': 'consent',
    });

    // Start local server to capture redirect
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _redirectPort);

    // Open browser
    if (await canLaunchUrl(authUri)) {
      await launchUrl(authUri, mode: LaunchMode.externalApplication);
    } else {
      await server.close();
      throw Exception('Could not open browser for Google Drive authorization');
    }

    // Wait for redirect with auth code
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

        // Ignore other requests (favicon etc)
        request.response
          ..statusCode = 404
          ..write('Not found');
        await request.response.close();
      }
    } finally {
      await server.close();
    }

    if (authCode == null) {
      throw Exception('Google Drive authorization was cancelled or failed');
    }

    // Exchange code for tokens
    final tokenBody = <String, String>{
      'code': authCode,
      'client_id': _clientId!,
      'redirect_uri': redirectUri,
      'grant_type': 'authorization_code',
    };
    if (_clientSecret != null) tokenBody['client_secret'] = _clientSecret!;

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
      final resp = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        _email = data['email'] as String?;
      }
    } catch (_) {}
  }

  /// Resolve a full path (e.g., /Documents/report.pdf) to a file ID.
  /// For files (not just folders), we look up the parent and search by name.
  Future<String?> _resolveFileId(String path) async {
    if (path == '/' || path.isEmpty) return 'root';

    final parentPath = p.posix.dirname(path);
    final fileName = p.posix.basename(path);
    final parentId = await _resolvePathToId(parentPath) ?? 'root';

    return await _findFileInFolder(parentId, fileName);
  }

  Future<String?> _findFileInFolder(String parentId, String name) async {
    final query = "name='${_escapeQuery(name)}' and '$parentId' in parents and trashed=false";
    final resp = await _apiGet('/files', queryParams: {
      'q': query,
      'fields': 'files(id)',
      'pageSize': '1',
    });
    final files = (resp['files'] as List?) ?? [];
    if (files.isEmpty) return null;
    return files[0]['id'] as String;
  }

  Future<String?> _findFolderInParent(String parentId, String name) async {
    final query = "name='${_escapeQuery(name)}' and '$parentId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false";
    final resp = await _apiGet('/files', queryParams: {
      'q': query,
      'fields': 'files(id)',
      'pageSize': '1',
    });
    final files = (resp['files'] as List?) ?? [];
    if (files.isEmpty) return null;
    return files[0]['id'] as String;
  }

  String _escapeQuery(String s) => s.replaceAll("'", "\\'");

  // --- HTTP helpers ---

  Future<Map<String, dynamic>> _apiGet(String endpoint, {Map<String, String>? queryParams}) async {
    final uri = Uri.parse('$_apiBase$endpoint').replace(queryParameters: queryParams);
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $_accessToken'});

    if (resp.statusCode == 401) {
      // Try refresh
      await _refreshAccessToken();
      final retryResp = await http.get(uri, headers: {'Authorization': 'Bearer $_accessToken'});
      if (retryResp.statusCode != 200) {
        throw Exception('GDrive API error (${retryResp.statusCode}): ${retryResp.body}');
      }
      return json.decode(retryResp.body) as Map<String, dynamic>;
    }

    if (resp.statusCode != 200) {
      throw Exception('GDrive API error (${resp.statusCode}): ${resp.body}');
    }

    return json.decode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _apiPost(String endpoint, {required String body, String contentType = 'application/json'}) async {
    final uri = Uri.parse('$_apiBase$endpoint');
    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': contentType,
      },
      body: body,
    );

    if (resp.statusCode != 200) {
      throw Exception('GDrive API error (${resp.statusCode}): ${resp.body}');
    }

    return json.decode(resp.body) as Map<String, dynamic>;
  }
}
