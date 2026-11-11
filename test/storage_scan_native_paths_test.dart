import 'dart:io';

import 'package:crisp_cloud/models/storage_analysis.dart';
import 'package:crisp_cloud/services/storage_scan_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  final files = <String, int>{
    'plain.txt': 3,
    '.hidden': 0,
    '..leading': 2,
    'many..dots.txt': 4,
    '雪-😀.txt': 5,
    'space name.txt': 1,
    if (!Platform.isWindows) ...{
      r'back\slash.txt': 6,
      r'..\literal': 7,
      'trailing.': 8,
      ' leading and trailing ': 9,
      'file:name': 10,
    },
  };
  final folders = <String>[
    'folder.with.dots',
    '.hidden-folder',
    '子目录',
    if (!Platform.isWindows) r'back\slash-folder',
  ];

  setUp(() async {
    final temporary = await Directory.systemTemp.createTemp('scan-paths-');
    root = Directory(await temporary.resolveSymbolicLinks());
    for (final file in files.entries) {
      await File(p.join(root.path, file.key))
          .writeAsBytes(List<int>.filled(file.value, file.value));
    }
    for (final folder in folders) {
      await Directory(p.join(root.path, folder)).create();
    }
  });

  tearDown(() => root.delete(recursive: true));

  Future<void> verify(
    Future<StorageScanDirectory> Function(String) read,
    String input,
    String expectedParent,
  ) async {
    final result = await read(input);
    expect(result.isComplete, isTrue, reason: result.issues.toString());
    expect(result.issues, isEmpty);
    expect(
      result.entries.map((item) => item.name),
      unorderedEquals([...files.keys, ...folders]),
    );
    for (final item in result.entries) {
      final expected = await FileStat.stat(p.join(root.path, item.name));
      expect(item.path, p.join(expectedParent, item.name));
      expect(item.isFolder, folders.contains(item.name));
      expect(item.isSymlink, isFalse);
      expect(item.size, files[item.name]);
      expect(item.updatedAt, expected.modified);
    }
  }

  for (final persistent in [false, true]) {
    final mode = persistent ? 'persistent' : 'one-off';
    test('$mode reader retains native names and exact metadata', () async {
      final worker = persistent ? await NativeStorageScanWorker.start() : null;
      final read = worker?.readDirectory ?? readNativeStorageScanDirectory;
      try {
        await verify(read, root.path, root.path);
      } finally {
        await worker?.close();
      }
    });

    test('$mode reader preserves normalization fallback paths', () async {
      final worker = persistent ? await NativeStorageScanWorker.start() : null;
      final read = worker?.readDirectory ?? readNativeStorageScanDirectory;
      final separator = p.separator;
      final relative = p.relative(root.path, from: Directory.current.path);
      final aliases = <(String, String)>[
        ('${root.path}$separator', root.path),
        ('${root.path}$separator.$separator', root.path),
        ('${root.path}${separator}folder.with.dots$separator..', root.path),
        ('${root.path}$separator$separator', root.path),
        (relative, relative),
        if (Platform.isWindows) (root.path.replaceAll(r'\', '/'), root.path),
        if (!Platform.isWindows) ('/${root.path}', root.path),
      ];
      try {
        for (final (input, expectedParent) in aliases) {
          await verify(read, input, expectedParent);
        }
      } finally {
        await worker?.close();
      }
    });
  }

  test(
    'canonical and fallback paths preserve links without target metadata',
    () async {
      final targets = <String, String>{
        '雪-link': p.join(root.path, 'plain.txt'),
        r'back\link': p.join(root.path, 'folder.with.dots'),
        '.broken-link': p.join(root.path, 'absent'),
      };
      for (final target in targets.entries) {
        await Link(p.join(root.path, target.key)).create(target.value);
      }
      final worker = await NativeStorageScanWorker.start();
      try {
        for (final input in [root.path, '${root.path}/./']) {
          final result = await worker.readDirectory(input);
          expect(result.isComplete, isTrue);
          expect(result.issues, isEmpty);
          final links = result.entries.where((item) => item.isSymlink == true);
          expect(links.map((item) => item.name), unorderedEquals(targets.keys));
          for (final link in links) {
            expect(link.path, p.join(root.path, link.name));
            expect(link.size, isNull);
            expect(link.updatedAt, isNull);
            expect(link.isFolder, isFalse);
          }
        }
      } finally {
        await worker.close();
      }
    },
    skip: Platform.isWindows
        ? 'Link creation may need Windows developer mode.'
        : false,
  );
}
