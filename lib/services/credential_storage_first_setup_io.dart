import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Checks for any previous native profile, including cached files, vaults, and
/// legacy provider configuration. Empty support directories are allowed because
/// path_provider can create that directory while resolving its location.
Future<bool> nativeCredentialProfileIsEmpty({
  Directory? supportDirectory,
  String? legacyConfigPath,
  Map<String, Object?> setupPreferences = const {},
}) async {
  try {
    final support = supportDirectory ?? await getApplicationSupportDirectory();
    String legacyPath;
    if (legacyConfigPath != null) {
      legacyPath = legacyConfigPath;
    } else if (Platform.isAndroid || Platform.isIOS) {
      legacyPath = p.join(support.path, '.cloud-storage-config');
    } else {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'];
      if (home == null || home.isEmpty) return false;
      legacyPath = p.join(home, '.cloud-storage-config');
    }
    if (await FileSystemEntity.type(legacyPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return false;
    }
    final type = await FileSystemEntity.type(support.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return true;
    if (type != FileSystemEntityType.directory) return false;
    await for (final entry in support.list(followLinks: false)) {
      // shared_preferences_linux/windows 2.4.1 stores its own JSON in this
      // directory. Permit only the exact already-checked setup preferences,
      // never arbitrary contents, unknown entries, or a symlink with this name.
      if ((Platform.isLinux || Platform.isWindows) &&
          p.basename(entry.path) == 'shared_preferences.json' &&
          entry is File &&
          await entry.length() <= 65536) {
        final decoded = jsonDecode(await entry.readAsString());
        final expected = {
          for (final pair in setupPreferences.entries)
            'flutter.${pair.key}': pair.value,
        };
        if (decoded is Map &&
            decoded.length == expected.length &&
            expected.entries.every((pair) =>
                decoded.containsKey(pair.key) && decoded[pair.key] == pair.value)) {
          continue;
        }
      }
      return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}
