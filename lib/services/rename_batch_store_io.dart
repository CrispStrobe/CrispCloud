import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/rename_batch.dart';
import 'rename_batch_store.dart';

RenameBatchStore createRenameBatchStore() => NativeRenameBatchStore();

/// Same-directory replacement is atomic. The new file is flushed before the
/// old journal is replaced; failures propagate before another rename starts.
class NativeRenameBatchStore extends RenameBatchStore {
  NativeRenameBatchStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;
  final Future<Directory> Function() _directory;
  Future<void> _writes = Future.value();
  final List<String> _warnings = [];
  @override
  List<String> get warnings => List.unmodifiable(_warnings);

  static Future<Directory> _defaultDirectory() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'rename_batches'),
  );

  Future<File> _file(String id) async {
    RenameBatchStore.validateId(id);
    return File(p.join((await _directory()).path, '$id.json'));
  }

  @override
  Future<List<RenameBatchRecord>> list() async {
    await _writes;
    final directory = await _directory();
    if (!await directory.exists()) return [];
    final records = <RenameBatchRecord>[];
    _warnings.clear();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          records.add(decodeRenameBatch(await entity.readAsString()));
        } catch (error) {
          _warnings.add('Cannot read ${entity.path}: $error');
        }
      }
    }
    return records..sort((a, b) => b.created.compareTo(a.created));
  }

  @override
  Future<RenameBatchRecord?> read(String id) async {
    await _writes;
    final file = await _file(id);
    return await file.exists()
        ? decodeRenameBatch(await file.readAsString())
        : null;
  }

  @override
  Future<void> save(RenameBatchRecord record) {
    final encoded = encodeRenameBatch(record);
    final operation = _writes.then((_) async {
      final file = await _file(record.id);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.pending');
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(file.path);
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  @override
  Future<void> remove(String id) async {
    await _writes;
    final file = await _file(id);
    if (await file.exists()) await file.delete();
  }
}
