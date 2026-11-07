import 'dart:io';
import 'dart:isolate';

import 'package:crisp_cloud/services/storage_scan_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late NativeStorageScanWorker worker;

  setUp(() async {
    final temporary = await Directory.systemTemp.createTemp('scan-session-');
    root = Directory(await temporary.resolveSymbolicLinks());
    worker = await NativeStorageScanWorker.start();
  });

  tearDown(() async {
    await worker.close();
    await root.delete(recursive: true);
  });

  test(
    'one worker routes queued directories and retains exact metadata',
    () async {
      final first = await Directory(p.join(root.path, 'first')).create();
      final second = await Directory(p.join(root.path, 'second')).create();
      await File(p.join(first.path, '雪.txt')).writeAsBytes([1, 2, 3]);
      await File(p.join(first.path, '.hidden')).writeAsBytes([4]);
      await File(p.join(second.path, 'zero.bin')).create();
      await Directory(p.join(second.path, 'empty')).create();

      final results = await Future.wait([
        worker.readDirectory(first.path),
        worker.readDirectory(second.path),
        worker.readDirectory(first.path),
      ]);

      for (final result in results) {
        expect(result.isComplete, isTrue);
        expect(result.issues, isEmpty);
        expect(result.entries.every((item) => item.updatedAt != null), isTrue);
      }
      expect(
        {for (final item in results[0].entries) item.name: item.size},
        {'雪.txt': 3, '.hidden': 1},
      );
      final secondItems = {
        for (final item in results[1].entries) item.name: item,
      };
      expect(secondItems['zero.bin']!.size, 0);
      expect(secondItems['empty']!.isFolder, isTrue);
      expect(secondItems['empty']!.size, isNull);
      expect(
        results[2].entries.map((item) => (item.path, item.size)),
        unorderedEquals(
          results[0].entries.map((item) => (item.path, item.size)),
        ),
      );
    },
  );

  test(
    'directory errors leave the worker available for healthy siblings',
    () async {
      await expectLater(
        worker.readDirectory(p.join(root.path, 'missing')),
        throwsA(isA<RemoteError>()),
      );
      await File(p.join(root.path, 'retained.bin')).writeAsBytes([1, 2]);

      final result = await worker.readDirectory(root.path);
      expect(result.isComplete, isTrue);
      expect(result.entries.single.name, 'retained.bin');
      expect(result.entries.single.size, 2);
    },
  );

  test(
    'close drains queued reads, is idempotent and rejects new reads',
    () async {
      await File(p.join(root.path, 'payload.bin')).writeAsBytes([1, 2, 3, 4]);
      final reads = [
        worker.readDirectory(root.path),
        worker.readDirectory(root.path),
      ];
      final closing = worker.close();
      expect(worker.close(), same(closing));
      await expectLater(worker.readDirectory(root.path), throwsStateError);

      final results = await Future.wait(reads);
      await closing;
      expect(
        results.every((result) => result.entries.single.size == 4),
        isTrue,
      );
      await worker.close();
      await expectLater(worker.readDirectory(root.path), throwsStateError);
    },
  );

  test('independent scan sessions do not close each other', () async {
    final other = await NativeStorageScanWorker.start();
    try {
      await worker.close();
      final result = await other.readDirectory(root.path);
      expect(result.isComplete, isTrue);
      expect(result.entries, isEmpty);
    } finally {
      await other.close();
    }
  });

  test(
    'session refuses link roots and never counts link target bytes',
    () async {
      final child = await Directory(p.join(root.path, 'child')).create();
      await File(p.join(child.path, 'target.bin')).writeAsBytes([1, 2, 3]);
      final link = await Link(p.join(root.path, 'link')).create(child.path);
      await expectLater(
        worker.readDirectory(link.path),
        throwsA(isA<RemoteError>()),
      );
      final listing = await worker.readDirectory(root.path);
      final item = listing.entries.singleWhere((item) => item.name == 'link');
      expect(item.isSymlink, isTrue);
      expect(item.size, isNull);
      expect(item.isFolder, isFalse);
    },
    skip: Platform.isWindows
        ? 'Link creation may need Windows developer mode.'
        : false,
  );
}
