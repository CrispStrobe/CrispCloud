import 'dart:convert';
import 'package:crisp_storage/crisp_storage.dart'
    show HostKeyPrompt, SftpHostKeyException, openVerifiedSsh;
// lib/adapters/sftp_adapter.dart
//
// Pure-Dart SFTP adapter for the crisp CLI, backed by dartssh2.
// Ported from lib/services/sftp_client_adapter.dart with Flutter / kIsWeb
// dependencies removed (native TCP only in CLI context).

import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../config/cli_config.dart';
import 'cli_storage_client.dart';

class SftpCliAdapter implements CliStorageClient {
  final String _username;
  final String _password;
  final String _host;
  final int _port;

  String? _hostKey;
  String? get trustedHostKey => _hostKey;
  HostKeyPrompt? confirmHostKey;
  SSHClient? _ssh;
  SftpClient? _sftp;

  SftpCliAdapter({
    required String username,
    required String password,
    required String host,
    int port = 22,
    String? hostKey,
  })  : _username = username,
        _password = password,
        _host = host,
        _port = port,
        _hostKey = hostKey;

  factory SftpCliAdapter.fromConfig(Map<String, dynamic> cfg) {
    final username = cfg['username'] as String?;
    final password = cfg['password'] as String?;
    final host = cfg['host'] as String?;
    final port = int.tryParse((cfg['port'] ?? '22').toString()) ?? 22;

    if (username == null || password == null || host == null) {
      throw CliConfigException(
        'SFTP provider config missing required fields: username, password, host',
      );
    }
    return SftpCliAdapter(
      username: username,
      password: password,
      host: host,
      port: port,
      hostKey: cfg['hostKey'] as String?,
    );
  }

  /// Parse the identity string used with `crisp connect`:
  ///   user@host[:port]
  static Map<String, String> parseIdentity(String identity, String password) {
    final atIdx = identity.lastIndexOf('@');
    if (atIdx < 0) {
      throw CliConfigException(
        'Invalid SFTP identity format. Expected: username@host[:port]',
      );
    }
    final username = identity.substring(0, atIdx);
    final hostPort = identity.substring(atIdx + 1);
    final address = Uri.tryParse('ssh://$hostPort');
    if (username.isEmpty ||
        address == null ||
        address.host.isEmpty ||
        address.userInfo.isNotEmpty ||
        address.path.isNotEmpty ||
        address.hasQuery ||
        address.hasFragment ||
        (address.hasPort && (address.port < 1 || address.port > 65535))) {
      throw CliConfigException('Invalid SFTP server address');
    }
    final host = address.host;
    final port = '${address.hasPort ? address.port : 22}';

    return {
      'username': username,
      'password': password,
      'host': host,
      'port': port,
    };
  }

  @override
  String get providerName => 'SFTP';

  Future<void> _ensureConnected() async {
    if (_ssh != null && !_ssh!.isClosed && _sftp != null) return;

    final socket = await SSHSocket.connect(_host, _port,
        timeout: const Duration(seconds: 20));
    _ssh = await openVerifiedSsh(socket,
        username: _username, password: _password, verify: (_, bytes) async {
      final observed = utf8.decode(bytes);
      if (_hostKey == observed) return true;
      final endpoint = '$_host:$_port';
      if (_hostKey != null ||
          confirmHostKey == null ||
          !await confirmHostKey!(endpoint, observed)) {
        throw SftpHostKeyException(observed,
            expected: _hostKey, endpoint: endpoint);
      }
      _hostKey = observed;
      return true;
    });
    await _ssh!.authenticated;
    _sftp = await _ssh!.sftp();
  }

  @override
  Future<List<CliFileItem>> list(String remotePath) async {
    await _ensureConnected();
    final items = await _sftp!.listdir(remotePath);
    final result = <CliFileItem>[];
    for (final item in items) {
      if (item.filename == '.' || item.filename == '..') continue;
      final fullPath = p.posix.join(remotePath, item.filename);
      final modTime = item.attr.modifyTime;
      final modifiedAt = modTime != null
          ? DateTime.fromMillisecondsSinceEpoch(modTime * 1000)
              .toIso8601String()
          : null;
      result.add(CliFileItem(
        name: item.filename,
        path: fullPath,
        isDirectory: item.attr.isDirectory,
        size: item.attr.size,
        modifiedAt: modifiedAt,
      ));
    }
    return result;
  }

  @override
  Future<void> upload(
    List<int> data,
    String fileName,
    String remoteDir, {
    void Function(int sent, int total)? onProgress,
  }) async {
    await _ensureConnected();
    final remoteFilePath = p.posix.join(remoteDir, fileName);
    final file = await _sftp!.open(
      remoteFilePath,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );

    try {
      final bytes = Uint8List.fromList(data);
      const chunkSize = 32 * 1024;
      int offset = 0;

      while (offset < bytes.length) {
        final end = (offset + chunkSize > bytes.length)
            ? bytes.length
            : offset + chunkSize;
        await file.writeBytes(bytes.sublist(offset, end));
        offset = end;
        onProgress?.call(offset, bytes.length);
      }
    } finally {
      await file.close();
    }
  }

  @override
  Future<List<int>> downloadBytes(String remotePath) async {
    await _ensureConnected();
    final file = await _sftp!.open(remotePath, mode: SftpFileOpenMode.read);
    final builder = BytesBuilder(copy: false);

    try {
      int offset = 0;
      while (true) {
        final chunk = await file.readBytes(length: 32 * 1024, offset: offset);
        if (chunk.isEmpty) break;
        builder.add(chunk);
        offset += chunk.length;
      }
      return builder.takeBytes();
    } finally {
      await file.close();
    }
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    await _ensureConnected();
    final file = await _sftp!.open(remotePath, mode: SftpFileOpenMode.read);
    final fileSize = (await file.stat()).size ?? 0;
    final localFile = File(localPath);
    final sink = localFile.openWrite();

    try {
      int downloaded = 0;
      int offset = 0;
      while (true) {
        final chunk = await file.readBytes(length: 32 * 1024, offset: offset);
        if (chunk.isEmpty) break;
        sink.add(chunk);
        offset += chunk.length;
        downloaded += chunk.length;
        onProgress?.call(downloaded, fileSize);
      }
    } finally {
      await sink.close();
      await file.close();
    }
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    await _ensureConnected();
    try {
      await _sftp!.mkdir(remotePath);
    } catch (_) {
      // ignore if already exists
    }
  }

  @override
  Future<void> delete(String remotePath) async {
    await _ensureConnected();
    final stat = await _sftp!.stat(remotePath);
    if (stat.isDirectory) {
      await _deleteDir(remotePath);
    } else {
      await _sftp!.remove(remotePath);
    }
  }

  Future<void> _deleteDir(String path) async {
    final items = await _sftp!.listdir(path);
    for (final item in items) {
      if (item.filename == '.' || item.filename == '..') continue;
      final full = p.posix.join(path, item.filename);
      if (item.attr.isDirectory) {
        await _deleteDir(full);
      } else {
        await _sftp!.remove(full);
      }
    }
    await _sftp!.rmdir(path);
  }

  @override
  Future<void> move(String sourcePath, String targetPath) async {
    await _ensureConnected();
    await _sftp!.rename(sourcePath, targetPath);
  }

  @override
  Future<CliFileItem?> stat(String remotePath) async {
    await _ensureConnected();
    try {
      final s = await _sftp!.stat(remotePath);
      final modTime = s.modifyTime;
      return CliFileItem(
        name: p.posix.basename(remotePath),
        path: remotePath,
        isDirectory: s.isDirectory,
        size: s.size,
        modifiedAt: modTime != null
            ? DateTime.fromMillisecondsSinceEpoch(modTime * 1000)
                .toIso8601String()
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> share(String remotePath, {Duration? expires}) {
    throw UnsupportedError('SFTP does not support share links.');
  }

  @override
  Future<void> dispose() async {
    try {
      await _sftp?.close();
    } catch (_) {}
    try {
      await _ssh?.close();
    } catch (_) {}
    _ssh = null;
    _sftp = null;
  }
}
