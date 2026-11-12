import 'package:crisp_cloud/services/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_endpoint_backend.dart';
import 'support/archive_package_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ArchiveEndpoint> open(ArchiveEndpointTestBackend backend) async {
    final endpoint = await ArchiveEndpoint.open(
      containerBackend: backend,
      containerFile: (await backend.stat('/out/work.cpio'))!,
      journal: ArchivePublicationJournal(
        storage: MemoryFileCollectionStorage(),
      ),
    );
    addTearDown(endpoint.close);
    expect(endpoint.workspace.canUpdate, isTrue);
    return endpoint;
  }

  for (final special in [
    ('setuid file', '/input/tool', 0x800),
    ('setgid directory', '/input/group', 0x400),
  ]) {
    for (final move in [false, true]) {
      test(
        '${move ? 'move' : 'copy'} refuses ${special.$1} before adopting the import',
        () async {
          final original = referenceNewc();
          final backend = ArchiveEndpointTestBackend()
            ..put('/out/work.cpio', original)
            ..put('/input/tool', [1, 2, 3])
            ..put('/input/group/member', [4, 5]);
          backend.modes[special.$2] = 0x1ed | special.$3;
          final endpoint = await open(backend);
          final revision = endpoint.workspace.revision;
          final before = endpoint.workspace
              .list('/')
              .map((item) => item.path)
              .toList();
          final plan = await endpoint.prepareImport(
            source: backend,
            files: [(await backend.stat(special.$2))!],
            moveSources: move,
          );
          expect(plan.canStage, isTrue, reason: plan.errors.join('\n'));
          await expectLater(
            endpoint.stageImport(plan, control: FileOperationControl()),
            throwsA(
              isA<ArchiveViewException>().having(
                (error) => error.message,
                'reason',
                contains('ownership'),
              ),
            ),
          );
          expect(endpoint.workspace.revision, revision);
          expect(endpoint.workspace.dirty, isFalse);
          expect(endpoint.workspace.list('/').map((item) => item.path), before);
          expect(backend.files['/out/work.cpio'], original);
          expect(backend.files['/input/tool'], [1, 2, 3]);
          expect(backend.files['/input/group/member'], [4, 5]);
          expect(backend.directories, contains('/input/group'));
          expect(backend.mutations, isEmpty);
        },
      );
    }
  }

  test(
    'ordinary executable permissions remain supported by archive imports',
    () async {
      final original = referenceNewc();
      final backend = ArchiveEndpointTestBackend()
        ..put('/out/work.cpio', original)
        ..put('/input/tool', [1, 2, 3]);
      backend.modes['/input/tool'] = 0x1ed;
      final endpoint = await open(backend);
      final plan = await endpoint.prepareImport(
        source: backend,
        files: [(await backend.stat('/input/tool'))!],
      );
      expect(plan.canStage, isTrue, reason: plan.errors.join('\n'));
      final review = await endpoint.stageImport(
        plan,
        control: FileOperationControl(),
      );
      expect(backend.files['/out/work.cpio'], original);
      await endpoint.commit(reviewed: review);
      final saved = await openViewerArchive(
        backend.files['/out/work.cpio']!,
        name: 'work.cpio',
      );
      try {
        final executable = saved.members.singleWhere(
          (member) => member.name == 'tool',
        );
        expect(executable.posixMode, 0x8000 | 0x1ed);
        expect(await saved.readMember(executable), [1, 2, 3]);
      } finally {
        await saved.close();
      }
      expect(backend.files['/input/tool'], [1, 2, 3]);
    },
  );
}
