import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/models/file_item.dart';

void main() {
  group('FileItem', () {
    test('creates with required fields', () {
      final item = FileItem(
        name: 'test.txt',
        path: '/docs/test.txt',
        isDirectory: false,
        size: 1024,
      );

      expect(item.name, equals('test.txt'));
      expect(item.path, equals('/docs/test.txt'));
      expect(item.isDirectory, isFalse);
      expect(item.size, equals(1024));
    });

    test('creates directory', () {
      final dir = FileItem(
        name: 'docs',
        path: '/docs',
        isDirectory: true,
        size: 0,
      );

      expect(dir.isDirectory, isTrue);
    });

    test('sizeFormatted returns readable format', () {
      final item = FileItem(
        name: 'file.bin',
        path: '/file.bin',
        isDirectory: false,
        size: 1048576, // 1 MB
      );

      final formatted = item.sizeFormatted;
      expect(formatted, contains('MB'));
    });

    test('equality by path', () {
      final a = FileItem(name: 'a.txt', path: '/a.txt', isDirectory: false, size: 0);
      final b = FileItem(name: 'a.txt', path: '/a.txt', isDirectory: false, size: 0);
      final c = FileItem(name: 'c.txt', path: '/c.txt', isDirectory: false, size: 0);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
