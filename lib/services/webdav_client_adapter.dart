import 'package:crisp_storage/crisp_storage.dart' as storage;

// lib/services/webdav_client_adapter.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart' as dio;
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:path/path.dart' as p;

import 'cloud_storage_interface.dart';
import 'bounded_transfer_stream.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';
import 'webdav_config_service.dart';

import 'dart:io' as dart_io;
import './webdav_operation_failure.dart';

class WebDavClientAdapter extends CloudStorageClient
    with CloudTransferOperations {
  @override
  StorageTransferCapabilities get transferCapabilities =>
      const StorageTransferCapabilities(
        nativeCopy: true,
        noReplaceCopy: true,
        nativeMove: true,
        atomicMove: true,
        noReplaceMove: true,
        boundedDownload: !kIsWeb,
        boundedUpload: !kIsWeb,
      );

  @override
  Future<CloudTransferResult> copyToExact(
    String sourcePath,
    String destinationPath, {
    bool replace = false,
    String? expectedSourceVersion,
    String? expectedDestinationVersion,
    TransferCheckpoint? checkpoint,
    void Function(int, int)? onProgress,
  }) async {
    await _ensureClient();
    await checkpoint?.call();
    if (expectedSourceVersion != null || expectedDestinationVersion != null) {
      throw UnsupportedError(
        'This WebDAV library cannot send conditional copy headers.',
      );
    }
    return _exactTransfer('COPY', sourcePath, destinationPath, replace);
  }

  @override
  Future<CloudTransferResult> moveToExact(
    String sourcePath,
    String destinationPath, {
    bool replace = false,
    String? expectedSourceVersion,
    String? expectedDestinationVersion,
    TransferCheckpoint? checkpoint,
  }) async {
    await _ensureClient();
    await checkpoint?.call();
    if (expectedSourceVersion != null || expectedDestinationVersion != null) {
      throw UnsupportedError(
        'This WebDAV library cannot send conditional move headers.',
      );
    }
    return _exactTransfer('MOVE', sourcePath, destinationPath, replace);
  }

  Future<CloudTransferResult> _exactTransfer(
    String method,
    String source,
    String destination,
    bool replace,
  ) async {
    if (!p.posix.isAbsolute(source) || !p.posix.isAbsolute(destination)) {
      throw ArgumentError('WebDAV transfer paths must be absolute.');
    }
    final client = _client!;
    final base = Uri.parse(client.uri);
    final target = base.replace(
      pathSegments: [
        ...base.pathSegments.where((segment) => segment.isNotEmpty),
        ...destination.split('/').where((segment) => segment.isNotEmpty),
      ],
    );
    var challenges = 0;
    try {
      // The library's copy/move helper treats every 207 as successful. A
      // Multi-Status response may instead describe a partly failed operation.
      final response = await client.c.req<dio.ResponseBody>(
        client,
        method,
        Uri(pathSegments: source.split('/')).toString(),
        optionsHandler: (options) {
          options.responseType = dio.ResponseType.stream;
          options.followRedirects = false;
          options.headers!['destination'] = target.toString();
          options.headers!['overwrite'] = replace ? 'T' : 'F';
          options.validateStatus = (status) {
            if (status == null || (status >= 300 && status < 400)) return false;
            if (status == 401 && ++challenges > 2) return false;
            return true;
          };
        },
      );
      var metadataBytes = 0;
      if (response.data case final body?) {
        await for (final bytes in body.stream) {
          metadataBytes += bytes.length;
          if (metadataBytes > 256 * 1024) {
            throw StateError('WebDAV returned oversized transfer metadata.');
          }
        }
      }
      if (response.statusCode != 201 && response.statusCode != 204) {
        throw StateError(
          'WebDAV $method did not confirm complete success (${response.statusCode}). '
          'Inspect the retained source and destination before retrying.',
        );
      }
      return CloudTransferResult(path: destination);
    } on dio.DioException catch (error) {
      throw StateError(
        'WebDAV $method was not confirmed (${error.response?.statusCode ?? 'connection interrupted'}). '
        'No redirected destination was authorized.',
      );
    }
  }

  static const _log = Log('WebDAVClient');

  final WebDavConfigService _config;
  final webdav.Client Function(String, String, String) _clientFactory;

  WebDavConfigService get config => _config;

  webdav.Client? _client;
  storage.RemoteClient? _streamClient;
  @override
  bool get supportsStreaming => !kIsWeb;
  String? _user;
  String? _host;

  WebDavClientAdapter({
    required dynamic config,
    webdav.Client Function(String, String, String)? clientFactory,
  }) : _clientFactory =
           clientFactory ??
           ((url, user, password) => webdav.newClient(
             url,
             user: user,
             password: password,
             debug: false,
           )),
       _config = (config is WebDavConfigService)
           ? config
           : WebDavConfigService(
               configPath: '',
               secureStorage: InMemorySecureStorage(),
             );

  @override
  String get providerName => 'WebDAV';

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated => _client != null;

  @override
  String? get userId => _user;

  @override
  String? get bucketId => _host;

  void _initClient(String url, String user, String password) {
    _streamClient?.close();
    _streamClient = kIsWeb
        ? null
        : storage.RemoteClient(
            storage.RemoteConnection(
              id: 'crispcloud-webdav',
              name: 'WebDAV',
              kind: 'webdav',
              url: url,
              username: user,
              secret: password,
              allowLocalHttp: true,
            ),
          );
    _client = _clientFactory(url, user, password);
    _client!.setHeaders({'Content-Type': 'application/octet-stream'});
  }

  @override
  Future<void> login(
    String email,
    String password, {
    String? twoFactorCode,
  }) async {
    String user = email;
    String host = '';

    if (email.contains('@http')) {
      final splitIndex = email.lastIndexOf('@http');
      user = email.substring(0, splitIndex);
      host = email.substring(splitIndex + 1);
    } else {
      throw WebDavException(WebDavOperationCode.invalidIdentity, 'Format must be user@ServerURL');
    }

    try {
      final tempClient = _clientFactory(host, user, password);
      await tempClient.readDir('/');
    } catch (e) {
      throw WebDavException(WebDavOperationCode.connectionFailed, 'Connection failed: $e', {'error': e});
    }

    await _config.saveCredentials({
      'username': user,
      'password': password,
      'host': host,
    });

    _user = user;
    _host = host;
    _initClient(host, user, password);
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    await _ensureClient();

    // Note: webdav_client 1.2.2 returns a List<int>, but it loads fully into memory.
    // It does not expose a stream directly for progress updates easily without modifying the lib.
    final data = await _client!.read(remotePath);

    if (onProgress != null) {
      onProgress(data.length, data.length);
    }

    return Uint8List.fromList(data);
  }

  @override
  Future<void> logout() async {
    _streamClient?.close();
    _streamClient = null;
    _client?.c.close(force: true);
    _client = null;
    await _config.clearCredentials();
  }

  /// Restore the exact saved endpoint/account without rewriting credentials.
  /// Authenticate with a bounded depth-zero probe, not an entire directory
  /// listing. A redirect must not carry saved credentials to another endpoint.
  Future<void> restoreSession({String remotePath = '/'}) async {
    if (!p.posix.isAbsolute(remotePath)) {
      throw ArgumentError.value(remotePath, 'remotePath', 'Must be absolute');
    }
    await _ensureClient();
    final client = _client!;
    final cancel = dio.CancelToken();
    final timeout = Timer(const Duration(seconds: 30), () {
      cancel.cancel('The saved WebDAV connection timed out.');
    });
    var challenges = 0;
    try {
      final response = await client.c.req<dio.ResponseBody>(
        client,
        'PROPFIND',
        Uri(pathSegments: remotePath.split('/')).toString(),
        data:
            '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/>'
            '</d:prop></d:propfind>',
        cancelToken: cancel,
        optionsHandler: (options) {
          options.responseType = dio.ResponseType.stream;
          options.followRedirects = false;
          options.headers!['depth'] = '0';
          options.headers!['content-type'] = 'application/xml;charset=UTF-8';
          options.validateStatus = (status) {
            if (status == 401) return ++challenges <= 2;
            return status == 207;
          };
        },
      );
      var bytes = 0;
      if (response.data case final body?) {
        await for (final chunk in body.stream) {
          bytes += chunk.length;
          if (bytes > 256 * 1024) {
            cancel.cancel('The WebDAV authentication response is too large.');
            throw StateError(
              'The WebDAV authentication response is too large.',
            );
          }
        }
      }
      if (response.statusCode != 207) {
        throw StateError('The saved WebDAV account was not authenticated.');
      }
    } finally {
      timeout.cancel();
    }
  }

  Future<void> _ensureClient() async {
    if (_client != null) return;

    final creds = await _config.readCredentials();
    if (creds == null) throw WebDavException(WebDavOperationCode.notLoggedIn, 'Not logged in');

    _user = creds['username'];
    _host = creds['host'];
    _initClient(_host!, _user!, creds['password']!);
  }

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    await _ensureClient();
    try {
      final list = await _client!.readDir(path);
      if (list.isEmpty) return null;

      final item = list.first;

      // FIX: Use isDir and mTime for webdav_client 1.2.2
      return {
        'type': (item.isDir ?? false) ? 'folder' : 'file',
        'name': item.name ?? p.basename(path),
        'path': path,
        'size': item.size,
        'updatedAt': item.mTime?.toIso8601String(),
        'uuid': path,
      };
    } catch (e) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    await _ensureClient();

    final folders = <Map<String, dynamic>>[];
    final files = <Map<String, dynamic>>[];

    try {
      final contents = await _client!.readDir(path);

      for (final item in contents) {
        if (item.name == null || item.name == '.' || item.name == '..') {
          continue;
        }

        final fullPath = p.posix.join(path, item.name);
        // FIX: Use isDir
        final isDir = item.isDir ?? false;

        final map = {
          'uuid': fullPath,
          'name': item.name,
          'size': item.size,
          // FIX: Use mTime
          'modificationTime': item.mTime?.toIso8601String(),
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
      throw WebDavException(WebDavOperationCode.listFailed, 'Failed to list path $path: $e', {'path': path, 'error': e});
    }

    return {'folders': folders, 'files': files};
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
    if (kIsWeb) {
      // The browser transport used by webdav_client collects request bodies.
      // Bound that fallback explicitly instead of implying a streamed PUT.
      if (length > 32 * 1024 * 1024) {
        throw UnsupportedError(
          'WebDAV uploads above 32 MiB require the desktop app.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final part in validatedTransferParts(
        dataStream,
        length,
        64 * 1024,
      )) {
        bytes.add(part);
      }
      return uploadFile(
        bytes.takeBytes(),
        fileName,
        targetPath,
        onProgress: onProgress,
      );
    }
    await _ensureClient();
    final path = Uri(
      pathSegments: p.posix.join(targetPath, fileName).split('/'),
    ).toString();
    Stream<List<int>> checked = validatedTransferParts(
      dataStream,
      length,
      64 * 1024,
    );
    if (length == 0) {
      await checked.drain<void>();
      checked = const Stream.empty();
    }
    await _client!.c.wdWriteWithStream(
      _client!,
      path,
      checked,
      length,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    await _ensureClient();
    final remotePath = p.posix.join(targetPath, fileName);

    await _client!.write(remotePath, Uint8List.fromList(fileData));

    if (onProgress != null) {
      onProgress(fileData.length, fileData.length);
    }
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    await _ensureClient();

    if (kIsWeb) {
      throw WebDavUnsupportedError(WebDavOperationCode.webDownload, 'Use the browser download stream on web');
    }
    final sink = dart_io.File(localPath).openWrite();
    try {
      await for (final chunk in downloadStream(
        remotePath,
        onProgress: onProgress,
      )) {
        sink.add(chunk);
        // Apply disk backpressure instead of accumulating the whole response.
        await sink.flush();
      }
    } finally {
      await sink.close();
    }
  }

  @override
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async* {
    await _ensureClient();
    if (kIsWeb) {
      yield await downloadFileBytes(remotePath, onProgress: onProgress);
      return;
    }
    yield* _streamClient!.downloadStream(
      Uri(path: remotePath.replaceFirst(RegExp(r'^/+'), '')).toString(),
      onProgress: onProgress,
    );
  }

  @override
  Future<void> createFolderPath(String path) async {
    await _ensureClient();
    await _client!.mkdir(path);
  }

  @override
  Future<void> deletePath(String path) async {
    await _ensureClient();
    await _client!.remove(path); // 'remove' instead of 'removeAll' in 1.2.2 usually, checking common usage
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    await _ensureClient();
    // FIX: Use rename() for moving, with overwrite=false (or true if preferred)
    await _client!.rename(sourcePath, targetPath, false);
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    await _ensureClient();
    final newPath = p.posix.join(p.dirname(path), newName);
    // FIX: Use rename()
    await _client!.rename(path, newPath, false);
  }

  @override
  Future<bool> is2faNeeded(String email) async => false;
}
