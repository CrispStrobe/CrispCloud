import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/rename_batch.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/multi_rename_service.dart';
import 'package:crisp_cloud/services/native_file_primitives.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/rename_batch_digest.dart';
import 'package:crisp_cloud/services/rename_batch_service.dart';
import 'package:crisp_cloud/services/rename_batch_storage.dart';
import 'package:crisp_cloud/services/rename_batch_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _CutPowerStore extends MemoryRenameBatchStore {
  bool cut = false;
  @override
  Future<void> save(RenameBatchRecord record) async {
    if (cut ||
        record.steps.any((step) => step.state == RenameStepState.completed)) {
      cut = true;
      throw StateError('Simulated interruption before completion persistence');
    }
    await super.save(record);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SourceRenameBatchStorage storage;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('crisp-batch-rename-');
    storage = SourceRenameBatchStorage(
      reference: const StorageReference(
        kind: 'local',
        provider: 'local',
        accountKey: 'native-test',
      ),
      source: LocalPanelSource(directory.path),
      local: LocalFileService(),
      isCurrent: () => true,
      fallbackRename: (_, _) =>
          throw StateError('Native execution must use the exclusive primitive'),
    );
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<MultiRenamePlan> makePlan(Map<String, String> names) async {
    final items = <FileItem>[];
    for (final name in names.keys) {
      items.add((await storage.stat(p.join(directory.path, name)))!);
    }
    return const MultiRenameService().preview(
      items,
      const MultiRenameOptions(),
      directory: directory.path,
      pathContext: p.context,
      allowDependencies: true,
      caseSensitivePaths: storage.caseSensitivePaths,
      targetNames: {
        for (final entry in names.entries)
          p.join(directory.path, entry.key): entry.value,
      },
    );
  }

  test(
    'native swap and whole-batch restore retain distinct file bytes',
    () async {
      await File(p.join(directory.path, 'a')).writeAsString('alpha');
      await File(p.join(directory.path, 'b')).writeAsString('bravo');
      final service = RenameBatchService(MemoryRenameBatchStore());
      final record = await service.prepare(
        await makePlan({'a': 'b', 'b': 'a'}),
        storage,
      );
      await service.run(record, storage);
      expect(record.isComplete, isTrue);
      expect(await File(p.join(directory.path, 'a')).readAsString(), 'bravo');
      expect(await File(p.join(directory.path, 'b')).readAsString(), 'alpha');
      await service.restore(record, storage);
      expect(record.isRestored, isTrue);
      expect(await File(p.join(directory.path, 'a')).readAsString(), 'alpha');
      expect(await File(p.join(directory.path, 'b')).readAsString(), 'bravo');
    },
    skip: !supportsNativeExclusiveRename,
  );

  test('native directory interruption is reconciled from a streamed content manifest', () async {
    final folder = await Directory(p.join(directory.path, 'folder')).create();
    await File(p.join(folder.path, 'data.bin'))
        .writeAsBytes(List.generate(200000, (index) => index % 251));
    final cutStore = _CutPowerStore();
    final record = await RenameBatchService(cutStore)
        .prepare(await makePlan({'folder': 'renamed'}), storage);
    await expectLater(
      RenameBatchService(cutStore).run(record, storage),
      throwsA(isA<RenameBatchPersistenceException>()),
    );
    final interrupted = (await cutStore.read(record.id))!;
    expect(interrupted.steps.single.before!.digest, isNotNull);
    final recoveredStore = MemoryRenameBatchStore();
    await recoveredStore.save(interrupted);
    await RenameBatchService(recoveredStore).run(interrupted, storage);
    expect(interrupted.isComplete, isTrue);
    expect(
      await File(p.join(directory.path, 'renamed', 'data.bin')).length(),
      200000,
    );
    await RenameBatchService(recoveredStore).restore(interrupted, storage);
    expect(await folder.exists(), isTrue);
  }, skip: !supportsNativeExclusiveRename);

  test('native symlink digest and rename never follow its target', () async {
    final target = File(p.join(directory.path, 'target'));
    await target.writeAsString('target remains');
    final link = Link(p.join(directory.path, 'link'));
    await link.create('target');
    final digest = await nativeRenameDigest(link.path, () {});
    final service = RenameBatchService(MemoryRenameBatchStore());
    final record = await service.prepare(
      await makePlan({'link': 'renamed-link'}),
      storage,
    );
    await service.run(record, storage);
    expect(record.isComplete, isTrue);
    expect(
      await Link(p.join(directory.path, 'renamed-link')).target(),
      'target',
    );
    expect(
      await nativeRenameDigest(p.join(directory.path, 'renamed-link'), () {}),
      digest,
    );
    expect(await target.readAsString(), 'target remains');
  }, skip: !supportsNativeExclusiveRename || Platform.isWindows);

  test(
    'native nested folder and child restore preserves content preconditions',
    () async {
      final folder = await Directory(p.join(directory.path, 'folder')).create();
      await File(p.join(folder.path, 'child.txt'))
          .writeAsString('original content');
      final service = RenameBatchService(MemoryRenameBatchStore());
      final record = await service.prepare(
        await makePlan({'folder': 'renamed', 'folder/child.txt': 'new.txt'}),
        storage,
      );
      await service.run(record, storage);
      expect(record.isComplete, isTrue);
      await service.restore(record, storage);
      expect(record.isRestored, isTrue);
      expect(
        await File(p.join(folder.path, 'child.txt')).readAsString(),
        'original content',
      );
    },
    skip: !supportsNativeExclusiveRename,
  );

  test(
    'a replaced native directory cannot be restored under the original name',
    () async {
      final folder = await Directory(p.join(directory.path, 'folder')).create();
      await File(p.join(folder.path, 'child.txt'))
          .writeAsString('original content');
      final service = RenameBatchService(MemoryRenameBatchStore());
      final record = await service.prepare(
        await makePlan({'folder': 'renamed'}),
        storage,
      );
      await service.run(record, storage);
      final renamed = Directory(p.join(directory.path, 'renamed'));
      await renamed.delete(recursive: true);
      await renamed.create();
      await File(p.join(renamed.path, 'different.txt'))
          .writeAsString('replacement');
      await service.restore(record, storage);
      expect(record.isRestored, isFalse);
      expect(await renamed.exists(), isTrue);
      expect(await folder.exists(), isFalse);
    },
    skip: !supportsNativeExclusiveRename,
  );
}
