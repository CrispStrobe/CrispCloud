// test/local_file_walk_test.dart
//
// Tests for the flat-view recursive walk.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/local_file_service.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('walk_test_');
    await Directory('${dir.path}/sub/deep').create(recursive: true);
    await File('${dir.path}/a.txt').writeAsString('a');
    await File('${dir.path}/sub/b.txt').writeAsString('bb');
    await File('${dir.path}/sub/deep/c.txt').writeAsString('ccc');
    await File('${dir.path}/.hidden').writeAsString('hidden');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('walks subdirectories and skips hidden files', () async {
    final files = await walkLocalFiles(dir.path);
    final names = files.map((f) => f.name).toSet();

    expect(names, containsAll(<String>['a.txt', 'b.txt', 'c.txt']));
    expect(names, isNot(contains('.hidden')));
    expect(files.every((f) => !f.isFolder), isTrue);
    expect(files.firstWhere((f) => f.name == 'b.txt').size, 2);
  });

  test('includes hidden files when requested', () async {
    final files = await walkLocalFiles(dir.path, includeHidden: true);
    expect(files.map((f) => f.name), contains('.hidden'));
  });

  test('respects maxItems', () async {
    final files = await walkLocalFiles(dir.path, maxItems: 1);
    expect(files.length, 1);
  });
}
