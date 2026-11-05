import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/transfer_spool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native spools stream to private disk and remove only their own files',
    () async {
      final directory = await Directory.systemTemp.createTemp('spool-test-');
      addTearDown(() => directory.delete(recursive: true));
      final unrelated = File('${directory.path}/keep')
        ..writeAsStringSync('keep');
      await IOOverrides.runZoned(() async {
        final chunks = List.generate(
          300,
          (index) => List.filled(4096, index % 256),
        );
        final spool = await createTransferSpool(Stream.fromIterable(chunks));
        expect(spool.length, 300 * 4096);
        expect(await File(spool.localPath!).length(), spool.length);
        final contents = await spool
            .openRead()
            .expand((chunk) => chunk)
            .toList();
        expect(contents, chunks.expand((chunk) => chunk).toList());
        await spool.dispose();
        await spool.dispose();
        expect(await File(spool.localPath!).exists(), isFalse);
        expect(() => spool.openRead(), throwsStateError);
      }, getSystemTempDirectory: () => directory);
      expect(await directory.list().map((entry) => entry.path).toList(), [
        unrelated.path,
      ]);
    },
  );

  for (final mode in ['too long', 'too short', 'source error', 'cancelled']) {
    test('$mode spooling removes partial data', () async {
      final directory = await Directory.systemTemp.createTemp(
        'spool-fail-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      await IOOverrides.runZoned(() async {
        Stream<List<int>> source() async* {
          yield [1, 2, 3];
          if (mode == 'source error') throw StateError('Source failed');
          yield [4, 5, 6];
        }

        await expectLater(
          createTransferSpool(
            source(),
            expectedLength: mode == 'too short' ? 10 : null,
            maxBytes: mode == 'too long' ? 4 : null,
            checkpoint: mode == 'cancelled'
                ? () async => throw const FileOperationCancelled()
                : null,
          ),
          throwsA(anything),
        );
        expect(await directory.list().toList(), isEmpty);
      }, getSystemTempDirectory: () => directory);
    });
  }

  test('cancellation releases a pending source read without awaiting stalled provider cleanup', () async {
    final control = FileOperationControl();
    final cleanup = Completer<void>();
    final cleanupStarted = Completer<void>();
    final source = StreamController<int>(
      onCancel: () {
        cleanupStarted.complete();
        return cleanup.future;
      },
    );
    final assertion = expectLater(
      control.bind(source.stream).toList(),
      throwsA(isA<FileOperationCancelled>()),
    );
    control.cancel();
    await assertion.timeout(const Duration(seconds: 2));
    expect(cleanupStarted.isCompleted, isTrue);
    cleanup.complete();
    await source.close();
  });

  test(
    'stream subscription pause propagates backpressure to the source',
    () async {
      final control = FileOperationControl();
      final paused = Completer<void>();
      final resumed = Completer<void>();
      final source = StreamController<int>(
        onPause: () => paused.complete(),
        onResume: () => resumed.complete(),
      );
      final values = <int>[];
      final subscription = control.bind(source.stream).listen(values.add);
      subscription.pause();
      await paused.future;
      source.add(7);
      expect(values, isEmpty);
      subscription.resume();
      await resumed.future;
      await source.close();
      expect(values, [7]);
      await subscription.cancel();
    },
  );
}
