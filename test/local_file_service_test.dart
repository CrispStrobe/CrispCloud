import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/local_file_service_native.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LocalFileService', () {
    test('factory constructor does not throw', () {
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

    test('DesktopFileService has access to every path', () async {
      final service = DesktopFileService();
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

    test('DesktopFileService has no granted base path', () {
      final service = DesktopFileService();
      // DesktopFileService.grantedBasePath always returns null
      expect(service.grantedBasePath, isNull);
    });
  });

  group('DesktopFileService', () {
    test('factory returns the implementation for the host platform', () {
      final service = LocalFileService();
      if (Platform.isMacOS) {
        expect(service, isA<MacosFileService>());
      } else if (Platform.isLinux || Platform.isWindows) {
        expect(service, isA<DesktopFileService>());
      } else if (Platform.isAndroid || Platform.isIOS) {
        expect(service, isA<MobileFileService>());
      }
    });

    test('readFile throws for non-existent file', () async {
      final service = DesktopFileService();
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
      final service = DesktopFileService();
      final testPath =
          '/tmp/crisp_cloud_test_${DateTime.now().millisecondsSinceEpoch}.txt';
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
