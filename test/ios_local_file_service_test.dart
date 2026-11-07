import 'dart:async';
import 'dart:io';

import 'package:crisp_ios_files/crisp_ios_files.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/ios_file_listing.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/local_file_service_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('crisp_ios_files');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MobileFileService service;
  late List<MethodCall> calls;
  late Set<String> active;
  var counter = 0;
  String? restored;
  String? selected;
  String? failMethod;
  String failureCode = 'access_denied';
  bool accessAllowed = true;
  Future<void> Function(MethodCall)? intercept;

  Map<String, Object> entry(String path, String kind) => {
    'path': path,
    'kind': kind,
    'size': 123,
    'modifiedMs': 1700000000000,
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    active = {};
    counter = 0;
    restored = '/provider/folder';
    selected = '/provider/new';
    failMethod = null;
    failureCode = 'access_denied';
    accessAllowed = true;
    intercept = null;
    service = MobileFileService(
      isIOS: true,
      documentsDirectory: () async => Directory('/sandbox/Documents'),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      await intercept?.call(call);
      if (call.method == failMethod) {
        throw PlatformException(
          code: failureCode,
          message: 'Selected folder unavailable',
        );
      }
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'restoreLastDirectory':
          return restored;
        case 'pickDirectory':
          return selected;
        case 'hasAccess':
          return accessAllowed;
        case 'acquireAccess':
          final token = 'scope-${++counter}';
          active.add(token);
          return {'token': token, 'path': args!['path']};
        case 'releaseAccess':
          active.remove(args!['token']);
          return null;
        case 'listDirectory':
          return [
            entry('/provider/folder/file.txt', 'file'),
            entry('/provider/folder/dir', 'directory'),
            entry('/provider/folder/link', 'link'),
          ];
        case 'walkFiles':
          return [entry('/provider/folder/sub/file.txt', 'file')];
        case 'readFile':
          return Uint8List.fromList([1, 2, 3]);
        case 'fileLength':
          return 3;
        default:
          return null;
      }
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'restores durable refreshed selection and exposes native-only defaults',
    () async {
      expect(service, isA<ScopedLocalFileOperations>());
      expect(service.currentPath, '/');
      expect(service.grantedBasePath, isNull);
      expect(await service.getInitialPath(), '/provider/folder');
      expect(service.currentPath, '/provider/folder');
      expect(service.grantedBasePath, '/provider/folder');
      expect(service.getWebMetadata('/a'), isEmpty);
      expect(service.getWebFileRef('/a'), isNull);
      await service.refresh();
      expect(calls.map((c) => c.method), ['restoreLastDirectory']);
    },
  );

  test(
    'missing revoked corrupt or moved-away grants fall back to app documents',
    () async {
      restored = null;
      expect(await service.getInitialPath(), '/sandbox/Documents');
      expect(service.grantedBasePath, '/sandbox/Documents');
      failMethod = 'restoreLastDirectory';
      expect(await service.getInitialPath(), '/sandbox/Documents');
      failureCode = 'file_error';
      expect(await service.getInitialPath(), '/sandbox/Documents');
      expect(await service.getSafeFallbackDirectory(), '/sandbox/Documents');
      failMethod = null;
      restored = '/provider/renamed';
      expect(await service.getInitialPath(), '/provider/renamed');
    },
  );

  test('picker commits new path only on success; cancel and failure preserve previous', () async {
    await service.getInitialPath();
    selected = null;
    expect(
      await service.requestDirectoryAccess(
        initialDirectory: '/provider/folder',
      ),
      isNull,
    );
    expect(service.currentPath, '/provider/folder');
    expect(service.grantedBasePath, '/provider/folder');
    expect(calls.last.arguments, {'initialDirectory': '/provider/folder'});
    failMethod = 'pickDirectory';
    await expectLater(
      service.requestDirectoryAccess(),
      throwsA(isA<PlatformException>()),
    );
    expect(service.currentPath, '/provider/folder');
    failMethod = null;
    selected = '/provider/new';
    expect(await service.requestDirectoryAccess(), '/provider/new');
    expect(service.currentPath, '/provider/new');
    expect(service.grantedBasePath, '/provider/new');
  });

  test(
    'listing uses coordinated native metadata after native scope has ended',
    () async {
      final entities = (await service.listDirectory('/provider/./folder'))!;
      expect(service.currentPath, '/provider/folder');
      expect(entities[0], isA<File>());
      expect(entities[1], isA<Directory>());
      expect(entities[2], isA<Link>());
      expect((await entities[0].stat()).size, 123);
      expect((await entities[1].stat()).type, FileSystemEntityType.directory);
      expect((await entities[2].stat()).type, FileSystemEntityType.link);
      expect(calls.map((c) => c.method), ['listDirectory']);
      expect((calls.last.arguments as Map)['path'], '/provider/folder');
      failMethod = 'listDirectory';
      await expectLater(
        service.listDirectory('/denied'),
        throwsA(isA<PathAccessException>()),
      );
      expect(service.currentPath, '/provider/folder');
    },
  );

  test(
    'reads writes create delete and lengths use native coordinated methods',
    () async {
      expect(await service.readFile('/provider/file'), [1, 2, 3]);
      final bytes = Uint8List.fromList([4, 5]);
      await service.saveFile('/provider/file', bytes);
      expect((calls.last.arguments as Map)['overwrite'], isTrue);
      expect(
        await service.saveFileWithResult(
          '/provider/file',
          bytes,
          overwrite: false,
        ),
        LocalFileSaveResult.written,
      );
      expect((calls.last.arguments as Map)['overwrite'], isFalse);
      await service.createDirectory('/provider/new');
      expect(calls.last.method, 'createDirectory');
      await service.deleteEntry('/provider/new', true);
      expect(calls.last.arguments, {'path': '/provider/new', 'isFolder': true});
      await service.deleteEntry('/provider/file', false);
      expect((calls.last.arguments as Map)['isFolder'], isFalse);
      expect(await service.fileLength('/provider/file'), 3);
      failMethod = 'fileLength';
      expect(await service.fileLength('/provider/file'), isNull);
    },
  );

  test(
    'all native operation failures translate to actionable access errors',
    () async {
      final operations = <String, Future<dynamic> Function()>{
        'listDirectory': () => service.listDirectory('/a'),
        'readFile': () => service.readFile('/a'),
        'writeFile': () => service.saveFile('/a', Uint8List(0)),
        'createDirectory': () => service.createDirectory('/a'),
        'deleteEntry': () => service.deleteEntry('/a', false),
        'walkFiles': () => service.walkFiles('/a'),
      };
      for (final operation in operations.entries) {
        failMethod = operation.key;
        await expectLater(
          operation.value(),
          throwsA(isA<PathAccessException>()),
        );
      }
      failMethod = 'writeFile';
      await expectLater(
        service.saveFileWithResult('/a', Uint8List(0)),
        throwsA(isA<PathAccessException>()),
      );
      failureCode = 'directory_moved';
      await expectLater(
        service.saveFile('/a', Uint8List(0)),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'walk produces file models and forwards hidden and limit options',
    () async {
      final files = await service.walkFiles(
        '/provider/folder',
        includeHidden: true,
        maxItems: 4,
      );
      expect(files.single.name, 'file.txt');
      expect(files.single.path, '/provider/folder/sub/file.txt');
      expect(files.single.isFolder, isFalse);
      expect(files.single.size, 123);
      expect(files.single.updatedAt!.millisecondsSinceEpoch, 1700000000000);
      expect(calls.last.arguments, {
        'path': '/provider/folder',
        'includeHidden': true,
        'maxItems': 4,
      });
      await expectLater(
        service.walkFiles('/a', maxItems: -1),
        throwsArgumentError,
      );
    },
  );

  test(
    'hasAccess and ensureAccess require native proof, not a path prefix',
    () async {
      await service.getInitialPath();
      expect(await service.hasAccessToPath('/provider/folder'), isTrue);
      accessAllowed = false;
      expect(await service.hasAccessToPath('/provider/folder-copy'), isFalse);
      expect(await service.ensureAccess('/provider/folder/file'), isFalse);
      expect((calls.last.arguments as Map)['path'], '/provider/folder/file');
      failMethod = 'hasAccess';
      expect(await service.hasAccessToPath('/provider/folder'), isFalse);
      expect(await service.ensureAccess('relative'), isFalse);
    },
  );

  test(
    'terminal and operation scopes remain independently held until each ends',
    () async {
      final firstEntered = Completer<void>();
      final secondEntered = Completer<void>();
      final firstExit = Completer<int>();
      final secondExit = Completer<int>();
      final first = service.withFileOperationAccess('/provider/folder', () {
        firstEntered.complete();
        return firstExit.future;
      });
      final second = service.withFileOperationAccess('/provider/other', () {
        secondEntered.complete();
        return secondExit.future;
      });
      await Future.wait([firstEntered.future, secondEntered.future]);
      expect(active.length, 2);
      secondExit.complete(2);
      expect(await second, 2);
      expect(active.length, 1);
      firstExit.complete(1);
      expect(await first, 1);
      expect(active, isEmpty);
    },
  );

  test(
    'scope denial skips callback; callback errors survive cleanup failures',
    () async {
      failMethod = 'acquireAccess';
      var ran = false;
      await expectLater(
        service.withFileOperationAccess('/a', () async {
          ran = true;
        }),
        throwsA(isA<PathAccessException>()),
      );
      expect(ran, isFalse);
      failMethod = null;
      final error = PlatformException(code: 'callback_error');
      await expectLater(
        service.withFileOperationAccess('/a', () async => throw error),
        throwsA(same(error)),
      );
      expect(active, isEmpty);
      failMethod = 'releaseAccess';
      expect(
        await service.withFileOperationAccess('/a', () async => 'saved'),
        'saved',
      );
      await expectLater(
        service.withFileOperationAccess('/a', () async => throw error),
        throwsA(same(error)),
      );
    },
  );

  test(
    'media read holds file access and media output holds containing directory',
    () async {
      expect(
        await service.withMediaFileAccess('/provider/movie.mp4', (path) async {
          expect(active.length, 1);
          return path;
        }),
        '/provider/movie.mp4',
      );
      expect(active, isEmpty);
      expect(
        await service.withMediaFileAccess('/provider/./output.mp4', (
          path,
        ) async {
          expect(active.length, 1);
          return path;
        }, forWrite: true),
        '/provider/output.mp4',
      );
      final acquisitions = calls
          .where((c) => c.method == 'acquireAccess')
          .toList();
      expect(acquisitions.map((c) => (c.arguments as Map)['path']), [
        '/provider/movie.mp4',
        '/provider',
      ]);
      expect(active, isEmpty);
      final failure = StateError('decoder failed');
      await expectLater(
        service.withMediaFileAccess('/a', (_) async => throw failure),
        throwsA(same(failure)),
      );
      expect(active, isEmpty);
    },
  );

  test(
    'legacy overlapping streams co-retain all grants until last consumer ends',
    () async {
      expect(await service.beginStreamAccess('/provider/a'), isTrue);
      expect(await service.beginStreamAccess('/provider/b'), isTrue);
      expect(active.length, 2);
      await service.endStreamAccess();
      expect(active.length, 2);
      await service.endStreamAccess();
      expect(active, isEmpty);
      await service.endStreamAccess();
      expect(calls.where((c) => c.method == 'releaseAccess').length, 2);
      failMethod = 'acquireAccess';
      expect(await service.beginStreamAccess('/denied'), isFalse);
      failMethod = null;
      expect(await service.beginStreamAccess('/provider/c'), isTrue);
      await service.endStreamAccess();
      expect(active, isEmpty);
    },
  );

  test(
    'new stream does not lose its grant while previous group is releasing',
    () async {
      await service.beginStreamAccess('/a');
      final releasing = Completer<void>();
      final releaseGate = Completer<void>();
      intercept = (call) async {
        if (call.method == 'releaseAccess' && !releasing.isCompleted) {
          releasing.complete();
          await releaseGate.future;
        }
      };
      final ending = service.endStreamAccess();
      await releasing.future;
      await service.beginStreamAccess('/b');
      expect(active.length, 2);
      releaseGate.complete();
      await ending;
      expect(active.length, 1);
      await service.endStreamAccess();
      expect(active, isEmpty);
    },
  );

  test(
    'metadata snapshots preserve File Directory Link identity and avoid raw IO',
    () async {
      for (final kind in ['file', 'directory', 'link']) {
        final entity = iosListingEntity(
          IosFileEntry(
            path: '/missing/$kind',
            kind: kind,
            size: 22,
            modifiedAt: DateTime(2025),
          ),
        );
        expect(entity.path, '/missing/$kind');
        expect(entity.uri, Uri.file('/missing/$kind'));
        expect(entity.isAbsolute, isTrue);
        expect(entity.absolute, same(entity));
        expect(entity.statSync().size, 22);
        final stat = await entity.stat();
        expect(stat.modified, DateTime(2025));
        expect(stat.changed, stat.modified);
        expect(stat.accessed, stat.modified);
        expect(stat.mode, 0);
        expect(stat.modeString(), '---------');
        expect(() => entity.deleteSync(), throwsUnsupportedError);
      }
      expect(
        () => iosListingEntity(
          IosFileEntry(
            path: '/a',
            kind: 'socket',
            size: 0,
            modifiedAt: DateTime(2025),
          ),
        ),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    },
  );

  test(
    'Android local operations remain on dart IO without iOS channel calls',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'crisp-android-service-',
      );
      addTearDown(() => root.delete(recursive: true));
      final android = MobileFileService(
        isIOS: false,
        documentsDirectory: () async => root,
      );
      expect(await android.getInitialPath(), root.path);
      expect(await android.getSafeFallbackDirectory(), root.path);
      final folder = '${root.path}/sub';
      final path = '$folder/file';
      await android.createDirectory(folder);
      await android.saveFile(path, Uint8List.fromList([1, 2]));
      expect(await android.readFile(path), [1, 2]);
      expect(await android.fileLength(path), 2);
      expect(await android.fileLength('$folder/missing'), isNull);
      expect((await android.listDirectory(folder))!.single.path, path);
      expect((await android.walkFiles(root.path)).single.path, path);
      expect(await android.hasAccessToPath(path), isTrue);
      expect(await android.ensureAccess(path), isTrue);
      expect(await android.withFileOperationAccess(path, () async => 7), 7);
      expect(
        await android.withMediaFileAccess(
          path,
          (accessible) async => accessible,
        ),
        path,
      );
      expect(
        await android.saveFileWithResult(path, Uint8List.fromList([3])),
        LocalFileSaveResult.written,
      );
      expect(await android.beginStreamAccess(path), isTrue);
      await android.endStreamAccess();
      await android.deleteEntry(path, false);
      await android.deleteEntry(folder, true);
      expect(calls, isEmpty);
    },
  );
}
