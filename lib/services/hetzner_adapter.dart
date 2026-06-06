// lib/services/hetzner_adapter.dart
//
// Hetzner Storage Box adapter — thin wrapper around SFTPClientAdapter or
// WebDavClientAdapter with Hetzner-specific defaults.
//
// Hetzner Storage Box connectivity:
//   SFTP  — host: uNNNNNN.your-storagebox.de, port: 23
//   WebDAV — URL: https://uNNNNNN.your-storagebox.de/, port: 443 (implicit)
//
// Sub-accounts: Hetzner allows sub-accounts whose login names follow the
// pattern "uNNNNNN-subN".  When a sub-account is specified the effective
// username becomes "<username>-<subAccount>".

import 'dart:typed_data';

import 'cloud_storage_interface.dart';
import 'hetzner_config_service.dart';
import 'log_service.dart';
import 'secure_storage_service.dart';
import 'sftp_client_adapter.dart';
import 'sftp_config_service.dart';
import 'webdav_client_adapter.dart';
import 'webdav_config_service.dart';

// Re-export so consumers only need to import this file.
export 'hetzner_config_service.dart' show HetznerProtocol;

/// Default SFTP port used by Hetzner Storage Boxes (not the standard 22).
const int kHetznerSftpPort = 23;

/// Default WebDAV port used by Hetzner Storage Boxes (HTTPS).
const int kHetznerWebDavPort = 443;

/// Constructs the Hetzner hostname from a username like "u123456".
String hetznerHostname(String username) =>
    '$username.your-storagebox.de';

/// Constructs the full HTTPS WebDAV base URL.
String hetznerWebDavUrl(String username) =>
    'https://${hetznerHostname(username)}/';

/// Returns the effective login username, appending the sub-account suffix
/// when one is provided.
String hetznerEffectiveUsername(String username, String? subAccount) {
  if (subAccount != null && subAccount.isNotEmpty) {
    return '$username-$subAccount';
  }
  return username;
}

// ---------------------------------------------------------------------------
// Adapter
// ---------------------------------------------------------------------------

class HetznerStorageBoxAdapter extends CloudStorageClient {
  static const _log = Log('HetznerAdapter');

  final HetznerConfigService _config;

  /// The inner adapter that performs the actual I/O.  Null until [login].
  CloudStorageClient? _inner;

  HetznerStorageBoxAdapter({required HetznerConfigService config})
      : _config = config;

  /// Factory that creates the adapter with a fresh in-memory config (useful
  /// in tests or one-shot scenarios).
  factory HetznerStorageBoxAdapter.withMemoryStorage() {
    return HetznerStorageBoxAdapter(
      config: HetznerConfigService(secureStorage: InMemorySecureStorage()),
    );
  }

  // ── Provider identity ─────────────────────────────────────────────────────

  @override
  String get providerName => 'Hetzner Storage Box';

  @override
  String get rootPath => '/';

  // ── Auth state ────────────────────────────────────────────────────────────

  @override
  bool get isAuthenticated => _inner?.isAuthenticated ?? false;

  @override
  String? get userId => _inner?.userId;

  @override
  String? get bucketId => _inner?.bucketId;

  // ── Capability flags — delegated to inner adapter ─────────────────────────
  // SFTP capabilities: supportsStreaming = true, rest = defaults.
  // WebDAV capabilities: all defaults.
  // We delegate so the flags change automatically when the protocol changes.

  @override
  bool get supportsStreaming => _inner?.supportsStreaming ?? false;

  @override
  bool get supportsMultipart => _inner?.supportsMultipart ?? false;

  @override
  bool get supportsVersioning => _inner?.supportsVersioning ?? false;

  @override
  bool get supportsSharing => _inner?.supportsSharing ?? false;

  @override
  bool get supportsSearch => _inner?.supportsSearch ?? false;

  @override
  bool get supportsThumbnails => _inner?.supportsThumbnails ?? false;

  @override
  bool get supportsTrash => _inner?.supportsTrash ?? true;

  @override
  bool get supportsNativeShare => _inner?.supportsNativeShare ?? false;

  @override
  bool get supportsServerSideCopy => _inner?.supportsServerSideCopy ?? false;

  @override
  bool get supportsFullTextSearch => _inner?.supportsFullTextSearch ?? false;

  // ── Authentication ────────────────────────────────────────────────────────

  /// Logs in using saved credentials (restores a prior session).
  /// Constructs the appropriate inner adapter from persisted config.
  Future<void> loginFromSaved() async {
    final creds = await _config.readCredentials();
    if (creds == null) throw Exception('No saved Hetzner credentials');

    final username = creds['username'] ?? '';
    final password = creds['password'] ?? '';
    final protocol = HetznerConfigService.parseProtocol(creds['protocol']);
    final subAccount = creds['subAccount'];

    await _loginWithCredentials(
      username: username,
      password: password,
      protocol: protocol,
      subAccount: subAccount,
    );
  }

  /// Primary login entry point.  [email] is treated as the Hetzner username
  /// (uNNNNNN) for symmetry with the [CloudStorageClient] interface; the host
  /// and port are derived automatically.
  @override
  Future<void> login(
    String email,
    String password, {
    String? twoFactorCode,
    HetznerProtocol protocol = HetznerProtocol.sftp,
    String? subAccount,
  }) async {
    // Treat 'email' as the plain username (uNNNNNN).
    final username = email.trim();

    await _config.saveCredentials(
      username: username,
      password: password,
      protocol: protocol,
      subAccount: subAccount,
    );

    try {
      await _loginWithCredentials(
        username: username,
        password: password,
        protocol: protocol,
        subAccount: subAccount,
      );
    } catch (e) {
      await _config.clearCredentials();
      rethrow;
    }
  }

  /// Internal helper: build the inner adapter and connect.
  Future<void> _loginWithCredentials({
    required String username,
    required String password,
    required HetznerProtocol protocol,
    String? subAccount,
  }) async {
    final effectiveUser = hetznerEffectiveUsername(username, subAccount);
    final host = hetznerHostname(username);

    _log.info('Connecting to $host via ${protocol.name} as $effectiveUser');

    switch (protocol) {
      case HetznerProtocol.sftp:
        final sftpConfig = SFTPConfigService(
          configPath: '',
          secureStorage: InMemorySecureStorage(),
        );
        final sftpAdapter = SFTPClientAdapter(config: sftpConfig);
        // SFTP login uses the format "user@host:port"
        await sftpAdapter.login(
          '$effectiveUser@$host:$kHetznerSftpPort',
          password,
        );
        _inner = sftpAdapter;

      case HetznerProtocol.webdav:
        final webdavConfig = WebDavConfigService(
          configPath: '',
          secureStorage: InMemorySecureStorage(),
        );
        final webdavAdapter = WebDavClientAdapter(config: webdavConfig);
        // WebDAV login uses the format "user@ServerURL"
        final webdavUrl = hetznerWebDavUrl(username);
        await webdavAdapter.login(
          '$effectiveUser@$webdavUrl',
          password,
        );
        _inner = webdavAdapter;
    }
  }

  @override
  Future<bool> is2faNeeded(String email) async => false;

  @override
  Future<void> logout() async {
    await _inner?.logout();
    _inner = null;
    await _config.clearCredentials();
  }

  // ── Path operations — delegated ───────────────────────────────────────────

  CloudStorageClient get _requireInner {
    if (_inner == null) throw Exception('Not connected to Hetzner Storage Box');
    return _inner!;
  }

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) =>
      _requireInner.resolvePath(path);

  @override
  Future<Map<String, dynamic>> listPath(String path) =>
      _requireInner.listPath(path);

  // ── File operations — delegated ───────────────────────────────────────────

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) =>
      _requireInner.uploadFile(
        fileData,
        fileName,
        targetPath,
        onProgress: onProgress,
      );

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) =>
      _requireInner.downloadFileByPath(
        remotePath,
        localPath,
        onProgress: onProgress,
      );

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) =>
      _requireInner.downloadFileBytes(remotePath, onProgress: onProgress);

  // ── Folder operations — delegated ─────────────────────────────────────────

  @override
  Future<void> createFolderPath(String path) =>
      _requireInner.createFolderPath(path);

  // ── Delete / Move / Rename — delegated ───────────────────────────────────

  @override
  Future<void> deletePath(String path) => _requireInner.deletePath(path);

  @override
  Future<void> movePath(String sourcePath, String targetPath) =>
      _requireInner.movePath(sourcePath, targetPath);

  @override
  Future<void> renamePath(String path, String newName) =>
      _requireInner.renamePath(path, newName);

  // ── Optional overrides — delegated ───────────────────────────────────────

  @override
  Future<Uint8List?> getThumbnail(String remotePath) =>
      _inner?.getThumbnail(remotePath) ?? Future.value(null);

  @override
  Future<Map<String, int>?> getQuota() =>
      _inner?.getQuota() ?? Future.value(null);

  @override
  Future<void> uploadStream(
    Stream<List<int>> dataStream,
    int length,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) =>
      _requireInner.uploadStream(
        dataStream,
        length,
        fileName,
        targetPath,
        onProgress: onProgress,
      );

  @override
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) =>
      _requireInner.downloadStream(remotePath, onProgress: onProgress);
}
