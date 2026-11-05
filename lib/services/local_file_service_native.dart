// services/local_file_service_native.dart
//
// All native (non-web) LocalFileService implementations:
// MacosFileService, DesktopFileService, MobileFileService

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import '../models/file_item.dart';
import 'bookmark_service.dart';
import 'local_file_service.dart';
import 'macos_bookmark_service.dart';
import '../utils/path_access.dart';

LocalFileService createPlatformFileService() {
  if (Platform.isMacOS) return MacosFileService();
  if (Platform.isAndroid || Platform.isIOS) return MobileFileService();
  if (Platform.isWindows || Platform.isLinux) return DesktopFileService();
  throw UnsupportedError('Unsupported platform');
}

/// Stage editor output beside the destination and replace it only after the
/// bytes have been flushed. A failed write never truncates the original.
///
/// Existing file mode bits are inherited by staging from a copy. Symlinks
/// are deliberately rejected: replacing their inode would replace the link
/// rather than editing its target. Callers can save a separate copy instead.
/// This is atomic replacement on filesystems supporting rename-over-file; it
/// is not a compare-and-swap with the editor's earlier conflict check.
Future<void> writeLocalEditorFile(
  String path,
  Uint8List data, {
  bool overwrite = true,
}) async {
  final destination = File(path);
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.link) {
    throw FileSystemException(
      'Save a separate copy when editing a symbolic link.',
      path,
    );
  }
  if (type == FileSystemEntityType.directory) {
    throw FileSystemException('The destination is a directory.', path);
  }
  if (!overwrite && type != FileSystemEntityType.notFound) {
    throw FileSystemException(
      'A file already exists with that name.',
      path,
      const OSError('File exists', 17),
    );
  }
  if (!await destination.parent.exists()) {
    await destination.parent.create(recursive: true);
  }

  if (!overwrite) {
    // Dart exposes exclusive file creation but no rename-without-replacement.
    // Reserve an unused path before writing. This rejects known collisions;
    // the API does not prevent another process replacing that reservation.
    // The original document remains untouched even on failure.
    await destination.create(exclusive: true);
    try {
      await destination.writeAsBytes(data, flush: true);
    } catch (_) {
      try {
        await destination.delete();
      } catch (_) {
        // Preserve the write error; an incomplete copy is never a clean save.
      }
      rethrow;
    }
    return;
  }

  final staging = await destination.parent.createTemp('.crisp-pdf-save-');
  final staged = File('${staging.path}${Platform.pathSeparator}document.pdf');
  try {
    int? originalMode;
    if (type == FileSystemEntityType.file) {
      if (!Platform.isWindows) {
        originalMode = (await destination.stat()).mode & 0xfff;
        // Rename permission on the parent can bypass a read-only file's mode.
        // Do not silently turn that into permission to replace its contents.
        if ((originalMode & 0x92) == 0) {
          throw FileSystemException(
            'The PDF is read-only. Save a separate copy.',
            path,
          );
        }
      }
      await destination.copy(staged.path);
      if (originalMode != null) {
        final stagedMode = (await staged.stat()).mode & 0xfff;
        if (originalMode != stagedMode) {
          throw FileSystemException(
            'Could not preserve file permissions. Save a separate copy.',
            path,
          );
        }
      }
    }
    await staged.writeAsBytes(data, flush: true);
    if (originalMode != null &&
        ((await staged.stat()).mode & 0xfff) != originalMode) {
      throw FileSystemException(
        'Could not preserve file permissions. Save a separate copy.',
        path,
      );
    }
    await staged.rename(path);
  } finally {
    try {
      await staging.delete(recursive: true);
    } catch (_) {
      // The destination's completed write must not become a failed save just
      // because removing an empty staging directory failed.
    }
  }
}

// --- macOS Implementation ---
class MacosFileService implements LocalFileService, LocalFileSaveReporter {
  String? _grantedBasePath;
  final _bookmarks = SecureBookmarks();
  List<FileSystemEntity> _resolvedBookmarks = <FileSystemEntity>[];
  FileSystemEntity? _streamScope;

  @override
  String currentPath = Platform.environment['HOME'] ?? '/';

  @override
  String? get grantedBasePath => _grantedBasePath;

  @override
  Map<String, dynamic> getWebMetadata(String path) => {};

  @override
  Object? getWebFileRef(String path) => null;

  @override
  Future<void> refresh() async {}

  Future<bool> _loadAndResolveBookmarks() async {
    try {
      _resolvedBookmarks = await MacOSBookmarkService.getResolvedBookmarks();
      if (_resolvedBookmarks.isNotEmpty) {
        _grantedBasePath = _resolvedBookmarks.last.path;
        return true;
      }
      _grantedBasePath = null;
      return false;
    } catch (e) {
      debugPrint('Failed to load or resolve bookmarks: $e');
      _resolvedBookmarks = <FileSystemEntity>[];
      _grantedBasePath = null;
      return false;
    }
  }

  FileSystemEntity? _scopeFor(String path) {
    for (final FileSystemEntity scope in _resolvedBookmarks) {
      if (isSameOrUnderPath(path, scope.path)) return scope;
    }
    return null;
  }

  /// Resolve symlinks before checking or acquiring access.
  ///
  /// A symlink under a granted folder can point into an ungranted volume. The
  /// sandbox then denies the target even though the link's path looks covered.
  Future<String> _accessPath(String path) async {
    // realpath resolves links in every path component, but the sandbox can
    // deny it when the target volume is not granted yet. Fall back to reading
    // the final symlink itself, which only needs access to the granted parent.
    try {
      return await File(path).resolveSymbolicLinks();
    } catch (_) {
      var current = path;
      for (var i = 0; i < 10; i++) {
        try {
          final type =
              await FileSystemEntity.type(current, followLinks: false);
          if (type != FileSystemEntityType.link) return current;
          final target = await Link(current).target();
          current = p.normalize(
            p.isAbsolute(target)
                ? target
                : p.join(p.dirname(current), target),
          );
        } catch (_) {
          break;
        }
      }
      try {
        return await Directory(path).resolveSymbolicLinks();
      } catch (_) {
        return current;
      }
    }
  }

  /// Probe the real operation under [scope]; a resolved bookmark alone does
  /// not prove that its security scope is still usable after a rebuild.
  Future<bool> _probeAccess(String path, FileSystemEntity? scope) async {
    var started = false;
    if (scope != null) {
      try {
        await _bookmarks.startAccessingSecurityScopedResource(scope);
        started = true;
      } catch (e) {
        debugPrint('Could not start security scope for $path: $e');
        return false;
      }
    }
    try {
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.notFound) {
        // A missing file is not a permission problem when a scope already
        // covers its folder; saving a new file there is still allowed.
        return scope != null;
      }
      if (type == FileSystemEntityType.directory) {
        return await Directory(path).exists();
      }
      final handle = await File(path).open();
      await handle.close();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (started) {
        try {
          await _bookmarks.stopAccessingSecurityScopedResource(scope!);
        } catch (_) {
          // Best effort.
        }
      }
    }
  }

  @override
  Future<String> getInitialPath() async {
    final grantedPath = await MacOSBookmarkService.getLastGrantedDirectory();
    if (grantedPath != null) {
      _grantedBasePath = grantedPath;
      currentPath = grantedPath;
      return currentPath;
    }
    currentPath = await getSafeFallbackDirectory();
    _grantedBasePath = null;
    return currentPath;
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    final path = await MacOSBookmarkService.requestDirectoryAccess(
      initialDirectory: initialDirectory,
    );
    if (path != null) {
      _grantedBasePath = path;
      currentPath = path;
      await _loadAndResolveBookmarks();
    }
    return path;
  }

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    currentPath = path;
    if (_resolvedBookmarks.isEmpty) {
      await _loadAndResolveBookmarks();
    }

    final String accessPath = await _accessPath(path);
    final FileSystemEntity? scope = _scopeFor(accessPath);
    if (scope != null) {
      try {
        await _bookmarks.startAccessingSecurityScopedResource(scope);
        final entities = await Directory(accessPath).list().toList();
        await _bookmarks.stopAccessingSecurityScopedResource(scope);
        return entities;
      } catch (e) {
        try { await _bookmarks.stopAccessingSecurityScopedResource(scope); } catch (_) {}
      }
    }

    try {
      return await Directory(accessPath).list().toList();
    } catch (e) {
      debugPrint('Failed to list directory: $e');
      rethrow;
    }
  }

  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async {
    if (_resolvedBookmarks.isEmpty) await _loadAndResolveBookmarks();

    final String accessPath = await _accessPath(path);
    final FileSystemEntity? readScope = _scopeFor(accessPath);
    if (readScope != null) {
      try {
        await _bookmarks.startAccessingSecurityScopedResource(readScope);
        final data = await File(accessPath).readAsBytes();
        await _bookmarks.stopAccessingSecurityScopedResource(readScope);
        return data;
      } catch (e) {
        try { await _bookmarks.stopAccessingSecurityScopedResource(readScope); } catch (_) {}
        rethrow;
      }
    }
    return File(accessPath).readAsBytes();
  }

  @override
  Future<void> saveFile(String path, Uint8List data) async {
    if (_resolvedBookmarks.isEmpty) await _loadAndResolveBookmarks();

    final String accessPath = await _accessPath(path);
    final FileSystemEntity? saveScope = _scopeFor(accessPath);
    if (saveScope != null) {
      try {
        await _bookmarks.startAccessingSecurityScopedResource(saveScope);
        final file = File(accessPath);
        if (!await file.parent.exists()) await file.parent.create(recursive: true);
        await file.writeAsBytes(data);
        await _bookmarks.stopAccessingSecurityScopedResource(saveScope);
        return;
      } catch (e) {
        try { await _bookmarks.stopAccessingSecurityScopedResource(saveScope); } catch (_) {}
        rethrow;
      }
    }

    final file = File(accessPath);
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsBytes(data);
  }

  @override
  Future<LocalFileSaveResult> saveFileWithResult(
    String path,
    Uint8List data, {
    bool overwrite = true,
  }) async {
    final scope = await _beginScope(path);
    try {
      await writeLocalEditorFile(path, data, overwrite: overwrite);
      return LocalFileSaveResult.written;
    } finally {
      await _endScope(scope);
    }
  }

  Future<FileSystemEntity?> _beginScope(String path) async {
    if (_resolvedBookmarks.isEmpty) await _loadAndResolveBookmarks();
    final String accessPath = await _accessPath(path);
    final FileSystemEntity? scope = _scopeFor(accessPath);
    if (scope == null) return null;
    try {
      await _bookmarks.startAccessingSecurityScopedResource(scope);
      return scope;
    } catch (e) {
      debugPrint('Failed to start security scope for $path: $e');
      return null;
    }
  }

  Future<void> _endScope(FileSystemEntity? scope) async {
    if (scope == null) return;
    try {
      await _bookmarks.stopAccessingSecurityScopedResource(scope);
    } catch (_) {
      // Best effort.
    }
  }

  @override
  Future<bool> hasAccessToPath(String path) async {
    if (_resolvedBookmarks.isEmpty) await _loadAndResolveBookmarks();

    // Check the real target, not just the symlink's lexical path. A link may
    // live under a granted folder while its target does not.
    final String accessPath = await _accessPath(path);
    final FileSystemEntity? scope = _scopeFor(accessPath);
    if (scope != null) {
      return _probeAccess(accessPath, scope);
    }

    // No bookmark covers the resolved target. Probe actual access instead of
    // assuming the home directory is readable: the sandbox denies most of it
    // until the user grants the containing folder.
    return _probeAccess(accessPath, null);
  }

  @override
  Future<bool> ensureAccess(String path) async {
    if (await hasAccessToPath(path)) return true;

    // Ask for the real target's folder. Re-picking the symlink's parent would
    // grant nothing when the link points into another volume.
    final String accessPath = await _accessPath(path);
    final granted = await requestDirectoryAccess(
      initialDirectory: File(accessPath).parent.path,
    );
    if (granted == null) return false;
    return hasAccessToPath(path);
  }

  @override
  Future<bool> beginStreamAccess(String path) async {
    if (!await ensureAccess(path)) return false;
    _streamScope = await _beginScope(path);
    return true;
  }

  @override
  Future<void> endStreamAccess() async {
    final scope = _streamScope;
    _streamScope = null;
    await _endScope(scope);
  }

  @override
  Future<T> withFileOperationAccess<T>(
      String path, Future<T> Function() action) async {
    if (!await ensureAccess(path)) {
      throw FileSystemException('Access to this path was not granted.', path);
    }
    final scope = await _beginScope(path);
    try {
      return await action();
    } finally {
      await _endScope(scope);
    }
  }

  @override
  Future<int?> fileLength(String path) async {
    if (!await hasAccessToPath(path) && !await ensureAccess(path)) return null;
    final String accessPath = await _accessPath(path);
    final scope = await _beginScope(path);
    try {
      return await File(accessPath).length();
    } on FileSystemException {
      return null;
    } finally {
      await _endScope(scope);
    }
  }

  @override
  Future<List<FileItem>> walkFiles(
    String path, {
    bool includeHidden = false,
    int maxItems = 10000,
  }) async {
    if (!await ensureAccess(path)) return const <FileItem>[];
    final scope = await _beginScope(path);
    try {
      return await walkLocalFiles(
        path,
        includeHidden: includeHidden,
        maxItems: maxItems,
      );
    } finally {
      await _endScope(scope);
    }
  }

  @override
  Future<void> createDirectory(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> deleteEntry(String path, bool isFolder) async {
    if (isFolder) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  @override
  Future<String> getSafeFallbackDirectory() async {
    return Platform.environment['HOME'] ?? '/';
  }
}

// --- Windows/Linux Implementation ---
class DesktopFileService implements LocalFileService, LocalFileSaveReporter {
  @override
  String currentPath = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/';

  @override
  String? get grantedBasePath => null;

  @override
  Map<String, dynamic> getWebMetadata(String path) => {};

  @override
  Object? getWebFileRef(String path) => null;

  @override
  Future<void> refresh() async {}

  @override
  Future<String> getInitialPath() async {
    final lastPath = await BookmarkService.getLastPath();
    try {
      if (lastPath != null && await Directory(lastPath).exists()) {
        currentPath = lastPath;
        return lastPath;
      }
    } catch (e) {
      debugPrint('Could not access last path, using fallback. Error: $e');
    }
    currentPath = await getSafeFallbackDirectory();
    return currentPath;
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Directory',
      lockParentWindow: true,
      initialDirectory: initialDirectory,
    );
    if (path != null) {
      await BookmarkService.saveLastPath(path);
      currentPath = path;
    }
    return path;
  }

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    currentPath = path;
    return Directory(path).list().toList();
  }

  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async {
    return File(path).readAsBytes();
  }

  @override
  Future<void> saveFile(String path, Uint8List data) async {
    final file = File(path);
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsBytes(data);
  }

  @override
  Future<LocalFileSaveResult> saveFileWithResult(
    String path,
    Uint8List data, {
    bool overwrite = true,
  }) async {
    await writeLocalEditorFile(path, data, overwrite: overwrite);
    return LocalFileSaveResult.written;
  }

  @override
  Future<bool> hasAccessToPath(String path) async => true;

  @override
  Future<void> createDirectory(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> deleteEntry(String path, bool isFolder) async {
    if (isFolder) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  @override
  Future<String> getSafeFallbackDirectory() async {
    return Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/';
  }

  @override
  Future<List<FileItem>> walkFiles(
    String path, {
    bool includeHidden = false,
    int maxItems = 10000,
  }) =>
      walkLocalFiles(
        path,
        includeHidden: includeHidden,
        maxItems: maxItems,
      );

  @override
  Future<bool> ensureAccess(String path) async => true;

  @override
  Future<bool> beginStreamAccess(String path) async => true;

  @override
  Future<void> endStreamAccess() async {}

  @override
  Future<int?> fileLength(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return null;
    }
  }

}

// --- Mobile (Android/iOS) Implementation ---
class MobileFileService implements LocalFileService, LocalFileSaveReporter {
  String? _grantedBasePath;
  static const String _mobileBookmarkKey = 'mobile_bookmark_data';
  final _bookmarks = SecureBookmarks();
  FileSystemEntity? _resolvedBookmarkFile;

  @override
  String currentPath = '/';

  @override
  String? get grantedBasePath => _grantedBasePath;

  @override
  Map<String, dynamic> getWebMetadata(String path) => {};

  @override
  Object? getWebFileRef(String path) => null;

  @override
  Future<void> refresh() async {}

  Future<bool> _loadAndResolveBookmark() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bookmarkBase64 = prefs.getString(_mobileBookmarkKey);
      if (bookmarkBase64 == null) return false;
      _resolvedBookmarkFile = await _bookmarks.resolveBookmark(bookmarkBase64);
      return true;
    } catch (e) {
      debugPrint('Failed to load or resolve mobile bookmark: $e');
      _resolvedBookmarkFile = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_mobileBookmarkKey);
      return false;
    }
  }

  @override
  Future<String> getInitialPath() async {
    if (await _loadAndResolveBookmark()) {
      try {
        if (await _resolvedBookmarkFile!.exists()) {
          _grantedBasePath = _resolvedBookmarkFile!.path;
          currentPath = _resolvedBookmarkFile!.path;
          return currentPath;
        } else {
          await SharedPreferences.getInstance().then((p) => p.remove(_mobileBookmarkKey));
        }
      } catch (e) {
        await SharedPreferences.getInstance().then((p) => p.remove(_mobileBookmarkKey));
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    _grantedBasePath = dir.path;
    currentPath = dir.path;
    return dir.path;
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select a Folder',
      initialDirectory: initialDirectory,
    );

    if (path != null) {
      try {
        final String bookmarkData = await _bookmarks.bookmark(Directory(path));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_mobileBookmarkKey, bookmarkData);
        _grantedBasePath = path;
        currentPath = path;
        await _loadAndResolveBookmark();
      } catch (e) {
        debugPrint('Error saving mobile bookmark: $e');
      }
    }
    return path;
  }

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    currentPath = path;

    if (_resolvedBookmarkFile == null) await _loadAndResolveBookmark();

    try {
      if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
        await _bookmarks.startAccessingSecurityScopedResource(_resolvedBookmarkFile!);
      }

      final entities = await Directory(path).list().toList();

      if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
      }

      return entities;
    } catch (e) {
      debugPrint('Failed to list mobile directory: $e');
      if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
      }
      rethrow;
    }
  }

  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async {
    if (_resolvedBookmarkFile == null) await _loadAndResolveBookmark();

    if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
      try {
        await _bookmarks.startAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        final data = await File(path).readAsBytes();
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        return data;
      } catch (e) {
        try { await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!); } catch (_) {}
        rethrow;
      }
    }

    return File(path).readAsBytes();
  }

  @override
  Future<void> saveFile(String path, Uint8List data) async {
    if (_resolvedBookmarkFile == null) await _loadAndResolveBookmark();

    if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
      try {
        await _bookmarks.startAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        final file = File(path);
        if (!await file.parent.exists()) await file.parent.create(recursive: true);
        await file.writeAsBytes(data);
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        return;
      } catch (e) {
        try { await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!); } catch (_) {}
        rethrow;
      }
    }
    final file = File(path);
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsBytes(data);
  }

  @override
  Future<LocalFileSaveResult> saveFileWithResult(
    String path,
    Uint8List data, {
    bool overwrite = true,
  }) async {
    if (_resolvedBookmarkFile == null) await _loadAndResolveBookmark();
    final scope = _resolvedBookmarkFile;
    final activeScope =
        scope != null && isSameOrUnderPath(path, scope.path) ? scope : null;
    if (activeScope != null) {
      await _bookmarks.startAccessingSecurityScopedResource(activeScope);
    }
    try {
      await writeLocalEditorFile(path, data, overwrite: overwrite);
      return LocalFileSaveResult.written;
    } finally {
      if (activeScope != null) {
        try {
          await _bookmarks.stopAccessingSecurityScopedResource(activeScope);
        } catch (_) {
          // Releasing access must not change the result of a completed write.
        }
      }
    }
  }

  @override
  Future<bool> hasAccessToPath(String path) async {
    if (path.startsWith(currentPath)) return true;
    if (_grantedBasePath != null && path.startsWith(_grantedBasePath!)) return true;
    try {
      await Directory(path).stat();
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> createDirectory(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> deleteEntry(String path, bool isFolder) async {
    if (isFolder) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  @override
  Future<String> getSafeFallbackDirectory() async {
    return (await getApplicationDocumentsDirectory()).path;
  }

  @override
  Future<List<FileItem>> walkFiles(
    String path, {
    bool includeHidden = false,
    int maxItems = 10000,
  }) =>
      walkLocalFiles(
        path,
        includeHidden: includeHidden,
        maxItems: maxItems,
      );

  @override
  Future<bool> ensureAccess(String path) async => true;

  @override
  Future<bool> beginStreamAccess(String path) async => true;

  @override
  Future<void> endStreamAccess() async {}

  @override
  Future<int?> fileLength(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return null;
    }
  }

}
