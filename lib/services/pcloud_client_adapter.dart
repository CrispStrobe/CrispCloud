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
import 'bounded_http_transfer.dart';
import 'bounded_transfer_stream.dart';
import 'transfer_spool.dart';
import 'spooled_http_upload.dart';
import 'delta_sync_service.dart';
import 'pcloud_config_service.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';

class PCloudClientAdapter extends CloudStorageClient
    with CloudTransferOperations
    implements FreshCloudDirectoryReader {
  @override
  StorageTransferCapabilities get transferCapabilities =>
      const StorageTransferCapabilities(
        deleteEmptyDirectory: true,
        boundedUpload: true,
        boundedDownload: true,
      );

  @override
  Future<void> deleteDirectoryIfEmpty(String path) async {
    _ensureToken();
    final folderId = await _resolveFolderId(path);
    final uri = Uri.parse('$_apiBase/deletefolder').replace(
      queryParameters: {
        'access_token': _accessToken!,
        'folderid': folderId.toString(),
      },
    );
    _parseResponse(await http.get(uri), 'deletefolder');
    _pathToFolderId.remove(path);
  }

  static const _log = Log('PCloudClient');

  final PCloudConfigService _config;

  PCloudConfigService get config => _config;

  String? _accessToken;
  String? _email;
  String? _appKey;
  bool _useEuApi;
  bool _authenticated = false;
  int _authEpoch = 0;

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
          : PCloudConfigService(
              configPath: '',
              secureStorage: InMemorySecureStorage(),
            ),
      // Keep the public named argument compatible with the minimum Dart SDK.
      // ignore: prefer_initializing_formals
      _useEuApi = useEuApi;

  String get _apiBase =>
      _useEuApi ? 'https://eapi.pcloud.com' : 'https://api.pcloud.com';
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
  bool get supportsStreaming => true;
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
  Future<void> login(
    String identity,
    String password, {
    String? twoFactorCode,
  }) async {
    final epoch = ++_authEpoch;
    _authenticated = false;
    _pathToFolderId
      ..clear()
      ..['/'] = 0;
    // identity format: "appKey" or "appKey|eu" to select EU endpoint
    final parts = identity.split('|');
    _appKey = parts[0].trim();
    _useEuApi = parts.length > 1 && parts[1].trim().toLowerCase() == 'eu';

    if (_appKey == null || _appKey!.isEmpty) {
      throw Exception('App Key is required');
    }

    // Try stored access token (pCloud long-lived tokens don't expire)
    final creds = await _config.readCredentials();
    if (epoch != _authEpoch) {
      throw StateError('pCloud authentication was superseded.');
    }
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
        if (epoch != _authEpoch) rethrow;
        // Stored token invalid; proceed to browser flow
        _accessToken = null;
      }
    }

    if (kIsWeb) {
      throw Exception(
        'pCloud OAuth2 on web requires a different redirect flow.',
      );
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
    _authEpoch++;
    // pCloud has no token-revocation endpoint for OAuth2 implicit tokens
    _accessToken = null;
    _email = null;
    _authenticated = false;
    _pathToFolderId
      ..clear()
      ..['/'] = 0;
  }

  Future<bool> restoreCredentials() async {
    final epoch = ++_authEpoch;
    _authenticated = false;
    _pathToFolderId
      ..clear()
      ..['/'] = 0;
    final creds = await _config.readCredentials();
    if (creds == null ||
        creds['access_token'] == null ||
        creds['access_token']!.isEmpty) {
      return false;
    }
    if (epoch != _authEpoch) return false;
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
      final uri = Uri.parse('$_apiBase/listfolder').replace(
        queryParameters: {
          'access_token': _accessToken!,
          'folderid': currentId.toString(),
          'nofiles': '1',
        },
      );
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
  Future<Map<String, dynamic>> readDirectoryForEdit(String path) {
    _pathToFolderId
      ..clear()
      ..['/'] = 0;
    return listPath(path);
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    _ensureToken();

    final folderId = await _resolveFolderId(path);
    final uri = Uri.parse('$_apiBase/listfolder').replace(
      queryParameters: {
        'access_token': _accessToken!,
        'folderid': folderId.toString(),
      },
    );

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
        'uuid': isFolder ? 'd_${item['folderid']}' : 'f_${item['fileid']}',
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

  // --- Bounded transfers ---

  (int, String, String) _captureTransfer() {
    if (!isAuthenticated) throw StateError('pCloud is not authenticated.');
    return (_authEpoch, _accessToken!, _apiBase);
  }

  void _checkTransfer((int, String, String) captured) {
    if (!isAuthenticated ||
        _authEpoch != captured.$1 ||
        _accessToken != captured.$2 ||
        _apiBase != captured.$3) {
      throw StateError('The original pCloud account is no longer connected.');
    }
  }

  Map<String, dynamic> _transferMetadata(
    http.Response response,
    String operation,
  ) {
    if (response.statusCode != 200) {
      throw StateError('pCloud $operation failed (${response.statusCode}).');
    }
    final Object? decoded;
    try {
      decoded = json.decode(response.body);
    } catch (_) {
      throw StateError('pCloud $operation returned invalid metadata.');
    }
    if (decoded is! Map<String, dynamic> || decoded['result'] != 0) {
      throw StateError('pCloud $operation did not confirm success.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _readTransferMetadata(
    (int, String, String) captured,
    String method,
    Map<String, String> parameters,
  ) async {
    _checkTransfer(captured);
    final client = http.Client();
    try {
      final uri = Uri.parse(
        '${captured.$3}/$method',
      ).replace(queryParameters: {'access_token': captured.$2, ...parameters});
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await sendTransferRequest(
        client,
        request,
        operation: 'pCloud $method',
      );
      _checkTransfer(captured);
      return _transferMetadata(response, method);
    } finally {
      client.close();
    }
  }

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
        p.posix.basename(fileName) != fileName) {
      throw ArgumentError.value(fileName, 'fileName');
    }
    final captured = _captureTransfer();
    final parent = p.posix.normalize(p.posix.join('/', targetPath));
    // Resolve the supplied path on the server, bypassing cached folder IDs.
    // Official HTTP protocol supports a single raw PUT body plus filename.
    // https://docs.pcloud.com/protocols/http_json_protocol/uploading_files.html
    final uri = Uri.parse('${captured.$3}/uploadfile').replace(
      queryParameters: {
        'access_token': captured.$2,
        'path': parent,
        'filename': fileName,
        'nopartial': '1',
      },
    );
    http.Response response;
    if (kIsWeb) {
      final spool = await createTransferSpool(
        dataStream,
        expectedLength: length,
        checkpoint: () async => _checkTransfer(captured),
      );
      try {
        response = await uploadSpooledHttpBody(
          uri,
          spool,
          operation: 'pCloud upload',
          checkCurrent: () => _checkTransfer(captured),
          onProgress: onProgress,
        );
      } finally {
        await spool.dispose();
      }
    } else {
      var sent = 0;
      final body = validatedTransferParts(dataStream, length, 64 * 1024).map((
        part,
      ) {
        _checkTransfer(captured);
        sent += part.length;
        onProgress?.call(sent, length);
        return part;
      });
      final client = http.Client();
      try {
        response = await sendTransferRequest(
          client,
          _PCloudUploadRequest(uri, body, length),
          operation: 'pCloud upload',
        );
      } finally {
        client.close();
      }
    }
    _checkTransfer(captured);
    final data = _transferMetadata(response, 'upload');
    final entries = data['metadata'];
    final metadata = entries is List && entries.length == 1
        ? entries.single
        : null;
    if (metadata is! Map ||
        metadata['fileid'] is! num ||
        metadata['isfolder'] == true ||
        metadata['name'] != fileName ||
        metadata['size'] != length ||
        (metadata['path'] != null &&
            metadata['path'] != p.posix.join(parent, fileName))) {
      throw StateError(
        'pCloud did not confirm the uploaded file identity and size.',
      );
    }
    onProgress?.call(length, length);
  }

  @override
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async* {
    final captured = _captureTransfer();
    final path = p.posix.normalize(p.posix.join('/', remotePath));
    final stat = await _readTransferMetadata(captured, 'stat', {'path': path});
    final metadata = stat['metadata'];
    if (metadata is! Map ||
        metadata['isfolder'] == true ||
        metadata['fileid'] is! num ||
        metadata['size'] is! int ||
        (metadata['size'] as int) < 0) {
      throw StateError(
        'pCloud did not return a readable file identity and size.',
      );
    }
    final link = await _readTransferMetadata(captured, 'getfilelink', {
      'fileid': metadata['fileid'].toString(),
    });
    final hosts = link['hosts'];
    final pathPart = link['path'];
    if (hosts is! List ||
        hosts.isEmpty ||
        hosts.first is! String ||
        pathPart is! String ||
        !pathPart.startsWith('/') ||
        pathPart.startsWith('//')) {
      throw StateError('pCloud returned an invalid download address.');
    }
    final host = hosts.first as String;
    if (!RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(host)) {
      throw StateError('pCloud returned an invalid download host.');
    }
    final uri = Uri.parse('https://$host$pathPart');
    await for (final part in streamHttpDownload(
      uri,
      operation: 'pCloud download',
      expectedLength: metadata['size'] as int,
      onProgress: onProgress,
    )) {
      _checkTransfer(captured);
      yield part;
    }
    _checkTransfer(captured);
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    final bytes = BytesBuilder(copy: false);
    await for (final part in downloadStream(
      remotePath,
      onProgress: onProgress,
    )) {
      bytes.add(part);
    }
    return bytes.takeBytes();
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Use browser file storage to save this download.');
    }
    final writer = await File(localPath).open(mode: FileMode.write);
    try {
      await for (final part in downloadStream(
        remotePath,
        onProgress: onProgress,
      )) {
        await writer.writeFrom(part);
      }
      await writer.flush();
    } finally {
      await writer.close();
    }
  }

  // --- Folder ---

  @override
  Future<void> createFolderPath(String path) async {
    _ensureToken();

    final split = _splitPath(path);
    final parentId = await _resolveFolderId(split.parent);

    final uri = Uri.parse('$_apiBase/createfolder').replace(
      queryParameters: {
        'access_token': _accessToken!,
        'folderid': parentId.toString(),
        'name': split.name,
      },
    );

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
      final uri = Uri.parse('$_apiBase/deletefile').replace(
        queryParameters: {
          'access_token': _accessToken!,
          'fileid': fileId.toString(),
        },
      );
      final resp = await http.get(uri);
      _parseResponse(resp, 'deletefile');
      return;
    } catch (_) {}

    // Delete folder recursively
    final folderId = await _resolveFolderId(path);
    final uri = Uri.parse('$_apiBase/deletefolderrecursive').replace(
      queryParameters: {
        'access_token': _accessToken!,
        'folderid': folderId.toString(),
      },
    );
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
      final uri = Uri.parse('$_apiBase/movefile').replace(
        queryParameters: {
          'access_token': _accessToken!,
          'fileid': fileId.toString(),
          'tofolderid': destFolderId.toString(),
          'toname': fileName,
        },
      );
      final resp = await http.get(uri);
      _parseResponse(resp, 'movefile');
      return;
    } catch (_) {}

    // Move folder
    final folderId = await _resolveFolderId(sourcePath);
    final uri = Uri.parse('$_apiBase/movefolder').replace(
      queryParameters: {
        'access_token': _accessToken!,
        'folderid': folderId.toString(),
        'tofolderid': destFolderId.toString(),
        'toname': fileName,
      },
    );
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
      final uri = Uri.parse('$_apiBase/renamefile').replace(
        queryParameters: {
          'access_token': _accessToken!,
          'fileid': fileId.toString(),
          'toname': newName,
        },
      );
      final resp = await http.get(uri);
      _parseResponse(resp, 'renamefile');
      return;
    } catch (_) {}

    // Rename folder
    final folderId = await _resolveFolderId(path);
    final parentId = await _resolveFolderId(_splitPath(path).parent);
    final uri = Uri.parse('$_apiBase/renamefolder').replace(
      queryParameters: {
        'access_token': _accessToken!,
        'folderid': folderId.toString(),
        'tofolderid': parentId.toString(),
        'toname': newName,
      },
    );
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

    final uri = Uri.parse('$_apiBase/listfolder').replace(
      queryParameters: {
        'access_token': _accessToken!,
        'folderid': parentId.toString(),
      },
    );
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
    final epoch = _authEpoch;
    final token = _accessToken!;
    final base = _apiBase;
    final uri = Uri.parse(
      '$base/userinfo',
    ).replace(queryParameters: {'access_token': token});
    final resp = await http.get(uri);
    if (epoch != _authEpoch || token != _accessToken || base != _apiBase) {
      throw StateError('The pCloud account changed during authentication.');
    }
    final data = _parseResponse(resp, 'userinfo');
    _email = data['email'] as String?;
  }

  /// Parse a pCloud API JSON response and check the result code.
  Map<String, dynamic> _parseResponse(http.Response resp, String endpoint) {
    if (resp.statusCode != 200) {
      throw Exception(
        'pCloud $endpoint HTTP error (${resp.statusCode}): ${resp.body}',
      );
    }
    if (resp.body.isEmpty) return {};
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final result = data['result'] as int? ?? 0;
    if (result != 0) {
      throw Exception(
        'pCloud $endpoint error (result=$result): ${data['error'] ?? resp.body}',
      );
    }
    return data;
  }

  Future<void> _browserOAuthFlow() async {
    final epoch = _authEpoch;
    const redirectUri = 'http://localhost:$_redirectPort';

    final authUri = Uri.parse(_authUrl).replace(
      queryParameters: {
        'client_id': _appKey!,
        'response_type': 'code',
        'redirect_uri': redirectUri,
      },
    );

    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      _redirectPort,
    );

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
              '<p>You can close this window.</p></body></html>',
            );
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
              '<p>You can close this window and return to CrispCloud.</p></body></html>',
            );
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

    if (epoch != _authEpoch) {
      throw StateError('pCloud authentication was superseded.');
    }
    if (authCode == null) {
      throw Exception('pCloud authorization was cancelled or failed');
    }

    // Exchange code for access token
    final tokenUri = Uri.parse(_tokenUrl).replace(
      queryParameters: {
        'client_id': _appKey!,
        'code': authCode,
        'redirect_uri': redirectUri,
      },
    );

    final tokenResp = await http.get(tokenUri);
    if (epoch != _authEpoch) {
      throw StateError('pCloud authentication was superseded.');
    }
    if (tokenResp.statusCode != 200) {
      throw Exception(
        'pCloud token exchange failed (${tokenResp.statusCode}): ${tokenResp.body}',
      );
    }

    final tokenData = json.decode(tokenResp.body) as Map<String, dynamic>;
    final tokenResult = tokenData['result'] as int? ?? -1;
    if (tokenResult != 0) {
      throw Exception(
        'pCloud token error (result=$tokenResult): ${tokenData['error'] ?? tokenResp.body}',
      );
    }

    _accessToken = tokenData['access_token'] as String?;
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw Exception('pCloud: no access token in response');
    }

    // If the response indicates EU location, switch to EU API
    final locationId = tokenData['locationid'] as int?;
    if (locationId == 2) {
      _useEuApi = true;
      _log.info(
        'pCloud account is on EU servers; switching to eapi.pcloud.com',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Delta Sync — block-level file sync via pCloud's random-access API
  // ---------------------------------------------------------------------------

  /// Whether block-level delta sync is enabled for this connection.
  bool deltaSyncEnabled = false;

  final DeltaSyncService _deltaSyncService = DeltaSyncService();

  /// Open a file descriptor on the pCloud server for random-access I/O.
  /// Returns the file descriptor (fd) number.
  Future<int> fileOpen(int fileId, {bool write = false}) async {
    _ensureToken();
    final flags = write ? 0x0042 : 0x0000; // O_CREAT|O_RDWR : O_RDONLY
    final uri = Uri.parse('$_apiBase/file_open').replace(
      queryParameters: {
        'access_token': _accessToken!,
        'fileid': fileId.toString(),
        'flags': flags.toString(),
      },
    );
    final resp = await http.get(uri);
    final data = _parseResponse(resp, 'file_open');
    return data['fd'] as int;
  }

  /// Read bytes from a pCloud file descriptor at a specific offset.
  Future<List<int>> filePread(int fd, int offset, int count) async {
    _ensureToken();
    final uri = Uri.parse('$_apiBase/file_pread').replace(
      queryParameters: {
        'access_token': _accessToken!,
        'fd': fd.toString(),
        'count': count.toString(),
        'offset': offset.toString(),
      },
    );
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('pCloud file_pread failed (HTTP ${resp.statusCode})');
    }
    return resp.bodyBytes;
  }

  /// Write bytes to a pCloud file descriptor at a specific offset.
  Future<void> filePwrite(int fd, int offset, List<int> data) async {
    _ensureToken();
    final uri = Uri.parse('$_apiBase/file_pwrite').replace(
      queryParameters: {
        'access_token': _accessToken!,
        'fd': fd.toString(),
        'offset': offset.toString(),
      },
    );
    final req = http.Request('PUT', uri);
    req.bodyBytes = data is Uint8List ? data : Uint8List.fromList(data);
    req.headers['Content-Type'] = 'application/octet-stream';
    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    _parseResponse(resp, 'file_pwrite');
  }

  /// Close a pCloud file descriptor.
  Future<void> fileClose(int fd) async {
    _ensureToken();
    final uri = Uri.parse('$_apiBase/file_close').replace(
      queryParameters: {'access_token': _accessToken!, 'fd': fd.toString()},
    );
    final resp = await http.get(uri);
    _parseResponse(resp, 'file_close');
  }

  /// Get the SHA-256 checksum of a remote file (server-computed).
  Future<String?> fileChecksum(int fileId) async {
    _ensureToken();
    final uri = Uri.parse('$_apiBase/checksumfile').replace(
      queryParameters: {
        'access_token': _accessToken!,
        'fileid': fileId.toString(),
      },
    );
    final resp = await http.get(uri);
    final data = _parseResponse(resp, 'checksumfile');
    return data['sha256'] as String?;
  }

  /// Orchestrate a delta upload for a single file.
  ///
  /// 1. Resolve remote file ID.
  /// 2. Compute local block map.
  /// 3. Compare with cached remote block map (or compute fresh via pread).
  /// 4. Open file descriptor, pwrite changed blocks, close.
  /// 5. Update cached block map.
  Future<DeltaResult?> deltaUpload(
    String localPath,
    String remotePath, {
    String? cacheDir,
    void Function(int, int, int)? onProgress,
  }) async {
    if (!deltaSyncEnabled) return null;
    _ensureToken();

    final file = File(localPath);
    final fileSize = await file.length();
    if (!_deltaSyncService.shouldUseDeltaSync(fileSize)) return null;

    // Get remote file ID
    final fileId = await _resolveFileId(remotePath);

    // Try to load cached remote block map
    BlockMap? remoteMap;
    if (cacheDir != null) {
      final cachePath = _deltaSyncService.blockMapCachePath(
        cacheDir,
        remotePath,
        'pcloud',
      );
      remoteMap = await _deltaSyncService.loadBlockMap(cachePath);
    }

    // If no cache, compute remote block map by reading blocks via pread
    if (remoteMap == null) {
      _log.info(
        'Delta sync: computing remote block map via pread for $remotePath',
      );
      remoteMap = await _computeRemoteBlockMap(fileId, remotePath);
    }

    // Compute local block map
    final localMap = await _deltaSyncService.computeBlockMap(
      localPath,
      blockSize: remoteMap.blockSize,
      onProgress: onProgress,
    );

    // Compare
    final delta = _deltaSyncService.compareBlockMaps(localMap, remoteMap);
    if (delta.changedBlocks.isEmpty) {
      _log.info('Delta sync: $remotePath is identical');
      return delta;
    }

    _log.info(
      'Delta sync: $remotePath — ${delta.changedBlocks.length}/${delta.totalBlocks} blocks changed, '
      '${delta.savingsPercent.toStringAsFixed(1)}% savings',
    );

    // Open, write changed blocks, close
    final fd = await fileOpen(fileId, write: true);
    try {
      final raf = await file.open();
      try {
        for (final blockIdx in delta.changedBlocks) {
          final sig = localMap.signatures[blockIdx];
          await raf.setPosition(sig.offset);
          final buf = Uint8List(sig.size);
          await raf.readInto(buf);
          await filePwrite(fd, sig.offset, buf);
        }
      } finally {
        await raf.close();
      }
    } finally {
      await fileClose(fd);
    }

    // Cache new block map
    if (cacheDir != null) {
      final cachePath = _deltaSyncService.blockMapCachePath(
        cacheDir,
        remotePath,
        'pcloud',
      );
      await _deltaSyncService.saveBlockMap(localMap, cachePath);
    }

    return delta;
  }

  /// Compute a block map for a remote file by reading blocks via file_pread.
  Future<BlockMap> _computeRemoteBlockMap(int fileId, String remotePath) async {
    // First, get file size via stat
    final uri = Uri.parse('$_apiBase/stat').replace(
      queryParameters: {
        'access_token': _accessToken!,
        'fileid': fileId.toString(),
      },
    );
    final resp = await http.get(uri);
    final data = _parseResponse(resp, 'stat');
    final metadata = data['metadata'] as Map<String, dynamic>;
    final fileSize = (metadata['size'] as num).toInt();

    const blockSize = 4 * 1024 * 1024;
    final blockCount = fileSize == 0
        ? 0
        : ((fileSize + blockSize - 1) ~/ blockSize);

    final fd = await fileOpen(fileId);
    try {
      final signatures = <BlockSignature>[];
      for (int i = 0; i < blockCount; i++) {
        final offset = i * blockSize;
        final size = (offset + blockSize > fileSize)
            ? fileSize - offset
            : blockSize;
        final bytes = await filePread(fd, offset, size);

        signatures.add(
          BlockSignature(
            blockIndex: i,
            offset: offset,
            size: bytes.length,
            weakHash: _deltaSyncService.adler32(bytes),
            strongHash: _deltaSyncService.sha256Hex(bytes),
          ),
        );
      }

      return BlockMap(
        filePath: remotePath,
        totalSize: fileSize,
        blockSize: blockSize,
        blockCount: blockCount,
        signatures: signatures,
        createdAt: DateTime.now(),
      );
    } finally {
      await fileClose(fd);
    }
  }
}

class _PCloudUploadRequest extends http.BaseRequest {
  _PCloudUploadRequest(Uri uri, this.body, int length) : super('PUT', uri) {
    contentLength = length;
    followRedirects = false;
    headers['content-type'] = 'application/octet-stream';
  }
  final Stream<List<int>> body;
  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(body);
  }
}
