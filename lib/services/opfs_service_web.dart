// lib/services/opfs_service_web.dart
//
// Web implementation of OpfsService using navigator.storage.getDirectory().

import 'dart:async';
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;
import 'filen_web_stub.dart' if (dart.library.js_util) 'dart:js_util' as js;

import 'log_service.dart';
import 'opfs_service.dart';

OpfsService createOpfsService() => _WebOpfsService();

class _WebOpfsService implements OpfsService {
  static const _log = Log('OpfsService');

  // Root OPFS directory handle (FileSystemDirectoryHandle).
  dynamic _root;

  @override
  bool get isSupported {
    try {
      final storage = js.getProperty(html.window.navigator, 'storage');
      return storage != null && js.hasProperty(storage, 'getDirectory');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> initialize() async {
    if (!isSupported) {
      _log.warn('OPFS not supported by this browser');
      return;
    }
    try {
      final storage = js.getProperty(html.window.navigator, 'storage');
      final promise = js.callMethod(storage, 'getDirectory', []);
      _root = await js.promiseToFuture(promise);
      _log.info('OPFS root directory handle obtained');
    } catch (e, st) {
      _log.error('OPFS initialize failed', e, st);
    }
  }

  @override
  Future<void> writeFile(String relativePath, Uint8List data) async {
    _requireInitialized();
    try {
      final fileHandle = await _resolveFileHandle(relativePath, create: true);
      final writablePromise = js.callMethod(fileHandle, 'createWritable', []);
      final writable = await js.promiseToFuture(writablePromise);

      final writePromise = js.callMethod(writable, 'write', [data]);
      await js.promiseToFuture(writePromise);

      final closePromise = js.callMethod(writable, 'close', []);
      await js.promiseToFuture(closePromise);

      _log.debug('OPFS write', {'path': relativePath, 'bytes': data.length});
    } catch (e, st) {
      _log.error('OPFS writeFile failed', e, st);
      rethrow;
    }
  }

  @override
  Future<Uint8List?> readFile(String relativePath) async {
    _requireInitialized();
    try {
      final fileHandle = await _resolveFileHandle(relativePath, create: false);
      if (fileHandle == null) return null;

      final filePromise = js.callMethod(fileHandle, 'getFile', []);
      final file = await js.promiseToFuture(filePromise);

      final reader = html.FileReader();
      reader.readAsArrayBuffer(file as html.Blob);
      await reader.onLoad.first;

      final bytes = reader.result as Uint8List;
      _log.debug('OPFS read', {'path': relativePath, 'bytes': bytes.length});
      return bytes;
    } catch (e) {
      if (_isNotFound(e)) return null;
      _log.error('OPFS readFile failed for $relativePath', e);
      return null;
    }
  }

  @override
  Future<void> deleteFile(String relativePath) async {
    _requireInitialized();
    try {
      final parts = _splitPath(relativePath);
      final dirHandle = await _resolveDir(parts.sublist(0, parts.length - 1),
          create: false);
      if (dirHandle == null) return;

      final removeOpts = js.newObject();
      js.setProperty(removeOpts, 'recursive', false);
      final promise = js.callMethod(
          dirHandle, 'removeEntry', [parts.last, removeOpts]);
      await js.promiseToFuture(promise);
      _log.debug('OPFS deleted', {'path': relativePath});
    } catch (e) {
      if (_isNotFound(e)) return;
      _log.error('OPFS deleteFile failed for $relativePath', e);
    }
  }

  @override
  Future<bool> exists(String relativePath) async {
    _requireInitialized();
    try {
      final handle = await _resolveFileHandle(relativePath, create: false);
      return handle != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> clearAll() async {
    _requireInitialized();
    try {
      // Enumerate entries at root and delete each one.
      final valuesIter = js.callMethod(_root, 'values', []);
      while (true) {
        final nextPromise = js.callMethod(valuesIter, 'next', []);
        final next = await js.promiseToFuture(nextPromise);
        if (js.getProperty(next, 'done') == true) break;
        final handle = js.getProperty(next, 'value');
        final name = js.getProperty(handle, 'name') as String;
        final opts = js.newObject();
        js.setProperty(opts, 'recursive', true);
        final removePromise = js.callMethod(_root, 'removeEntry', [name, opts]);
        await js.promiseToFuture(removePromise);
      }
      _log.info('OPFS cache cleared');
    } catch (e, st) {
      _log.error('OPFS clearAll failed', e, st);
    }
  }

  // ---- Helpers ----------------------------------------------------------

  void _requireInitialized() {
    if (_root == null) {
      throw StateError(
          'OpfsService not initialized — call initialize() first');
    }
  }

  List<String> _splitPath(String relativePath) {
    return relativePath
        .split('/')
        .where((p) => p.isNotEmpty)
        .toList();
  }

  /// Resolve or optionally create intermediate directories.
  Future<dynamic> _resolveDir(List<String> parts,
      {required bool create}) async {
    dynamic current = _root;
    for (final part in parts) {
      final opts = js.newObject();
      js.setProperty(opts, 'create', create);
      try {
        final promise =
            js.callMethod(current, 'getDirectoryHandle', [part, opts]);
        current = await js.promiseToFuture(promise);
      } catch (e) {
        if (_isNotFound(e)) return null;
        rethrow;
      }
    }
    return current;
  }

  /// Resolve the file handle for [relativePath].
  Future<dynamic> _resolveFileHandle(String relativePath,
      {required bool create}) async {
    final parts = _splitPath(relativePath);
    if (parts.isEmpty) return null;

    final dirHandle =
        await _resolveDir(parts.sublist(0, parts.length - 1), create: create);
    if (dirHandle == null) return null;

    final opts = js.newObject();
    js.setProperty(opts, 'create', create);

    try {
      final promise =
          js.callMethod(dirHandle, 'getFileHandle', [parts.last, opts]);
      return await js.promiseToFuture(promise);
    } catch (e) {
      if (_isNotFound(e)) return null;
      rethrow;
    }
  }

  bool _isNotFound(Object e) {
    final s = e.toString();
    return s.contains('NotFoundError') || s.contains('not found');
  }
}
