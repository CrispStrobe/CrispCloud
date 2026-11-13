import 'dart:io';

import 'package:crisp_cloud/services/archive_directory_sync_service.dart';
import 'package:crisp_cloud/services/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_hfs_writer.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_streaming_writer.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/archive_directory_sync_fixture.dart';
import 'support/archive_endpoint_backend.dart';

final _modified = DateTime.utc(2026, 11, 13, 1, 2, 3);
String _hfs(String path) => '/${normalizeHfsArchivePath(path)}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  });

  late Directory directory;
  late LocalOperationBackend local;
  late ArchivePublicationJournal journal;
  setUp(() async {
    final temporary = await Directory.systemTemp.createTemp(
      'dmg-transfer-names-',
    );
    directory = Directory(await temporary.resolveSymbolicLinks());
    local = LocalOperationBackend(LocalFileService(), isCurrent: () => true);
    journal = ArchivePublicationJournal(storage: MemoryFileCollectionStorage());
    addTearDown(() => directory.delete(recursive: true));
  });

  Future<(File, ArchiveWorkspace)> createDmg(
    Map<String, List<int>> files,
  ) async {
    final file = File(p.join(directory.path, 'target.dmg'));
    final output = await file.open(mode: FileMode.writeOnly);
    try {
      await writeStreamingArchiveEntries(
        ArchiveEndpointFormat.dmg,
        [
          for (final entry in files.entries)
            ArchiveWriteEntry(
              path: entry.key,
              isDirectory: false,
              size: entry.value.length,
              modified: _modified,
              mode: 0x1a4,
              readChunks: () => Stream.value(entry.value),
            ),
        ],
        sink: (bytes) async {
          await output.writeFrom(bytes);
        },
        maxOutputBytes: kArchiveStreamingLimit,
      );
      await output.flush();
    } finally {
      await output.close();
    }
    final workspace = await ArchiveWorkspace.open(
      local,
      (await local.stat(file.path))!,
      journal: journal,
    );
    addTearDown(workspace.close);
    expect(workspace.canUpdate, isTrue, reason: workspace.updateSupport);
    return (file, workspace);
  }

  Future<ArchiveWorkspace> reopen(File file) async {
    final workspace = await ArchiveWorkspace.open(
      local,
      (await local.stat(file.path))!,
      journal: journal,
    );
    addTearDown(workspace.close);
    return workspace;
  }

  test('DMG sync matches NFC source to NFD target and removes only selected archive rows', () async {
    final (target, workspace) = await createDmg({
      'données/café.txt': [1],
      'données/égal.txt': [4],
      'données/retiré.txt': [9],
      'données/Case.txt': [5],
    });
    final sourceRoot = p.join(directory.path, 'source');
    await Directory(sourceRoot).create();
    final sourceCafe = await writeDirectorySyncSource(sourceRoot, 'café.txt', [
      2,
    ]);
    await writeDirectorySyncSource(sourceRoot, 'égal.txt', [4]);
    await writeDirectorySyncSource(sourceRoot, 'case.txt', [6]);
    final service = ArchiveDirectorySyncService(
      source: local,
      sourceDirectory: sourceRoot,
      destination: workspace,
      destinationDirectory: '/données',
    );
    addTearDown(service.close);
    final original = await target.readAsBytes();
    final plan = await service.compare(control: FileOperationControl());
    final removed = normalizeHfsArchivePath('retiré.txt');
    expect(
      {for (final row in plan.rows) row.relativePath: row.status},
      {
        'café.txt': ArchiveDirectorySyncStatus.changed,
        'égal.txt': ArchiveDirectorySyncStatus.equal,
        'case.txt': ArchiveDirectorySyncStatus.sourceOnly,
        'Case.txt': ArchiveDirectorySyncStatus.archiveOnly,
        removed: ArchiveDirectorySyncStatus.archiveOnly,
      },
    );
    final changed = plan.rows.singleWhere(
      (row) => row.relativePath == 'café.txt',
    );
    expect(changed.source!.path, sourceCafe.path);
    expect(changed.archive!.path, _hfs('données/café.txt'));
    final review = await service.stage(
      plan,
      copyPaths: {'café.txt', 'case.txt'},
      removePaths: {removed},
      allowRemovals: true,
      control: FileOperationControl(),
    );
    expect(await target.readAsBytes(), original);
    final result = await service.commit(reviewed: review);
    expect(result.copiedPaths, ['café.txt', 'case.txt']);
    expect(result.removedPaths, [removed]);
    final published = await reopen(target);
    expect(await published.read('/données/café.txt'), [2]);
    expect(await published.read('/données/égal.txt'), [4]);
    expect(await published.read('/données/Case.txt'), [5]);
    expect(await published.read('/données/case.txt'), [6]);
    expect(await published.backend.stat('/données/retiré.txt'), isNull);
    expect(await sourceCafe.readAsBytes(), [2]);
  });

  test(
    'DMG sync refuses distinct source names with one HFS destination key before staging',
    () async {
      final (target, workspace) = await createDmg({
        'keep.txt': [9],
      });
      final sourceRoot = p.join(directory.path, 'source');
      await Directory(sourceRoot).create();
      await writeDirectorySyncSource(sourceRoot, 'café.txt', [1]);
      await writeDirectorySyncSource(sourceRoot, 'cafe\u0301.txt', [2]);
      final service = ArchiveDirectorySyncService(
        source: local,
        sourceDirectory: sourceRoot,
        destination: workspace,
      );
      addTearDown(service.close);
      final original = await target.readAsBytes();
      await expectLater(
        service.compare(control: FileOperationControl()),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('collide'),
          ),
        ),
      );
      expect(workspace.dirty, isFalse);
      expect(await target.readAsBytes(), original);
      expect(await File(p.join(sourceRoot, 'café.txt')).readAsBytes(), [1]);
      expect(await File(p.join(sourceRoot, 'cafe\u0301.txt')).readAsBytes(), [
        2,
      ]);
    },
    skip: Platform.isMacOS
        ? 'The default macOS filesystem already aliases NFC/NFD filenames.'
        : false,
  );

  for (final conflict in [
    FileConflictPolicy.replace,
    FileConflictPolicy.skip,
    FileConflictPolicy.keepBoth,
  ]) {
    test(
      'DMG import ${conflict.name} previews canonical conflicts and publishes new NFC names',
      () async {
        final (target, workspace) = await createDmg({
          'café.txt': [1],
        });
        final endpoint = ArchiveEndpoint.fromWorkspace(workspace);
        addTearDown(endpoint.close);
        final source = ArchiveEndpointTestBackend()
          ..put('/input/café.txt', [7])
          ..put('/input/cafe\u0301.txt', [99])
          ..put('/input/créé.txt', [8]);
        final plan = await endpoint.prepareImport(
          source: source,
          files: [
            (await source.stat('/input/café.txt'))!,
            (await source.stat('/input/créé.txt'))!,
          ],
          conflict: conflict,
          moveSources: conflict == FileConflictPolicy.replace,
        );
        expect(plan.canStage, isTrue, reason: plan.errors.join('\n'));
        final collision = plan.entries.singleWhere(
          (entry) => entry.source.name == 'café.txt',
        );
        if (conflict == FileConflictPolicy.keepBoth) {
          expect(collision.existing, isNull);
          expect(
            workspace.backend.pathKey(collision.destination),
            isNot(_hfs('café.txt')),
          );
        } else {
          expect(collision.existing!.path, _hfs('café.txt'));
          expect(collision.destination, _hfs('café.txt'));
        }
        final original = await target.readAsBytes();
        final review = await endpoint.stageImport(
          plan,
          control: FileOperationControl(),
        );
        expect(await target.readAsBytes(), original);
        final result = await endpoint.commit(reviewed: review);
        expect(
          result.publishedFiles,
          conflict == FileConflictPolicy.skip ? 1 : 2,
        );
        final published = await reopen(target);
        expect(
          await published.read('/café.txt'),
          conflict == FileConflictPolicy.replace ? [7] : [1],
        );
        expect(await published.read('/créé.txt'), [8]);
        expect(
          published.list().map((file) => file.path),
          contains(_hfs('créé.txt')),
        );
        if (conflict == FileConflictPolicy.keepBoth) {
          expect(await published.read(collision.destination), [7]);
          expect(published.list(), hasLength(3));
        } else {
          expect(published.list(), hasLength(2));
        }
        // Destination canonicalization must never fold source identity: the
        // unselected NFD source remains even when the selected NFC file moves.
        expect(source.files['/input/cafe\u0301.txt'], [99]);
        if (conflict == FileConflictPolicy.replace) {
          expect(result.removedSources, 2);
          expect(source.files.containsKey('/input/café.txt'), isFalse);
          expect(source.files.containsKey('/input/créé.txt'), isFalse);
        } else {
          expect(result.removedSources, 0);
          expect(source.files['/input/café.txt'], [7]);
        }
      },
    );
  }

  test('DMG import detects canonical source collisions in preview and Keep both reserves distinct keys', () async {
    final (target, workspace) = await createDmg({});
    final endpoint = ArchiveEndpoint.fromWorkspace(workspace);
    addTearDown(endpoint.close);
    final source = ArchiveEndpointTestBackend()
      ..put('/input/café.txt', [1])
      ..put('/input/cafe\u0301.txt', [2])
      ..put('/input/Case.txt', [3])
      ..put('/input/case.txt', [4]);
    final files = [
      for (final path in source.files.keys) (await source.stat(path))!,
    ];
    final original = await target.readAsBytes();
    final ambiguous = await endpoint.prepareImport(
      source: source,
      files: files,
      conflict: FileConflictPolicy.replace,
    );
    expect(ambiguous.canStage, isFalse);
    expect(
      ambiguous.errors.join('\n'),
      contains('Several source items target'),
    );
    expect(workspace.dirty, isFalse);
    expect(await target.readAsBytes(), original);
    final plan = await endpoint.prepareImport(
      source: source,
      files: files,
      conflict: FileConflictPolicy.keepBoth,
    );
    expect(plan.canStage, isTrue, reason: plan.errors.join('\n'));
    expect({
      for (final entry in plan.entries)
        workspace.backend.pathKey(entry.destination),
    }, hasLength(4));
    final review = await endpoint.stageImport(
      plan,
      control: FileOperationControl(),
    );
    await endpoint.commit(reviewed: review);
    final published = await reopen(target);
    expect(published.list(), hasLength(4));
    for (final entry in plan.entries) {
      expect(
        await published.read(entry.destination),
        source.files[entry.source.path],
      );
    }
    expect(await published.read('/Case.txt'), [3]);
    expect(await published.read('/case.txt'), [4]);
    expect(source.files, hasLength(4));
  });
}
