// lib/adapters/rust_cloud_adapter.dart
//
// Filen and Internxt for the standalone CLI, through the shared Rust engine
// in crisp_storage (`rust_cloud/`). The CLI has no Dart Filen/Internxt
// client, so `engine` may only be `rust` (or omitted). A missing native
// library is reported before any credential is used; there is no fallback.

import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_storage/rust_cloud.dart';

import '../config/cli_config.dart';
import 'cli_storage_client.dart';

class RustCloudCliAdapter implements CliStorageClient, CliStreamingUpload {
  RustCloudCliAdapter._(
    this.provider,
    this._email,
    this._password,
    this._twoFactorCode,
    this._api,
  );

  /// [api] is injectable for tests; production uses the native bridge.
  factory RustCloudCliAdapter.fromConfig(
    String type,
    Map<String, dynamic> config, {
    RustCloudApi? api,
  }) {
    final provider = switch (type) {
      'filen' => RustCloudProvider.filen,
      'internxt' => RustCloudProvider.internxt,
      _ => throw CliConfigException('Unsupported provider type "$type".'),
    };
    final email = config['email'];
    final password = config['password'];
    if (email is! String || email.isEmpty) {
      throw CliConfigException('${_label(provider)} requires "email".');
    }
    if (password is! String || password.isEmpty) {
      throw CliConfigException('${_label(provider)} requires "password".');
    }
    final code = config['twoFactorCode'];
    if (code != null && code is! String) {
      throw CliConfigException('twoFactorCode must be a string.');
    }
    final engine = config['engine'];
    if (engine != null && engine != 'rust') {
      throw CliConfigException(
        '${_label(provider)} in the CLI uses the Rust engine; '
        'engine must be "rust" or omitted (got "$engine").',
      );
    }
    return RustCloudCliAdapter._(
      provider,
      email,
      password,
      code as String?,
      api ?? defaultRustCloudApi(),
    );
  }

  final RustCloudProvider provider;
  final String _email;
  final String _password;
  final String? _twoFactorCode;
  final RustCloudApi _api;
  RustCloudSession? _session;

  static String _label(RustCloudProvider provider) =>
      provider == RustCloudProvider.filen ? 'Filen' : 'Internxt';

  @override
  String get providerName => _label(provider);

  Future<RustCloudSession> _open() async {
    final existing = _session;
    if (existing != null && !existing.isClosed) return existing;
    try {
      await _api.initialize();
    } on RustCloudUnavailable {
      throw CliConfigException(
        'The Rust storage engine is not available in this build. Set '
        'CRISP_CLOUD_LIBRARY to libcrisp_cloud_bridge, or build the CLI with '
        'the crisp_storage hook define rust_cloud: true.',
      );
    }
    return _session = await RustCloudSession.login(
      _api,
      provider,
      _email,
      _password,
      twoFactorCode: _twoFactorCode,
    );
  }

  static String _normalize(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty && p != '.');
    return '/${parts.join('/')}';
  }

  static String _join(String dir, String name) {
    final base = _normalize(dir);
    return base == '/' ? '/$name' : '$base/$name';
  }

  static (String parent, String name) _split(String path) {
    final normalized = _normalize(path);
    final cut = normalized.lastIndexOf('/');
    final parent = cut <= 0 ? '/' : normalized.substring(0, cut);
    return (parent, normalized.substring(cut + 1));
  }

  CliFileItem _item(String path, RustCloudEntry entry) => CliFileItem(
    name: entry.name,
    path: path,
    isDirectory: entry.isDirectory,
    size: entry.isDirectory ? null : entry.size,
    modifiedAt: entry.modified?.toIso8601String(),
  );

  @override
  Future<List<CliFileItem>> list(String remotePath) async {
    final session = await _open();
    final dir = _normalize(remotePath);
    final entries = await session.list(dir, fresh: true);
    return [for (final e in entries) _item(_join(dir, e.name), e)];
  }

  @override
  Future<CliFileItem?> stat(String remotePath) async {
    final session = await _open();
    try {
      return _item(
        _normalize(remotePath),
        await session.stat(_normalize(remotePath)),
      );
    } on RustCloudException catch (e) {
      if (e.code == RustCloudErrorCode.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    await (await _open()).mkdir(_normalize(remotePath));
  }

  @override
  Future<void> delete(String remotePath) async {
    await (await _open()).trash(_normalize(remotePath));
  }

  @override
  Future<void> move(String sourcePath, String targetPath) async {
    final session = await _open();
    final source = _normalize(sourcePath);
    final (sourceParent, sourceName) = _split(source);
    final (targetParent, targetName) = _split(targetPath);
    var current = source;
    if (targetParent != sourceParent) {
      await session.move(current, targetParent);
      current = _join(targetParent, sourceName);
    }
    if (targetName != sourceName) {
      await session.rename(current, targetName);
    }
  }

  @override
  Future<void> uploadFile(
    File file,
    String fileName,
    String remoteDir, {
    void Function(int sent, int total)? onProgress,
  }) async {
    await (await _open()).upload(
      file.path,
      _normalize(remoteDir),
      fileName,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> upload(
    List<int> data,
    String fileName,
    String remoteDir, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final dir = await Directory.systemTemp.createTemp('crisp-cloud-up-');
    try {
      final file = File('${dir.path}/upload.bin');
      await file.writeAsBytes(data, flush: true);
      await uploadFile(file, fileName, remoteDir, onProgress: onProgress);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    await (await _open()).download(
      _normalize(remotePath),
      localPath,
      onProgress: onProgress,
    );
  }

  @override
  Future<List<int>> downloadBytes(String remotePath) async {
    final dir = await Directory.systemTemp.createTemp('crisp-cloud-down-');
    try {
      final path = '${dir.path}/download.bin';
      await download(remotePath, path);
      return Uint8List.fromList(await File(path).readAsBytes());
    } finally {
      await dir.delete(recursive: true);
    }
  }

  @override
  Future<String> share(String remotePath, {Duration? expires}) =>
      throw UnsupportedError(
        'Share links are not available for ${_label(provider)} in the CLI.',
      );

  @override
  Future<void> dispose() async {
    _session?.close();
    _session = null;
  }
}
