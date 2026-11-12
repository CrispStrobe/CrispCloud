// lib/services/internxt_client_adapter.dart
//
// Adapter that exposes the published internxt_client package
// through cloud-dart's CloudStorageClient interface (so AppState
// can treat Internxt the same way it treats Filen / SFTP / WebDAV).
//
// Phase 6.c: previously delegated to an embedded ~2700-line copy
// of the protocol (see ../internxt_client.dart pre-rewire). Now
// constructs a real InternxtClient from the package, passing:
//   - URL overrides for kIsWeb (Vercel proxy paths)
//   - Host secure storage for credentials on native and web
// Bounded transfers reuse the package's cryptography with private spooling.
// Directory/path reads use request-local caches so newly uploaded objects are
// immediately visible without relying on the SDK session's one-hour cache.

import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:internxt_client/internxt_client.dart';
import 'package:crisp_storage/rust_cloud.dart';

import 'cloud_storage_interface.dart';
import 'connection_failure.dart';
import 'internxt_client.dart' show InternxtUrls;
import 'internxt_operation_failure.dart';
import 'internxt_flutter/secure_config_storage.dart';
import 'secure_storage_service.dart';
import 'log_service.dart';
import 'internxt_streaming_transfer.dart';
import 'internxt_transfer_platform.dart';
import 'rust_cloud_delegate.dart';

class InternxtClientAdapter extends CloudStorageClient
    with CloudTransferOperations
    implements FreshCloudDirectoryReader {
  static const _log = Log('InternxtClient');
  final InternxtClient _client;
  final InternxtStreamingTransfer _streaming;
  int _authGeneration = 0;
  final RustCloudApi? _rustApiOverride;

  /// Requested engine for the next sign-in (per connection profile, default
  /// from `CRISP_INTERNXT_BACKEND`). A restored session keeps the engine whose
  /// format it was saved in; Dart and Rust sessions are not interchangeable.
  CloudEngine engine = configuredCloudEngine(RustCloudProvider.internxt);
  CloudEngine? _effectiveEngine;
  RustCloudDelegate? _rust;

  CloudEngine? get effectiveEngine => _effectiveEngine;
  RustCloudApi get _rustApi => _rustApiOverride ?? defaultRustCloudApi();

  @override
  bool get supportsStreaming => true;
  @override
  bool get supportsMultipart => true;
  @override
  StorageTransferCapabilities get transferCapabilities =>
      const StorageTransferCapabilities(
        boundedUpload: true,
        boundedDownload: true,
      );
  @override
  String get transferIdentity => _rust != null
      ? jsonEncode(['internxt-rust', _rust!.account, _rust!.rootId])
      : jsonEncode([
    'internxt',
    _client.driveApiUrl,
    _client.networkUrl,
    userId,
    bucketId,
    _client.rootFolderId,
  ]);

  Future<void> _persistRust(String email, String envelope) =>
      _client.config.saveCredentials({
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
  Future<bool> restoreSavedSession(Map<String, dynamic> creds) async {
    final envelope = creds['rustSession'];
    if (envelope is String && envelope.isNotEmpty) {
      await _rustApi.initialize();
      final session = await RustCloudSession.restore(
        _rustApi,
        RustCloudProvider.internxt,
        envelope,
      );
      final email = creds['email'] as String? ?? session.account;
      _authGeneration++;
      _client.setAuth({});
      _closeRust();
      _rust = RustCloudDelegate(
        session,
        persist: (renewed) => _persistRust(email, renewed),
      );
      _effectiveEngine = CloudEngine.rust;
      return true;
    }
    if (creds['token'] == null) return false;
    _closeRust();
    setAuth(creds);
    _effectiveEngine = CloudEngine.dart;
    return true;
  }

  InternxtClientAdapter({required ConfigService config, RustCloudApi? rustApi})
    : _rustApiOverride = rustApi,
      _streaming = const InternxtStreamingTransfer(),
      _client = InternxtClient(
        // Production callers inject the host's secure ConfigStorage. Keep the
        // ConfigService seam so isolated tests can supply their own backend.
        config: config,
        networkUrl: InternxtUrls.networkUrl,
        driveApiUrl: InternxtUrls.driveApiUrl,
      );

  @visibleForTesting
  InternxtClientAdapter.withClient(
    this._client, {
    InternxtStreamingTransfer? streaming,
    RustCloudApi? rustApi,
  }) : _rustApiOverride = rustApi,
       _streaming = streaming ?? const InternxtStreamingTransfer();

  /// Convenience constructor that builds the right ConfigService
  /// for the host platform. Use this when AppState doesn't already
  /// have one in hand.
  factory InternxtClientAdapter.forHost({
    required String configPath,
    required SecureStorage secureStorage,
  }) {
    return InternxtClientAdapter(
      config: createSecureInternxtConfig(
        configPath: configPath,
        secureStorage: secureStorage,
      ),
    );
  }

  ConfigService get config => _client.config;

  Map<String, dynamic>? get lastLoginResponse => _lastLoginResponse;
  Map<String, dynamic>? _lastLoginResponse;

  @override
  String get providerName => 'Internxt';

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated => _rust != null || _client.userId != null;

  @override
  String? get userId => _rust?.account ?? _client.userId;

  @override
  String? get bucketId => _rust != null ? null : _client.bucketId;

  void setAuth(Map<String, dynamic> creds) {
    _authGeneration++;
    _client.setAuth(creds);
  }

  @override
  Future<void> login(
    String email,
    String password, {
    String? twoFactorCode,
  }) async {
    _authGeneration++;
    // Choose the engine before any credential leaves this method. Auto uses
    // Dart only when the Rust library cannot load; sign-in failures never
    // switch engines.
    final selected = await selectCloudEngine(engine, () => _rustApi.initialize());
    if (selected == CloudEngine.rust) {
      final session = await RustCloudSession.login(
        _rustApi,
        RustCloudProvider.internxt,
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
      _client.setAuth({});
      _lastLoginResponse = null;
      _closeRust();
      _rust = RustCloudDelegate(
        session,
        persist: (renewed) => _persistRust(email, renewed),
      );
      _effectiveEngine = CloudEngine.rust;
      return;
    }
    _closeRust();
    _log.debug('Calling InternxtClient login...');
    try {
      final response = await _client.login(
        email,
        password,
        tfaCode: twoFactorCode,
      );
      _lastLoginResponse = response;
      _log.debug('Login successful. Keys received: ${response.keys}');
      setAuth(response);
      _effectiveEngine = CloudEngine.dart;
    } catch (e) {
      _log.error('Login failed', e);
      rethrow;
    }
  }

  @override
  Future<bool> is2faNeeded(String email) async {
    // The Rust engine reports TwoFactorRequired from sign-in instead of a
    // separate pre-check; resolve the engine without loading credentials.
    if (engine != CloudEngine.dart) {
      final selected = await selectCloudEngine(
        engine,
        () => _rustApi.initialize(),
      );
      if (selected == CloudEngine.rust) return false;
    }
    return _client.is2faNeeded(email);
  }

  @override
  Future<void> logout() async {
    _closeRust();
    _effectiveEngine = null;
    _authGeneration++;
    _client.setAuth({});
    _lastLoginResponse = null;
    await _client.config.clearCredentials();
  }

  InternxtTransferSession _capture({bool requireEncryption = true}) {
    final generation = _authGeneration;
    final user = _client.userId,
        bucket = _client.bucketId,
        root = _client.rootFolderId;
    final token = _client.newToken, mnemonic = _client.mnemonic;
    final bridge = _client.bridgeUser, bridgeId = _client.userIdForAuth;
    if (user == null ||
        user.isEmpty ||
        token == null ||
        token.isEmpty ||
        root == null ||
        root.isEmpty ||
        (requireEncryption &&
            (bucket == null ||
                bucket.isEmpty ||
                mnemonic == null ||
                mnemonic.isEmpty ||
                bridge == null ||
                bridge.isEmpty ||
                bridgeId == null ||
                bridgeId.isEmpty))) {
      throw StateError('Sign in to Internxt before transferring files.');
    }
    void check() {
      if (!isAuthenticated ||
          generation != _authGeneration ||
          user != _client.userId ||
          bucket != _client.bucketId ||
          root != _client.rootFolderId ||
          token != _client.newToken ||
          mnemonic != _client.mnemonic ||
          bridge != _client.bridgeUser ||
          bridgeId != _client.userIdForAuth) {
        throw StateError(
          'The original Internxt account is no longer available.',
        );
      }
    }

    check();
    return InternxtTransferSession(
      driveUrl: _client.driveApiUrl,
      networkUrl: _client.networkUrl,
      token: token,
      mnemonic: mnemonic ?? '',
      bucket: bucket ?? '',
      rootFolder: root,
      bridgeUser: bridge ?? '',
      userIdForAuth: bridgeId ?? user,
      checkCurrent: check,
    );
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
    yield* _streaming.download(_capture(), remotePath, onProgress: onProgress);
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    const maxBytes = 32 * 1024 * 1024;
    final rust = _rust;
    if (rust != null) {
      return rust.downloadBytes(
        remotePath,
        onProgress: onProgress,
        maxBytes: maxBytes,
      );
    }
    final result = BytesBuilder(copy: false);
    await for (final bytes in _streaming.download(
      _capture(),
      remotePath,
      onProgress: onProgress,
      maxBytes: maxBytes,
    )) {
      if (result.length + bytes.length > maxBytes) {
        throw StateError('This Internxt file requires a streaming download.');
      }
      result.add(bytes);
    }
    return result.takeBytes();
  }

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    final rust = _rust;
    if (rust != null) return rust.resolvePath(path);
    try {
      return await _streaming.resolve(_capture(requireEncryption: false), path);
    } on InternxtPathNotFound {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) =>
      _rust?.listPath(path) ??
      _streaming.list(_capture(requireEncryption: false), path);

  @override
  Future<Map<String, dynamic>> readDirectoryForEdit(String path) =>
      _rust?.listPath(path, fresh: true) ?? listPath(path);

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
    if (length == 0) throw InternxtEmptyFileUnsupported();
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
    await _streaming.upload(
      _capture(),
      dataStream,
      length,
      fileName,
      targetPath,
      onProgress: onProgress,
    );
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
    final session = _capture();
    await saveInternxtDownload(
      _streaming.download(session, remotePath, onProgress: onProgress),
      localPath,
      checkCurrent: session.checkCurrent,
    );
  }

  @override
  Future<void> createFolderPath(String path) =>
      _rust?.createFolderPath(path) ?? _client.createFolderPath(path);

  @override
  Future<void> deletePath(String path) async {
    final rust = _rust;
    if (rust != null) return rust.deletePath(path);
    final session = _capture(requireEncryption: false);
    final source = await _streaming.resolve(session, path);
    session.checkCurrent();
    await _client.trashItems(
      source['uuid'] as String,
      source['type'] as String,
    );
    session.checkCurrent();
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    final rust = _rust;
    if (rust != null) return rust.movePath(sourcePath, targetPath);
    final session = _capture(requireEncryption: false);
    final source = await _streaming.resolve(session, sourcePath);
    final target = await _streaming.resolve(session, targetPath);
    if (target['type'] != 'folder') {
      throw StateError('The target is not a folder.');
    }
    session.checkCurrent();
    if (source['type'] == 'file') {
      await _client.moveFile(
        source['uuid'] as String,
        target['uuid'] as String,
      );
    } else {
      await _client.moveFolder(
        source['uuid'] as String,
        target['uuid'] as String,
      );
    }
    session.checkCurrent();
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    if (newName.isEmpty ||
        newName == '.' ||
        newName == '..' ||
        newName.contains('/') ||
        newName.contains(r'\') ||
        newName.contains('\u0000')) {
      throw const FormatException('Enter a file name without path separators.');
    }
    final rust = _rust;
    if (rust != null) return rust.renamePath(path, newName);
    final session = _capture(requireEncryption: false);
    final source = await _streaming.resolve(session, path);
    session.checkCurrent();
    if (source['type'] == 'file') {
      await _client.renameFile(
        source['uuid'] as String,
        p.posix.basenameWithoutExtension(newName),
        p.posix.extension(newName).replaceFirst('.', ''),
      );
    } else {
      await _client.renameFolder(source['uuid'] as String, newName);
    }
    session.checkCurrent();
  }

  // Internxt-specific operations exposed for AppState's search UI.
  Future<Map<String, List<Map<String, dynamic>>>> search(
    String query, {
    bool detailed = false,
  }) => _rust != null
      ? Future.error(UnsupportedError('Search uses the Dart Internxt engine.'))
      : _client.search(query, detailed: detailed);

  Future<List<Map<String, dynamic>>> findFiles(
    String path,
    String pattern, {
    int maxDepth = -1,
  }) => _rust != null
      ? Future.error(UnsupportedError('Find uses the Dart Internxt engine.'))
      : _client.findFiles(path, pattern, maxDepth: maxDepth);
}
