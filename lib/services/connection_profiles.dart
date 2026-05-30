// lib/services/connection_profiles.dart
//
// Named connection profiles: save/load multiple configurations per provider.
// Stored in SecureStorage as JSON maps keyed by profile name.

import 'dart:convert';

import 'secure_storage_service.dart';
import 'log_service.dart';

class ConnectionProfile {
  final String name;
  final String provider;
  final Map<String, String> fields;

  const ConnectionProfile({
    required this.name,
    required this.provider,
    required this.fields,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'provider': provider,
    'fields': fields,
  };

  factory ConnectionProfile.fromJson(Map<String, dynamic> json) =>
      ConnectionProfile(
        name: json['name'] as String,
        provider: json['provider'] as String,
        fields: Map<String, String>.from(json['fields'] as Map),
      );
}

class ConnectionProfileService {
  static final _log = Log('ConnectionProfiles');
  static const _storageKey = 'connection_profiles';

  final SecureStorage _storage;

  ConnectionProfileService(this._storage);

  /// Get all saved profiles.
  Future<List<ConnectionProfile>> getAll() async {
    try {
      final raw = await _storage.read(_storageKey);
      if (raw == null || raw.isEmpty) return [];
      final list = json.decode(raw) as List;
      return list.map((e) => ConnectionProfile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      _log.warn('Failed to load profiles', e);
      return [];
    }
  }

  /// Get profiles for a specific provider.
  Future<List<ConnectionProfile>> getForProvider(String provider) async {
    final all = await getAll();
    return all.where((p) => p.provider == provider).toList();
  }

  /// Save a profile (upserts by name + provider).
  Future<void> save(ConnectionProfile profile) async {
    final all = await getAll();
    all.removeWhere((p) => p.name == profile.name && p.provider == profile.provider);
    all.add(profile);
    await _writeAll(all);
    _log.info('Saved profile "${profile.name}" for ${profile.provider}');
  }

  /// Delete a profile by name and provider.
  Future<void> delete(String name, String provider) async {
    final all = await getAll();
    all.removeWhere((p) => p.name == name && p.provider == provider);
    await _writeAll(all);
    _log.info('Deleted profile "$name" for $provider');
  }

  Future<void> _writeAll(List<ConnectionProfile> profiles) async {
    await _storage.write(_storageKey, json.encode(profiles.map((p) => p.toJson()).toList()));
  }
}
