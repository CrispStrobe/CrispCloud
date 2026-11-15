import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/terminal_key_binding.dart';
import '../utils/async_lock.dart';

/// Versioned local mappings. Corrupt or newer data is preserved before writes.
class TerminalKeyBindings {
  TerminalKeyBindings({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : _read = read ?? _readPreferences,
       _write = write ?? _writePreferences,
       _lock = read == null ? _preferencesLock : AsyncLock() {
    if ((read == null) != (write == null)) {
      throw ArgumentError('Supply both terminal key binding storage callbacks');
    }
  }

  static const preferencesKey = 'terminal_key_bindings_v1';
  static const maximumBindings = 50;
  static const maximumStorageLength = 512 * 1024;
  static final _preferencesLock = AsyncLock();
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  final AsyncLock _lock;

  static Future<String?> _readPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString(preferencesKey);
  }

  static Future<void> _writePreferences(String value) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(preferencesKey, value)) {
      throw StateError('Terminal key binding storage failed');
    }
  }

  Future<List<TerminalKeyBinding>> load() => _lock.synchronized(_load);

  Future<List<TerminalKeyBinding>> _load() async {
    final raw = await _read();
    if (raw == null) return const [];
    if (raw.length > maximumStorageLength) {
      throw const FormatException('Terminal key binding store exceeds limit');
    }
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        data['version'] is! int ||
        data['version'] != 1 ||
        data['bindings'] is! List) {
      throw const FormatException('Unsupported terminal key binding store');
    }
    final entries = data['bindings'] as List;
    if (entries.length > maximumBindings) {
      throw const FormatException('Too many terminal key bindings');
    }
    final chords = <TerminalKeyChord>{};
    final bindings = <TerminalKeyBinding>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid terminal key binding record');
      }
      final binding = TerminalKeyBinding.fromJson(entry);
      if (!chords.add(binding.chord)) {
        throw const FormatException('Duplicate terminal key binding');
      }
      bindings.add(binding);
    }
    return List.unmodifiable(bindings);
  }

  /// A different shortcut is never silently overwritten when editing a record.
  Future<void> save(
    TerminalKeyBinding binding, {
    TerminalKeyChord? replacing,
  }) => _lock.synchronized(() async {
    final bindings = (await _load()).toList();
    final previous = replacing == null
        ? -1
        : bindings.indexWhere((item) => item.chord == replacing);
    if (replacing != null && previous < 0) {
      throw StateError('Terminal key binding changed while editing');
    }
    if (bindings.asMap().entries.any(
      (entry) => entry.key != previous && entry.value.chord == binding.chord,
    )) {
      throw StateError('Terminal shortcut already has a binding');
    }
    if (previous < 0) {
      if (bindings.length >= maximumBindings) {
        throw StateError('Terminal key binding limit reached');
      }
      bindings.add(binding);
    } else {
      bindings[previous] = binding;
    }
    await _persist(bindings);
  });

  Future<void> delete(TerminalKeyChord chord) => _lock.synchronized(() async {
    final bindings = (await _load())
        .where((item) => item.chord != chord)
        .toList();
    await _persist(bindings);
  });

  Future<void> _persist(List<TerminalKeyBinding> bindings) async {
    final value = jsonEncode({
      'version': 1,
      'bindings': bindings.map((item) => item.toJson()).toList(),
    });
    if (value.length > maximumStorageLength) {
      throw StateError('Terminal key binding store exceeds limit');
    }
    await _write(value);
  }
}
