import 'dart:io';
import 'dart:typed_data';
import 'package:crisp_storage/crisp_storage.dart';
import 'bounded_download.dart';
import 'cli_storage_client.dart';
import '../config/cli_config.dart';

/// Both CLI engines use the same profile and transport as the GUI.
class SmbCliAdapter
    implements CliStorageClient, CliBoundedDownload, CliStreamingUpload {
  final RemoteConnection connection;
  final SmbSession session;
  SmbCliAdapter._(this.connection) : session = SmbSession(connection);
  factory SmbCliAdapter.fromConfig(Map<String, dynamic> config) {
    if (config['url'] is! String ||
        config['username'] is! String ||
        config['password'] is! String) {
      throw CliConfigException('SMB requires url, username and password.');
    }
    final encryption = config['requireEncryption'];
    if (encryption != null && encryption is! bool) {
      throw CliConfigException('requireEncryption must be a boolean.');
    }
    return SmbCliAdapter._(
      RemoteConnection(
        id: 'cli',
        name: 'SMB',
        kind: 'smb',
        url: config['url'] as String,
        username: config['username'] as String,
        secret: config['password'] as String,
        requireEncryption: encryption != false,
        smbBackend: parseSmbBackend(config['smbBackend']),
      ),
    );
  }
  static Map<String, dynamic> parseIdentity(String identity, String password) {
    final split = identity.lastIndexOf('@smb://');
    if (split < 1) throw CliConfigException('Use username@smb://host/share/.');
    return {
      'username': identity.substring(0, split),
      'url': identity.substring(split + 1),
      'password': password,
    };
  }

  @override
  String get providerName => 'SMB';
  String _url(String path) => session.urlForPath(path);
  CliFileItem _item(RemoteEntry e) => CliFileItem(
    name: e.name,
    path:
        '/${Uri.parse(e.path).pathSegments.skip(connection.url.pathSegments.where((s) => s.isNotEmpty).length).where((s) => s.isNotEmpty).join('/')}',
    isDirectory: e.type == 'folder',
    size: e.size,
  );
  @override
  Future<List<CliFileItem>> list(String remotePath) async =>
      (await session.browse(_url(remotePath))).map(_item).toList();
  @override
  Future<CliFileItem?> stat(String remotePath) async {
    final result = await session.stat(_url(remotePath));
    return result == null ? null : _item(result);
  }

  @override
  Future<void> upload(
    List<int> data,
    String fileName,
    String remoteDir, {
    void Function(int, int)? onProgress,
  }) async {
    if (fileName.isEmpty || fileName.contains('/')) {
      throw const FormatException('Invalid filename.');
    }
    await session.upload(_url('$remoteDir/$fileName'), Stream.value(data));
    onProgress?.call(data.length, data.length);
  }

  @override
  Future<void> uploadFile(
    File file,
    String fileName,
    String remoteDir, {
    void Function(int, int)? onProgress,
  }) async {
    if (fileName.isEmpty || fileName.contains('/')) {
      throw const FormatException('Invalid filename.');
    }
    final size = await file.length();
    var sent = 0;
    await session.upload(
      _url('$remoteDir/$fileName'),
      file.openRead().map((chunk) {
        sent += chunk.length;
        onProgress?.call(sent, size);
        return chunk;
      }),
    );
    onProgress?.call(sent, size);
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    void Function(int, int)? onProgress,
  }) async {
    final info = await stat(remotePath);
    if (info == null || info.isDirectory) {
      throw const RemoteException(
        'Choose an SMB file.',
        code: RemoteErrorCode.invalidFile,
      );
    }
    final output = File(localPath), staging = File('$localPath.part');
    await output.parent.create(recursive: true);
    if (info.size == 0) {
      await staging.writeAsBytes([]);
    } else {
      await session.download(
        _url(remotePath),
        staging,
        limit: 0x7fffffffffffffff,
        onBytes: (n) => onProgress?.call(n, info.size ?? 0),
      );
    }
    await staging.rename(output.path);
    final marker = File('${staging.path}.resume');
    if (await marker.exists()) await marker.delete();
  }

  @override
  Future<List<int>> downloadBytes(String remotePath) =>
      downloadBytesBounded(remotePath, maxBytes: 64 * 1024 * 1024);
  @override
  Future<Uint8List> downloadBytesBounded(
    String remotePath, {
    required int maxBytes,
  }) async {
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    final info = await stat(remotePath);
    if ((info?.size ?? 0) > maxBytes) throw CliDownloadLimitException(maxBytes);
    final result = BytesBuilder(copy: false);
    await for (final chunk in session.stream(_url(remotePath))) {
      if (result.length + chunk.length > maxBytes) {
        throw CliDownloadLimitException(maxBytes);
      }
      result.add(chunk);
    }
    return result.takeBytes();
  }

  @override
  Future<void> createDirectory(String path) => session.mkdir(_url(path));
  @override
  Future<void> delete(String path) async {
    final entry = await stat(path);
    if (entry == null) {
      throw const RemoteException(
        'SMB path not found.',
        code: RemoteErrorCode.smbNotFound,
      );
    }
    await session.delete(_url(path), directory: entry.isDirectory);
  }

  @override
  Future<void> move(String sourcePath, String targetPath) =>
      session.rename(_url(sourcePath), _url(targetPath));
  @override
  Future<String> share(String path, {Duration? expires}) async =>
      throw UnsupportedError('SMB does not provide public share links.');
  @override
  Future<void> dispose() async => session.close();
}
