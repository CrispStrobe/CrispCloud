import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/services/terminal_workspace_service.dart';
import 'package:crisp_cloud/services/terminal_workspace_service_stub.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late TerminalWorkspaceService service;
  late _Cloud client;
  late bool current;
  late String root;

  Future<TerminalWorkspace> stage([
    List<String> paths = const ['/cloud/a.txt'],
  ]) => service.stage(
    client: client,
    remoteRoot: '/cloud',
    items: paths.map(client.item).toList(),
    isCurrent: () => current,
  );
  Future<File> edit(
    TerminalWorkspace workspace,
    String path,
    String contents,
  ) async {
    final file = File(p.join(workspace.directoryPath, path));
    await file.parent.create(recursive: true);
    return file.writeAsString(contents, flush: true);
  }

  Future<TerminalWorkspaceUploadResult> upload(
    TerminalWorkspace workspace, [
    List<TerminalWorkspaceChange>? changes,
  ]) async => service.uploadReviewed(
    workspaceId: workspace.id,
    client: client,
    changes: changes ?? await service.inspect(workspace.id),
    isCurrent: () => current,
  );

  setUp(() async {
    // Canonical path: macOS's temp folder lives below the /var link and the
    // service stores resolved locations.
    temporary = Directory(
      await (await Directory.systemTemp.createTemp('terminal-workspace-test-'))
          .resolveSymbolicLinks(),
    );
    root = p.join(temporary.path, 'workspaces');
    service = TerminalWorkspaceService(rootDirectory: root);
    client = _Cloud()..put('/cloud/a.txt', 'original');
    current = true;
  });
  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  group('native staging and persistence', () {
    test(
      'the default workspace directory is persistent app Documents storage',
      () async {
        final previous = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _DocumentsPath(temporary.path);
        addTearDown(() => PathProviderPlatform.instance = previous);
        service = TerminalWorkspaceService();
        final workspace = await stage();
        expect(
          p.isWithin(
            p.join(temporary.path, 'CrispCloudTerminalWorkspaces'),
            workspace.directoryPath,
          ),
          isTrue,
        );
        expect(
          (await TerminalWorkspaceService().load(workspace.id))!.directoryPath,
          workspace.directoryPath,
        );
      },
    );

    test(
      'rebuilds local paths when an app container is relocated after restart',
      () async {
        final workspace = await stage();
        final relocated = p.join(temporary.path, 'relocated-container');
        await Directory(root).rename(relocated);
        service = TerminalWorkspaceService(rootDirectory: relocated);
        final recovered = (await service.load(workspace.id))!;
        expect(
          recovered.directoryPath,
          p.join(relocated, workspace.id, 'files'),
        );
        expect(
          await File(p.join(recovered.directoryPath, 'a.txt')).readAsString(),
          'original',
        );
        expect(await service.inspect(recovered.id), isEmpty);
      },
    );

    test(
      'persisted transfer errors redact signed URLs and credentials',
      () async {
        client.onDownloadChunk = (_) => throw StateError(
          'download failed at https://name:password@example.test/object?secret=signed-token',
        );
        await expectLater(stage(), throwsA(isA<TerminalWorkspaceException>()));
        final saved = (await service.list()).single;
        expect(saved.error, contains('[remote endpoint]'));
        expect(saved.toJson().toString(), isNot(contains('signed-token')));
        expect(saved.toJson().toString(), isNot(contains('password')));
      },
    );

    test('streams into persistent files with identity and fingerprints outside cwd', () async {
      final progress = <(int, int)>[];
      final workspace = await service.stage(
        client: client,
        remoteRoot: '/cloud',
        items: [client.item('/cloud/a.txt')],
        storage: storageReferenceForClient(client),
        isCurrent: () => true,
        title: 'My commands',
        onProgress: (done, total) => progress.add((done, total)),
      );
      expect(service.isSupported, isTrue);
      expect(workspace.title, 'My commands');
      expect(workspace.status, TerminalWorkspaceStatus.ready);
      expect(workspace.storage, storageReferenceForClient(client));
      expect(workspace.remoteRoot, '/cloud');
      expect(
        workspace.entries.single.fingerprint.objectId,
        client.objects['/cloud/a.txt']!.id,
      );
      expect(
        workspace.entries.single.fingerprint.version,
        client.objects['/cloud/a.txt']!.version,
      );
      expect(
        workspace.entries.single.originalDigest,
        sha256.convert(utf8.encode('original')).toString(),
      );
      expect(
        await File(p.join(workspace.directoryPath, 'a.txt')).readAsString(),
        'original',
      );
      expect(
        (await Directory(
          workspace.directoryPath,
        ).list().toList()).map((item) => p.basename(item.path)),
        ['a.txt'],
      );
      expect(progress, [(1, 1)]);
      expect(client.bufferedDownloads, 0);
      expect(client.cachedLists, 0);
      expect(client.downloads, ['/cloud/a.txt']);
      expect(await service.inspect(workspace.id), isEmpty);
      final restarted = TerminalWorkspaceService(rootDirectory: root);
      final loaded = (await restarted.load(workspace.id))!;
      expect(loaded.directoryPath, workspace.directoryPath);
      expect(loaded.toJson(), workspace.toJson());
      expect((await restarted.list()).single.id, workspace.id);
      expect(
        await restarted.list(
          storage: const StorageReference(
            kind: 'remote',
            provider: 'other',
            accountKey: 'other',
          ),
        ),
        isEmpty,
      );
      expect(await restarted.list(storage: workspace.storage), hasLength(1));
      expect(
        await restarted.load('ws-00000000-0000-0000-0000-000000000000'),
        isNull,
      );
    });

    test('stages recursive folders, empty directories and literal shell metacharacters', () async {
      client.mkdir('/cloud/project');
      client.mkdir('/cloud/project/empty');
      client.mkdir('/cloud/project/sub');
      client.put(
        '/cloud/project/sub/space ; \$(touch nope).txt',
        'literal filename',
      );
      client.put('/cloud/project/.hidden', 'hidden');
      final workspace = await stage(['/cloud/project']);
      expect(
        workspace.entries.map((entry) => entry.relativePath),
        containsAll([
          'project',
          'project/empty',
          'project/sub',
          'project/sub/space ; \$(touch nope).txt',
          'project/.hidden',
        ]),
      );
      expect(
        await Directory(p.join(workspace.directoryPath, 'project', 'empty'))
            .exists(),
        isTrue,
      );
      expect(
        await File(
          p.join(
            workspace.directoryPath,
            'project',
            'sub',
            'space ; \$(touch nope).txt',
          ),
        ).readAsString(),
        'literal filename',
      );
      expect(await service.inspect(workspace.id), isEmpty);
      expect(client.uploads, isEmpty);
    });

    test(
      'rejects unscoped, stale and account-switched selections before download',
      () async {
        for (final items in [
          <FileItem>[],
          [FileItem(name: '../escape', path: '/escape', isFolder: false)],
          [FileItem(name: 'a.txt', path: '/elsewhere/a.txt', isFolder: false)],
          [client.item('/cloud/a.txt').copyWith(uuid: 'old-object')],
          [client.item('/cloud/a.txt').copyWith(size: 500)],
          [client.item('/cloud/a.txt').copyWith(storageId: 'wrong-account')],
        ]) {
          await expectLater(
            service.stage(
              client: client,
              remoteRoot: '/cloud',
              items: items,
              isCurrent: () => true,
            ),
            throwsA(
              anyOf(isA<TerminalWorkspaceException>(), isA<FormatException>()),
            ),
          );
        }
        current = false;
        await expectLater(stage(), throwsA(isA<TerminalWorkspaceException>()));
        current = true;
        client.account = '';
        await expectLater(stage(), throwsA(isA<TerminalWorkspaceException>()));
        expect(client.downloads, isEmpty);
      },
    );

    test(
      'rejects wrong captured storage and paths outside namespace',
      () async {
        final captured = storageReferenceForClient(client);
        client.account = 'different-account';
        await expectLater(
          service.stage(
            client: client,
            remoteRoot: '/cloud',
            items: [client.item('/cloud/a.txt')],
            storage: captured,
            isCurrent: () => true,
          ),
          throwsA(isA<TerminalWorkspaceException>()),
        );
        client.namespaceRoot = '/restricted';
        await expectLater(stage(), throwsA(isA<TerminalWorkspaceException>()));
        await expectLater(
          service.stage(
            client: client,
            remoteRoot: '/cloud/../other',
            items: [client.item('/cloud/a.txt')],
            isCurrent: () => true,
          ),
          throwsFormatException,
        );
      },
    );

    test(
      'fresh pagination, malformed lengths and ambiguous names fail closed',
      () async {
        for (final extra in [
          {'nextPageToken': 'page2'},
          {'has_more': true},
          {'complete': false},
          {'error': 'denied'},
          {'files': null},
        ]) {
          client.listingOverride = extra;
          await expectLater(
            stage(),
            throwsA(isA<TerminalWorkspaceException>()),
          );
        }
        client.listingOverride = null;
        for (final value in [-1, 1.5, '10', double.nan]) {
          client.sizeOverride = value;
          await expectLater(
            stage(),
            throwsA(isA<TerminalWorkspaceException>()),
          );
        }
        client.sizeOverride = null;
        client.put('/cloud/A.txt', 'case collision');
        await expectLater(stage(), throwsA(isA<TerminalWorkspaceException>()));
        expect(client.downloads, isEmpty);
      },
    );

    test(
      'rejects remote links, directory cycles and traversal from listing',
      () async {
        client.objects['/cloud/a.txt']!.link = true;
        await expectLater(stage(), throwsA(isA<TerminalWorkspaceException>()));
        client.objects['/cloud/a.txt']!.link = false;
        client.mkdir('/cloud/folder');
        client.mkdir('/cloud/folder/sub');
        client.directories['/cloud/folder/sub'] =
            client.directories['/cloud/folder']!;
        await expectLater(
          stage(['/cloud/folder']),
          throwsA(isA<TerminalWorkspaceException>()),
        );
        client.rawNameOverride = '../escaped';
        await expectLater(stage(), throwsFormatException);
        expect(client.downloads, isEmpty);
      },
    );

    test('entry, depth, byte and stream length limits are enforced', () async {
      for (final arguments in [
        (entries: 0, depth: 1, bytes: 1),
        (entries: 1, depth: 0, bytes: 1),
        (entries: 1, depth: 1, bytes: 0),
      ]) {
        expect(
          () => TerminalWorkspaceService(
            rootDirectory: root,
            maxEntries: arguments.entries,
            maxDepth: arguments.depth,
            maxTotalBytes: arguments.bytes,
          ),
          throwsArgumentError,
        );
      }
      service = TerminalWorkspaceService(rootDirectory: root, maxTotalBytes: 3);
      await expectLater(stage(), throwsA(isA<TerminalWorkspaceException>()));
      service = TerminalWorkspaceService(rootDirectory: root, maxEntries: 1);
      client.put('/cloud/b.txt', 'b');
      await expectLater(stage(), throwsA(isA<TerminalWorkspaceException>()));
      client.objects.remove('/cloud/b.txt');
      service = TerminalWorkspaceService(rootDirectory: root, maxDepth: 1);
      client.mkdir('/cloud/folder');
      client.put('/cloud/folder/child', 'c');
      await expectLater(
        stage(['/cloud/folder']),
        throwsA(isA<TerminalWorkspaceException>()),
      );
      service = TerminalWorkspaceService(rootDirectory: root);
      client.sizeOverride = 2;
      await expectLater(stage(), throwsA(isA<TerminalWorkspaceException>()));
      client.sizeOverride = null;
      client.streamExtra = 'extra';
      await expectLater(stage(), throwsA(isA<TerminalWorkspaceException>()));
    });

    test('stream errors preserve a journal and resume without overwriting completed edits', () async {
      client.put('/cloud/b.txt', 'second');
      client.failDownload = '/cloud/b.txt';
      String? id;
      try {
        await stage(['/cloud/a.txt', '/cloud/b.txt']);
        fail('Expected staging interruption');
      } on TerminalWorkspaceException catch (error) {
        id = error.workspaceId;
      }
      final interrupted = (await service.load(id!))!;
      expect(interrupted.status, TerminalWorkspaceStatus.interrupted);
      expect(
        interrupted.entries.first.status,
        TerminalWorkspaceEntryStatus.ready,
      );
      expect(
        interrupted.entries.last.status,
        TerminalWorkspaceEntryStatus.pending,
      );
      expect(interrupted.error, contains('download interrupted'));
      expect(
        await Directory(p.join(root, id, 'scratch')).list().toList(),
        isEmpty,
      );
      await edit(interrupted, 'a.txt', 'local edits retained');
      client.failDownload = null;
      service = TerminalWorkspaceService(rootDirectory: root);
      final resumed = await service.resumeStage(
        workspaceId: id,
        client: client,
        isCurrent: () => true,
      );
      expect(resumed.status, TerminalWorkspaceStatus.ready);
      expect(
        await File(p.join(resumed.directoryPath, 'a.txt')).readAsString(),
        'local edits retained',
      );
      expect(
        await File(p.join(resumed.directoryPath, 'b.txt')).readAsString(),
        'second',
      );
      expect((await service.inspect(id)).single.relativePath, 'a.txt');
      final unchanged = await service.resumeStage(
        workspaceId: id,
        client: client,
        isCurrent: () => true,
      );
      expect(unchanged.revision, resumed.revision);
    });

    test(
      'cancelled stage is recoverable and changed remote refuses resume',
      () async {
        client.put('/cloud/b.txt', 'second');
        var cancelled = false;
        String? id;
        try {
          await service.stage(
            client: client,
            remoteRoot: '/cloud',
            items: [client.item('/cloud/a.txt'), client.item('/cloud/b.txt')],
            isCurrent: () => true,
            isCancelled: () => cancelled,
            onProgress: (_, _) => cancelled = true,
          );
        } on TerminalWorkspaceException catch (error) {
          id = error.workspaceId;
        }
        expect(id, isNotNull);
        client.put('/cloud/b.txt', 'cloud changed');
        await expectLater(
          service.resumeStage(
            workspaceId: id!,
            client: client,
            isCurrent: () => true,
          ),
          throwsA(isA<TerminalWorkspaceException>()),
        );
        expect(
          (await service.load(id))!.status,
          TerminalWorkspaceStatus.interrupted,
        );
        expect(
          await File(p.join((await service.load(id))!.directoryPath, 'a.txt'))
              .readAsString(),
          'original',
        );
      },
    );

    test('staging detects remote mutation during download', () async {
      client.onDownloadChunk = (path) {
        if (path == '/cloud/a.txt') client.put(path, 'updated!');
      };
      await expectLater(stage(), throwsA(isA<TerminalWorkspaceException>()));
      final saved = (await service.list()).single;
      expect(saved.status, TerminalWorkspaceStatus.interrupted);
      expect(
        await File(p.join(saved.directoryPath, 'a.txt')).exists(),
        isFalse,
      );
    });

    test(
      'resumes a crash after file rename only when bytes still match',
      () async {
        final workspace = await stage();
        await _editManifest(root, workspace.id, (json) {
          final entry = (json['entries'] as List).single as Map;
          entry['status'] = 'pending';
          json['status'] = 'staging';
        });
        final resumed = await service.resumeStage(
          workspaceId: workspace.id,
          client: client,
          isCurrent: () => true,
        );
        expect(resumed.status, TerminalWorkspaceStatus.ready);
        await _editManifest(root, workspace.id, (json) {
          final entry = (json['entries'] as List).single as Map;
          entry['status'] = 'pending';
        });
        await edit(workspace, 'a.txt', 'do not replace me');
        await expectLater(
          service.resumeStage(
            workspaceId: workspace.id,
            client: client,
            isCurrent: () => true,
          ),
          throwsA(
            predicate((error) => error.toString().contains('contains edits')),
          ),
        );
        expect(
          await File(p.join(workspace.directoryPath, 'a.txt')).readAsString(),
          'do not replace me',
        );
      },
    );

    test('recovers a newer flushed journal and preserves corrupt journals with warnings', () async {
      final workspace = await stage();
      final manifest = File(p.join(root, workspace.id, 'manifest.json'));
      final old = await manifest.readAsString();
      await _editManifest(root, workspace.id, (json) {
        json['revision'] = (json['revision'] as int) + 1;
        json['title'] = 'Recovered pending journal';
      });
      await manifest.rename(p.join(root, workspace.id, 'manifest.pending'));
      await manifest.writeAsString(old, flush: true);
      expect(
        (await service.load(workspace.id))!.title,
        'Recovered pending journal',
      );
      await File(p.join(root, workspace.id, 'manifest.pending'))
          .writeAsString('broken');
      expect((await service.load(workspace.id))!.title, workspace.title);
      await manifest.writeAsString('broken too');
      expect(await service.list(), isEmpty);
      expect(service.warnings, hasLength(1));
      expect(await manifest.exists(), isTrue);
      await expectLater(
        service.load(workspace.id),
        throwsA(isA<TerminalWorkspaceException>()),
      );
    });
  });

  group('local inspection and containment', () {
    test('inspection cancellation stops before enumeration and between file chunks', () async {
      final workspace = await stage();
      await expectLater(
        service.inspect(workspace.id, isCancelled: () => true),
        throwsA(
          predicate(
            (error) => error.toString().contains('inspection cancelled'),
          ),
        ),
      );
      final local = File(p.join(workspace.directoryPath, 'a.txt'));
      await local.writeAsBytes(Uint8List(2 * 1024 * 1024));
      var checks = 0;
      await expectLater(
        service.inspect(workspace.id, isCancelled: () => ++checks >= 8),
        throwsA(
          predicate(
            (error) => error.toString().contains('inspection cancelled'),
          ),
        ),
      );
      expect(checks, inInclusiveRange(8, 10));
      expect(await local.length(), 2 * 1024 * 1024);
      expect((await service.load(workspace.id))!.revision, workspace.revision);
      expect(client.uploads, isEmpty);
    });

    test(
      'binary and empty files round-trip through streaming staging and upload',
      () async {
        client.putBytes('/cloud/a.txt', [0, 255, 128, 10, 13, 1]);
        client.put('/cloud/empty', '');
        final workspace = await stage(['/cloud/a.txt', '/cloud/empty']);
        expect(
          await File(p.join(workspace.directoryPath, 'a.txt')).readAsBytes(),
          [0, 255, 128, 10, 13, 1],
        );
        expect(
          await File(p.join(workspace.directoryPath, 'empty')).length(),
          0,
        );
        await File(p.join(workspace.directoryPath, 'a.txt'))
            .writeAsBytes([254, 0, 127, 255]);
        await edit(workspace, 'new-empty', '');
        final result = await upload(workspace);
        expect(result.succeeded, isTrue);
        expect(client.objects['/cloud/a.txt']!.bytes, [254, 0, 127, 255]);
        expect(client.objects['/cloud/new-empty']!.bytes, isEmpty);
      },
    );

    test(
      'uses decrypted lengths while retaining provider stored-size metadata',
      () async {
        client.transformedStoredSize = 36;
        final workspace = await stage();
        expect(workspace.entries.single.originalSize, 8);
        expect(workspace.entries.single.fingerprint.size, 8);
        expect(
          await File(p.join(workspace.directoryPath, 'a.txt')).length(),
          8,
        );
        await edit(workspace, 'a.txt', 'longer plaintext');
        final result = await upload(workspace);
        expect(result.succeeded, isTrue);
        expect(client.text('/cloud/a.txt'), 'longer plaintext');
      },
    );

    test('enforces byte limits even when the provider omits lengths', () async {
      client.omitSizes = true;
      service = TerminalWorkspaceService(rootDirectory: root, maxTotalBytes: 3);
      await expectLater(
        stage(),
        throwsA(predicate((error) => error.toString().contains('size limit'))),
      );
      final workspace = (await service.list()).single;
      expect(workspace.status, TerminalWorkspaceStatus.interrupted);
      expect(
        await File(p.join(workspace.directoryPath, 'a.txt')).exists(),
        isFalse,
      );
    });

    test(
      'blocks both names in a local case collision and bounds inspection reads',
      () async {
        // A case-insensitive volume (macOS default) cannot hold both names.
        final probe = File(p.join(temporary.path, 'case-probe'));
        await probe.writeAsString('x');
        if (await File(p.join(temporary.path, 'CASE-PROBE')).exists()) {
          markTestSkipped('Case-insensitive file system');
          return;
        }
        final workspace = await stage();
        await edit(workspace, 'new.txt', 'new');
        await edit(workspace, 'NEW.txt', 'different');
        final changes = await service.inspect(workspace.id);
        expect(changes, hasLength(2));
        expect(changes.every((change) => !change.canUpload), isTrue);
        service = TerminalWorkspaceService(
          rootDirectory: root,
          maxTotalBytes: 2,
        );
        final limited = await service.inspect(workspace.id);
        expect(limited.every((change) => !change.canUpload), isTrue);
      },
    );

    test(
      'will not adopt an unjournaled local file as a completed download',
      () async {
        final workspace = await stage();
        await _editManifest(root, workspace.id, (json) {
          final entry = (json['entries'] as List).single as Map;
          entry['status'] = 'pending';
          entry.remove('originalDigest');
          entry.remove('originalSize');
        });
        await expectLater(
          service.resumeStage(
            workspaceId: workspace.id,
            client: client,
            isCurrent: () => true,
          ),
          throwsA(
            predicate((error) => error.toString().contains('contains edits')),
          ),
        );
        expect(
          await File(p.join(workspace.directoryPath, 'a.txt')).readAsString(),
          'original',
        );
      },
    );

    test(
      'retains a local file created while a download is in flight',
      () async {
        client.onDownloadChunk = (_) async {
          final pending = (await service.list()).single;
          await edit(pending, 'a.txt', 'created concurrently');
        };
        await expectLater(
          stage(),
          throwsA(
            predicate(
              (error) => error.toString().contains('appeared while staging'),
            ),
          ),
        );
        final workspace = (await service.list()).single;
        expect(
          await File(p.join(workspace.directoryPath, 'a.txt')).readAsString(),
          'created concurrently',
        );
      },
    );

    test(
      'checks parent links again after a download before installing a file',
      () async {
        client.mkdir('/cloud/folder');
        client.put('/cloud/folder/child', 'child');
        final outside = await Directory(p.join(temporary.path, 'outside'))
            .create();
        var replaced = false;
        client.onDownloadChunk = (_) async {
          if (replaced) return;
          replaced = true;
          final workspace = (await service.list()).single;
          final folder = p.join(workspace.directoryPath, 'folder');
          await Directory(folder).rename('$folder-original');
          await Link(folder).create(outside.path);
        };
        await expectLater(
          stage(['/cloud/folder']),
          throwsA(isA<TerminalWorkspaceException>()),
        );
        expect(await outside.list().toList(), isEmpty);
      },
    );

    test(
      'classifies modified, added, removed and new-directory paths',
      () async {
        final workspace = await stage();
        await edit(workspace, 'a.txt', 'edits');
        await edit(workspace, 'output.txt', 'output');
        await edit(workspace, 'newdir/out.txt', 'nested');
        final changes = await service.inspect(workspace.id);
        final indexed = {
          for (final change in changes) change.relativePath: change,
        };
        expect(indexed['a.txt']!.kind, TerminalWorkspaceChangeKind.modified);
        expect(indexed['output.txt']!.kind, TerminalWorkspaceChangeKind.added);
        expect(indexed['newdir']!.isDirectory, isTrue);
        expect(indexed['newdir']!.canUpload, isFalse);
        expect(indexed['newdir/out.txt']!.canUpload, isTrue);
        expect(
          indexed['a.txt']!.digest,
          sha256.convert(utf8.encode('edits')).toString(),
        );
        await File(p.join(workspace.directoryPath, 'a.txt')).delete();
        expect(
          (await service.inspect(workspace.id)).first.kind,
          TerminalWorkspaceChangeKind.deleted,
        );
      },
    );

    test(
      'never propagates a local deletion and unchanged uploads are a no-op',
      () async {
        final workspace = await stage();
        final noOp = await upload(workspace);
        expect(noOp.succeeded, isTrue);
        expect(noOp.workspace.revision, workspace.revision);
        expect(noOp.uploadedPaths, isEmpty);
        expect(client.uploads, isEmpty);
        await File(p.join(workspace.directoryPath, 'a.txt')).delete();
        final result = await upload(workspace);
        expect(result.skippedPaths, ['a.txt']);
        expect(client.text('/cloud/a.txt'), 'original');
        expect(client.deletes, isEmpty);
      },
    );

    test(
      'does not follow file or directory links outside the workspace',
      () async {
        final workspace = await stage();
        final outside = await File(p.join(temporary.path, 'secret'))
            .writeAsString('outside');
        await File(p.join(workspace.directoryPath, 'a.txt')).delete();
        await Link(p.join(workspace.directoryPath, 'a.txt'))
            .create(outside.path);
        await Link(p.join(workspace.directoryPath, 'linked-dir'))
            .create(temporary.path);
        final changes = await service.inspect(workspace.id);
        expect(changes, hasLength(2));
        expect(
          changes.every(
            (change) => change.kind == TerminalWorkspaceChangeKind.unsafe,
          ),
          isTrue,
        );
        final result = await upload(workspace, changes);
        expect(result.uploadedPaths, isEmpty);
        expect(client.uploads, isEmpty);
        expect(await outside.readAsString(), 'outside');
      },
    );

    test('rejects a replaced workspace root or journal symlink', () async {
      final workspace = await stage();
      final outside = await Directory(p.join(temporary.path, 'outside'))
          .create();
      final moved = '${workspace.directoryPath}-old';
      await Directory(workspace.directoryPath).rename(moved);
      await Link(workspace.directoryPath).create(outside.path);
      await expectLater(
        service.inspect(workspace.id),
        throwsA(isA<TerminalWorkspaceException>()),
      );
      await Link(workspace.directoryPath).delete();
      await Directory(moved).rename(workspace.directoryPath);
      final manifest = File(p.join(root, workspace.id, 'manifest.json'));
      await manifest.delete();
      await Link(manifest.path).create(p.join(outside.path, 'manifest.json'));
      await expectLater(
        service.load(workspace.id),
        throwsA(isA<TerminalWorkspaceException>()),
      );
      expect(await service.list(), isEmpty);
      expect(service.warnings, isNotEmpty);
    });

    test(
      'rejects symlink storage root and tampered manifest path mappings',
      () async {
        final target = await Directory(p.join(temporary.path, 'actual-root'))
            .create();
        await Link(root).create(target.path);
        await expectLater(
          service.list(),
          throwsA(isA<TerminalWorkspaceException>()),
        );
        await Link(root).delete();
        service = TerminalWorkspaceService(rootDirectory: root);
        final workspace = await stage();
        await _editManifest(root, workspace.id, (json) {
          ((json['entries'] as List).single as Map)['remotePath'] =
              '/other-account/escape';
        });
        await expectLater(
          service.load(workspace.id),
          throwsA(isA<TerminalWorkspaceException>()),
        );
        await expectLater(service.load('../anything'), throwsFormatException);
      },
    );

    test('rejects regular-file and directory type substitutions', () async {
      client.mkdir('/cloud/folder');
      client.put('/cloud/folder/child', 'child');
      final workspace = await stage(['/cloud/a.txt', '/cloud/folder']);
      await File(p.join(workspace.directoryPath, 'a.txt')).delete();
      await Directory(p.join(workspace.directoryPath, 'a.txt')).create();
      await Directory(p.join(workspace.directoryPath, 'folder'))
          .delete(recursive: true);
      await File(p.join(workspace.directoryPath, 'folder'))
          .writeAsString('replacement');
      final changes = await service.inspect(workspace.id);
      expect(
        changes.where(
          (change) => change.kind == TerminalWorkspaceChangeKind.unsafe,
        ),
        hasLength(2),
      );
      expect(
        changes
            .where(
              (change) => change.kind == TerminalWorkspaceChangeKind.deleted,
            )
            .single
            .relativePath,
        'folder/child',
      );
    });
  });

  group('reviewed uploads and recovery', () {
    test('conditional native-move backup receipt survives interruption after backedUp', () async {
      client.mode = _Mode.conditionalMove;
      client.versionChangesOnMove = true;
      final workspace = await stage();
      await edit(workspace, 'a.txt', 'reviewed native replacement');
      final review = await service.inspect(workspace.id);
      var interrupted = false;
      final manifest = File(p.join(root, workspace.id, 'manifest.json'));
      bool activeUntilBackedUp() {
        if (interrupted) return false;
        final envelope = jsonDecode(manifest.readAsStringSync()) as Map;
        final record = jsonDecode(envelope['payload'] as String) as Map;
        final entry = (record['entries'] as List).single as Map;
        if ((entry['pendingUpload'] as Map?)?['phase'] == 'backedUp') {
          interrupted = true;
          return false;
        }
        return true;
      }

      final failed = await service.uploadReviewed(
        workspaceId: workspace.id,
        client: client,
        changes: review,
        isCurrent: activeUntilBackedUp,
      );
      expect(interrupted, isTrue);
      expect(failed.succeeded, isFalse);
      expect(client.objects.containsKey('/cloud/a.txt'), isFalse);
      final receipt = failed.workspace.entries.single.pendingUpload!;
      expect(receipt['phase'], 'backedUp');
      expect(receipt['backupCopyVersion'], isNull);
      final backup = receipt['backupPath'] as String;
      expect(receipt['backupVersion'], client.objects[backup]!.version);
      expect(client.text(backup), 'original');
      service = TerminalWorkspaceService(rootDirectory: root);
      final recovered = await upload(workspace);
      expect(recovered.succeeded, isTrue);
      expect(client.text('/cloud/a.txt'), 'reviewed native replacement');
      expect(client.text(backup), 'original');
      expect(recovered.workspace.warnings.join(), contains(backup));
    });

    test(
      'native-move restoration records a changed revision for a safe retry',
      () async {
        client.mode = _Mode.conditionalMove;
        client.versionChangesOnMove = true;
        final workspace = await stage();
        await edit(workspace, 'a.txt', 'replacement');
        client.failCommit = true;
        final failed = await upload(workspace);
        expect(failed.succeeded, isFalse);
        expect(client.text('/cloud/a.txt'), 'original');
        final receipt = failed.workspace.entries.single.pendingUpload!;
        expect(receipt['restoreMovePath'], '/cloud/a.txt');
        expect(
          receipt['restoreMoveVersion'],
          client.objects['/cloud/a.txt']!.version,
        );
        expect(
          receipt['restoreMoveVersion'],
          isNot(workspace.entries.single.fingerprint.version),
        );
        client.failCommit = false;
        service = TerminalWorkspaceService(rootDirectory: root);
        expect((await upload(workspace)).succeeded, isTrue);
        expect(client.text('/cloud/a.txt'), 'replacement');
      },
    );

    test('conditional native moves protect replacements and unsafe preferred move routes are rejected', () async {
      client.mode = _Mode.conditionalMove;
      final workspace = await stage();
      await edit(workspace, 'a.txt', 'conditional move edit');
      expect((await upload(workspace)).succeeded, isTrue);
      expect(client.text('/cloud/a.txt'), 'conditional move edit');
      final next = await stage();
      await edit(next, 'a.txt', 'unsafe route edit');
      client.mode = _Mode.mixedUnsafe;
      final uploadsBefore = client.uploads.length;
      final refused = await upload(next);
      expect(refused.failures['a.txt'], contains('cannot atomically protect'));
      expect(client.uploads.length, uploadsBefore);
    });

    test('a failed commit restores the original and accepts a retry against the recorded restored revision', () async {
      final workspace = await stage();
      await edit(workspace, 'a.txt', 'reviewed replacement');
      client.failCommit = true;
      final failed = await upload(workspace);
      expect(failed.succeeded, isFalse);
      expect(client.text('/cloud/a.txt'), 'original');
      expect(
        failed.workspace.entries.single.pendingUpload!['restoreCopyVersion'],
        client.objects['/cloud/a.txt']!.version,
      );
      client.failCommit = false;
      service = TerminalWorkspaceService(rootDirectory: root);
      final recovered = await upload(workspace);
      expect(recovered.succeeded, isTrue);
      expect(client.text('/cloud/a.txt'), 'reviewed replacement');
    });

    test(
      'backup cleanup failures are recorded as persistent nonfatal warnings',
      () async {
        final workspace = await stage();
        await edit(workspace, 'a.txt', 'edited');
        client.failBackupDeletion = true;
        final result = await upload(workspace);
        expect(result.succeeded, isTrue);
        expect(result.workspace.warnings.join(), contains('.crisp-replaced-'));
        expect(
          (await TerminalWorkspaceService(rootDirectory: root)
                  .load(workspace.id))!
              .warnings,
          result.workspace.warnings,
        );
      },
    );

    test('lost acknowledgements for new files recover without treating them as unrelated conflicts', () async {
      final workspace = await stage();
      await edit(workspace, 'output', 'output contents');
      client.loseCommitReply = true;
      final failed = await upload(workspace);
      expect(failed.succeeded, isFalse);
      expect(
        (await service.inspect(workspace.id)).single.kind,
        TerminalWorkspaceChangeKind.added,
      );
      final uploadsBefore = client.uploads.length;
      client.loseCommitReply = false;
      final recovered = await upload(workspace);
      expect(recovered.succeeded, isTrue);
      expect(client.uploads.length, uploadsBefore);
      expect(await service.inspect(workspace.id), isEmpty);
    });

    test(
      'uploads only reviewed changes using staged streams and updates baseline',
      () async {
        client.put('/cloud/b.txt', 'second');
        final workspace = await stage(['/cloud/a.txt', '/cloud/b.txt']);
        await edit(workspace, 'a.txt', 'reviewed edit');
        await edit(workspace, 'b.txt', 'leave local');
        final changes = await service.inspect(workspace.id);
        final result = await upload(
          workspace,
          changes.where((change) => change.relativePath == 'a.txt').toList(),
        );
        expect(result.succeeded, isTrue);
        expect(result.uploadedPaths, ['a.txt']);
        expect(client.text('/cloud/a.txt'), 'reviewed edit');
        expect(client.text('/cloud/b.txt'), 'second');
        expect(client.bufferedUploads, 0);
        expect(client.uploads.single, contains('/.crisp-transfer-'));
        expect(client.legacyRenames, 0);
        expect(client.copies, hasLength(2));
        expect(
          client.copies.every((copy) => copy.expectedVersion != null),
          isTrue,
        );
        expect(
          (await service.inspect(workspace.id)).single.relativePath,
          'b.txt',
        );
        expect(
          (await service.load(workspace.id))!.entries.first.originalDigest,
          sha256.convert(utf8.encode('reviewed edit')).toString(),
        );
      },
    );

    test('uploads new files with exact no-replace moves while retaining unsupported replacements', () async {
      client.mode = _Mode.moveOnly;
      final workspace = await stage();
      await edit(workspace, 'a.txt', 'retained edit');
      await edit(workspace, 'new.txt', 'new content');
      final result = await upload(workspace);
      expect(result.uploadedPaths, ['new.txt']);
      expect(result.failures['a.txt'], contains('cannot atomically protect'));
      expect(client.text('/cloud/a.txt'), 'original');
      expect(client.text('/cloud/new.txt'), 'new content');
      expect(
        await File(p.join(workspace.directoryPath, 'a.txt')).readAsString(),
        'retained edit',
      );
      expect(
        (await service.load(workspace.id))!.error,
        contains('retained locally'),
      );
    });

    test('an incapable provider retains all local work without a direct upload fallback', () async {
      client.mode = _Mode.unsupported;
      final workspace = await stage();
      await edit(workspace, 'a.txt', 'edit');
      await edit(workspace, 'new.txt', 'new');
      final result = await upload(workspace);
      expect(result.failures, hasLength(2));
      expect(
        result.failures['new.txt'],
        contains('cannot guarantee an exact upload'),
      );
      expect(client.uploads, isEmpty);
      expect(client.text('/cloud/a.txt'), 'original');
    });

    test(
      'missing revision tokens prevent unsafe replacement before any upload',
      () async {
        client.omitVersions = true;
        final workspace = await stage();
        await edit(workspace, 'a.txt', 'edit');
        final result = await upload(workspace);
        expect(result.failures['a.txt'], contains('no revision token'));
        expect(client.uploads, isEmpty);
      },
    );

    test(
      'stale, forged, duplicated and changed review tokens are rejected',
      () async {
        final workspace = await stage();
        await edit(workspace, 'a.txt', 'first edit');
        final change = (await service.inspect(workspace.id)).single;
        await expectLater(
          upload(workspace, [change, change]),
          throwsA(isA<TerminalWorkspaceException>()),
        );
        await expectLater(
          upload(workspace, [
            TerminalWorkspaceChange(
              workspaceId: workspace.id,
              manifestRevision: change.manifestRevision,
              relativePath: change.relativePath,
              remotePath: '/elsewhere/a.txt',
              kind: change.kind,
              digest: change.digest,
              size: change.size,
            ),
          ]),
          throwsA(isA<TerminalWorkspaceException>()),
        );
        await edit(workspace, 'a.txt', 'second edit');
        await expectLater(
          upload(workspace, [change]),
          throwsA(
            predicate(
              (error) => error.toString().contains('changed after review'),
            ),
          ),
        );
        expect(client.uploads, isEmpty);
        final fresh = await service.inspect(workspace.id);
        await upload(workspace, fresh);
        await expectLater(
          upload(workspace, fresh),
          throwsA(predicate((error) => error.toString().contains('stale'))),
        );
      },
    );

    test('uses immutable reviewed snapshot even if a shell edits the file during upload', () async {
      final workspace = await stage();
      await edit(workspace, 'a.txt', 'reviewed bytes');
      final changes = await service.inspect(workspace.id);
      client.beforeUpload = () async {
        await edit(workspace, 'a.txt', 'later shell bytes');
      };
      final result = await upload(workspace, changes);
      expect(result.succeeded, isTrue);
      expect(client.text('/cloud/a.txt'), 'reviewed bytes');
      expect(
        await File(p.join(workspace.directoryPath, 'a.txt')).readAsString(),
        'later shell bytes',
      );
      final remaining = (await service.inspect(workspace.id)).single;
      expect(remaining.kind, TerminalWorkspaceChangeKind.modified);
      expect(
        remaining.digest,
        sha256.convert(utf8.encode('later shell bytes')).toString(),
      );
    });

    test(
      'detects remote version, identity and same-metadata content changes',
      () async {
        for (final preserveMetadata in [false, true]) {
          final workspace = await stage();
          await edit(workspace, 'a.txt', 'local edit');
          client.put(
            '/cloud/a.txt',
            'changed!',
            preserveMetadata: preserveMetadata,
          );
          final result = await upload(workspace);
          expect(result.failures['a.txt'], contains('changed since staging'));
          expect(client.text('/cloud/a.txt'), 'changed!');
          expect(client.uploads, isEmpty);
          client.put('/cloud/a.txt', 'original');
        }
        final workspace = await stage();
        await edit(workspace, 'a.txt', 'local edit');
        client.directories['/cloud'] = 'replacement-root';
        await expectLater(
          upload(workspace),
          throwsA(
            predicate((error) => error.toString().contains('changed identity')),
          ),
        );
      },
    );

    test(
      'detects remote mutation after streaming and conditional-copy races',
      () async {
        final workspace = await stage();
        await edit(workspace, 'a.txt', 'local edit');
        client.afterUpload = () {
          client.put('/cloud/a.txt', 'changed!', preserveMetadata: true);
        };
        final changed = await upload(workspace);
        expect(changed.failures['a.txt'], contains('changed while uploading'));
        expect(client.text('/cloud/a.txt'), 'changed!');
        expect(client.copies, isEmpty);
        client.afterUpload = null;
        client.put('/cloud/a.txt', 'original');
        final second = await stage();
        await edit(second, 'a.txt', 'second edit');
        client.beforeCopy = (source, destination) {
          if (source == '/cloud/a.txt') client.put(source, 'racing writer');
        };
        final raced = await upload(second);
        expect(raced.succeeded, isFalse);
        expect(client.text('/cloud/a.txt'), 'racing writer');
        expect(
          client.objects.keys.where(
            (path) => path.contains('.crisp-replaced-'),
          ),
          isEmpty,
        );
      },
    );

    test('new-name conflicts and new directory requirements never overwrite remotely', () async {
      final workspace = await stage();
      await edit(workspace, 'existing.txt', 'new local');
      await edit(workspace, 'new-folder/output.txt', 'nested output');
      client.put('/cloud/existing.txt', 'remote existing');
      final result = await upload(workspace);
      expect(
        result.failures['existing.txt'],
        contains('already uses this new name'),
      );
      expect(
        result.failures['new-folder/output.txt'],
        contains('Create it remotely'),
      );
      expect(result.skippedPaths, ['new-folder']);
      expect(client.text('/cloud/existing.txt'), 'remote existing');
      expect(client.uploads, isEmpty);
    });

    test('another writer at final commit is preserved together with original backup', () async {
      final workspace = await stage();
      await edit(workspace, 'a.txt', 'local edit');
      client.beforeCopy = (source, destination) {
        if (source.contains('.crisp-transfer-') &&
            destination == '/cloud/a.txt') {
          client.put(destination, 'concurrent destination');
        }
      };
      final result = await upload(workspace);
      expect(result.succeeded, isFalse);
      expect(client.text('/cloud/a.txt'), 'concurrent destination');
      final backup = client.objects.keys.singleWhere(
        (path) => path.contains('.crisp-replaced-'),
      );
      expect(client.text(backup), 'original');
      expect(result.failures['a.txt'], contains(backup));
      expect(
        (await service.load(workspace.id))!
            .entries
            .single
            .pendingUpload!['backupPath'],
        backup,
      );
    });

    test('failed uploads keep originals and retry from the persisted reviewed baseline', () async {
      final workspace = await stage();
      await edit(workspace, 'a.txt', 'local edit');
      client.failUpload = true;
      final failed = await upload(workspace);
      expect(failed.succeeded, isFalse);
      expect(client.text('/cloud/a.txt'), 'original');
      expect(
        failed.workspace.entries.single.pendingUpload!['phase'],
        'uploading',
      );
      expect(failed.workspace.status, TerminalWorkspaceStatus.interrupted);
      client.failUpload = false;
      service = TerminalWorkspaceService(rootDirectory: root);
      final retried = await upload(workspace);
      expect(retried.succeeded, isTrue);
      expect(client.text('/cloud/a.txt'), 'local edit');
      expect(retried.workspace.entries.single.pendingUpload, isNull);
      expect(retried.workspace.error, isNull);
      expect(
        await Directory(p.join(root, workspace.id, 'scratch')).list().toList(),
        isEmpty,
      );
    });

    test('corrupted remote stage is never promoted', () async {
      final workspace = await stage();
      await edit(workspace, 'a.txt', 'local edit');
      client.corruptUpload = true;
      final result = await upload(workspace);
      expect(result.failures['a.txt'], contains('content check'));
      expect(client.text('/cloud/a.txt'), 'original');
      expect(client.copies, isEmpty);
    });

    test('lost commit acknowledgements reconcile without re-uploading and retain recovery warnings', () async {
      final workspace = await stage();
      await edit(workspace, 'a.txt', 'local edit');
      client.loseCommitReply = true;
      final interrupted = await upload(workspace);
      expect(interrupted.succeeded, isFalse);
      expect(client.text('/cloud/a.txt'), 'local edit');
      final uploadCount = client.uploads.length;
      client.loseCommitReply = false;
      service = TerminalWorkspaceService(rootDirectory: root);
      final recovered = await upload(workspace);
      expect(recovered.succeeded, isTrue);
      expect(client.uploads.length, uploadCount);
      expect(recovered.workspace.warnings, isNotEmpty);
      expect(recovered.workspace.warnings.join(), contains('.crisp-replaced-'));
      expect(await service.inspect(workspace.id), isEmpty);
      await service.list();
      expect(service.warnings, containsAll(recovered.workspace.warnings));
    });

    test('lost acknowledgement followed by further local edits preserves both reviews', () async {
      final workspace = await stage();
      await edit(workspace, 'a.txt', 'first reviewed edit');
      client.loseCommitReply = true;
      await upload(workspace);
      client.loseCommitReply = false;
      await edit(workspace, 'a.txt', 'next reviewed edit');
      final result = await upload(workspace);
      expect(result.succeeded, isTrue);
      expect(client.text('/cloud/a.txt'), 'next reviewed edit');
      expect(await service.inspect(workspace.id), isEmpty);
      expect(
        client.objects.values.any(
          (object) => utf8.decode(object.bytes) == 'original',
        ),
        isTrue,
      );
    });

    test(
      'recovers a terminated transaction with a verified original backup',
      () async {
        final workspace = await stage();
        await edit(workspace, 'a.txt', 'reviewed recovery');
        final changes = await service.inspect(workspace.id);
        const backup =
            '/cloud/.crisp-replaced-00000000-0000-4000-8000-000000000000.bak';
        final original = client.objects.remove('/cloud/a.txt')!;
        client.put(backup, utf8.decode(original.bytes));
        await _editManifest(root, workspace.id, (json) {
          final entry = (json['entries'] as List).single as Map;
          entry['pendingUpload'] = {
            'digest': changes.single.digest,
            'length': changes.single.size,
            'phase': 'backedUp',
            'destination': '/cloud/a.txt',
            'backupPath': backup,
            'backupCopyVersion': client.objects[backup]!.version,
          };
          json['status'] = 'uploading';
        });
        service = TerminalWorkspaceService(rootDirectory: root);
        final recovered = await upload(workspace);
        expect(recovered.succeeded, isTrue);
        expect(client.text('/cloud/a.txt'), 'reviewed recovery');
        expect(client.text(backup), 'original');
        expect(recovered.workspace.warnings.join(), contains(backup));
      },
    );

    test('unverified missing originals and altered backup versions remain conflicts', () async {
      final workspace = await stage();
      await edit(workspace, 'a.txt', 'local edits');
      client.objects.remove('/cloud/a.txt');
      final missing = await upload(workspace);
      expect(missing.failures['a.txt'], contains('changed since staging'));
      expect(client.uploads, isEmpty);
      const backup =
          '/cloud/.crisp-replaced-00000000-0000-4000-8000-000000000000.bak';
      client.put(backup, 'original');
      final review = (await service.inspect(workspace.id)).single;
      await _editManifest(root, workspace.id, (json) {
        ((json['entries'] as List).single as Map)['pendingUpload'] = {
          'digest': review.digest,
          'length': review.size,
          'phase': 'backedUp',
          'backupPath': backup,
          'backupCopyVersion': 'an-old-revision',
        };
      });
      final mismatched = await upload(workspace);
      expect(mismatched.succeeded, isFalse);
      expect(client.uploads, isEmpty);
      expect(client.text(backup), 'original');
    });

    test('account switching before and during upload prohibits replacement-account writes', () async {
      final workspace = await stage();
      await edit(workspace, 'a.txt', 'local edit');
      final changes = await service.inspect(workspace.id);
      client.account = 'another-user';
      await expectLater(
        upload(workspace, changes),
        throwsA(isA<TerminalWorkspaceException>()),
      );
      expect(client.uploads, isEmpty);
      client.account = 'user';
      client.afterUpload = () {
        client.account = 'another-user';
      };
      final interrupted = await upload(workspace, changes);
      expect(interrupted.succeeded, isFalse);
      expect(client.text('/cloud/a.txt'), 'original');
      expect(client.copies, isEmpty);
      expect(client.deletes, isEmpty);
      expect(interrupted.workspace.entries.single.pendingUpload, isNotNull);
      client.account = 'user';
      current = false;
      await expectLater(
        service.resumeStage(
          workspaceId: workspace.id,
          client: client,
          isCurrent: () => current,
        ),
        throwsA(isA<TerminalWorkspaceException>()),
      );
    });

    test(
      'cancellation and independent errors retain all unuploaded local files',
      () async {
        client.put('/cloud/b.txt', 'second');
        final workspace = await stage(['/cloud/a.txt', '/cloud/b.txt']);
        await edit(workspace, 'a.txt', 'first edit');
        await edit(workspace, 'b.txt', 'second edit');
        var cancelled = false;
        client.afterUpload = () {
          cancelled = true;
        };
        final result = await service.uploadReviewed(
          workspaceId: workspace.id,
          client: client,
          changes: await service.inspect(workspace.id),
          isCurrent: () => true,
          isCancelled: () => cancelled,
        );
        expect(result.failures.keys, containsAll(['a.txt', 'b.txt']));
        expect(client.text('/cloud/a.txt'), 'original');
        expect(client.text('/cloud/b.txt'), 'second');
        expect(client.uploads, hasLength(1));
      },
    );

    test('serialized service instances reject a review superseded by another uploader', () async {
      final workspace = await stage();
      await edit(workspace, 'a.txt', 'edited');
      final changes = await service.inspect(workspace.id);
      final second = TerminalWorkspaceService(rootDirectory: root);
      final first = upload(workspace, changes);
      final stale = second.uploadReviewed(
        workspaceId: workspace.id,
        client: client,
        changes: changes,
        isCurrent: () => true,
      );
      await expectLater(stale, throwsA(isA<TerminalWorkspaceException>()));
      expect((await first).succeeded, isTrue);
      expect(client.uploads, hasLength(1));
    });
  });

  test(
    'web stub reports unsupported and has no native workspace operations',
    () async {
      final unsupported = UnsupportedTerminalWorkspaceService();
      expect(
        createTerminalWorkspaceService(
          rootDirectory: root,
          maxEntries: 1,
          maxDepth: 1,
          maxTotalBytes: 1,
        ).isSupported,
        isFalse,
      );
      expect(unsupported.isSupported, isFalse);
      expect(unsupported.warnings, isEmpty);
      expect(await unsupported.list(), isEmpty);
      await expectLater(unsupported.load('any'), throwsUnsupportedError);
      await expectLater(unsupported.inspect('any'), throwsUnsupportedError);
      await expectLater(
        unsupported.resumeStage(
          workspaceId: 'any',
          client: client,
          isCurrent: () => true,
        ),
        throwsUnsupportedError,
      );
      await expectLater(
        unsupported.stage(
          client: client,
          remoteRoot: '/cloud',
          items: [],
          isCurrent: () => true,
        ),
        throwsUnsupportedError,
      );
      await expectLater(
        unsupported.uploadReviewed(
          workspaceId: 'any',
          client: client,
          changes: [],
          isCurrent: () => true,
        ),
        throwsUnsupportedError,
      );
    },
  );
}

class _DocumentsPath extends PathProviderPlatform {
  _DocumentsPath(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Future<void> _editManifest(
  String root,
  String id,
  void Function(Map<String, dynamic>) edit,
) async {
  final file = File(p.join(root, id, 'manifest.json'));
  final envelope = jsonDecode(await file.readAsString()) as Map;
  final json = Map<String, dynamic>.from(
    jsonDecode(envelope['payload'] as String) as Map,
  );
  edit(json);
  final payload = jsonEncode(json);
  await file.writeAsString(
    jsonEncode({
      'payload': payload,
      'sha256': sha256.convert(utf8.encode(payload)).toString(),
    }),
    flush: true,
  );
}

enum _Mode {
  conditionalCopy,
  conditionalMove,
  moveOnly,
  mixedUnsafe,
  unsupported,
}

class _CloudObject {
  _CloudObject(this.bytes, this.id, this.version);
  Uint8List bytes;
  final String id;
  final String version;
  bool link = false;
}

class _Cloud extends CloudStorageClient
    with CloudTransferOperations
    implements FreshCloudDirectoryReader {
  final objects = <String, _CloudObject>{};
  final directories = <String, String>{'/': 'root', '/cloud': 'cloud-dir'};
  final uploads = <String>[];
  final downloads = <String>[];
  final deletes = <String>[];
  final copies =
      <({String source, String destination, String? expectedVersion})>[];
  int revision = 0;
  int bufferedDownloads = 0;
  int bufferedUploads = 0;
  int cachedLists = 0;
  int legacyRenames = 0;
  bool authenticated = true;
  String account = 'user';
  String namespaceRoot = '/';
  _Mode mode = _Mode.conditionalCopy;
  bool omitVersions = false;
  bool omitSizes = false;
  bool failUpload = false;
  bool failCommit = false;
  bool failBackupDeletion = false;
  bool versionChangesOnMove = false;
  bool corruptUpload = false;
  bool loseCommitReply = false;
  String? failDownload;
  String? streamExtra;
  Object? sizeOverride;
  int? transformedStoredSize;
  String? rawNameOverride;
  Map<String, dynamic>? listingOverride;
  FutureOr<void> Function()? beforeUpload;
  FutureOr<void> Function()? afterUpload;
  FutureOr<void> Function(String path)? onDownloadChunk;
  FutureOr<void> Function(String source, String destination)? beforeCopy;

  void put(String path, String contents, {bool preserveMetadata = false}) {
    putBytes(path, utf8.encode(contents), preserveMetadata: preserveMetadata);
  }

  void putBytes(
    String path,
    List<int> contents, {
    bool preserveMetadata = false,
  }) {
    final old = objects[path];
    final bytes = Uint8List.fromList(contents);
    if (preserveMetadata && old != null) {
      old.bytes = bytes;
    } else {
      revision++;
      objects[path] = _CloudObject(bytes, 'object-$revision', 'rev-$revision');
    }
  }

  void mkdir(String path) => directories[path] = 'dir-${directories.length}';
  String text(String path) => utf8.decode(objects[path]!.bytes);
  Map<String, dynamic> metadata(String path) {
    final file = objects[path];
    return {
      'name': rawNameOverride ?? p.posix.basename(path),
      'uuid': file?.id ?? directories[path],
      if (file != null && !omitSizes)
        'size': sizeOverride ?? transformedStoredSize ?? file.bytes.length,
      if (file != null && transformedStoredSize != null)
        'downloadSize': file.bytes.length,
      if (file != null && !omitVersions) 'version': file.version,
      if (file != null) 'isSymlink': file.link,
    };
  }

  FileItem item(String path) => FileItem(
    name: p.posix.basename(path),
    path: path,
    uuid: objects[path]?.id ?? directories[path],
    isFolder: directories.containsKey(path),
    size: omitSizes
        ? null
        : transformedStoredSize ?? objects[path]?.bytes.length,
    metadata: metadata(path),
    isSymlink: objects[path]?.link,
  );

  @override
  StorageTransferCapabilities get transferCapabilities => switch (mode) {
    _Mode.conditionalCopy => const StorageTransferCapabilities(
      caseSensitivity: StorageCaseSensitivity.sensitive,
      nativeCopy: true,
      noReplaceCopy: true,
      conditionalCopy: true,
      conditionalDelete: true,
      boundedDownload: true,
      boundedUpload: true,
    ),
    _Mode.moveOnly => const StorageTransferCapabilities(
      caseSensitivity: StorageCaseSensitivity.sensitive,
      nativeMove: true,
      atomicMove: true,
      noReplaceMove: true,
      boundedDownload: true,
      boundedUpload: true,
    ),
    _Mode.conditionalMove => const StorageTransferCapabilities(
      caseSensitivity: StorageCaseSensitivity.sensitive,
      nativeMove: true,
      atomicMove: true,
      noReplaceMove: true,
      conditionalMove: true,
      conditionalDelete: true,
      boundedDownload: true,
      boundedUpload: true,
    ),
    _Mode.mixedUnsafe => const StorageTransferCapabilities(
      caseSensitivity: StorageCaseSensitivity.sensitive,
      nativeMove: true,
      atomicMove: true,
      noReplaceMove: true,
      nativeCopy: true,
      noReplaceCopy: true,
      conditionalCopy: true,
      conditionalDelete: true,
    ),
    _Mode.unsupported => const StorageTransferCapabilities(),
  };
  @override
  String get providerName => 'Workspace test provider';
  @override
  String get rootPath => namespaceRoot;
  @override
  bool get isAuthenticated => authenticated;
  @override
  String? get userId => account;
  @override
  String? get bucketId => 'bucket';
  @override
  Future<void> login(
    String email,
    String password, {
    String? twoFactorCode,
  }) async {
    authenticated = true;
  }

  @override
  Future<void> logout() async {
    authenticated = false;
  }

  @override
  Future<bool> is2faNeeded(String email) async => false;
  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async =>
      objects.containsKey(path) || directories.containsKey(path)
      ? metadata(path)
      : null;
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    cachedLists++;
    return readDirectoryForEdit(path);
  }

  @override
  Future<Map<String, dynamic>> readDirectoryForEdit(String path) async {
    if (!directories.containsKey(path)) {
      throw StateError('Directory unavailable');
    }
    return {
      'folders': directories.keys
          .where((entry) => entry != path && p.posix.dirname(entry) == path)
          .map(metadata)
          .toList(),
      'files': objects.keys
          .where((entry) => p.posix.dirname(entry) == path)
          .map(metadata)
          .toList(),
      ...?listingOverride,
    };
  }

  @override
  Future<void> createFolderPath(String path) async => mkdir(path);
  @override
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async* {
    downloads.add(remotePath);
    final bytes = List<int>.from(objects[remotePath]!.bytes);
    for (var offset = 0; offset < bytes.length; offset += 3) {
      final end = offset + 3 > bytes.length ? bytes.length : offset + 3;
      yield bytes.sublist(offset, end);
      await onDownloadChunk?.call(remotePath);
      if (failDownload == remotePath) throw StateError('download interrupted');
    }
    if (streamExtra != null) yield utf8.encode(streamExtra!);
  }

  @override
  Future<void> uploadStream(
    Stream<List<int>> dataStream,
    int length,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    final path = p.posix.join(targetPath, fileName);
    uploads.add(path);
    await beforeUpload?.call();
    final bytes = <int>[];
    await for (final chunk in dataStream) {
      bytes.addAll(chunk);
      putBytes(path, bytes);
      if (failUpload) throw StateError('upload interrupted');
    }
    if (bytes.isEmpty) put(path, '');
    if (corruptUpload) put(path, 'x' * bytes.length);
    expect(bytes.length, length);
    await afterUpload?.call();
  }

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    bufferedUploads++;
    throw UnsupportedError('Buffered upload should never be called');
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    bufferedDownloads++;
    throw UnsupportedError('Buffered download should never be called');
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async => throw UnsupportedError('Path download should never be called');
  @override
  Future<void> deletePath(String path) async {
    deletes.add(path);
    objects.remove(path);
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async =>
      throw UnsupportedError('Legacy moves should never be called');
  @override
  Future<void> renamePath(String path, String newName) async {
    legacyRenames++;
    throw UnsupportedError('Legacy renames should never be called');
  }

  @override
  Future<CloudTransferResult> copyToExact(
    String sourcePath,
    String destinationPath, {
    bool replace = false,
    String? expectedSourceVersion,
    String? expectedDestinationVersion,
    TransferCheckpoint? checkpoint,
    void Function(int, int)? onProgress,
  }) async {
    await checkpoint?.call();
    await beforeCopy?.call(sourcePath, destinationPath);
    final source = objects[sourcePath];
    if (source == null || expectedSourceVersion != source.version) {
      throw StateError('Conditional source version changed');
    }
    if (objects.containsKey(destinationPath) ||
        directories.containsKey(destinationPath)) {
      throw StateError('Destination exists');
    }
    expect(replace, isFalse);
    copies.add((
      source: sourcePath,
      destination: destinationPath,
      expectedVersion: expectedSourceVersion,
    ));
    if (failCommit && sourcePath.contains('.crisp-transfer-')) {
      throw StateError('Commit failed before promotion');
    }
    putBytes(destinationPath, source.bytes);
    final copied = objects[destinationPath]!;
    if (loseCommitReply && sourcePath.contains('.crisp-transfer-')) {
      throw StateError('Commit acknowledgement lost');
    }
    return CloudTransferResult(
      path: destinationPath,
      id: copied.id,
      version: copied.version,
      size: copied.bytes.length,
    );
  }

  @override
  Future<CloudTransferResult> moveToExact(
    String sourcePath,
    String destinationPath, {
    bool replace = false,
    String? expectedSourceVersion,
    String? expectedDestinationVersion,
    TransferCheckpoint? checkpoint,
  }) async {
    await checkpoint?.call();
    if (objects.containsKey(destinationPath) ||
        directories.containsKey(destinationPath)) {
      throw StateError('Destination exists');
    }
    expect(replace, isFalse);
    var source = objects[sourcePath]!;
    if (expectedSourceVersion != null &&
        expectedSourceVersion != source.version) {
      throw StateError('Move source version changed');
    }
    if (failCommit && sourcePath.contains('.crisp-transfer-')) {
      throw StateError('Commit failed before promotion');
    }
    objects.remove(sourcePath);
    if (versionChangesOnMove) {
      source = _CloudObject(source.bytes, source.id, 'move-${++revision}');
    }
    objects[destinationPath] = source;
    return CloudTransferResult(
      path: destinationPath,
      id: source.id,
      version: source.version,
      size: source.bytes.length,
    );
  }

  @override
  Future<void> deleteTransferFile(
    String path, {
    String? expectedVersion,
  }) async {
    if (failBackupDeletion && path.contains('.crisp-replaced-')) {
      throw StateError('Backup cleanup failed');
    }
    if (objects[path]?.version != expectedVersion) {
      throw StateError('Delete version changed');
    }
    deletes.add(path);
    objects.remove(path);
  }
}
