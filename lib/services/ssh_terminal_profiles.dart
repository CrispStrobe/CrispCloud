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
       _write = write ?? _writePreferences,
       _lock = read == null ? _preferencesLock : AsyncLock() {
    if ((read == null) != (write == null)) {
      throw ArgumentError('Supply both SSH profile storage callbacks');
    }
  }

  static const preferencesKey = 'terminal_ssh_profiles_v1';
  static const maxProfiles = 50;
  static const maxStorageLength = 256 * 1024;
  final Future<String?> Function() _read;
  final Future<void> Function(String value) _write;
  static final _preferencesLock = AsyncLock();
  final AsyncLock _lock;

  static Future<String?> _readPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString(preferencesKey);
  }

  static Future<void> _writePreferences(String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      preferencesKey,
      value,
    )) {
      throw StateError('SSH profile storage failed');
    }
  }

  Future<List<SshTerminalProfile>> load() =>
      _lock.synchronized(() async => (await _load()).profiles);

  Future<({int version, List<SshTerminalProfile> profiles})> _load() async {
    final raw = await _read();
    if (raw == null) {
      return (version: 1, profiles: const <SshTerminalProfile>[]);
    }
    if (raw.length > maxStorageLength) {
      throw const FormatException('SSH profile store exceeds the limit');
    }
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        data['version'] is! int ||
        !const [1, 2, 3].contains(data['version']) ||
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
    return (
      version: data['version'] as int,
      profiles: List<SshTerminalProfile>.unmodifiable(profiles),
    );
  }

  Future<void> save(SshTerminalProfile profile) => _lock.synchronized(() async {
    // A malformed or newer store fails before any write, preserving its data.
    final stored = await _load();
    final profiles = stored.profiles.toList();
    final index = profiles.indexWhere((item) => item.name == profile.name);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      if (profiles.length >= maxProfiles) {
        throw StateError('SSH profile limit reached');
      }
      profiles.add(profile);
    }
    await _persist(profiles, minimumVersion: stored.version);
  });

  /// Import a reviewed batch without replacing any existing destination.
  /// Collision/capacity checks and the one write share the store mutation lock.
  Future<void> addAllNew(List<SshTerminalProfile> additions) {
    final pending = List<SshTerminalProfile>.unmodifiable(additions);
    return _lock.synchronized(() async {
      if (pending.isEmpty) return;
      final stored = await _load();
      if (stored.profiles.length + pending.length > maxProfiles) {
        throw StateError('SSH profile limit reached');
      }
      final names = stored.profiles.map((profile) => profile.name).toSet();
      for (final profile in pending) {
        if (!names.add(profile.name)) {
          throw StateError('SSH profile name already exists');
        }
      }
      await _persist([
        ...stored.profiles,
        ...pending,
      ], minimumVersion: stored.version);
    });
  }

  Future<void> delete(String name) => _lock.synchronized(() async {
    final stored = await _load();
    final profiles = stored.profiles
        .where((item) => item.name != name)
        .toList();
    await _persist(profiles, minimumVersion: stored.version);
  });

  Future<void> _persist(
    List<SshTerminalProfile> profiles, {
    required int minimumVersion,
  }) async {
    // Old v1 readers ignore unknown fields within a profile. A v2 envelope
    // makes them preserve/refuse a jump route instead of silently connecting
    // directly. Once upgraded, keep v2 even after removing the last route.
    // v3 readers understand agent authentication and forwarding permission.
    // Older readers must refuse the envelope instead of dropping that choice.
    final version =
        minimumVersion >= 3 ||
            profiles.any((profile) => profile.config.usesAgent)
        ? 3
        : minimumVersion >= 2 ||
              profiles.any((profile) => profile.config.jumpHosts.isNotEmpty)
        ? 2
        : 1;
    final encoded = jsonEncode({
      'version': version,
      'profiles': profiles.map((item) => item.toJson()).toList(),
    });
    if (encoded.length > maxStorageLength) {
      throw StateError('SSH profile store exceeds the limit');
    }
    await _write(encoded);
  }
}
