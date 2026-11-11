import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/local_file_service_native.dart';
import 'package:crisp_cloud/services/local_file_service_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _LegacyFiles extends Fake implements LocalFileService {
  int interactiveReads = 0;
  int accessRequests = 0;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    interactiveReads++;
    return [];
  }

  @override
  Future<bool> ensureAccess(String path) async {
    accessRequests++;
    return true;
  }
}

class _Bookmarks implements SecureBookmarks {
  _Bookmarks(this.root);
  final Directory root;
  bool allowStart = true;
  int active = 0;
  final starts = <String>[];
  final stops = <String>[];

  @override
  Future<FileSystemEntity> resolveBookmark(
    String bookmark, {
    bool isDirectory = false,
  }) async => root;

  @override
  Future<bool> startAccessingSecurityScopedResource(
    FileSystemEntity entity,
  ) async {
    starts.add(entity.path);
    if (!allowStart) return false;
    active++;
    return true;
  }

  @override
  Future<bool> stopAccessingSecurityScopedResource(
    FileSystemEntity entity,
  ) async {
    stops.add(entity.path);
    active--;
    return true;
  }

  @override
  Future<String> bookmark(FileSystemEntity entity) =>
      throw StateError('A snapshot must never create a grant.');
}

class _NoPickerMac extends MacosFileService {
  _NoPickerMac({super.bookmarks, super.resolveBookmarks});
  int prompts = 0;

  @override
  Future<bool> ensureAccess(String path) async {
    prompts++;
    throw StateError('A snapshot must not enter the interactive access flow.');
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    prompts++;
    throw StateError('A snapshot must never request a directory.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final temporary = await Directory.systemTemp.createTemp('crisp-snapshot-');
    root = Directory(await temporary.resolveSymbolicLinks());
    await File(p.join(root.path, 'file.txt')).writeAsString('readable');
    await Directory(p.join(root.path, 'folder')).create();
  });

  tearDown(() => root.delete(recursive: true));

  test(
    'legacy services fail closed without interactive listing or access',
    () async {
      final legacy = _LegacyFiles();
      final LocalFileService service = legacy;
      await expectLater(
        service.listDirectorySnapshot(root.path),
        throwsA(isA<UnsupportedError>()),
      );
      expect(legacy.interactiveReads, 0);
      expect(legacy.accessRequests, 0);
    },
  );

  for (final platform in ['desktop', 'macos', 'mobile']) {
    test(
      '$platform snapshot preserves navigation and child entry kinds',
      () async {
        final LocalFileService service = switch (platform) {
          'desktop' => DesktopFileService(),
          'macos' => _NoPickerMac(resolveBookmarks: () async => []),
          _ => MobileFileService(isIOS: false),
        };
        service.currentPath = p.join(root.path, 'visible');
        final beforeGrant = service.grantedBasePath;
        final entities = (await service.listDirectorySnapshot(root.path))!;
        expect(
          entities.map((entry) => p.basename(entry.path)),
          unorderedEquals(['file.txt', 'folder']),
        );
        expect(
          entities.singleWhere((entry) => p.basename(entry.path) == 'file.txt'),
          isA<File>(),
        );
        expect(
          entities.singleWhere((entry) => p.basename(entry.path) == 'folder'),
          isA<Directory>(),
        );
        expect(service.currentPath, p.join(root.path, 'visible'));
        expect(service.grantedBasePath, beforeGrant);
        expect(() => entities.clear(), throwsUnsupportedError);
        await expectLater(
          service.listDirectorySnapshot(p.join(root.path, 'missing')),
          throwsA(isA<FileSystemException>()),
        );
        expect(service.currentPath, p.join(root.path, 'visible'));
        expect(service.grantedBasePath, beforeGrant);
        await expectLater(
          service.listDirectorySnapshot('relative-folder'),
          throwsA(isA<FileSystemException>()),
        );
        // Ordinary interactive listing keeps its original navigation behavior.
        await service.listDirectory(root.path);
        expect(service.currentPath, root.path);
        if (service is _NoPickerMac) expect(service.prompts, 0);
      },
    );

    test('$platform snapshot keeps child symbolic links as links', () async {
      final link = await Link(p.join(root.path, 'link'))
          .create(p.join(root.path, 'folder'));
      final LocalFileService service = switch (platform) {
        'desktop' => DesktopFileService(),
        'macos' => _NoPickerMac(resolveBookmarks: () async => []),
        _ => MobileFileService(isIOS: false),
      };
      final entities = (await service.listDirectorySnapshot(root.path))!;
      expect(
        entities.singleWhere((entry) => entry.path == link.path),
        isA<Link>(),
      );
    }, skip: Platform.isWindows);
  }

  test(
    'a late macOS snapshot never restores or replaces newer navigation',
    () async {
      final bookmarks = _Bookmarks(root);
      final pending = Completer<List<FileSystemEntity>>();
      final service = _NoPickerMac(
        bookmarks: bookmarks,
        resolveBookmarks: () => pending.future,
      )..currentPath = p.join(root.path, 'original');
      final snapshot = service.listDirectorySnapshot(root.path);
      expect(service.currentPath, p.join(root.path, 'original'));
      service.currentPath = p.join(root.path, 'newer');
      pending.complete([root]);
      expect(await snapshot, hasLength(2));
      expect(service.currentPath, p.join(root.path, 'newer'));
      expect(service.grantedBasePath, isNull);
      expect(service.prompts, 0);
      expect(bookmarks.starts, [root.path]);
      expect(bookmarks.stops, [root.path]);
      expect(bookmarks.active, 0);
    },
  );

  test(
    'macOS snapshot rejects a refused scope without unscoped retry',
    () async {
      final bookmarks = _Bookmarks(root)..allowStart = false;
      final service = _NoPickerMac(
        bookmarks: bookmarks,
        resolveBookmarks: () async => [root],
      )..currentPath = p.join(root.path, 'visible');
      await expectLater(
        service.listDirectorySnapshot(root.path),
        throwsA(isA<PathAccessException>()),
      );
      expect(service.currentPath, p.join(root.path, 'visible'));
      expect(service.grantedBasePath, isNull);
      expect(service.prompts, 0);
      expect(bookmarks.starts, [root.path]);
      expect(bookmarks.stops, isEmpty);
      expect(bookmarks.active, 0);
    },
  );

  test(
    'macOS concurrent and failed snapshots release only their own scopes',
    () async {
      final bookmarks = _Bookmarks(root);
      final service = _NoPickerMac(
        bookmarks: bookmarks,
        resolveBookmarks: () async => [root],
      )..currentPath = p.join(root.path, 'visible');
      await Future.wait([
        service.listDirectorySnapshot(root.path),
        service.listDirectorySnapshot(p.join(root.path, 'folder')),
      ]);
      await expectLater(
        service.listDirectorySnapshot(p.join(root.path, 'missing')),
        throwsA(isA<FileSystemException>()),
      );
      expect(bookmarks.starts, List.filled(3, root.path));
      expect(bookmarks.stops, List.filled(3, root.path));
      expect(bookmarks.active, 0);
      expect(service.currentPath, p.join(root.path, 'visible'));
      expect(service.grantedBasePath, isNull);
      expect(service.prompts, 0);
    },
  );

  test(
    'mobile snapshot resolves saved access without selecting the grant',
    () async {
      SharedPreferences.setMockInitialValues({'mobile_bookmark_data': 'saved'});
      final bookmarks = _Bookmarks(root);
      final service = MobileFileService(isIOS: false, bookmarks: bookmarks)
        ..currentPath = p.join(root.path, 'visible');
      expect(await service.listDirectorySnapshot(root.path), hasLength(2));
      expect(service.currentPath, p.join(root.path, 'visible'));
      expect(service.grantedBasePath, isNull);
      expect(bookmarks.starts, [root.path]);
      expect(bookmarks.stops, [root.path]);
      expect(bookmarks.active, 0);
      bookmarks.allowStart = false;
      await expectLater(
        service.listDirectorySnapshot(root.path),
        throwsA(isA<PathAccessException>()),
      );
      expect(bookmarks.stops, [root.path]);
      expect(service.currentPath, p.join(root.path, 'visible'));
      expect(service.grantedBasePath, isNull);
    },
  );

  test('browser snapshots reject ungranted paths without navigating', () async {
    final service = WebFileService.instance;
    final previous = service.currentPath;
    addTearDown(() => service.currentPath = previous);
    service.currentPath = '/selected-browser-folder';
    await expectLater(
      service.listDirectorySnapshot('/ungranted-browser-folder'),
      throwsA(isA<PathAccessException>()),
    );
    expect(service.currentPath, '/selected-browser-folder');
    expect(service.grantedBasePath, isNull);
    expect(await service.hasAccessToPath('/ungranted-browser-folder'), isFalse);
    final roots = (await service.listDirectorySnapshot('/'))!;
    expect(() => roots.clear(), throwsUnsupportedError);
    expect(service.currentPath, '/selected-browser-folder');
  });
}
