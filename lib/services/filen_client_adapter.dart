// lib/services/filen_client_adapter.dart
import 'dart:typed_data';

import 'cloud_storage_interface.dart';

import 'package:filen_client/filen_client.dart';
import 'package:crisp_storage/rust_cloud.dart';

import 'filen_config_service.dart';

import 'package:flutter/foundation.dart'; // for kIsWeb

import 'log_service.dart';
import 'upload_temp_file.dart';
import 'filen_stream_transfer.dart';
import 'internxt_transfer_platform.dart' show saveInternxtDownload;
import './filen_operation_failure.dart';
import 'rust_cloud_delegate.dart';

class FilenClientAdapter extends CloudStorageClient
    with CloudTransferOperations
    implements FreshCloudDirectoryReader {
  @override
  bool get supportsStreaming => true;
  @override
  StorageTransferCapabilities get transferCapabilities =>
      const StorageTransferCapabilities(
        boundedUpload: true,
        boundedDownload: true,
      );
  static const _log = Log('FilenClient');

  final FilenClient _client;
  final FilenConfigService filenConfig;
  final RustCloudApi? _rustApiOverride;

  /// Requested engine for the next sign-in (per connection profile, default
  /// from `CRISP_FILEN_BACKEND`). A restored session keeps the engine whose
  /// format it was saved in; Dart and Rust sessions are not interchangeable.
  CloudEngine engine = configuredCloudEngine(RustCloudProvider.filen);
  CloudEngine? _effectiveEngine;
  RustCloudDelegate? _rust;

  /// Engine of the current session (null before sign-in/restore).
  CloudEngine? get effectiveEngine => _effectiveEngine;
  RustCloudApi get _rustApi => _rustApiOverride ?? defaultRustCloudApi();

  FilenClientAdapter({required FilenConfigService config, RustCloudApi? rustApi})
    : filenConfig = config,
      _rustApiOverride = rustApi,
      _client = FilenClient(
        config: ConfigService(
          configPath: config.configPath,
          storage: config.sdkStorage,
        ),
      );

  @visibleForTesting
  FilenClientAdapter.withClient(
    FilenClient client, {
    required FilenConfigService config,
    RustCloudApi? rustApi,
  }) : _client = client,
       filenConfig = config,
       _rustApiOverride = rustApi;

  Future<void> _persistRust(String email, String envelope) =>
      filenConfig.saveCredentials({
        'email': email,
        'engine': CloudEngine.rust.name,
        'rustSession': envelope,
      });

  void _closeRust() {
    _rust?.close();
    _rust = null;
  }

  /// Restore a saved login. Rust-format credentials require the Rust engine
  /// (strict: no Dart fallback); legacy Dart credentials use the Dart client.
  Future<bool> restoreSavedSession(Map<String, String> creds) async {
    final envelope = creds['rustSession'];
    if (envelope != null && envelope.isNotEmpty) {
      await _rustApi.initialize();
      final session = await RustCloudSession.restore(
        _rustApi,
        RustCloudProvider.filen,
        envelope,
      );
      final email = creds['email'] ?? session.account;
      _closeRust();
      _client.setAuth({});
      _rust = RustCloudDelegate(
        session,
        persist: (renewed) => _persistRust(email, renewed),
      );
      _effectiveEngine = CloudEngine.rust;
      return true;
    }
    if (creds['email'] == null) return false;
    final apiKey = creds['apiKey'];
    if (apiKey == null || apiKey.isEmpty) return false;
    _closeRust();
    _client.setAuth(creds);
    _effectiveEngine = CloudEngine.dart;
    return true;
  }

  (String, List<String>, String, void Function()) _captureTransfer() {
    final token = _client.apiKey;
    final keys = List<String>.of(_client.masterKeys);
    final email = _client.email ?? '';
    final root = _client.baseFolderUUID;
    if (token == null || token.isEmpty || keys.isEmpty) {
      throw StateError('Sign in to Filen before transferring files.');
    }
    void check() {
      if (_client.apiKey != token ||
          (_client.email ?? '') != email ||
          _client.baseFolderUUID != root ||
          !listEquals(keys, _client.masterKeys)) {
        throw StateError('The original Filen account is no longer available.');
      }
    }

    return (token, keys, email, check);
  }

  @override
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async* {
    final rust = _rust;
    if (rust != null) {
      yield* rust.downloadStream(remotePath, onProgress: onProgress);
      return;
    }
    final captured = _captureTransfer();
    final resolved = await _client.resolvePath(remotePath);
    captured.$4();
    if (resolved['type'] != 'file' || resolved['uuid'] is! String) {
      throw StateError('The Filen source is not a file.');
    }
    yield* readFilenStream(
      _client,
      resolved['uuid'] as String,
      token: captured.$1,
      masterKeys: captured.$2,
      checkCurrent: captured.$4,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> uploadStream(
    Stream<List<int>> dataStream,
    int length,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    final rust = _rust;
    if (rust != null) {
      return rust.uploadStream(
        dataStream,
        length,
        fileName,
        targetPath,
        onProgress: onProgress,
      );
    }
    if (fileName.isEmpty ||
        fileName == '.' ||
        fileName == '..' ||
        fileName.contains('/') ||
        fileName.contains(r'\') ||
        fileName.contains('\u0000')) {
      throw const FormatException('Enter a file name without path separators.');
    }
    final captured = _captureTransfer();
    final parent = await _client.resolvePath(targetPath);
    captured.$4();
    if (parent['type'] != 'folder' || parent['uuid'] is! String) {
      throw StateError('The Filen target is not a folder.');
    }
    await writeFilenStream(
      _client,
      dataStream,
      length,
      fileName,
      parent['uuid'] as String,
      token: captured.$1,
      masterKeys: captured.$2,
      email: captured.$3,
      checkCurrent: captured.$4,
      onProgress: onProgress,
    );
  }

  @override
  String get providerName => 'Filen';

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated =>
      _rust != null || _client.apiKey != null && _client.apiKey!.isNotEmpty;

  @override
  String? get userId => _rust?.account ?? _client.email;

  @override
  String? get bucketId => null; // Filen doesn't use buckets in the same way Internxt does

  // Expose for AppState to use
  bool debugMode = false;

  // Expose client for direct access when needed
  FilenClient get client => _client;

  @override
  Future<void> login(
    String email,
    String password, {
    String? twoFactorCode,
  }) async {
    // Choose the engine before any credential leaves this method. Auto uses
    // Dart only when the Rust library cannot load; sign-in failures never
    // switch engines.
    final selected = await selectCloudEngine(engine, () => _rustApi.initialize());
    if (selected == CloudEngine.rust) {
      final session = await RustCloudSession.login(
        _rustApi,
        RustCloudProvider.filen,
        email,
        password,
        twoFactorCode: twoFactorCode,
      );
      try {
        await _persistRust(email, session.envelope);
      } catch (_) {
        session.close();
        rethrow;
      }
      _closeRust();
      _client.setAuth({});
      _rust = RustCloudDelegate(
        session,
        persist: (renewed) => _persistRust(email, renewed),
      );
      _effectiveEngine = CloudEngine.rust;
      return;
    }
    _closeRust();
    // Authenticate
    final credentials = await _client.login(
      email,
      password,
      twoFactorCode: twoFactorCode ?? "",
    );

    // Set auth on the client instance immediately
    _client.setAuth(credentials);

    try {
      // Ensure we have the base folder UUID
      if (credentials['baseFolderUUID'] == null ||
          credentials['baseFolderUUID'].isEmpty) {
        final rootUUID = await _client.fetchBaseFolderUUID();
        credentials['baseFolderUUID'] = rootUUID;
        _client.baseFolderUUID = rootUUID;
      }

      // Save using the same verified store as the injected SDK ConfigService.
      await filenConfig.saveCredentials({
        'email': email,
        'apiKey': credentials['apiKey'] ?? '',
        'masterKeys': credentials['masterKeys'] ?? '',
        'baseFolderUUID': credentials['baseFolderUUID'] ?? '',
        'userId': credentials['userId'] ?? '',
      });
      _effectiveEngine = CloudEngine.dart;
    } catch (_) {
      // A failed login must not leave a usable session behind the error dialog.
      // Keep any durable entry intact: a failed readback may follow a write
      // that actually committed, and deleting it would make recovery harder.
      _client.setAuth({});
      rethrow;
    }
  }

  @override
  Future<bool> is2faNeeded(String email) async {
    // Filen API doesn't have a specific pre-check for 2FA status without attempting login
    return false;
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    final rust = _rust;
    if (rust != null) {
      return rust.downloadBytes(remotePath, onProgress: onProgress);
    }
    // Consume through EOF before returning any bytes. Chunk GCM tags do not
    // bind their order: the verified stream also checks the authenticated size
    // and whole-file hash when the provider metadata contains one.
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in downloadStream(
      remotePath,
      onProgress: onProgress,
    )) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  @override
  Future<void> logout() async {
    _closeRust();
    _effectiveEngine = null;
    _client.setAuth({});
    try {
      await filenConfig.clearCredentials();
      if (!identical(_client.config.storage, filenConfig.sdkStorage)) {
        // withClient can supply a separate SDK backend. It must not silently
        // retain a login even though the app's own secure entry was removed.
        await _client.config.clearCredentials();
        if (await _client.config.storage.readCredentials() != null) {
          throw const FilenCredentialDeletionFailure();
        }
      }
    } catch (_) {
      throw const FilenCredentialDeletionFailure();
    }
  }

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    final rust = _rust;
    if (rust != null) return rust.resolvePath(path);
    try {
      // FilenClient has a resolvePath method
      final resolved = await _client.resolvePath(path);
      return resolved;
    } catch (e) {
      // Return null if not found (standardize behavior)
      if (e.toString().contains('not found')) return null;
      _log.warn('Error resolving path', e);
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> readDirectoryForEdit(String path) async {
    final rust = _rust;
    if (rust != null) return rust.listPath(path, fresh: true);
    // Filen caches directory contents for ten minutes. Refresh only the path's
    // ancestors and target folder instead of evicting unrelated file listings.
    final cache = _client.cache;
    cache.clearPathCache();
    var parentUuid = _client.baseFolderUUID;
    var prefix = '';
    for (final segment in path.split('/').where((part) => part.isNotEmpty)) {
      cache.invalidate(parentUuid);
      prefix = '$prefix/$segment';
      final folder = await _client.resolvePath(prefix);
      if (folder['type'] != 'folder' || folder['uuid'] is! String) {
        throw StateError('The source directory could not be verified.');
      }
      parentUuid = folder['uuid'] as String;
    }
    cache.invalidate(parentUuid);
    return listPath(path);
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    final rust = _rust;
    if (rust != null) return rust.listPath(path);
    try {
      // 1. Resolve path to get the UUID
      final resolved = await _client.resolvePath(path);

      if (resolved['type'] != 'folder') {
        throw FilenOperationFailure(
          FilenOperationCode.notFolder,
          'Path is not a folder',
        );
      }

      final uuid = resolved['uuid'];

      // 2. Fetch folders and files using the UUID
      // FilenClient separates these into two calls
      final folders = await _client.listFoldersAsync(uuid, detailed: true);
      final files = await _client.listFolderFiles(uuid, detailed: true);

      return {'folders': folders, 'files': files};
    } catch (e) {
      _log.warn('Error listing path', e);
      // Return empty structure on error to prevent UI crash
      return {
        'folders': <Map<String, dynamic>>[],
        'files': <Map<String, dynamic>>[],
      };
    }
  }

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    final rust = _rust;
    if (rust != null) {
      return rust.uploadBytes(
        fileData,
        fileName,
        targetPath,
        onProgress: onProgress,
      );
    }
    // 1. Resolve Target
    final resolvedFolder = await _client.resolvePath(targetPath);
    if (resolvedFolder['type'] != 'folder') {
      throw FilenOperationFailure(
        FilenOperationCode.targetNotFolder,
        'Target path is not a folder',
      );
    }
    final parentUuid = resolvedFolder['uuid'];

    if (kIsWeb) {
      // --- WEB PATH (Memory) ---
      // This path purely uses memory and HTTP, avoiding all filesystem calls
      _log.info('Web upload: uploading bytes directly...');
      await _client.uploadBytes(
        Uint8List.fromList(fileData),
        fileName,
        parentUuid,
        onProgress: onProgress,
      );
    } else {
      // --- NATIVE PATH (Disk) ---
      // Wrapped in 'else' to ensure Directory.systemTemp is unreachable on Web
      await withTemporaryUploadFile(fileName, fileData, (tempFile) async {
        await _client.uploadFile(tempFile, parentUuid);
        if (onProgress != null) {
          onProgress(fileData.length, fileData.length);
        }
      });
    }
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    final rust = _rust;
    if (rust != null) {
      return rust.downloadToPath(remotePath, localPath, onProgress: onProgress);
    }
    final captured = _captureTransfer();
    // Reuse the existing platform publisher: private staging until stream EOF,
    // then atomic replacement (or a verified copy for selected-file access).
    // A bad final hash, truncated transfer or account switch must not overwrite
    // an existing destination with partially verified plaintext.
    await saveInternxtDownload(
      downloadStream(remotePath, onProgress: onProgress),
      localPath,
      checkCurrent: captured.$4,
    );
  }

  @override
  Future<void> createFolderPath(String path) async {
    final rust = _rust;
    if (rust != null) return rust.createFolderPath(path);
    // Map to createFolderRecursive in FilenClient
    await _client.createFolderRecursive(path);
  }

  @override
  Future<void> deletePath(String path) async {
    final rust = _rust;
    if (rust != null) return rust.deletePath(path);
    // 1. Resolve path to get UUID
    final resolved = await resolvePath(path);
    if (resolved != null) {
      final uuid = resolved['uuid'] as String;
      final type = resolved['type'] as String;

      // 2. Call trashItem
      await _client.trashItem(uuid, type);
    } else {
      throw FilenOperationFailure(
        FilenOperationCode.unresolvedPath,
        'Could not resolve path: $path',
        {'path': path},
      );
    }
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    final rust = _rust;
    if (rust != null) return rust.movePath(sourcePath, targetPath);
    // 1. Resolve Source
    final sourceResolved = await resolvePath(sourcePath);
    if (sourceResolved == null) {
      throw FilenOperationFailure(
        FilenOperationCode.unresolvedSource,
        'Could not resolve source path: $sourcePath',
        {'path': sourcePath},
      );
    }

    // 2. Resolve Target (Parent folder)
    // Filen moveItem expects the UUID of the *destination folder*
    // If targetPath is the full new path (e.g. /Docs/NewName), we might need logic.
    // Usually move interface implies moving INTO targetPath.

    final targetResolved = await resolvePath(targetPath);
    if (targetResolved == null || targetResolved['type'] != 'folder') {
      throw Exception('Target path must be an existing folder: $targetPath');
    }

    final sourceUuid = sourceResolved['uuid'] as String;
    final sourceType = sourceResolved['type'] as String;
    final targetUuid = targetResolved['uuid'] as String;

    await _client.moveItem(sourceUuid, targetUuid, sourceType);
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    final rust = _rust;
    if (rust != null) return rust.renamePath(path, newName);
    // 1. Resolve path to UUID
    final resolved = await resolvePath(path);

    if (resolved == null) {
      throw FilenOperationFailure(
        FilenOperationCode.unresolvedPath,
        'Could not resolve path: $path',
        {'path': path},
      );
    }

    final uuid = resolved['uuid'] as String;
    final type = resolved['type'] as String;

    // 2. Call renameItem
    await _client.renameItem(uuid, newName, type);
  }
}
