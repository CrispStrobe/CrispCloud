import '../models/storage_reference.dart';

// lib/services/ftp_client_adapter.dart
import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

import 'cloud_storage_interface.dart';
import 'upload_temp_file.dart';
import 'ftp_config_service.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';

typedef FTPClientFactory = FTPConnect Function(
  String host, {
  required int port,
  required String user,
  required String pass,
  required SecurityType securityType,
  required int timeout,
});

class FTPClientAdapter extends CloudStorageClient
    with CloudTransferOperations
    implements StorageNamespaceIdentity {
  @override
  String get storageNamespace => '${_host ?? ''}:$_port';

  @override
  StorageTransferCapabilities get transferCapabilities =>
      const StorageTransferCapabilities(
        // FTP RNTO cannot enforce the optional exact no-replace contract.
        deleteEmptyDirectory: true,
      );

  @override
  Future<void> deleteDirectoryIfEmpty(String path) async {
    await _ensureConnection();
    final result = await _ftpClient!.deleteEmptyDirectory(path);
    if (!result) throw StateError('FTP refused to remove the empty directory.');
  }

  static const _log = Log('FTPClient');

  final FTPConfigService _config;
  final FTPClientFactory _createClient;

  // Expose config for AppState to read credentials
  FTPConfigService get config => _config;

  // FTP State. ftpconnect has one control socket without a command queue.
  // Absolute data paths avoid CWD-dependent routing; callers must still avoid
  // overlapping commands on this connection. Directory operations retain CWD.
  FTPConnect? _ftpClient;
  String? _username;
  String? _host;
  int _port = 21;
  bool _useTLS = false;
  bool _authenticated = false;

  FTPClientAdapter({required dynamic config, FTPClientFactory? clientFactory})
    : _config = (config is FTPConfigService)
          ? config
          : FTPConfigService(
              configPath: '',
              secureStorage: InMemorySecureStorage(),
            ),
      _createClient = clientFactory ?? FTPConnect.new;

  @override
  String get providerName => 'FTP';

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated => _authenticated;

  @override
  String? get userId => _username;

  @override
  String? get bucketId => _host;

  @override
  bool get supportsStreaming => false;

  @override
  bool get supportsTrash => false;

  // --- Connection Management ---

  Future<void> _ensureConnection() async {
    if (_ftpClient != null && _authenticated) return;

    final creds = await _config.readCredentials();
    if (creds == null) throw Exception('Not logged in');

    _username = creds['username'];
    _host = creds['host'];
    final password = creds['password'];
    _port = int.tryParse(creds['port'] ?? '21') ?? 21;
    _useTLS = creds['useTLS'] == 'true';

    if (_host == null || _username == null || password == null) {
      throw Exception('Incomplete credentials');
    }

    try {
      _ftpClient = _createClient(
        _host!,
        port: _port,
        user: _username!,
        pass: password,
        securityType: _useTLS ? SecurityType.ftps : SecurityType.ftp,
        timeout: 30,
      );

      final connected = await _ftpClient!.connect();
      if (!connected) {
        throw Exception('FTP connection failed');
      }
      _authenticated = true;
    } catch (e) {
      _ftpClient = null;
      _authenticated = false;
      _log.error('Connection error', e);
      throw Exception('Connection failed: $e');
    }
  }

  // --- Interface Implementation ---

  @override
  Future<void> login(
    String email,
    String password, {
    String? twoFactorCode,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('FTP is not supported on Web');
    }

    String user = email;
    String host = '';
    String port = '21';
    bool useTLS = false;

    if (email.contains('@')) {
      final parts = email.split('@');
      user = parts[0];
      final hostPart = parts[1];

      if (hostPart.contains(':')) {
        final hostParts = hostPart.split(':');
        host = hostParts[0];
        final portAndFlags = hostParts[1];
        // Check for ?tls=true suffix
        if (portAndFlags.contains('?')) {
          final qParts = portAndFlags.split('?');
          port = qParts[0];
          if (qParts[1].contains('tls=true')) {
            useTLS = true;
          }
        } else {
          port = portAndFlags;
        }
      } else {
        host = hostPart;
      }
    } else {
      throw Exception(
        'Format must be user@host[:port] (e.g. user@ftp.example.com:21)',
      );
    }

    await _config.saveCredentials({
      'username': user,
      'password': password,
      'host': host,
      'port': port,
      'useTLS': useTLS.toString(),
    });

    try {
      await _ensureConnection();
    } catch (e) {
      await _config.clearCredentials();
      rethrow;
    }
  }

  @override
  Future<bool> is2faNeeded(String email) async => false;

  @override
  Future<void> logout() async {
    if (_ftpClient != null) {
      try {
        await _ftpClient!.disconnect();
      } catch (e) {
        _log.warn('Disconnect error', e);
      }
    }
    _ftpClient = null;
    _authenticated = false;
    await _config.clearCredentials();
  }

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    await _ensureConnection();
    try {
      // Try to list the path to determine if it exists
      final currentDir = await _ftpClient!.currentDirectory();
      final changed = await _ftpClient!.changeDirectory(path);
      if (changed) {
        // It's a directory
        await _ftpClient!.changeDirectory(currentDir);
        return {
          'type': 'folder',
          'name': p.basename(path),
          'path': path,
          'uuid': path,
        };
      }
      // If changeDirectory failed, it might be a file
      return {
        'type': 'file',
        'name': p.basename(path),
        'path': path,
        'uuid': path,
      };
    } catch (e) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    await _ensureConnection();

    final folders = <Map<String, dynamic>>[];
    final files = <Map<String, dynamic>>[];

    try {
      await _ftpClient!.changeDirectory(path);
      final items = await _ftpClient!.listDirectoryContent();

      for (final item in items) {
        final name = item.name;
        if (name == '.' || name == '..') continue;

        final fullPath = p.posix.join(path, name);
        final isDir = item.type == FTPEntryType.dir;

        final modTimeStr = item.modifyTime?.toIso8601String();

        final map = {
          'uuid': fullPath,
          'name': name,
          'size': item.size,
          'modificationTime': modTimeStr,
          'type': isDir ? 'folder' : 'file',
          'path': fullPath,
        };

        if (isDir) {
          folders.add(map);
        } else {
          files.add(map);
        }
      }
    } catch (e) {
      _log.error('List error', e);
      throw Exception('Failed to list path $path: $e');
    }

    return {'folders': folders, 'files': files};
  }

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    await _ensureConnection();
    final client = _ftpClient!;
    final remotePath = p.posix.normalize(
      p.posix.join('/', targetPath, fileName),
    );

    // A separate directory also isolates concurrent uploads with the same name.
    await withTemporaryUploadFile(fileName, fileData, (tempFile) async {
      // ftpconnect forwards sRemoteName unchanged in STOR. Do not depend on the
      // current directory, which navigation or another transfer can change.
      final success = await client.uploadFile(
        tempFile,
        sRemoteName: remotePath,
      );
      if (!success) {
        throw Exception('FTP upload failed for $fileName');
      }
      onProgress?.call(fileData.length, fileData.length);
    });
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    await _ensureConnection();
    final client = _ftpClient!;
    final source = p.posix.normalize(p.posix.join('/', remotePath));
    final localFile = File(localPath);
    // The library sends this complete path in both SIZE and RETR.
    final success = await client.downloadFile(source, localFile);
    if (!success) {
      throw Exception('FTP download failed for $remotePath');
    }

    final size = await localFile.length();
    onProgress?.call(size, size);
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    await _ensureConnection();
    final client = _ftpClient!;
    final source = p.posix.normalize(p.posix.join('/', remotePath));
    final tempDir = await Directory.systemTemp.createTemp(
      'crisp-ftp-download-',
    );
    final tempFile = File(p.join(tempDir.path, 'payload'));
    try {
      final success = await client.downloadFile(source, tempFile);
      if (!success) {
        throw Exception('FTP download failed for $remotePath');
      }

      final bytes = await tempFile.readAsBytes();
      onProgress?.call(bytes.length, bytes.length);
      return bytes;
    } finally {
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (error, stack) {
        _log.warn(
          'Could not remove temporary FTP download files',
          error,
          stack,
        );
      }
    }
  }

  @override
  Future<void> createFolderPath(String path) async {
    await _ensureConnection();
    try {
      await _ftpClient!.makeDirectory(path);
    } catch (e) {
      // Ignore if already exists
      _log.debug('mkdir note: $e');
    }
  }

  @override
  Future<void> deletePath(String path) async {
    await _ensureConnection();

    // Try to determine if it's a directory
    try {
      final currentDir = await _ftpClient!.currentDirectory();
      final isDir = await _ftpClient!.changeDirectory(path);
      if (isDir) {
        await _ftpClient!.changeDirectory(currentDir);
        await _deleteDirectoryRecursive(path);
        return;
      }
    } catch (e) {
      // Not a directory, try as file
    }

    await _ftpClient!.deleteFile(path);
  }

  Future<void> _deleteDirectoryRecursive(String path) async {
    await _ftpClient!.changeDirectory(path);
    final items = await _ftpClient!.listDirectoryContent();

    for (final item in items) {
      if (item.name == '.' || item.name == '..') continue;
      final fullPath = p.posix.join(path, item.name);

      if (item.type == FTPEntryType.dir) {
        await _deleteDirectoryRecursive(fullPath);
      } else {
        await _ftpClient!.deleteFile(fullPath);
      }
    }

    // Go back to parent before removing directory
    await _ftpClient!.changeDirectory(p.posix.dirname(path));
    await _ftpClient!.deleteEmptyDirectory(path);
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    await _ensureConnection();
    await _ftpClient!.rename(sourcePath, targetPath);
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    await _ensureConnection();
    final newPath = p.posix.join(p.posix.dirname(path), newName);
    await _ftpClient!.rename(path, newPath);
  }
}
