import 'dart:io';

import 'package:crisp_cloud/services/internxt_client_adapter.dart';
import 'package:crisp_cloud/services/internxt_streaming_transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internxt_client/internxt_client.dart' as sdk;
import 'package:path/path.dart' as p;

class _DownloadFixture extends InternxtStreamingTransfer {
  _DownloadFixture({this.fail = false, this.duringDownload});
  final bool fail;
  final Future<void> Function()? duringDownload;
  String? requested;
  @override
  Stream<List<int>> download(
    InternxtTransferSession session,
    String path, {
    void Function(int, int)? onProgress,
    int? maxBytes,
  }) async* {
    requested = path;
    await duringDownload?.call();
    session.checkCurrent();
    yield [1, 2];
    if (fail) throw const FileSystemException('Fixture download interrupted');
    yield [3, 4];
    onProgress?.call(4, 4);
  }
}

InternxtClientAdapter _adapter(_DownloadFixture streaming) =>
    InternxtClientAdapter.withClient(
      sdk.InternxtClient(
        config: sdk.ConfigService(
          configPath: '/unused-memory-config',
          storage: sdk.InMemoryConfigStorage(),
        ),
      )..setAuth({
        'userId': 'fixture',
        'bridgeUser': 'fixture',
        'userIdForAuth': 'fixture',
        'mnemonic': 'fixture',
        'newToken': 'fixture',
        'rootFolderId': 'root',
        'bucketId': '0123456789abcdef01234567',
      }),
      streaming: streaming,
    );

void main() {
  test('selected-file access stages privately when its parent cannot create an inbox', () async {
    final base = await Directory.current.createTemp('internxt_permissions_');
    final root = await Directory(p.join(base.path, 'selected')).create();
    final fallback = await Directory(p.join(base.path, 'private')).create();
    final target = File(p.join(root.path, 'selected.bin'));
    var sawPrivateStage = false;
    try {
      await target.writeAsBytes([9]);
      expect((await Process.run('chmod', ['500', root.path])).exitCode, 0);
      final fixture = _DownloadFixture(
        duringDownload: () async {
          final stages = await fallback.list().toList();
          sawPrivateStage = stages.length == 1 && stages.single is Directory;
          expect(
            await root.list().where((entry) => entry is Directory).toList(),
            isEmpty,
          );
        },
      );
      await IOOverrides.runZoned(
        () =>
            _adapter(fixture).downloadFileByPath('/Lecture 1.wav', target.path),
        getSystemTempDirectory: () => fallback,
      );
      expect(await target.readAsBytes(), [1, 2, 3, 4]);
      expect(sawPrivateStage, isTrue);
      expect(await fallback.list().toList(), isEmpty);
    } finally {
      await Process.run('chmod', ['700', root.path]);
      await base.delete(recursive: true);
    }
  }, skip: Platform.isWindows);

  test(
    'unauthenticated download fails before filesystem or network work',
    () async {
      final client = InternxtClientAdapter(
        config: sdk.ConfigService(
          configPath: '/unused-memory-config',
          storage: sdk.InMemoryConfigStorage(),
        ),
      );
      await expectLater(
        client.downloadFileByPath('/file.wav', '/unused-target'),
        throwsStateError,
      );
    },
  );

  for (final remote in ['/books/Lecture 1.wav', '/books/Lecture 1']) {
    test(
      'stream download reaches the selected destination for $remote',
      () async {
        final root = await Directory.current.createTemp('internxt_adapter_');
        final fixture = _DownloadFixture();
        try {
          final unrelated = File(p.join(root.path, 'Lecture 1.wav'));
          await unrelated.writeAsBytes([9]);
          final requested = File(p.join(root.path, 'preview-unique.bin'));
          await requested.writeAsBytes([8]);
          final progress = <int>[];
          await _adapter(fixture).downloadFileByPath(
            remote,
            requested.path,
            onProgress: (done, total) => progress.add(done),
          );
          expect(fixture.requested, remote);
          expect(await requested.readAsBytes(), [1, 2, 3, 4]);
          expect(await unrelated.readAsBytes(), [9]);
          expect(progress.last, 4);
          expect(
            await root.list().where((entry) => entry is Directory).toList(),
            isEmpty,
          );
        } finally {
          await root.delete(recursive: true);
        }
      },
    );
  }

  test(
    'interrupted stream preserves destination and removes its private stage',
    () async {
      final root = await Directory.current.createTemp('internxt_adapter_');
      try {
        final target = File(p.join(root.path, 'existing.bin'));
        await target.writeAsBytes([9]);
        await expectLater(
          _adapter(_DownloadFixture(fail: true))
              .downloadFileByPath('/file.wav', target.path),
          throwsA(isA<FileSystemException>()),
        );
        expect(await target.readAsBytes(), [9]);
        expect(
          await root.list().where((entry) => entry is Directory).toList(),
          isEmpty,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
