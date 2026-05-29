import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/local_file_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LocalFileService', () {
    test('factory constructor does not throw', () {
      // On Linux (test runner), this should return a DesktopFileService
      expect(() => LocalFileService(), returnsNormally);
    });

    test('factory returns a LocalFileService implementation', () {
      final service = LocalFileService();
      expect(service, isA<LocalFileService>());
    });

    test('currentPath is set to a non-empty string after construction', () {
      final service = LocalFileService();
      expect(service.currentPath, isNotEmpty);
    });

    test('currentPath can be reassigned', () {
      final service = LocalFileService();
      service.currentPath = '/tmp/test_dir';
      expect(service.currentPath, equals('/tmp/test_dir'));
    });

    test('getWebMetadata returns empty map by default', () {
      final service = LocalFileService();
      final meta = service.getWebMetadata('/some/path');
      expect(meta, isEmpty);
    });

    test('refresh completes without error', () async {
      final service = LocalFileService();
      // refresh() is a no-op on native platforms
      await expectLater(service.refresh(), completes);
    });

    test('hasAccessToPath returns true on desktop', () async {
      final service = LocalFileService();
      // DesktopFileService always returns true for hasAccessToPath
      final hasAccess = await service.hasAccessToPath('/tmp');
      expect(hasAccess, isTrue);
    });

    test('getSafeFallbackDirectory returns a non-empty path', () async {
      final service = LocalFileService();
      final fallback = await service.getSafeFallbackDirectory();
      expect(fallback, isNotEmpty);
    });

    test('getInitialPath returns a non-empty path', () async {
      final service = LocalFileService();
      final path = await service.getInitialPath();
      expect(path, isNotEmpty);
    });

    test('listDirectory returns list for valid path', () async {
      final service = LocalFileService();
      // /tmp should exist on Linux
      final entities = await service.listDirectory('/tmp');
      expect(entities, isNotNull);
      expect(entities, isA<List>());
    });

    test('grantedBasePath is null on desktop', () {
      final service = LocalFileService();
      // DesktopFileService.grantedBasePath always returns null
      expect(service.grantedBasePath, isNull);
    });
  });

  group('DesktopFileService', () {
    test('is returned by factory on Linux', () {
      final service = LocalFileService();
      expect(service, isA<DesktopFileService>());
    });

    test('readFile throws for non-existent file', () async {
      final service = LocalFileService();
      expect(
        () => service.readFile('/non/existent/path/file.txt'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains(''),
        )),
      );
    });

    test('saveFile creates file at given path', () async {
      final service = LocalFileService();
      final testPath = '/tmp/crisp_cloud_test_${DateTime.now().millisecondsSinceEpoch}.txt';
      final data = [72, 101, 108, 108, 111]; // "Hello"

      await service.saveFile(testPath, Uint8List.fromList(data));

      // Verify we can read it back
      final readBack = await service.readFile(testPath);
      expect(readBack, equals(data));

      // Clean up
      try {
        await File(testPath).delete();
      } catch (_) {}
    });
  });
}
