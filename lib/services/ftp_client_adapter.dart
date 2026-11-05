import '../models/storage_reference.dart';

// lib/services/ftp_client_adapter.dart
import 'dart:io';
import 'dart:async';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

import 'cloud_storage_interface.dart';
import 'upload_temp_file.dart';
import 'ftp_config_service.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';
import 'ftp_transfer_session.dart';

typedef FTPClientFactory =
    FTPConnect Function(
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
        boundedUpload: !kIsWeb,
        boundedDownload: !kIsWeb,
      );

  @override
  Future<void> deleteDirectoryIfEmpty(String path) => _serialized(() async {
    final result = await _operationClient.deleteEmptyDirectory(path);
    if (!result) throw StateError('FTP refused to remove the empty directory.');
  });

  static const _log = Log('FTPClient');

  final FTPConfigService _config;
  final FTPClientFactory _createClient;

  // Expose config for AppState to read credentials
  FTPConfigService get config => _config;

  // FTP State. ftpconnect has one control socket without a command queue.
  // Legacy metadata operations share this connection and are serialized.
  // Bounded data transfers use independent control and data connections.
  FTPConnect? _ftpClient;
  String? _username;
  String? _password;
  String? _host;
  int _port = 21;
  bool _useTLS = false;
  bool _authenticated = false;
  int _authEpoch = 0;
  final Set<FtpTransferSession> _transferSessions = {};
  Future<void>? _connecting;
  Future<void> _legacyQueue = Future.value();
  final Object _legacyClientKey = Object();

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final epoch = _authEpoch;
    final preceding = _legacyQueue;
    final released = Completer<void>();
    _legacyQueue = released.future;
    await preceding;
    try {
      if (epoch != _authEpoch) {
        throw StateError('The FTP account changed before this operation.');
      }
      await _ensureConnection();
      if (epoch != _authEpoch) {
        throw StateError('The FTP account changed before this operation.');
      }
      final client = _ftpClient!;
      final result = await runZoned(
        action,
        zoneValues: {_legacyClientKey: (client, epoch)},
      );
      if (!_authenticated ||
          epoch != _authEpoch ||
          !identical(client, _ftpClient)) {
        throw StateError('The original FTP account is no longer connected.');
      }
      return result;
    } finally {
      released.complete();
    }
  }

  FTPConnect get _operationClient {
    final captured = Zone.current[_legacyClientKey] as (FTPConnect, int)?;
    if (captured == null ||
        !_authenticated ||
        captured.$2 != _authEpoch ||
        !identical(captured.$1, _ftpClient)) {
      throw StateError('The original FTP account is no longer connected.');
    }
    return captured.$1;
  }

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
  bool get supportsStreaming => !kIsWeb;

  @override
  bool get supportsTrash => false;

  // --- Connection Management ---

  Future<void> _ensureConnection() {
    if (_ftpClient != null && _authenticated) return Future.value();
    if (_connecting != null) return _connecting!;
    late Future<void> pending;
    pending = _connect().whenComplete(() {
      if (identical(_connecting, pending)) _connecting = null;
    });
    return _connecting = pending;
  }

  Future<void> _connect() async {
    final epoch = _authEpoch;
    final creds = await _config.readCredentials();
    if (creds == null) throw Exception('Not logged in');
    final username = creds['username'];
    final host = creds['host'];
    final password = creds['password'];
    final port = int.tryParse(creds['port'] ?? '21') ?? 21;
    final tls = creds['useTLS'] == 'true';
    if (host == null || username == null || password == null) {
      throw Exception('Incomplete credentials');
    }
    if (epoch != _authEpoch) {
      throw StateError('The FTP account changed while connecting.');
    }
    final connection = _createClient(
      host,
      port: port,
      user: username,
      pass: password,
      securityType: tls ? SecurityType.ftps : SecurityType.ftp,
      timeout: 30,
    );
    try {
      final connected = await connection.connect();
      if (!connected) {
        throw Exception('FTP connection failed');
      }
      if (epoch != _authEpoch) {
        throw StateError('The FTP account changed while connecting.');
      }
      _ftpClient = connection;
      _username = username;
      _host = host;
      _password = password;
      _port = port;
      _useTLS = tls;
      _authenticated = true;
    } catch (e) {
      try {
        await connection.disconnect();
      } catch (_) {
        /* Preserve connection failure. */
      }
      if (epoch == _authEpoch) {
        _ftpClient = null;
        _authenticated = false;
        _password = null;
      }
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
    _authEpoch++;
    await _closeSessions();

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
    _authEpoch++;
    await _closeSessions();
    await _config.clearCredentials();
  }

  Future<void> _closeSessions() async {
    for (final session in _transferSessions.toList()) {
      session.close();
    }
    _transferSessions.clear();
    final connection = _ftpClient;
    _ftpClient = null;
    _connecting = null;
    _authenticated = false;
    _password = null;
    if (connection != null) {
      try {
        await connection.disconnect();
      } catch (e) {
        _log.warn('Disconnect error', e);
      }
    }
  }

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) =>
      _serialized(() async {
        try {
          // Try to list the path to determine if it exists
          final currentDir = await _operationClient.currentDirectory();
          final changed = await _operationClient.changeDirectory(path);
          if (changed) {
            // It's a directory
            await _operationClient.changeDirectory(currentDir);
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
      });

  @override
  Future<Map<String, dynamic>> listPath(String path) => _serialized(() async {
    final folders = <Map<String, dynamic>>[];
    final files = <Map<String, dynamic>>[];

    try {
      if (!await _operationClient.changeDirectory(path)) {
        throw StateError('The FTP directory is unavailable: $path');
      }
      final items = await _operationClient.listDirectoryContent();

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
  });

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) => _serialized(() async {
    final client = _operationClient;
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
  });

  Future<FtpTransferSession> _openTransfer() async {
    if (kIsWeb) throw UnsupportedError('FTP is unavailable in a browser.');
    await _ensureConnection();
    final epoch = _authEpoch;
    final connection = _ftpClient;
    final password = _password;
    if (password == null) {
      throw StateError('The FTP session credentials are unavailable.');
    }
    final session = FtpTransferSession(
      host: _host!,
      port: _port,
      username: _username!,
      password: password,
      secure: _useTLS,
      isCurrent: () =>
          _authenticated &&
          _authEpoch == epoch &&
          identical(_ftpClient, connection),
    );
    _transferSessions.add(session);
    try {
      await session.connect();
      return session;
    } catch (_) {
      _transferSessions.remove(session);
      session.close();
      rethrow;
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
    final remote = p.posix.normalize(p.posix.join('/', targetPath, fileName));
    final session = await _openTransfer();
    try {
      await session.upload(remote, dataStream, length, onProgress: onProgress);
    } finally {
      _transferSessions.remove(session);
      session.close();
    }
  }

  @override
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async* {
    final remote = p.posix.normalize(p.posix.join('/', remotePath));
    final session = await _openTransfer();
    try {
      yield* session.download(remote, onProgress: onProgress);
    } finally {
      _transferSessions.remove(session);
      session.close();
    }
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) => _serialized(() async {
    final client = _operationClient;
    final source = p.posix.normalize(p.posix.join('/', remotePath));
    final localFile = File(localPath);
    // The library sends this complete path in both SIZE and RETR.
    final success = await client.downloadFile(source, localFile);
    if (!success) {
      throw Exception('FTP download failed for $remotePath');
    }

    final size = await localFile.length();
    onProgress?.call(size, size);
  });

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) => _serialized(() async {
    final client = _operationClient;
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
  });

  @override
  Future<void> createFolderPath(String path) => _serialized(() async {
    try {
      await _operationClient.makeDirectory(path);
    } catch (e) {
      // Ignore if already exists
      _log.debug('mkdir note: $e');
    }
  });

  @override
  Future<void> deletePath(String path) => _serialized(() async {
    // Try to determine if it's a directory
    try {
      final currentDir = await _operationClient.currentDirectory();
      final isDir = await _operationClient.changeDirectory(path);
      if (isDir) {
        await _operationClient.changeDirectory(currentDir);
        await _deleteDirectoryRecursive(path);
        return;
      }
    } catch (e) {
      // Not a directory, try as file
    }

    await _operationClient.deleteFile(path);
  });

  Future<void> _deleteDirectoryRecursive(String path) async {
    await _operationClient.changeDirectory(path);
    final items = await _operationClient.listDirectoryContent();

    for (final item in items) {
      if (item.name == '.' || item.name == '..') continue;
      final fullPath = p.posix.join(path, item.name);

      if (item.type == FTPEntryType.dir) {
        await _deleteDirectoryRecursive(fullPath);
      } else {
        await _operationClient.deleteFile(fullPath);
      }
    }

    // Go back to parent before removing directory
    await _operationClient.changeDirectory(p.posix.dirname(path));
    await _operationClient.deleteEmptyDirectory(path);
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) =>
      _serialized(() async {
        await _operationClient.rename(sourcePath, targetPath);
      });

  @override
  Future<void> renamePath(String path, String newName) => _serialized(() async {
    final newPath = p.posix.join(p.posix.dirname(path), newName);
    await _operationClient.rename(path, newPath);
  });
}
