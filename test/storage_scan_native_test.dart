import 'dart:io';

import 'package:crisp_cloud/services/storage_scan_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('crisp-scan-worker-');
    temporary = Directory(await temporary.resolveSymbolicLinks());
  });
  tearDown(() async => temporary.delete(recursive: true));

  test(
    'worker preserves Unicode, hidden names, zero sizes and empty folders',
    () async {
      await File(p.join(temporary.path, '雪.txt')).writeAsBytes([1, 2, 3]);
      await File(p.join(temporary.path, '.hidden')).writeAsBytes([4]);
      await File(p.join(temporary.path, 'zero.bin')).create();
      await Directory(p.join(temporary.path, 'empty')).create();

      final result = await readNativeStorageScanDirectory(temporary.path);
      final items = {for (final item in result.entries) item.name: item};
      expect(result.isComplete, isTrue);
      expect(result.issues, isEmpty);
      expect(
        items.keys,
        unorderedEquals(['雪.txt', '.hidden', 'zero.bin', 'empty']),
      );
      expect(items['雪.txt']!.size, 3);
      expect(items['.hidden']!.size, 1);
      expect(items['zero.bin']!.size, 0);
      expect(items['empty']!.isFolder, isTrue);
      expect(items['empty']!.size, isNull);
      expect(items.values.every((item) => item.updatedAt != null), isTrue);
      expect(await File(p.join(temporary.path, '雪.txt')).readAsBytes(), [
        1,
        2,
        3,
      ]);
    },
  );

  test(
    'worker identifies broken, file and cycle links without following them',
    () async {
      final target = File(p.join(temporary.path, 'target.bin'));
      await target.writeAsBytes(List.filled(13, 1));
      await Link(p.join(temporary.path, 'file-link')).create(target.path);
      await Link(p.join(temporary.path, 'cycle')).create(temporary.path);
      await Link(p.join(temporary.path, 'broken'))
          .create(p.join(temporary.path, 'absent'));

      final result = await readNativeStorageScanDirectory(temporary.path);
      expect(result.isComplete, isTrue);
      final links = result.entries.where((item) => item.isSymlink == true);
      expect(
        links.map((item) => item.name),
        unorderedEquals(['file-link', 'cycle', 'broken']),
      );
      expect(
        links.every((item) => item.size == null && !item.isFolder),
        isTrue,
      );
      expect(
        result.entries.where((item) => item.isSymlink != true).single.size,
        13,
      );
    },
    skip: Platform.isWindows
        ? 'Link creation may need Windows developer mode.'
        : false,
  );

  test('worker refuses a symbolic-link root or missing directory', () async {
    await expectLater(
      readNativeStorageScanDirectory(p.join(temporary.path, 'missing')),
      throwsA(isA<FileSystemException>()),
    );
    if (!Platform.isWindows) {
      final link = Link(p.join(temporary.path, 'root-link'));
      await link.create(temporary.path);
      await expectLater(
        readNativeStorageScanDirectory(link.path),
        throwsA(isA<FileSystemException>()),
      );
    }
  });
}
