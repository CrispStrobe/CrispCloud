import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/terminal_arrangement.dart';
import '../utils/async_lock.dart';

/// Explicitly saved workspace arrangements, without connections or credentials.
///
/// Read-modify-write operations share one lock, including between instances
/// using the default preferences backend. Unknown/corrupt data fails closed
/// before a write so it can still be recovered by a compatible application.
class TerminalArrangements {
  TerminalArrangements({
    Future<String?> Function()? read,
    Future<void> Function(String value)? write,
  }) : _read = read ?? _readPreferences,
       _write = write ?? _writePreferences,
       _lock = read == null ? _preferencesLock : AsyncLock() {
    if ((read == null) != (write == null)) {
      throw ArgumentError('Supply both terminal arrangement storage callbacks');
    }
  }

  static const preferencesKey = 'terminal_arrangements_v1';
  static const maxArrangements = 20;
  static const maxStorageLength = 1024 * 1024;
  static final _preferencesLock = AsyncLock();

  final Future<String?> Function() _read;
  final Future<void> Function(String value) _write;
  final AsyncLock _lock;

  static Future<String?> _readPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString(preferencesKey);
  }

  static Future<void> _writePreferences(String value) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(preferencesKey, value)) {
      throw StateError('Terminal arrangement storage failed');
    }
  }

  Future<List<TerminalArrangement>> load() => _lock.synchronized(_load);

  Future<List<TerminalArrangement>> _load() async {
    final raw = await _read();
    if (raw == null) return const [];
    if (raw.length > maxStorageLength) {
      throw const FormatException('Terminal arrangement store exceeds limit');
    }
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        data['version'] is! int ||
        (data['version'] != 1 && data['version'] != 2) ||
        data['arrangements'] is! List) {
      throw const FormatException('Unsupported terminal arrangement store');
    }
    final entries = data['arrangements'] as List;
    if (entries.length > maxArrangements) {
      throw const FormatException('Too many terminal arrangements');
    }
    final names = <String>{};
    final arrangements = <TerminalArrangement>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid terminal arrangement record');
      }
      final arrangement = TerminalArrangement.fromJson(
        entry,
        requireLayout: data['version'] == 2,
      );
      if (!names.add(arrangement.name)) {
        throw const FormatException('Duplicate terminal arrangement name');
      }
      arrangements.add(arrangement);
    }
    arrangements.sort((a, b) {
      final lower = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return lower != 0 ? lower : a.name.compareTo(b.name);
    });
    return List.unmodifiable(arrangements);
  }

  Future<void> save(TerminalArrangement arrangement) =>
      _lock.synchronized(() async {
        final arrangements = (await _load()).toList();
        final index = arrangements.indexWhere(
          (item) => item.name == arrangement.name,
        );
        if (index >= 0) {
          arrangements[index] = arrangement;
        } else {
          if (arrangements.length >= maxArrangements) {
            throw StateError('Terminal arrangement limit reached');
          }
          arrangements.add(arrangement);
        }
        await _persist(arrangements);
      });

  Future<void> delete(String name) => _lock.synchronized(() async {
    final arrangements = (await _load())
        .where((item) => item.name != name)
        .toList();
    await _persist(arrangements);
  });

  Future<void> _persist(List<TerminalArrangement> arrangements) async {
    final encoded = jsonEncode({
      // Keep the same storage key so an older app rejects this version before
      // it can silently discard nested panes during a read-modify-write.
      'version': 2,
      'arrangements': arrangements.map((item) => item.toJson()).toList(),
    });
    if (encoded.length > maxStorageLength) {
      throw StateError('Terminal arrangement store exceeds limit');
    }
    await _write(encoded);
  }
}
