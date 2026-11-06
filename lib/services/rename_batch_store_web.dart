import 'package:shared_preferences/shared_preferences.dart';

import '../models/rename_batch.dart';
import 'rename_batch_store.dart';

RenameBatchStore createRenameBatchStore() => BrowserRenameBatchStore();

/// Browser storage acknowledges each whole journal replacement. Durability is
/// subject to the browser's storage policy; history contains no credentials.
class BrowserRenameBatchStore extends RenameBatchStore {
  static const _prefix = 'commander.renameBatch.v1.';
  final List<String> _warnings = [];
  @override
  List<String> get warnings => List.unmodifiable(_warnings);
  @override
  Future<List<RenameBatchRecord>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final records = <RenameBatchRecord>[];
    _warnings.clear();
    for (final key in prefs.getKeys().where((key) => key.startsWith(_prefix))) {
      try {
        records.add(decodeRenameBatch(prefs.getString(key)!));
      } catch (error) {
        _warnings.add('Cannot read browser recovery record $key: $error');
      }
    }
    return records..sort((a, b) => b.created.compareTo(a.created));
  }

  @override
  Future<RenameBatchRecord?> read(String id) async {
    RenameBatchStore.validateId(id);
    final value = (await SharedPreferences.getInstance()).getString(
      '$_prefix$id',
    );
    return value == null ? null : decodeRenameBatch(value);
  }

  @override
  Future<void> save(RenameBatchRecord record) async {
    RenameBatchStore.validateId(record.id);
    if (!await (await SharedPreferences.getInstance()).setString(
      '$_prefix${record.id}',
      encodeRenameBatch(record),
    )) {
      throw StateError('The browser could not save rename recovery history.');
    }
  }

  @override
  Future<void> remove(String id) async {
    RenameBatchStore.validateId(id);
    if (!await (await SharedPreferences.getInstance()).remove('$_prefix$id')) {
      throw StateError('The browser could not remove rename history.');
    }
  }
}
