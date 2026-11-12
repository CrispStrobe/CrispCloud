import 'dart:io';

import 'package:path/path.dart' as p;

/// When [path] is a symbolic link (or a chain of links) whose final target
/// does not exist, returns that missing target; otherwise null.
///
/// A dangling link, for example one into an unmounted volume, cannot be fixed
/// by granting folder access, so callers report it instead of opening the
/// folder picker. Only the link itself and metadata are read.
Future<String?> missingLinkTarget(String path) async {
  var current = path;
  for (var hop = 0; hop < 40; hop++) {
    if (await FileSystemEntity.type(current, followLinks: false) !=
        FileSystemEntityType.link) {
      return null;
    }
    final String target;
    try {
      target = await Link(current).target();
    } on FileSystemException {
      return null;
    }
    final resolved = p.normalize(
      p.isAbsolute(target) ? target : p.join(p.dirname(current), target),
    );
    final type = await FileSystemEntity.type(resolved, followLinks: false);
    if (type == FileSystemEntityType.notFound) return resolved;
    if (type != FileSystemEntityType.link) return null;
    current = resolved;
  }
  return null;
}

/// User-facing explanation for a dangling link at [path].
String missingLinkMessage(String path, String target) =>
    '"${p.basename(path)}" is a link to "$target", which does not exist '
    '(for example an unmounted volume).';
