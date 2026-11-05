import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/models/file_item.dart';

void main() {
  group('FileItem', () {
    test(
      'equal paths and object IDs from different accounts remain distinct',
      () {
        final a = FileItem(
          name: 'a',
          path: '/a',
          uuid: 'same-id',
          storageId: 'account-a',
          isFolder: false,
        );
        final b = a.copyWith(storageId: 'account-b');
        expect({a, b}.length, 2);
        expect(a.copyWith(name: 'renamed').storageId, 'account-a');
        expect(a, a.copyWith());
      },
    );

    test('rows without identity do not collapse and equality is symmetric', () {
      final a = FileItem(name: 'a', isFolder: false);
      final b = FileItem(name: 'b', isFolder: false);
      expect({a, b}.length, 2);
      final pathOnly = a.copyWith(path: '/a');
      final identified = pathOnly.copyWith(uuid: 'id');
      expect(pathOnly == identified, isFalse);
      expect(identified == pathOnly, isFalse);
    });
    test('creates with required fields', () {
      final item = FileItem(
        name: 'test.txt',
        path: '/docs/test.txt',
        isFolder: false,
        size: 1024,
      );

      expect(item.name, equals('test.txt'));
      expect(item.path, equals('/docs/test.txt'));
      expect(item.isFolder, isFalse);
      expect(item.size, equals(1024));
    });

    test('creates directory', () {
      final dir = FileItem(
        name: 'docs',
        path: '/docs',
        isFolder: true,
        size: 0,
      );

      expect(dir.isFolder, isTrue);
    });

    test('sizeFormatted returns readable format', () {
      final item = FileItem(
        name: 'file.bin',
        path: '/file.bin',
        isFolder: false,
        size: 1048576, // 1 MB
      );

      final formatted = item.sizeFormatted;
      expect(formatted, contains('MB'));
    });

    test('equality by path', () {
      final a = FileItem(
        name: 'a.txt',
        path: '/a.txt',
        isFolder: false,
        size: 0,
      );
      final b = FileItem(
        name: 'a.txt',
        path: '/a.txt',
        isFolder: false,
        size: 0,
      );
      final c = FileItem(
        name: 'c.txt',
        path: '/c.txt',
        isFolder: false,
        size: 0,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
