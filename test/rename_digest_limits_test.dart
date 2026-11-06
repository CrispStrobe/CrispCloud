import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/rename_batch_digest_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('rename-digest-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test(
    'streamed directory encoding remains compatible after a rename',
    () async {
      final folder = await Directory(p.join(root.path, 'before')).create();
      final child = await Directory(p.join(folder.path, 'nested')).create();
      await File(p.join(folder.path, 'ä "one"')).writeAsString('first');
      await File(p.join(folder.path, 'z')).writeAsString('last');
      await File(p.join(child.path, 'part')).writeAsString('nested');
      final legacy = await _legacy(folder.path);
      expect(await nativeRenameDigest(folder.path, () {}), legacy);
      final renamed = await folder.rename(p.join(root.path, 'after'));
      expect(await nativeRenameDigest(renamed.path, () {}), legacy);
    },
  );

  test(
    'enumeration entry budget is shared across nested directories',
    () async {
      for (final name in ['left', 'right']) {
        final dir = await Directory(p.join(root.path, name)).create();
        await File(p.join(dir.path, 'part')).writeAsString('data');
      }
      await expectLater(
        nativeRenameDigest(root.path, () {}, maxEntries: 4),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            contains('enumeration limit'),
          ),
        ),
      );
      expect(
        await nativeRenameDigest(root.path, () {}, maxEntries: 5),
        isNotNull,
      );
    },
  );

  test('depth and retained path bytes have independent bounds', () async {
    final child = await Directory(p.join(root.path, 'nested')).create();
    await File(p.join(child.path, 'part')).writeAsString('data');
    await expectLater(
      nativeRenameDigest(root.path, () {}, maxDepth: 1),
      throwsA(
        isA<FileSystemException>().having(
          (e) => e.message,
          'message',
          contains('depth limit'),
        ),
      ),
    );
    await expectLater(
      nativeRenameDigest(root.path, () {}, maxListedPathBytes: 1),
      throwsA(
        isA<FileSystemException>().having(
          (e) => e.message,
          'message',
          contains('enumeration limit'),
        ),
      ),
    );
  });

  test(
    'cancellation interrupts enumeration before consuming the directory',
    () async {
      for (var i = 0; i < 30; i++) {
        await File(p.join(root.path, '$i')).writeAsString('data');
      }
      var checks = 0;
      await expectLater(
        nativeRenameDigest(root.path, () {
          if (++checks == 7) throw StateError('cancelled');
        }),
        throwsStateError,
      );
      expect(checks, 7);
      expect(await root.list().length, 30);
    },
  );

  test('symlink targets are fingerprinted without traversing them', () async {
    final outside = await Directory(p.join(root.path, 'outside')).create();
    final folder = await Directory(p.join(root.path, 'folder')).create();
    final target = await File(p.join(outside.path, 'target'))
        .writeAsString('one');
    await Link(p.join(folder.path, 'link')).create(outside.path);
    final before = await nativeRenameDigest(folder.path, () {}, maxEntries: 2);
    await target.writeAsString('changed');
    expect(await nativeRenameDigest(folder.path, () {}, maxEntries: 2), before);
  }, skip: Platform.isWindows);
}

Future<String> _legacy(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.file) {
    return sha256.convert(await File(path).readAsBytes()).toString();
  }
  final entries = await Directory(path).list(followLinks: false).toList();
  entries.sort((a, b) => a.path.compareTo(b.path));
  return sha256
      .convert(
        utf8.encode(
          jsonEncode([
            for (final entry in entries)
              [p.basename(entry.path), await _legacy(entry.path)],
          ]),
        ),
      )
      .toString();
}
