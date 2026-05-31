// lib/services/file_system_access_service_web.dart
//
// Web implementation of FileSystemAccessService using the File System
// Access API (showOpenFilePicker / showSaveFilePicker / showDirectoryPicker)
// and IndexedDB for handle persistence.

import 'dart:async';
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;
import 'filen_web_stub.dart' if (dart.library.js_util) 'dart:js_util' as js;

import 'log_service.dart';
import 'file_system_access_service.dart';

FileSystemAccessService createFileSystemAccessService() =>
    _WebFileSystemAccessService();

// IndexedDB store name used for handle persistence.
const _kDbName = 'crisp_cloud_fsa';
const _kStoreName = 'handles';
const _kDbVersion = 1;

class _WebFileSystemAccessService implements FileSystemAccessService {
  static final _log = Log('FileSystemAccessService');

  @override
  bool get isSupported =>
      js.hasProperty(html.window, 'showOpenFilePicker') &&
      js.hasProperty(html.window, 'showDirectoryPicker');

  // ---- Open file picker -------------------------------------------------

  @override
  Future<FsaFileResult?> openFilePicker({List<String>? acceptedTypes}) async {
    if (!isSupported) {
      _log.warn('showOpenFilePicker not supported by this browser');
      return null;
    }
    try {
      final opts = js.newObject();
      js.setProperty(opts, 'multiple', false);

      if (acceptedTypes != null && acceptedTypes.isNotEmpty) {
        // Build a single accept entry for all provided MIME types.
        final acceptMap = js.newObject();
        final typesArray = js.jsify(acceptedTypes);
        js.setProperty(acceptMap, 'application/octet-stream', typesArray);
        final acceptEntry = js.newObject();
        js.setProperty(acceptEntry, 'accept', acceptMap);
        js.setProperty(opts, 'types', js.jsify([acceptEntry]));
      }

      final promise = js.callMethod(html.window, 'showOpenFilePicker', [opts]);
      final handles = await js.promiseToFuture(promise);

      // The API returns an array; we requested single selection.
      final handle = js.callMethod(handles, 'at', [0]);
      if (handle == null) return null;

      final filePromise = js.callMethod(handle, 'getFile', []);
      final file = await js.promiseToFuture(filePromise);

      final reader = html.FileReader();
      reader.readAsArrayBuffer(file as html.Blob);
      await reader.onLoad.first;

      final bytes = reader.result as Uint8List;
      final name = js.getProperty(file, 'name') as String;
      _log.info('File opened via FSA API', {'name': name, 'bytes': bytes.length});
      return FsaFileResult(name: name, bytes: bytes);
    } catch (e) {
      if (_isAbort(e)) return null;
      _log.error('openFilePicker failed', e);
      return null;
    }
  }

  // ---- Save file picker -------------------------------------------------

  @override
  Future<String?> saveFilePicker({
    required Uint8List data,
    required String suggestedName,
    List<String>? acceptedTypes,
  }) async {
    if (!js.hasProperty(html.window, 'showSaveFilePicker')) {
      _log.warn('showSaveFilePicker not supported — triggering download');
      _triggerDownload(data, suggestedName);
      return suggestedName;
    }
    try {
      final opts = js.newObject();
      js.setProperty(opts, 'suggestedName', suggestedName);

      final promise = js.callMethod(html.window, 'showSaveFilePicker', [opts]);
      final fileHandle = await js.promiseToFuture(promise);

      final writablePromise =
          js.callMethod(fileHandle, 'createWritable', []);
      final writable = await js.promiseToFuture(writablePromise);

      final writePromise = js.callMethod(writable, 'write', [data]);
      await js.promiseToFuture(writePromise);

      final closePromise = js.callMethod(writable, 'close', []);
      await js.promiseToFuture(closePromise);

      final name = js.getProperty(fileHandle, 'name') as String;
      _log.info('File saved via FSA API', {'name': name});
      return name;
    } catch (e) {
      if (_isAbort(e)) return null;
      _log.error('saveFilePicker failed', e);
      return null;
    }
  }

  // ---- Directory picker -------------------------------------------------

  @override
  Future<Object?> openDirectoryPicker() async {
    if (!isSupported) {
      _log.warn('showDirectoryPicker not supported');
      return null;
    }
    try {
      final opts = js.newObject();
      js.setProperty(opts, 'mode', 'readwrite');

      final promise =
          js.callMethod(html.window, 'showDirectoryPicker', [opts]);
      final handle = await js.promiseToFuture(promise);
      final name = js.getProperty(handle, 'name') as String;
      _log.info('Directory selected via FSA API', {'name': name});
      return handle;
    } catch (e) {
      if (_isAbort(e)) return null;
      _log.error('openDirectoryPicker failed', e);
      return null;
    }
  }

  // ---- IndexedDB handle persistence ------------------------------------

  @override
  Future<void> persistHandle(String key, Object handle) async {
    try {
      final db = await _openDb();
      final txn = db.transaction(_kStoreName, 'readwrite');
      final store = txn.objectStore(_kStoreName);
      store.put(handle, key);
      await txn.completed;
      _log.debug('Handle persisted', {'key': key});
    } catch (e, st) {
      _log.error('persistHandle failed', e, st);
    }
  }

  @override
  Future<Object?> getPersistedHandle(String key) async {
    try {
      final db = await _openDb();
      final txn = db.transaction(_kStoreName, 'readonly');
      final store = txn.objectStore(_kStoreName);
      final result = await store.getObject(key);
      await txn.completed;
      if (result != null) {
        _log.debug('Handle retrieved from IDB', {'key': key});
      }
      return result;
    } catch (e, st) {
      _log.error('getPersistedHandle failed', e, st);
      return null;
    }
  }

  @override
  Future<void> removePersistedHandle(String key) async {
    try {
      final db = await _openDb();
      final txn = db.transaction(_kStoreName, 'readwrite');
      final store = txn.objectStore(_kStoreName);
      store.delete(key);
      await txn.completed;
      _log.debug('Handle removed from IDB', {'key': key});
    } catch (e, st) {
      _log.error('removePersistedHandle failed', e, st);
    }
  }

  // ---- Helpers ----------------------------------------------------------

  /// Opens the IndexedDB database. Returns a dynamic handle because
  /// universal_html's IDB types are stubs on the VM target.
  Future<dynamic> _openDb() async {
    // On web, html.window.indexedDB is the real IDBFactory.
    // We use dynamic to avoid type errors on the VM analyzer.
    final idbFactory = html.window.indexedDB;
    if (idbFactory == null) {
      throw Exception('IndexedDB not available');
    }
    final request = idbFactory.open(_kDbName, version: _kDbVersion);

    final completer = Completer<dynamic>();

    request.onUpgradeNeeded.listen((event) {
      final db = (event.target as dynamic).result;
      if (!(db.objectStoreNames as List).contains(_kStoreName)) {
        db.createObjectStore(_kStoreName);
      }
    });

    request.onSuccess.listen((event) {
      completer.complete((event.target as dynamic).result);
    });

    request.onError.listen((event) {
      completer.completeError(Exception('IndexedDB open failed'));
    });

    return completer.future;
  }

  bool _isAbort(Object e) {
    final s = e.toString();
    return s.contains('AbortError') || s.contains('user aborted');
  }

  void _triggerDownload(Uint8List data, String fileName) {
    final blob = html.Blob([data]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}
