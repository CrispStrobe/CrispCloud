// services/local_file_service_web.dart
//
// Web implementation of LocalFileService using virtual filesystem.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;
import 'filen_web_stub.dart' if (dart.library.js_util) 'dart:js_util' as js_util;
import 'package:path/path.dart' as p;
import '../models/file_item.dart';
import 'local_file_service.dart';
import 'log_service.dart';

LocalFileService createPlatformFileService() {
  return WebFileService.instance;
}

class WebFileService implements LocalFileService {
  static const _log = Log('WebFS');

  // Singleton pattern to preserve state across reloads/instantiations
  static final WebFileService instance = WebFileService._internal();
  WebFileService._internal();

  // Stores directory structure: Key='/Photos', Value=[Entity('img.jpg')]
  static final Map<String, List<FileSystemEntity>> _virtualTree = {};
  // Stores actual file references: Key='/Photos/img.jpg', Value=FileObject
  static final Map<String, html.File> _fileRefs = {};

  // File System Access API Handles (Chrome/Edge only) — one per opened root folder.
  static final Map<String, dynamic> _rootHandles = {};

  @override
  String currentPath = '/';

  @override
  String? get grantedBasePath => null;

  @override
  Map<String, dynamic> getWebMetadata(String path) {
    final f = _fileRefs[path];
    if (f != null) {
      return {
        'size': f.size,
        'modified': DateTime.fromMillisecondsSinceEpoch(f.lastModified ?? DateTime.now().millisecondsSinceEpoch),
      };
    }
    return {};
  }

  /// Tries to use Modern API (Chrome), falls back to Legacy Input (Safari)
  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    _log.debug('requestDirectoryAccess: initial=$initialDirectory');
    // Ensure root listing exists (idempotent — don't clear other roots' data).
    if (!_virtualTree.containsKey('/')) {
      _virtualTree['/'] = [];
    }

    // 2. Try File System Access API (Chrome/Edge/Opera — skip on Safari)
    final userAgent = html.window.navigator.userAgent;
    final isSafari = userAgent.contains('Safari') && !userAgent.contains('Chrome') && !userAgent.contains('Chromium');
    if (!isSafari && js_util.hasProperty(html.window, 'showDirectoryPicker')) {
      try {
        debugPrint("[Web] Attempting 'showDirectoryPicker' (Write Access)...");

        final opts = js_util.newObject();
        js_util.setProperty(opts, 'mode', 'readwrite');

        final promise = js_util.callMethod(html.window, 'showDirectoryPicker', [opts]);
        final dirHandle = await js_util.promiseToFuture(promise);

        final rootName = _sanitizeFsaName(js_util.getProperty(dirHandle, 'name') as String);
        debugPrint("[Web] Got handle for folder: $rootName");

        // If this root was already opened, clear its stale children so they reload fresh.
        _clearSubtree('/$rootName');

        _rootHandles['/$rootName'] = dirHandle;

        // Add the root folder to top-level listing (if not already there).
        if (!_virtualTree['/']!.any((e) => e.path == '/$rootName')) {
          _virtualTree['/']!.add(Directory('/$rootName'));
        }

        // Load only the immediate children (lazy — no deep recursion).
        await _loadDirectChildren(dirHandle, '/$rootName');

        currentPath = '/$rootName';
        return currentPath;
      } catch (e) {
        _log.warn('operation failed', e);
        if (e.toString().contains('AbortError') || e.toString().contains('user aborted')) {
          debugPrint("[Web] User cancelled directory picker.");
          return null;
        }
        debugPrint("[Web] showDirectoryPicker failed: $e. Falling back to input.");
      }
    }

    // 3. Legacy Fallback (Safari/Firefox)
    final completer = Completer<String?>();
    final input = html.FileUploadInputElement();

    input.setAttribute('webkitdirectory', '');
    input.setAttribute('directory', '');
    input.multiple = true;

    input.onChange.listen((e) {
      if (input.files == null || input.files!.isEmpty) {
        completer.complete(null);
        return;
      }

      String rootName = 'root';
      if (input.files!.isNotEmpty) {
        final firstPath = input.files!.first.relativePath ?? input.files!.first.name;
        final cleanFirst = _sanitizeRelPath(firstPath);
        final parts = cleanFirst.split('/');
        if (parts.isNotEmpty) rootName = parts[0];
      }

      debugPrint("[Web] Processing ${input.files!.length} files via legacy input (root: $rootName)...");

      if (!_virtualTree['/']!.any((e) => e.path == '/$rootName')) {
        _virtualTree['/']!.add(Directory('/$rootName'));
      }

      for (final file in input.files!) {
        if (file.name.startsWith('._')) continue;

        final rawRelPath = file.relativePath ?? file.name;
        final relPath = _sanitizeRelPath(rawRelPath);
        final fullPath = '/$relPath';

        _fileRefs[fullPath] = file;
        _populateVirtualTree(relPath);
      }

      final startPath = '/$rootName';
      currentPath = startPath;
      completer.complete(startPath);
    });

    input.click();
    return completer.future;
  }

  static String _sanitizeRelPath(String raw) {
    String decoded;
    try {
      decoded = Uri.decodeComponent(raw);
    } catch (e) {
      _log.warn('operation failed', e);
      decoded = raw;
    }
    decoded = decoded.replaceAll('\$2F', '/').replaceAll('\$3A', ':');

    if (decoded.contains(':')) {
      decoded = decoded.substring(decoded.indexOf(':') + 1);
    }
    return decoded;
  }

  static String _sanitizeFsaName(String raw) {
    final rel = _sanitizeRelPath(raw);
    final parts = rel.split('/');
    return parts.last.isEmpty ? rel : parts.last;
  }

  /// Stored directory handles for lazy loading subdirectories (FSA API).
  static final Map<String, dynamic> _dirHandles = {};

  /// Given a path like '/FolderA/sub/file.txt', returns the root handle for '/FolderA'.
  static dynamic _findRootHandle(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    return _rootHandles['/${parts.first}'];
  }

  /// Remove cached state for a specific root and all its descendants.
  void _clearSubtree(String rootPath) {
    _virtualTree.removeWhere((k, _) => k == rootPath || k.startsWith('$rootPath/'));
    _fileRefs.removeWhere((k, _) => k.startsWith('$rootPath/') || k == rootPath);
    _dirHandles.removeWhere((k, _) => k == rootPath || k.startsWith('$rootPath/'));
    _rootHandles.remove(rootPath);
  }

  /// Load only the immediate children of a directory handle (no recursion).
  Future<void> _loadDirectChildren(dynamic dirHandle, String absPath) async {
    if (_virtualTree.containsKey(absPath) && _virtualTree[absPath]!.isNotEmpty) {
      return; // Already loaded.
    }
    _virtualTree[absPath] = [];
    _dirHandles[absPath] = dirHandle;

    try {
      final valuesIterator = js_util.callMethod(dirHandle, 'values', []);

      while (true) {
        final nextPromise = js_util.callMethod(valuesIterator, 'next', []);
        final next = await js_util.promiseToFuture(nextPromise);

        if (js_util.getProperty(next, 'done') == true) break;

        final handle = js_util.getProperty(next, 'value');
        final name = _sanitizeFsaName(js_util.getProperty(handle, 'name') as String);
        final kind = js_util.getProperty(handle, 'kind');

        if (name.startsWith('.') || name.startsWith('._')) continue;

        final itemAbsPath = "$absPath/$name";

        if (kind == 'file') {
          _virtualTree[absPath]!.add(File(itemAbsPath));
          final filePromise = js_util.callMethod(handle, 'getFile', []);
          final fileObj = await js_util.promiseToFuture(filePromise);
          _fileRefs[itemAbsPath] = fileObj;
        } else if (kind == 'directory') {
          _virtualTree[absPath]!.add(Directory(itemAbsPath));
          // Store handle for lazy loading when user navigates into it.
          _dirHandles[itemAbsPath] = handle;
        }
      }
    } catch (e) {
      debugPrint("[Web] Error loading children of $absPath: $e");
    }
  }

  void _populateVirtualTree(String relPath) {
    final parts = relPath.split('/');
    String parentPath = '/';

    for (int i = 0; i < parts.length; i++) {
      final partName = parts[i];
      final isFile = (i == parts.length - 1);
      final currentItemPath = parentPath == '/' ? '/$partName' : '$parentPath/$partName';

      if (!_virtualTree.containsKey(parentPath)) {
        _virtualTree[parentPath] = [];
      }

      final exists = _virtualTree[parentPath]!.any((e) => e.path == currentItemPath);

      if (!exists) {
        if (isFile) {
          _virtualTree[parentPath]!.add(File(currentItemPath));
        } else {
          _virtualTree[parentPath]!.add(Directory(currentItemPath));
        }
      }
      parentPath = currentItemPath;
    }
  }

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    _log.debug('listDirectory: $path (tree=${_virtualTree.containsKey(path)}, handle=${_dirHandles.containsKey(path)})');
    String lookup = path;
    if (lookup.length > 1 && lookup.endsWith('/')) {
      lookup = lookup.substring(0, lookup.length - 1);
    }

    // Lazy-load subdirectory contents from FSA handle if not yet loaded.
    if ((!_virtualTree.containsKey(lookup) || _virtualTree[lookup]!.isEmpty) &&
        _dirHandles.containsKey(lookup)) {
      await _loadDirectChildren(_dirHandles[lookup], lookup);
    }

    return _virtualTree[lookup] ?? [];
  }

  @override
  Future<bool> hasAccessToPath(String path) async {
    if (path == '/') return true;

    String lookup = path;
    if (lookup.length > 1 && lookup.endsWith('/')) {
      lookup = lookup.substring(0, lookup.length - 1);
    }
    return _virtualTree.containsKey(lookup) || _fileRefs.containsKey(lookup) || _dirHandles.containsKey(lookup);
  }

  @override
  Future<String> getSafeFallbackDirectory() async => '/';

  @override
  Object? getWebFileRef(String path) => _fileRefs[path];

  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async {
    _log.debug('readFile: $path (refs=${_fileRefs.containsKey(path)}, handles=${_dirHandles.length})');
    // Try direct lookup first.
    var fileRef = _fileRefs[path];

    // Try with/without leading slash variations.
    if (fileRef == null && path.startsWith('/')) {
      fileRef = _fileRefs[path.substring(1)];
    }
    if (fileRef == null && !path.startsWith('/')) {
      fileRef = _fileRefs['/$path'];
    }

    // Try FSA handle: navigate to the file through parent directory handles.
    final rootHandle = _findRootHandle(path);
    if (fileRef == null && rootHandle != null) {
      try {
        final parts = path.split('/').where((s) => s.isNotEmpty).toList();
        if (parts.length >= 2) {
          // Navigate through directory handles to reach the file.
          dynamic current = rootHandle;
          // Skip the root folder name (first segment matches the root handle).
          for (var i = 1; i < parts.length - 1; i++) {
            final dirHandle = _dirHandles['/${parts.sublist(0, i + 1).join('/')}'];
            if (dirHandle != null) {
              current = dirHandle;
            } else {
              final opts = js_util.newObject();
              final promise = js_util.callMethod(current, 'getDirectoryHandle', [parts[i], opts]);
              current = await js_util.promiseToFuture(promise);
            }
          }
          final fileName = parts.last;
          final fhPromise = js_util.callMethod(current, 'getFileHandle', [fileName]);
          final fh = await js_util.promiseToFuture(fhPromise);
          final fPromise = js_util.callMethod(fh, 'getFile', []);
          fileRef = await js_util.promiseToFuture(fPromise);
          _fileRefs[path] = fileRef!;
        }
      } catch (e) {
        _log.debug('FSA file lookup failed for $path: $e');
      }
    }

    if (fileRef == null) throw Exception('File ref not found: $path');

    final reader = html.FileReader();
    reader.readAsArrayBuffer(fileRef);
    await reader.onLoad.first;
    return reader.result as Uint8List;
  }

  @override
  Future<void> refresh() async {
    if (_rootHandles.isNotEmpty) {
      _log.debug('Refreshing current directory from handle...');
      // Only reload the current path (not the entire tree).
      final lookup = currentPath.endsWith('/') && currentPath.length > 1
          ? currentPath.substring(0, currentPath.length - 1)
          : currentPath;
      // Clear cached children for current path so they reload.
      _virtualTree.remove(lookup);
      if (_dirHandles.containsKey(lookup)) {
        await _loadDirectChildren(_dirHandles[lookup], lookup);
      } else {
        final rootHandle = _findRootHandle(lookup);
        if (rootHandle != null) {
          await _loadDirectChildren(rootHandle, lookup);
        }
      }
      _log.debug('Refresh complete.');
    }
  }

  @override
  Future<void> deleteEntry(String path, bool isFolder) async {
    _log.debug('deleteEntry: $path isFolder=$isFolder');
    final dirPath = p.dirname(path);
    final name = p.basename(path);

    // Try FSA removeEntry on the parent directory handle.
    final parentHandle = _dirHandles[dirPath];
    if (parentHandle != null) {
      try {
        final opts = js_util.newObject();
        if (isFolder) js_util.setProperty(opts, 'recursive', true);
        final promise = js_util.callMethod(parentHandle, 'removeEntry', [name, opts]);
        await js_util.promiseToFuture(promise);
      } catch (e) {
        _log.debug('FSA removeEntry failed: $e');
        throw Exception('Delete failed: $e');
      }
    }

    // Clean up virtual tree.
    _fileRefs.remove(path);
    _virtualTree[dirPath]?.removeWhere((e) => e.path == path);
    _virtualTree.remove(path);
    _dirHandles.remove(path);
  }

  @override
  Future<void> saveFile(String path, Uint8List data) async {
    _log.debug('saveFile: $path (${data.length} bytes)');
    final rootHandle = _findRootHandle(path);
    if (rootHandle != null) {
      try {
        _log.debug('Attempting write via directory handle navigation...');

        final permState = await _verifyPermission(rootHandle, 'readwrite');
        if (!permState) {
          _log.debug('Permission denied/dismissed. Falling back.');
        } else {
          // Navigate to the parent directory of the target file.
          final parts = path.split('/').where((s) => s.isNotEmpty).toList();
          dynamic current = rootHandle;

          // Walk from segment 1 (skip root folder name) to second-to-last (parent dir).
          for (var i = 1; i < parts.length - 1; i++) {
            final dirPath = '/${parts.sublist(0, i + 1).join('/')}';
            final cachedHandle = _dirHandles[dirPath];
            if (cachedHandle != null) {
              current = cachedHandle;
            } else {
              final opts = js_util.newObject();
              js_util.setProperty(opts, 'create', true);
              final promise = js_util.callMethod(current, 'getDirectoryHandle', [parts[i], opts]);
              current = await js_util.promiseToFuture(promise);
              _dirHandles[dirPath] = current;
            }
          }

          final fileName = parts.last;
          final createOpts = js_util.newObject();
          js_util.setProperty(createOpts, 'create', true);

          final fileHandlePromise = js_util.callMethod(current, 'getFileHandle', [fileName, createOpts]);
          final fileHandle = await js_util.promiseToFuture(fileHandlePromise);

          final writablePromise = js_util.callMethod(fileHandle, 'createWritable', []);
          final writable = await js_util.promiseToFuture(writablePromise);

          final writePromise = js_util.callMethod(writable, 'write', [data]);
          await js_util.promiseToFuture(writePromise);

          final closePromise = js_util.callMethod(writable, 'close', []);
          await js_util.promiseToFuture(closePromise);

          _log.debug('Successfully wrote to $path');

          final fileObjPromise = js_util.callMethod(fileHandle, 'getFile', []);
          final fileObj = await js_util.promiseToFuture(fileObjPromise);

          final dirPath = p.dirname(path);
          _fileRefs[path] = fileObj;

          if (!_virtualTree.containsKey(dirPath)) {
            _virtualTree[dirPath] = [];
          }
          if (_virtualTree[dirPath]!.where((e) => e.path == path).isEmpty) {
            _virtualTree[dirPath]!.add(File(path));
          }

          return;
        }
      } catch (e) {
        _log.debug('Direct write failed ($e). Falling back.');
      }
    }

    _triggerBrowserDownload(path, data);
  }

  Future<bool> _verifyPermission(dynamic handle, String mode) async {
    try {
      final opts = js_util.newObject();
      js_util.setProperty(opts, 'mode', mode);

      final queryPromise = js_util.callMethod(handle, 'queryPermission', [opts]);
      final state = await js_util.promiseToFuture(queryPromise);

      if (state == 'granted') {
        return true;
      }

      _log.debug('Permission is "$state", querying user...');
      final reqPromise = js_util.callMethod(handle, 'requestPermission', [opts]);
      final newState = await js_util.promiseToFuture(reqPromise);

      return newState == 'granted';
    } catch (e) {
      _log.debug('Permission verification error: $e');
      return false;
    }
  }

  void _triggerBrowserDownload(String path, Uint8List data) {
    _log.debug('Triggering browser download for $path');
    final fileName = p.basename(path);
    final blob = html.Blob([data]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute("download", fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Future<String> getInitialPath() async => '/';
}
