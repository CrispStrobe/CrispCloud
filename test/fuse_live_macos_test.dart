// Opt-in native integration: CRISPCLOUD_FUSE_TEST_BACKEND=macfuse-fskit or
// fuse-t, and CRISPCLOUD_FUSE_TEST_HELPER=/path/to/crispcloud_fuse_bridge.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/fuse_filesystem.dart';
import 'package:crisp_cloud/services/fuse_mount_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixtureClient implements CloudStorageClient {
  @override
  String get providerName => 'Fixture';
  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async => null;
  @override
  Future<Map<String, dynamic>> listPath(String path) async => path == '/remote'
      ? {
          'folders': [
            {'name': '旅行'},
          ],
          'files': [
            {'name': 'café.txt', 'size': 5},
            {'name': 'offline.txt', 'size': 5},
          ],
        }
      : {'folders': [], 'files': []};
  @override
  Future<Uint8List> downloadFileBytes(
    String path, {
    Function(int, int)? onProgress,
  }) async {
    if (path.endsWith('/offline.txt')) throw const SocketException('offline');
    return Uint8List.fromList(utf8.encode('hello'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final backend = Platform.environment['CRISPCLOUD_FUSE_TEST_BACKEND'];
  final helper = Platform.environment['CRISPCLOUD_FUSE_TEST_HELPER'];
  test(
    'native mount lists, reads, rejects writes and unmounts',
    () async {
      for (var cycle = 0; cycle < 2; cycle++) {
        final dir = await Directory.systemTemp.createTemp('cc_fuse_live_');
        final mount = Directory('${dir.path}/mount');
        await mount.create();
        final fs = FuseFilesystem(
          client: _FixtureClient(),
          remotePath: '/remote',
        );
        unawaited(fs.serveRequests());
        final socket = await fs.ready;
        final process = await Process.start(helper!, [
          mount.path,
          socket,
          backend!,
        ]);
        final output = StringBuffer();
        final ready = Completer<void>();
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              output.writeln(line);
              if (line == 'MOUNTED' && !ready.isCompleted) ready.complete();
            });
        process.stderr.transform(utf8.decoder).listen(output.write);
        try {
          await Future.any<void>([
            ready.future,
            process.exitCode.then(
              (code) => throw StateError('Helper exited $code: $output'),
            ),
          ]).timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              throw StateError('Mount did not become ready: $output');
            },
          );
          var mounted = false;
          for (var attempt = 0; attempt < 50; attempt++) {
            if (await FuseMountService().isPlatformMountPoint(mount.path)) {
              mounted = true;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(mounted, isTrue, reason: 'No mount appeared: $output');
          final names = await mount
              .list()
              .map(
                (item) => item.uri.pathSegments.where((s) => s.isNotEmpty).last,
              )
              .toList();
          expect(names, containsAll(['café.txt', '旅行']));
          expect(await File('${mount.path}/café.txt').readAsString(), 'hello');
          expect(await Directory('${mount.path}/旅行').list().toList(), isEmpty);
          await expectLater(
            File('${mount.path}/offline.txt').readAsString(),
            throwsA(isA<FileSystemException>()),
          );
          await expectLater(
            File('${mount.path}/new.txt').writeAsString('blocked'),
            throwsA(isA<FileSystemException>()),
          );
          final unmount = await Process.run('/sbin/umount', [mount.path]);
          expect(unmount.exitCode, 0, reason: '${unmount.stderr}');
        } finally {
          await Process.run('/sbin/umount', [mount.path]);
          process.kill();
          await process.exitCode.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              process.kill(ProcessSignal.sigkill);
              return -1;
            },
          );
          await fs.dispose();
          await dir.delete(recursive: true);
        }
      }
    },
    skip: !Platform.isMacOS || backend == null || helper == null
        ? 'Set CRISPCLOUD_FUSE_TEST_BACKEND and CRISPCLOUD_FUSE_TEST_HELPER on macOS.'
        : false,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
