import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_hfs_writer.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_streaming_writer.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/native_file_primitives.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/dmg_fixture.dart';
import 'support/hfs_fixture.dart';

final _modified = DateTime.utc(2026, 11, 13, 1, 2, 3);

ArchiveWriteEntry _entry(String path, List<int> bytes) => ArchiveWriteEntry(
  path: path,
  isDirectory: false,
  size: bytes.length,
  modified: _modified,
  mode: 0x1a4,
  readChunks: () => Stream<List<int>>.value(bytes),
);

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
    final temporary = await Directory.systemTemp.createTemp('crisp-dmg-names-');
    directory = Directory(await temporary.resolveSymbolicLinks());
    local = LocalOperationBackend(LocalFileService(), isCurrent: () => true);
    journal = ArchivePublicationJournal(storage: MemoryFileCollectionStorage());
    addTearDown(() => directory.delete(recursive: true));
  });

  Future<File> writeArchive(
    String suffix,
    ArchiveEndpointFormat format,
    List<ArchiveWriteEntry> entries,
  ) async {
    final file = File(p.join(directory.path, 'names.$suffix'));
    final output = await file.open(mode: FileMode.writeOnly);
    try {
      await writeStreamingArchiveEntries(
        format,
        entries,
        sink: (bytes) async {
          await output.writeFrom(bytes);
        },
        maxOutputBytes: kArchiveStreamingLimit,
      );
      await output.flush();
    } finally {
      await output.close();
    }
    return file;
  }

  Future<ArchiveWorkspace> open(File file) async {
    final workspace = await ArchiveWorkspace.open(
      local,
      (await local.stat(file.path))!,
      journal: journal,
    );
    addTearDown(workspace.close);
    return workspace;
  }

  test('DMG NFC edits and imports use the HFS namespace before and after publication', () async {
    final file = await writeArchive('dmg', ArchiveEndpointFormat.dmg, [
      _entry('original.txt', [1, 2]),
    ]);
    final workspace = await open(file);
    expect(workspace.canUpdate, isTrue, reason: workspace.updateSupport);
    workspace.rename('/original.txt', 'café.txt');
    workspace.replace('/café.txt', Uint8List.fromList([9, 8]));
    workspace.createDirectory('/données', modified: _modified, mode: 0x1ed);
    final afterDirectory = workspace.revision;
    workspace.createDirectory('/donne\u0301es');
    expect(workspace.revision, afterDirectory);
    workspace.replace(
      '/données/édité.txt',
      Uint8List.fromList([7]),
      modified: _modified,
    );
    final imported = File(p.join(directory.path, 'résumé.txt'));
    await imported.writeAsBytes([4, 5, 6]);
    await imported.setLastModified(_modified);
    await workspace.addFiles(local, [
      (await local.stat(imported.path))!,
    ], directory: '/données');
    workspace.applyImport([
      ArchiveWorkspaceImport(
        '/données/équipe.txt',
        isFolder: false,
        bytes: Uint8List.fromList([3, 2, 1]),
        modified: _modified,
        mode: 0x1a4,
      ),
    ], expectedRevision: workspace.revision);
    final beforeEquivalentRename = workspace.revision;
    workspace.rename('/cafe\u0301.txt', 'café.txt');
    expect(workspace.revision, beforeEquivalentRename);
    expect(await workspace.read('/café.txt'), [9, 8]);
    expect(await workspace.read('/cafe\u0301.txt'), [9, 8]);
    expect(
      workspace.backend.pathKey('/données/édité.txt'),
      workspace.backend.pathKey('/donne\u0301es/e\u0301dite\u0301.txt'),
    );
    expect(
      (await workspace.backend.stat('/données/édité.txt'))?.path,
      '/${normalizeHfsArchivePath('données/édité.txt')}',
    );
    expect(
      (await workspace.backend.readMetadata('/café.txt')).mode! & 0xfff,
      0x1a4,
    );
    expect(
      workspace.list('/données').map((item) => item.name).toSet(),
      {
        'édité.txt',
        'résumé.txt',
        'équipe.txt',
      }.map(normalizeHfsArchivePath).toSet(),
    );
    await workspace.save(reviewed: await workspace.review());
    await workspace.close();

    final reopened = await open(file);
    expect(reopened.canUpdate, isTrue, reason: reopened.updateSupport);
    expect(reopened.list().map((item) => item.name).toSet(), {
      normalizeHfsArchivePath('café.txt'),
      normalizeHfsArchivePath('données'),
    });
    expect(await reopened.read('/café.txt'), [9, 8]);
    expect(await reopened.read('/données/édité.txt'), [7]);
    expect(await reopened.read('/données/résumé.txt'), [4, 5, 6]);
    expect(await reopened.read('/données/équipe.txt'), [3, 2, 1]);
    reopened.remove(['/données/équipe.txt']);
    expect(
      await reopened.backend.stat('/donne\u0301es/e\u0301quipe.txt'),
      isNull,
    );
  }, skip: !supportsNativeExclusiveRename);

  test(
    'DMG equivalent-name conflicts and unsafe paths leave the draft unchanged',
    () async {
      final file = await writeArchive('dmg', ArchiveEndpointFormat.dmg, [
        _entry('café.txt', [1]),
        _entry('other.txt', [2]),
      ]);
      final workspace = await open(file);
      final original = await file.readAsBytes();
      final revision = workspace.revision;
      expect(
        () => workspace.rename('/other.txt', 'café.txt'),
        throwsStateError,
      );
      expect(() => workspace.createDirectory('/café.txt'), throwsStateError);
      expect(
        () => workspace.applyImport([
          ArchiveWorkspaceImport(
            '/touché.txt',
            isFolder: false,
            bytes: Uint8List.fromList([3]),
          ),
          ArchiveWorkspaceImport(
            '/touche\u0301.txt',
            isFolder: false,
            bytes: Uint8List.fromList([4]),
          ),
        ], expectedRevision: revision),
        throwsStateError,
      );

      final first = File(p.join(directory.path, 'first', 'touché.txt'));
      final second = File(p.join(directory.path, 'second', 'touche\u0301.txt'));
      await first.parent.create();
      await second.parent.create();
      await first.writeAsBytes([5]);
      await second.writeAsBytes([6]);
      await expectLater(
        workspace.addFiles(local, [
          (await local.stat(first.path))!,
          (await local.stat(second.path))!,
        ]),
        throwsStateError,
      );
      final existing = File(p.join(directory.path, 'café.txt'));
      await existing.writeAsBytes([7]);
      await expectLater(
        workspace.addFiles(local, [(await local.stat(existing.path))!]),
        throwsStateError,
      );
      for (final unsafe in [
        '../escape',
        '/absolute',
        'C:/escape',
        'bad\u0000name',
      ]) {
        expect(
          () => workspace.rename('/other.txt', unsafe),
          throwsA(isA<ArchiveViewException>()),
        );
      }
      expect(workspace.revision, revision);
      expect(workspace.dirty, isFalse);
      expect(await workspace.read('/café.txt'), [1]);
      expect(await workspace.read('/other.txt'), [2]);
      expect(await file.readAsBytes(), original);
    },
    skip: !supportsNativeExclusiveRename,
  );

  for (final format in [ArchiveEndpointFormat.iso, ArchiveEndpointFormat.rar]) {
    test('${format.name} retains distinct NFC and NFD member names', () async {
      final file = await writeArchive(format.name, format, [
        _entry('original.txt', [0]),
      ]);
      final workspace = await open(file);
      workspace.replace('/café.txt', Uint8List.fromList([1]));
      workspace.replace('/cafe\u0301.txt', Uint8List.fromList([2]));
      expect(workspace.list().map((item) => item.name).toSet(), {
        'original.txt',
        'café.txt',
        'cafe\u0301.txt',
      });
      expect(await workspace.read('/café.txt'), [1]);
      expect(await workspace.read('/cafe\u0301.txt'), [2]);
      expect((await workspace.review()).isCurrent, isTrue);
    }, skip: !supportsNativeExclusiveRename);
  }

  test('uninspected DMG fallback remains read-only', () async {
    final file = File(p.join(directory.path, 'foreign.dmg'));
    await file.writeAsBytes(DmgFixture(HfsFixture().bytes).bytes);
    final workspace = await open(file);
    expect(workspace.canUpdate, isFalse);
    expect(workspace.supportsLargeFiles, isFalse);
    expect(
      () => workspace.replace('/café.txt', Uint8List.fromList([1])),
      throwsUnsupportedError,
    );
  });
}
