// test/link_service_test.dart
//
// Tests for symlink/hardlink creation (Phase 4.3).

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/services/link_service.dart';

void main() {
  group('LinkService', () {
    late String tempDir;

    setUp(() async {
      tempDir = (await Directory.systemTemp.createTemp('link_test_')).path;
    });

    tearDown(() async {
      await Directory(tempDir).delete(recursive: true);
    });

    test('createSymlink creates a working symlink', () async {
      final targetPath = p.join(tempDir, 'target.txt');
      await File(targetPath).writeAsString('hello');

      final linkPath = p.join(tempDir, 'link.txt');
      await LinkService.createSymlink(targetPath, linkPath);

      expect(await File(linkPath).exists(), isTrue);
      expect(await File(linkPath).readAsString(), 'hello');

      // Verify it's actually a symlink
      final type = await FileSystemEntity.type(linkPath, followLinks: false);
      expect(type, FileSystemEntityType.link);
    });

    test('isSymlink detects symlinks correctly', () async {
      final targetPath = p.join(tempDir, 'real.txt');
      await File(targetPath).writeAsString('data');

      final linkPath = p.join(tempDir, 'sym.txt');
      await Link(linkPath).create(targetPath);

      expect(await LinkService.isSymlink(linkPath), isTrue);
      expect(await LinkService.isSymlink(targetPath), isFalse);
    });

    test('symlinkTarget returns the target path', () async {
      final targetPath = p.join(tempDir, 'target.txt');
      await File(targetPath).writeAsString('data');

      final linkPath = p.join(tempDir, 'link.txt');
      await Link(linkPath).create(targetPath);

      final target = await LinkService.symlinkTarget(linkPath);
      expect(target, targetPath);
    });

    test('symlinkTarget returns null for regular files', () async {
      final filePath = p.join(tempDir, 'regular.txt');
      await File(filePath).writeAsString('data');

      final target = await LinkService.symlinkTarget(filePath);
      expect(target, isNull);
    });
  }, skip: Platform.isWindows ? 'Symlinks require elevation on Windows' : null);
}
