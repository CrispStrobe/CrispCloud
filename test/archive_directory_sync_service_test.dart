import 'dart:io';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_container_publisher.dart';
import 'package:crisp_cloud/services/archive_directory_snapshot.dart';
import 'package:crisp_cloud/services/archive_directory_sync_service.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/archive_directory_sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  });
  late Directory temp;
  late String sourceRoot;
  late File target;
  late ArchiveDirectoryTestBackend backend;
  late ArchivePublicationJournal journal;
  late ArchiveWorkspace workspace;
  late ArchiveDirectorySyncService service;
  late bool current;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('archive-directory-sync-');
    sourceRoot = '${temp.path}/source';
    await Directory(sourceRoot).create();
    await Directory('${temp.path}/destination').create();
    current = true;
    backend = ArchiveDirectoryTestBackend(current: () => current);
    journal = ArchivePublicationJournal(storage: MemoryFileCollectionStorage());
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> open({
    Map<String, List<int>> source = const {
      'new': [1],
    },
    Set<String> sourceDirectories = const {},
    Map<String, List<int>> archive = const {
      'keep': [9],
    },
    Set<String> archiveDirectories = const {},
    koni.ArchiveWriteFormat format = const koni.ZipWriteFormat(),
    String name = 'target.zip',
    String destinationDirectory = '/',
    String? password,
    bool encryptNames = false,
  }) async {
    for (final item in source.entries) {
      await writeDirectorySyncSource(sourceRoot, item.key, item.value);
    }
    for (final item in sourceDirectories) {
      await Directory('$sourceRoot/$item').create(recursive: true);
    }
    target = File('${temp.path}/destination/$name');
    await target.writeAsBytes(
      await createDirectorySyncArchive(
        archive,
        directories: archiveDirectories,
        format: format,
        password: password,
        encryptNames: encryptNames,
      ),
      flush: true,
    );
    workspace = await ArchiveWorkspace.open(
      backend,
      (await backend.stat(target.path))!,
      password: password,
      journal: journal,
    );
    addTearDown(workspace.close);
    service = ArchiveDirectorySyncService(
      source: backend,
      sourceDirectory: sourceRoot,
      destination: workspace,
      destinationDirectory: destinationDirectory,
    );
    addTearDown(service.close);
  }

  Future<ArchiveDirectorySyncPlan> compare() =>
      service.compare(control: FileOperationControl());
  Set<String> updates(ArchiveDirectorySyncPlan plan) => {
    for (final row in plan.rows)
      if (row.status == ArchiveDirectorySyncStatus.sourceOnly ||
          row.status == ArchiveDirectorySyncStatus.changed)
        row.relativePath,
  };
  Set<String> archiveOnly(ArchiveDirectorySyncPlan plan) => {
    for (final row in plan.rows)
      if (row.status == ArchiveDirectorySyncStatus.archiveOnly)
        row.relativePath,
  };
  Future<ArchiveDirectorySyncReview> stage(
    ArchiveDirectorySyncPlan plan, {
    Set<String>? copies,
    Set<String> removals = const {},
    bool allowRemovals = false,
  }) => service.stage(
    plan,
    copyPaths: copies ?? updates(plan),
    removePaths: removals,
    allowRemovals: allowRemovals,
    control: FileOperationControl(),
  );
  Future<ViewerArchive> read({String? password}) async {
    final reader = await openViewerArchive(
      await target.readAsBytes(),
      name: target.uri.pathSegments.last,
      password: password,
    );
    addTearDown(reader.close);
    return reader;
  }

  Future<Map<String, List<int>>> contents({String? password}) async {
    final reader = await read(password: password);
    return {
      for (final member in reader.members.where((member) => member.isFile))
        member.name: await reader.readMember(member),
    };
  }

  test('complete comparison distinguishes equal new changed archive-only and empty entries without mutation', () async {
    await open(
      source: {
        'equal': [1],
        'changed': [2],
        'new/deep': [3],
      },
      sourceDirectories: {'empty'},
      archive: {
        'equal': [1],
        'changed': [9],
        'old': [8],
      },
    );
    final original = await target.readAsBytes();
    final revision = workspace.revision;
    final plan = await compare();
    expect(
      {for (final row in plan.rows) row.relativePath: row.status},
      {
        'changed': ArchiveDirectorySyncStatus.changed,
        'empty': ArchiveDirectorySyncStatus.sourceOnly,
        'equal': ArchiveDirectorySyncStatus.equal,
        'new': ArchiveDirectorySyncStatus.sourceOnly,
        'new/deep': ArchiveDirectorySyncStatus.sourceOnly,
        'old': ArchiveDirectorySyncStatus.archiveOnly,
      },
    );
    final equal = plan.rows.singleWhere((row) => row.relativePath == 'equal');
    expect(equal.sourceSha256, equal.archiveSha256);
    expect(equal.sourceSha256, hasLength(64));
    expect(plan.errors, isEmpty);
    expect(plan.canStage, isTrue);
    expect(workspace.revision, revision);
    expect(workspace.dirty, isFalse);
    expect(await target.readAsBytes(), original);
  });

  for (final tar in [false, true]) {
    test(
      '${tar ? 'TAR' : 'ZIP'} publishes selected updates while preserving archive-only content and equal metadata',
      () async {
        await open(
          source: {
            'equal': [1],
            'changed': [2],
            'new/deep': [3],
          },
          sourceDirectories: {'empty'},
          archive: {
            'equal': [1],
            'changed': [9],
            'old': [8],
          },
          format: tar
              ? const koni.TarWriteFormat()
              : const koni.ZipWriteFormat(),
          name: tar ? 'target.tar' : 'target.zip',
        );
        final original = await target.readAsBytes();
        final sourceSnapshot = await captureArchiveDirectorySnapshot(
          backend,
          sourceRoot,
        );
        final plan = await compare();
        final revision = workspace.revision;
        final review = await stage(plan);
        expect(plan.isConsumed, isTrue);
        expect(workspace.revision, revision + 1);
        expect(await target.readAsBytes(), original);
        expect(
          review.archiveReview.changes.any((change) => change.path == 'equal'),
          isFalse,
        );
        final result = await service.commit(reviewed: review);
        expect(result.receipt.record.directoryDependency, isNotNull);
        expect(result.receipt.record.toJson()['version'], 3);
        expect(result.removedPaths, isEmpty);
        expect(await contents(), {
          'equal': [1],
          'changed': [2],
          'new/deep': [3],
          'old': [8],
        });
        final reader = await read();
        expect(
          reader.members
                  .singleWhere((member) => member.name == 'equal')
                  .posixMode! &
              0xfff,
          0x1a0,
        );
        expect(
          reader.members.any(
            (member) =>
                !member.isFile &&
                member.name.replaceAll(RegExp(r'/+$'), '') == 'empty',
          ),
          isTrue,
        );
        await verifyArchiveDirectoryDependency(
          backend,
          sourceSnapshot.dependency,
        );
      },
    );
  }

  test('updates and explicit mirror removals stay inside the captured archive subdirectory', () async {
    await open(
      source: {
        'new': [1],
      },
      archive: {
        'scope/old': [2],
        'outside': [9],
      },
      destinationDirectory: '/scope',
    );
    final plan = await compare();
    expect(plan.rows.map((row) => row.relativePath), ['new', 'old']);
    final review = await stage(plan, removals: {'old'}, allowRemovals: true);
    expect(review.removedPaths, ['old']);
    expect(
      review.archiveReview.changes.any((change) => change.path == 'outside'),
      isFalse,
    );
    await service.commit(reviewed: review);
    expect(await contents(), {
      'scope/new': [1],
      'outside': [9],
    });
  });

  test(
    'selected folder rows never implicitly copy unchecked descendants',
    () async {
      await open(
        source: {
          'folder/child': [1],
        },
        sourceDirectories: {'empty'},
      );
      final plan = await compare();
      final review = await stage(plan, copies: {'folder', 'empty'});
      await service.commit(reviewed: review);
      expect(await contents(), {
        'keep': [9],
      });
      final reader = await read();
      expect(
        reader.members
            .where((member) => !member.isFile)
            .map((member) => member.name.replaceAll(RegExp(r'/+$'), '')),
        containsAll(['folder', 'empty']),
      );
    },
  );

  test('removals require explicit permission and unchecked descendants remain intact', () async {
    await open(
      source: {},
      archive: {
        'old/a': [1],
        'old/b': [2],
        'keep': [9],
      },
    );
    final plan = await compare();
    final revision = workspace.revision;
    await expectLater(
      stage(plan, copies: {}, removals: {'old/a'}),
      throwsStateError,
    );
    await expectLater(
      stage(plan, copies: {}, removals: {'old', 'old/a'}, allowRemovals: true),
      throwsStateError,
    );
    expect(plan.isConsumed, isFalse);
    expect(workspace.revision, revision);
    expect(workspace.dirty, isFalse);
    final review = await stage(
      plan,
      copies: {},
      removals: {'old/a'},
      allowRemovals: true,
    );
    await service.commit(reviewed: review);
    expect(await contents(), {
      'old/b': [2],
      'keep': [9],
    });
  });

  test('explicit mirror removes complete selected directory trees and empty members', () async {
    await open(
      source: {
        'new': [7],
      },
      archive: {
        'old/a': [1],
        'old/b': [2],
      },
      archiveDirectories: {'empty'},
    );
    final plan = await compare();
    final review = await stage(
      plan,
      removals: archiveOnly(plan),
      allowRemovals: true,
    );
    await service.commit(reviewed: review);
    expect(await contents(), {
      'new': [7],
    });
    expect((await read()).members.where((member) => !member.isFile), isEmpty);
  });

  test('equal-only comparison and unchecked archive-only rows do not rewrite the archive', () async {
    await open(
      source: {
        'equal': [1],
      },
      archive: {
        'equal': [1],
        'keep': [2],
      },
    );
    final original = await target.readAsBytes();
    final plan = await compare();
    expect(updates(plan), isEmpty);
    await expectLater(stage(plan), throwsStateError);
    expect(plan.isConsumed, isFalse);
    expect(workspace.dirty, isFalse);
    expect(await target.readAsBytes(), original);
    expect(backend.moves, isEmpty);
  });

  test(
    'type conflicts block staging without destructive replacement',
    () async {
      await open(
        source: {
          'conflict': [1],
          'new': [2],
        },
        archive: {
          'conflict/child': [9],
        },
      );
      final original = await target.readAsBytes();
      final plan = await compare();
      expect(plan.hasTypeConflicts, isTrue);
      expect(plan.canStage, isFalse);
      await expectLater(stage(plan, copies: {'new'}), throwsStateError);
      expect(workspace.dirty, isFalse);
      expect(await target.readAsBytes(), original);
    },
  );

  for (final change in [
    'selected bytes',
    'new source path',
    'removed source path',
    'unselected bytes',
  ]) {
    test('$change after comparison prevents atomic staging', () async {
      await open(
        source: {
          'new': [1],
          'unchosen': [2],
        },
      );
      final plan = await compare();
      final original = await target.readAsBytes();
      switch (change) {
        case 'selected bytes':
          await File('$sourceRoot/new').writeAsBytes([8]);
        case 'new source path':
          await writeDirectorySyncSource(sourceRoot, 'appeared', [8]);
        case 'removed source path':
          await File('$sourceRoot/unchosen').delete();
        case 'unselected bytes':
          await File('$sourceRoot/unchosen').writeAsBytes([8]);
      }
      await expectLater(stage(plan, copies: {'new'}), throwsStateError);
      expect(plan.isConsumed, isFalse);
      expect(workspace.dirty, isFalse);
      expect(await target.readAsBytes(), original);
      expect(backend.moves, isEmpty);
    });
  }

  test(
    'changes to an equal source file after review prevent publication',
    () async {
      await open(
        source: {
          'new': [1],
          'equal': [2],
        },
        archive: {
          'equal': [2],
          'old': [8],
        },
      );
      final plan = await compare();
      final review = await stage(plan, removals: {'old'}, allowRemovals: true);
      final original = await target.readAsBytes();
      await File('$sourceRoot/equal').writeAsBytes([7]);
      await expectLater(service.commit(reviewed: review), throwsStateError);
      expect(await target.readAsBytes(), original);
      expect(backend.moves, isEmpty);
    },
  );

  test(
    'a source appearance after mirror review cannot authorize stale deletion',
    () async {
      await open(
        source: {},
        archive: {
          'appeared': [1],
          'keep': [9],
        },
      );
      final plan = await compare();
      final review = await stage(
        plan,
        copies: {},
        removals: {'appeared'},
        allowRemovals: true,
      );
      await writeDirectorySyncSource(sourceRoot, 'appeared', [2]);
      await expectLater(service.commit(reviewed: review), throwsStateError);
      expect(await contents(), {
        'appeared': [1],
        'keep': [9],
      });
      expect(backend.moves, isEmpty);
    },
  );

  test('changed destination physical file is not overwritten', () async {
    await open();
    final plan = await compare();
    final review = await stage(plan);
    final external = await createDirectorySyncArchive({
      'external': [7],
    });
    await target.writeAsBytes(external, flush: true);
    await expectLater(service.commit(reviewed: review), throwsStateError);
    expect(await target.readAsBytes(), external);
    expect(backend.moves, isEmpty);
  });

  test('changed destination draft and a different plan cannot substitute reviewed actions', () async {
    await open();
    final old = await compare();
    final plan = await compare();
    await expectLater(stage(old), throwsStateError);
    final review = await stage(plan);
    workspace.createDirectory('/later');
    await expectLater(service.commit(reviewed: review), throwsStateError);
    expect(backend.moves, isEmpty);
  });

  test('ordinary Save, wrong owner, and discard cannot bypass the bound directory dependency', () async {
    await open();
    final review = await stage(await compare());
    final dependency = (await captureArchiveDirectorySnapshot(
      backend,
      sourceRoot,
    )).dependency;
    await expectLater(
      workspace.save(reviewed: review.archiveReview),
      throwsStateError,
    );
    await expectLater(
      workspace.save(
        reviewed: review.archiveReview,
        directoryDependency: dependency,
        directorySyncAuthority: Object(),
      ),
      throwsStateError,
    );
    workspace.discardDraft();
    workspace.remove(['/keep']);
    await expectLater(workspace.save(), throwsStateError);
    expect(await contents(), {
      'keep': [9],
    });
    expect(backend.moves, isEmpty);
  });

  test(
    'cancellation before staging or publication preserves physical originals',
    () async {
      await open();
      final plan = await compare();
      final cancelled = FileOperationControl()..cancel();
      await expectLater(
        service.stage(plan, copyPaths: {'new'}, control: cancelled),
        throwsA(isA<FileOperationCancelled>()),
      );
      expect(plan.isConsumed, isFalse);
      final review = await stage(plan);
      await expectLater(
        service.commit(reviewed: review, isCancelled: () => true),
        throwsA(isA<FileOperationCancelled>()),
      );
      expect(await contents(), {
        'keep': [9],
      });
      expect(backend.moves, isEmpty);
    },
  );

  test(
    'late source change retains v3 recovery and refuses stale finish',
    () async {
      await open();
      final review = await stage(await compare());
      final original = await target.readAsBytes();
      var changed = false;
      await expectLater(
        service.commit(
          reviewed: review,
          onPhase: (phase) {
            if (!changed && phase == ArchivePublicationPhase.installing) {
              changed = true;
              File('$sourceRoot/appeared').writeAsBytesSync([8], flush: true);
            }
          },
        ),
        throwsA(isA<ArchivePublicationException>()),
      );
      expect(changed, isTrue);
      expect(await target.readAsBytes(), original);
      final pending = workspace.pendingPublication!;
      expect(pending.directoryDependency, isNotNull);
      expect(pending.toJson()['version'], 3);
      final publisher = ArchiveContainerPublisher(backend, journal);
      await expectLater(
        publisher.recover(pending, ArchiveRecoveryAction.finishPublication),
        throwsA(isA<ArchivePublicationException>()),
      );
      await publisher.recover(
        publisher.activeRecord!,
        ArchiveRecoveryAction.restoreOriginal,
      );
      expect(await target.readAsBytes(), original);
      expect(await File('$sourceRoot/appeared').readAsBytes(), [8]);
    },
  );

  test(
    'independent encrypted destination policy and password remain intact',
    () async {
      await open(
        format: const koni.SevenZWriteFormat(),
        name: 'target.7z',
        password: 'destination-secret',
        encryptNames: true,
      );
      final review = await stage(await compare());
      final result = await service.commit(reviewed: review);
      expect(workspace.encrypted, isTrue);
      expect(workspace.encryptNames, isTrue);
      expect(await contents(password: 'destination-secret'), {
        'new': [1],
        'keep': [9],
      });
      expect(
        '${result.receipt.record.toJson()}',
        isNot(contains('destination-secret')),
      );
      expect('${result.receipt.record.toJson()}', isNot(contains('/new')));
    },
  );

  test('mirror cannot remove the last protected ZIP payload', () async {
    await open(
      source: {},
      archive: {
        'protected': [1],
      },
      password: 'secret',
    );
    final original = await target.readAsBytes();
    final plan = await compare();
    await expectLater(
      stage(plan, copies: {}, removals: {'protected'}, allowRemovals: true),
      throwsStateError,
    );
    expect(plan.isConsumed, isTrue);
    expect(workspace.dirty, isFalse);
    expect(await target.readAsBytes(), original);
    expect(backend.moves, isEmpty);
  });

  test(
    'privileged new source permissions are refused before any draft adoption',
    () async {
      await open();
      final chmod = await Process.run('chmod', ['4755', '$sourceRoot/new']);
      expect(chmod.exitCode, 0);
      final plan = await compare();
      await expectLater(stage(plan), throwsStateError);
      expect(plan.isConsumed, isFalse);
      expect(workspace.dirty, isFalse);
      expect(backend.moves, isEmpty);
    },
    skip: !Platform.isLinux && !Platform.isMacOS,
  );

  test(
    'nested archive destinations stay outside the synchronization contract',
    () async {
      await open(
        archive: {
          'inner.zip': await createDirectorySyncArchive({
            'keep': [9],
          }),
        },
      );
      final nested = await ArchiveWorkspace.openNested(
        backend,
        (await backend.stat(target.path))!,
        ['inner.zip'],
        journal: journal,
      );
      addTearDown(nested.close);
      final sync = ArchiveDirectorySyncService(
        source: backend,
        sourceDirectory: sourceRoot,
        destination: nested,
      );
      addTearDown(sync.close);
      expect(sync.unsupportedReason, contains('top-level'));
      await expectLater(
        sync.compare(control: FileOperationControl()),
        throwsStateError,
      );
      expect(backend.moves, isEmpty);
    },
  );

  test(
    'a stale captured source session cannot publish a prepared synchronization',
    () async {
      await open();
      final review = await stage(await compare());
      current = false;
      await expectLater(service.commit(reviewed: review), throwsStateError);
      current = true;
      expect(await contents(), {
        'keep': [9],
      });
      expect(backend.moves, isEmpty);
    },
  );
}
