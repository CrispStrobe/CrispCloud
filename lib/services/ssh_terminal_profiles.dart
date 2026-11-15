import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ssh_terminal_profile.dart';
import '../utils/async_lock.dart';

/// A small versioned destination store. Mutations reload under the same lock,
/// so saves from different terminal tabs cannot overwrite each other's work.
class SshTerminalProfiles {
  SshTerminalProfiles({
    Future<String?> Function()? read,
    Future<void> Function(String value)? write,
  }) : _read = read ?? _readPreferences,
       _write = write ?? _writePreferences;

  static const preferencesKey = 'terminal_ssh_profiles_v1';
  static const maxProfiles = 50;
  static const maxStorageLength = 256 * 1024;
  final Future<String?> Function() _read;
  final Future<void> Function(String value) _write;
  final _lock = AsyncLock();

  static Future<String?> _readPreferences() async =>
      (await SharedPreferences.getInstance()).getString(preferencesKey);

  static Future<void> _writePreferences(String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      preferencesKey,
      value,
    )) {
      throw StateError('SSH profile storage failed');
    }
  }

  Future<List<SshTerminalProfile>> load() => _lock.synchronized(_load);

  Future<List<SshTerminalProfile>> _load() async {
    final raw = await _read();
    if (raw == null) return const [];
    if (raw.length > maxStorageLength) {
      throw const FormatException('SSH profile store exceeds the limit');
    }
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        data['version'] != 1 ||
        data['profiles'] is! List) {
      throw const FormatException('Unsupported SSH profile store');
    }
    final entries = data['profiles'] as List;
    if (entries.length > maxProfiles) {
      throw const FormatException('Too many SSH profiles');
    }
    final names = <String>{};
    final profiles = <SshTerminalProfile>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid SSH profile record');
      }
      final profile = SshTerminalProfile.fromJson(entry);
      if (!names.add(profile.name)) {
        throw const FormatException('Duplicate SSH profile name');
      }
      profiles.add(profile);
    }
    profiles.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return List.unmodifiable(profiles);
  }

  Future<void> save(SshTerminalProfile profile) => _lock.synchronized(() async {
    // A malformed or newer store fails before any write, preserving its data.
    final profiles = (await _load()).toList();
    final index = profiles.indexWhere((item) => item.name == profile.name);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      if (profiles.length >= maxProfiles) {
        throw StateError('SSH profile limit reached');
      }
      profiles.add(profile);
    }
    await _persist(profiles);
  });

  Future<void> delete(String name) => _lock.synchronized(() async {
    final profiles = (await _load())
        .where((item) => item.name != name)
        .toList();
    await _persist(profiles);
  });

  Future<void> _persist(List<SshTerminalProfile> profiles) async {
    final encoded = jsonEncode({
      'version': 1,
      'profiles': profiles.map((item) => item.toJson()).toList(),
    });
    if (encoded.length > maxStorageLength) {
      throw StateError('SSH profile store exceeds the limit');
    }
    await _write(encoded);
  }
}
