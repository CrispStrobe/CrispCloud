import 'dart:io';

import 'package:path/path.dart' as p;

/// Remove only the old SDK credential file after its replacement was verified,
/// or during an explicit persistent logout. Never follow an unexpected link or
/// recursively remove a directory. Keep this small operation synchronous so a
/// widget's fake async zone cannot strand native filesystem completion events.
void deleteLegacyFilenCredentials(String configPath) {
  if (configPath.isEmpty || configPath.contains('\u0000')) {
    throw StateError('The Filen credential directory is invalid.');
  }
  final directoryType = FileSystemEntity.typeSync(configPath, followLinks: false);
  if (directoryType != FileSystemEntityType.directory &&
      directoryType != FileSystemEntityType.notFound) {
    throw StateError('The Filen credential directory is not a regular directory.');
  }

  // typeSync returns notFound for lookup errors too. Listing distinguishes a
  // genuinely missing directory from an unavailable one; never report access
  // denied as successful cleanup. Missing parents are also harmless here.
  final List<FileSystemEntity> entries;
  try {
    entries = Directory(configPath).listSync(followLinks: false);
  } on FileSystemException catch (error) {
    final code = error.osError?.errorCode;
    if (code == 2 || (Platform.isWindows && code == 3)) return;
    rethrow;
  }
  if (!entries.any((entry) => p.basename(entry.path) == 'credentials.json')) {
    return;
  }

  final path = p.join(configPath, 'credentials.json');
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type != FileSystemEntityType.file) {
    throw StateError('The legacy Filen credential entry is not a regular file.');
  }
  File(path).deleteSync();
  if (Directory(configPath).listSync(followLinks: false).any(
    (entry) => p.basename(entry.path) == 'credentials.json',
  )) {
    throw StateError('The legacy Filen credential file could not be removed.');
  }
}
