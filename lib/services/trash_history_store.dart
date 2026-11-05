import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/storage_reference.dart';
import '../utils/async_lock.dart';
import 'storage_trash.dart';

enum TrashRecordState { pending, trashed, restoring, restored, uncertain }

class TrashRecord {
  const TrashRecord({
    required this.id,
    required this.file,
    required this.name,
    required this.isFolder,
    required this.createdAt,
    required this.state,
    this.receipt,
    this.detail,
  });
  final String id;
  final FileReference file;
  final String name;
  final bool isFolder;
  final DateTime createdAt;
  final TrashRecordState state;
  final TrashReceipt? receipt;
  final String? detail;

  TrashRecord withState(
    TrashRecordState state, {
    TrashReceipt? receipt,
    String? detail,
  }) => TrashRecord(
    id: id,
    file: file,
    name: name,
    isFolder: isFolder,
    createdAt: createdAt,
    state: state,
    receipt: receipt ?? this.receipt,
    detail: detail,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'id': id,
    'file': file.toJson(),
    'name': name,
    'isFolder': isFolder,
    'createdAt': createdAt.toIso8601String(),
    'state': state.name,
    if (receipt != null) 'receipt': receipt!.toJson(),
    if (detail != null) 'detail': detail,
  };

  factory TrashRecord.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['id'] is! String ||
        json['name'] is! String) {
      throw const FormatException('Unsupported trash history record.');
    }
    final file = FileReference.fromJson(
      Map<String, dynamic>.from(json['file'] as Map),
    );
    final receipt = json['receipt'] == null
        ? null
        : TrashReceipt.fromJson(
            Map<String, dynamic>.from(json['receipt'] as Map),
          );
    if (receipt != null && receipt.originalPath != file.path) {
      throw const FormatException(
        'Trash receipt does not match its original path.',
      );
    }
    return TrashRecord(
      id: json['id'] as String,
      file: file,
      name: json['name'] as String,
      isFolder: json['isFolder'] == true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      state: TrashRecordState.values.byName(json['state'] as String),
      receipt: receipt,
      detail: json['detail'] as String?,
    );
  }
}

/// Trash identities survive panel disposal and restart. A pending/uncertain
/// record never invents a receipt or claims that the delete/restore completed.
class TrashHistoryStore extends ChangeNotifier {
  TrashHistoryStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance {
    ready = _load();
  }
  final Future<SharedPreferences> Function() _preferences;
  final _lock = AsyncLock();
  final _records = <String, TrashRecord>{};
  final _errors = <String>[];
  bool _disposed = false;
  static const _prefix = 'commander_trash_v1_';
  late final Future<void> ready;
  List<TrashRecord> get records => List.unmodifiable(
    _records.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );
  List<String> get errors => List.unmodifiable(_errors);
  TrashRecord? get(String id) => _records[id];

  Future<void> _load() async {
    try {
      final prefs = await _preferences();
      for (final key in prefs.getKeys().where(
        (key) => key.startsWith(_prefix),
      )) {
        try {
          final raw = prefs.getString(key);
          if (raw == null || raw.length > 256 * 1024) {
            throw const FormatException('Invalid trash history size.');
          }
          final record = TrashRecord.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          );
          if ('$_prefix${record.id}' != key) {
            throw const FormatException('Trash history ID mismatch.');
          }
          _records[record.id] = record;
        } catch (error) {
          _errors.add('$key: $error');
        }
      }
    } catch (error) {
      _errors.add('Could not load trash history: $error');
    }
    if (!_disposed) notifyListeners();
  }

  Future<TrashRecord> begin({
    required FileReference file,
    required String name,
    required bool isFolder,
  }) async {
    final record = TrashRecord(
      id: const Uuid().v4(),
      file: file,
      name: name,
      isFolder: isFolder,
      createdAt: DateTime.now().toUtc(),
      state: TrashRecordState.pending,
    );
    await save(record);
    return record;
  }

  Future<void> save(TrashRecord record, {bool retainOnFailure = false}) async {
    await ready;
    await _lock.synchronized(() async {
      if (retainOnFailure) _records[record.id] = record;
      try {
        final prefs = await _preferences();
        if (!await prefs.setString(
          '$_prefix${record.id}',
          jsonEncode(record.toJson()),
        )) {
          throw StateError('Trash history could not be saved.');
        }
        _records[record.id] = record;
      } catch (error) {
        _errors.add('${record.name}: $error');
        rethrow;
      } finally {
        if (!_disposed) notifyListeners();
      }
    });
  }

  Future<void> clearRestored() async {
    await ready;
    await _lock.synchronized(() async {
      final prefs = await _preferences();
      for (final record in _records.values.toList()) {
        if (record.state == TrashRecordState.restored) {
          if (!await prefs.remove('$_prefix${record.id}')) {
            throw StateError(
              'The restored history entry could not be removed.',
            );
          }
          _records.remove(record.id);
        }
      }
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
