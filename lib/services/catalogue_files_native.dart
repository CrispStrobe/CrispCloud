import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'macos_bookmark_service.dart';

Future<Directory> _root() async {
  final support = await getApplicationSupportDirectory();
  final root = Directory(p.join(support.path, 'Catalogues'));
  await root.create(recursive: true);
  return root;
}

Future<String> allocateCataloguePath(
  String id, {
  String extension = 'crispindex',
}) async {
  if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(id) ||
      !['crispindex', 'caf', 'download'].contains(extension)) {
    throw ArgumentError('Invalid owned catalogue path.');
  }
  return p.join((await _root()).path, '$id.$extension');
}

Future<void> discardOwnedCatalogueFile(String path) async {
  final root = await _root();
  if (!p.equals(p.dirname(p.absolute(path)), p.absolute(root.path))) {
    throw StateError('Only app-owned catalogue files may be removed.');
  }
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  if (type != FileSystemEntityType.file) {
    throw StateError('The catalogue file changed type; no file was removed.');
  }
  await File(path).delete();
}

Future<void> stageCatalogueStream(
  String path,
  Stream<List<int>> bytes, {
  required bool Function() cancelled,
}) async {
  final root = await _root();
  if (!p.equals(p.dirname(p.absolute(path)), p.absolute(root.path))) {
    throw StateError('Staging must remain app-owned.');
  }
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError('Catalogue staging path exists.');
  }
  await File(path).create(exclusive: true);
  final output = await File(path).open(mode: FileMode.writeOnly);
  try {
    await for (final chunk in bytes) {
      if (cancelled()) throw StateError('Catalogue transfer stopped.');
      await output.writeFrom(chunk);
    }
    if (cancelled()) throw StateError('Catalogue transfer stopped.');
    await output.flush();
  } finally {
    await output.close();
  }
}

Future<void> rememberPickedCatalogue(String path) async {
  if (Platform.isMacOS && !await MacOSBookmarkService.hasAccessToPath(path)) {
    await MacOSBookmarkService.addBookmark(path);
  }
}

/// Resolve a user-linked catalogue reference inside that selected root. The
/// catalogue cannot supply absolute paths, '..', or links escaping the root.
Future<Map<String, dynamic>> resolveCatalogueReference(
  String root,
  String relative,
) async {
  if (relative.isEmpty ||
      relative.startsWith('/') ||
      relative.contains('\\') ||
      relative
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw StateError('Invalid relative catalogue path.');
  }
  final canonicalRoot = await Directory(root).resolveSymbolicLinks();
  final candidate = p.joinAll([canonicalRoot, ...relative.split('/')]);
  final type = await FileSystemEntity.type(candidate, followLinks: false);
  if (type != FileSystemEntityType.file &&
      type != FileSystemEntityType.directory) {
    throw StateError('The indexed item is missing or is now a link.');
  }
  final target = await File(candidate).resolveSymbolicLinks();
  if (!p.isWithin(canonicalRoot, target)) {
    throw StateError(
      'The indexed path now resolves outside the linked folder.',
    );
  }
  final stat = await FileStat.stat(target);
  return {
    'path': target,
    'isFolder': type == FileSystemEntityType.directory,
    'bytes': stat.size,
    'modified': stat.modified.millisecondsSinceEpoch ~/ 1000,
  };
}
