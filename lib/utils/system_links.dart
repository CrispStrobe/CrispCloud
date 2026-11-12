import 'dart:io';

import 'package:path/path.dart' as p;

/// Whether [path] is a symbolic link directly below the filesystem root, such
/// as macOS's `/var`, `/tmp` and `/etc` (links into `/private`). Only an
/// administrator can create entries in `/`, so such links cannot be used to
/// redirect a write or an extraction. Links anywhere a user can create them
/// are still refused by the callers.
bool isSystemRootLink(String path) {
  if (Platform.isWindows) return false;
  final normalized = p.normalize(path);
  final root = p.rootPrefix(normalized);
  return p.isAbsolute(normalized) &&
      normalized != root &&
      p.dirname(normalized) == root;
}

/// [FileSystemEntity.type] without following links, except that a
/// [isSystemRootLink] reports the type of its target (macOS `/var` is a
/// directory for every purpose of these checks).
Future<FileSystemEntityType> entityTypeTrustingSystemLinks(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.link && isSystemRootLink(path)) {
    return FileSystemEntity.type(path, followLinks: true);
  }
  return type;
}
