import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rename_batch.dart';
import 'rename_batch_store_web.dart'
    if (dart.library.io) 'rename_batch_store_io.dart'
    as platform;

abstract class RenameBatchStore {
  List<String> get warnings => const [];
  Future<List<RenameBatchRecord>> list();
  Future<RenameBatchRecord?> read(String id);
  Future<void> save(RenameBatchRecord record);
  Future<void> remove(String id);

  static void validateId(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
      throw const FormatException('Invalid rename batch identifier.');
    }
  }
}

/// One store for all dialogs. It has no item-count cap: explicit batch history
/// remains available after the separate, short-lived action menu is trimmed.
final renameBatchStoreProvider = Provider<RenameBatchStore>(
  (ref) => platform.createRenameBatchStore(),
);

String encodeRenameBatch(RenameBatchRecord record) {
  final payload = jsonEncode(record.toJson());
  return jsonEncode({
    'sha256': sha256.convert(utf8.encode(payload)).toString(),
    'payload': payload,
  });
}

RenameBatchRecord decodeRenameBatch(String value) {
  final envelope = jsonDecode(value) as Map<String, dynamic>;
  final payload = envelope['payload'] as String;
  if (envelope['sha256'] != sha256.convert(utf8.encode(payload)).toString()) {
    throw const FormatException(
      'Rename history checksum mismatch. The original journal is retained.',
    );
  }
  return RenameBatchRecord.fromJson(
    jsonDecode(payload) as Map<String, dynamic>,
  );
}

class MemoryRenameBatchStore extends RenameBatchStore {
  final Map<String, String> _records = {};
  @override
  Future<List<RenameBatchRecord>> list() async =>
      _records.values.map(decodeRenameBatch).toList()
        ..sort((a, b) => b.created.compareTo(a.created));
  @override
  Future<RenameBatchRecord?> read(String id) async =>
      _records[id] == null ? null : decodeRenameBatch(_records[id]!);
  @override
  Future<void> save(RenameBatchRecord record) async {
    RenameBatchStore.validateId(record.id);
    _records[record.id] = encodeRenameBatch(record);
  }

  @override
  Future<void> remove(String id) async {
    _records.remove(id);
  }
}
