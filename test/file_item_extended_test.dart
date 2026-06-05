// test/file_item_extended_test.dart
//
// Tests for FileItem model extensions (Phase 2.1).

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/models/file_item.dart';

void main() {
  group('FileItem extensions', () {
    test('extension getter returns lowercase extension', () {
      final item = FileItem(name: 'File.DART', isFolder: false);
      expect(item.extension, 'dart');
    });

    test('extension getter returns empty for folders', () {
      final item = FileItem(name: 'src', isFolder: true);
      expect(item.extension, '');
    });

    test('extension getter returns empty for files without extension', () {
      final item = FileItem(name: 'Makefile', isFolder: false);
      expect(item.extension, '');
    });

    test('displaySize prefers calculatedSize over size', () {
      final item = FileItem(name: 'dir', isFolder: true, size: 0, calculatedSize: 1000);
      expect(item.displaySize, 1000);
    });

    test('displaySize falls back to size when no calculatedSize', () {
      final item = FileItem(name: 'file.txt', isFolder: false, size: 500);
      expect(item.displaySize, 500);
    });

    test('copyWith preserves unmodified fields', () {
      final original = FileItem(
        name: 'test.txt',
        path: '/tmp/test.txt',
        uuid: 'abc',
        isFolder: false,
        size: 100,
        updatedAt: DateTime(2024),
        metadata: {'key': 'value'},
        isSymlink: true,
        symlinkTarget: '/tmp/target',
        calculatedSize: null,
      );

      final copy = original.copyWith(calculatedSize: 5000);
      expect(copy.name, 'test.txt');
      expect(copy.path, '/tmp/test.txt');
      expect(copy.uuid, 'abc');
      expect(copy.isFolder, false);
      expect(copy.size, 100);
      expect(copy.isSymlink, true);
      expect(copy.symlinkTarget, '/tmp/target');
      expect(copy.calculatedSize, 5000);
      expect(copy.metadata, {'key': 'value'});
    });

    test('copyWith can override name', () {
      final original = FileItem(name: 'old.txt', isFolder: false);
      final copy = original.copyWith(name: 'new.txt');
      expect(copy.name, 'new.txt');
    });

    test('metadata field is nullable and optional', () {
      final item = FileItem(name: 'test', isFolder: false);
      expect(item.metadata, isNull);

      final withMeta = FileItem(name: 'test', isFolder: false, metadata: {'a': 1});
      expect(withMeta.metadata, {'a': 1});
    });

    test('isSymlink defaults to null', () {
      final item = FileItem(name: 'test', isFolder: false);
      expect(item.isSymlink, isNull);
    });

    test('sizeFormatted uses displaySize', () {
      final item = FileItem(name: 'dir', isFolder: true, calculatedSize: 1536);
      expect(item.sizeFormatted, '1.5 KB');
    });

    test('equality still based on uuid or path', () {
      final a = FileItem(name: 'a.txt', isFolder: false, uuid: 'x', size: 100);
      final b = FileItem(name: 'b.txt', isFolder: false, uuid: 'x', size: 200);
      expect(a, equals(b)); // same uuid

      final c = FileItem(name: 'c.txt', isFolder: false, path: '/p');
      final d = FileItem(name: 'd.txt', isFolder: false, path: '/p');
      expect(c, equals(d)); // same path
    });
  });
}
