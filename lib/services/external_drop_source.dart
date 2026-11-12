import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'file_operation_service.dart';
import 'panel_source_service.dart';
import 'storage_identity.dart';

enum ExternalDropFailure {
  invalidItems,
  duplicateNames,
  unavailable,
  changed,
  tooLarge,
  releaseFailed,
}

class ExternalDropException implements Exception {
  const ExternalDropException(this.failure);
  final ExternalDropFailure failure;
  @override
  String toString() => 'Dropped files: ${failure.name}';
}

/// Access belongs to this drop only. Bookmark bytes are never persisted.
abstract interface class ExternalDropAccess {
  Future<bool> start(Uint8List bookmark);
  Future<bool> stop(Uint8List bookmark);
}

class DesktopExternalDropAccess implements ExternalDropAccess {
  const DesktopExternalDropAccess();
  @override
  Future<bool> start(Uint8List bookmark) => DesktopDrop.instance
      .startAccessingSecurityScopedResource(bookmark: bookmark);
  @override
  Future<bool> stop(Uint8List bookmark) => DesktopDrop.instance
      .stopAccessingSecurityScopedResource(bookmark: bookmark);
}

/// A foreground-only copy source. Native paths remain under their dropped
/// scopes; browser files retain their supplied handles instead of being saved
/// into whichever local folder happens to be visible later.
class ExternalDropSource {
  ExternalDropSource._(this.backend, this.files, this._lifetime);
  final FileOperationBackend backend;
  final List<FileItem> files;
  final _DropLifetime _lifetime;
  bool get isCurrent => _lifetime.active;

  static const maxEntries = 200000;
  static const maxDepth = 256;
  static const maxNameBytes = 8 * 1024 * 1024;

  static Future<ExternalDropSource> prepare(
    List<DropItem> items, {
    bool browser = kIsWeb,
    ExternalDropAccess access = const DesktopExternalDropAccess(),
    bool Function()? canContinue,
  }) async {
    final lifetime = _DropLifetime(access);
    void check() {
      lifetime.check();
      if (!(canContinue?.call() ?? true)) {
        throw const ExternalDropException(ExternalDropFailure.unavailable);
      }
    }

    try {
      check();
      if (items.isEmpty) {
        throw const ExternalDropException(ExternalDropFailure.invalidItems);
      }
      if (items.length > maxEntries) {
        throw const ExternalDropException(ExternalDropFailure.tooLarge);
      }
      if (browser) {
        final backend = _BrowserDropBackend(lifetime);
        var nameBytes = 0;
        Future<FileItem> add(DropItem item, String parent, int depth) async {
          check();
          final name = item.name;
          if (name.isEmpty ||
              name == '.' ||
              name == '..' ||
              name.contains('/') ||
              name.contains(r'\') ||
              name.contains('\u0000') ||
              item is! DropItemFile && item is! DropItemDirectory) {
            throw const ExternalDropException(ExternalDropFailure.invalidItems);
          }
          final path = p.posix.join(parent, name);
          nameBytes += utf8.encode(path).length;
          if (depth > maxDepth ||
              backend.rows.length >= maxEntries ||
              nameBytes > maxNameBytes) {
            throw const ExternalDropException(ExternalDropFailure.tooLarge);
          }
          if (backend.rows.containsKey(path)) {
            throw const ExternalDropException(
              ExternalDropFailure.duplicateNames,
            );
          }
          final folder = item is DropItemDirectory;
          if (!folder && item.mimeType == 'directory') {
            throw const ExternalDropException(ExternalDropFailure.invalidItems);
          }
          final size = folder ? null : await item.length();
          check();
          if (size != null && size < 0) {
            throw const ExternalDropException(ExternalDropFailure.invalidItems);
          }
          final file = FileItem(
            name: name,
            path: path,
            isFolder: folder,
            size: size,
            updatedAt: folder ? null : await item.lastModified(),
          );
          check();
          backend.rows[path] = file;
          if (backend.rows.length % 256 == 0) {
            await Future<void>.delayed(Duration.zero);
            check();
          }
          if (folder) {
            backend.children[path] = [];
            for (final child in item.children) {
              backend.children[path]!.add(await add(child, path, depth + 1));
            }
          } else {
            backend.handles[path] = item;
          }
          return file;
        }

        final roots = <FileItem>[];
        for (final item in items) {
          roots.add(await add(item, '/', 0));
        }
        backend.children['/'] = roots;
        check();
        return ExternalDropSource._(
          backend,
          List.unmodifiable(roots),
          lifetime,
        );
      }

      for (final item in items) {
        check();
        final bookmark = item.extraAppleBookmark;
        if (bookmark != null && bookmark.isNotEmpty) {
          final captured = Uint8List.fromList(bookmark);
          if (!await access.start(captured)) {
            throw const ExternalDropException(ExternalDropFailure.unavailable);
          }
          lifetime.bookmarks.add(captured);
          check();
        }
      }
      final backend = _NativeDropBackend(lifetime);
      final roots = <FileItem>[];
      final seen = <String>{};
      for (final item in items) {
        check();
        final path = item.path;
        if (!p.isAbsolute(path) || path.contains('\u0000')) {
          throw const ExternalDropException(ExternalDropFailure.invalidItems);
        }
        final normalized = p.normalize(path);
        // Case-folded destination collision keys cannot discard distinct
        // selected files on a case-sensitive source volume.
        if (!seen.add(normalized)) continue;
        final file = await backend.readMetadataAt(normalized);
        check();
        if (file == null) {
          throw const ExternalDropException(ExternalDropFailure.unavailable);
        }
        roots.add(file);
      }
      backend.roots = List.unmodifiable(roots);
      return ExternalDropSource._(backend, backend.roots, lifetime);
    } catch (_) {
      await lifetime.close();
      rethrow;
    }
  }

  Future<void> close() => _lifetime.close();
}

class _DropLifetime {
  _DropLifetime(this.access);
  final ExternalDropAccess access;
  final bookmarks = <Uint8List>[];
  bool active = true;
  void check() {
    if (!active) {
      throw const ExternalDropException(ExternalDropFailure.unavailable);
    }
  }

  Future<void> close() async {
    if (!active) return;
    active = false;
    var failed = false;
    for (final bookmark in bookmarks.reversed) {
      try {
        if (!await access.stop(bookmark)) failed = true;
      } catch (_) {
        failed = true;
      }
    }
    bookmarks.clear();
    if (failed) {
      throw const ExternalDropException(ExternalDropFailure.releaseFailed);
    }
  }
}

abstract class _ExternalDropBackend extends FileOperationBackend {
  _ExternalDropBackend(this.lifetime);
  final _DropLifetime lifetime;
  @override
  bool get isCurrent => lifetime.active;
  @override
  String get label => 'Dropped files';

  Stream<List<int>> checkedStream(Stream<List<int>> stream, int length) async* {
    var received = 0;
    await for (final chunk in stream) {
      lifetime.check();
      received += chunk.length;
      if (received > length) {
        throw const ExternalDropException(ExternalDropFailure.changed);
      }
      for (var offset = 0; offset < chunk.length; offset += 65536) {
        lifetime.check();
        yield chunk.sublist(offset, (offset + 65536).clamp(0, chunk.length));
      }
    }
    lifetime.check();
    if (received != length) {
      throw const ExternalDropException(ExternalDropFailure.changed);
    }
  }

  @override
  Future<void> createDirectory(String path) async =>
      throw UnsupportedError('Dropped files are a read-only copy source.');
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async =>
      throw UnsupportedError('Dropped files are a read-only copy source.');
  @override
  Future<void> deleteFile(FileItem file) async =>
      throw UnsupportedError('Dropped files are a read-only copy source.');
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw UnsupportedError('Dropped files are a read-only copy source.');
}

class _BrowserDropBackend extends _ExternalDropBackend {
  _BrowserDropBackend(super.lifetime);
  final rows = <String, FileItem>{};
  final handles = <String, DropItem>{};
  final children = <String, List<FileItem>>{};
  final Object _identity = Object();
  @override
  Object get identity => _identity;
  @override
  p.Context get paths => p.posix;
  @override
  Future<FileItem?> stat(String path) async {
    lifetime.check();
    if (path == '/') return FileItem(name: '/', path: '/', isFolder: true);
    return rows[path];
  }

  @override
  Future<List<FileItem>> list(String path) async {
    lifetime.check();
    final entries = children[path];
    if (entries == null) {
      throw const ExternalDropException(ExternalDropFailure.invalidItems);
    }
    // The planner sorts each returned directory list. Give it a mutable copy
    // without exposing the captured manifest itself to modification.
    return List.of(entries);
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    lifetime.check();
    final current = rows[file.path];
    final handle = handles[file.path];
    if (current == null || handle == null || current.size != file.size) {
      throw const ExternalDropException(ExternalDropFailure.changed);
    }
    yield* checkedStream(handle.openRead(), current.size!);
  }
}

class _NativeDropBackend extends _ExternalDropBackend {
  _NativeDropBackend(super.lifetime);
  List<FileItem> roots = const [];
  @override
  Object get identity =>
      storageReferenceForSource(const LocalPanelSource('/')).id;
  @override
  p.Context get paths => p.context;
  @override
  String pathKey(String path) => Platform.isWindows || Platform.isMacOS
      ? paths.normalize(path).toLowerCase()
      : paths.normalize(path);

  Future<FileItem?> readMetadataAt(String path) async {
    lifetime.check();
    final type = await FileSystemEntity.type(path, followLinks: false);
    lifetime.check();
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw const ExternalDropException(ExternalDropFailure.invalidItems);
    }
    final stat = await FileStat.stat(path);
    lifetime.check();
    if (stat.type != type) {
      throw const ExternalDropException(ExternalDropFailure.changed);
    }
    return FileItem(
      name: paths.basename(path),
      path: path,
      isFolder: type == FileSystemEntityType.directory,
      size: type == FileSystemEntityType.file ? stat.size : null,
      updatedAt: stat.modified,
    );
  }

  Future<void> _checkPath(String path) async {
    lifetime.check();
    if (!paths.isAbsolute(path) || path.contains('\u0000')) {
      throw const ExternalDropException(ExternalDropFailure.invalidItems);
    }
    final matches = roots.where(
      (root) =>
          samePath(root.path!, path) ||
          root.isFolder && isWithin(root.path!, path),
    );
    if (matches.isEmpty) {
      throw const ExternalDropException(ExternalDropFailure.invalidItems);
    }
    final root = matches.reduce(
      (a, b) => a.path!.length > b.path!.length ? a : b,
    );
    var ancestor = paths.dirname(path);
    while (isWithin(root.path!, ancestor) || samePath(root.path!, ancestor)) {
      if (await FileSystemEntity.type(ancestor, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const ExternalDropException(ExternalDropFailure.changed);
      }
      lifetime.check();
      if (samePath(root.path!, ancestor)) break;
      ancestor = paths.dirname(ancestor);
    }
  }

  @override
  Future<FileItem?> stat(String path) async {
    await _checkPath(path);
    return readMetadataAt(paths.normalize(path));
  }

  @override
  Future<List<FileItem>> list(String path) async {
    await _checkPath(path);
    final folder = await readMetadataAt(path);
    if (folder?.isFolder != true) {
      throw const ExternalDropException(ExternalDropFailure.changed);
    }
    final entries = <FileItem>[];
    await for (final entry in Directory(path).list(followLinks: false)) {
      lifetime.check();
      if (entries.length >= ExternalDropSource.maxEntries) {
        throw const ExternalDropException(ExternalDropFailure.tooLarge);
      }
      final item = await readMetadataAt(entry.path);
      if (item == null) {
        throw const ExternalDropException(ExternalDropFailure.changed);
      }
      entries.add(item);
    }
    lifetime.check();
    return entries;
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    final before = await stat(file.path!);
    bool same(FileItem? current) =>
        current != null &&
        !current.isFolder &&
        current.size == file.size &&
        current.updatedAt == file.updatedAt;
    if (!same(before)) {
      throw const ExternalDropException(ExternalDropFailure.changed);
    }
    yield* checkedStream(File(file.path!).openRead(), before!.size!);
    if (!same(await stat(file.path!))) {
      throw const ExternalDropException(ExternalDropFailure.changed);
    }
  }
}
