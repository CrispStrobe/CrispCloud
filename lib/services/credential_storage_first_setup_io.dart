import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Preserve inspection errors: FileSystemEntity.type reports notFound for
/// lookup failures too, including access denied and a non-directory ancestor.
/// Only the OS's actual missing-path result establishes absence here.
Future<List<FileSystemEntity>?> _listDirectoryOrAbsent(
  Directory directory,
) async {
  try {
    return await directory.list(followLinks: false).toList();
  } on FileSystemException catch (error) {
    final code = error.osError?.errorCode;
    if (code != 2 && !(Platform.isWindows && code == 3)) rethrow;
    // Windows PATH_NOT_FOUND can also mean an intermediate component is a
    // regular file. Confirm a genuinely absent component through the nearest
    // readable parent; a present but unlistable file/link is ambiguous.
    final path = p.normalize(directory.absolute.path);
    final parentPath = p.dirname(path);
    if (parentPath == path) rethrow;
    final parentEntries = await _listDirectoryOrAbsent(Directory(parentPath));
    if (parentEntries != null &&
        parentEntries.any(
          (entry) =>
              p.basename(entry.path).toLowerCase() ==
              p.basename(path).toLowerCase(),
        )) {
      rethrow;
    }
    return null;
  }
}

/// Checks for any previous native profile, including cached files, vaults, and
/// legacy provider configuration. Empty support directories are allowed because
/// path_provider can create that directory while resolving its location.
Future<bool> nativeCredentialProfileIsEmpty({
  Directory? supportDirectory,
  String? legacyConfigPath,
  Map<String, Object?> setupPreferences = const {},
}) async {
  try {
    final suppliedSupport =
        supportDirectory ?? await getApplicationSupportDirectory();
    // A trailing separator makes some OS lookups follow a directory symlink
    // even with followLinks:false. Normalize before inspecting. Parent
    // traversal through a symlink has different semantics from lexical '..'
    // normalization, so it cannot establish fresh-profile evidence.
    if (p.split(suppliedSupport.path).contains('..')) return false;
    final support = Directory(p.normalize(suppliedSupport.path));
    String legacyPath;
    if (legacyConfigPath != null) {
      legacyPath = legacyConfigPath;
    } else if (Platform.isAndroid || Platform.isIOS) {
      legacyPath = p.join(support.path, '.cloud-storage-config');
    } else {
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home == null || home.isEmpty) return false;
      legacyPath = p.join(home, '.cloud-storage-config');
    }
    if (p.split(legacyPath).contains('..')) return false;
    legacyPath = p.normalize(legacyPath);
    if (await FileSystemEntity.type(legacyPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return false;
    }
    // A notFound type alone cannot distinguish an absent legacy directory from
    // an inaccessible profile. Inspect its parent without following entries.
    final legacyParentEntries = await _listDirectoryOrAbsent(
      Directory(p.dirname(legacyPath)),
    );
    if (legacyParentEntries != null &&
        legacyParentEntries.any(
          (entry) =>
              p.basename(entry.path).toLowerCase() ==
              p.basename(legacyPath).toLowerCase(),
        )) {
      // Case-insensitive filesystems can resolve a differently-cased name;
      // on case-sensitive filesystems, an ambiguous old profile is not fresh.
      return false;
    }
    final type = await FileSystemEntity.type(support.path, followLinks: false);
    if (type != FileSystemEntityType.directory &&
        type != FileSystemEntityType.notFound) {
      return false;
    }
    final entries = await _listDirectoryOrAbsent(support);
    if (entries == null) return true;
    for (final entry in entries) {
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
            expected.entries.every(
              (pair) =>
                  decoded.containsKey(pair.key) &&
                  decoded[pair.key] == pair.value,
            )) {
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
