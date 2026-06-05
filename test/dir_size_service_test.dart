// test/dir_size_service_test.dart
//
// Tests for directory size calculation service (Phase 4.4).

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/services/dir_size_service.dart';

void main() {
  group('DirSizeService', () {
    late String tempDir;
    late DirSizeService service;

    setUp(() async {
      tempDir = (await Directory.systemTemp.createTemp('dirsize_test_')).path;
      service = DirSizeService();
    });

    tearDown(() async {
      await Directory(tempDir).delete(recursive: true);
    });

    test('calculates correct size for flat directory', () async {
      await File(p.join(tempDir, 'a.txt')).writeAsBytes(Uint8List(100));
      await File(p.join(tempDir, 'b.txt')).writeAsBytes(Uint8List(200));

      final size = await service.calculateSize(tempDir);
      expect(size, 300);
    });

    test('calculates size recursively', () async {
      final subDir = p.join(tempDir, 'sub');
      await Directory(subDir).create();
      await File(p.join(tempDir, 'root.txt')).writeAsBytes(Uint8List(50));
      await File(p.join(subDir, 'nested.txt')).writeAsBytes(Uint8List(75));

      final size = await service.calculateSize(tempDir);
      expect(size, 125);
    });

    test('returns 0 for empty directory', () async {
      final emptyDir = p.join(tempDir, 'empty');
      await Directory(emptyDir).create();

      final size = await service.calculateSize(emptyDir);
      expect(size, 0);
    });

    test('returns 0 for non-existent directory', () async {
      final size = await service.calculateSize(p.join(tempDir, 'nope'));
      expect(size, 0);
    });

    test('caches results', () async {
      await File(p.join(tempDir, 'file.txt')).writeAsBytes(Uint8List(100));

      final size1 = await service.calculateSize(tempDir);
      // Add more data — should still return cached value
      await File(p.join(tempDir, 'extra.txt')).writeAsBytes(Uint8List(500));
      final size2 = await service.calculateSize(tempDir);

      expect(size1, size2); // cached, should be the same
    });

    test('invalidate clears cache', () async {
      await File(p.join(tempDir, 'file.txt')).writeAsBytes(Uint8List(100));

      final size1 = await service.calculateSize(tempDir);
      expect(size1, 100);

      await File(p.join(tempDir, 'extra.txt')).writeAsBytes(Uint8List(200));
      service.invalidate(tempDir);
      final size2 = await service.calculateSize(tempDir);
      expect(size2, 300);
    });

    test('getCachedSize returns null before calculation', () {
      expect(service.getCachedSize(tempDir), isNull);
    });

    test('getCachedSize returns value after calculation', () async {
      await File(p.join(tempDir, 'f.txt')).writeAsBytes(Uint8List(50));
      await service.calculateSize(tempDir);
      expect(service.getCachedSize(tempDir), 50);
    });

    test('invalidateAll clears all entries', () async {
      await File(p.join(tempDir, 'f.txt')).writeAsBytes(Uint8List(50));
      await service.calculateSize(tempDir);
      service.invalidateAll();
      expect(service.getCachedSize(tempDir), isNull);
    });
  });
}
