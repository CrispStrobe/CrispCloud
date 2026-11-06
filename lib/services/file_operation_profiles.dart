import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'file_operation_options.dart';

/// User-selected defaults and named profiles. Contains options only, never
/// source/destination accounts, selected filenames, tokens or credentials.
class FileOperationProfiles {
  static const _key = 'commander.transfer.profiles.v1';

  Future<Map<String, FileOperationOptions>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['version'] != 1) {
      throw const FormatException('Unsupported transfer profile format.');
    }
    return (decoded['profiles'] as Map).map(
      (name, value) => MapEntry(
        name as String,
        FileOperationOptions.fromJson(Map<String, dynamic>.from(value as Map)),
      ),
    );
  }

  Future<void> save(String name, FileOperationOptions options) async {
    name = name.trim();
    if (name.isEmpty || name.length > 100) {
      throw const FormatException(
        'Use a profile name between 1 and 100 characters.',
      );
    }
    final profiles = await load();
    // Profiles should never silently redirect a later selection or rename it
    // to a previous single-file name. Those fields belong to each preview.
    final safe = options.toJson()
      ..['relativeBase'] = null
      ..['destinationName'] = null;
    profiles[name] = FileOperationOptions.fromJson(safe);
    await _write(profiles);
  }

  Future<void> remove(String name) async {
    final profiles = (await load())..remove(name);
    await _write(profiles);
  }

  Future<void> _write(Map<String, FileOperationOptions> profiles) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _key,
      jsonEncode({
        'version': 1,
        'profiles': profiles.map((key, value) => MapEntry(key, value.toJson())),
      }),
    );
    if (!saved) throw StateError('Transfer preferences could not be saved.');
  }
}
