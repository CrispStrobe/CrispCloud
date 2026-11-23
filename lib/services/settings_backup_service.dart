import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/async_lock.dart';
import 'cloud_storage_interface.dart';
import 'connection_profiles.dart';
import 'encryption_service.dart';
import 'secure_storage_service.dart';

/// A portable snapshot. App-lock state, local trust decisions and installation
/// identifiers stay with the installation that created them.
class SettingsBackup {
  SettingsBackup._(
    this.preferences,
    this.cloud,
    this.credentials,
    this.profiles,
    this.profileCredentials,
  );

  static const maxBytes = 8 * 1024 * 1024;
  static const _format = 'crispcloud-settings';
  static const _version = 1;
  static const _iterations = 600000;
  static const _profileKey = 'connection_profiles';
  static final _lock = AsyncLock();

  final Map<String, Object> preferences;
  final Map<String, Object> cloud;
  final Map<String, String> credentials;
  final List<ConnectionProfile> profiles;
  final List<ConnectionProfile> profileCredentials;

  bool get hasCloud => cloud.isNotEmpty || profiles.isNotEmpty;
  bool get hasCredentials =>
      credentials.isNotEmpty || profileCredentials.isNotEmpty;

  static const _settings = <String, Type>{
    'app_locale': String,
    'app_theme': String,
    'app_accent_color': int,
    'font_family': String,
    'font_size': double,
    'fkey_bar_visible': bool,
    'layout_preset': String,
    'file_layout_local_v1': String,
    'file_layout_remote_v1': String,
    'file_columns_local_v1': String,
    'file_columns_remote_v1': String,
    'col_PanelSide.local_all_v1': String,
    'col_PanelSide.remote_all_v1': String,
    'toolbar_config_v1': String,
    'browser_menu_layout_v1': String,
    'keyboard_shortcuts': String,
    'quick_search_mode': String,
    'panel.sortFoldersLikeFiles.v1': bool,
    'quick_search_from_start': bool,
    'quick_search_case_sensitive': bool,
    'quick_search_arrow_navigation': bool,
    'quick_search_reset_seconds': int,
    'file_type_color_rules_v1': String,
    'file_type_color_enabled_v1': bool,
    'accessibility_high_contrast': bool,
    'accessibility_reduced_motion': bool,
    'analytics_enabled': bool,
    'disable_screenshots': bool,
    'prefer_external_editor': bool,
    'file_cache_max_size': int,
    'delta_sync_enabled': bool,
    'sync_auto_evict_days': int,
    'notifications_seconds': int,
    'notifications_history': bool,
    'notifications_hide_finished_queue': bool,
    'commander_transfer_bandwidth_v1': String,
    'office_length_unit_v1': String,
    'pdf.open.viewer': String,
    'pdf.open.secondaryViewer': String,
    'pdf.open.editor': String,
    'pdf.open.secondaryEditor': String,
    'pdf.open.shiftF4': String,
  };

  static const _providerNames = [
    'Azure Blob',
    'Backblaze B2',
    'Dropbox',
    'Filen',
    'FTP',
    'Google Drive',
    'Hetzner Storage Box',
    'Internxt',
    'Nextcloud',
    'OneDrive',
    'pCloud',
    'S3',
    'SFTP',
    'SMB',
    'WebDAV',
  ];
  static final _cloud = <String, Type>{
    'cloud_provider': String,
    for (final name in _providerNames) ...{
      'provider_${name}_timeout': int,
      'provider_${name}_follow_redirects': bool,
      'provider_${name}_verify_ssl': bool,
    },
  };
  static final _headerKeys = {
    for (final name in _providerNames) 'provider_${name}_headers',
  };
  static final _loginKeys = {
    for (final provider in CloudProvider.values)
      if (provider != CloudProvider.internxt) '${provider.name}_credentials',
    'hetzner_credentials',
    'internxt_config_v1:${base64Url.encode(utf8.encode('internxt'))}:'
        '${base64Url.encode(utf8.encode('.inxtcli-dart-creds.json'))}',
  };
  static const _profileFields = {
    'host',
    'port',
    'user',
    'username',
    'endpoint',
    'serverUrl',
    'region',
    'bucket',
    'securityMode',
    'tls',
    'encryption',
    'storageClass',
    'kmsKeyId',
    'eu',
    'smbBackend',
    'requireEncryption',
    'engine',
  };

  static Future<SettingsBackup> capture(
    SharedPreferences prefs, {
    SecureStorage? storage,
    required bool includeCloud,
    required bool includeCredentials,
  }) => _lock.synchronized(() async {
    await prefs.reload();
    final savedProfiles = includeCloud || includeCredentials
        ? _readProfiles(await _needStorage(storage).read(_profileKey))
        : <ConnectionProfile>[];
    return SettingsBackup._(
      _preferences(_settings, prefs),
      includeCloud ? _preferences(_cloud, prefs) : {},
      {
        if (includeCredentials) ...{
          for (final key in _loginKeys)
            if (await _needStorage(storage).read(key) case final value?)
              key: value,
          for (final key in _headerKeys)
            if (prefs.getString(key) case final value?) key: value,
        },
      },
      includeCloud ? _projectProfiles(savedProfiles, secrets: false) : [],
      includeCredentials ? _projectProfiles(savedProfiles, secrets: true) : [],
    );
  });

  static Map<String, Object> _preferences(
    Map<String, Type> schema,
    SharedPreferences prefs,
  ) => {
    for (final entry in schema.entries)
      if (prefs.get(entry.key) case final value?
          when _validPreference(entry.key, value, entry.value))
        entry.key: entry.value == double ? (value as num).toDouble() : value,
  };

  static bool _validPreference(String key, Object? value, Type? type) {
    if (type == double) {
      return value is num && value.isFinite && value >= 10 && value <= 20;
    }
    if (type == null || value?.runtimeType != type) return false;
    return switch (key) {
      'quick_search_reset_seconds' => const [0, 1, 2, 3, 5, 10].contains(value),
      'cloud_provider' => CloudProvider.values.any(
        (provider) => provider.name == value,
      ),
      _ => true,
    };
  }

  static SecureStorage _needStorage(SecureStorage? storage) =>
      storage ?? (throw StateError('Credential storage is unavailable.'));

  static List<ConnectionProfile> _readProfiles(String? raw) =>
      raw == null ? [] : _parseProfiles(jsonDecode(raw));

  static List<ConnectionProfile> _parseProfiles(Object? value) {
    if (value is! List) throw const FormatException();
    return [
      for (final row in value)
        ConnectionProfile.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  static String? _portableField(String field, String value) {
    if (field == 'email') {
      return RegExp(r'^[^\s@=;]+@[^\s@=;]+$').hasMatch(value) ? value : null;
    }
    if (!_profileFields.contains(field)) return null;
    if (!const ['host', 'serverUrl', 'endpoint'].contains(field)) return value;
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasAuthority) {
      return uri.userInfo.isEmpty && !uri.hasQuery && !uri.hasFragment
          ? value
          : null;
    }
    return value.contains(RegExp(r'[@?#]')) ? null : value;
  }

  static List<ConnectionProfile> _projectProfiles(
    List<ConnectionProfile> profiles, {
    required bool secrets,
  }) {
    return [
      for (final profile in profiles)
        ConnectionProfile(
          name: profile.name,
          provider: profile.provider,
          fields: {
            for (final entry in profile.fields.entries)
              if ((_portableField(entry.key, entry.value) == null) == secrets)
                entry.key: entry.value,
          },
        ),
    ].where((profile) => !secrets || profile.fields.isNotEmpty).toList();
  }

  Map<String, Object> _payload() => {
    'preferences': preferences,
    'cloud': cloud,
    'credentials': credentials,
    'profiles': [for (final p in profiles) p.toJson()],
    'profileCredentials': [for (final p in profileCredentials) p.toJson()],
  };

  Future<Uint8List> encode({String? password}) async {
    final data = _payload();
    final bytes = await compute(_encode, (data, password));
    if (bytes.length > maxBytes) throw const FormatException();
    return bytes;
  }

  static Uint8List _encode((Map<String, Object>, String?) request) {
    final (data, password) = request;
    final root = <String, Object>{'format': _format, 'version': _version};
    if (password == null) {
      root['data'] = data;
    } else {
      if (password.isEmpty) throw const FormatException();
      final salt = EncryptionService.generateSalt();
      final key = EncryptionService.deriveKey(
        password,
        salt,
        iterations: _iterations,
      );
      root['salt'] = base64Encode(salt);
      root['encrypted'] = base64Encode(
        EncryptionService.encrypt(
          Uint8List.fromList(utf8.encode(jsonEncode(data))),
          key,
        ),
      );
    }
    return Uint8List.fromList(utf8.encode(jsonEncode(root)));
  }

  static Map<String, dynamic> _envelope(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) throw const FormatException();
    final root = jsonDecode(utf8.decode(bytes));
    if (root is! Map<String, dynamic> ||
        root['format'] != _format ||
        root['version'] != _version ||
        (root.containsKey('data') == root.containsKey('encrypted'))) {
      throw const FormatException();
    }
    return root;
  }

  static bool isEncrypted(Uint8List bytes) =>
      _envelope(bytes).containsKey('encrypted');

  static Future<SettingsBackup> decode(Uint8List bytes, {String? password}) =>
      compute(_decode, (bytes, password));

  static SettingsBackup _decode((Uint8List, String?) request) {
    final (bytes, password) = request;
    final root = _envelope(bytes);
    var payload = root['data'];
    if (root.containsKey('encrypted')) {
      if (password == null || password.isEmpty) throw const FormatException();
      final salt = base64Decode(root['salt'] as String);
      if (salt.length != 16) throw const FormatException();
      final key = EncryptionService.deriveKey(
        password,
        salt,
        iterations: _iterations,
      );
      payload = jsonDecode(
        utf8.decode(
          EncryptionService.decrypt(
            base64Decode(root['encrypted'] as String),
            key,
          ),
        ),
      );
    }
    if (payload is! Map<String, dynamic>) throw const FormatException();
    final credentials = Map<String, String>.from(payload['credentials'] as Map);
    if (credentials.keys.any(
      (key) => !_loginKeys.contains(key) && !_headerKeys.contains(key),
    )) {
      throw const FormatException();
    }
    for (final entry in credentials.entries) {
      if (_loginKeys.contains(entry.key) && jsonDecode(entry.value) is! Map) {
        throw const FormatException();
      }
    }
    return SettingsBackup._(
      _validatedPrefs(payload['preferences'], _settings),
      _validatedPrefs(payload['cloud'], _cloud),
      credentials,
      _projectProfiles(_parseProfiles(payload['profiles']), secrets: false),
      _projectProfiles(
        _parseProfiles(payload['profileCredentials']),
        secrets: true,
      ),
    );
  }

  static Map<String, Object> _validatedPrefs(
    Object? value,
    Map<String, Type> schema,
  ) {
    if (value is! Map<String, dynamic>) throw const FormatException();
    return {
      for (final entry in value.entries)
        if (schema.containsKey(entry.key))
          entry.key: _validPreference(entry.key, entry.value, schema[entry.key])
              ? schema[entry.key] == double
                    ? (entry.value as num).toDouble()
                    : entry.value as Object
              : (throw const FormatException()),
    };
  }

  Future<void> restore(
    SharedPreferences prefs, {
    SecureStorage? storage,
    required bool includeCloud,
    required bool includeCredentials,
  }) => _lock.synchronized(() async {
    await prefs.reload();
    final preferenceChanges = {
      ...preferences,
      if (includeCloud) ...cloud,
      if (includeCredentials)
        for (final entry in credentials.entries)
          if (_headerKeys.contains(entry.key)) entry.key: entry.value,
    };
    final secureChanges = <String, String>{
      if (includeCredentials)
        for (final entry in credentials.entries)
          if (_loginKeys.contains(entry.key)) entry.key: entry.value,
    };
    final profileChanges = [
      if (includeCloud) ...profiles,
      if (includeCredentials) ...profileCredentials,
    ];
    final oldProfileData = profileChanges.isEmpty
        ? null
        : await _needStorage(storage).read(_profileKey);
    if (profileChanges.isNotEmpty) {
      final merged = {
        for (final p in _readProfiles(oldProfileData)) (p.provider, p.name): p,
      };
      for (final p in profileChanges) {
        final id = (p.provider, p.name);
        merged[id] = ConnectionProfile(
          name: p.name,
          provider: p.provider,
          fields: {...?merged[id]?.fields, ...p.fields},
        );
      }
      secureChanges[_profileKey] = jsonEncode(
        merged.values.map((p) => p.toJson()).toList(),
      );
    }
    final previousSecure = {
      for (final key in secureChanges.keys)
        key: key == _profileKey
            ? oldProfileData
            : await _needStorage(storage).read(key),
    };
    final previousPrefs = {
      for (final key in preferenceChanges.keys) key: prefs.get(key),
    };
    final rollback = <Future<void> Function()>[];
    try {
      for (final entry in secureChanges.entries) {
        final secure = _needStorage(storage);
        final old = previousSecure[entry.key];
        rollback.add(
          () => old == null
              ? secure.delete(entry.key)
              : secure.write(entry.key, old),
        );
        await secure.write(entry.key, entry.value);
        if (await secure.read(entry.key) != entry.value) {
          throw StateError('Credential restore could not be verified.');
        }
      }
      for (final entry in preferenceChanges.entries) {
        rollback.add(
          () => _writePreference(prefs, entry.key, previousPrefs[entry.key]),
        );
        await _writePreference(prefs, entry.key, entry.value);
      }
    } catch (_) {
      var rollbackFailed = false;
      for (final undo in rollback.reversed) {
        try {
          await undo();
        } catch (_) {
          rollbackFailed = true;
        }
      }
      throw SettingsRestoreException(rollbackFailed: rollbackFailed);
    }
  });

  static Future<void> _writePreference(
    SharedPreferences prefs,
    String key,
    Object? value,
  ) async {
    final saved = await switch (value) {
      null => prefs.remove(key),
      final bool data => prefs.setBool(key, data),
      final int data => prefs.setInt(key, data),
      final double data => prefs.setDouble(key, data),
      final String data => prefs.setString(key, data),
      _ => throw const FormatException(),
    };
    if (!saved) throw StateError('Preference restore could not be saved.');
  }
}

class SettingsRestoreException implements Exception {
  const SettingsRestoreException({required this.rollbackFailed});
  final bool rollbackFailed;
}
