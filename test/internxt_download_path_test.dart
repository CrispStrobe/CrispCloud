import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:internxt_client/internxt_client.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:crisp_cloud/services/internxt_client_adapter.dart';

class DownloadFixture extends sdk.InternxtClient {
  DownloadFixture({this.fail = false, this.name = 'Lecture 1'})
      : super(
            config: sdk.ConfigService(
                configPath: '/unused-memory-config',
                storage: sdk.InMemoryConfigStorage())) {
    setAuth({
      'userId': 'fixture',
      'bridgeUser': 'fixture',
      'userIdForAuth': 'fixture',
      'mnemonic': 'fixture',
      'newToken': 'fixture'
    });
  }
  final bool fail;
  final String name;
  String? destination;
  @override
  Future<Map<String, dynamic>> resolvePath(String path) async => {
        'type': 'file', 'uuid': 'fixture',
        // Real SDK shape: the name lives under metadata and excludes extension.
        'metadata': {'name': name, 'fileType': 'wav'},
      };
  @override
  Future<void> downloadPath(
    String remotePath, {
    String? localDestination,
    required bool recursive,
    required String onConflict,
    required bool preserveTimestamps,
    required List<String> include,
    required List<String> exclude,
    required String bridgeUser,
    required String userIdForAuth,
    required String batchId,
    Map<String, dynamic>? initialBatchState,
    required Future<void> Function(Map<String, dynamic>) saveStateCallback,
  }) async {
    destination = localDestination;
    expect(onConflict, 'overwrite');
    await File(p.join(localDestination!, '$name.wav'))
        .writeAsBytes([1, 2, 3, 4]);
    if (fail) throw const FileSystemException('Fixture download interrupted');
  }
}

void main() {
  test('selected-file access falls back when its parent cannot create an inbox',
      () async {
    final root =
        await Directory.systemTemp.createTemp('crisp-adapter-permissions-');
    final sdkClient = DownloadFixture();
    final target = File(p.join(root.path, 'selected.bin'));
    try {
      await target.writeAsBytes([9]);
      expect((await Process.run('chmod', ['500', root.path])).exitCode, 0);
      await InternxtClientAdapter.withClient(sdkClient)
          .downloadFileByPath('/Lecture 1.wav', target.path);
      expect(await target.readAsBytes(), [1, 2, 3, 4]);
      expect(Directory(sdkClient.destination!).parent.path,
          Directory.systemTemp.path);
      expect(await Directory(sdkClient.destination!).exists(), isFalse);
    } finally {
      await Process.run('chmod', ['700', root.path]);
      await root.delete(recursive: true);
    }
  }, skip: Platform.isWindows);
  test('unauthenticated download fails before filesystem or network work',
      () async {
    final adapter = InternxtClientAdapter(
        config: sdk.ConfigService(
            configPath: '/unused-memory-config',
            storage: sdk.InMemoryConfigStorage()));
    await expectLater(adapter.downloadFileByPath('/file.wav', '/unused-target'),
        throwsA(isA<StateError>()));
  });
  for (final remote in ['/books/Lecture 1.wav', '/books/Lecture 1']) {
    test('SDK download reaches a renamed destination for $remote', () async {
      final root = await Directory.systemTemp.createTemp('crisp-adapter-test-');
      final sdkClient = DownloadFixture();
      try {
        final unrelated = File(p.join(root.path, 'Lecture 1.wav'));
        await unrelated.writeAsBytes([9]);
        final requested = File(p.join(root.path, 'preview-unique.bin'));
        await requested.writeAsBytes([8]);
        final progress = <int>[];
        await InternxtClientAdapter.withClient(sdkClient).downloadFileByPath(
          remote,
          requested.path,
          onProgress: (done, total) => progress.add(done),
        );
        expect(await requested.readAsBytes(), [1, 2, 3, 4]);
        expect(await unrelated.readAsBytes(), [9]);
        expect(progress.last, 4);
        expect(await Directory(sdkClient.destination!).exists(), isFalse);
      } finally {
        await root.delete(recursive: true);
      }
    });
  }
  test(
      'interrupted SDK download preserves the destination and removes its inbox',
      () async {
    final root = await Directory.systemTemp.createTemp('crisp-adapter-test-');
    final sdkClient = DownloadFixture(fail: true);
    try {
      final target = File(p.join(root.path, 'existing.bin'));
      await target.writeAsBytes([9]);
      await expectLater(
          InternxtClientAdapter.withClient(sdkClient)
              .downloadFileByPath('/Lecture 1.wav', target.path),
          throwsA(isA<FileSystemException>()));
      expect(await target.readAsBytes(), [9]);
      expect(await Directory(sdkClient.destination!).exists(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('remote metadata cannot escape the private inbox', () async {
    final sdkClient = DownloadFixture(name: '../invalid');
    await expectLater(
        InternxtClientAdapter.withClient(sdkClient)
            .downloadFileByPath('/file.wav', '/unused-target'),
        throwsA(isA<FormatException>()));
    expect(sdkClient.destination, isNull);
  });
}
