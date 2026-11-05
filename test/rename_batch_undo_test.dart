import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/multi_rename_service.dart';
import 'package:crisp_cloud/services/rename_batch_undo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const service = MultiRenameService();
  final files = [
    for (var index = 0; index < 75; index++)
      FileItem(name: '$index.txt', path: '/$index.txt', isFolder: false),
  ];

  FileItem? info(Map<String, String> storage, String path) {
    final content = storage[path];
    return content == null ? null : FileItem(
      name: p.posix.basename(path), path: path, isFolder: false,
      uuid: content, size: content.length,
    );
  }

  RenameBatchUndo batchUndo(MultiRenameResult result, Map<String, String> storage) =>
      RenameBatchUndo(result, pathContext: p.posix, caseSensitivePaths: true,
        capturedTargets: {
          for (final outcome in result.outcomes)
            outcome.entry.targetPath: info(storage, outcome.entry.targetPath),
        },
      );

  Future<MultiRenameResult> renameAll(Map<String, String> storage) {
    final plan = service.preview(
      files, const MultiRenameOptions(nameMask: '[N]_new'), directory: '/',
    );
    return service.execute(
      plan,
      exists: (path) async => storage.containsKey(path),
      rename: (file, name) async {
        storage[p.posix.join(p.posix.dirname(file.path!), name)] =
            storage.remove(file.path!)!;
      },
    );
  }

  test('one undo retains every item in a batch larger than 50 records', () async {
    final storage = {for (final file in files) file.path!: file.name};
    final original = Map<String, String>.of(storage);
    final result = await renameAll(storage);
    final undo = batchUndo(result, storage);
    expect(undo.remaining, 75);
    final restored = await undo.execute(
      stat: (path) async => info(storage, path),
      rename: (file, name) async {
        storage['/$name'] = storage.remove(file.path!)!;
      },
    );
    expect(restored.renamed, 75);
    expect(undo.remaining, 0);
    expect(storage, original);
  });

  test('partial undo retries only items that have not been restored', () async {
    final storage = {for (final file in files) file.path!: file.name};
    final original = Map<String, String>.of(storage);
    final result = await renameAll(storage);
    final undo = batchUndo(result, storage);
    var count = 0;
    final first = await undo.execute(
      stat: (path) async => info(storage, path),
      rename: (file, name) async {
        if (++count == 3) throw StateError('Temporary failure');
        storage['/$name'] = storage.remove(file.path!)!;
      },
    );
    expect(first.renamed, 2);
    expect(first.failed, 1);
    expect(undo.remaining, 73);
    final retried = await undo.execute(
      stat: (path) async => info(storage, path),
      rename: (file, name) async {
        storage['/$name'] = storage.remove(file.path!)!;
      },
    );
    expect(retried.renamed, 73);
    expect(storage, original);
  });

  test('an occupied original name blocks the whole undo before mutation', () async {
    final storage = {for (final file in files) file.path!: file.name};
    final result = await renameAll(storage);
    storage['/74.txt'] = 'New unrelated content';
    final before = Map<String, String>.of(storage);
    final undo = batchUndo(result, storage);
    await expectLater(
      undo.execute(
        stat: (path) async => info(storage, path),
        rename: (_, _) async => fail('Undo must not start'),
      ),
      throwsA(isA<MultiRenamePreflightException>()),
    );
    expect(storage, before);
    expect(undo.remaining, 75);
  });

  test('a replacement at a renamed path is never renamed by undo', () async {
    final storage = {for (final file in files) file.path!: file.name};
    final result = await renameAll(storage);
    final undo = batchUndo(result, storage);
    // Equal length still differs by the captured provider object identity.
    storage['/0_new.txt'] = 'x.txt';
    final before = Map<String, String>.of(storage);
    await expectLater(
      undo.execute(
        stat: (path) async => info(storage, path),
        rename: (_, _) async => fail('A replacement must not be renamed'),
      ),
      throwsA(isA<MultiRenamePreflightException>()),
    );
    expect(storage, before);
    expect(undo.remaining, 75);
  });

  test('failed post-rename identity capture makes undo explicitly unavailable', () async {
    final storage = {for (final file in files) file.path!: file.name};
    final result = await renameAll(storage);
    final undo = RenameBatchUndo(
      result, pathContext: p.posix, caseSensitivePaths: true,
      capturedTargets: const {},
    );
    await expectLater(
      undo.execute(
        stat: (path) async => info(storage, path),
        rename: (_, _) async => fail('Unverified targets must not be renamed'),
      ),
      throwsA(isA<MultiRenamePreflightException>()),
    );
  });
}
