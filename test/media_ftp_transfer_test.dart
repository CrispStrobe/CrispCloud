import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/ftp_client_adapter.dart';
import 'package:crisp_cloud/services/ftp_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;

FTPClientFactory _factory(_FTPConnection client) =>
    (
      String host, {
      required int port,
      required String user,
      required String pass,
      required SecurityType securityType,
      required int timeout,
    }) => client;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FTPConfigService config;
  late _FTPConnection connection;
  late FTPClientAdapter adapter;

  setUp(() async {
    config = FTPConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    );
    connection = _FTPConnection();
    adapter = FTPClientAdapter(
      config: config,
      clientFactory: _factory(connection),
    );
    await adapter.login('editor@fixture.invalid', 'synthetic-test-password');
  });

  tearDown(() async {
    await adapter.logout();
  });

  test('uploads pass complete root and nested paths without changing server directory', () async {
    connection.directory = '/unrelated';
    final progress = <(int, int)>[];
    await adapter.uploadFile(
      [1, 2],
      'copy.wav',
      '/media/',
      onProgress: (sent, total) => progress.add((sent, total)),
    );
    await adapter.uploadFile([3, 4], 'copy.wav', '/');
    expect(connection.uploads.map((upload) => upload.$1), [
      '/media/copy.wav',
      '/copy.wav',
    ]);
    expect(connection.uploads.map((upload) => upload.$2), [
      [1, 2],
      [3, 4],
    ]);
    expect(connection.changedDirectories, isEmpty);
    expect(connection.directory, '/unrelated');
    expect(progress, [(2, 2)]);
    for (final path in connection.uploadFiles) {
      expect(await Directory(p.dirname(path)).exists(), isFalse);
    }
  });

  test('same-basename downloads on independent FTP sessions retain their own temporary bytes', () async {
    final otherConnection = _FTPConnection();
    final other = FTPClientAdapter(
      config: config,
      clientFactory: _factory(otherConnection),
    );
    await other.login('editor@fixture.invalid', 'synthetic-test-password');
    addTearDown(other.logout);
    connection.files['/first/source.wav'] = [1, 1, 1];
    otherConnection.files['/second/source.wav'] = [2, 2, 2];
    final bothReady = Completer<void>();
    final release = Completer<void>();
    var ready = 0;
    Future<bool> holdDownload(String path, File file) async {
      if (++ready == 2) bothReady.complete();
      await release.future;
      return true;
    }

    connection.afterDownloadWrite = holdDownload;
    otherConnection.afterDownloadWrite = holdDownload;
    final first = adapter.downloadFileBytes('/first/source.wav');
    final second = other.downloadFileBytes('/second/source.wav');
    try {
      await bothReady.future;
      expect(
        connection.downloadFiles.single,
        isNot(otherConnection.downloadFiles.single),
      );
    } finally {
      release.complete();
    }
    expect(await first, [1, 1, 1]);
    expect(await second, [2, 2, 2]);
    expect(connection.downloadNames, ['/first/source.wav']);
    expect(otherConnection.downloadNames, ['/second/source.wav']);
    expect(connection.changedDirectories, isEmpty);
    expect(otherConnection.changedDirectories, isEmpty);
    for (final path in [
      ...connection.downloadFiles,
      ...otherConnection.downloadFiles,
    ]) {
      expect(await Directory(p.dirname(path)).exists(), isFalse);
    }
  });

  for (final throwsError in [false, true]) {
    test(
      'a ${throwsError ? 'throwing' : 'rejected'} download cleans partial temporary files',
      () async {
        connection.files['/media/source.wav'] = [1, 2, 3];
        connection.afterDownloadWrite = (_, _) async {
          if (throwsError) throw StateError('Interrupted transfer');
          return false;
        };
        await expectLater(
          adapter.downloadFileBytes('/media/source.wav'),
          throwsA(anything),
        );
        expect(connection.downloadNames, ['/media/source.wav']);
        expect(
          await Directory(p.dirname(connection.downloadFiles.single)).exists(),
          isFalse,
        );
      },
    );
  }

  test('downloadFileByPath uses an absolute remote name and leaves the requested local output', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ftp-local-output-test-',
    );
    addTearDown(() async {
      await directory.delete(recursive: true);
    });
    final output = File(p.join(directory.path, 'chosen.wav'));
    connection.directory = '/elsewhere';
    connection.files['/media/source.wav'] = [4, 5, 6];
    final progress = <(int, int)>[];
    await adapter.downloadFileByPath(
      'media/source.wav',
      output.path,
      onProgress: (received, total) => progress.add((received, total)),
    );
    expect(await output.readAsBytes(), [4, 5, 6]);
    expect(connection.downloadNames, ['/media/source.wav']);
    expect(connection.changedDirectories, isEmpty);
    expect(progress, [(3, 3)]);
  });
}

/// Records the adapter-to-library contract, not FTP wire concurrency. Production
/// ftpconnect owns one unqueued control socket, so parallel-transfer isolation
/// above deliberately uses independent connections.
class _FTPConnection implements FTPConnect {
  final files = <String, List<int>>{};
  final uploads = <(String, Uint8List)>[];
  final uploadFiles = <String>[];
  final downloadFiles = <String>[];
  final downloadNames = <String?>[];
  final changedDirectories = <String?>[];
  String directory = '/';
  Future<bool> Function(String path, File file)? afterDownloadWrite;

  @override
  Future<bool> connect() async => true;

  @override
  Future<bool> disconnect() async => true;

  @override
  Future<bool> changeDirectory(String? path) async {
    changedDirectories.add(path);
    directory = path!;
    return true;
  }

  @override
  Future<bool> uploadFile(
    File file, {
    String sRemoteName = '',
    void Function(double, int, int)? onProgress,
  }) async {
    uploadFiles.add(file.path);
    uploads.add((sRemoteName, await file.readAsBytes()));
    return true;
  }

  @override
  Future<bool> downloadFile(
    String? remoteName,
    File file, {
    void Function(double, int, int)? onProgress,
  }) async {
    downloadNames.add(remoteName);
    downloadFiles.add(file.path);
    final source = p.posix.join(directory, remoteName!);
    await file.writeAsBytes(files[source]!, flush: true);
    return await afterDownloadWrite?.call(source, file) ?? true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
