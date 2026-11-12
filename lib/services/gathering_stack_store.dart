import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gathering_stack.dart';
import '../utils/async_lock.dart';
import 'file_collection_storage.dart';
import 'file_collection_storage_factory.dart';

/// A small, persistent gathering surface using the existing collection record
/// storage. Atomic publication preserves the last valid stack on write failure.
class GatheringStackStore extends ChangeNotifier {
  GatheringStackStore({FileCollectionStorage? storage})
    : _storage =
          storage ??
          createFileCollectionStorage(
            preferences: SharedPreferences.getInstance,
          ) {
    ready = _load();
  }

  static const recordKey = 'gathering-stack-v1';
  static const maximumEntries = 1000;
  static const maximumBytes = 2 * 1024 * 1024;
  final FileCollectionStorage _storage;
  final _lock = AsyncLock();
  List<GatheringStackEntry> _entries = const [];
  final _states = <String, GatheringReferenceState>{};
  String? _raw;
  Object? _loadError;
  bool _disposed = false;
  bool _loading = true;
  int _intentRevision = 0;
  late final Future<void> ready;

  List<GatheringStackEntry> get entries => _entries;
  bool get isLoading => _loading;
  Object? get loadError => _loadError;
  int get intentRevision => _intentRevision;
  GatheringReferenceState stateFor(String id) =>
      _states[id] ?? GatheringReferenceState.unchecked;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    _loading = true;
    _changed();
    try {
      final raw = await _storage.read(recordKey, maxBytes: maximumBytes);
      final next = <GatheringStackEntry>[];
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is! Map || data['version'] != 1 || data['entries'] is! List) {
          throw const GatheringException(GatheringFailure.invalidReference);
        }
        final values = data['entries'] as List;
        if (values.length > maximumEntries) {
          throw const GatheringException(GatheringFailure.limit);
        }
        for (final value in values) {
          next.add(
            GatheringStackEntry.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          );
        }
        _validate(next);
      }
      if (_disposed) return;
      _entries = List.unmodifiable(next);
      _raw = raw;
      _loadError = null;
      _states.clear();
    } catch (error) {
      _loadError = error;
    } finally {
      _loading = false;
      _changed();
    }
  }

  Future<void> reload() async {
    _intentRevision++;
    if (_loading) await ready;
    await _lock.synchronized(_load);
  }

  void _check() {
    if (_disposed || _loadError != null) {
      throw const GatheringException(GatheringFailure.storageFailure);
    }
  }

  static void _validate(List<GatheringStackEntry> entries) {
    if (entries.length > maximumEntries) {
      throw const GatheringException(GatheringFailure.limit);
    }
    if (entries.map((item) => item.id).toSet().length != entries.length ||
        entries.map((item) => item.identityKey).toSet().length !=
            entries.length) {
      throw const GatheringException(GatheringFailure.invalidReference);
    }
  }

  Future<void> _publish(List<GatheringStackEntry> entries) async {
    _check();
    _validate(entries);
    const prefix = '{"version":1,"entries":[';
    final encoded = <String>[];
    var bytes = prefix.length + 2;
    for (final entry in entries) {
      final row = jsonEncode(entry.toJson());
      bytes += utf8.encode(row).length + (encoded.isEmpty ? 0 : 1);
      if (bytes > maximumBytes) {
        throw const GatheringException(GatheringFailure.limit);
      }
      encoded.add(row);
    }
    final value = '$prefix${encoded.join(',')}]}';
    var committed = false;
    try {
      committed = await _storage.compareAndSwap(recordKey, _raw, value);
    } catch (_) {
      // A durable commit may precede an adapter error. Read it back before
      // reporting failure or retaining an obsolete in-memory revision.
      try {
        committed =
            await _storage.read(recordKey, maxBytes: maximumBytes) == value;
      } catch (_) {
        committed = false;
      }
    }
    if (!committed) {
      throw const GatheringException(GatheringFailure.storageFailure);
    }
    _raw = value;
    _entries = List.unmodifiable(entries);
    final live = entries.map((item) => item.id).toSet();
    _states.removeWhere((key, _) => !live.contains(key));
    _changed();
  }

  Future<GatheringAddResult> add(
    Iterable<GatheringStackEntry> additions, {
    bool Function()? isCurrent,
  }) async {
    final captured = List<GatheringStackEntry>.unmodifiable(
      additions.take(maximumEntries + 1),
    );
    if (captured.isEmpty) {
      throw const GatheringException(GatheringFailure.empty);
    }
    if (captured.length > maximumEntries) {
      throw const GatheringException(GatheringFailure.limit);
    }
    _intentRevision++;
    if (_loading) await ready;
    return _lock.synchronized(() async {
      _check();
      if (!(isCurrent?.call() ?? true)) {
        throw const GatheringException(GatheringFailure.changed);
      }
      final next = List<GatheringStackEntry>.of(_entries);
      final positions = {
        for (var index = 0; index < next.length; index++)
          next[index].identityKey: index,
      };
      var added = 0;
      var refreshed = 0;
      for (final entry in captured) {
        final previous = positions[entry.identityKey];
        if (previous == null) {
          positions[entry.identityKey] = next.length;
          next.add(entry);
          added++;
        } else {
          // Explicitly gathering a current row again refreshes its evidence
          // and ticket without duplicating its position in the stack.
          next[previous] = entry;
          refreshed++;
        }
      }
      await _publish(next);
      return GatheringAddResult(added: added, refreshed: refreshed);
    });
  }

  Future<void> remove(String id) async {
    _intentRevision++;
    if (_loading) await ready;
    await _lock.synchronized(() async {
      await _publish(_entries.where((entry) => entry.id != id).toList());
    });
  }

  Future<void> move(String id, int offset) async {
    _intentRevision++;
    if (_loading) await ready;
    await _lock.synchronized(() async {
      _check();
      final next = List<GatheringStackEntry>.of(_entries);
      final from = next.indexWhere((entry) => entry.id == id);
      if (from < 0) return;
      final to = (from + offset).clamp(0, next.length - 1);
      if (to == from) return;
      final entry = next.removeAt(from);
      next.insert(to, entry);
      await _publish(next);
    });
  }

  void recordStates(
    Iterable<GatheringStackEntry> captured,
    Map<String, GatheringReferenceState> states,
  ) {
    final current = {for (final entry in _entries) entry.id: entry.evidenceKey};
    for (final entry in captured) {
      if (current[entry.id] == entry.evidenceKey &&
          states.containsKey(entry.id)) {
        _states[entry.id] = states[entry.id]!;
      }
    }
    _changed();
  }

  /// Completion changes neither user intent nor a later replacement ticket.
  /// This is deliberately called once per settled foreground account group.
  Future<int> removeConfirmed(
    Iterable<GatheringStackEntry> captured,
    Set<String> successfulIds,
  ) async {
    final evidence = {
      for (final entry in captured)
        if (successfulIds.contains(entry.id)) entry.id: entry.evidenceKey,
    };
    if (evidence.isEmpty) return 0;
    if (_loading) await ready;
    return _lock.synchronized(() async {
      _check();
      final next = _entries.where((entry) {
        return evidence[entry.id] != entry.evidenceKey;
      }).toList();
      final removed = _entries.length - next.length;
      if (removed != 0) await _publish(next);
      return removed;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _intentRevision++;
    super.dispose();
  }
}
