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
//   - SharedPreferencesStorage for kIsWeb (file-IO unavailable)
// Path-based facade methods (listPath, uploadFileBytes, movePath,
// etc.) come from the package's `paths.dart` extension methods —
// no local extensions file needed anymore.

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:internxt_client/internxt_client.dart';

import 'cloud_storage_interface.dart';
import 'internxt_client.dart' show InternxtUrls;
import 'internxt_flutter/shared_prefs_storage.dart';
import 'log_service.dart';

class InternxtClientAdapter extends CloudStorageClient {
  static const _log = Log('InternxtClient');
  final InternxtClient _client;

  InternxtClientAdapter({required ConfigService config})
      : _client = InternxtClient(
          // Adapter accepts whatever ConfigService AppState constructed.
          // For Web that means a ConfigService whose storage is
          // SharedPreferencesStorage; for native it's the default
          // FileConfigStorage. Either way, just pass it through.
          config: config,
          networkUrl: InternxtUrls.networkUrl,
          driveApiUrl: InternxtUrls.driveApiUrl,
        );

  @visibleForTesting
  InternxtClientAdapter.withClient(InternxtClient client) : _client = client;

  /// Convenience constructor that builds the right ConfigService
  /// for the host platform. Use this when AppState doesn't already
  /// have one in hand.
  factory InternxtClientAdapter.forHost({required String configPath}) {
    final storage = kIsWeb ? SharedPreferencesStorage() : null;
    return InternxtClientAdapter(
      config: ConfigService(configPath: configPath, storage: storage),
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
  bool get isAuthenticated => _client.userId != null;

  @override
  String? get userId => _client.userId;

  @override
  String? get bucketId => _client.bucketId;

  void setAuth(Map<String, dynamic> creds) {
    _client.setAuth(creds);
  }

  @override
  Future<void> login(String email, String password,
      {String? twoFactorCode}) async {
    _log.debug('Calling InternxtClient login...');
    try {
      final response =
          await _client.login(email, password, tfaCode: twoFactorCode);
      _lastLoginResponse = response;
      _log.debug('Login successful. Keys received: ${response.keys}');
      _client.setAuth(response);
    } catch (e) {
      _log.error('Login failed', e);
      rethrow;
    }
  }

  @override
  Future<bool> is2faNeeded(String email) => _client.is2faNeeded(email);

  @override
  Future<void> logout() async {
    _client.userId = null;
    _client.bucketId = null;
    await _client.config.clearCredentials();
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) {
    // Path-based variant from the package's `paths.dart` extension.
    return _client.downloadFileBytesByPath(remotePath, onProgress: onProgress);
  }

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    try {
      return await _client.resolvePath(path);
    } catch (e) {
      if (e is UnsupportedError) rethrow;
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) => _client.listPath(path);

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int p1, int p2)? onProgress,
  }) {
    // Path-based bytes upload from `paths.dart`.
    return _client.uploadFileBytes(fileData, fileName, targetPath);
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int p1, int p2)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Use browser downloads on the web.');
    }
    if (!isAuthenticated ||
        _client.bridgeUser == null ||
        _client.userIdForAuth == null ||
        _client.mnemonic == null) {
      throw StateError('Sign in to Internxt before downloading.');
    }
    final resolved = await _client.resolvePath(remotePath);
    if (resolved['type'] != 'file') {
      throw StateError('The selected path is not a file.');
    }
    final metadata = (resolved['metadata'] as Map?) ?? resolved;
    var name = metadata['name'] as String? ?? p.posix.basename(remotePath);
    final extension = metadata['fileType'] as String? ?? '';
    if (extension.isNotEmpty &&
        extension != 'file' &&
        !name.toLowerCase().endsWith('.${extension.toLowerCase()}')) {
      name = '$name.$extension';
    }
    // Reject path separators and NUL in provider metadata.
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.codeUnits.contains(92) ||
        name.codeUnits.contains(0) ||
        p.basename(name) != name) {
      throw const FormatException('Invalid remote filename.');
    }
    // SDK 0.2.3 saves the original name but its rename helper reads a missing
    // top-level name. Stage privately under the actual remote filename first.
    final destination = File(localPath);
    await destination.parent.create(recursive: true);
    late final Directory inbox;
    var atomic = true;
    try {
      inbox = await destination.parent.createTemp('.crisp-internxt-download-');
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      final denied = Platform.isWindows ? code == 5 : code == 1 || code == 13;
      if (!denied) rethrow;
      // A sandbox save dialog may grant only the selected file, not its parent.
      inbox = await Directory.systemTemp.createTemp('crisp-internxt-download-');
      atomic = false;
    }
    try {
      final received = File(p.join(inbox.path, name));
      await _client.downloadFileByPath(remotePath, received.path,
          onConflict: 'overwrite');
      final size = await received.length();
      if (atomic) {
        await received.rename(destination.path);
      } else {
        await received.copy(destination.path);
      }
      onProgress?.call(size, size);
    } finally {
      await inbox.delete(recursive: true);
    }
  }

  @override
  Future<void> createFolderPath(String path) => _client.createFolderPath(path);

  @override
  Future<void> deletePath(String path) => _client.deletePath(path);

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    await _client.movePath(sourcePath, targetPath);
  }

  @override
  Future<void> renamePath(String path, String newName) =>
      _client.renamePath(path, newName);

  // Internxt-specific operations exposed for AppState's search UI.
  Future<Map<String, List<Map<String, dynamic>>>> search(String query,
          {bool detailed = false}) =>
      _client.search(query, detailed: detailed);

  Future<List<Map<String, dynamic>>> findFiles(String path, String pattern,
          {int maxDepth = -1}) =>
      _client.findFiles(path, pattern, maxDepth: maxDepth);
}
