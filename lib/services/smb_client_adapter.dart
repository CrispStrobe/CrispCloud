import 'dart:io';
import 'dart:typed_data';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'cloud_storage_interface.dart';
import 'smb_config_service.dart';

/// File-manager operations over the same SMB transport as CrisperPlayer.
class SmbClientAdapter extends CloudStorageClient {
  final SmbConfigService config;
  SmbSession? _session;
  String? _username, _server;
  bool requireEncryption = true;
  SmbClientAdapter({required this.config});
  @override
  String get providerName => 'SMB';
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => _session != null;
  @override
  String? get userId => _username;
  @override
  String? get bucketId => _server;
  @override
  bool get supportsStreaming => !kIsWeb;
  @override
  bool get supportsTrash => false;
  @override
  Future<bool> is2faNeeded(String email) async => false;

  Future<SmbSession> _connect(Map<String, String> credentials) async {
    if (kIsWeb) throw UnsupportedError('SMB requires the installed app.');
    final connection = RemoteConnection(
        id: 'crispcloud-smb',
        name: 'SMB',
        kind: 'smb',
        url: credentials['url']!,
        username: credentials['username']!,
        secret: credentials['password']!,
        requireEncryption: credentials['requireEncryption'] != 'false');
    final session = SmbSession(connection);
    try {
      await session.browse('');
    } catch (_) {
      session.close();
      rethrow;
    }
    _username = connection.username;
    _server = connection.url.toString();
    requireEncryption = connection.requireEncryption;
    return session;
  }

  Future<SmbSession> _ensure() async {
    if (_session != null) return _session!;
    final credentials = await config.readCredentials();
    if (credentials == null) throw StateError('Connect to an SMB share first.');
    return _session = await _connect(credentials);
  }

  @override
  Future<void> login(String email, String password,
      {String? twoFactorCode}) async {
    final split = email.lastIndexOf('@smb://');
    if (split < 1) {
      throw const FormatException('Use username@smb://host/share/.');
    }
    final credentials = {
      'username': email.substring(0, split),
      'url': email.substring(split + 1),
      'password': password,
      'requireEncryption': '$requireEncryption'
    };
    final session = await _connect(credentials);
    try {
      await config.saveCredentials(credentials);
    } catch (_) {
      session.close();
      rethrow;
    }
    _session?.close();
    _session = session;
  }

  @override
  Future<void> logout() async {
    _session?.close();
    _session = null;
    _username = _server = null;
    await config.clearCredentials();
  }
  Future<bool> restoreCredentials() async {
    if (await config.readCredentials() == null) return false;
    await _ensure();
    return true;
  }

  String _url(SmbSession session, String path) => session.urlForPath(path);
  Map<String, dynamic> _map(RemoteEntry e, String path) => {
        'uuid': path,
        'path': path,
        'name': e.name,
        'type': e.type,
        'size': e.size,
      };
  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    final session = await _ensure();
    final entry = await session.stat(_url(session, path));
    return entry == null ? null : _map(entry, path);
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    final session = await _ensure();
    final entries = await session.browse(_url(session, path));
    return {
      'folders': [
        for (final e in entries)
          if (e.type == 'folder') _map(e, p.posix.join(path, e.name))
      ],
      'files': [
        for (final e in entries)
          if (e.type == 'file') _map(e, p.posix.join(path, e.name))
      ],
    };
  }

  String _child(String parent, String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains(r'\') ||
        name.contains('\u0000')) {
      throw const FormatException('Enter a file name without path separators.');
    }
    return p.posix.join(parent, name);
  }

  @override
  Stream<List<int>> downloadStream(String remotePath,
      {Function(int, int)? onProgress}) async* {
    final session = await _ensure();
    yield* session.stream(_url(session, remotePath), onProgress: onProgress);
  }

  @override
  Future<Uint8List> downloadFileBytes(String remotePath,
      {Function(int, int)? onProgress}) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk
        in downloadStream(remotePath, onProgress: onProgress)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  @override
  Future<void> downloadFileByPath(String remotePath, String localPath,
      {Function(int, int)? onProgress}) async {
    final session = await _ensure();
    final source = _url(session, remotePath);
    final total = (await session.stat(source))?.size ?? 0;
    await session.download(source, File(localPath),
        limit: 64 * 1024 * 1024 * 1024,
        onBytes: (received) => onProgress?.call(received, total));
    // Resume hints belong to incomplete transfers, not the user's downloads.
    for (final suffix in ['.resume', '.resume.tmp']) {
      final sidecar = File('$localPath$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
  }

  @override
  Future<void> uploadFile(
      List<int> fileData, String fileName, String targetPath,
      {Function(int, int)? onProgress}) async {
    final session = await _ensure();
    await session.write(_url(session, _child(targetPath, fileName)),
        Uint8List.fromList(fileData));
    onProgress?.call(fileData.length, fileData.length);
  }

  @override
  Future<void> uploadStream(Stream<List<int>> dataStream, int length,
      String fileName, String targetPath,
      {Function(int, int)? onProgress}) async {
    final session = await _ensure();
    var received = 0;
    final data = dataStream.map((chunk) {
      received += chunk.length;
      onProgress?.call(received, length);
      return chunk;
    });
    await session.upload(_url(session, _child(targetPath, fileName)), data);
  }

  @override
  Future<void> createFolderPath(String path) async {
    final session = await _ensure();
    // Creating nested folders matches the other file-manager providers.
    var current = '';
    session.urlForPath(path); // Validate before creating anything.
    for (final part in path.split('/').where((e) => e.isNotEmpty)) {
      current = '$current/$part';
      final url = _url(session, current);
      final entry = await session.stat(url);
      if (entry == null) {
        await session.mkdir(url);
      } else if (entry.type != 'folder') {
        throw StateError('A file occupies the folder path.');
      }
    }
  }

  @override
  Future<void> deletePath(String path) async {
    if (path.replaceAll('/', '').isEmpty) {
      throw const FormatException('Cannot delete the share root.');
    }
    final session = await _ensure();
    final url = _url(session, path);
    final entry = await session.stat(url);
    if (entry == null) throw StateError('File or folder was not found.');
    if (entry.type == 'folder') {
      final listing = await listPath(path);
      for (final child in [
        ...listing['files'] as List,
        ...listing['folders'] as List
      ]) {
        await deletePath(child['path'] as String);
      }
    }
    await session.delete(url, directory: entry.type == 'folder');
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    final session = await _ensure();
    if (sourcePath.replaceAll('/', '').isEmpty ||
        targetPath.replaceAll('/', '').isEmpty) {
      throw const FormatException('Cannot move the share root.');
    }
    await session.rename(_url(session, sourcePath), _url(session, targetPath));
  }

  @override
  Future<void> renamePath(String path, String newName) async =>
      movePath(path, _child(p.posix.dirname(path), newName));
}
